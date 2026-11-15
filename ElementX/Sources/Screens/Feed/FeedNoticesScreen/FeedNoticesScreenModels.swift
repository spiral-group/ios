//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The person's feed notices, newest
// first (lane I3, arch § 5.11): statements of reasons about their posts,
// comments and account, and the receipts and decisions of their reports.
// The Agents hub's sections are fixed, so the notices have their own screen
// under the Feed tab.
//

import Foundation

enum FeedNoticesScreenViewModelAction {
    case openPost(postID: String)
}

/// A notice with its words prepared once.
struct FeedNoticeItem: Identifiable, Equatable {
    var notice: FeedNotice
    let content: FeedNoticeContent

    init(notice: FeedNotice) {
        self.notice = notice
        content = FeedNoticeContent(notice: notice)
    }

    var id: String {
        notice.id
    }
}

enum FeedNoticesListState: Equatable {
    case loading
    case loaded([FeedNoticeItem], loadMore: LoadMoreState)
    /// `FEED_MODE=off`.
    case unavailable
    /// The first page could not be read: never shown as "no notices".
    case failed
}

struct FeedNoticesScreenViewState: BindableState {
    var listState: FeedNoticesListState = .loading
    /// "Updating…" or "No connection" at the top, in place of pull to refresh (decision 289).
    var syncStatus: PlatformSyncStatus?

    var items: [FeedNoticeItem] {
        if case .loaded(let items, _) = listState { items } else { [] }
    }

    var sentinel: LoadMoreState? {
        guard case .loaded(_, let loadMore) = listState, loadMore != .exhausted else { return nil }
        return loadMore
    }

    /// Only a read that reached its end with nothing in it is "No notices".
    var isEmpty: Bool {
        guard case .loaded(let items, .exhausted) = listState else { return false }
        return items.isEmpty
    }
}

enum FeedNoticesScreenViewAction {
    /// Shown: read again on `feed.notice` from the sync stream.
    case appeared
    case disappeared
    /// The failed state's Retry.
    case retry
    case loadMore
    /// A notice came on screen: an unread one is marked read.
    case noticeAppeared(noticeID: String)
    case openPost(postID: String)
}
