//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 87): an agent's block of a person, read and undone.
// Decision 98: the owner's messenger ignore list, sent whole. Decision 136: a
// new personal assistant gets it right away.
//

import AgentPlatformClient
import Foundation

nonisolated extension AgentPlatformService {
    func listAgentBlocks(ofContact contactMXID: String) async -> Result<[AgentContactBlock], AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            switch try await client.underlying.listMyBlocks(.init(query: .init(contactMxid: contactMXID))) {
            case .ok(let ok):
                return try .success(ok.body.json.blocks.map(Self.mapContactBlock))
            case .badRequest(let bad):
                return .failure(.validation(detail: (try? bad.body.applicationProblemJson.detail) ?? "contact_mxid"))
            case .unauthorized:
                return .failure(.unauthorized)
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }

    func listBlockedContacts(agentID: String, cursor: String?, limit: Int) async -> Result<AgentBlockedContactsPage, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            switch try await client.underlying.listAgentBlocks(.init(path: .init(id: agentID),
                                                                     query: .init(limit: Int64(limit), cursor: cursor))) {
            case .ok(let ok):
                let body = try ok.body.json
                return .success(.init(blocks: body.blocks.map {
                    AgentBlockedContact(contactMXID: $0.contactMxid, displayName: $0.displayName, blockedAt: $0.blockedAt)
                },
                nextCursor: body.nextCursor))
            case .badRequest(let bad):
                return .failure(.validation(detail: (try? bad.body.applicationProblemJson.detail) ?? "cursor"))
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

    func unblockContact(_ contactMXID: String, forAgent agentID: String) async -> Result<Void, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            switch try await client.underlying.deleteAgentBlocks(.init(path: .init(id: agentID), query: .init(contactMxid: contactMXID))) {
            case .noContent:
                return .success(())
            case .badRequest(let bad):
                return .failure(.validation(detail: (try? bad.body.applicationProblemJson.detail) ?? "contact_mxid"))
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

    // AGENT-PLATFORM (decision 98)
    func syncIgnoredUsers(_ userIDs: [String]) async -> Result<Void, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            switch try await client.underlying.putMyIgnoredUsers(.init(body: .json(.init(userIds: userIDs)))) {
            case .noContent:
                return .success(())
            case .badRequest(let bad):
                return .failure(.validation(detail: (try? bad.body.applicationProblemJson.detail) ?? "user_ids"))
            case .unauthorized:
                return .failure(.unauthorized)
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }

    private static func mapContactBlock(_ wire: Components.Schemas.ContactBlockView) -> AgentContactBlock {
        AgentContactBlock(agentID: wire.agentId, agentMXID: wire.agentMxid, agentName: wire.agentName, blockedAt: wire.blockedAt)
    }
}

// MARK: - A new personal assistant (decision 136)

extension AgentPlatformService {
    /// Every response that names the owner's personal assistant reports it
    /// here, `nil` when there is none. The one place a new assistant asks for
    /// the owner's ignore list.
    func personalAssistantSeen(_ agentID: String?) {
        if personalAssistantSightings.record(agentID) {
            ownerBlocksNeedResync()
        }
    }
}

/// What this session last saw of the owner's personal assistant.
final class PersonalAssistantSightings {
    private enum Sighting: Equatable {
        case missing
        case assistant(id: String)
    }

    private var lastSighting: Sighting?

    /// Whether this is a new assistant: one after none, or another one. The
    /// first sighting of the session is not, the launch PUT covered it.
    func record(_ agentID: String?) -> Bool {
        let sighting = agentID.map { Sighting.assistant(id: $0) } ?? .missing
        defer { lastSighting = sighting }
        guard let lastSighting, lastSighting != sighting, case .assistant = sighting else {
            return false
        }
        return true
    }
}
