//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The author sheet: name, avatar, the
// official label, the bio (plain text, decision 255 reversed), their posts,
// Message, Block and Report. Spiral's official account has Report only:
// nobody reads its chats, and it is Spiral's own voice, not a stranger's.
//

import Foundation

enum FeedAuthorScreenViewModelAction {
    case openRoom(roomID: String)
    case openPost(FeedPost)
    /// The person, or one of their posts (lane I3 on B4).
    case report(FeedReportTarget)
    case dismiss
}

enum FeedAuthorPostsState: Equatable {
    case loading
    case loaded([FeedItem], loadMore: LoadMoreState)
    /// `404` (they block the person, or the account is not shown) or `400` (not a local account).
    case notAvailable
    case unavailable
    /// Could not be read: never shown as "no posts".
    case failed
}

struct FeedAuthorScreenViewState: BindableState {
    let author: FeedAuthor
    /// The person's own sheet has no Message, Block or Report.
    let isOwnProfile: Bool
    var postsState: FeedAuthorPostsState = .loading
    var isBlocked = false
    var revealedPostIDs: Set<String> = []
    /// Hidden until the person's media setting is read.
    var hidesMedia = true
    /// Reading on past empty pages stopped at its limit: the bottom row is a tap, not a sentinel.
    var isReadOnPaused = false
    /// "Updating…" or "No connection" at the top (decision 289).
    var syncStatus: PlatformSyncStatus?
    var bindings = FeedAuthorScreenViewStateBindings()

    /// Not on the person's own sheet, not for an author whose name the feed
    /// withheld (a chat would show the real display name, decision 272), and not
    /// for Spiral's official account, whose chats nobody reads (operator, 2026-11-13).
    var canMessage: Bool {
        !isOwnProfile && !author.isNameWithheld && !author.isOfficial
    }

    /// Blocking the official account would ignore Spiral itself everywhere; Hide and Report stay on its posts.
    var canBlock: Bool {
        !isOwnProfile && !author.isOfficial
    }

    var sentinel: LoadMoreState? {
        guard case .loaded(_, let loadMore) = postsState, loadMore != .exhausted else { return nil }
        return loadMore
    }

    /// Only a read that reached its end with nothing in it is "No posts yet".
    var isEmpty: Bool {
        guard case .loaded(let items, .exhausted) = postsState else { return false }
        return items.isEmpty
    }
}

struct FeedAuthorScreenViewStateBindings {
    var alertInfo: AlertInfo<FeedAuthorScreenAlertType>?
    var mediaPreviewItem: MediaPreviewItem?
}

enum FeedAuthorScreenAlertType: Hashable {
    case confirmBlock
    case blockFailed
    case confirmUnblock
    case unblockFailed
    case confirmStartChat
    case chatFailed
}

enum FeedAuthorScreenViewAction {
    /// Shown: read again when the sync says the author's posts changed.
    case appeared
    case disappeared
    case retry
    case loadMore
    case message
    case block
    case unblock
    case report
    case dismiss
    case card(postID: String, FeedPostCardAction)
}
