//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: Spiral link namespace (Brief 0060 / ADR-0072).
//
// `https://spiral.md` is the ONLY link namespace this app generates.
// The Matrix Rust SDK's `matrix.to` permalink helpers
// (`matrixToUserPermalink`, `matrixToRoomAliasPermalink`,
// `Room.matrixToPermalink`, `Room.matrixToEventPermalink`) are NEVER
// used for outbound sharing or mentions — they remain available only
// as read-only parsing of bridge/legacy inbound content (mautrix
// bridges format mentions as matrix.to links forever).
//
// URL contract — the path carries the Matrix identifier VERBATIM,
// sigil included, with the homeserver implied (ADR-0060):
//
//   https://spiral.md/@{localpart}              →  @localpart:spiral.md
//   https://spiral.md/c/{alias}                 →  #alias:spiral.md
//   https://spiral.md/!{roomLocalpart}          →  !roomLocalpart:spiral.md
//   https://spiral.md/!{room}/${event}          →  event permalink
//
// `@`, `!` and `$` are legal unencoded path characters (RFC 3986
// `pchar`). The alias sigil `#` is the one that cannot appear: it
// starts the URL fragment, so `spiral.md/#general` never reaches the
// server — exactly the matrix.to limitation this namespace escapes.
// Aliases therefore keep the `/c/` prefix.
//
// The `spiral:` scheme mirrors the same shapes for the landing page's
// "Open in Spiral" button, because iOS universal links do not fire on
// same-domain taps in Safari (Apple TN3155). It uses THREE slashes
// (`spiral:///@red`): with two, Foundation reads `@` as the userinfo
// separator and the localpart becomes the host.
//
// The codec is stateless and synchronous: room/event localparts that
// Synapse generates are already URL-safe, so path segments carry them
// verbatim with no base64 layer.

import Foundation
import MatrixRustSDK

