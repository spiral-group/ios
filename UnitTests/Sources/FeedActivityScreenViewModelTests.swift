//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Lane I5: Activity behind the bell — what
// an entry says, the seen mark on the server's word, a failed read never shown
// as "no activity", the way to the post (at the comment) and to the notices —
// and who liked a post.
//

import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct FeedActivityScreenViewModelTests {
    private let service = FeedServiceMock()
    private let indicators = UserIndicatorControllerMock()
    private let notices = PassthroughSubject<Int, Never>()
    private let store: FeedStore

    init() {
        store = FeedStore(feedService: service, currentUserID: "@me:spiral.md")
        service.noticesUnreadPublisher = notices.eraseToAnyPublisher()
        service.noticesCursorLimitLanguageReturnValue = .success(FeedNoticePage(items: [], nextCursor: nil, unread: 0))
        service.markActivitySeenUpToReturnValue = .success(0)
    }

    private func loadedViewModel(_ result: Result<FeedActivityPage, FeedError>) async throws -> FeedActivityScreenViewModel {
        service.activityCursorLimitReturnValue = result
        let viewModel = FeedActivityScreenViewModel(feedService: service, store: store, mediaProvider: MediaProviderMock(.init()), userIndicatorController: indicators)
        let settled = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { if case .loading = $0 { false } else { true } }
        try await settled.fulfill()
        return viewModel
    }

    @Test
    func theUnreadEntriesAreMarkedSeenUpToTheNewestShown() async throws {
        let viewModel = try await loadedViewModel(.success(FeedActivityPage(items: FeedPreviewData.activity, nextCursor: nil, unread: 2)))

        #expect(viewModel.context.viewState.items.map(\.id) == FeedPreviewData.activity.map(\.id))
        try await eventually { service.markActivitySeenUpToCallsCount == 1 }
        #expect(service.markActivitySeenUpToReceivedDate == FeedPreviewData.activity.map(\.at).max())
        // The dots stay for this visit.
        #expect(viewModel.context.viewState.items.first?.entry.isUnread == true)
    }

    /// The newest entry is a kind this build skips: the mark covers it, or it would stay unread for ever.
    @Test
    func theSeenMarkCoversASkippedNewestEntry() async throws {
        let skippedAt = try #require(FeedPreviewData.activity.map(\.at).max()).addingTimeInterval(60)
        _ = try await loadedViewModel(.success(FeedActivityPage(items: FeedPreviewData.activity, nextCursor: nil, unread: 3, newestAt: skippedAt)))

        try await eventually { service.markActivitySeenUpToCallsCount == 1 }
        #expect(service.markActivitySeenUpToReceivedDate == skippedAt)
    }

    @Test
    func nothingUnreadMarksNothing() async throws {
        _ = try await loadedViewModel(.success(FeedActivityPage(items: FeedPreviewData.activity, nextCursor: nil, unread: 0)))
        try await Task.sleep(for: .milliseconds(50))

        #expect(service.markActivitySeenUpToCallsCount == 0)
    }

    /// A failure is not an answer: never "No activity yet", and nothing is marked seen.
    @Test
    func aFailedReadIsNotAnEmptyList() async throws {
        let viewModel = try await loadedViewModel(.failure(.transport))

        #expect(viewModel.context.viewState.listState == .failed)
        #expect(!viewModel.context.viewState.isEmpty)
        #expect(service.markActivitySeenUpToCallsCount == 0)
    }

    @Test
    func aFailedRefreshKeepsWhatIsShown() async throws {
        let viewModel = try await loadedViewModel(.success(FeedActivityPage(items: FeedPreviewData.activity, nextCursor: nil, unread: 0)))
        service.activityCursorLimitReturnValue = .failure(.transport)

        await viewModel.loadFirstPage(isManual: true)

        #expect(viewModel.context.viewState.items.count == FeedPreviewData.activity.count)
        #expect(indicators.submitIndicatorDelayReceivedArguments?.indicator.title == UntranslatedL10n.screenFeedActivityRefreshFailed)
    }

    /// Decision 289: shown, Activity is read again on `feed.activity`; there is no pull to refresh.
    @Test
    func newActivityIsReadWhileItShows() async throws {
        let viewModel = try await loadedViewModel(.success(FeedActivityPage(items: Array(FeedPreviewData.activity.prefix(1)), nextCursor: nil, unread: 0)))
        viewModel.context.send(viewAction: .appeared)
        service.activityCursorLimitReturnValue = .success(FeedActivityPage(items: FeedPreviewData.activity, nextCursor: nil, unread: 0))

        let moved = deferFulfillment(viewModel.context.observe(\.viewState.items.count)) { $0 == FeedPreviewData.activity.count }
        store.apply([.activity])
        try await moved.fulfill()
        #expect(service.activityCursorLimitReceivedArguments?.limit == FeedActivityScreenViewModel.pageSize)
    }

    /// Off screen only the bell's count is read (one entry); the list is read once it shows again.
    @Test
    func activityOffScreenReadsTheCountThenTheListWhenItShows() async throws {
        let viewModel = try await loadedViewModel(.success(FeedActivityPage(items: Array(FeedPreviewData.activity.prefix(1)), nextCursor: nil, unread: 0)))
        store.apply([.activity])
        await store.settle()
        #expect(service.activityCursorLimitCallsCount == 2)
        #expect(service.activityCursorLimitReceivedArguments?.limit == 1)

        service.activityCursorLimitReturnValue = .success(FeedActivityPage(items: FeedPreviewData.activity, nextCursor: nil, unread: 0))
        let moved = deferFulfillment(viewModel.context.observe(\.viewState.items.count)) { $0 == FeedPreviewData.activity.count }
        viewModel.context.send(viewAction: .appeared)
        try await moved.fulfill()
        #expect(service.activityCursorLimitCallsCount == 3)
    }

    /// A failure is not an answer: a failed read again leaves what was shown, without a toast.
    @Test
    func aFailedReadAgainKeepsTheList() async throws {
        let viewModel = try await loadedViewModel(.success(FeedActivityPage(items: FeedPreviewData.activity, nextCursor: nil, unread: 0)))
        viewModel.context.send(viewAction: .appeared)
        service.activityCursorLimitReturnValue = .failure(.transport)

        store.apply([.activity])
        await store.settle()

        #expect(service.activityCursorLimitCallsCount == 2)
        #expect(viewModel.context.viewState.items.count == FeedPreviewData.activity.count)
        #expect(indicators.submitIndicatorDelayCallsCount == 0)
    }

    @Test
    func onlyAReadThatReachedItsEndEmptyIsEmpty() async throws {
        let viewModel = try await loadedViewModel(.success(FeedActivityPage(items: [], nextCursor: "more", unread: 0)))
        #expect(!viewModel.context.viewState.isEmpty)

        let ended = try await loadedViewModel(.success(FeedActivityPage(items: [], nextCursor: nil, unread: 0)))
        #expect(ended.context.viewState.isEmpty)
    }

    @Test
    func theFeedOffIsUnavailable() async throws {
        let viewModel = try await loadedViewModel(.failure(.unavailable))
        #expect(viewModel.context.viewState.listState == .unavailable)
    }

    /// A like group that gained a like moved to the top: the one already shown is not shown twice.
    @Test
    func theNextPageAddsOnlyEntriesNotShown() async throws {
        let first = Array(FeedPreviewData.activity.prefix(2))
        let viewModel = try await loadedViewModel(.success(FeedActivityPage(items: first, nextCursor: "c2", unread: 0)))
        service.activityCursorLimitReturnValue = .success(FeedActivityPage(items: Array(FeedPreviewData.activity.prefix(4)), nextCursor: nil, unread: 0))

        viewModel.context.send(viewAction: .loadMore)
        try await eventually { viewModel.context.viewState.sentinel == nil }

        #expect(viewModel.context.viewState.items.map(\.id) == FeedPreviewData.activity.prefix(4).map(\.id))
        #expect(service.activityCursorLimitReceivedArguments?.cursor == "c2")
    }

    @Test
    func anEntryOpensItsPostAtTheComment() async throws {
        let viewModel = try await loadedViewModel(.success(FeedActivityPage(items: FeedPreviewData.activity, nextCursor: nil, unread: 0)))
        let reply = try #require(FeedPreviewData.activity.first { $0.kind == .reply })
        let like = try #require(FeedPreviewData.activity.first { $0.kind == .like })

        let openedReply = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .openPost(reply.postID, reply.commentID) = action { true } else { false }
        }
        viewModel.context.send(viewAction: .open(entryID: reply.id))
        try await openedReply.fulfill()

        let openedLike = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .openPost(like.postID, nil) = action { true } else { false }
        }
        viewModel.context.send(viewAction: .open(entryID: like.id))
        try await openedLike.fulfill()
    }

    @Test
    func fromSpiralCountsTheUnreadNoticesAndOpensThem() async throws {
        let viewModel = try await loadedViewModel(.success(FeedActivityPage(items: [], nextCursor: nil, unread: 0)))

        let two = deferFulfillment(viewModel.context.observe(\.viewState.unreadNotices)) { $0 == 2 }
        notices.send(2)
        try await two.fulfill()

        let opened = deferFulfillment(viewModel.actionsPublisher) { if case .openNotices = $0 { true } else { false } }
        viewModel.context.send(viewAction: .openNotices)
        try await opened.fulfill()
    }

    /// Decision 288: the row is there only when there is a notice, read or not.
    @Test
    func fromSpiralIsHiddenWithoutANotice() async throws {
        let viewModel = try await loadedViewModel(.success(FeedActivityPage(items: [], nextCursor: nil, unread: 0)))

        try await eventually { viewModel.context.viewState.hasNotices != nil }
        #expect(!viewModel.context.viewState.showsFromSpiral)
    }

    @Test
    func fromSpiralShowsAReadNotice() async throws {
        service.noticesCursorLimitLanguageReturnValue = .success(FeedNoticePage(items: Array(FeedPreviewData.notices.prefix(1)), nextCursor: nil, unread: 0))
        let viewModel = try await loadedViewModel(.success(FeedActivityPage(items: [], nextCursor: nil, unread: 0)))

        try await eventually { viewModel.context.viewState.showsFromSpiral }
    }

    /// A notice that arrives while Activity is open, then is read, keeps the row.
    @Test
    func fromSpiralStaysAfterANewNoticeIsRead() async throws {
        let viewModel = try await loadedViewModel(.success(FeedActivityPage(items: [], nextCursor: nil, unread: 0)))
        try await eventually { viewModel.context.viewState.hasNotices == false }

        notices.send(1)
        try await eventually { viewModel.context.viewState.showsFromSpiral }
        notices.send(0)
        try await eventually { viewModel.context.viewState.unreadNotices == 0 }
        #expect(viewModel.context.viewState.showsFromSpiral)
    }

    @Test
    func fromSpiralShowsWhenTheNoticesCannotBeRead() async throws {
        service.noticesCursorLimitLanguageReturnValue = .failure(.transport)
        let viewModel = try await loadedViewModel(.success(FeedActivityPage(items: [], nextCursor: nil, unread: 0)))

        try await eventually { viewModel.context.viewState.showsFromSpiral }
    }

    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}

