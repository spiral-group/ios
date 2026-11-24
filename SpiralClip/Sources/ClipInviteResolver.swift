//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: the App Clip for invite links (Brief 0086).
//

import Foundation

/// What `GET https://<host>/join/{token}` says, in the shape the app's `InviteLinkResolver` reads.
enum ClipInviteResolution: Equatable {
    case valid(inviterDisplayName: String?, inviterUserID: String?, inviterAvatarURL: URL?)
    /// Unknown, revoked, used up or expired: the invitation can't be used.
    case unavailable
    /// No answer at all: offline or the request failed.
    case offline
    /// An answer the Clip can't read (a newer server, an error page).
    case unreadable
}

protocol ClipInviteResolverProtocol {
    func resolve(token: String) async -> ClipInviteResolution
}

/// The only request the Clip makes; it sends nothing but the token.
struct ClipInviteResolver: ClipInviteResolverProtocol {
    var session: URLSession = .shared

    func resolve(token: String) async -> ClipInviteResolution {
        guard let url = ClipInviteLink.webURL(token: token) else { return .unreadable }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            return .offline
        }
        return Self.resolution(from: data)
    }

    /// The body decides, not the status code: the endpoint answers a dead token with its state too.
    static func resolution(from data: Data) -> ClipInviteResolution {
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return .unreadable }
        switch body.state {
        case "valid":
            return .valid(inviterDisplayName: body.inviter?.displayName,
                          inviterUserID: body.inviter?.mxid,
                          inviterAvatarURL: body.inviter?.avatarURL.flatMap { avatarURL($0) })
        case "expired", "exhausted", "invalid":
            return .unavailable
        default:
            return .unreadable
        }
    }

    /// The inviter's public picture (`https://<host>/og/u/<localpart>`). Only this build's server, as the Clip talks to no one else.
    static func avatarURL(_ string: String, host: String = ClipInviteLink.host) -> URL? {
        guard let url = URL(string: string), url.scheme == "https",
              url.host(percentEncoded: false)?.lowercased() == host else {
            return nil
        }
        return url
    }

    private struct Body: Decodable {
        let state: String
        let inviter: Inviter?
    }

    private struct Inviter: Decodable {
        let displayName: String
        let avatarURL: String?
        let mxid: String

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case avatarURL = "avatar_url"
            case mxid
        }
    }
}