/// A Spiral smart link — the product's single source of truth for
/// building and parsing every shareable URL.
///
/// `nonisolated`: a pure value type consumed from nonisolated contexts
/// (e.g. `RoomMemberProxyProtocol.permalink`); upstream's Swift 6.2
/// default-MainActor isolation would otherwise capture it.
nonisolated enum SpiralLink: Equatable {
    /// `@localpart:spiral.md` profile link.
    case user(localpart: String)
    /// `#alias:spiral.md` room link via canonical alias.
    case roomAlias(alias: String)
    /// `!roomLocalpart:spiral.md` room link via room ID.
    case room(roomLocalpart: String)
    /// Event permalink inside a room.
    case event(roomLocalpart: String, eventLocalpart: String)
    
    /// The homeserver domain implied by every link (ADR-0060:
    /// server_name == main_domain, single-tenant deployment).
    static let serverName = isLocalDevStack ? "localhost" : "spiral.md"
    
    /// A Debug build launched with `SPIRAL_DEV_STACK=1` talks to the local dev
    /// stack, whose server name is `localhost` (docs/project/DEV_STACK_SIMULATOR.md).
    static let isLocalDevStack: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["SPIRAL_DEV_STACK"] == "1"
        #else
        false
        #endif
    }()
    
    // MARK: - Building
    
    private static let webBase = "https://\(serverName)"
    /// Three slashes on purpose — see the note at the top of the file.
    private static let schemeBase = "spiral://"
    
    /// The shareable HTTPS URL (universal link).
    var webURL: URL? {
        url(base: Self.webBase)
    }
    
    /// The custom-scheme URL used by the landing page's open button.
    var schemeURL: URL? {
        url(base: Self.schemeBase)
    }
    
    private func url(base: String) -> URL? {
        URL(string: base + path)
    }
    
    /// The path component shared by both URL forms.
    private var path: String {
        switch self {
        case .user(let localpart):
            return "/@\(localpart)"
        case .roomAlias(let alias):
            return "/c/\(alias)"
        case .room(let roomLocalpart):
            return "/!\(roomLocalpart)"
        case .event(let roomLocalpart, let eventLocalpart):
            return "/!\(roomLocalpart)/$\(eventLocalpart)"
        }
    }
    
    /// Matrix identifier for this link's target.
    var matrixIdentifier: String {
        switch self {
        case .user(let localpart):
            return "@\(localpart):\(Self.serverName)"
        case .roomAlias(let alias):
            return "#\(alias):\(Self.serverName)"
        case .room(let roomLocalpart):
            return Self.roomIdentifier(for: roomLocalpart)
        case .event(let roomLocalpart, _):
            return Self.roomIdentifier(for: roomLocalpart)
        }
    }
    
    /// Rebuilds a room ID from the localpart a link carries.
    ///
    /// The URL cannot say whether the room predates room version 12,
    /// but the shape can: v12 IDs are the create-event hash, 43
    /// base64url characters, and carry no `:server`. Anything shorter
    /// is an older opaque ID, which on this single-homeserver
    /// deployment (ADR-0060) is always ours.
    private static func roomIdentifier(for roomLocalpart: String) -> String {
        roomLocalpart.count == hashedRoomIDLength ? "!\(roomLocalpart)" : "!\(roomLocalpart):\(serverName)"
    }
    
    /// Length of a base64url-encoded SHA-256 hash without padding.
    private static let hashedRoomIDLength = 43
    
    // MARK: - Building from Matrix identifiers
    
    /// Builds a profile link from a full MXID (`@localpart:server`).
    /// Returns nil for users on foreign homeservers — we never mint
    /// spiral.md links for entities we don't serve.
    init?(userID: String) {
        guard let localpart = Self.localpart(from: userID, sigil: "@"),
              Self.validUserLocalpart(localpart) else {
            return nil
        }
        self = .user(localpart: localpart)
    }
    
    /// Builds a room link, preferring the canonical alias when one
    /// exists (shorter, human-readable) and falling back to the
    /// room ID (unbreakable).
    init?(roomID: String, canonicalAlias: String?) {
        if let canonicalAlias,
           let aliasLocalpart = Self.localpart(from: canonicalAlias, sigil: "#"),
           Self.validAliasLocalpart(aliasLocalpart) {
            self = .roomAlias(alias: aliasLocalpart)
            return
        }
        guard let roomLocalpart = Self.localpart(from: roomID, sigil: "!", allowsMissingServer: true),
              Self.validRoomLocalpart(roomLocalpart) else {
            return nil
        }
        self = .room(roomLocalpart: roomLocalpart)
    }
    
    /// Builds an event permalink. Always room-ID based: aliases can be
    /// re-pointed, an event permalink must keep resolving.
    init?(roomID: String, eventID: String) {
        // Event IDs carry no `:server` suffix on room version 4+ (they
        // are `$` + a base64url hash), so only the sigil is stripped.
        guard let roomLocalpart = Self.localpart(from: roomID, sigil: "!", allowsMissingServer: true),
              Self.validRoomLocalpart(roomLocalpart),
              let eventLocalpart = eventID.dropSigil("$"),
              Self.validEventLocalpart(eventLocalpart) else {
            return nil
        }
        self = .event(roomLocalpart: roomLocalpart, eventLocalpart: eventLocalpart)
    }
    
    /// Extracts and validates the localpart from a Matrix identifier
    /// belonging to our homeserver.
    /// - Parameter allowsMissingServer: room IDs lost their `:server`
    ///   suffix in room version 12, so for those the domain is optional.
    ///   Users and aliases always carry one.
    private static func localpart(from identifier: String,
                                  sigil: String,
                                  allowsMissingServer: Bool = false) -> String? {
        guard identifier.hasPrefix(sigil) else { return nil }
        
        let body = identifier.dropFirst(sigil.count)
        
        guard let separator = body.firstIndex(of: ":") else {
            // No domain at all: only legal for a room-version-12 ID,
            // and only because every room here is on our homeserver.
            guard allowsMissingServer, !body.isEmpty else { return nil }
            return String(body)
        }
        
        guard body[body.index(after: separator)...] == serverName else {
            return nil
        }
        
        let localpart = body[body.startIndex..<separator]
        return localpart.isEmpty ? nil : String(localpart)
    }
    
    // MARK: - Parsing
    
    /// Parses an HTTPS universal link or a `spiral://` scheme URL.
    /// Returns nil for any other scheme, host, or malformed shape.
    static func parse(_ url: URL) -> SpiralLink? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        
        let path: String
        switch scheme {
        case "https":
            guard url.host(percentEncoded: false)?.lowercased() == serverName else {
                return nil
            }
            path = url.path(percentEncoded: false)
        case "spiral":
            // `spiral:///@red` — the authority is empty on purpose, so
            // the whole identifier stays in the path. A two-slash form
            // would make Foundation read `@` as a userinfo separator.
            guard url.host(percentEncoded: false)?.isEmpty ?? true else {
                return nil
            }
            path = url.path(percentEncoded: false)
        default:
            return nil
        }
        
        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let first = segments.first else { return nil }
        
        // `@localpart` — profile.
        if let localpart = first.dropSigil("@") {
            guard segments.count == 1, validUserLocalpart(localpart) else { return nil }
            return .user(localpart: localpart)
        }
        
        // `!roomLocalpart` on its own, or followed by `$eventLocalpart`.
        if let roomLocalpart = first.dropSigil("!") {
            guard validRoomLocalpart(roomLocalpart) else { return nil }
            
            switch segments.count {
            case 1:
                return .room(roomLocalpart: roomLocalpart)
            case 2:
                guard let eventLocalpart = segments[1].dropSigil("$"),
                      validEventLocalpart(eventLocalpart) else {
                    return nil
                }
                return .event(roomLocalpart: roomLocalpart, eventLocalpart: eventLocalpart)
            default:
                return nil
            }
        }
        
        // `c/alias` — the sigil-less prefix aliases need because `#`
        // would start a URL fragment.
        if first == "c" {
            guard segments.count == 2, validAliasLocalpart(segments[1]) else { return nil }
            return .roomAlias(alias: segments[1])
        }
        
        return nil
    }
    
    // MARK: - Validation (mirrors `links.rs` on the backend)
    
    /// Matrix user localpart grammar on this deployment. The spec's
    /// `/` and `+` are excluded — our URL shape cannot carry them and
    /// no local user (owners, agents, bridge puppets) has them.
    static func validUserLocalpart(_ value: String) -> Bool {
        validLocalpart(value) { character in
            character.isASCII && (character.isLowercase || character.isNumber || character == "." || character == "_" || character == "=" || character == "-")
        }
    }
    
    /// Room-alias localpart — same grammar as user localparts.
    static func validAliasLocalpart(_ value: String) -> Bool {
        validUserLocalpart(value)
    }
    
    /// Room-ID localpart (`[A-Za-z]{18}` in practice; opaque-token
    /// alphabet accepted defensively).
    static func validRoomLocalpart(_ value: String) -> Bool {
        validLocalpart(value) { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == "-")
        }
    }
    
    /// Event-ID localpart (base64url on room v4+).
    static func validEventLocalpart(_ value: String) -> Bool {
        validRoomLocalpart(value)
    }
    
    private static let maxLocalpartLength = 255
    
    private static func validLocalpart(_ value: String, charset: (Character) -> Bool) -> Bool {
        !value.isEmpty && value.count <= maxLocalpartLength && value.allSatisfy(charset)
    }
}