/// What an entry says, in the words the push uses too.
@MainActor
struct FeedActivityItemTests {
    @Test
    func aLikeGroupNamesTheNewestAndCountsTheRest() throws {
        let group = try #require(FeedPreviewData.activity.first)
        let item = FeedActivityItem(entry: group)

        #expect(item.title == UntranslatedL10n.screenFeedActivityLikedMany("Taras", UntranslatedL10n.screenFeedActivityOthers(3)))
        #expect(item.title == "Taras and 3 others liked your post")
        #expect(item.context == nil)

        let single = FeedActivityItem(entry: FeedPreviewData.activity[4])
        #expect(single.title == "Ann liked your post")
    }

    @Test
    func aCommentAndAReplyQuoteWhoAndWhat() {
        let reply = FeedActivityItem(entry: FeedPreviewData.activity[1])
        #expect(reply.title == "Olena: So true!")
        #expect(reply.context == UntranslatedL10n.screenFeedActivityReplyContext)

        let comment = FeedActivityItem(entry: FeedPreviewData.activity[2])
        #expect(comment.title == "bob: The kale always survives.")
        #expect(comment.context == UntranslatedL10n.screenFeedActivityCommentContext)
    }

    /// A sensitive entry's text stays behind "Show", for VoiceOver too; a withheld name stays neutral.
    @Test
    func aSensitiveEntryHidesItsPreviews() {
        let item = FeedActivityItem(entry: FeedPreviewData.activity[3])

        #expect(item.hiddenTitle == UntranslatedL10n.screenFeedAuthorWithheldName)
        let hidden = item.accessibilityLabel(isRevealed: false)
        #expect(!hidden.contains("Something upsetting"))
        #expect(!hidden.contains(item.entry.postPreview))
        #expect(hidden.contains(UntranslatedL10n.screenFeedSensitiveTitle))
        #expect(item.accessibilityLabel(isRevealed: true).contains("Something upsetting"))
    }
}

