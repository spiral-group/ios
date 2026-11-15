//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The public feed's posts as the app owns
// them, mapped from the generated `Components.Schemas.Feed*` types by
// `FeedService`. Every enumerated field is a wire string on the server
// (arch § 3); here it is an app enum with an `.other` case, so a newer value
// degrades instead of failing a page (decision 96).
//

import Foundation

nonisolated struct FeedPost: Identifiable, Equatable, Codable {
    /// UUIDv7, lower-case; the dedupe key across pages.
    let id: String
    let createdAt: Date
    let author: FeedAuthor
    let content: FeedContent
    /// Moved by likes, comments and shares (lane I3).
    var counts: FeedCounts
    var viewer: FeedViewer
    /// Moved by the sync stream (`feed.post_state`).
    var state: FeedPostState
    /// Only when `state` is `.held`.
    let heldReason: FeedHeldReason?
    /// The author's switch (lane I3).
    var commentsEnabled: Bool
}

nonisolated struct FeedAuthor: Equatable, Codable {
    let userID: String
    /// Absent when unset; `displayName` falls back to the MXID's localpart.
    let name: String?
    let avatarURL: URL?
    /// One plain-text line of at most 160 characters (MSC4133 `io.spiral.bio`).
    let bio: String?
    /// Spiral's official account, shown with a label (D-P1).
    let isOfficial: Bool
    /// The name (or the localpart) breaks the rules (lane B4): shown as a
    /// neutral name, never the localpart, and without the MXID or a bio.
    let isNameWithheld: Bool

    var displayName: String {
        FeedActivityText.name(userID: userID, name: name, isNameWithheld: isNameWithheld)
    }

    /// The MXID to show under the name; `nil` while the name is withheld, as the MXID carries the localpart.
    var shownUserID: String? {
        isNameWithheld ? nil : userID
    }
}

nonisolated struct FeedContent: Equatable, Codable {
    let kind: FeedContentKind
    /// Plain text, no markup; links are detected by `FeedTextBuilder`.
    let text: String
    /// 0–4 images in order.
    let media: [FeedMediaRef]
    /// Set by a moderator or the filter: one post-level "Show" overlay.
    let isSensitive: Bool
}

nonisolated enum FeedContentKind: Equatable, Codable {
    case text
    case textImages
    /// A kind newer than this build: "Update Spiral to see this post".
    case other(String)

    init(wireValue: String) {
        switch wireValue {
        case "text": self = .text
        case "text_images": self = .textImages
        default: self = .other(wireValue)
        }
    }
}

nonisolated struct FeedMediaRef: Equatable, Codable {
    let id: String
    /// `nil` when the server sent something that is not a URL; the tile then shows its placeholder.
    let mxcURL: URL?
    let mimeType: String
    let width: Int
    let height: Int
    let blurhash: String?
    let altText: String?
}

nonisolated struct FeedCounts: Equatable, Codable {
    var likes: Int
    var comments: Int
    var shares: Int
}

nonisolated struct FeedViewer: Equatable, Codable {
    var liked: Bool
    var hidden: Bool
    let isAuthor: Bool
}

nonisolated enum FeedPostState: Equatable, Codable {
    case visible
    /// Seen by its author only: "Under review".
    case held
    /// Its author is deactivated; the server returns it to nobody.
    case hiddenAuthor
    /// Seen by its author only.
    case removed
    /// A state newer than this build: shown as "not available".
    case other(String)

    init(wireValue: String) {
        switch wireValue {
        case "visible": self = .visible
        case "held": self = .held
        case "hidden_author": self = .hiddenAuthor
        case "removed": self = .removed
        default: self = .other(wireValue)
        }
    }
}

nonisolated enum FeedHeldReason: Equatable, Codable {
    case filter
    case reports
    case moderator
    case premoderation
    case sla
    case other(String)

    init(wireValue: String) {
        switch wireValue {
        case "filter": self = .filter
        case "reports": self = .reports
        case "moderator": self = .moderator
        case "premoderation": self = .premoderation
        case "sla": self = .sla
        default: self = .other(wireValue)
        }
    }
}

nonisolated struct FeedPage: Equatable, Codable {
    let items: [FeedPost]
    /// Opaque; pass it back for the next (older) page. `nil` at the end.
    let nextCursor: String?
    /// The pinned rules post above the first page of Latest (D-P1).
    let pinned: FeedPost?
}
