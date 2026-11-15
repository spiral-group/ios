//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082, decision 289). Latest: paging, the
// pinned post, the "N new posts" pill counted from the sync stream, the
// offline first page, a read again that keeps the person's place, the posts on
// their way, and a block that hides at once.
//

import Combine
import Foundation
@testable import Spiral
import Testing
import UIKit

@MainActor
struct FeedScreenViewModelTests {
    private let service = FeedServiceMock()
    private let ignoredUsers = CurrentValueSubject<[String]?, Never>([])
    private let clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md"))

    private let engagement: FeedEngagementController

    init() {
        engagement = .make(service)
        // Lane I3 on B4: the notices behind the badge and a held post's banner.
        service.noticesUnreadPublisher = Empty().eraseToAnyPublisher()
        service.activityUnreadPublisher = Empty().eraseToAnyPublisher()
        service.noticesCursorLimitLanguageReturnValue = .success(FeedNoticePage(items: [], nextCursor: nil, unread: 0))
        clientProxy.ignoredUsersPublisher = ignoredUsers.asCurrentValuePublisher()
        service.cachedFirstPageReturnValue = nil
        service.draftReturnValue = nil
        // `ready.fresh` reads the bell's counts too.
        service.activityCursorLimitReturnValue = .success(FeedActivityPage(items: [], nextCursor: nil, unread: 0))
    }

    private var store: FeedStore {
        engagement.store
    }

    private func makeViewModel() -> FeedScreenViewModel {
        FeedScreenViewModel(feedService: service,
                            engagement: engagement,
                            clientProxy: clientProxy,
                            mediaProvider: MediaProviderMock(.init()),
                            userIndicatorController: UserIndicatorControllerMock())
    }

