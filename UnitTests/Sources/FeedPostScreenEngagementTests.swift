//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082, decision 289). Lane I3 on the post
// screen: a like is rolled back when the server refuses it, a comment shows
// at once as sending and is replaced by the server's copy, a refused one stays
// with Retry under one key, a delete removes a comment only once the server
// did, and the author's comment switch, hide and the rules sheet behave as
// the contract says. The post and its comments follow the sync stream.
//

import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct FeedPostScreenEngagementTests {
    private let service = FeedServiceMock()
    private let engagement: FeedEngagementController
    private let clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md"))
    private let indicators = UserIndicatorControllerMock()

    private static let post = FeedPreviewData.textPost.withCounts(likes: 4, comments: 2)
    private static let ownPost = FeedPreviewData.post(id: FeedPreviewData.textPost.id, author: FeedPreviewData.ann, minutesAgo: 1,
                                                      text: "Mine", isAuthor: true)
    private static let first = FeedPreviewData.comment(id: "01933f2b-0000-7000-8000-000000000001", author: FeedPreviewData.bob,
                                                       minutesAgo: 3, text: "First")
    private static let second = FeedPreviewData.comment(id: "01933f2b-0000-7000-8000-000000000002", author: FeedPreviewData.ann,
                                                        minutesAgo: 2, text: "Second", replyTo: FeedCommentReply(id: first.id, author: FeedPreviewData.bob),
                                                        isAuthor: true)

    init() {
        engagement = .make(service, userIndicatorController: indicators)
        // Lane I3 on B4: the notices behind the badge and a held post's banner.
        service.noticesUnreadPublisher = Empty().eraseToAnyPublisher()
        service.activityUnreadPublisher = Empty().eraseToAnyPublisher()
        service.noticesCursorLimitLanguageReturnValue = .success(FeedNoticePage(items: [], nextCursor: nil, unread: 0))
        clientProxy.ignoredUsersPublisher = CurrentValueSubject<[String]?, Never>([]).asCurrentValuePublisher()
        service.postIdReturnValue = .success(Self.post)
        service.commentsPostIDCursorLimitReturnValue = .success(FeedCommentPage(items: [Self.first, Self.second], nextCursor: nil))
    }

    private func loadedViewModel() async throws -> FeedPostScreenViewModel {
        let viewModel = FeedPostScreenViewModel(postID: FeedPreviewData.textPost.id,
                                                post: nil,
                                                feedService: service,
                                                engagement: engagement,
                                                clientProxy: clientProxy,
                                                mediaProvider: MediaProviderMock(.init()),
                                                userIndicatorController: indicators)
        let read = deferFulfillment(viewModel.context.observe(\.viewState.commentsState)) { state in
            if case .loading = state { false } else { true }
        }
        try await read.fulfill()
        return viewModel
    }

    private func post(of viewModel: FeedPostScreenViewModel) throws -> FeedPost {
        try #require(viewModel.context.viewState.post)
    }

    // MARK: - Who liked and live counts (lane I5)

    @Test
    func theLikesCountOpensWhoLiked() async throws {
        let viewModel = try await loadedViewModel()

        let opened = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .openLikers(let postID) = action { postID == Self.post.id } else { false }
        }
        viewModel.context.send(viewAction: .card(.openLikers))
        try await opened.fulfill()
    }

    /// Decision 289: a counts change from the sync stream shows on the open post.
    @Test
    func aCountsChangeShowsOnTheOpenPost() async throws {
        let viewModel = try await loadedViewModel()

        let moved = deferFulfillment(viewModel.context.observe(\.viewState.post?.counts.comments)) { $0 == 5 }
        engagement.store.apply([.counts(postID: Self.post.id, counts: FeedCounts(likes: 6, comments: 5, shares: 0))])
        try await moved.fulfill()
        #expect(viewModel.context.viewState.post?.counts.likes == 6)
    }

    /// While it shows, a new comment from someone else reads the comments again; gone from screen, it waits until it shows.
    @Test
    func aNewCommentIsReadWhileThePostShows() async throws {
        let viewModel = try await loadedViewModel()
        viewModel.context.send(viewAction: .appeared)
        let third = FeedPreviewData.comment(id: "01933f2b-0000-7000-8000-000000000003", author: FeedPreviewData.bob, minutesAgo: 1, text: "Third")
        service.commentsPostIDCursorLimitReturnValue = .success(FeedCommentPage(items: [Self.first, Self.second, third], nextCursor: nil))

        let read = deferFulfillment(viewModel.context.observe(\.viewState.visibleComments.count)) { $0 == 3 }
        engagement.store.apply([.commentAdded(postID: Self.post.id, commentID: third.id)])
        try await read.fulfill()

        viewModel.context.send(viewAction: .disappeared)
        service.commentsPostIDCursorLimitReturnValue = .success(FeedCommentPage(items: [Self.first, third], nextCursor: nil))
        engagement.store.apply([.commentRemoved(postID: Self.post.id, commentID: Self.second.id)])
        await engagement.store.settle()
        #expect(viewModel.context.viewState.visibleComments.count == 3)

        let back = deferFulfillment(viewModel.context.observe(\.viewState.visibleComments.count)) { $0 == 2 }
        viewModel.context.send(viewAction: .appeared)
        try await back.fulfill()
    }

    /// A failure is not an answer: comments read again and not answered stay as shown.
    @Test
    func aFailedReadAgainKeepsTheComments() async throws {
        let viewModel = try await loadedViewModel()
        viewModel.context.send(viewAction: .appeared)
        let reads = service.commentsPostIDCursorLimitCallsCount
        service.commentsPostIDCursorLimitReturnValue = .failure(.transport)

        engagement.store.apply([.commentAdded(postID: Self.post.id, commentID: nil)])
        await engagement.store.settle()

        #expect(service.commentsPostIDCursorLimitCallsCount > reads)
        #expect(viewModel.context.viewState.visibleComments.map(\.id) == [Self.first.id, Self.second.id])
        #expect(engagement.store.isStale(.comments(postID: Self.post.id)))
    }

    /// A screen dropped without `disappeared` (its stack torn down) is no longer shown.
    @Test
    func aDroppedScreenIsNoLongerShown() async throws {
        var viewModel: FeedPostScreenViewModel? = FeedPostScreenViewModel(postID: Self.post.id, post: Self.post, feedService: service, engagement: engagement,
                                                                          clientProxy: clientProxy, mediaProvider: MediaProviderMock(.init()),
                                                                          userIndicatorController: indicators)
        let read = try #require(viewModel).context.observe(\.viewState.isSettled)
        try await deferFulfillment(read) { $0 }.fulfill()
        viewModel?.context.send(viewAction: .appeared)
        #expect(engagement.store.isShown(.comments(postID: Self.post.id)))

        viewModel = nil
        for _ in 0..<300 where engagement.store.isShown(.comments(postID: Self.post.id)) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!engagement.store.isShown(.comments(postID: Self.post.id)))
    }

    /// Opened from an Activity entry: the screen knows the comment to scroll to.
    @Test
    func anActivityEntryOpensThePostAtItsComment() {
        let viewModel = FeedPostScreenViewModel(postID: Self.post.id, post: Self.post, focusedCommentID: Self.second.id, feedService: service,
                                                engagement: engagement,
                                                clientProxy: clientProxy, mediaProvider: MediaProviderMock(.init()), userIndicatorController: indicators)

        #expect(viewModel.context.viewState.focusedCommentID == Self.second.id)
    }

    // MARK: - Like

    @Test
    func aLikeShowsAtOnceAndTakesTheServersCount() async throws {
        let viewModel = try await loadedViewModel()
        var duringRequest: FeedPost?
        service.setLikedPostIDClosure = { _, _ in
            duringRequest = viewModel.context.viewState.post
            return .success(FeedLikes(likes: 9, liked: true))
        }

        let settled = deferFulfillment(viewModel.context.observe(\.viewState.post)) { $0?.counts.likes == 9 }
        viewModel.context.send(viewAction: .card(.like))
        try await settled.fulfill()

        #expect(duringRequest?.viewer.liked == true)
        #expect(duringRequest?.counts.likes == 5)
        #expect(try post(of: viewModel).viewer.liked)
        #expect(service.setLikedPostIDReceivedArguments?.liked == true)
    }

    /// A failure is not an answer: a refused like never stays liked.
    @Test
    func aRefusedLikeIsRolledBack() async throws {
        let viewModel = try await loadedViewModel()
        var likedDuringRequest = false
        service.setLikedPostIDClosure = { _, _ in
            likedDuringRequest = viewModel.context.viewState.post?.viewer.liked == true
            return .failure(.rateLimited(retryAfterSeconds: 30))
        }

        let rolledBack = deferFulfillment(viewModel.context.observe(\.viewState.post)) { post in
            service.setLikedPostIDCallsCount == 1 && post?.viewer.liked == false && post?.counts.likes == 4
        }
        viewModel.context.send(viewAction: .card(.like))
        try await rolledBack.fulfill()

        #expect(likedDuringRequest)

        #expect(indicators.submitIndicatorDelayReceivedArguments?.indicator.title == UntranslatedL10n.screenFeedLikeRateLimited)
    }

    @Test
    func aSecondTapWaitsForTheFirstAnswer() async throws {
        let viewModel = try await loadedViewModel()
        var calls = 0
        service.setLikedPostIDClosure = { liked, _ in
            calls += 1
            if calls == 1 {
                viewModel.context.send(viewAction: .card(.like))
            }
            return .success(FeedLikes(likes: liked ? 9 : 4, liked: liked))
        }

        let settled = deferFulfillment(viewModel.context.observe(\.viewState.post)) { $0?.counts.likes == 9 && $0?.viewer.liked == true }
        viewModel.context.send(viewAction: .card(.like))
        try await settled.fulfill()
        // A second tap that was not held back would have run by now.
        try await Task.sleep(for: .milliseconds(100))

        #expect(calls == 1)
    }

    // MARK: - Comments

    @Test
    func commentsReadOldestFirstWithTheirReply() async throws {
        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.visibleComments.map(\.id) == [Self.first.id, Self.second.id])
        #expect(viewModel.context.viewState.visibleComments[1].comment.replyTo?.id == Self.first.id)
        #expect(service.commentsPostIDCursorLimitReceivedArguments?.cursor == nil)
    }

    @Test
    func commentsTheAuthorTurnedOffAreNotReadForAnyoneElse() async throws {
        service.postIdReturnValue = .success(Self.post.withCommentsEnabled(false))

        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.commentsState == .off)
        #expect(!viewModel.context.viewState.canComment)
        #expect(!service.commentsPostIDCursorLimitCalled)
    }

    @Test
    func theAuthorStillSeesCommentsTheyTurnedOff() async throws {
        service.postIdReturnValue = .success(Self.ownPost.withCommentsEnabled(false))

        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.visibleComments.count == 2)
        #expect(!viewModel.context.viewState.canComment)
    }

    /// Only the feed's own 404 is "not available"; any other failure is a Retry.
    @Test(arguments: [(FeedError.notFound, FeedCommentsState.notAvailable), (.server(status: 404), .failed), (.transport, .failed)])
    func aFailedReadOfTheCommentsSaysWhich(error: FeedError, expected: FeedCommentsState) async throws {
        service.commentsPostIDCursorLimitReturnValue = .failure(error)

        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.commentsState == expected)
    }

    /// An empty page with a cursor is not the end: reading goes on.
    @Test
    func anEmptyPageWithACursorReadsOn() async throws {
        var pages = [FeedCommentPage(items: [], nextCursor: "c1"), FeedCommentPage(items: [Self.first], nextCursor: nil)]
        service.commentsPostIDCursorLimitClosure = { _, _, _ in .success(pages.removeFirst()) }

        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.visibleComments.map(\.id) == [Self.first.id])
        #expect(service.commentsPostIDCursorLimitReceivedInvocations.map(\.cursor) == [nil, "c1"])
    }

    /// Decision 289: the comment shows at once as sending, and the server's copy replaces it.
    @Test
    func aSentCommentShowsAtOnceAndTheServersCopyReplacesIt() async throws {
        let viewModel = try await loadedViewModel()
        let sent = FeedPreviewData.comment(id: "01933f2b-0000-7000-8000-000000000009", author: FeedPreviewData.ann, minutesAgo: 0,
                                           text: "Nice", isAuthor: true)
        var duringRequest: [FeedCommentItem] = []
        var fieldDuringRequest = "unread"
        service.createCommentPostIDTextReplyToIdempotencyKeyClosure = { _, _, _, _ in
            duringRequest = viewModel.context.viewState.pendingComments
            fieldDuringRequest = viewModel.context.commentText
            return .success(sent)
        }

        viewModel.context.commentText = "Nice"
        await viewModel.sendComment()

        #expect(duringRequest.map(\.comment.text) == ["Nice"])
        #expect(duringRequest.first?.delivery == .sending)
        #expect(duringRequest.first?.pendingKey == service.createCommentPostIDTextReplyToIdempotencyKeyReceivedArguments?.idempotencyKey)
        #expect(fieldDuringRequest.isEmpty)
        #expect(viewModel.context.viewState.pendingComments.isEmpty)
        #expect(viewModel.context.viewState.visibleComments.last?.id == sent.id)
        #expect(try post(of: viewModel).counts.comments == 3)
    }

    /// A failure is not an answer: a refused comment stays with Retry, which sends the same text with the same key.
    @Test
    func aRefusedCommentStaysWithRetryUnderItsKey() async throws {
        let viewModel = try await loadedViewModel()
        // A refusal the server answered: nothing was made.
        service.createCommentPostIDTextReplyToIdempotencyKeyReturnValue = .failure(.rateLimited(retryAfterSeconds: 30))

        viewModel.context.commentText = "Nice"
        await viewModel.sendComment()
        let pending = try #require(viewModel.context.viewState.pendingComments.first)
        #expect(pending.delivery == .failed(.rateLimited(retryAfterSeconds: 30)))
        #expect(pending.comment.text == "Nice")
        #expect(viewModel.context.viewState.visibleComments.count == 2)
        #expect(viewModel.context.alertInfo?.id == .commentRefused)
        #expect(try post(of: viewModel).counts.comments == 2)

        let made = FeedPreviewData.comment(id: "01933f2b-0000-7000-8000-000000000009", author: FeedPreviewData.ann, minutesAgo: 0,
                                           text: "Nice", isAuthor: true)
        service.createCommentPostIDTextReplyToIdempotencyKeyReturnValue = .success(made)
        await viewModel.retryComment(try #require(pending.pendingKey))

        let invocations = service.createCommentPostIDTextReplyToIdempotencyKeyReceivedInvocations
        #expect(invocations.count == 2)
        #expect(invocations[0].idempotencyKey == invocations[1].idempotencyKey)
        #expect(invocations[1].text == "Nice")
        #expect(viewModel.context.viewState.pendingComments.isEmpty)
        #expect(viewModel.context.viewState.visibleComments.last?.id == made.id)
    }

    /// No answer: no alert, the comment says "Couldn't send" with Retry; Discard drops it.
    @Test(arguments: [FeedError.transport, .server(status: 502)])
    func aLostAnswerStaysWithRetryAndCanBeDiscarded(error: FeedError) async throws {
        let viewModel = try await loadedViewModel()
        service.createCommentPostIDTextReplyToIdempotencyKeyReturnValue = .failure(error)

        viewModel.context.commentText = "Nice"
        await viewModel.sendComment()

        let pending = try #require(viewModel.context.viewState.pendingComments.first)
        #expect(pending.delivery == .failed(error))
        #expect(viewModel.context.alertInfo == nil)

        viewModel.context.send(viewAction: .discardComment(try #require(pending.pendingKey)))
        #expect(viewModel.context.viewState.pendingComments.isEmpty)
        #expect(service.createCommentPostIDTextReplyToIdempotencyKeyCallsCount == 1)
    }

    /// Each comment sent has a key of its own.
    @Test
    func anotherCommentIsAnotherKey() async throws {
        let viewModel = try await loadedViewModel()
        service.createCommentPostIDTextReplyToIdempotencyKeyReturnValue = .failure(.transport)

        viewModel.context.commentText = "Nice"
        await viewModel.sendComment()
        viewModel.context.commentText = "Nice"
        await viewModel.sendComment()

        let keys = service.createCommentPostIDTextReplyToIdempotencyKeyReceivedInvocations.map(\.idempotencyKey)
        #expect(keys.count == 2)
        #expect(keys[0] != keys[1])
        #expect(viewModel.context.viewState.pendingComments.count == 2)
    }

    @Test
    func aReplySendsItsCommentAndAGoneOneIsLetGo() async throws {
        let viewModel = try await loadedViewModel()
        service.createCommentPostIDTextReplyToIdempotencyKeyReturnValue = .failure(.unprocessable)

        viewModel.context.send(viewAction: .reply(commentID: Self.first.id))
        #expect(viewModel.context.viewState.replyingTo?.id == Self.first.id)
        viewModel.context.commentText = "Agreed"
        await viewModel.sendComment()

        #expect(service.createCommentPostIDTextReplyToIdempotencyKeyReceivedArguments?.replyTo == Self.first.id)
        #expect(viewModel.context.viewState.replyingTo == nil)
        #expect(viewModel.context.alertInfo?.title == UntranslatedL10n.screenFeedCommentErrorReplyGoneTitle)
        #expect(viewModel.context.viewState.pendingComments.first?.comment.text == "Agreed")
        #expect(viewModel.context.viewState.pendingComments.first?.comment.replyTo?.id == Self.first.id)
    }

    @Test
    func theDailyCapIsNamedFromTheStanding() async throws {
        let viewModel = try await loadedViewModel()
        service.createCommentPostIDTextReplyToIdempotencyKeyReturnValue = .failure(.rateLimited(retryAfterSeconds: 20000))
        service.standingReturnValue = .success(FeedStanding(rulesVersion: FeedRules.version, rulesAccepted: true,
                                                            postsPerDay: 20, postsToday: 0, suspendedUntil: nil,
                                                            commentsPerDay: 20, commentsToday: 20))

        viewModel.context.commentText = "One more"
        await viewModel.sendComment()

        #expect(viewModel.context.alertInfo?.message == UntranslatedL10n.screenFeedCommentDailyCapNotice(20))
        #expect(viewModel.context.viewState.commentCapNotice == UntranslatedL10n.screenFeedCommentDailyCapNotice(20))
    }

    /// The first comment of someone who never posted meets the rules; agreeing sends the same comment with the same key.
    @Test
    func theRulesComeFirstAndAgreeingSendsTheSameComment() async throws {
        let viewModel = try await loadedViewModel()
        let sent = FeedPreviewData.comment(id: "01933f2b-0000-7000-8000-000000000009", author: FeedPreviewData.ann, minutesAgo: 0,
                                           text: "Hello", isAuthor: true)
        var answers: [Result<FeedComment, FeedError>] = [.failure(.rulesNotAccepted(currentVersion: FeedRules.version)), .success(sent)]
        service.createCommentPostIDTextReplyToIdempotencyKeyClosure = { _, _, _, _ in answers.removeFirst() }
        service.acceptRulesVersionReturnValue = .success(FeedStanding(rulesVersion: FeedRules.version, rulesAccepted: true,
                                                                      postsPerDay: nil, postsToday: 0, suspendedUntil: nil))

        viewModel.context.commentText = "Hello"
        await viewModel.sendComment()
        #expect(viewModel.context.isPresentingRules)
        #expect(viewModel.context.alertInfo == nil)

        await viewModel.acceptRules()

        let keys = service.createCommentPostIDTextReplyToIdempotencyKeyReceivedInvocations.map(\.idempotencyKey)
        #expect(keys.count == 2)
        #expect(keys[0] == keys[1])
        #expect(!viewModel.context.isPresentingRules)
        #expect(viewModel.context.viewState.visibleComments.last?.id == sent.id)
    }

    @Test
    func aHeldCommentShowsToItsAuthorWithoutCounting() async throws {
        let viewModel = try await loadedViewModel()
        let held = FeedPreviewData.comment(id: "01933f2b-0000-7000-8000-000000000009", author: FeedPreviewData.ann, minutesAgo: 0,
                                           text: "Hmm", state: .held, isAuthor: true)
        service.createCommentPostIDTextReplyToIdempotencyKeyReturnValue = .success(held)

        viewModel.context.commentText = "Hmm"
        await viewModel.sendComment()

        #expect(viewModel.context.viewState.visibleComments.last?.authorLabel == UntranslatedL10n.screenFeedPostHeldLabel)
        #expect(try post(of: viewModel).counts.comments == 2)
    }

    // MARK: - Delete a comment

    @Test
    func aCommentLeavesOnlyOnceTheServerDeletedIt() async throws {
        let viewModel = try await loadedViewModel()
        service.deleteCommentIdReturnValue = .failure(.server(status: 404))

        await viewModel.deleteComment(Self.second.id)
        #expect(viewModel.context.viewState.visibleComments.count == 2)
        #expect(viewModel.context.alertInfo?.id == .deleteCommentFailed)

        service.deleteCommentIdReturnValue = .success(())
        await viewModel.deleteComment(Self.first.id)
        #expect(viewModel.context.viewState.visibleComments.map(\.id) == [Self.second.id])
        #expect(viewModel.context.viewState.visibleComments[0].comment.replyTo == nil, "A reply loses its \"replying to\"")
        #expect(try post(of: viewModel).counts.comments == 1)
    }

    @Test
    func onlyADeletableCommentAsksToBeDeleted() async throws {
        let viewModel = try await loadedViewModel()

        viewModel.context.send(viewAction: .deleteComment(commentID: Self.first.id))
        #expect(viewModel.context.alertInfo == nil)

        viewModel.context.send(viewAction: .deleteComment(commentID: Self.second.id))
        #expect(viewModel.context.alertInfo?.id == .confirmDeleteComment(commentID: Self.second.id))
    }

    // MARK: - The author's switch, hide

    @Test
    func theCommentSwitchChangesOnlyWhenTheServerDid() async throws {
        service.postIdReturnValue = .success(Self.ownPost)
        let viewModel = try await loadedViewModel()
        #expect(viewModel.context.viewState.canToggleComments)

        service.setCommentsEnabledPostIDReturnValue = .failure(.transport)
        viewModel.context.send(viewAction: .setCommentsEnabled(false))
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .actionFailed }
        try await failed.fulfill()
        #expect(try post(of: viewModel).commentsEnabled)

        service.setCommentsEnabledPostIDReturnValue = .success(Self.ownPost.withCommentsEnabled(false))
        let off = deferFulfillment(viewModel.context.observe(\.viewState.post)) { $0?.commentsEnabled == false }
        viewModel.context.send(viewAction: .setCommentsEnabled(false))
        try await off.fulfill()
        #expect(service.setCommentsEnabledPostIDReceivedArguments?.enabled == false)
        #expect(viewModel.context.viewState.visibleComments.count == 2, "The author keeps seeing them")
    }

    /// `feed.post_updated` from the sync stream: the shown post is read again, and comments turned off leave.
    @Test
    func commentsTurnedOffElsewhereLeaveTheScreen() async throws {
        let viewModel = try await loadedViewModel()
        viewModel.context.send(viewAction: .appeared)
        service.postIdReturnValue = .success(Self.post.withCommentsEnabled(false))

        let off = deferFulfillment(viewModel.context.observe(\.viewState.commentsState)) { $0 == .off }
        engagement.store.apply([.postUpdated(postID: Self.post.id)])
        try await off.fulfill()

        #expect(!viewModel.context.viewState.canComment)
        #expect(service.postIdCallsCount == 2)
    }

    /// A post gone for the person (`feed.post_state` → gone) is "not available" where it is open.
    @Test
    func aPostGoneWhileOpenIsNotAvailable() async throws {
        let viewModel = try await loadedViewModel()

        let gone = deferFulfillment(viewModel.context.observe(\.viewState.visibleLoadState)) { $0 == .notAvailable }
        engagement.store.apply([.postState(postID: Self.post.id, state: .other("gone"))])
        try await gone.fulfill()
    }

    @Test
    func aPostIsHiddenOnlyOnceTheServerHidIt() async throws {
        let viewModel = try await loadedViewModel()
        #expect(viewModel.context.viewState.canHide)

        service.setHiddenPostIDReturnValue = .failure(.transport)
        await viewModel.hide()
        #expect(!viewModel.context.viewState.isHidden)

        service.setHiddenPostIDReturnValue = .success(())
        await viewModel.hide()
        #expect(viewModel.context.viewState.isHidden)
        #expect(!viewModel.context.viewState.canHide)
        #expect(service.setHiddenPostIDReceivedArguments?.hidden == true)
    }

    @Test
    func onlyOthersHideAndAHiddenPostCanComeBack() async throws {
        service.postIdReturnValue = .success(Self.ownPost)
        var viewModel = try await loadedViewModel()
        #expect(!viewModel.context.viewState.canHide)

        var hidden = Self.post
        hidden.viewer.hidden = true
        service.postIdReturnValue = .success(hidden)
        viewModel = try await loadedViewModel()
        #expect(viewModel.context.viewState.isHidden)
        #expect(!viewModel.context.viewState.canHide)

        service.setHiddenPostIDReturnValue = .success(())
        let shown = deferFulfillment(viewModel.context.observe(\.viewState.post)) { $0?.viewer.hidden == false }
        viewModel.context.send(viewAction: .unhide)
        try await shown.fulfill()
        #expect(service.setHiddenPostIDReceivedArguments?.hidden == false)
    }

    // MARK: - Share

    /// Decision 267: a sensitive post is shared only after "Show".
    @Test
    func aSensitivePostIsSharedOnlyOnceShown() async throws {
        service.postIdReturnValue = .success(FeedPreviewData.sensitivePost)
        let viewModel = try await loadedViewModel()
        var shared = 0
        let cancellable = viewModel.actionsPublisher.sink { if case .share = $0 { shared += 1 } }
        defer { cancellable.cancel() }

        viewModel.context.send(viewAction: .card(.share))
        #expect(shared == 0)

        viewModel.context.send(viewAction: .card(.reveal))
        viewModel.context.send(viewAction: .card(.share))
        #expect(shared == 1)
    }

    // MARK: - Sensitive (decision 265)

    @Test
    func aSensitiveCommentsTextIsNotReadUntilShown() {
        let item = FeedCommentItem(comment: FeedPreviewData.comment(id: "01933f2b-0000-7000-8000-000000000003", author: FeedPreviewData.bob,
                                                                    minutesAgo: 1, text: "Secret words", isSensitive: true))

        #expect(!item.accessibilityLabel(isRevealed: false).contains("Secret words"))
        #expect(item.accessibilityLabel(isRevealed: true).contains("Secret words"))
    }

    @Test
    func aCommentStateNewerThanTheAppIsNotAvailable() {
        let item = FeedCommentItem(comment: FeedPreviewData.comment(id: "01933f2b-0000-7000-8000-000000000003", author: FeedPreviewData.bob,
                                                                    minutesAgo: 1, text: "x", state: .other("archived")))

        #expect(!item.isAvailable)
        #expect(item.accessibilityLabel(isRevealed: true) == UntranslatedL10n.screenFeedCommentNotAvailable)
    }

    // MARK: - Refusals are not the connection (L-b)

    /// Only "no answer" blames the connection; a server's refusal of a comment says what it refused.
    @Test(arguments: [(FeedError.temporarilyUnavailable(retryAfterSeconds: 5), UntranslatedL10n.screenFeedCommentErrorTryShortlyMessage),
                      (.forbidden, UntranslatedL10n.screenFeedCommentErrorAccountRestrictedMessage),
                      (.server(status: 500), UntranslatedL10n.screenFeedCommentErrorServerMessage),
                      (.server(status: 400), UntranslatedL10n.screenFeedCommentErrorServerMessage),
                      (.transport, UntranslatedL10n.screenFeedCommentErrorGenericMessage)])
    func aRefusedCommentIsNotBlamedOnTheConnection(error: FeedError, message: String) {
        #expect(FeedPostScreenViewModel.commentMessage(for: error).message == message)
    }

    @Test(arguments: [(FeedError.transport, UntranslatedL10n.screenFeedCommentDeleteFailedMessage),
                      (.unavailable, UntranslatedL10n.screenFeedCommentDeleteFailedUnavailableMessage),
                      (.rateLimited(retryAfterSeconds: 10), UntranslatedL10n.screenFeedCommentDeleteFailedTryShortlyMessage),
                      (.temporarilyUnavailable(retryAfterSeconds: nil), UntranslatedL10n.screenFeedCommentDeleteFailedTryShortlyMessage),
                      (.forbidden, UntranslatedL10n.screenFeedCommentDeleteFailedAccountRestrictedMessage),
                      (.server(status: 500), UntranslatedL10n.screenFeedCommentDeleteFailedServerMessage)])
    func aFailedCommentDeleteSaysWhy(error: FeedError, message: String) async throws {
        service.deleteCommentIdReturnValue = .failure(error)
        let viewModel = try await loadedViewModel()

        await viewModel.deleteComment(Self.second.id)

        #expect(viewModel.context.alertInfo?.message == message)
    }

    /// An unhide, the comment switch and a report share one message per refusal.
    @Test(arguments: [(FeedError.transport, UntranslatedL10n.screenFeedActionFailedMessage),
                      (.unavailable, UntranslatedL10n.screenFeedActionFailedUnavailableMessage),
                      (.rateLimited(retryAfterSeconds: nil), UntranslatedL10n.screenFeedActionFailedTryShortlyMessage),
                      (.temporarilyUnavailable(retryAfterSeconds: 3), UntranslatedL10n.screenFeedActionFailedTryShortlyMessage),
                      (.forbidden, UntranslatedL10n.screenFeedActionFailedAccountRestrictedMessage),
                      (.server(status: 502), UntranslatedL10n.screenFeedActionFailedServerMessage)])
    func aRefusedActionSaysWhy(error: FeedError, message: String) {
        #expect(error.actionFailedMessage == message)
    }

    @Test
    func aRefusedReportIsNotBlamedOnTheConnection() {
        let alert = FeedReportScreenViewModel.alert(for: .server(status: 500)) { }
        #expect(alert.message == UntranslatedL10n.screenFeedActionFailedServerMessage)
    }
}
