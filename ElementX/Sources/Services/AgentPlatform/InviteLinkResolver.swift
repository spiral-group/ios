//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: invite links (Brief 0073 / ADR-0008).
//

import Foundation

/// Who is inviting, as the public `GET /join/{token}` reports it.
nonisolated struct InviteInviter: Equatable, Hashable, Codable {
    let displayName: String
    let avatarURL: String?
    let mxid: String
    
    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case mxid
    }
}

/// What the server says about an invitation before anyone registers
/// with it. `invalid` covers unknown and revoked tokens.
nonisolated enum InviteLinkState: Equatable {
    case valid(inviter: InviteInviter?)
    case expired
    case exhausted
    case invalid
}

enum InviteLinkResolverError: Error {
    case network
    case malformedResponse
}

// sourcery: AutoMockable
protocol InviteLinkResolverProtocol {
    /// Asks the public landing endpoint for the invitation's state. No
    /// authentication — this runs before the person has an account.
    func resolve(_ link: SpiralInviteLink) async -> Result<InviteLinkState, InviteLinkResolverError>
}

/// `GET https://spiral.md/join/{token}` with `Accept: application/json`.
final class InviteLinkResolver: InviteLinkResolverProtocol {
    private let session: URLSession
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    func resolve(_ link: SpiralInviteLink) async -> Result<InviteLinkState, InviteLinkResolverError> {
        var request = URLRequest(url: link.webURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        
        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            MXLog.error("Failed resolving invite link: \(error)")
            return .failure(.network)
        }
        
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else {
            return .failure(.malformedResponse)
        }
        
        switch body.state {
        case "valid": return .success(.valid(inviter: body.inviter))
        case "expired": return .success(.expired)
        case "exhausted": return .success(.exhausted)
        case "invalid": return .success(.invalid)
        default: return .failure(.malformedResponse)
        }
    }
    
    private struct Body: Decodable {
        let state: String
        let inviter: InviteInviter?
    }
}