    private func loadedViewModel() async throws -> FeedScreenViewModel {
        let viewModel = makeViewModel()
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            switch state {
            case .loading: false
            case .loaded(_, let loadMore): loadMore != .loading
            default: true
            }
        }
        try await loaded.fulfill()
        return viewModel
    }

    // MARK: - The person's own photo

    /// A name or photo changed elsewhere reaches a Feed already open.
    @Test
    func theOwnProfileFollowsAChangedProfile() async throws {
        service.latestCursorLimitReturnValue = .success(FeedPage(items: [], nextCursor: nil, pinned: nil))
        let profile = CurrentValueSubject<UserProfile, Never>(UserProfile(userID: "@me:spiral.md", displayName: "Before"))
        clientProxy.userProfilePublisher = profile.asCurrentValuePublisher()
        let viewModel = try await loadedViewModel()
        #expect(viewModel.context.viewState.ownProfile?.displayName == "Before")

        let changed = deferFulfillment(viewModel.context.observe(\.viewState.ownProfile)) { $0?.displayName == "After" }
        profile.send(UserProfile(userID: "@me:spiral.md", displayName: "After"))
        try await changed.fulfill()
    }

    // MARK: - First page

    @Test
    func theFirstPageShowsNewestFirst() async throws {
        let posts = FeedPreviewData.posts(3)
        service.latestCursorLimitReturnValue = .success(FeedPage(items: posts, nextCursor: "c1", pinned: nil))

        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.visibleItems.map(\.post) == posts)
        #expect(viewModel.context.viewState.sentinel == .idle(cursor: "c1"))
        #expect(service.latestCursorLimitReceivedArguments?.cursor == nil)
        #expect(service.latestCursorLimitReceivedArguments?.limit == FeedScreenViewModel.pageSize)
    }

    @Test
    func aFinishedEmptyReadIsBeTheFirst() async throws {
        service.latestCursorLimitReturnValue = .success(FeedPage(items: [], nextCursor: nil, pinned: nil))

        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.isEmpty)
    }

    /// Contract note from B1a's review: an empty page with a cursor is not the
    /// end. The app reads on and never shows "Be the first today" for it.
    @Test
    func anEmptyPageWithACursorIsReadPast() async throws {
        let posts = FeedPreviewData.posts(2)
        service.latestCursorLimitClosure = { cursor, _ in
            switch cursor {
            case nil: .success(FeedPage(items: [], nextCursor: "c1", pinned: nil))
            case "c1": .success(FeedPage(items: [], nextCursor: "c2", pinned: nil))
            default: .success(FeedPage(items: posts, nextCursor: nil, pinned: nil))
            }
        }

        let viewModel = makeViewModel()
        let shown = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            if case .loaded(let items, .exhausted) = state { items.count == 2 } else { false }
        }
        try await shown.fulfill()

        #expect(viewModel.context.viewState.isEmpty == false)
        #expect(service.latestCursorLimitCallsCount == 3)
    }

    /// A failed read with nothing kept is a failure with a retry, never an empty feed.
    @Test
    func aFailedReadIsNotAnEmptyFeed() async throws {
        service.latestCursorLimitReturnValue = .failure(.transport)

        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.listState == .failed)
        #expect(viewModel.context.viewState.isEmpty == false)
    }

    @Test
    func aFailedReadShowsTheKeptFirstPageOffline() async throws {
        service.latestCursorLimitReturnValue = .failure(.transport)
        service.cachedFirstPageReturnValue = FeedPage(items: FeedPreviewData.posts(2), nextCursor: "c1", pinned: nil)

        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.isOffline)
        #expect(viewModel.context.viewState.visibleItems.count == 2)
        #expect(viewModel.context.viewState.sentinel == nil, "an offline page does not page")
    }

    @Test
    func theFeedSwitchedOffIsUnavailableEvenWithAKeptPage() async throws {
        service.latestCursorLimitReturnValue = .failure(.unavailable)
        service.cachedFirstPageReturnValue = FeedPage(items: FeedPreviewData.posts(2), nextCursor: nil, pinned: nil)

        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.listState == .unavailable)
    }

    @Test
    func aFailedRefreshKeepsWhatWasShown() async throws {
        service.latestCursorLimitReturnValue = .success(FeedPage(items: FeedPreviewData.posts(2), nextCursor: nil, pinned: nil))
        let viewModel = try await loadedViewModel()

        service.latestCursorLimitReturnValue = .failure(.server(status: 500))
        await viewModel.loadFirstPage()

        #expect(viewModel.context.viewState.visibleItems.count == 2)
        #expect(viewModel.context.viewState.isOffline == false)
    }

    /// The authors could not be read: one retry after the server's `Retry-After`.
    @Test
    func aTemporaryRefusalIsRetriedOnce() async throws {
        let posts = FeedPreviewData.posts(1)
        service.latestCursorLimitClosure = { [service] _, _ in
            service.latestCursorLimitCallsCount == 1 ? .failure(.temporarilyUnavailable(retryAfterSeconds: 0)) : .success(FeedPage(items: posts, nextCursor: nil, pinned: nil))
        }

        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.visibleItems.map(\.post) == posts)
        #expect(service.latestCursorLimitCallsCount == 2)
    }

    @Test
    func aSecondTemporaryRefusalIsAFailureNotAnEmptyFeed() async throws {
        service.latestCursorLimitReturnValue = .failure(.temporarilyUnavailable(retryAfterSeconds: 0))

        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.listState == .failed)
        #expect(service.latestCursorLimitCallsCount == 2)
    }

    @Test
    func theRetryWaitsWhatTheServerSaysWithinBounds() {
        #expect(FeedScreenViewModel.retryDelay(retryAfterSeconds: nil) == .seconds(5))
        #expect(FeedScreenViewModel.retryDelay(retryAfterSeconds: -1) == .seconds(5))
        #expect(FeedScreenViewModel.retryDelay(retryAfterSeconds: 0) == .zero)
        #expect(FeedScreenViewModel.retryDelay(retryAfterSeconds: 7) == .seconds(7))
        #expect(FeedScreenViewModel.retryDelay(retryAfterSeconds: 3600) == .seconds(30))
    }

    // MARK: - Pinned

    @Test
    func thePinnedPostIsOnTopAndNotRepeatedInTheList() async throws {
        let pinned = FeedPreviewData.officialPost
        let posts = FeedPreviewData.posts(2)
        service.latestCursorLimitReturnValue = .success(FeedPage(items: [pinned] + posts, nextCursor: nil, pinned: pinned))

        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.visiblePinned?.post == pinned)
        #expect(viewModel.context.viewState.visibleItems.map(\.post) == posts)
        #expect(viewModel.context.viewState.isEmpty == false)
    }

    /// The placeholder's pinned card stands in only for a pinned post that comes in (DEBT, Feed pinned card).
    @Test
    func theLoadingPlaceholderExpectsThePinnedPostTheLastReadHad() async throws {
        let pinned = FeedPreviewData.officialPost
        service.latestCursorLimitReturnValue = .failure(.transport)

        // Never read here: Latest opens on its rules post.
        #expect(makeViewModel().context.viewState.expectsPinned)

        service.cachedFirstPageReturnValue = FeedPage(items: FeedPreviewData.posts(2), nextCursor: nil, pinned: nil)
        #expect(makeViewModel().context.viewState.expectsPinned == false)

        service.cachedFirstPageReturnValue = FeedPage(items: FeedPreviewData.posts(2), nextCursor: nil, pinned: pinned)
        #expect(makeViewModel().context.viewState.expectsPinned)

        // Its author is blocked: it won't show.
        ignoredUsers.send([pinned.author.userID])
        let viewModel = makeViewModel()
        let blocked = deferFulfillment(viewModel.context.observe(\.viewState.expectsPinned)) { $0 == false }
        try await blocked.fulfill()
    }

    /// A read with no pinned post sets the next placeholder, before the page is kept on disk.
    @Test
    func aReadWithoutAPinnedPostDropsThePlaceholdersPinnedCard() async throws {
        service.cachedFirstPageReturnValue = FeedPage(items: [], nextCursor: nil, pinned: FeedPreviewData.officialPost)
        service.latestCursorLimitReturnValue = .success(FeedPage(items: FeedPreviewData.posts(2), nextCursor: nil, pinned: nil))

        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.lastPinned == .none)
        #expect(viewModel.context.viewState.expectsPinned == false)
    }

    // MARK: - Paging

    @Test
    func theNextPageIsAppendedWithoutRepeats() async throws {
        let first = FeedPreviewData.posts(3)
        let second = FeedPreviewData.posts(3, startingAt: 2) // Overlaps the last post of the first page.
        service.latestCursorLimitClosure = { cursor, _ in
            cursor == nil ? .success(FeedPage(items: first, nextCursor: "c1", pinned: nil)) : .success(FeedPage(items: second, nextCursor: nil, pinned: nil))
        }
        let viewModel = try await loadedViewModel()

        let appended = deferFulfillment(viewModel.context.observe(\.viewState.visibleItems.count)) { $0 == 5 }
        viewModel.context.send(viewAction: .loadMore)
        try await appended.fulfill()

        #expect(Set(viewModel.context.viewState.visibleItems.map(\.id)).count == 5)
        #expect(viewModel.context.viewState.sentinel == nil)
    }

    @Test
    func aStaleCursorStartsFromTheFirstPage() async throws {
        var calls: [String?] = []
        service.latestCursorLimitClosure = { cursor, _ in
            calls.append(cursor)
            if cursor == nil { return .success(FeedPage(items: FeedPreviewData.posts(1), nextCursor: "stale", pinned: nil)) }
            return .failure(.invalidCursor)
        }
        let viewModel = try await loadedViewModel()

        let reloaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { _ in calls.count == 3 }
        viewModel.context.send(viewAction: .loadMore)
        try await reloaded.fulfill()

        #expect(calls == [nil, "stale", nil])
    }

    @Test
    func aFailedNextPageKeepsItsCursorForARetry() async throws {
        service.latestCursorLimitClosure = { cursor, _ in
            cursor == nil ? .success(FeedPage(items: FeedPreviewData.posts(1), nextCursor: "c1", pinned: nil)) : .failure(.transport)
        }
        let viewModel = try await loadedViewModel()

        let failed = deferFulfillment(viewModel.context.observe(\.viewState.sentinel)) { $0 == .failed(cursor: "c1") }
        viewModel.context.send(viewAction: .loadMore)
        try await failed.fulfill()
    }

    /// Ten empty pages in a row stop the read-on; the row at the bottom is
    /// then a tap to read on, not a sentinel that has already appeared.
    @Test
    func aLongRunOfEmptyPagesWaitsForATap() async throws {
        var calls = 0
        service.latestCursorLimitClosure = { _, _ in
            calls += 1
            return .success(FeedPage(items: [], nextCursor: "c\(calls)", pinned: nil))
        }
        let viewModel = try await loadedViewModel()

        #expect(calls == 1 + FeedScreenViewModel.maxEmptyPagesInARow)
        #expect(viewModel.context.viewState.sentinel == .idle(cursor: "c\(calls)"))
        #expect(viewModel.context.viewState.isReadOnPaused)
        #expect(viewModel.context.viewState.isEmpty == false)

        let readOn = deferFulfillment(viewModel.context.observe(\.viewState.isReadOnPaused)) { _ in calls == 1 + 2 * FeedScreenViewModel.maxEmptyPagesInARow }
        viewModel.context.send(viewAction: .loadMore)
        try await readOn.fulfill()
        #expect(viewModel.context.viewState.isReadOnPaused)
    }

    // MARK: - Reading again

    /// Release day turns `FEED_MODE` from off to open: the tab that said
    /// "unavailable" reads again when it shows.
    @Test(arguments: [FeedError.unavailable, .transport])
    func aFirstPageThatDidNotLoadIsReadAgainOnAppear(error: FeedError) async throws {
        service.latestCursorLimitReturnValue = .failure(error)
        let viewModel = try await loadedViewModel()
        #expect(viewModel.context.viewState.listState == .unavailable || viewModel.context.viewState.listState == .failed)

        service.latestCursorLimitReturnValue = .success(FeedPage(items: FeedPreviewData.posts(1), nextCursor: nil, pinned: nil))
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.visibleItems.count)) { $0 == 1 }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()
    }

    @Test
    func anOfflineFirstPageIsReadAgainOnReturnToTheForeground() async throws {
        service.latestCursorLimitReturnValue = .failure(.transport)
        service.cachedFirstPageReturnValue = FeedPage(items: FeedPreviewData.posts(1), nextCursor: nil, pinned: nil)
        let viewModel = try await loadedViewModel()
        viewModel.context.send(viewAction: .appeared)
        // The re-read keeps the offline page on screen while it runs: wait for the read, not a change.
        for _ in 0..<200 where service.latestCursorLimitCallsCount < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        await Task.yield()
        #expect(viewModel.context.viewState.isOffline)

        service.latestCursorLimitReturnValue = .success(FeedPage(items: FeedPreviewData.posts(3), nextCursor: nil, pinned: nil))
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.visibleItems.count)) { $0 == 3 }
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await loaded.fulfill()
        #expect(viewModel.context.viewState.isOffline == false)
    }

    @Test
    func aLoadedFeedIsNotReadAgainOnAppear() async throws {
        service.latestCursorLimitReturnValue = .success(FeedPage(items: FeedPreviewData.posts(1), nextCursor: nil, pinned: nil))
        let viewModel = try await loadedViewModel()

        viewModel.context.send(viewAction: .appeared)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()

        #expect(service.latestCursorLimitCallsCount == 1)
    }

    // MARK: - New posts (the sync stream)

    /// Decision 289: the pill counts `feed.post_published`, not a poll: others' posts only, each once, none already shown.
    @Test
    func thePillCountsPostsPublishedOnTheStream() async throws {
        let posts = FeedPreviewData.posts(2)
        service.latestCursorLimitReturnValue = .success(FeedPage(items: posts, nextCursor: nil, pinned: nil))
        let viewModel = try await loadedViewModel()

        let three = deferFulfillment(viewModel.context.observe(\.viewState.newPostsCount)) { $0 == 3 }
        store.apply([.postPublished(postID: "n1", authorID: FeedPreviewData.bob.userID),
                     .postPublished(postID: "n2", authorID: FeedPreviewData.bob.userID),
                     .postPublished(postID: "n2", authorID: FeedPreviewData.bob.userID),
                     .postPublished(postID: "mine", authorID: "@me:spiral.md"),
                     .postPublished(postID: posts[0].id, authorID: posts[0].author.userID),
                     .postPublished(postID: "n3", authorID: FeedPreviewData.ann.userID)])
        try await three.fulfill()
        #expect(viewModel.context.viewState.newPostsPillTitle == UntranslatedL10n.screenFeedNewPosts(3))

        // One removed before it was shown leaves the count.
        let two = deferFulfillment(viewModel.context.observe(\.viewState.newPostsCount)) { $0 == 2 }
        store.apply([.postState(postID: "n1", state: .other("gone"))])
        try await two.fulfill()
    }

    @Test
    func thePillSaysNinetyNinePlusAtTheCap() async throws {
        service.latestCursorLimitReturnValue = .success(FeedPage(items: FeedPreviewData.posts(1), nextCursor: nil, pinned: nil))
        let viewModel = try await loadedViewModel()

        let many = deferFulfillment(viewModel.context.observe(\.viewState.newPostsCount)) { $0 == FeedScreenViewModel.headCap }
        store.apply((0..<120).map { .postPublished(postID: "n\($0)", authorID: FeedPreviewData.bob.userID) })
        try await many.fulfill()

        #expect(viewModel.context.viewState.newPostsPillTitle == UntranslatedL10n.screenFeedNewPostsMany)
    }

    /// The pill reads the first page afresh; nothing is prepended into the live list.
    @Test
    func tappingThePillReadsTheFirstPageAgain() async throws {
        let old = FeedPreviewData.posts(2, startingAt: 5)
        service.latestCursorLimitReturnValue = .success(FeedPage(items: old, nextCursor: "c1", pinned: nil))
        let viewModel = try await loadedViewModel()
        let fresh = FeedPreviewData.posts(4)
        store.apply(fresh.prefix(2).map { .postPublished(postID: $0.id, authorID: $0.author.userID) })
        #expect(viewModel.context.viewState.visibleItems.map(\.post) == old, "The stream never prepends into the list")

        service.latestCursorLimitReturnValue = .success(FeedPage(items: fresh, nextCursor: "c9", pinned: nil))
        let replaced = deferFulfillment(viewModel.context.observe(\.viewState.visibleItems.count)) { $0 == 4 }
        viewModel.context.send(viewAction: .showNewPosts)
        try await replaced.fulfill()

        #expect(viewModel.context.viewState.visibleItems.map(\.post) == fresh)
        #expect(viewModel.context.viewState.newPostsCount == 0)
        #expect(viewModel.context.viewState.scrollToTopRequest == 1)
        #expect(service.latestCursorLimitReceivedArguments?.cursor == nil)
    }

    // MARK: - Read again (`ready.fresh`, `limited`)

    /// Read again while shown, Latest keeps the person's place: shown posts get their new values,
    /// one gone from the page's span leaves, newer ones go to the pill, older pages stay.
    @Test
    func aReadAgainKeepsThePlaceAndPutsNewerPostsInThePill() async throws {
        let posts = FeedPreviewData.posts(6)
        service.latestCursorLimitClosure = { cursor, _ in
            cursor == nil
                ? .success(FeedPage(items: Array(posts[1...3]), nextCursor: "c1", pinned: nil))
                : .success(FeedPage(items: Array(posts[4...5]), nextCursor: nil, pinned: nil))
        }
        let viewModel = try await loadedViewModel()
        viewModel.context.send(viewAction: .loadMore)
        try await deferFulfillment(viewModel.context.observe(\.viewState.visibleItems.count)) { $0 == 5 }.fulfill()
        viewModel.context.send(viewAction: .appeared)

        let liked = posts[1].withCounts(likes: 8)
        service.latestCursorLimitClosure = { _, _ in
            // posts[0] is new above the top; posts[2] is gone (hidden, removed); posts[1] has a new count.
            .success(FeedPage(items: [posts[0], liked, posts[3]], nextCursor: "c2", pinned: nil))
        }
        store.markEverythingStale()
        await store.settle()

        #expect(viewModel.context.viewState.visibleItems.map(\.id) == [posts[1].id, posts[3].id, posts[4].id, posts[5].id])
        #expect(viewModel.context.viewState.visibleItems.first?.post.counts.likes == 8)
        #expect(viewModel.context.viewState.newPostsCount == 1)
        #expect(viewModel.context.viewState.sentinel == nil, "The read on of older pages stays where it was")
    }

    /// Fable H1: the next page was asked for before the post went (or was hidden elsewhere); its older copy does not bring it back.
    @Test(arguments: [FeedSyncChange.postState(postID: "01933f2a-0000-7000-8000-000000001003", state: .other("gone")),
                      .hidden(postID: "01933f2a-0000-7000-8000-000000001003")])
    func aNextPageInFlightDoesNotBringBackAPostTheStreamTookOut(change: FeedSyncChange) async throws {
        let posts = FeedPreviewData.posts(4)
        service.latestCursorLimitClosure = { [store] cursor, _ in
            guard cursor != nil else { return .success(FeedPage(items: Array(posts[0...2]), nextCursor: "c1", pinned: nil)) }
            // The change arrives while the page is on its way, and the page answers with the copy from before it.
            await MainActor.run { store.apply([change]) }
            return .success(FeedPage(items: [posts[3]], nextCursor: nil, pinned: nil))
        }
        #expect(posts[3].id == "01933f2a-0000-7000-8000-000000001003")
        let viewModel = try await loadedViewModel()

        viewModel.context.send(viewAction: .loadMore)
        try await deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == .loaded(Array(posts[0...2]).map(FeedItem.init), loadMore: .exhausted) }
            .fulfill()
        #expect(store.list(.latest)?.ids == posts[0...2].map(\.id))
    }

    /// `ready.fresh` and `limited` read again only what is shown: Latest off screen is read when it shows again.
    @Test
    func onlyWhatIsShownIsReadAgainAtOnce() async throws {
        service.latestCursorLimitReturnValue = .success(FeedPage(items: FeedPreviewData.posts(2), nextCursor: nil, pinned: nil))
        let viewModel = try await loadedViewModel()

        store.markEverythingStale()
        await store.settle()
        #expect(service.latestCursorLimitCallsCount == 1)

        viewModel.context.send(viewAction: .appeared)
        await store.settle()
        #expect(service.latestCursorLimitCallsCount == 2)

        // Read now: nothing more on the next show.
        viewModel.context.send(viewAction: .disappeared)
        viewModel.context.send(viewAction: .appeared)
        await store.settle()
        #expect(service.latestCursorLimitCallsCount == 2)
    }

    /// A failure is not an answer: a read again that fails leaves the list as shown, without a toast.
    @Test
    func aFailedReadAgainKeepsTheList() async throws {
        let posts = FeedPreviewData.posts(2)
        service.latestCursorLimitReturnValue = .success(FeedPage(items: posts, nextCursor: nil, pinned: nil))
        let viewModel = try await loadedViewModel()
        viewModel.context.send(viewAction: .appeared)
        service.latestCursorLimitReturnValue = .failure(.transport)

        store.markEverythingStale()
        await store.settle()

        #expect(viewModel.context.viewState.visibleItems.map(\.post) == posts)
        #expect(store.isStale(.latest))
    }

    // MARK: - Posts on their way (decision 289)

    /// A post shows at once as sending, then as the server made it at the top; a failure stays with Retry under its key.
    @Test
    func aPostShowsAtOnceAndAFailureStaysWithRetry() async throws {
        let posts = FeedPreviewData.posts(1, startingAt: 3)
        service.latestCursorLimitReturnValue = .success(FeedPage(items: posts, nextCursor: nil, pinned: nil))
        let viewModel = try await loadedViewModel()
        let key = UUID()
        service.draftReturnValue = FeedDraft(text: "Hello", idempotencyKey: key)
        var duringRequest: [FeedPendingPost] = []
        service.createPostTextIdempotencyKeyClosure = { _, _ in
            duringRequest = viewModel.context.viewState.pendingPosts
            return .failure(.transport)
        }

        await store.publishPost(text: "Hello", idempotencyKey: key)
        #expect(duringRequest.map(\.delivery) == [.sending])
        try await deferFulfillment(viewModel.context.observe(\.viewState.pendingPosts)) { $0.first?.delivery == .failed(.transport) }.fulfill()
        #expect(service.deleteDraftCallsCount == 0, "The draft stays until the server has the post")

        let made = FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000611", author: FeedPreviewData.ann, minutesAgo: 0, text: "Hello", isAuthor: true)
        service.createPostTextIdempotencyKeyClosure = nil
        service.createPostTextIdempotencyKeyReturnValue = .success(made)
        let published = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .published(let post) = action { post == made } else { false }
        }
        viewModel.context.send(viewAction: .retryPost(key))
        try await published.fulfill()

        let keys = service.createPostTextIdempotencyKeyReceivedInvocations.map(\.idempotencyKey)
        #expect(keys == [key, key])
        #expect(viewModel.context.viewState.pendingPosts.isEmpty)
        #expect(viewModel.context.viewState.visibleItems.map(\.id) == [made.id] + posts.map(\.id))
        #expect(service.deleteDraftCallsCount == 1)
    }

    /// A held post is not in Latest; Discard drops a failed one with its draft.
    @Test
    func aHeldPostIsNotInLatestAndDiscardDropsAFailedOne() async throws {
        service.latestCursorLimitReturnValue = .success(FeedPage(items: [], nextCursor: nil, pinned: nil))
        let viewModel = try await loadedViewModel()
        let held = FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000612", author: FeedPreviewData.ann, minutesAgo: 0,
                                        text: "Held", state: .held, isAuthor: true)
        service.createPostTextIdempotencyKeyReturnValue = .success(held)
        await store.publishPost(text: "Held", idempotencyKey: UUID())
        #expect(store.posts(in: .latest).isEmpty)

        let key = UUID()
        service.draftReturnValue = FeedDraft(text: "No", idempotencyKey: key)
        service.createPostTextIdempotencyKeyReturnValue = .failure(.linkRefused)
        await store.publishPost(text: "No", idempotencyKey: key)
        try await deferFulfillment(viewModel.context.observe(\.viewState.pendingPosts.count)) { $0 == 1 }.fulfill()

        viewModel.context.send(viewAction: .discardPost(key))
        try await deferFulfillment(viewModel.context.observe(\.viewState.pendingPosts.count)) { $0 == 0 }.fulfill()
        #expect(service.deleteDraftCallsCount == 1)
    }

    /// Refused over the rules, Retry opens the composer, whose draft has the same key.
    @Test
    func aPostRefusedOverTheRulesIsRetriedInTheComposer() async throws {
        service.latestCursorLimitReturnValue = .success(FeedPage(items: [], nextCursor: nil, pinned: nil))
        let viewModel = try await loadedViewModel()
        let key = UUID()
        service.createPostTextIdempotencyKeyReturnValue = .failure(.rulesNotAccepted(currentVersion: FeedRules.version))
        await store.publishPost(text: "First", idempotencyKey: key)

        let composes = deferFulfillment(viewModel.actionsPublisher) { if case .compose = $0 { true } else { false } }
        viewModel.context.send(viewAction: .retryPost(key))
        try await composes.fulfill()
        #expect(service.createPostTextIdempotencyKeyCallsCount == 1)
    }

    /// The sync's state shows at the top while the stream is not live.
    @Test
    func theConnectionStateShowsAtTheTop() async throws {
        service.latestCursorLimitReturnValue = .success(FeedPage(items: [], nextCursor: nil, pinned: nil))
        let viewModel = try await loadedViewModel()
        #expect(viewModel.context.viewState.syncStatus == nil)

        store.connectionState = .waiting(attempt: 2, isOffline: true)
        try await deferFulfillment(viewModel.context.observe(\.viewState.syncStatus)) { $0 == .noConnection }.fulfill()
        store.connectionState = .connecting
        try await deferFulfillment(viewModel.context.observe(\.viewState.syncStatus)) { $0 == .updating }.fulfill()
        store.connectionState = .live
        try await deferFulfillment(viewModel.context.observe(\.viewState.syncStatus)) { $0 == nil }.fulfill()
    }

    // MARK: - Blocks

    /// FD6: a block hides the person's posts at once, before the next read.
    @Test
    func aBlockHidesThePersonsPostsAtOnce() async throws {
        let bobs = FeedPreviewData.posts(2, startingAt: 10, author: FeedPreviewData.bob)
        service.latestCursorLimitReturnValue = .success(FeedPage(items: FeedPreviewData.posts(2) + bobs, nextCursor: nil, pinned: nil))
        let viewModel = try await loadedViewModel()
        #expect(viewModel.context.viewState.visibleItems.count == 4)

        let hidden = deferFulfillment(viewModel.context.observe(\.viewState.visibleItems.count)) { $0 == 2 }
        ignoredUsers.send([FeedPreviewData.bob.userID])
        try await hidden.fulfill()

        #expect(viewModel.context.viewState.visibleItems.allSatisfy { $0.post.author != FeedPreviewData.bob })
        #expect(service.latestCursorLimitCallsCount == 1, "no read was needed")
    }

    // MARK: - Cards

    @Test
    func aSensitivePostIsRevealedAsAWhole() async throws {
        service.latestCursorLimitReturnValue = .success(FeedPage(items: [FeedPreviewData.sensitivePost], nextCursor: nil, pinned: nil))
        let viewModel = try await loadedViewModel()
        let id = FeedPreviewData.sensitivePost.id
        let card = try #require(viewModel.context.viewState.visibleItems.first?.card)
        #expect(!card.accessibilityLabel(isRevealed: false).contains(FeedPreviewData.sensitivePost.content.text))

        viewModel.context.send(viewAction: .card(postID: id, .reveal))

        #expect(viewModel.context.viewState.revealedPostIDs == [id])
        #expect(card.accessibilityLabel(isRevealed: true).contains(FeedPreviewData.sensitivePost.content.text))
    }

    @Test
    func aCardOpensItsPostAndItsAuthor() async throws {
        let post = FeedPreviewData.textPost
        service.latestCursorLimitReturnValue = .success(FeedPage(items: [post], nextCursor: nil, pinned: nil))
        let viewModel = try await loadedViewModel()

        var actions: [String] = []
        let cancellable = viewModel.actionsPublisher.sink { action in
            switch action {
            case .openPost(let opened): actions.append("post \(opened.id)")
            case .openAuthor(let author): actions.append("author \(author.userID)")
            case .compose: actions.append("compose")
            case .openOwnPosts: actions.append("own posts")
            case .share(let shared): actions.append("share \(shared.id)")
            case .report(let target): actions.append("report \(target)")
            case .openActivity: actions.append("activity")
            case .openLikers(let postID): actions.append("likers \(postID)")
            case .published(let post): actions.append("published \(post.id)")
            }
        }
        viewModel.context.send(viewAction: .card(postID: post.id, .openPost))
        viewModel.context.send(viewAction: .card(postID: post.id, .openAuthor))

        #expect(actions == ["post \(post.id)", "author \(post.author.userID)"])
        _ = cancellable
    }

    @Test
    func aNotAvailableCardOpensNothing() async throws {
        let hidden = FeedPreviewData.post(id: FeedPreviewData.textPost.id, author: FeedPreviewData.ann, minutesAgo: 1, text: "x", state: .hiddenAuthor)
        service.latestCursorLimitReturnValue = .success(FeedPage(items: [hidden], nextCursor: nil, pinned: nil))
        let viewModel = try await loadedViewModel()

        var actions = 0
        let cancellable = viewModel.actionsPublisher.sink { _ in actions += 1 }
        viewModel.context.send(viewAction: .card(postID: hidden.id, .openPost))
        viewModel.context.send(viewAction: .card(postID: hidden.id, .openAuthor))

        #expect(actions == 0)
        _ = cancellable
    }

    /// Until the person's media setting is read, the feed's images stay hidden.
    @Test
    func mediaIsHiddenUntilTheSettingArrives() {
        service.latestCursorLimitReturnValue = .success(FeedPage(items: [], nextCursor: nil, pinned: nil))

        #expect(makeViewModel().context.viewState.hidesMedia)
    }

    /// The feed is public: a "private chats only" media setting does not load its images.
    @Test(arguments: [(TimelineMediaVisibility.always, false), (.privateOnly, true), (.never, true)])
    func thePersonsMediaSettingDecides(visibility: TimelineMediaVisibility, hides: Bool) async throws {
        clientProxy.timelineMediaVisibilityPublisher = CurrentValueSubject(visibility).asCurrentValuePublisher()
        service.latestCursorLimitReturnValue = .success(FeedPage(items: [], nextCursor: nil, pinned: nil))

        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.hidesMedia == hides)
    }

    // MARK: - The person's own posts (lane I2)

    @Test
    func aDeletedPostLeavesLatestAtOnce() async throws {
        let posts = FeedPreviewData.posts(2)
        service.latestCursorLimitReturnValue = .success(FeedPage(items: posts, nextCursor: nil, pinned: nil))
        let viewModel = try await loadedViewModel()

        let gone = deferFulfillment(viewModel.context.observe(\.viewState.visibleItems)) { $0.map(\.post) == [posts[1]] }
        store.removePost(posts[0].id)
        try await gone.fulfill()
    }

    /// `422 idempotency-key-reused`: an earlier version is published, which Latest, shown, reads in.
    @Test
    func anEarlierVersionPublishedIsReadIn() async throws {
        service.latestCursorLimitReturnValue = .success(FeedPage(items: [], nextCursor: nil, pinned: nil))
        let viewModel = try await loadedViewModel()
        viewModel.context.send(viewAction: .appeared)

        let earlier = FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000603", author: FeedPreviewData.ann, minutesAgo: 1,
                                           text: "Earlier", isAuthor: true)
        service.latestCursorLimitReturnValue = .success(FeedPage(items: [earlier], nextCursor: nil, pinned: nil))
        service.createPostTextIdempotencyKeyReturnValue = .failure(.idempotencyKeyReused)
        let readIn = deferFulfillment(viewModel.context.observe(\.viewState.visibleItems)) { $0.map(\.post) == [earlier] }
        await store.publishPost(text: "Later", idempotencyKey: UUID())
        try await readIn.fulfill()
        // The text that was refused needs a key of its own; it waits with Retry.
        #expect(viewModel.context.viewState.pendingPosts.first?.delivery == .failed(.idempotencyKeyReused))
        #expect(service.saveDraftReceivedDraft?.text == "Later")
    }
}

