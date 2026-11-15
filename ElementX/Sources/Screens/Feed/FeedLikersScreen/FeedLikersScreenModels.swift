//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Who liked a post (lane I5, decision
// 287: visible to everyone; blocks hide both ways on the server), newest
// first, opened from the count on a card or the post. A tap on a person opens
// their author sheet.
//

import Foundation

enum FeedLikersScreenViewModelAction {
    case openAuthor(FeedAuthor)
}

enum FeedLikersListState: Equatable {
    case loading
    case loaded([FeedLiker], loadMore: LoadMoreState)
    /// The post is not there for the person any more.
    case notAvailable
    /// `FEED_MODE=off`.
    case unavailable
    /// The first page could not be read: never shown as "no likes".
    case failed
}

struct FeedLikersScreenViewState: BindableState {
    var listState: FeedLikersListState = .loading
    /// The person's ignore list, applied at once, before the next read.
    var blockedUserIDs: Set<String> = []
    /// "Updating…" or "No connection" at the top (decision 289).
    var syncStatus: PlatformSyncStatus?

    var likers: [FeedLiker] {
        guard case .loaded(let likers, _) = listState else { return [] }
        return likers.filter { !blockedUserIDs.contains($0.author.userID) }
    }

    var sentinel: LoadMoreState? {
        guard case .loaded(_, let loadMore) = listState, loadMore != .exhausted else { return nil }
        return loadMore
    }

    /// Only a read that reached its end with nobody in it is "No likes yet".
    var isEmpty: Bool {
        guard case .loaded(_, .exhausted) = listState else { return false }
        return likers.isEmpty
    }
}

enum FeedLikersScreenViewAction {
    /// Shown: read again when the post's likes move (`feed.counts`).
    case appeared
    case disappeared
    case retry
    case loadMore
    case openAuthor(userID: String)
}
