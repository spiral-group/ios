//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0078, GDPR): the person's own data — the account
// export, the calls and one call's export, and erasing what their assistant
// remembers about a contact.
//

import AgentPlatformClient
import Foundation
import OpenAPIRuntime

nonisolated extension AgentPlatformService {
    func exportAccountData() async -> Result<Data, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            try await Self.mapDocument(client.jsonDocument(at: "/api/v1/me/export"))
        }
    }

    func listVoiceSessions(cursor: String?) async -> Result<VoiceSessionsPage, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            switch try await client.underlying.listForOwnerHandler(.init(query: .init(limit: 50, cursor: cursor))) {
            case .ok(let ok):
                let body = try ok.body.json
                return .success(VoiceSessionsPage(sessions: body.items.map(Self.mapVoiceSessionRecord),
                                                  nextCursor: body.nextCursor))
            case .badRequest(let bad):
                let detail = (try? bad.body.applicationProblemJson.detail) ?? "bad cursor"
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

    func exportVoiceSession(sessionID: String) async -> Result<Data, AgentPlatformError> {
        guard let encodedID = sessionID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) else {
            return .failure(.validation(detail: "session id"))
        }
        return await withUnauthorizedRetry { [client] in
            try await Self.mapDocument(client.jsonDocument(at: "/api/v1/voice-sessions/\(encodedID)/export"))
        }
    }

    func eraseAssistantMemory(aboutContact contactMXID: String) async -> Result<ContactErasure, AgentPlatformError> {
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<ContactErasure, AgentPlatformError> in
            switch try await client.underlying.deleteMeMemory(.init(query: .init(contactMxid: contactMXID))) {
            case .ok(let ok):
                return try .success(ContactErasure(ok.body.json.erased))
            case .badRequest(let bad):
                let detail = (try? bad.body.applicationProblemJson.detail) ?? "contact_mxid"
                return .failure(.validation(detail: detail))
            case .unauthorized:
                return .failure(.unauthorized)
            case .notFound(let notFound):
                // The route's own 404 names what is missing; any other 404
                // (a route that is not there) erased nothing anyone can vouch for.
                let detail = try? notFound.body.applicationProblemJson.detail
                return detail == Self.noAccountDetail ? .success(.nothing) : .failure(.notFound)
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
        // AGENT-PLATFORM (decision 98): the person's rows are gone, the owner's block of them with them.
        if case .success = result {
            await ownerBlocksNeedResync()
        }
        return result
    }

    // MARK: - Mapping
    
    /// `DELETE /me/memory`'s own 404 detail (`me.rs` `delete_me_memory`): the
    /// caller has no account, so nothing is held about anyone.
    static let noAccountDetail = "account"

    static func mapDocument(_ response: (status: Int, body: Data)) -> Result<Data, AgentPlatformError> {
        switch response.status {
        case 200:
            .success(response.body)
        default:
            .failure(mapUndocumented(response.status))
        }
    }

    private static func mapVoiceSessionRecord(_ wire: Components.Schemas.VoiceSessionView) -> VoiceSessionRecord {
        VoiceSessionRecord(id: wire.id,
                           agentMXID: wire.agentMxid,
                           roomID: wire.roomId,
                           createdAt: wire.createdAt,
                           startedAt: wire.startedAt,
                           endedAt: wire.endedAt)
    }
}

nonisolated extension ContactErasure {
    init(_ body: Components.Schemas.ContactErasureCountsBody) {
        self.init(memoryEntries: Int(body.memoryEntries),
                  relationships: Int(body.relationships),
                  transcriptLines: Int(body.transcriptLines),
                  outreachTargets: Int(body.outreachTargets),
                  approvals: Int(body.approvals),
                  keyRelayRows: Int(body.keyRelayRows),
                  verifications: Int(body.verifications),
                  actionLogEntriesScrubbed: Int(body.actionLogEntriesScrubbed),
                  sessionControlsScrubbed: Int(body.sessionControlsScrubbed),
                  inviteRedemptionsScrubbed: Int(body.inviteRedemptionsScrubbed),
                  toolScopesRewritten: Int(body.toolScopesRewritten),
                  toolsTurnedOff: Int(body.toolsTurnedOff))
    }
}