// MARK: - Canonical link resolution

/// A Matrix entity a tappable link points at, whichever namespace the
/// link itself used.
nonisolated enum MatrixLinkTarget: Equatable {
    case user(userID: String)
    case roomAlias(alias: String)
    case room(roomID: String)
    case event(roomID: String, eventID: String)
}

nonisolated extension SpiralLink {
    /// **The** link resolver for the whole app: every surface that has
    /// to decide "is this URL one of ours, and what does it point at?"
    /// calls this and nothing else.
    ///
    /// Two namespaces reach the client, and they are not symmetric:
    ///
    /// * `spiral.md` smart links — everything the app itself hands to
    ///   the user (share sheet, copy link, universal links). This is
    ///   the only namespace we ever *generate*.
    /// * `matrix.to` permalinks — Matrix WIRE format. The spec encodes
    ///   mentions inside `formatted_body` this way, the Rust rich-text
    ///   editor detects them by that shape, and the mautrix bridges
    ///   emit them in every bridged mention. We parse them so those
    ///   taps stay in the app; we never mint them ourselves.
    ///
    /// Keeping both behind one function is what stops the two rails
    /// from drifting into per-call-site `if/else` chains.
    static func matrixLinkTarget(from url: URL) -> MatrixLinkTarget? {
        if let spiralLink = parse(url) {
            switch spiralLink {
            case .user:
                return .user(userID: spiralLink.matrixIdentifier)
            case .roomAlias:
                return .roomAlias(alias: spiralLink.matrixIdentifier)
            case .room:
                return .room(roomID: spiralLink.matrixIdentifier)
            case .event(_, let eventLocalpart):
                return .event(roomID: spiralLink.matrixIdentifier, eventID: "$\(eventLocalpart)")
            }
        }
        
        // Inbound-only: matrix.to / matrix: URIs from message content.
        guard let entity = parseMatrixEntityFrom(uri: url.absoluteString) else { return nil }
        
        switch entity.id {
        case .user(let id):
            return .user(userID: id)
        case .roomAlias(let alias):
            return .roomAlias(alias: alias)
        case .room(let id):
            return .room(roomID: id)
        case .eventOnRoomId(let roomID, let eventID):
            return .event(roomID: roomID, eventID: eventID)
        case .eventOnRoomAlias(let alias, let eventID):
            return .event(roomID: alias, eventID: eventID)
        }
    }
}

private nonisolated extension String {
    /// Returns the string without its leading Matrix sigil, or nil when
    /// it doesn't carry that sigil.
    func dropSigil(_ sigil: Character) -> String? {
        guard first == sigil else { return nil }
        return String(dropFirst())
    }
}