@MainActor
struct FeedLikersScreenViewModelTests {
    private let service = FeedServiceMock()
    private let blocked = CurrentValueSubject<[String]?, Never>([])
    private let store: FeedStore

    init() {
        store = FeedStore(feedService: service, currentUserID: "@me:spiral.md")
    }

    private func loadedViewModel(_ result: Result<FeedLikersPage, FeedError>) async throws -> FeedLikersScreenViewModel {
        service.likersPostIDCursorLimitReturnValue = result
        let clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md"))
        clientProxy.ignoredUsersPublisher = blocked.asCurrentValuePublisher()
        let viewModel = FeedLikersScreenViewModel(postID: FeedPreviewData.textPost.id,
                                                  feedService: service,
                                                  store: store,
                                                  clientProxy: clientProxy,
                                                  mediaProvider: MediaProviderMock(.init()),
                                                  userIndicatorController: UserIndicatorControllerMock())
        let settled = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { if case .loading = $0 { false } else { true } }
        try await settled.fulfill()
        return viewModel
    }

    @Test
    func whoLikedIsReadForThePost() async throws {
        let viewModel = try await loadedViewModel(.success(FeedLikersPage(items: FeedPreviewData.likers, nextCursor: nil)))

        #expect(viewModel.context.viewState.likers == FeedPreviewData.likers)
        #expect(service.likersPostIDCursorLimitReceivedArguments?.postID == FeedPreviewData.textPost.id)
        #expect(!viewModel.context.viewState.isEmpty)
    }

