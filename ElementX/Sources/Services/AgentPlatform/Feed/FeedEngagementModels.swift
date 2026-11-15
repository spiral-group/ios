//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Lane I3 on B3's contract: likes, flat
// comments with "replying to", hide, the author's comment switch and the
// share into a chat, as the app owns them. Enumerated wire strings keep an
// `.other` case, so a newer value degrades instead of failing (decision 96).
//

import Foundation

/// A comment under a post (flat, D-P7), oldest first in its list.
nonisolated struct FeedComment: Identifiable, Equatable {
    /// UUIDv7, lower-case: sorting by it sorts by time.
    let id: String
    let postID: String
    let author: FeedAuthor
    /// Plain text, at most 1,000 characters; links are detected by `FeedTextBuilder`.
    let text: String
    /// The comment this one replies to, while the person may see it.
    let replyTo: FeedCommentReply?
    let createdAt: Date
    let state: FeedCommentState
    /// Only when `state` is `.held`.
    let heldReason: FeedHeldReason?
    let isAuthor: Bool
    /// They wrote it, or it is under their post.
    let canDelete: Bool
    /// Decision 265: set by the filter; the text is shown behind one "Show". Absent (an older server) is `false`.
    let isSensitive: Bool
}

nonisolated struct FeedCommentReply: Equatable {
    let id: String
    let author: FeedAuthor
}

nonisolated enum FeedCommentState: Equatable {
    case visible
    /// Seen by its author only: "Under review".
    case held
    /// Seen by its author only.
    case removed
    /// A state newer than this build: shown as "not available".
    case other(String)

    init(wireValue: String) {
        switch wireValue {
        case "visible": self = .visible
        case "held": self = .held
        case "removed": self = .removed
        default: self = .other(wireValue)
        }
    }
}

nonisolated struct FeedCommentPage: Equatable {
    let items: [FeedComment]
    /// The next (newer) page; `nil` at the end. A page may be empty and still have one.
    let nextCursor: String?
}

/// A post's likes as the server counted them after a like or an unlike.
nonisolated struct FeedLikes: Equatable {
    let likes: Int
    let liked: Bool
}

/// What the app sends into a chat to share a post, built by the server.
nonisolated struct FeedShareMessage: Equatable {
    /// The post's text, a blank line, and the line with the link, in `lang`.
    let body: String
    /// The post's shares (each person counts once).
    let shares: Int
}

/// The comment rules of `POST /feed/posts/{id}/comments`, measured as the server does.
nonisolated enum FeedCommentText {
    static let maximumLength = 1000
    /// The counter shows from here on.
    static let counterThreshold = 900

    static func length(of text: String) -> Int {
        FeedPostText.length(of: text)
    }

    static func isPostable(_ text: String) -> Bool {
        let length = length(of: text)
        return length > 0 && length <= maximumLength
    }
}
