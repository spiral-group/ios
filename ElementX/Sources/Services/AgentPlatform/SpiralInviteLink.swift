//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: invite links (Brief 0073 / ADR-0008).
//
// `https://spiral.md/join/{token}` is the one shape an invitation takes;
// `spiral://join/{token}` mirrors it for the landing page's "Open in
// Spiral" button (universal links do not fire on same-domain taps in
// Safari — Apple TN3155). The token is opaque: the orchestrator mints
// it from a base62 alphabet and campaign tokens such as `TESTFLIGHT`
// are upper-case words, so the grammar here is the wide
// `[A-Za-z0-9_-]{4,64}` that identity-login also accepts.
//

import Foundation

/// An invitation to register — the token, and the two URL forms it is
/// carried in.
nonisolated struct SpiralInviteLink: Equatable, Hashable, CustomStringConvertible {
    let token: String
    
    /// The token is a seat-taking capability: never in logs or rageshakes.
    var description: String { "SpiralInviteLink(<redacted>)" }
    
    private static let webBase = "https://\(SpiralLink.serverName)/join/"
    private static let schemeBase = "spiral://join/"
    
    /// The query parameter the app appends to the OAuth authorization
    /// URL; MAS forwards it to Hydra and identity-login reads it from
    /// the login request (ADR-0008 decision 3).
    static let authorizationQueryParameter = "spiral_invite"
    
    init?(token: String) {
        guard Self.validToken(token) else { return nil }
        self.token = token
    }
    
    /// The shareable HTTPS URL (universal link).
    var webURL: URL {
        URL(string: Self.webBase + token)!
    }
    
    /// The custom-scheme URL used by the landing page's open button.
    var schemeURL: URL {
        URL(string: Self.schemeBase + token)!
    }
    
    // MARK: - Parsing
    
    /// Parses an HTTPS universal link or a `spiral://join/…` URL.
    /// Returns nil for any other scheme, host, or shape.
    static func parse(_ url: URL) -> SpiralInviteLink? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        
        let segments: [String]
        switch scheme {
        case "https":
            guard url.host(percentEncoded: false)?.lowercased() == SpiralLink.serverName else { return nil }
            segments = url.path(percentEncoded: false).split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        case "spiral":
            // `spiral://join/T` reads `join` as the host; `spiral:///join/T`
            // keeps it in the path. Accept both — the landing page uses the
            // first, hand-typed links may use either.
            let host = url.host(percentEncoded: false) ?? ""
            let pathSegments = url.path(percentEncoded: false).split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            segments = host.isEmpty ? pathSegments : [host] + pathSegments
        default:
            return nil
        }
        
        guard segments.count == 2, segments[0] == "join" else { return nil }
        return SpiralInviteLink(token: segments[1])
    }
    
    /// Pulls an invitation out of whatever the person pasted: a full
    /// link in either form, or the bare token.
    static func parse(pastedText: String) -> SpiralInviteLink? {
        let trimmed = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        if let url = URL(string: trimmed), url.scheme != nil {
            return parse(url)
        }
        
        // A link typed without a scheme — `spiral.md/join/T`.
        if trimmed.lowercased().hasPrefix("\(SpiralLink.serverName)/"), let url = URL(string: "https://" + trimmed) {
            return parse(url)
        }
        
        return SpiralInviteLink(token: trimmed)
    }
    
    // MARK: - Validation (mirrors `invites-core.ts` in identity-login)
    
    static func validToken(_ value: String) -> Bool {
        (4...64).contains(value.count) && value.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == "-")
        }
    }
}
