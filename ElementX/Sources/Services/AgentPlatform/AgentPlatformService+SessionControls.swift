//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0054): in-call agent session controls.
//
// Implements the voice-session controls slice of
// `AgentPlatformServiceProtocol` — the REST backing for the Element
// Call widget's `window.controls.spiralBridge`. The widget never
// holds credentials; the CallScreen bridge proxies every call here
// with the session's MAS token.
//

import AgentPlatformClient
import Foundation
import OpenAPIRuntime

nonisolated extension AgentPlatformService {
    // MARK: - Session discovery

    func voiceSessionControlContexts(roomID: String) async -> Result<[VoiceSessionControlContext], VoiceControlsError> {
        await controlsCall {
            let response = try await self.client.underlying.listForOwnerHandler(.init(query: .init(limit: 50)))
            switch response {
            case .ok(let ok):
                let sessions = try ok.body.json.items
                // `starting` and `ending` joined the backend's vocabulary
                // with two-phase teardown (audit C9): `starting` is the
                // startup claim between consent and `active`, `ending` is a
                // teardown still converging. Both are sessions that EXIST —
                // omitting them made the Agent Center drop a session exactly
                // during the join window (controls flickered off on every
                // doorbell-triggered reload) and pretend a tearing-down agent
                // was already gone. The per-session controls read still
                // decides what is operable; membership in this set only
                // decides visibility.
                let live: Set = ["pending_consent", "pending_join", "starting", "active", "ending"]
                let contexts = sessions
                    .filter { $0.roomId == roomID && live.contains($0.state) }
                    .map { session in
                        // The owner listing only returns the caller's own
                        // sessions — everything here is controllable.
                        //
                        VoiceSessionControlContext(sessionID: session.id,
                                                   agentMxid: session.agentMxid,
                                                   canControl: true,
                                                   state: session.state)
                    }
                return .success(contexts)
            case .badRequest:
                return .failure(.unavailable("bad request"))
            case .unauthorized:
                return .failure(.unauthorized)
            case .internalServerError:
                return .failure(.unavailable("status 500"))
            case .undocumented(statusCode: let code, _):
                return .failure(.unavailable("status \(code)"))
            }
        }
    }

    // MARK: - Controls state + catalog

    func voiceSessionControls(sessionID: String) async -> Result<VoiceControlsState, VoiceControlsError> {
        await controlsCall {
            let response = try await self.client.underlying.getSessionControls(.init(path: .init(sessionId: sessionID)))
            switch response {
            case .ok(let ok):
                return try .success(Self.controlsState(from: ok.body.json))
            case .forbidden:
                return .failure(.unavailable("forbidden"))
            case .notFound:
                return .failure(.gone)
            case .badRequest:
                return .failure(.unavailable("status 400"))
            case .unauthorized:
                return .failure(.unauthorized)
            case .internalServerError:
                return .failure(.unavailable("status 500"))
            case .undocumented(statusCode: let code, _):
                return .failure(.unavailable("status \(code)"))
            }
        }
    }

    func voiceControlsCatalog(agentID: String) async -> Result<VoiceControlsCatalog, VoiceControlsError> {
        await controlsCall {
            let response = try await self.client.underlying.getAgentControlsCatalog(.init(path: .init(id: agentID)))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                let languages = body.voiceTranslationLanguages.map {
                    VoiceControlsCatalogLanguage(code: $0.code, label: $0.displayName)
                }
                return .success(VoiceControlsCatalog(voiceTranslationLanguages: languages))
            case .forbidden:
                return .failure(.unavailable("forbidden"))
            case .badRequest:
                return .failure(.unavailable("status 400"))
            case .unauthorized:
                return .failure(.unauthorized)
            case .internalServerError:
                return .failure(.unavailable("status 500"))
            case .undocumented(statusCode: let code, _):
                return .failure(.unavailable("status \(code)"))
            }
        }
    }

    // MARK: - Writes

    func setVoiceTranslation(sessionID: String,
                             params: VoiceTranslationParams,
                             revision: Int32) async -> Result<VoiceControlsState, VoiceControlsError> {
        await controlsCall {
            let body = try Components.Schemas.SetControlRequest(params: Self.translationParamsObject(params),
                                                                revision: revision,
                                                                state: "enabled")
            let response = try await self.client.underlying.putSessionControl(.init(path: .init(sessionId: sessionID,
                                                                                                control: "translation"),
                                                                                    body: .json(body)))
            return try Self.mapSetControlResponse(response)
        }
    }

    /// Wire shape of the backend's `SessionControlParams` (tagged like
    /// `ToolParams`): `{"kind": "translation", "style": …,
    /// "directions": [{"speaker_scope": …, "target_languages": […]}]}`.
    /// One direction per booth (Brief 0062). The `speaker_scope` value
    /// follows the serde form of `AudienceScope`: unit scopes are bare
    /// strings, member scopes are `{"<scope>": {"members": […]}}`.
    private static func translationParamsObject(_ params: VoiceTranslationParams) throws -> OpenAPIObjectContainer {
        // `any Sendable`: the resolved swift-openapi-runtime under Swift 6.2
        // types `unvalidatedValue` as Sendable — plain `Any` no longer compiles.
        func scopeWire(_ booth: VoiceTranslationBooth) -> any Sendable {
            switch booth.speakerScope {
            case "specific_senders", "everyone_except":
                return [booth.speakerScope: ["members": booth.speakerMembers]]
            default:
                return booth.speakerScope
            }
        }
        return try OpenAPIObjectContainer(unvalidatedValue: [
            "kind": "translation",
            "style": params.style,
            "directions": params.booths.map { booth in
                [
                    "speaker_scope": scopeWire(booth),
                    "target_languages": booth.targetLanguages
                ] as [String: any Sendable]
            }
        ])
    }

    func disableVoiceTranslation(sessionID: String,
                                 revision: Int32) async -> Result<VoiceControlsState, VoiceControlsError> {
        await controlsCall {
            let body = Components.Schemas.SetControlRequest(params: nil,
                                                            revision: revision,
                                                            state: "disabled")
            let response = try await self.client.underlying.putSessionControl(.init(path: .init(sessionId: sessionID,
                                                                                                control: "translation"),
                                                                                    body: .json(body)))
            return try Self.mapSetControlResponse(response)
        }
    }

    func clearVoiceTranslationOverride(sessionID: String) async -> Result<VoiceControlsState, VoiceControlsError> {
        await controlsCall {
            let response = try await self.client.underlying.deleteSessionControl(.init(path: .init(sessionId: sessionID,
                                                                                                   control: "translation")))
            switch response {
            case .ok(let ok):
                return try .success(Self.controlsState(from: ok.body.json.controls))
            case .forbidden:
                return .failure(.unavailable("forbidden"))
            case .notFound:
                return .failure(.gone)
            case .gone:
                return .failure(.gone)
            case .badRequest:
                return .failure(.unavailable("status 400"))
            case .unauthorized:
                return .failure(.unauthorized)
            case .unprocessableContent:
                return .failure(.unavailable("status 422"))
            case .internalServerError:
                return .failure(.unavailable("status 500"))
            case .undocumented(statusCode: let code, _):
                return .failure(.unavailable("status \(code)"))
            }
        }
    }

    func saveVoiceTranslationAsRoomDefault(sessionID: String) async -> Result<Void, VoiceControlsError> {
        await controlsCall {
            let response = try await self.client.underlying.postSaveAsRoomDefault(.init(path: .init(sessionId: sessionID,
                                                                                                    control: "translation")))
            switch response {
            case .ok:
                return .success(())
            case .forbidden:
                return .failure(.unavailable("forbidden"))
            case .notFound, .gone:
                return .failure(.gone)
            case .conflict(let conflict):
                // The promotion is refused like an arm (ADR-0088): no room
                // under the cap, or two directions are the same tool.
                if let refusal = Self.toolRefusal(try? conflict.body.applicationProblemJson) {
                    return .failure(.toolRefused(refusal))
                }
                return .failure(.unavailable("status 409"))
            case .unprocessableContent(let rejection):
                let problem = try? rejection.body.applicationProblemJson
                if let refusal = Self.toolRefusal(problem) {
                    return .failure(.toolRefused(refusal))
                }
                return .failure(.rejected(problem?.detail ?? "nothing to save — no active override"))
            case .badRequest:
                return .failure(.unavailable("status 400"))
            case .unauthorized:
                return .failure(.unauthorized)
            case .internalServerError:
                return .failure(.unavailable("status 500"))
            case .undocumented(statusCode: let code, _):
                return .failure(.unavailable("status \(code)"))
            }
        }
    }

    private static func toolRefusal(_ problem: Components.Schemas.ProblemDetails?) -> RoomToolRefusal? {
        problem.flatMap { RoomToolRefusal(problemType: $0._type, detail: $0.detail) }
    }

    // MARK: - Brief 0055: attach / end / artifact disable

    func attachVoiceAgent(agentID: String,
                          roomID: String,
                          params: VoiceAttachParams) async -> Result<String, VoiceControlsError> {
        await controlsCall {
            // WYSIWYG: the sheet's toggles are the whole truth for this
            // call, so every control is sent EXPLICITLY (translation off
            // = `disabled`, not "inherit whatever Tools say").
            let translation: Components.Schemas.AttachControlWrite
            if let t = params.translation {
                translation = try .init(params: Self.translationParamsObject(t), state: "enabled")
            } else {
                translation = .init(state: "disabled")
            }
            // Conversation off is the call's own rule, not "silent": the
            // owner's own chat with the assistant still talks (decision 180).
            let body = Components.Schemas.AttachRequest(controls: .init(conversation: .init(state: params.conversation ? "enabled" : "inherit"),
                                                                        recording: .init(state: params.recording ? "enabled" : "disabled"),
                                                                        summary: .init(state: params.summary ? "enabled" : "disabled"),
                                                                        translation: translation),
                                                        leavePolicy: .callEnd,
                                                        roomId: roomID)
            let response = try await self.client.underlying.attachHandler(.init(path: .init(id: agentID),
                                                                                body: .json(body)))
            switch response {
            case .accepted(let accepted):
                return try .success(accepted.body.json.sessionId)
            case .conflict(let conflict):
                // The agent already has a session in this room: the "add"
                // gesture joins it (the panel converges on it). Any other 409
                // (not a voice agent, a read-back race) is a retry.
                let problem = try? conflict.body.applicationProblemJson
                if problem?._type == VoiceControlsError.voiceSessionActiveTypeURI, let existing = problem?.existingSessionId {
                    return .success(existing)
                }
                if problem?._type == AgentPlatformError.agentPausedTypeURI {
                    return .failure(.agentPaused)
                }
                return .failure(.conflict)
            case .badRequest:
                return .failure(.rejected("bad request"))
            case .forbidden:
                return .failure(.unavailable("forbidden"))
            case .unauthorized:
                return .failure(.unauthorized)
            case .unprocessableContent(let rejection):
                // Brief 0062 — the attach 422 now also carries the
                // booth conflict (ADR-0075 D3): surface the RFC 7807
                // detail verbatim (it names the covering agent)
                // instead of assuming the join-failure copy.
                let problem = try? rejection.body.applicationProblemJson
                let detail = problem?.detail
                    ?? "the agent could not join this room — invite it first"
                // The invite-only refusal is the only 422 the caller acts on,
                // so it is identified by the backend's stable `type` URI rather
                // than by reading its prose.
                if problem?._type == VoiceControlsError.inviteRequiredTypeURI {
                    return .failure(.inviteRequired(detail))
                }
                return .failure(.rejected(Self.stripBoothConflictMarker(detail)))
            case .unsupportedMediaType:
                return .failure(.unavailable("status 415"))
            case .internalServerError:
                return .failure(.unavailable("status 500"))
            case .undocumented(statusCode: let code, _):
                return .failure(.unavailable("status \(code)"))
            }
        }
    }

    func endVoiceSession(sessionID: String) async -> Result<Void, VoiceControlsError> {
        await controlsCall {
            let response = try await self.client.underlying.endOrPurgeHandler(.init(path: .init(sessionId: sessionID)))
            switch response {
            case .noContent, .ok:
                return .success(())
            case .forbidden:
                return .failure(.unavailable("forbidden"))
            case .unauthorized:
                return .failure(.unauthorized)
            case .notFound:
                return .failure(.gone)
            case .conflict:
                // "Purge requested while teardown is still in progress".
                // Unreachable from here — this client never passes
                // `?purge=true` — but the case appeared when the spec was
                // refreshed, having been documented on the backend since
                // April while the vendored copy predated it. Surfaced
                // honestly rather than folded into success: if it ever does
                // arrive, the session is mid-teardown and a reload will show
                // the truth.
                return .failure(.conflict)
            case .badRequest:
                return .failure(.unavailable("status 400"))
            case .internalServerError:
                return .failure(.unavailable("status 500"))
            case .undocumented(statusCode: let code, _):
                return .failure(.unavailable("status \(code)"))
            }
        }
    }

    /// Turn an on/off session control on or off mid-call. Recording and
    /// summary were disable-only until Brief 0059 (stopping a recording left
    /// no way back); every switch shares this one write.
    func setVoiceSwitch(sessionID: String,
                        control: VoiceSessionSwitch,
                        enabled: Bool,
                        revision: Int32) async -> Result<VoiceControlsState, VoiceControlsError> {
        await controlsCall {
            let body = Components.Schemas.SetControlRequest(params: nil,
                                                            revision: revision,
                                                            state: enabled ? "enabled" : "disabled")
            let response = try await self.client.underlying.putSessionControl(.init(path: .init(sessionId: sessionID,
                                                                                                control: control.rawValue),
                                                                                    body: .json(body)))
            return try Self.mapSetControlResponse(response)
        }
    }

    // MARK: - Mapping

    private static func mapSetControlResponse(_ response: Operations.PutSessionControl.Output) throws -> Result<VoiceControlsState, VoiceControlsError> {
        switch response {
        case .ok(let ok):
            return try .success(controlsState(from: ok.body.json.controls))
        case .forbidden:
            return .failure(.unavailable("forbidden"))
        case .notFound:
            return .failure(.gone)
        case .conflict(let conflict):
            // Brief 0062 — two DIFFERENT 409s share this status: the CAS
            // revision conflict (widget reloads + retries) and the ADR-0075
            // booth conflict (another agent covers a claimed speaker — the
            // user must change the config, not retry).
            //
            // Told apart by the backend's stable `type` URI (audit A8-4),
            // the same way the invite-only refusal already is. It used to be
            // a substring search in the human `detail`, which made a copy
            // edit on the backend able to silently turn "change your
            // configuration" into "reload and retry".
            let problem = try? conflict.body.applicationProblemJson
            if problem?._type == VoiceControlsError.boothConflictTypeURI {
                let detail = problem?.detail ?? "another agent already covers this speaker"
                return .failure(.rejected(Self.stripBoothConflictMarker(detail)))
            }
            return .failure(.conflict)
        case .gone:
            return .failure(.gone)
        case .unprocessableContent(let rejection):
            let detail = (try? rejection.body.applicationProblemJson.detail)
                ?? "the request was rejected — reload and try again"
            return .failure(.rejected(detail))
        case .badRequest:
            return .failure(.unavailable("status 400"))
        case .unauthorized:
            return .failure(.unauthorized)
        case .unsupportedMediaType:
            return .failure(.unavailable("status 415"))
        case .internalServerError:
            return .failure(.unavailable("status 500"))
        case .undocumented(statusCode: let code, _):
            return .failure(.unavailable("status \(code)"))
        }
    }

    /// The backend's booth-conflict detail is
    /// `…: [booth-conflict agent=…] <human copy>` — show only the
    /// human copy (the marker is a wire discriminator, not UI text).
    private static func stripBoothConflictMarker(_ detail: String) -> String {
        guard let markerRange = detail.range(of: "[booth-conflict") else { return detail }
        let tail = detail[markerRange.lowerBound...]
        guard let close = tail.range(of: "] ") else { return detail }
        return String(tail[close.upperBound...])
    }

    private static func controlsState(from response: Components.Schemas.SessionControlsResponse) -> VoiceControlsState {
        // Brief 0062 — pass the booth list through verbatim; the panel
        // edits exactly what the engine runs.
        let booths = response.effective.booths.map {
            VoiceTranslationBooth(speakerScope: $0.speakerScope,
                                  speakerMembers: $0.speakerMembers,
                                  targetLanguages: $0.targetLanguages)
        }
        let effective = VoiceControlsEffective(source: response.effective.source,
                                               style: response.effective.style,
                                               booths: booths)
        let override = response.overrides
            .first { $0.control == "translation" }
            .map { VoiceControlsOverride(state: $0.state, revision: $0.revision) }
        func artifactRevision(_ control: String) -> Int32 {
            response.overrides.first { $0.control == control }?.revision ?? 0
        }
        let artifacts = VoiceControlsArtifacts(recording: VoiceArtifactState(enabled: response.callArtifacts.recordingEnabled,
                                                                             revision: artifactRevision("recording"),
                                                                             delivery: response.callArtifacts.recordingDelivery,
                                                                             deliveryTarget: response.callArtifacts.recordingDeliveryTarget,
                                                                             stopped: response.callArtifacts.recordingStopped),
                                               summary: VoiceArtifactState(enabled: response.callArtifacts.summaryEnabled,
                                                                           revision: artifactRevision("summary"),
                                                                           delivery: response.callArtifacts.summaryDelivery,
                                                                           deliveryTarget: response.callArtifacts.summaryDeliveryTarget,
                                                                           stopped: false))
        return VoiceControlsState(sessionID: response.sessionId,
                                  effective: effective,
                                  override: override,
                                  artifacts: artifacts,
                                  conversation: VoiceConversationState(active: response.conversation.active,
                                                                       available: response.conversation.available,
                                                                       revision: response.conversation.revision),
                                  canSaveAsRoomDefault: response.canSaveAsRoomDefault)
    }

    /// Same stale-MAS-token retry as `withUnauthorizedRetry` — a 401 gets
    /// one more attempt once the SDK has had time to refresh the token — but
    /// folding transport errors into the call controls' vocabulary instead
    /// of `AgentPlatformError`.
    private func controlsCall<Value>(_ operation: () async throws -> Result<Value, VoiceControlsError>) async -> Result<Value, VoiceControlsError> {
        let first = await controlsAttempt(operation)
        guard case .failure(.unauthorized) = first else { return first }
        try? await Task.sleep(for: Self.unauthorizedRetryDelay)
        return await controlsAttempt(operation)
    }

    private func controlsAttempt<Value>(_ operation: () async throws -> Result<Value, VoiceControlsError>) async -> Result<Value, VoiceControlsError> {
        do {
            return try await operation()
        } catch {
            MXLog.error("Voice session controls call failed: \(error)")
            return .failure(.unavailable("transport error"))
        }
    }
}