/// Lane B5's per-account read window (30 reads per 10 s): every feed read may
/// answer `429` with `Retry-After`. A read nobody asked for waits and reads
/// once more; one the person asked for says "slow down". Either way what is on
/// screen stays, and a refusal is never "empty" or "not available".
@MainActor
struct FeedReadWindowTests {
    private let service = FeedServiceMock()
    private let clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md"))
    private let indicators = UserIndicatorControllerMock()

    private static let overTheWindow = FeedError.rateLimited(retryAfterSeconds: 0)
    private static let posts = FeedPreviewData.posts(2)
    private static let page = FeedPage(items: posts, nextCursor: nil, pinned: nil)

    init() {
        service.noticesUnreadPublisher = Empty().eraseToAnyPublisher()
        service.activityUnreadPublisher = Empty().eraseToAnyPublisher()
        service.noticesCursorLimitLanguageReturnValue = .success(FeedNoticePage(items: [], nextCursor: nil, unread: 0))
        service.cachedFirstPageReturnValue = nil
        service.commentsPostIDCursorLimitReturnValue = .success(FeedCommentPage(items: [], nextCursor: nil))
        service.draftReturnValue = nil
        clientProxy.ignoredUsersPublisher = CurrentValueSubject<[String]?, Never>([]).asCurrentValuePublisher()
    }

