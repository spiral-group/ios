//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: concrete `AgentPlatformServiceProtocol` impl
// that wraps the swift-openapi-generator-produced typed client.
//
// Wiring shape (called once during AppCoordinator boot, after
// UserSession is ready):
//
//   let bridge = MatrixSDKAuthBridge(clientProxy: clientProxy)
//   let client = try AgentPlatformClient(
//       serverURL: AppSettings.agentPlatformBaseURL,
//       authProvider: bridge
//   )
//   let service = AgentPlatformService(client: client)
//
// Then `service` is injected into ViewModels via the standard
// `Parameters` struct pattern. See
// `docs/project/DESIGNS/agent-platform-services.md` for the
// full target shape.
//
// At M2.3 close-out the service surface is intentionally narrow
// (2 endpoints — list personal agents + list pending approvals)
// — enough to wire end-to-end + add the first UI screens. Each
// new screen lands its own protocol-extension method as it ships.

import AgentPlatformClient
import Combine
import Foundation
import OpenAPIRuntime

/// Concrete `AgentPlatformServiceProtocol` implementation.
///
/// Holds a strong reference to `AgentPlatformClient` (which
/// holds the URLSession transport + AuthMiddleware). One
/// instance per UserSession; recreate on logout / session swap.
///
/// ### Stale-token resilience
///
/// MAS access tokens have a fixed TTL (5 min by default). The
/// underlying matrix-rust-sdk performs background refreshes on
/// its own 401 responses and writes the new token back to the
/// shared keychain, but our REST client sits outside that loop —
/// `MatrixSDKAuthBridge.currentAccessToken()` reads whatever the
/// keychain contains *at request time*.
///
/// During session boot the keychain may still hold the about-to-
/// expire token until the SDK's first sync round-trip triggers a
/// refresh. Any REST call fired in that window (e.g. the
/// AppCoordinator smoke) sees a 401 even though the credentials
/// will be valid ~100-200 ms later.
///
/// The service therefore wraps every endpoint in
/// `withUnauthorizedRetry`: on the first 401 it sleeps briefly
/// (long enough for the SDK to land its refresh) and replays the
/// call once. Persistent 401 still surfaces as
/// `AgentPlatformError.unauthorized` to the caller.
@MainActor
final class AgentPlatformService: AgentPlatformServiceProtocol {
    let client: AgentPlatformClient

    /// Single retry window for stale-access-token races. 700 ms
    /// is comfortably longer than the observed matrix-rust-sdk
    /// refresh latency (~100-300 ms on Wi-Fi) but short enough
    /// that genuine permission failures still surface within
    /// human-perceptible time.
    nonisolated static let unauthorizedRetryDelay: Duration = .milliseconds(700)

    // AGENT-PLATFORM (decision 98)
    private let ownerBlocksResyncSubject = PassthroughSubject<Void, Never>()
    var ownerBlocksResyncPublisher: AnyPublisher<Void, Never> {
        ownerBlocksResyncSubject.eraseToAnyPublisher()
    }

    // AGENT-PLATFORM (decision 136)
    let personalAssistantSightings: PersonalAssistantSightings

    init(client: AgentPlatformClient) {
        self.client = client
        personalAssistantSightings = PersonalAssistantSightings()
    }

    /// The rows the owner's blocks live in were dropped or created.
    func ownerBlocksNeedResync() {
        ownerBlocksResyncSubject.send()
    }

    // MARK: - Personal agents

    func listMyPersonalAgents() async -> Result<MyPersonalAgentsView, AgentPlatformError> {
        // Brief 0038: GET /me/personal-agents is gone — walk the canonical
        // surface: directory (carries provisioning_status) -> the solo
        // space's detail -> its personal_assistant cards.
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<MyPersonalAgentsView, AgentPlatformError> in
            let dirResponse = try await client.underlying.listMyAgentSpaces(.init())
            let directory: Components.Schemas.ListAgentSpacesResponse
            switch dirResponse {
            case .ok(let ok):
                directory = try ok.body.json
            case .unauthorized:
                return .failure(.unauthorized)
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }

            let status = MyPersonalAgentsView.ProvisioningStatus(rawValue: directory.provisioningStatus) ?? .idle
            guard let solo = directory.spaces.first(where: { $0.kind == "solo" }) else {
                // Personal space not reconciled yet — same shape the old
                // endpoint answered pre-reconcile.
                return .success(.init(agents: [], provisioningStatus: status))
            }

            let detailResponse = try await client.underlying.fetchMyAgentSpace(.init(path: .init(orgId: solo.orgId)))
            switch detailResponse {
            case .ok(let ok):
                let body = try ok.body.json
                let agents = body.agents
                    .filter { $0.kind == "personal_assistant" }
                    .map {
                        PersonalAgentSummary(id: $0.agentId,
                                             matrixUserID: $0.matrixUserId,
                                             displayName: $0.displayName,
                                             avatarMXC: $0.avatarMxc,
                                             visibility: $0.visibility,
                                             lifecycleState: $0.lifecycleState)
                    }
                return .success(.init(agents: agents, provisioningStatus: status))
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden:
                return .failure(.forbidden)
            case .notFound:
                return .failure(.notFound)
            case .badRequest:
                return .failure(.validation(detail: "bad request"))
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
        if case .success(let view) = result {
            personalAssistantSeen(view.agents.first?.id)
        }
        return result
    }

    // MARK: - Notifications hub (Brief 0041 D3, ADR-0054)

    func fetchNotifications(activityCursor: String?,
                            limit: Int) async -> Result<NotificationsSnapshot, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.getNotifications(.init(query: .init(limit: Int64(max(1, min(limit, 100))),
                                                                                           cursor: activityCursor)))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                return .success(Self.mapNotifications(body))
            case .badRequest(let bad):
                let detail = (try? bad.body.applicationProblemJson.detail) ?? "bad request"
                return .failure(.validation(detail: detail))
            case .unauthorized:
                return .failure(.unauthorized)
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }

    func dismissVisitorMessage(id: String) async -> Result<Void, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            switch try await client.underlying.dismissVisitorMessage(.init(path: .init(id: id))) {
            case .noContent:
                return .success(())
            case .badRequest(let bad):
                return .failure(.validation(detail: (try? bad.body.applicationProblemJson.detail) ?? "id"))
            case .unauthorized:
                return .failure(.unauthorized)
            case .notFound:
                return .failure(.notFound)
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }

    func registerPushDevice(pushkey: String, appID: String) async -> Result<Void, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.registerPushDevice(.init(body: .json(.init(appId: appID,
                                                                                                  pushkey: pushkey))))
            switch response {
            case .noContent:
                return .success(())
            case .badRequest(let bad):
                let detail = (try? bad.body.applicationProblemJson.detail) ?? "bad request"
                return .failure(.validation(detail: detail))
            case .unauthorized:
                return .failure(.unauthorized)
            case .unprocessableContent:
                return .failure(.validation(detail: "unprocessable"))
            case .unsupportedMediaType:
                return .failure(.validation(detail: "unsupported media type"))
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }

    func markNotificationsSeen() async -> Result<Date, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            // Omit `last_seen_at` — the server clock is the marker
            // (avoids client-clock skew rewinding the badge; the
            // upsert is monotonic server-side anyway).
            let response = try await client.underlying.putLastSeen(.init(body: .json(.init(lastSeenAt: nil))))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                return .success(body.lastSeenAt)
            case .unauthorized:
                return .failure(.unauthorized)
            case .badRequest:
                return .failure(.validation(detail: "bad request"))
            case .unprocessableContent:
                return .failure(.validation(detail: "unprocessable"))
            case .unsupportedMediaType:
                return .failure(.validation(detail: "unsupported media type"))
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }

    private nonisolated static func mapNotifications(_ body: Components.Schemas.NotificationsResponse) -> NotificationsSnapshot {
        let approvals = body.needsAction.approvals.map {
            NeedsActionItem.approval(ApprovalSummary(id: $0.id,
                                                     agentID: $0.agentId,
                                                     draftBody: $0.draftBody,
                                                     targetRoomID: $0.targetRoomId,
                                                     createdAt: $0.createdAt,
                                                     counterpartMXID: mapContext($0.contextSnapshot,
                                                                                 draftBody: $0.draftBody,
                                                                                 targetRoomID: $0.targetRoomId).counterpartMXID))
        }
        let verifications = body.needsAction.verifications.compactMap(Self.mapVerificationSummary).map {
            NeedsActionItem.verification($0)
        }
        // Interleave the two families newest-first — the wire keeps
        // them separate (each family already has a wire type), the
        // pinned section renders one chronological list.
        let needsAction = (approvals + verifications)
            .sorted { $0.createdAt > $1.createdAt }
        return NotificationsSnapshot(needsAction: needsAction,
                                     activity: body.activity.map(Self.mapActivityEntry),
                                     nextActivityCursor: body.nextActivityCursor,
                                     lastSeenAt: body.lastSeenAt,
                                     unseenCount: Int(body.unseenCount),
                                     visitorMessages: body.visitorMessages.map {
                                         VisitorMessage(id: $0.id,
                                                        kind: .init(serverValue: $0.kind),
                                                        agentID: $0.agentId,
                                                        visitorMXID: $0.visitorMxid,
                                                        roomID: $0.roomId,
                                                        body: $0.body,
                                                        createdAt: $0.createdAt)
                                     })
    }

    func fetchApproval(id: String) async -> Result<ApprovalDetail, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.fetchApproval(.init(path: .init(id: id)))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                guard let detail = Self.mapApprovalDetail(body) else {
                    return .failure(.validation(detail: "approval payload unparseable"))
                }
                return .success(detail)
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden:
                return .failure(.forbidden)
            case .notFound(let notFound):
                return .failure(Self.mapApprovalNotFound(type: (try? notFound.body.applicationProblemJson)?._type))
            case .badRequest:
                return .failure(.validation(detail: "bad request"))
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }

    func decideApproval(id: String, decision: ApprovalDecision) async -> Result<ApprovalDecisionResult, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let requestBody: Components.Schemas.DecideRequest
            switch decision {
            case .approve:
                requestBody = .case1(.init(action: .approve))
            case .reject:
                requestBody = .case2(.init(action: .reject))
            case .edit(let newBody):
                requestBody = .case3(.init(action: .edit, newBody: newBody))
            }
            let response = try await client.underlying.decideHandler(.init(path: .init(id: id),
                                                                           body: .json(requestBody)))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                guard let approval = Self.mapApprovalDetail(body.approval) else {
                    return .failure(.validation(detail: "approval payload unparseable"))
                }
                let delivery = Self.mapDelivery(body.delivery)
                return .success(.init(approval: approval, delivery: delivery))
            case .badRequest(let bad):
                let detail = (try? bad.body.applicationProblemJson.detail) ?? "bad request"
                return .failure(.validation(detail: detail))
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden:
                return .failure(.forbidden)
            case .notFound(let notFound):
                return .failure(Self.mapApprovalNotFound(type: (try? notFound.body.applicationProblemJson)?._type))
            case .conflict(let conflict):
                // Two 409s, told apart by `type`: the platform refused an
                // approve to a person the owner blocked (the card is closed),
                // or the approval was already decided.
                let problem = try? conflict.body.applicationProblemJson
                if problem?._type == AgentPlatformError.targetBlockedTypeURI {
                    return .failure(.targetBlocked)
                }
                if problem?._type == AgentPlatformError.agentPausedTypeURI {
                    return .failure(.agentPaused)
                }
                return .failure(.conflict(detail: problem?.detail ?? "already decided"))
            case .unprocessableContent:
                return .failure(.validation(detail: "unprocessable"))
            case .unsupportedMediaType:
                return .failure(.validation(detail: "unsupported media type"))
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }

    // MARK: - Verifications (S156)

    func listVerificationsForAgent(agentID: String) async -> Result<[VerificationSummary], AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.listForAgent(.init(path: .init(agentId: agentID)))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                let items = body.items.compactMap(Self.mapVerificationSummary)
                return .success(items)
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden:
                return .failure(.forbidden)
            case .notFound:
                return .failure(.notFound)
            case .badRequest:
                return .failure(.validation(detail: "bad request"))
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }

    func fetchVerification(id: String) async -> Result<VerificationDetail, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.fetchDetail(.init(path: .init(id: id)))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                return .success(Self.mapVerificationDetail(body))
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden:
                return .failure(.forbidden)
            case .notFound:
                return .failure(.notFound)
            case .badRequest:
                return .failure(.validation(detail: "bad request"))
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }

    func confirmVerification(id: String) async -> Result<VerificationDetail, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            // The UI gates this call behind a strict-SAS checkbox,
            // so by the time we POST, the owner has acknowledged.
            // The backend rejects `comparison_acknowledged != true`
            // with 422 — we never send anything but `true`.
            let requestBody = Components.Schemas.ConfirmRequest(comparisonAcknowledged: true)
            let response = try await client.underlying.confirmHandler(.init(path: .init(id: id),
                                                                            body: .json(requestBody)))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                return .success(Self.mapVerificationDetail(body))
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden:
                return .failure(.forbidden)
            case .notFound:
                return .failure(.notFound)
            case .conflict(let conflict):
                // 409 = the matrix-sdk-crypto OlmMachine no longer
                // tracks this VerificationRequest (orchestrator
                // restart, remote cancelled, deadline elapsed).
                // The DB row gets marked cancelled silently on the
                // server; the UI surfaces a "request expired"
                // message so the owner can move on.
                let detail = (try? conflict.body.applicationProblemJson.detail) ?? "verification request no longer active"
                return .failure(.conflict(detail: detail))
            case .unprocessableContent(let unprocessable):
                // 422 = wrong state (not pending_owner — UI
                // shouldn't have shown the Confirm button) or SAS
                // not yet ready (race: emojis arrived after the
                // user opened the screen but cleared before tap).
                let detail = (try? unprocessable.body.applicationProblemJson.detail) ?? "verification not actionable"
                return .failure(.validation(detail: detail))
            case .badRequest:
                return .failure(.validation(detail: "bad request"))
            case .unsupportedMediaType:
                return .failure(.validation(detail: "unsupported media type"))
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }

    func rejectVerification(id: String) async -> Result<VerificationDetail, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.rejectHandler(.init(path: .init(id: id)))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                return .success(Self.mapVerificationDetail(body))
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden:
                return .failure(.forbidden)
            case .notFound:
                return .failure(.notFound)
            case .unprocessableContent(let unprocessable):
                let detail = (try? unprocessable.body.applicationProblemJson.detail) ?? "verification not actionable"
                return .failure(.validation(detail: detail))
            case .badRequest:
                return .failure(.validation(detail: "bad request"))
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }

    // MARK: - Agent activity (Phase R3.5 E1)

    func listAgentActivity(agentID: String,
                           filter: ActionOutcomeFilter,
                           cursor: String?,
                           limit: Int) async -> Result<AgentActivityPage, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            // Server clamps `[1, 100]` but mirroring the bound
            // here gives a faster failure mode for typo'd callers
            // + lets the generated `Int64` cast safely.
            let clampedLimit = Int64(max(1, min(limit, 100)))
            let response = try await client.underlying.listAgentActivity(.init(path: .init(id: agentID),
                                                                               query: .init(state: filter.wireValue,
                                                                                            limit: clampedLimit,
                                                                                            cursor: cursor)))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                let items = body.items.map(Self.mapActivityEntry)
                return .success(.init(items: items, nextCursor: body.nextCursor))
            case .badRequest(let bad):
                let detail = (try? bad.body.applicationProblemJson.detail) ?? "bad request"
                return .failure(.validation(detail: detail))
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden:
                return .failure(.forbidden)
            case .notFound:
                return .failure(.notFound)
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }

    // MARK: - Outreach queue (S159)

    func enqueueOutreachTargets(agentID: String,
                                mxids: [String]) async -> Result<EnqueueOutreachResult, AgentPlatformError> {
        // Backend hard-caps the batch at 200; iOS clamps here
        // too so a paste of 5000 doesn't get a generic 400
        // back. We only surface the cap; the editor's Save
        // button enforces the upper bound visually too.
        if mxids.isEmpty {
            return .failure(.validation(detail: "at least one MXID required"))
        }
        if mxids.count > 200 {
            return .failure(.validation(detail: "batch size capped at 200"))
        }

        return await withUnauthorizedRetry { [client] in
            let requestBody = Components.Schemas.EnqueueRequest(mxids: mxids)
            let response = try await client.underlying.enqueue(.init(path: .init(id: agentID),
                                                                     body: .json(requestBody)))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                return .success(Self.mapEnqueueResponse(body))
            case .badRequest(let bad):
                let detail = (try? bad.body.applicationProblemJson.detail) ?? "bad request"
                return .failure(.validation(detail: detail))
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden:
                return .failure(.forbidden)
            case .notFound:
                return .failure(.notFound)
            case .conflict(let conflict):
                let detail = (try? conflict.body.applicationProblemJson.detail) ?? "agent behaviour is not Outreach"
                return .failure(.conflict(detail: detail))
            case .unprocessableContent:
                return .failure(.validation(detail: "unprocessable"))
            case .unsupportedMediaType:
                return .failure(.validation(detail: "unsupported media type"))
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }

    func listOutreachQueue(agentID: String,
                           status: OutreachTargetStatus?,
                           limit: Int) async -> Result<[OutreachQueueEntry], AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let clampedLimit = Int64(max(1, min(limit, 500)))
            let response = try await client.underlying.listQueue(.init(path: .init(id: agentID),
                                                                       query: .init(status: status?.wireValue,
                                                                                    limit: clampedLimit)))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                return .success(body.items.map(Self.mapOutreachQueueEntry))
            case .badRequest(let bad):
                let detail = (try? bad.body.applicationProblemJson.detail) ?? "unknown status filter"
                return .failure(.validation(detail: detail))
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden:
                return .failure(.forbidden)
            case .notFound:
                return .failure(.notFound)
            case .conflict(let conflict):
                let detail = (try? conflict.body.applicationProblemJson.detail) ?? "agent behaviour is not Outreach"
                return .failure(.conflict(detail: detail))
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }

    private nonisolated static func mapOutreachQueueEntry(_ wire: Components.Schemas.OutreachQueueEntry) -> OutreachQueueEntry {
        OutreachQueueEntry(id: wire.id,
                           targetMXID: wire.targetMxid,
                           status: OutreachTargetStatus(wire: wire.status),
                           approvalID: wire.approvalId,
                           draftBody: wire.draftBody,
                           errorMessage: wire.errorMessage,
                           createdAt: wire.createdAt,
                           updatedAt: wire.updatedAt)
    }

    private nonisolated static func mapEnqueueResponse(_ wire: Components.Schemas.EnqueueResponse) -> EnqueueOutreachResult {
        EnqueueOutreachResult(items: wire.items.map(mapEnqueueResponseItem),
                              accepted: Int(wire.accepted),
                              rejected: Int(wire.rejected))
    }

    /// Map wire `EnqueueResponseItem` (allOf of a per-MXID
    /// envelope + the discriminated `EnqueueItemOutcome` enum)
    /// into our display DTO. The generated type's `value2`
    /// holds the per-item `target_mxid`; the discriminator
    /// lives on `value1.value1 / value2 / value3`.
    private nonisolated static func mapEnqueueResponseItem(_ wire: Components.Schemas.EnqueueResponseItem) -> EnqueueOutreachItem {
        let mxid = wire.value2.targetMxid
        let outcome: EnqueueOutreachOutcome
        switch wire.value1 {
        case .case1(let queued):
            outcome = .queued(id: queued.id)
        case .case2:
            outcome = .duplicate
        case .case3(let invalid):
            outcome = .invalid(reason: invalid.reason)
        }
        return EnqueueOutreachItem(targetMXID: mxid, outcome: outcome)
    }

    // MARK: - Public user profile (S157)

    func fetchUserProfile(mxid: String) async -> Result<UserProfileView, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.getUserProfile(.init(path: .init(mxid: mxid)))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                return .success(Self.mapUserProfile(body))
            case .unauthorized:
                return .failure(.unauthorized)
            case .notFound:
                return .failure(.notFound)
            case .badRequest:
                return .failure(.validation(detail: "bad request"))
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }

    // MARK: - Invite links (Brief 0073 / ADR-0008)
    
    func fetchMyInvite() async -> Result<MyInvite, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.getMyInvite()
            switch response {
            case .ok(let ok):
                return Self.mapMyInvite(try ok.body.json)
            case .unauthorized:
                return .failure(.unauthorized)
            case .notFound:
                return .failure(.notFound)
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }
    
    func createPhraseReset() async -> Result<URL, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.createPhraseReset()
            switch response {
            case .ok(let ok):
                guard let url = URL(string: try ok.body.json.url) else {
                    return .failure(.validation(detail: "phrase-reset url"))
                }
                return .success(url)
            case .unauthorized:
                return .failure(.unauthorized)
            case .notFound:
                return .failure(.notFound)
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }
    
    func deleteAccount() async -> Result<Void, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            switch try await client.underlying.deleteMe() {
            case .ok:
                return .success(())
            case .unauthorized:
                return .failure(.unauthorized)
            case .notFound:
                return .failure(.notFound)
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .serviceUnavailable:
                return .failure(.serverError(status: 503))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }
    
    func fetchAIConsent() async -> Result<AIConsent, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            switch try await client.underlying.getAiConsent() {
            case .ok(let ok):
                return .success(Self.mapAIConsent(try ok.body.json))
            case .unauthorized:
                return .failure(.unauthorized)
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }
    
    func setAIConsent(granted: Bool) async -> Result<AIConsent, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            switch try await client.underlying.putAiConsent(.init(body: .json(.init(granted: granted)))) {
            case .ok(let ok):
                return .success(Self.mapAIConsent(try ok.body.json))
            case .unauthorized:
                return .failure(.unauthorized)
            case .badRequest:
                return .failure(.validation(detail: "bad request"))
            case .unprocessableContent:
                return .failure(.validation(detail: "unprocessable"))
            case .unsupportedMediaType:
                return .failure(.validation(detail: "unsupported media type"))
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }
    
    private nonisolated static func mapAIConsent(_ wire: Components.Schemas.AiConsentResponse) -> AIConsent {
        AIConsent(isGranted: wire.granted,
                  currentVersion: wire.currentVersion,
                  decidedVersion: wire.decidedVersion)
    }
    
    func fetchMyInviteJoined() async -> Result<[InviteJoinedEntry], AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.listJoined()
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                return .success(body.joined.map { InviteJoinedEntry(userID: $0.userId, joinedAt: $0.joinedAt) })
            case .unauthorized:
                return .failure(.unauthorized)
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }
    
    private nonisolated static func mapMyInvite(_ wire: Components.Schemas.InviteResponse) -> Result<MyInvite, AgentPlatformError> {
        guard let link = SpiralInviteLink(token: wire.token) else {
            MXLog.error("Invite token from the server does not fit the link grammar")
            return .failure(.validation(detail: "invite token"))
        }
        return .success(MyInvite(link: link,
                                 maxUses: Int(wire.maxUses),
                                 used: Int(wire.used),
                                 expiresAt: wire.expiresAt))
    }
    
    /// Map wire `UserProfileResponse` → display DTO.
    private nonisolated static func mapUserProfile(_ wire: Components.Schemas.UserProfileResponse) -> UserProfileView {
        UserProfileView(mxid: wire.mxid,
                        displayName: wire.displayName,
                        publicAgents: wire.publicAgents.map(mapPublicAgentSummary))
    }

    /// Map wire `PublicAgentSummary` → display DTO. Optional
    /// persona fields stay optional — the UI falls back to the
    /// MXID localpart when `displayName` is absent.
    private nonisolated static func mapPublicAgentSummary(_ wire: Components.Schemas.PublicAgentSummary) -> PublicAgentSummary {
        PublicAgentSummary(id: wire.id,
                           matrixUserID: wire.matrixUserId,
                           displayName: wire.displayName,
                           tone: wire.tone,
                           greeting: wire.greeting,
                           visitorGreeting: wire.visitorGreeting,
                           createdAt: wire.createdAt)
    }

    /// Map wire `AgentActivityEntry` → display DTO. Currently
    /// 1:1 — the wire shape was designed to be UI-ready
    /// (Brief 0002 § API contract / AgentActivityEntry). We
    /// still funnel through this helper so a future enrichment
    /// (e.g. local-cache room display name lookup) has a single
    /// site to land in.
    private nonisolated static func mapActivityEntry(_ wire: Components.Schemas.AgentActivityEntry) -> AgentActivityEntry {
        // The generator emits the open-content `input_redacted`
        // as `OpenAPIObjectContainer.value: [String: (any Sendable)?]`.
        // Narrow to `[String: Any]` (dropping the optional inner
        // type) for downstream UI — pretty-printing + lookups by
        // string key are the only operations we run on it.
        let inputDict: [String: Any] = wire.inputRedacted.value.compactMapValues { $0 }
        return AgentActivityEntry(id: wire.id,
                                  agentID: wire.agentId,
                                  roomID: wire.roomId,
                                  capabilityName: wire.capabilityName,
                                  inputRedacted: inputDict,
                                  reasoningSummary: wire.reasoningSummary,
                                  policyDecision: AgentActionPolicyDecision(wire: wire.policyDecision),
                                  policyReason: wire.policyReason,
                                  approvalID: wire.approvalId,
                                  longFlowID: wire.longFlowId,
                                  outcome: AgentActionOutcome(wire: wire.outcome),
                                  outcomeEventID: wire.outcomeEventId,
                                  createdAt: wire.createdAt,
                                  resolvedAt: wire.resolvedAt)
    }

    // MARK: - Mapping helpers

    /// Maps `Components.Schemas.ApprovalResponse` → `ApprovalDetail`.
    /// Returns nil if a required field is missing (shouldn't
    /// happen — the generated type enforces the required set —
    /// but defensive coding here insulates us from a future spec
    /// regression).
    private nonisolated static func mapApprovalDetail(_ body: Components.Schemas.ApprovalResponse) -> ApprovalDetail? {
        ApprovalDetail(id: body.id,
                       agentID: body.agentId,
                       ownerUserID: body.ownerUserId,
                       draftBody: body.draftBody,
                       targetRoomID: body.targetRoomId,
                       state: mapState(body.state),
                       context: mapContext(body.contextSnapshot, draftBody: body.draftBody, targetRoomID: body.targetRoomId),
                       createdAt: body.createdAt,
                       updatedAt: body.updatedAt,
                       expiresAt: body.expiresAt,
                       decidedAt: body.decidedAt,
                       decidedBy: body.decidedBy,
                       escalationReason: body.escalationReason)
    }

    private nonisolated static func mapState(_ state: Components.Schemas.ApprovalStateResponse) -> ApprovalState {
        switch state {
        case .case1(let pending) where pending.status == .pending: return .pending
        case .case2(let approved) where approved.status == .approved: return .approved
        case .case3(let rejected) where rejected.status == .rejected: return .rejected
        case .case4(let edited) where edited.status == .edited: return .edited(newBody: edited.newBody)
        case .case5(let expired) where expired.status == .expired: return .expired
        default:
            // Defensive: if oneOf discrimination misses, treat as
            // pending so the UI can at least render. Real
            // regression would surface as "decide button visible
            // on an already-decided approval", which a manual
            // tester would catch.
            return .pending
        }
    }

    /// Tell the card types apart from the free-form
    /// `context_snapshot`. A personal agent's first contact carries
    /// no `kind`: it is the approval whose snapshot names the
    /// visitor under `visitor_mxid` (the platform's own test,
    /// `worker/reply/consent.rs`). Other cards say `kind`; an
    /// unknown one bubbles up as `.unknown(rawKind:)` so the UI
    /// falls back to the generic card instead of crashing.
    private nonisolated static func mapContext(_ snapshot: OpenAPIRuntime.OpenAPIObjectContainer,
                                               draftBody: String,
                                               targetRoomID: String) -> ApprovalContext {
        let dict = snapshot.value
        guard let kind = dict["kind"] as? String else {
            if let visitor = dict["visitor_mxid"] as? String, !visitor.isEmpty {
                return .personalAgentFirstContact(visitorMXID: visitor)
            }
            return .generic(senderMXID: nonBlank(dict["sender_mxid"]).flatMap { $0.hasPrefix("@") ? $0 : nil })
        }
        switch kind {
        case "cold_outreach":
            // The platform writes the target under `target_mxid`
            // (`domain/services/outbound_open_dm.rs`).
            let target = (dict["target_mxid"] as? String) ?? ""
            let warnings = (dict["warnings"] as? [Any])?.compactMap { $0 as? String } ?? []
            return .coldOutreach(targetMXID: target, warnings: warnings)
        case "block_sender":
            // Without the person it names, the card could not say whom it blocks.
            guard let target = nonBlank(dict["target_mxid"]), target.hasPrefix("@") else {
                return .unknown(rawKind: kind)
            }
            // `draft_body` and `target_room_id` carry the reason and the room too.
            return .blockSender(ApprovalBlockRequest(targetMXID: target,
                                                     roomID: nonBlank(dict["room_id"]) ?? targetRoomID,
                                                     isDirectMessage: dict["room_kind"] as? String == "direct_message",
                                                     reason: nonBlank(dict["reason"]) ?? draftBody,
                                                     userMessage: nonBlank(dict["user_message"])))
        default:
            return .unknown(rawKind: kind)
        }
    }

    private nonisolated static func nonBlank(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    // MARK: - Read-model mapping

    /// `GET /agents/{id}/read-model` and the `PATCH /agents/{id}` answer
    /// share one shape (Brief 0038).
    nonisolated static func mapAgentReadModel(_ body: Components.Schemas.AgentDetailResponse) -> AgentReadModel {
        AgentReadModel(agentID: body.agentId,
                       matrixUserID: body.matrixUserId,
                       displayName: body.displayName,
                       avatarMXC: body.avatarMxc,
                       kind: body.kind,
                       visibility: body.visibility,
                       lifecycleState: body.lifecycleState,
                       organizationID: body.organizationId,
                       roomCount: Int(body.roomCount),
                       activeToolCount: Int(body.activeToolCount),
                       configVersionNumber: Int(body.configVersionNumber),
                       persona: mapPersonaFromReadModel(body),
                       roleBrief: body.roleBrief,
                       // A value this build doesn't know reads as not set (decision 96).
                       voiceLanguage: body.voiceLanguage.flatMap(AgentVoiceLanguage.init(rawValue:)),
                       visitorPolicy: body.persona.flatMap { AgentVisitorPolicy(rawValue: $0.visitorPolicy) },
                       paused: body.paused)
    }

    /// `nil` when the agent kind carries no editable persona (company roles).
    private nonisolated static func mapPersonaFromReadModel(_ body: Components.Schemas.AgentDetailResponse) -> PersonaView? {
        guard let persona = body.persona else { return nil }
        return PersonaView(agentID: body.agentId,
                           ownerDisplayName: persona.ownerDisplayName,
                           tone: persona.tone,
                           greeting: persona.greeting,
                           visitorGreeting: persona.visitorGreeting,
                           toolUseEnabled: persona.toolUseEnabled,
                           model: persona.model,
                           configVersionID: body.configVersionId,
                           versionNumber: Int(body.configVersionNumber))
    }

    // MARK: - Verifications mapping

    /// Map wire `VerificationApprovalResponse` → display
    /// `VerificationSummary`. Returns nil if the row is in a
    /// terminal state that the list never renders (defensive —
    /// backend's `list_pending_for_agent` already filters to
    /// non-terminal, but a forward-compat row from a newer
    /// backend version could leak through and we'd rather skip
    /// silently than crash).
    private nonisolated static func mapVerificationSummary(_ wire: Components.Schemas.VerificationApprovalResponse) -> VerificationSummary? {
        let state = parseVerificationState(wire.state)
        switch state {
        case .confirmed, .cancelled:
            return nil
        default:
            return VerificationSummary(id: wire.id,
                                       requesterUserID: wire.requesterUserId,
                                       requesterDeviceID: wire.requesterDeviceId,
                                       state: state,
                                       createdAt: wire.createdAt,
                                       deadlineAt: wire.deadlineAt)
        }
    }

    /// Map wire `VerificationApprovalResponse` → full
    /// `VerificationDetail`. Never returns nil — even terminal
    /// states (`confirmed`, `cancelled`) are legitimate on detail
    /// open (e.g. the owner taps a row, then the remote side
    /// finalises before the GET completes).
    private nonisolated static func mapVerificationDetail(_ wire: Components.Schemas.VerificationApprovalResponse) -> VerificationDetail {
        let emojis = wire.emojis?.map { VerificationEmoji(symbol: $0.glyph, description: $0.description) }
        return VerificationDetail(id: wire.id,
                                  agentID: wire.agentId,
                                  ownerUserID: wire.ownerUserId,
                                  requesterUserID: wire.requesterUserId,
                                  requesterDeviceID: wire.requesterDeviceId,
                                  state: parseVerificationState(wire.state),
                                  emojis: emojis,
                                  cancelCode: wire.cancelCode,
                                  createdAt: wire.createdAt,
                                  deadlineAt: wire.deadlineAt,
                                  decidedAt: wire.decidedAt,
                                  decidedBy: wire.decidedBy)
    }

    /// Wire-string → typed `AgentVerificationState`. Unknown
    /// strings bubble up as `.unknown(rawValue:)` so the UI
    /// degrades to "no actions available" instead of crashing
    /// on a future backend variant.
    private nonisolated static func parseVerificationState(_ raw: String) -> AgentVerificationState {
        switch raw {
        case "pending_dh_exchange": return .pendingDhExchange
        case "pending_owner": return .pendingOwner
        case "awaiting_remote_done": return .awaitingRemoteDone
        case "confirmed": return .confirmed
        case "cancelled": return .cancelled
        default: return .unknown(rawValue: raw)
        }
    }

    /// The `oneOf` has no discriminator: the generated decoder tries each member in
    /// spec order, so a member the spec lacks fails the whole decide response.
    private nonisolated static func mapDelivery(_ delivery: Components.Schemas.DeliveryResponse) -> ApprovalDeliveryOutcome {
        switch delivery {
        case .case1: return .notSent
        case .case2(let sent): return .sent(eventID: sent.eventId)
        case .case3(let failed): return .sendFailed(reason: failed.reason)
        case .case4(let deferred): return .deferred(deferredKind: deferred.deferredKind)
        case .case5: return .applied
        }
    }

    // MARK: - Unified Tool + Trigger control (Brief 0036 / ADR-0048)

    func fetchRoomTools(roomID: String) async -> Result<RoomToolsView, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.getRoomTools(.init(path: .init(roomId: roomID)))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                return .success(Self.mapRoomTools(body))
            case .unauthorized:
                return .failure(.unauthorized)
            case .badRequest:
                return .failure(.validation(detail: "bad request"))
            case .forbidden:
                return .failure(.forbidden)
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }

    func fetchToolsCatalog(agentID: String,
                           roomID: String) async -> Result<ToolsCatalogView, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.getToolsCatalog(.init(path: .init(id: agentID, roomId: roomID)))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                return .success(Self.mapToolsCatalog(body))
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden:
                return .failure(.forbidden)
            case .badRequest:
                return .failure(.validation(detail: "bad request"))
            case .notFound:
                return .failure(.notFound)
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }

    func armTool(agentID: String,
                 roomID: String,
                 params: ToolParams,
                 trigger: TriggerKind,
                 replacesToolID: String?) async -> Result<ControlSetResultView, RoomToolArmError> {
        let input = Operations.PostTool.Input(path: .init(id: agentID, roomId: roomID),
                                              body: .json(.init(params: params.wireObject,
                                                                replacesToolId: replacesToolID,
                                                                trigger: trigger.wireObject)))
        // The same one-retry-on-401 as `withUnauthorizedRetry`, which is
        // typed to `AgentPlatformError`.
        let first = await armToolOnce(input)
        guard case .failure(.failed(.unauthorized)) = first else { return first }
        try? await Task.sleep(for: Self.unauthorizedRetryDelay)
        return await armToolOnce(input)
    }

    private func armToolOnce(_ input: Operations.PostTool.Input) async -> Result<ControlSetResultView, RoomToolArmError> {
        do {
            return try await Self.mapArmTool(client.underlying.postTool(input))
        } catch {
            return .failure(.failed(.transport(underlying: error)))
        }
    }

    func disableTool(agentID: String,
                     roomID: String,
                     toolID: String) async -> Result<ControlSetResultView, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.deleteTool(.init(path: .init(id: agentID, roomId: roomID, toolId: toolID)))
            return Self.mapControlSet(response)
        }
    }

    // MARK: - Helpers

    /// Runs `operation` once; if it yields `.unauthorized`, waits
    /// `unauthorizedRetryDelay` (giving matrix-rust-sdk's refresh
    /// loop time to land a fresh access token in the keychain)
    /// and replays it. Transport errors during the first attempt
    /// short-circuit immediately — only `unauthorized` is treated
    /// as retriable.
    ///
    /// The operation closure runs on the caller's (main) actor — it lost
    /// its `@Sendable` in the Swift 6.2 migration because the annotation
    /// forced call-site closures onto `@concurrent`, demanding Sendable
    /// DTOs for no benefit: both invocations happen sequentially in this
    /// method and share the same `AgentPlatformClient`.
    func withUnauthorizedRetry<Value>(_ operation: () async throws -> Result<Value, AgentPlatformError>) async -> Result<Value, AgentPlatformError> {
        do {
            let first = try await operation()
            if case .failure(.unauthorized) = first {
                try? await Task.sleep(for: Self.unauthorizedRetryDelay)
                do {
                    return try await operation()
                } catch {
                    return .failure(.transport(underlying: error))
                }
            }
            return first
        } catch {
            return .failure(.transport(underlying: error))
        }
    }

    /// Two 404s on an approval, told apart by `type`: the approval is gone, or
    /// the platform does not serve the route (`/errors/not-found`), which says
    /// nothing about the approval.
    nonisolated static func mapApprovalNotFound(type: String?) -> AgentPlatformError {
        type == AgentPlatformError.approvalNotFoundTypeURI ? .approvalNotFound : .notFound
    }

    nonisolated static func mapUndocumented(_ status: Int) -> AgentPlatformError {
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 409: return .conflict(detail: "HTTP 409")
        case 500...: return .serverError(status: status)
        default: return .serverError(status: status)
        }
    }

    // MARK: - Tool mappers (Brief 0036)

    /// Map any tool SET operation's generated `Output` to a domain result
    /// via the `ControlSetOutputConvertible` witness.
    private nonisolated static func mapControlSet<O: ControlSetOutputConvertible>(_ output: O) -> Result<ControlSetResultView, AgentPlatformError> {
        output.asControlSetResult()
    }

    private nonisolated static func mapArmTool(_ output: Operations.PostTool.Output) -> Result<ControlSetResultView, RoomToolArmError> {
        switch output {
        case .ok(let ok):
            return (try? .success(.init(ok.body.json))) ?? .failure(.failed(.validation(detail: "tool set body unparseable")))
        case .accepted(let accepted):
            return (try? .success(.init(accepted.body.json))) ?? .failure(.failed(.validation(detail: "tool set body unparseable")))
        case .unauthorized:
            return .failure(.failed(.unauthorized))
        case .forbidden:
            return .failure(.failed(.forbidden))
        case .notFound:
            return .failure(.failed(.notFound))
        case .conflict(let conflict):
            return .failure(armRefusal(problem: try? conflict.body.applicationProblemJson, status: 409))
        case .unprocessableContent(let rejection):
            return .failure(armRefusal(problem: try? rejection.body.applicationProblemJson, status: 422))
        case .badRequest:
            return .failure(.failed(.validation(detail: "bad request")))
        case .unsupportedMediaType:
            return .failure(.failed(.validation(detail: "unsupported media type")))
        case .internalServerError:
            return .failure(.failed(.serverError(status: 500)))
        case .undocumented(let status, _):
            return .failure(.failed(mapUndocumented(status)))
        }
    }

    private nonisolated static func armRefusal(problem: Components.Schemas.ProblemDetails?, status: Int) -> RoomToolArmError {
        if problem?._type == RoomToolArmError.replacedGoneTypeURI {
            return .replacedGone
        }
        if let problem, let refusal = RoomToolRefusal(problemType: problem._type, detail: problem.detail) {
            return .refused(refusal)
        }
        let detail = problem?.detail ?? "HTTP \(status)"
        return .failed(status == 409 ? .conflict(detail: detail) : .validation(detail: detail))
    }

    /// Map the `GET /rooms/:room_id/tools` room-wide read into the view
    /// type. Own agents carry full typed params/trigger; the safe slice
    /// leaves them `nil` (Brief 0035 visibility model).
    private nonisolated static func mapRoomTools(_ body: Components.Schemas.RoomToolsResponse) -> RoomToolsView {
        let agents = body.agents.enumerated().map { agentIndex, entry in
            let tools = entry.tools.enumerated().map { toolIndex, tool -> RoomToolView in
                // `params` / `trigger` are elided (JSON `null`) for agents
                // the caller doesn't own — the Brief 0035 safe slice. Treat
                // absent-or-empty identically as "no detail".
                let paramsWire = tool.params?.value ?? [:]
                let triggerWire = tool.trigger?.value ?? [:]
                let params = paramsWire.isEmpty ? nil : ToolParams(wire: paramsWire)
                let trigger = triggerWire.isEmpty ? nil : TriggerKind(wire: triggerWire)
                return RoomToolView(toolID: tool.id,
                                    toolKind: tool.toolKind,
                                    triggerKind: tool.triggerKind,
                                    targetLanguage: tool.targetLanguage,
                                    params: params,
                                    trigger: trigger,
                                    safeSliceSalt: "\(agentIndex).\(toolIndex)")
            }
            return RoomToolAgentEntry(agentID: entry.agentId,
                                      matrixUserID: entry.matrixUserId,
                                      displayName: entry.displayName,
                                      ownerUserID: entry.ownerUserId,
                                      isMine: entry.isMine,
                                      tools: tools)
        }
        return RoomToolsView(roomID: body.roomId, agents: agents)
    }

    /// Map the `GET /tools/catalog` typed schemas into the view type. The
    /// schemas are raw JSON dictionaries a form renderer walks.
    private nonisolated static func mapToolsCatalog(_ body: Components.Schemas.ToolsCatalogResponse) -> ToolsCatalogView {
        ToolsCatalogView(agentID: body.agentId,
                         roomID: body.roomId,
                         paramsSchema: body.paramsSchema.value.mapValues(AnyHashableJSON.init),
                         triggerSchema: body.triggerSchema.value.mapValues(AnyHashableJSON.init),
                         textTranslationLanguages: body.textTranslationLanguages.map(AgentLanguage.init(catalog:)),
                         voiceTranslationLanguages: body.voiceTranslationLanguages.map(AgentLanguage.init(catalog:)),
                         availableToolKinds: body.availableToolKinds)
    }
}
