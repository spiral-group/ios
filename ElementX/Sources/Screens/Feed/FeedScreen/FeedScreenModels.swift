//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The Feed tab's root: Latest, newest
// first, with the pinned rules post on top (D-P1), the "N new posts" pill,
// the person's posts on their way (decision 289) and the sync's state.
//

import Foundation

enum FeedScreenViewModelAction {
    case openPost(FeedPost)
    case openAuthor(FeedAuthor)
    /// Lane I2: the composer, and the person's own posts (held ones included).
    case compose
    case openOwnPosts
    /// Lane I3: the chat picker for this post.
    case share(FeedPost)
    /// Lane I3 on B4: the report screen.
    case report(FeedReportTarget)
    /// Activity behind the bell, with the notices a tap further (lane I5).
    case openActivity
    /// Who liked the post (lane I5).
    case openLikers(postID: String)
    /// A post sent again from Latest was made: visible, or held for review.
    case published(FeedPost)
}

/// A post with the card prepared for it.
struct FeedItem: Identifiable, Equatable {
    let post: FeedPost
    let card: FeedPostCardModel

    init(post: FeedPost) {
        self.post = post
        card = FeedPostCardModel(post: post)
    }

    var id: String {
        post.id
    }
}

enum FeedListState: Equatable {
    case loading
    case loaded([FeedItem], loadMore: LoadMoreState)
    /// The first page could not be read; the one kept from the last read is shown.
    case offline([FeedItem])
    /// `FEED_MODE=off`: "Feed is unavailable".
    case unavailable
    /// The first page could not be read and none was kept: never shown as an empty feed.
    case failed
}

/// What Latest's last first page said of its pinned post.
enum FeedLastPinned: Equatable {
    /// Never read on this device: Latest opens on its pinned rules post, so one is expected.
    case unknown
    case none
    case post(authorID: String)

    init(_ page: FeedPage) {
        self = page.pinned.map { .post(authorID: $0.author.userID) } ?? .none
    }
}

struct FeedScreenViewState: BindableState {
    /// The person's own profile, for the bar's button to Own posts (Brief 0083).
    var ownProfile: UserProfile?
    var listState: FeedListState = .loading
    var pinned: FeedItem?
    /// The pinned post the last first page read on this device had, for the placeholder while the next one loads.
    var lastPinned = FeedLastPinned.unknown
    /// The person's ignore list; their posts vanish at once, before the next read.
    var blockedUserIDs: Set<String> = []
    /// Sensitive posts the person chose to see.
    var revealedPostIDs: Set<String> = []
    /// The person's media setting: the feed is public, so only "always" loads
    /// images. Hidden until the setting is read.
    var hidesMedia = true
    /// `feed.post_published` since Latest was read (the store's); the pill shows while it is above zero.
    var newPostsCount = 0
    /// The person's posts the server has not taken yet, newest first.
    var pendingPosts: [FeedPendingPost] = []
    /// "Updating…" or "No connection" at the top while the sync stream is not live.
    var syncStatus: PlatformSyncStatus?
    /// Bumped to ask the list to scroll back to its top.
    var scrollToTopRequest = 0
    /// Reading on past empty pages stopped at its limit: the bottom row is a tap, not a sentinel.
    var isReadOnPaused = false
    /// The unread notices as the server last counted them; `nil` until it has, and kept when a read fails.
    var unreadNotices: Int?
    /// The unread activity as the server last counted it (a page, the seen mark); `nil` until it has.
    var unreadActivity: Int?
    var bindings = FeedScreenViewStateBindings()

    /// The posts to show, without anyone the person blocks.
    var visibleItems: [FeedItem] {
        let items: [FeedItem] = switch listState {
        case .loaded(let items, _), .offline(let items): items
        case .loading, .unavailable, .failed: []
        }
        guard !blockedUserIDs.isEmpty else { return items }
        return items.filter { !blockedUserIDs.contains($0.post.author.userID) }
    }

    var visiblePinned: FeedItem? {
        pinned.flatMap { blockedUserIDs.contains($0.post.author.userID) ? nil : $0 }
    }

    /// The placeholder draws the pinned card only where one should come in, so the posts don't move up when none does.
    var expectsPinned: Bool {
        switch lastPinned {
        case .unknown: true
        case .none: false
        case .post(let authorID): !blockedUserIDs.contains(authorID)
        }
    }

    /// The bottom sentinel; `nil` at the end or when nothing pages.
    var sentinel: LoadMoreState? {
        guard case .loaded(_, let loadMore) = listState, loadMore != .exhausted else { return nil }
        return loadMore
    }

    /// Only a read that reached its end with nothing to show is "Be the first today".
    var isEmpty: Bool {
        guard case .loaded(_, .exhausted) = listState else { return false }
        return visibleItems.isEmpty && visiblePinned == nil && pendingPosts.isEmpty
    }

    var isOffline: Bool {
        if case .offline = listState { true } else { false }
    }

    /// The bell's badge: unread activity and unread notices together.
    var bellUnread: Int {
        (unreadActivity ?? 0) + (unreadNotices ?? 0)
    }

    /// "Activity", with the unread count once the server gave one.
    var bellAccessibilityLabel: String {
        bellUnread > 0 ? UntranslatedL10n.a11yFeedActivityUnread(bellUnread) : UntranslatedL10n.screenFeedActivityTitle
    }

    /// "99+" at the server's cap.
    var newPostsPillTitle: String? {
        guard newPostsCount > 0 else { return nil }
        return newPostsCount >= FeedScreenViewModel.headCap ? UntranslatedL10n.screenFeedNewPostsMany : UntranslatedL10n.screenFeedNewPosts(newPostsCount)
    }
}

struct FeedScreenViewStateBindings {
    var mediaPreviewItem: MediaPreviewItem?
}

enum FeedScreenViewAction {
    case appeared
    case disappeared
    /// Pull to refresh (Latest is the one list that keeps it, decision 289), and the retry of a failed first page.
    case refresh
    case loadMore
    /// The "N new posts" pill: a fresh first page, never prepended to the live list.
    case showNewPosts
    case card(postID: String, FeedPostCardAction)
    case compose
    case openOwnPosts
    case openActivity
    /// A post on its way that failed.
    case retryPost(UUID)
    case discardPost(UUID)
}
