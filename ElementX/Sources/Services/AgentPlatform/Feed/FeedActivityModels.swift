//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Lane I5 on B6's contract (decision 287):
// what others do with what the person wrote (likes grouped, comments,
// replies) and who liked a post, as the app owns
// them. Kept in memory only: nothing here is written to the device.
//

import Foundation

/// What an activity entry is about. An entry of a kind newer than this build is skipped (decision 96).
nonisolated enum FeedActivityKind: Equatable {
    /// The likes on one of the person's posts in one UTC day.
    case like
    /// A comment under one of the person's posts.
    case comment
    /// A reply to one of the person's comments.
    case reply

    init?(wireValue: String) {
        switch wireValue {
        case "like": self = .like
        case "comment": self = .comment
        case "reply": self = .reply
        default: return nil
        }
    }
}

nonisolated struct FeedActivityEntry: Identifiable, Equatable {
    /// Stable across pages and pushes (`like:<post>:<day>`, `comment:<id>`, `reply:<id>`): the dedupe key.
    let id: String
    let kind: FeedActivityKind
    /// A like group's newest like; a comment's creation.
    let at: Date
    let postID: String
    /// The comment of a `comment` or `reply`: the post opens at it.
    let commentID: String?
    /// Newest first: up to three likers, or the comment's author. Never empty on the wire.
    let actors: [FeedAuthor]
    /// Everyone in a like group (1 for a comment); it may count people no longer shown.
    let total: Int
    /// The comment's text, one line (`comment`, `reply`).
    let preview: String?
    /// The post's text, one line.
    let postPreview: String
    /// The comment or the post is sensitive: the previews stay behind "Show".
    let isSensitive: Bool
    var isUnread: Bool

    /// "and N others": the group's people not shown by name.
    var othersCount: Int {
        max(0, total - 1)
    }
}

nonisolated struct FeedActivityPage: Equatable {
    /// Newest first, kinds this build knows only.
    let items: [FeedActivityEntry]
    /// The next (older) page; `nil` at the end. A page may be empty and still have one.
    let nextCursor: String?
    /// Unread entries, at most 99: the badge.
    let unread: Int
    /// The newest entry the server sent, a kind this build skips included: the seen mark goes up to it.
    let newestAt: Date?

    init(items: [FeedActivityEntry], nextCursor: String?, unread: Int, newestAt: Date? = nil) {
        self.items = items
        self.nextCursor = nextCursor
        self.unread = unread
        self.newestAt = [newestAt, items.map(\.at).max()].compactMap(\.self).max()
    }
}

/// One person who liked a post.
nonisolated struct FeedLiker: Identifiable, Equatable {
    let author: FeedAuthor
    let likedAt: Date

    var id: String {
        author.userID
    }
}

nonisolated struct FeedLikersPage: Equatable {
    /// Newest first.
    let items: [FeedLiker]
    /// The next (older) page; `nil` at the end. A page may be empty and still have one.
    let nextCursor: String?
}

/// Who an engagement push reaches (decision 287): a string on the wire, so
/// "following" can join with follows; a newer value shows as it is.
nonisolated enum FeedPushAudience: Hashable {
    case everyone
    case off
    /// A value newer than this build: shown, not offered (decision 96).
    case other(String)

    init(wireValue: String) {
        switch wireValue {
        case "everyone": self = .everyone
        case "off": self = .off
        default: self = .other(wireValue)
        }
    }

    var wireValue: String {
        switch self {
        case .everyone: "everyone"
        case .off: "off"
        case .other(let value): value
        }
    }
}

/// The person's feed push settings, per kind (decisions 266, 287). Notices always push.
nonisolated struct FeedNotificationSettings: Equatable {
    var likes: FeedPushAudience
    var comments: FeedPushAudience
    var replies: FeedPushAudience
}
