//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082, decision 289). Lane I3 in Latest and on
// the author sheet, on the session's one store: a like on a card is rolled
// back when the server refuses it, a post the person hid leaves the lists,
// and a count the sync stream moved shows on every screen holding the post.
// The card offers likes, comments and share only on a visible post.
//

import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct FeedListEngagementTests {
    private let service = FeedServiceMock()
    private let clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md"))
    private let posts = FeedPreviewData.posts(3)
    /// The session's one controller, shared by the screens of a test as by the app's.
    private let engagement: FeedEngagementController

    init() {
        // Lane I3 on B4: the notices behind the badge and a held post's banner.
        service.noticesUnreadPublisher = Empty().eraseToAnyPublisher()
        service.activityUnreadPublisher = Empty().eraseToAnyPublisher()
        service.noticesCursorLimitLanguageReturnValue = .success(FeedNoticePage(items: [], nextCursor: nil, unread: 0))
        engagement = .make(service)
        clientProxy.ignoredUsersPublisher = CurrentValueSubject<[String]?, Never>([]).asCurrentValuePublisher()
        service.cachedFirstPageReturnValue = nil
        service.latestCursorLimitReturnValue = .success(FeedPage(items: posts, nextCursor: nil, pinned: nil))
    }

    private func loadedViewModel() async throws -> FeedScreenViewModel {
        let viewModel = FeedScreenViewModel(feedService: service,
                                            engagement: engagement,
                                            clientProxy: clientProxy,
                                            mediaProvider: MediaProviderMock(.init()),
                                            userIndicatorController: UserIndicatorControllerMock())
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            if case .loaded(_, .exhausted) = state { true } else { false }
        }
        try await loaded.fulfill()
        return viewModel
    }

    private func post(_ id: String, in viewModel: FeedScreenViewModel) -> FeedPost? {
        viewModel.context.viewState.visibleItems.first { $0.id == id }?.post
    }

    @Test
    func aRefusedLikeOnACardIsRolledBack() async throws {
        let viewModel = try await loadedViewModel()
        let id = posts[1].id
        var likedDuringRequest = false
        service.setLikedPostIDClosure = { _, _ in
            likedDuringRequest = post(id, in: viewModel)?.viewer.liked == true
            return .failure(.transport)
        }

        let rolledBack = deferFulfillment(viewModel.context.observe(\.viewState.visibleItems)) { items in
            items.first { $0.id == id }?.post.viewer.liked == false && service.setLikedPostIDCallsCount == 1
        }
        viewModel.context.send(viewAction: .card(postID: id, .like))
        try await rolledBack.fulfill()

        #expect(likedDuringRequest)
        #expect(post(id, in: viewModel)?.counts.likes == 0)
        #expect(post(posts[0].id, in: viewModel)?.viewer.liked == false, "Only that post moved")
    }

    /// One like per post in the whole session, whichever screen asks, and a
    /// refusal rolled back on every screen that showed it.
    @Test
    func aLikeIsOneAtATimeAcrossScreensAndRolledBackOnAll() async throws {
        let latest = try await loadedViewModel()
        let id = posts[0].id
        service.postIdReturnValue = .success(posts[0])
        service.commentsPostIDCursorLimitReturnValue = .success(FeedCommentPage(items: [], nextCursor: nil))
        let postScreen = FeedPostScreenViewModel(postID: id,
                                                 post: posts[0],
                                                 feedService: service,
                                                 engagement: engagement,
                                                 clientProxy: clientProxy,
                                                 mediaProvider: MediaProviderMock(.init()),
                                                 userIndicatorController: UserIndicatorControllerMock())
        var calls = 0
        var likedOnLatestDuringRequest = false
        service.setLikedPostIDClosure = { _, _ in
            calls += 1
            if calls == 1 {
                likedOnLatestDuringRequest = post(id, in: latest)?.viewer.liked == true
                // A tap on the other screen while the first like is on its way.
                latest.context.send(viewAction: .card(postID: id, .like))
            }
            return .failure(.rateLimited(retryAfterSeconds: 30))
        }

        let rolledBack = deferFulfillment(postScreen.context.observe(\.viewState.post)) { post in
            calls >= 1 && post?.viewer.liked == false
        }
        postScreen.context.send(viewAction: .card(.like))
        try await rolledBack.fulfill()
        try await Task.sleep(for: .milliseconds(100))

        #expect(calls == 1)
        #expect(likedOnLatestDuringRequest, "The like shows on every screen at once")
        #expect(post(id, in: latest)?.viewer.liked == false)
        #expect(post(id, in: latest)?.counts.likes == 0)
        #expect(postScreen.context.viewState.post?.viewer.liked == false)
    }

    /// A comment made or deleted on the post screen moves the count on the list's card.
    @Test
    func aCommentMadeOrDeletedMovesTheListsCount() async throws {
        let latest = try await loadedViewModel()
        let id = posts[0].id
        let comment = FeedPreviewData.comment(id: "01933f2b-0000-7000-8000-000000000009", author: FeedPreviewData.ann, minutesAgo: 0,
                                              text: "Nice", isAuthor: true)
        service.postIdReturnValue = .success(posts[0])
        service.commentsPostIDCursorLimitReturnValue = .success(FeedCommentPage(items: [], nextCursor: nil))
        service.createCommentPostIDTextReplyToIdempotencyKeyReturnValue = .success(comment)
        service.deleteCommentIdReturnValue = .success(())
        let postScreen = FeedPostScreenViewModel(postID: id,
                                                 post: posts[0],
                                                 feedService: service,
                                                 engagement: engagement,
                                                 clientProxy: clientProxy,
                                                 mediaProvider: MediaProviderMock(.init()),
                                                 userIndicatorController: UserIndicatorControllerMock())
        let read = deferFulfillment(postScreen.context.observe(\.viewState.commentsState)) { if case .loaded = $0 { true } else { false } }
        try await read.fulfill()

        let counted = deferFulfillment(latest.context.observe(\.viewState.visibleItems)) { $0.first?.post.counts.comments == 1 }
        postScreen.context.commentText = "Nice"
        await postScreen.sendComment()
        try await counted.fulfill()

        let uncounted = deferFulfillment(latest.context.observe(\.viewState.visibleItems)) { $0.first?.post.counts.comments == 0 }
        await postScreen.deleteComment(comment.id)
        try await uncounted.fulfill()
    }

    @Test
    func aCountTheServerMovedShowsOnTheCard() async throws {
        let viewModel = try await loadedViewModel()

        let moved = deferFulfillment(viewModel.context.observe(\.viewState.visibleItems)) { items in
            items.first?.card.engagement?.likes == 7 && items.first?.card.engagement?.shares == 2
        }
        // The person's like from another device, and the counts everyone sees.
        engagement.store.apply([.viewerLike(postID: posts[0].id, liked: true),
                                .counts(postID: posts[0].id, counts: FeedCounts(likes: 7, comments: 0, shares: 2))])
        try await moved.fulfill()

        #expect(viewModel.context.viewState.visibleItems.first?.card.engagement?.isLiked == true)
    }

    @Test
    func aHiddenPostLeavesTheList() async throws {
        let viewModel = try await loadedViewModel()

        let gone = deferFulfillment(viewModel.context.observe(\.viewState.visibleItems)) { $0.count == 2 }
        engagement.store.apply([.hidden(postID: posts[1].id)])
        try await gone.fulfill()

        #expect(!viewModel.context.viewState.visibleItems.contains { $0.id == posts[1].id })
    }

    /// Shown again from the post screen: Latest reads it in where the server puts it.
    @Test
    func aPostShownAgainComesBackToTheList() async throws {
        service.latestCursorLimitReturnValue = .success(FeedPage(items: [posts[0], posts[2]], nextCursor: nil, pinned: nil))
        let viewModel = try await loadedViewModel()
        viewModel.context.send(viewAction: .appeared)
        service.latestCursorLimitReturnValue = .success(FeedPage(items: posts, nextCursor: nil, pinned: nil))

        let back = deferFulfillment(viewModel.context.observe(\.viewState.visibleItems)) { $0.count == 3 }
        engagement.store.apply([.unhidden(postID: posts[1].id)])
        try await back.fulfill()

        #expect(viewModel.context.viewState.visibleItems.map(\.id) == posts.map(\.id))
    }

    @Test
    func aCardAsksForTheSharePickerAndItsPostForComments() async throws {
        let viewModel = try await loadedViewModel()
        var actions: [String] = []
        let cancellable = viewModel.actionsPublisher.sink { action in
            switch action {
            case .share(let post): actions.append("share \(post.id)")
            case .openPost(let post): actions.append("post \(post.id)")
            default: break
            }
        }

        viewModel.context.send(viewAction: .card(postID: posts[0].id, .share))
        viewModel.context.send(viewAction: .card(postID: posts[0].id, .comment))

        #expect(actions == ["share \(posts[0].id)", "post \(posts[0].id)"])
        _ = cancellable
    }

    /// Decision 267: a sensitive post is shared only after "Show".
    @Test
    func aSensitivePostIsSharedOnlyOnceShown() async throws {
        service.latestCursorLimitReturnValue = .success(FeedPage(items: [FeedPreviewData.sensitivePost], nextCursor: nil, pinned: nil))
        let viewModel = try await loadedViewModel()
        let id = FeedPreviewData.sensitivePost.id
        var shared: [String] = []
        let cancellable = viewModel.actionsPublisher.sink { if case .share(let post) = $0 { shared.append(post.id) } }
        defer { cancellable.cancel() }

        viewModel.context.send(viewAction: .card(postID: id, .share))
        #expect(shared.isEmpty)

        viewModel.context.send(viewAction: .card(postID: id, .reveal))
        viewModel.context.send(viewAction: .card(postID: id, .share))
        #expect(shared == [id])
    }

    // MARK: - Who liked and live counts (lane I5)

    /// The count opens who liked; a post nobody liked has no one to show.
    @Test
    func theLikesCountOpensWhoLiked() async throws {
        service.latestCursorLimitReturnValue = .success(FeedPage(items: [posts[0], posts[1].withCounts(likes: 2)], nextCursor: nil, pinned: nil))
        let viewModel = try await loadedViewModel()
        var opened: [String] = []
        let cancellable = viewModel.actionsPublisher.sink { action in
            if case .openLikers(let postID) = action { opened.append(postID) }
        }

        viewModel.context.send(viewAction: .card(postID: posts[0].id, .openLikers))
        viewModel.context.send(viewAction: .card(postID: posts[1].id, .openLikers))

        #expect(opened == [posts[1].id])
        _ = cancellable
    }

    /// Decision 289: one `feed.counts` change shows on every screen holding the post, with no bus between them.
    @Test
    func aCountsChangeShowsOnEveryScreenHoldingThePost() async throws {
        let latest = try await loadedViewModel()
        let shown = posts[0]
        service.postIdReturnValue = .success(shown)
        service.commentsPostIDCursorLimitReturnValue = .success(FeedCommentPage(items: [], nextCursor: nil))
        service.authorPostsUserIDCursorLimitReturnValue = .success(FeedPage(items: [shown], nextCursor: nil, pinned: nil))
        let postScreen = FeedPostScreenViewModel(postID: shown.id, post: shown, feedService: service, engagement: engagement, clientProxy: clientProxy,
                                                 mediaProvider: MediaProviderMock(.init()), userIndicatorController: UserIndicatorControllerMock())
        let authorSheet = FeedAuthorScreenViewModel(author: shown.author, feedService: service, engagement: engagement, clientProxy: clientProxy,
                                                    mediaProvider: MediaProviderMock(.init()), userIndicatorController: UserIndicatorControllerMock())
        try await deferFulfillment(authorSheet.context.observe(\.viewState.postsState)) { $0 != .loading }.fulfill()

        let counts = FeedCounts(likes: 11, comments: 4, shares: 3)
        let onLatest = deferFulfillment(latest.context.observe(\.viewState.visibleItems)) { $0.first?.post.counts == counts }
        let onPost = deferFulfillment(postScreen.context.observe(\.viewState.post?.counts)) { $0 == counts }
        let onAuthor = deferFulfillment(authorSheet.context.observe(\.viewState.postsState)) { state in
            if case .loaded(let items, _) = state { items.first?.post.counts == counts } else { false }
        }
        engagement.store.apply([.counts(postID: shown.id, counts: counts)])
        try await onLatest.fulfill()
        try await onPost.fulfill()
        try await onAuthor.fulfill()
    }

    /// A screen dropped without `disappeared` (its stack torn down) is no longer shown.
    @Test
    func aDroppedScreenIsNoLongerShown() async throws {
        var viewModel: FeedScreenViewModel? = try await loadedViewModel()
        viewModel?.context.send(viewAction: .appeared)
        #expect(engagement.store.isShown(.latest))

        viewModel = nil
        for _ in 0..<300 where engagement.store.isShown(.latest) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!engagement.store.isShown(.latest))
    }

    /// A frame of the stream moves the card where it shows, and only that card.
    @Test
    func aLiveCountMovesTheCard() async throws {
        let viewModel = try await loadedViewModel()
        let id = posts[2].id

        let moved = deferFulfillment(viewModel.context.observe(\.viewState.visibleItems)) { items in
            items.first { $0.id == id }?.card.engagement?.likes == 7
        }
        engagement.store.apply([.counts(postID: id, counts: FeedCounts(likes: 7, comments: 2, shares: 1))])
        try await moved.fulfill()

        #expect(post(id, in: viewModel)?.counts == FeedCounts(likes: 7, comments: 2, shares: 1))
        #expect(post(posts[0].id, in: viewModel)?.counts.likes == 0)
    }

    // MARK: - The card

    @Test
    func onlyAVisiblePostIsLikedCommentedOnAndShared() {
        let visible = FeedPostCardModel(post: FeedPreviewData.engagedPost)
        let expected = FeedPostCardModel.Engagement(likes: 12, isLiked: true, comments: 3, shares: 1, commentsEnabled: true, canHide: true, canReport: true)
        #expect(visible.engagement == expected)
        #expect(visible.accessibilityLabel(isRevealed: false).contains(UntranslatedL10n.a11yFeedLikes(12)))
        #expect(visible.accessibilityLabel(isRevealed: false).contains(UntranslatedL10n.a11yFeedLikedByYou))
        #expect(!FeedPostCardModel(post: FeedPreviewData.textPost).accessibilityLabel(isRevealed: false).contains(UntranslatedL10n.a11yFeedLikes(0)),
                "A count at zero is not read out")

        for state in [FeedPostState.held, .removed, .hiddenAuthor, .other("archived")] {
            let post = FeedPreviewData.post(id: FeedPreviewData.textPost.id, author: FeedPreviewData.ann, minutesAgo: 1, text: "x",
                                            state: state, isAuthor: true)
            #expect(FeedPostCardModel(post: post).engagement == nil, "\(state)")
        }

        let own = FeedPreviewData.post(id: FeedPreviewData.textPost.id, author: FeedPreviewData.ann, minutesAgo: 1, text: "x", isAuthor: true)
        #expect(FeedPostCardModel(post: own).engagement?.canHide == false, "The author does not hide their own post")
    }
}
