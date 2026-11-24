//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: platform sync (decision 289, `DESIGNS/platform-sync-contract.md`
// § 4–5, the backend's `SyncReady` / `SyncChanges` / `SyncLimited` /
// `SyncChange`). The frames of `GET /api/v1/sync` as the app owns them; each
// frame's SSE `id` is its `position`. A change
// names what changed, by id; only the values that are the same for every
// viewer (a post's counts and state) come in it. A kind this build does not
// know, or one it cannot read, is skipped (decision 96).
//

import Foundation

/// A frame of the sync stream the app acts on (keepalives never reach here).
nonisolated enum PlatformSyncEvent: Equatable {
    /// The stream is subscribed at `position`. `fresh` (no `since` was sent):
    /// re-read what is shown, then follow from here.
    case ready(position: String, fresh: Bool)
    /// One flush: the changes after the last position, coalesced per kind and subject.
    case changes(position: String, changes: [PlatformChange])
    /// `since` is older than the log keeps: re-read what is shown, continue from `position`.
    case limited(position: String)

    /// A frame by its `event` and `data`; `nil` for one this build does not know or cannot read.
    init?(event: String?, data: String?) {
        guard let data = data?.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        switch event {
        case "ready":
            guard let wire = try? decoder.decode(WireReady.self, from: data) else { return nil }
            self = .ready(position: wire.position.value, fresh: wire.fresh)
        case "changes":
            guard let wire = try? decoder.decode(WireChanges.self, from: data) else { return nil }
            self = .changes(position: wire.position.value, changes: wire.changes.compactMap(\.change))
        case "limited":
            guard let wire = try? decoder.decode(WirePosition.self, from: data) else { return nil }
            self = .limited(position: wire.position.value)
        default:
            return nil
        }
    }

    var position: String {
        switch self {
        case .ready(let position, _), .changes(let position, _), .limited(let position): position
        }
    }

    private struct WireReady: Decodable {
        let position: WirePositionValue
        let fresh: Bool
    }

    private struct WirePosition: Decodable {
        let position: WirePositionValue
    }

    private struct WireChanges: Decodable {
        let position: WirePositionValue
        /// One that does not decode is skipped, not the whole frame.
        let changes: [Lenient<PlatformChange>]
    }
}

/// The position is opaque: a string on the wire, a number taken as one too.
private nonisolated struct WirePositionValue: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else {
            value = try String(container.decode(Int64.self))
        }
    }
}

private nonisolated struct Lenient<Value: Decodable>: Decodable {
    let change: Value?

    init(from decoder: Decoder) throws {
        change = try? Value(from: decoder)
    }
}

/// One change of the log, by kind; ids lower-cased like every post id the app holds.
nonisolated enum PlatformChange: Equatable, Decodable {
    case feed(FeedSyncChange)
    /// The Agents tab's kinds (`agent.*`, `space.*`, `approval.*`, …; lane I7).
    case agents(AgentsSyncChange)
    /// A kind newer than this build, or one missing what it must name: nothing here acts on it.
    case other(kind: String)

    var kind: String {
        switch self {
        case .feed(let change): change.kind
        case .agents(let change): change.kind
        case .other(let kind): kind
        }
    }

    init(from decoder: Decoder) throws {
        let wire = try WireChange(from: decoder)
        if let change = wire.feedChange {
            self = .feed(change)
        } else if let change = AgentsSyncChange(kind: wire.kind, ids: wire.agentsIDs) {
            self = .agents(change)
        } else {
            self = .other(kind: wire.kind)
        }
    }

    private struct WireChange: Decodable {
        let kind: String
        let post: String?
        let author: String?
        let state: String?
        let likes: Int?
        let comments: Int?
        let shares: Int?
        let comment: String?
        let parent: String?
        let liked: Bool?
        // The Agents tab's ids.
        let agent: String?
        let space: String?
        let room: String?
        let approval: String?
        let verification: String?
        let message: String?

        var agentsIDs: AgentsSyncChange.IDs {
            AgentsSyncChange.IDs(agent: agent, space: space, room: room, approval: approval, verification: verification, message: message)
        }

        /// `nil` for a kind that is not the feed's, or one missing what it must name.
        var feedChange: FeedSyncChange? {
            let postID = post?.lowercased()
            switch kind {
            case "feed.post_published":
                guard let postID, let author else { return nil }
                return .postPublished(postID: postID, authorID: author)
            case "feed.post_state":
                guard let postID, let state else { return nil }
                return .postState(postID: postID, state: FeedPostState(wireValue: state))
            case "feed.post_updated":
                guard let postID else { return nil }
                return .postUpdated(postID: postID)
            case "feed.counts":
                guard let postID, let likes, let comments, let shares else { return nil }
                return .counts(postID: postID, counts: FeedCounts(likes: likes, comments: comments, shares: shares))
            case "feed.comment_added":
                guard let postID else { return nil }
                return .commentAdded(postID: postID, commentID: comment?.lowercased())
            case "feed.comment_removed":
                guard let postID else { return nil }
                return .commentRemoved(postID: postID, commentID: comment?.lowercased())
            case "feed.viewer_like":
                guard let postID, let liked else { return nil }
                return .viewerLike(postID: postID, liked: liked)
            case "feed.hidden":
                guard let postID else { return nil }
                return .hidden(postID: postID)
            case "feed.unhidden":
                guard let postID else { return nil }
                return .unhidden(postID: postID)
            case "feed.blocks":
                return .blocks
            case "feed.activity":
                return .activity
            case "feed.notice":
                return .notice
            default:
                return nil
            }
        }
    }
}