    /// A failure is not an answer: never "No likes to show".
    @Test
    func aFailedReadIsNotEmpty() async throws {
        let viewModel = try await loadedViewModel(.failure(.transport))

        #expect(viewModel.context.viewState.listState == .failed)
        #expect(!viewModel.context.viewState.isEmpty)
    }

    /// Decision 289: shown, who liked is read again when the post's likes move; a failed read again keeps who was shown.
    @Test
    func whoLikedIsReadAgainWhenTheLikesMove() async throws {
        let viewModel = try await loadedViewModel(.success(FeedLikersPage(items: Array(FeedPreviewData.likers.prefix(2)), nextCursor: nil)))
        store.upsert([FeedPreviewData.textPost])
        viewModel.context.send(viewAction: .appeared)
        service.likersPostIDCursorLimitReturnValue = .success(FeedLikersPage(items: FeedPreviewData.likers, nextCursor: nil))

        let more = deferFulfillment(viewModel.context.observe(\.viewState.likers.count)) { $0 == FeedPreviewData.likers.count }
        store.apply([.counts(postID: FeedPreviewData.textPost.id, counts: FeedCounts(likes: 9, comments: 0, shares: 0))])
        try await more.fulfill()

        service.likersPostIDCursorLimitReturnValue = .failure(.transport)
        store.apply([.counts(postID: FeedPreviewData.textPost.id, counts: FeedCounts(likes: 10, comments: 0, shares: 0))])
        await store.settle()
        #expect(service.likersPostIDCursorLimitCallsCount == 3)
        #expect(viewModel.context.viewState.likers.count == FeedPreviewData.likers.count)

        // The same count again is not a move: nothing more is read.
        store.apply([.counts(postID: FeedPreviewData.textPost.id, counts: FeedCounts(likes: 10, comments: 1, shares: 0))])
        await store.settle()
        #expect(service.likersPostIDCursorLimitCallsCount == 3)
    }

    @Test
    func aPostNoLongerThereIsNotAvailable() async throws {
        let viewModel = try await loadedViewModel(.failure(.notFound))
        #expect(viewModel.context.viewState.listState == .notAvailable)
    }

    @Test
    func someoneTheyBlockLeavesAtOnce() async throws {
        let viewModel = try await loadedViewModel(.success(FeedLikersPage(items: FeedPreviewData.likers, nextCursor: nil)))

        let fewer = deferFulfillment(viewModel.context.observe(\.viewState.likers.count)) { $0 == FeedPreviewData.likers.count - 1 }
        blocked.send([FeedPreviewData.taras.userID])
        try await fewer.fulfill()
    }

    @Test
    func theNextPageAddsOnlyPeopleNotShown() async throws {
        let viewModel = try await loadedViewModel(.success(FeedLikersPage(items: Array(FeedPreviewData.likers.prefix(2)), nextCursor: "l2")))
        service.likersPostIDCursorLimitReturnValue = .success(FeedLikersPage(items: Array(FeedPreviewData.likers.suffix(4)), nextCursor: nil))

        viewModel.context.send(viewAction: .loadMore)
        let all = deferFulfillment(viewModel.context.observe(\.viewState.likers.count)) { $0 == FeedPreviewData.likers.count }
        try await all.fulfill()
        #expect(viewModel.context.viewState.sentinel == nil)
    }

    @Test
    func aPersonOpensTheirAuthorSheet() async throws {
        let viewModel = try await loadedViewModel(.success(FeedLikersPage(items: FeedPreviewData.likers, nextCursor: nil)))

        let opened = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .openAuthor(let author) = action { author == FeedPreviewData.olena } else { false }
        }
        viewModel.context.send(viewAction: .openAuthor(userID: FeedPreviewData.olena.userID))
        try await opened.fulfill()
    }
}
