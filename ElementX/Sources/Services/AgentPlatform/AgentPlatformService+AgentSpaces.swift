//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: Brief 0037 — the Agent-Spaces management surface
// (directory, read-model, rooms, leave-room, create company/agent).
// Split from AgentPlatformService.swift to keep the class body under
// the SwiftLint type_body_length limit.
//

import AgentPlatformClient
import Foundation
import OpenAPIRuntime

nonisolated extension AgentPlatformService {
    // MARK: - Agent-Spaces directory (Brief 0037)

    func listMyAgentSpaces() async -> Result<AgentSpacesDirectory, AgentPlatformError> {
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<AgentSpacesDirectory, AgentPlatformError> in
            let response = try await client.underlying.listMyAgentSpaces(.init())
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                let spaces = body.spaces.map(Self.mapAgentSpaceSummary)
                let status = MyPersonalAgentsView.ProvisioningStatus(rawValue: body.provisioningStatus) ?? .idle
                return .success(.init(spaces: spaces, provisioningStatus: status))

            case .unauthorized:
                return .failure(.unauthorized)
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
        // AGENT-PLATFORM (decision 136): in progress means no live personal assistant.
        if case .success(let directory) = result, directory.provisioningStatus == .inProgress {
            await personalAssistantSeen(nil)
        }
        return result
    }

    func fetchAgentSpace(orgID: String) async -> Result<AgentSpaceDetail, AgentPlatformError> {
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<AgentSpaceDetail, AgentPlatformError> in
            let response = try await client.underlying.fetchMyAgentSpace(.init(path: .init(orgId: orgID)))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                return .success(.init(orgID: body.orgId,
                                      name: body.name,
                                      kind: AgentSpaceSummary.Kind(rawValue: body.kind) ?? .company,
                                      // A cleared logo is stored as "" server-side; normalise
                                      // to nil so the UI doesn't treat it as a present avatar.
                                      avatarMXC: body.avatarMxc.flatMap { $0.isEmpty ? nil : $0 },
                                      industry: body.industry,
                                      website: body.website,
                                      agents: body.agents.map(Self.mapAgentSpaceAgentCard)))

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
        // AGENT-PLATFORM (decision 136)
        if case .success(let detail) = result, detail.kind == .solo {
            await personalAssistantSeen(detail.agents.first { $0.kind == "personal_assistant" }?.agentID)
        }
        return result
    }

    private nonisolated static func mapAgentSpaceSummary(_ space: Components.Schemas.AgentSpaceSummaryResponse) -> AgentSpaceSummary {
        AgentSpaceSummary(orgID: space.orgId,
                          name: space.name,
                          kind: AgentSpaceSummary.Kind(rawValue: space.kind) ?? .company,
                          avatarMXC: space.avatarMxc.flatMap { $0.isEmpty ? nil : $0 },
                          agentCount: Int(space.agentCount))
    }

    func fetchAgentReadModel(agentID: String) async -> Result<AgentReadModel, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.fetchAgentReadModel(.init(path: .init(id: agentID)))
            switch response {
            case .ok(let ok):
                return try .success(Self.mapAgentReadModel(ok.body.json))

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

    func fetchAgentUsage(agentID: String) async -> Result<AgentUsage, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.fetchAgentUsage(.init(path: .init(id: agentID)))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                let days = body.days.compactMap { day -> AgentUsage.Day? in
                    guard let date = try? Date(day.date, strategy: .iso8601.year().month().day()) else {
                        return nil
                    }
                    return .init(id: day.date,
                                 date: date,
                                 usedPercent: day.usedPercent,
                                 categories: day.categories.map {
                                     .init(category: .init(serverValue: $0.category), usedPercent: $0.usedPercent)
                                 })
                }
                return .success(.init(today: .init(usedPercent: body.today.usedPercent,
                                                   limitReached: body.today.limitReached,
                                                   resetsAt: body.today.resetsAt),
                                      days: days))

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

    func fetchAgentRooms(agentID: String) async -> Result<[AgentRoomEntry], AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.fetchAgentRoomView(.init(path: .init(id: agentID)))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                let rooms = body.rooms.map { room in
                    AgentRoomEntry(roomID: room.roomId,
                                   displayName: room.displayName,
                                   kind: room.kind,
                                   activeTools: room.activeTools.map {
                                       AgentRoomToolSummary(toolID: $0.toolId,
                                                            toolKind: $0.toolKind,
                                                            targetLanguages: $0.targetLanguages,
                                                            firing: AgentToolFiring(rawValue: $0.triggerKind),
                                                            audience: AudienceScope(tag: $0.audience, members: $0.audienceMembers))
                                   })
                }
                return .success(rooms)

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

    func leaveRoom(agentID: String, roomID: String) async -> Result<Void, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.agentLeaveRoom(.init(path: .init(id: agentID),
                                                                            body: .json(.init(room: roomID))))
            switch response {
            case .ok:
                return .success(())
            case .badRequest(let bad):
                let detail = (try? bad.body.applicationProblemJson.detail) ?? "bad request"
                return .failure(.validation(detail: detail))
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden:
                return .failure(.forbidden)
            case .notFound:
                return .failure(.notFound)
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

    func joinRoom(agentID: String, roomID: String) async -> Result<Void, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.joinRoomHandler(.init(path: .init(id: agentID),
                                                                             body: .json(.init(room: roomID))))
            switch response {
            case .ok:
                return .success(())
            case .badRequest(let bad):
                let detail = (try? bad.body.applicationProblemJson.detail) ?? "bad request"
                return .failure(.validation(detail: detail))
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden:
                return .failure(.forbidden)
            case .notFound:
                return .failure(.notFound)
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

    func createCompany(name: String,
                       industry: String?,
                       website: String?,
                       brandingMXC: String?) async -> Result<AgentSpaceSummary, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.createAgentSpace(.init(body: .json(.init(brandingMxc: brandingMXC,
                                                                                                description: nil,
                                                                                                industry: industry,
                                                                                                name: name,
                                                                                                website: website))))
            switch response {
            case .created(let created):
                let body = try created.body.json
                return .success(Self.mapAgentSpaceSummary(body))
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

    func createCompanyAgent(companyID: String,
                            role: String,
                            displayName: String?,
                            roleBrief: String?) async -> Result<Void, AgentPlatformError> {
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<Void, AgentPlatformError> in
            let response = try await client.underlying.createSpaceAgent(.init(path: .init(orgId: companyID),
                                                                              body: .json(.init(displayName: displayName,
                                                                                                role: role,
                                                                                                roleBrief: roleBrief,
                                                                                                slug: nil))))
            switch response {
            case .created:
                return .success(())
            case .badRequest(let bad):
                let detail = (try? bad.body.applicationProblemJson.detail) ?? "bad request"
                return .failure(.validation(detail: detail))
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden:
                return .failure(.forbidden)
            case .notFound:
                return .failure(.notFound)
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
        // AGENT-PLATFORM (decision 98): the new agent has none of the owner's blocks yet.
        if case .success = result {
            await ownerBlocksNeedResync()
        }
        return result
    }

    private nonisolated static func mapAgentSpaceAgentCard(_ card: Components.Schemas.AgentCardResponse) -> AgentSpaceAgentCard {
        AgentSpaceAgentCard(agentID: card.agentId,
                            matrixUserID: card.matrixUserId,
                            displayName: card.displayName,
                            avatarMXC: card.avatarMxc,
                            kind: card.kind,
                            visibility: card.visibility,
                            lifecycleState: card.lifecycleState,
                            presence: AgentSpaceAgentCard.Presence(rawValue: card.presence) ?? .offline,
                            roomCount: Int(card.roomCount),
                            activeToolCount: Int(card.activeToolCount),
                            isPaused: card.paused)
    }

    func archiveAgent(agentID: String) async -> Result<Void, AgentPlatformError> {
        await withUnauthorizedRetry { [client] () async throws -> Result<Void, AgentPlatformError> in
            let response = try await client.underlying.deleteAgent(.init(path: .init(id: agentID)))
            switch response {
            case .noContent:
                return .success(())
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden:
                return .failure(.forbidden)
            case .notFound:
                return .failure(.notFound)
            // Decision 153: the personal assistant is never archived.
            case .conflict(let conflict):
                return .failure(.conflict(detail: (try? conflict.body.applicationProblemJson.detail) ?? "personal-assistant-not-deletable"))
            case .badRequest:
                return .failure(.validation(detail: "bad request"))
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }

    // MARK: - Schema-driven editing (Brief 0037 / ADR-0049)

    func fetchAgentEditSchema(agentID: String) async -> Result<AgentEditSchema, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.fetchAgentEditSchema(.init(path: .init(id: agentID)))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                return .success(Self.parseEditSchema(agentID: body.agentId,
                                                     kind: body.kind,
                                                     profileSchema: body.profileSchema.value,
                                                     personaSchema: body.personaSchema?.value))

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

    func editAgent(agentID: String, patch: AgentEditPatch) async -> Result<AgentReadModel, AgentPlatformError> {
        // The visitor policy is in the persona group on the wire.
        var persona: Components.Schemas.PersonaPatchBody?
        if !(patch.persona?.isEmpty ?? true) || patch.visitorPolicy != nil {
            persona = .init(greeting: patch.persona?.greeting,
                            ownerDisplayName: patch.persona?.ownerDisplayName,
                            tone: patch.persona?.tone,
                            visitorGreeting: patch.persona?.visitorGreeting,
                            visitorPolicy: patch.visitorPolicy?.rawValue)
        }
        let body = Components.Schemas.EditAgentRequest(avatarMxc: patch.avatarMXC,
                                                       displayName: patch.displayName,
                                                       model: nil,
                                                       paused: patch.paused,
                                                       persona: persona,
                                                       roleBrief: patch.roleBrief,
                                                       timezone: nil,
                                                       toolUseEnabled: nil,
                                                       visibility: patch.visibility,
                                                       voiceLanguage: patch.voiceLanguage?.rawValue)
        return await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.editAgent(.init(path: .init(id: agentID),
                                                                       body: .json(body)))
            switch response {
            case .ok(let ok):
                return try .success(Self.mapAgentReadModel(ok.body.json))
            case .badRequest(let bad):
                let detail = (try? bad.body.applicationProblemJson.detail) ?? "bad request"
                return .failure(.validation(detail: detail))
            case .conflict(let conflict):
                let detail = (try? conflict.body.applicationProblemJson.detail) ?? "conflict"
                return .failure(.conflict(detail: detail))
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden:
                return .failure(.forbidden)
            case .notFound:
                return .failure(.notFound)
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
    
    func updateCompanySpace(orgID: String,
                            name: String?,
                            industry: String?,
                            website: String?,
                            brandingMXC: String?) async -> Result<AgentSpaceSummary, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            let response = try await client.underlying.patchAgentSpace(.init(path: .init(orgId: orgID),
                                                                             body: .json(.init(brandingMxc: brandingMXC,
                                                                                               description: nil,
                                                                                               industry: industry,
                                                                                               name: name,
                                                                                               website: website))))
            switch response {
            case .ok(let ok):
                let body = try ok.body.json
                return .success(Self.mapAgentSpaceSummary(body))
            case .badRequest(let bad):
                let detail = (try? bad.body.applicationProblemJson.detail) ?? "bad request"
                return .failure(.validation(detail: detail))
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden:
                return .failure(.forbidden)
            case .notFound:
                return .failure(.notFound)
            // `/errors/personal-space-not-editable`: the edit is hidden for the
            // Solo space, so this is the generic failure if it ever happens.
            case .conflict(let conflict):
                return .failure(.conflict(detail: (try? conflict.body.applicationProblemJson.detail) ?? "conflict"))
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

    /// Walk the published JSON Schema for field bounds. Unknown or
    /// missing bounds fall back to permissive defaults — the server
    /// still validates authoritatively.
    private nonisolated static func parseEditSchema(agentID: String,
                                                    kind: String,
                                                    profileSchema: [String: Any],
                                                    personaSchema: [String: Any]?) -> AgentEditSchema {
        let profileProperties = profileSchema["properties"] as? [String: Any] ?? [:]
        let displayName = parseBounds(profileProperties["display_name"], defaultMin: 1, defaultMax: 64)

        var persona: AgentEditSchema.PersonaBounds?
        if let personaSchema {
            let personaProperties = personaSchema["properties"] as? [String: Any] ?? [:]
            persona = .init(ownerDisplayName: parseBounds(personaProperties["owner_display_name"], defaultMin: 0, defaultMax: 64),
                            tone: parseBounds(personaProperties["tone"], defaultMin: 0, defaultMax: 120),
                            greeting: parseBounds(personaProperties["greeting"], defaultMin: 0, defaultMax: 500),
                            visitorGreeting: parseBounds(personaProperties["visitor_greeting"], defaultMin: 0, defaultMax: 500))
        }

        return .init(agentID: agentID, kind: kind, displayName: displayName, persona: persona)
    }

    private nonisolated static func parseBounds(_ property: Any?, defaultMin: Int, defaultMax: Int) -> AgentEditSchema.FieldBounds {
        let dict = property as? [String: Any]
        let min = (dict?["minLength"] as? Int) ?? defaultMin
        let max = (dict?["maxLength"] as? Int) ?? defaultMax
        return .init(minLength: min, maxLength: max)
    }
}