/// The feed's kinds (contract § 5, Feed).
nonisolated enum FeedSyncChange: Equatable {
    case postPublished(postID: String, authorID: String)
    /// Mapped for this viewer (§ 4): the author sees the real state, anyone
    /// else `visible` or `gone`, which arrives as `.other("gone")` and is "not available".
    case postState(postID: String, state: FeedPostState)
    /// The author changed the post (the comment switch): re-read it.
    case postUpdated(postID: String)
    case counts(postID: String, counts: FeedCounts)
    case commentAdded(postID: String, commentID: String?)
    case commentRemoved(postID: String, commentID: String?)
    /// The person's own like, from this or another device.
    case viewerLike(postID: String, liked: Bool)
    case hidden(postID: String)
    case unhidden(postID: String)
    /// The person's own blocks changed: their lists re-read.
    case blocks
    /// The person's activity changed.
    case activity
    /// The person has a new or changed moderation notice.
    case notice

    var kind: String {
        switch self {
        case .postPublished: "feed.post_published"
        case .postState: "feed.post_state"
        case .postUpdated: "feed.post_updated"
        case .counts: "feed.counts"
        case .commentAdded: "feed.comment_added"
        case .commentRemoved: "feed.comment_removed"
        case .viewerLike: "feed.viewer_like"
        case .hidden: "feed.hidden"
        case .unhidden: "feed.unhidden"
        case .blocks: "feed.blocks"
        case .activity: "feed.activity"
        case .notice: "feed.notice"
        }
    }
}

/// The events of one opened stream, until the server ends it or it fails.
typealias PlatformSyncEventStream = AsyncThrowingStream<PlatformSyncEvent, Error>

nonisolated enum PlatformSyncError: Error, Equatable {
    /// No sync route on this backend (the router's 404).
    case unavailable
    case unauthorized
    /// `400`: `since` is not a position this server gave out; start without one.
    case invalidPosition
    /// `429`: the read window or the stream cap; `Retry-After` when sent.
    case rateLimited(retryAfterSeconds: Int?)
    case temporarilyUnavailable(retryAfterSeconds: Int?)
    case server(status: Int)
    /// No network: offline, the host not found or not reached, the connection lost or timed out.
    case transport
    /// TLS refused a certificate, the server's or ours: the network is there.
    case untrustedServer
    /// The exchange failed otherwise (the handshake, an answer that did not decode): the network is there.
    case badResponse

    /// An answer waiting does not change: a `401` after the retry, a `403`, a proxy's `404`, another `4xx`, a certificate refused.
    var isRefusal: Bool {
        switch self {
        case .unauthorized, .invalidPosition, .untrustedServer: true
        case .server(let status): (400..<500).contains(status) && status != 408
        case .unavailable, .rateLimited, .temporarilyUnavailable, .transport, .badResponse: false
        }
    }
}
