//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: the App Clip's invitation hand-off (Brief 0086).
//
// Compiled into BOTH the app and the SpiralClip target, so it imports
// Foundation only and uses no other app code. The Clip writes the
// invitation into the shared App Group's defaults as soon as it has a
// well-formed token; the app reads it on a launch with no session, turns
// it into `AppSettings.pendingInvite` and removes it. The JSON shape and
// the key are the contract in the brief: change both sides together.
//
// Both targets follow the build's environment (Brief 0084): `spiral.md`, or
// `staging.spiral.md` in a Staging build, from the `spiralServerName`
// Info.plist key set to `$(SPIRAL_ASSOCIATED_DOMAIN)`. The invitation records
// that host, so an app only takes an invitation for its own server.
//

import Foundation

/// The invitation the App Clip carries across the App Store install.
nonisolated struct ClipInvite: Codable, Equatable, CustomStringConvertible {
    let token: String
    /// The server the link was for: `spiral.md` or `staging.spiral.md`.
    let host: String
    var inviterDisplayName: String?
    var inviterUserID: String?
    let savedAt: Date

    init(token: String, host: String = ClipInviteLink.host, inviterDisplayName: String? = nil, inviterUserID: String? = nil, savedAt: Date) {
        self.token = token
        self.host = host
        self.inviterDisplayName = inviterDisplayName
        self.inviterUserID = inviterUserID
        self.savedAt = savedAt
    }

    /// The token is a seat-taking capability: never in logs.
    var description: String {
        "ClipInvite(<redacted>)"
    }
}

/// Reads and writes the `ClipInvite` in the App Group's `UserDefaults`.
nonisolated struct ClipInviteHandOff {
    static let key = "spiral.clipInvite.v1"
    /// How long the invitation waits for the full app (operator, 2026-11-19).
    static let lifetime: TimeInterval = 7 * 24 * 60 * 60
    /// The Info.plist key both targets carry with `$(APP_GROUP_IDENTIFIER)`.
    static let appGroupInfoPlistKey = "appGroupIdentifier"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The hand-off in the App Group named by the bundle's Info.plist.
    init?(bundle: Bundle = .main) {
        guard let appGroupIdentifier = bundle.object(forInfoDictionaryKey: Self.appGroupInfoPlistKey) as? String,
              let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return nil
        }
        self.init(defaults: defaults)
    }

    func write(_ invite: ClipInvite) {
        guard let data = try? Self.encoder.encode(invite) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// The stored invitation whatever its age, or nil when absent, malformed, without a host or carrying an invalid token.
    func read() -> ClipInvite? {
        guard let data = defaults.data(forKey: Self.key),
              let invite = try? Self.decoder.decode(ClipInvite.self, from: data),
              !invite.host.isEmpty,
              ClipInviteLink.isValidToken(invite.token) else {
            return nil
        }
        return invite
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    /// Removes the stored invitation and returns it if it is still fresh.
    func take(now: Date = .now) -> ClipInvite? {
        let invite = read()
        clear()
        guard let invite, Self.isFresh(invite, now: now) else { return nil }
        return invite
    }

    /// Fresh while younger than `lifetime`. A `savedAt` in the future (a clock change) counts as fresh.
    static func isFresh(_ invite: ClipInvite, now: Date) -> Bool {
        now.timeIntervalSince(invite.savedAt) < lifetime
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// The Clip's copy of `SpiralInviteLink`'s `/join/{token}` rule.
nonisolated enum ClipInviteLink {
    /// The Info.plist key both targets carry with `$(SPIRAL_ASSOCIATED_DOMAIN)`.
    static let serverNameInfoPlistKey = "spiralServerName"

    /// This build's server: `spiral.md`, or `staging.spiral.md` in a Staging build. Empty, so matching nothing, without the key.
    static let host = (Bundle.main.object(forInfoDictionaryKey: serverNameInfoPlistKey) as? String)?.lowercased() ?? ""

    /// The token of `https://<host>/join/{token}` or `spiral://join/{token}`, nil for anything else.
    static func token(from url: URL, host: String = host) -> String? {
        guard let scheme = url.scheme?.lowercased() else { return nil }

        let pathSegments = url.path(percentEncoded: false).split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let segments: [String]
        switch scheme {
        case "https":
            guard url.host(percentEncoded: false)?.lowercased() == host else { return nil }
            segments = pathSegments
        case "spiral":
            let urlHost = url.host(percentEncoded: false) ?? ""
            segments = urlHost.isEmpty ? pathSegments : [urlHost] + pathSegments
        default:
            return nil
        }

        guard segments.count == 2, segments[0] == "join", isValidToken(segments[1]) else { return nil }
        return segments[1]
    }

    /// Mirrors `SpiralInviteLink.validToken` (and identity-login's `invites-core.ts`).
    static func isValidToken(_ value: String) -> Bool {
        (4...64).contains(value.count) && value.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == "-")
        }
    }

    static func webURL(token: String, host: String = host) -> URL? {
        URL(string: "https://\(host)/join/\(token)")
    }

    static func schemeURL(token: String) -> URL? {
        URL(string: "spiral://join/\(token)")
    }
}