    private var slowDownToasts: Int {
        indicators.submitIndicatorDelayReceivedInvocations.count { $0.indicator.title == UntranslatedL10n.screenFeedSlowDown }
    }

    // MARK: - The rule

    @Test
    func theWaitIsTheServersWithinBounds() {
        #expect(FeedReadWindow.delay(retryAfterSeconds: 0) == .zero)
        #expect(FeedReadWindow.delay(retryAfterSeconds: 3) == .seconds(3))
        #expect(FeedReadWindow.delay(retryAfterSeconds: nil) == .seconds(5))
        #expect(FeedReadWindow.delay(retryAfterSeconds: 3600) == .seconds(30))
    }

    @Test
    func aReadNobodyAskedForIsTriedOnceMore() async {
        var calls = 0
        let read: () async -> Result<Int, FeedError> = {
            calls += 1
            return calls == 1 ? .failure(Self.overTheWindow) : .success(7)
        }
        #expect(await FeedReadWindow.retryingOnce(read) == .success(7))
        #expect(calls == 2)

        calls = 0
        #expect(await FeedReadWindow.retryingOnce { calls += 1; return Result<Int, FeedError>.failure(Self.overTheWindow) } == .failure(Self.overTheWindow))
        #expect(calls == 2)

        calls = 0
        #expect(await FeedReadWindow.retryingOnce { calls += 1; return Result<Int, FeedError>.failure(.transport) } == .failure(.transport))
        #expect(calls == 1)
    }

    // MARK: - Latest and the head

    private func feedViewModel() async throws -> FeedScreenViewModel {
        let viewModel = FeedScreenViewModel(feedService: service,
                                            engagement: .make(service),
                                            clientProxy: clientProxy,
                                            mediaProvider: MediaProviderMock(.init()),
                                            userIndicatorController: indicators)
        let settled = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            switch state {
            case .loading: false
            case .loaded(_, let loadMore): loadMore != .loading
            default: true
            }
        }
        try await settled.fulfill()
        return viewModel
    }

    @Test
    func latestIsReadAgainAfterTheWindow() async throws {
        service.latestCursorLimitClosure = { [service] _, _ in
            service.latestCursorLimitCallsCount == 1 ? .failure(Self.overTheWindow) : .success(Self.page)
        }

        let viewModel = try await feedViewModel()

        #expect(viewModel.context.viewState.visibleItems.map(\.post) == Self.posts)
        #expect(service.latestCursorLimitCallsCount == 2)
        #expect(slowDownToasts == 0)
    }

    @Test
    func aPullToRefreshOverTheWindowKeepsTheListAndSaysSlowDown() async throws {
        service.latestCursorLimitReturnValue = .success(Self.page)
        let viewModel = try await feedViewModel()
        let shown = viewModel.context.viewState.listState
        service.latestCursorLimitReturnValue = .failure(Self.overTheWindow)

        await viewModel.loadFirstPage(isManual: true)

        #expect(viewModel.context.viewState.listState == shown)
        #expect(service.latestCursorLimitCallsCount == 2)
        #expect(slowDownToasts == 1)
    }

    /// A Retry tapped on a page never read keeps the Retry, never "Be the first today".
    @Test
    func aRetryOverTheWindowIsNeverAnEmptyFeed() async throws {
        service.latestCursorLimitReturnValue = .failure(Self.overTheWindow)
        let viewModel = try await feedViewModel()
        #expect(viewModel.context.viewState.listState == .failed)

        await viewModel.loadFirstPage(isManual: true)

        #expect(viewModel.context.viewState.listState == .failed)
        #expect(!viewModel.context.viewState.isEmpty)
        #expect(slowDownToasts == 1)
    }

    @Test
    func theNextPageOverTheWindowIsReadAgainThenLeftToATap() async throws {
        service.latestCursorLimitReturnValue = .success(FeedPage(items: Self.posts, nextCursor: "c1", pinned: nil))
        let viewModel = try await feedViewModel()
        let items = viewModel.context.viewState.visibleItems
        service.latestCursorLimitReturnValue = .failure(Self.overTheWindow)

        await viewModel.loadNextPage(cursor: "c1", isManual: false)
        #expect(viewModel.context.viewState.listState == .loaded(items, loadMore: .failed(cursor: "c1")))
        #expect(service.latestCursorLimitCallsCount == 3)
        #expect(slowDownToasts == 0)

        await viewModel.loadNextPage(cursor: "c1", isManual: true)
        #expect(viewModel.context.viewState.listState == .loaded(items, loadMore: .failed(cursor: "c1")))
        #expect(service.latestCursorLimitCallsCount == 4)
        #expect(slowDownToasts == 1)
    }

    /// The bell's counts, read again on `feed.notice` / `feed.activity`, wait out the window once.
    @Test
    func theBadgesAreReadAgainAfterTheWindow() async {
        let store = FeedStore(feedService: service, currentUserID: "@me:spiral.md")
        service.noticesCursorLimitLanguageClosure = { [service] _, _, _ in
            service.noticesCursorLimitLanguageCallsCount == 1 ? .failure(Self.overTheWindow) : .success(FeedNoticePage(items: [], nextCursor: nil, unread: 0))
        }
        store.apply([.notice])
        await store.settle()
        #expect(service.noticesCursorLimitLanguageCallsCount == 2)
    }

    // MARK: - A post, its banner and its comments

    private func postViewModel(post: FeedPost? = nil) -> FeedPostScreenViewModel {
        FeedPostScreenViewModel(postID: FeedPreviewData.textPost.id,
                                post: post,
                                feedService: service,
                                engagement: FeedEngagementController.make(service, userIndicatorController: UserIndicatorControllerMock()),
                                clientProxy: clientProxy,
                                mediaProvider: MediaProviderMock(.init()),
                                userIndicatorController: indicators,
                                language: "en")
    }

    private func settled(_ viewModel: FeedPostScreenViewModel) async throws {
        let settled = deferFulfillment(viewModel.context.observe(\.viewState.isSettled)) { $0 }
        try await settled.fulfill()
    }

    @Test
    func aPostIsReadAgainAfterTheWindow() async throws {
        service.postIdClosure = { [service] _ in
            service.postIdCallsCount == 1 ? .failure(Self.overTheWindow) : .success(FeedPreviewData.textPost)
        }
        let viewModel = postViewModel()
        try await settled(viewModel)

        #expect(viewModel.context.viewState.loadState == .loaded(FeedItem(post: FeedPreviewData.textPost)))
        #expect(service.postIdCallsCount == 2)
    }

    @Test
    func aRetriedPostOverTheWindowSaysSlowDownNeverNotAvailable() async throws {
        service.postIdReturnValue = .failure(Self.overTheWindow)
        let viewModel = postViewModel()
        try await settled(viewModel)
        #expect(viewModel.context.viewState.loadState == .failed)

        await viewModel.load(isManual: true)

        #expect(viewModel.context.viewState.loadState == .failed)
        #expect(service.postIdCallsCount == 3)
        #expect(slowDownToasts == 1)
    }

    /// A post a list showed stays on screen when its read again is over the window.
    @Test
    func aShownPostStaysOverTheWindow() async throws {
        service.postIdReturnValue = .failure(Self.overTheWindow)
        let viewModel = postViewModel(post: FeedPreviewData.textPost)
        try await settled(viewModel)

        #expect(viewModel.context.viewState.loadState == .loaded(FeedItem(post: FeedPreviewData.textPost)))
        #expect(slowDownToasts == 0)
    }

    @Test
    func commentsAreReadAgainAfterTheWindowAndShownOnesStay() async throws {
        service.postIdReturnValue = .success(FeedPreviewData.textPost)
        service.commentsPostIDCursorLimitClosure = { [service] _, _, _ in
            service.commentsPostIDCursorLimitCallsCount == 1 ? .failure(Self.overTheWindow) : .success(FeedPreviewData.commentPage)
        }
        let viewModel = postViewModel()
        try await settled(viewModel)
        #expect(viewModel.context.viewState.visibleComments.count == FeedPreviewData.commentPage.items.count)
        let shown = viewModel.context.viewState.commentsState

        service.commentsPostIDCursorLimitClosure = nil
        service.commentsPostIDCursorLimitReturnValue = .failure(Self.overTheWindow)
        await viewModel.loadFirstCommentsPage()
        #expect(viewModel.context.viewState.commentsState == shown)

        await viewModel.loadFirstCommentsPage(isManual: true)
        #expect(viewModel.context.viewState.commentsState == shown)
        #expect(slowDownToasts == 1)
    }

    @Test
    func theBannersNoticeIsReadAgainAfterTheWindow() async throws {
        let removed = FeedPreviewData.post(id: FeedPreviewData.textPost.id, author: FeedPreviewData.ann, minutesAgo: 1, text: "Removed",
                                           state: .removed, isAuthor: true)
        let notice = FeedPreviewData.notice(id: "01933f2d-0000-7000-8000-000000000301", kind: .removed, isRead: true, postID: removed.id,
                                            statement: FeedPreviewData.statement(restriction: .removed, trigger: .report))
        service.postIdReturnValue = .success(removed)
        service.noticesCursorLimitLanguageClosure = { [service] _, _, _ in
            service.noticesCursorLimitLanguageCallsCount == 1 ? .failure(Self.overTheWindow) : .success(FeedNoticePage(items: [notice], nextCursor: nil, unread: 0))
        }
        let viewModel = postViewModel()
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.authorStatement)) { if case .loaded = $0 { true } else { false } }
        try await loaded.fulfill()

        #expect(viewModel.context.viewState.authorStatement == .loaded(FeedNoticeContent(notice: notice)))
        #expect(service.noticesCursorLimitLanguageCallsCount == 2)
    }

    // MARK: - An author's posts and the person's own

    private func authorViewModel(_ author: FeedAuthor) async throws -> FeedAuthorScreenViewModel {
        let viewModel = FeedAuthorScreenViewModel(author: author,
                                                  feedService: service,
                                                  engagement: FeedEngagementController.make(service, userIndicatorController: UserIndicatorControllerMock()),
                                                  clientProxy: clientProxy,
                                                  mediaProvider: MediaProviderMock(.init()),
                                                  userIndicatorController: indicators)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.postsState)) { $0 != .loading }
        try await loaded.fulfill()
        return viewModel
    }

    @Test
    func anAuthorsPostsAreReadAgainAndShownOnesStay() async throws {
        service.authorPostsUserIDCursorLimitClosure = { [service] _, _, _ in
            service.authorPostsUserIDCursorLimitCallsCount == 1 ? .failure(Self.overTheWindow) : .success(Self.page)
        }
        let viewModel = try await authorViewModel(FeedPreviewData.ann)
        let shown = viewModel.context.viewState.postsState
        #expect(shown == .loaded(Self.posts.map(FeedItem.init), loadMore: .exhausted))

        service.authorPostsUserIDCursorLimitClosure = nil
        service.authorPostsUserIDCursorLimitReturnValue = .failure(Self.overTheWindow)
        await viewModel.loadFirstPage()
        #expect(viewModel.context.viewState.postsState == shown)

        await viewModel.loadFirstPage(isManual: true)
        #expect(viewModel.context.viewState.postsState == shown)
        #expect(slowDownToasts == 1)
    }

    @Test
    func ownPostsOverTheWindowAreNeverNotAvailable() async throws {
        service.ownPostsCursorLimitReturnValue = .failure(Self.overTheWindow)
        let me = FeedAuthor(userID: "@me:spiral.md", name: "Me", avatarURL: nil, bio: nil, isOfficial: false, isNameWithheld: false)

        let viewModel = try await authorViewModel(me)

        #expect(viewModel.context.viewState.postsState == .failed)
        #expect(service.ownPostsCursorLimitCallsCount == 2)
    }

    // MARK: - Notices, the standing and the settings

    @Test
    func noticesAreReadAgainAndARefreshSaysSlowDown() async throws {
        let notices = FeedNoticePage(items: [FeedPreviewData.notices[0]], nextCursor: nil, unread: 1)
        service.noticesCursorLimitLanguageClosure = { [service] _, _, _ in
            service.noticesCursorLimitLanguageCallsCount == 1 ? .failure(Self.overTheWindow) : .success(notices)
        }
        let viewModel = FeedNoticesScreenViewModel(feedService: service,
                                                   store: FeedStore(feedService: service, currentUserID: "@me:spiral.md"),
                                                   userIndicatorController: indicators,
                                                   language: "en")
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { if case .loaded = $0 { true } else { false } }
        try await loaded.fulfill()
        let shown = viewModel.context.viewState.listState

        service.noticesCursorLimitLanguageClosure = nil
        service.noticesCursorLimitLanguageReturnValue = .failure(Self.overTheWindow)
        await viewModel.loadFirstPage(isManual: true)

        #expect(viewModel.context.viewState.listState == shown)
        #expect(slowDownToasts == 1)
    }

    @Test
    func theStandingIsReadAgainAfterTheWindow() async throws {
        let standing = FeedStanding(rulesVersion: FeedRules.version, rulesAccepted: true,
                                    postsPerDay: 30, postsToday: 0, suspendedUntil: nil)
        service.standingClosure = { [service] in
            service.standingCallsCount == 1 ? .failure(Self.overTheWindow) : .success(standing)
        }
        let viewModel = FeedComposerScreenViewModel(feedService: service, clientProxy: ClientProxyMock(.init(userID: "@me:spiral.md")), mediaProvider: MediaProviderMock(.init()))
        let read = deferFulfillment(viewModel.context.observe(\.viewState.standing)) { $0 != nil }
        try await read.fulfill()

        #expect(service.standingCallsCount == 2)
    }

    @Test
    func theSettingsAreReadAgainAndARetrySaysSlowDown() async throws {
        service.notificationSettingsClosure = { [service] in
            service.notificationSettingsCallsCount == 1 ? .failure(Self.overTheWindow) : .success(FeedNotificationSettings(likes: .everyone, comments: .everyone, replies: .off))
        }
        let viewModel = FeedNotificationSettingsViewModel(feedService: service, userIndicatorController: indicators)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.settingsState)) { if case .loading = $0 { false } else { true } }
        try await loaded.fulfill()
        #expect(viewModel.context.viewState.settings?.replies == .off)

        service.notificationSettingsClosure = nil
        service.notificationSettingsReturnValue = .failure(Self.overTheWindow)
        await viewModel.load(isManual: true)
        #expect(viewModel.context.viewState.settings?.replies == .off)
        #expect(slowDownToasts == 1)
    }
}
