//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). One post by id: "not available" for
// every reason the server or the person's blocks give, and a failed read
// that never pretends the post is gone.
//

import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct FeedPostScreenViewModelTests {
    private let service = FeedServiceMock()
    private let ignoredUsers = CurrentValueSubject<[String]?, Never>([])
    private let clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md"))

    init() {
        // Lane I3 on B4: the notices behind the badge and a held post's banner.
        service.noticesUnreadPublisher = Empty().eraseToAnyPublisher()
        service.activityUnreadPublisher = Empty().eraseToAnyPublisher()
        service.noticesCursorLimitLanguageReturnValue = .success(FeedNoticePage(items: [], nextCursor: nil, unread: 0))
        clientProxy.ignoredUsersPublisher = ignoredUsers.asCurrentValuePublisher()
        service.commentsPostIDCursorLimitReturnValue = .success(FeedCommentPage(items: [], nextCursor: nil))
    }

    private func loadedViewModel(post: FeedPost? = nil) async throws -> FeedPostScreenViewModel {
        let viewModel = FeedPostScreenViewModel(postID: FeedPreviewData.textPost.id,
                                                post: post,
                                                feedService: service,
                                                engagement: FeedEngagementController.make(service, userIndicatorController: UserIndicatorControllerMock()),
                                                clientProxy: clientProxy,
                                                mediaProvider: MediaProviderMock(.init()),
                                                userIndicatorController: UserIndicatorControllerMock())
        let read = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { _ in service.postIdCallsCount == 1 }
        try await read.fulfill()
        await Task.yield()
        return viewModel
    }

    @Test
    func aVisiblePostIsShown() async throws {
        service.postIdReturnValue = .success(FeedPreviewData.textPost)

        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.visibleLoadState == .loaded(FeedItem(post: FeedPreviewData.textPost)))
        #expect(service.postIdReceivedId == FeedPreviewData.textPost.id)
        #expect(viewModel.context.viewState.authorNotice == nil)
    }

    @Test(arguments: [FeedPostState.hiddenAuthor, .other("archived")])
    func aStateThePostScreenDoesNotShowIsNotAvailable(state: FeedPostState) async throws {
        service.postIdReturnValue = .success(FeedPreviewData.post(id: FeedPreviewData.textPost.id, author: FeedPreviewData.ann,
                                                                  minutesAgo: 1, text: "x", state: state))

        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.visibleLoadState == .notAvailable)
    }

    @Test
    func mediaIsHiddenUntilTheSettingArrives() {
        service.postIdReturnValue = .success(FeedPreviewData.textPost)
        let viewModel = FeedPostScreenViewModel(postID: FeedPreviewData.textPost.id,
                                                post: FeedPreviewData.textPost,
                                                feedService: service,
                                                engagement: FeedEngagementController.make(service, userIndicatorController: UserIndicatorControllerMock()),
                                                clientProxy: clientProxy,
                                                mediaProvider: MediaProviderMock(.init()),
                                                userIndicatorController: UserIndicatorControllerMock())

        #expect(viewModel.context.viewState.hidesMedia)
    }

    @Test
    func aHeldPostTellsItsAuthorWhy() async throws {
        service.postIdReturnValue = .success(FeedPreviewData.post(id: FeedPreviewData.textPost.id, author: FeedPreviewData.ann, minutesAgo: 1,
                                                                  text: "x", state: .held, heldReason: .filter, isAuthor: true))

        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.authorNotice == UntranslatedL10n.screenFeedPostHeldNotice)
    }

    @Test
    func aPostNotThereIsNotAvailable() async throws {
        service.postIdReturnValue = .failure(.notFound)

        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.visibleLoadState == .notAvailable)
    }

    /// A post a list showed and that is gone now (deleted, or its author left) is not available.
    @Test
    func aPostGoneSinceTheListIsNotAvailable() async throws {
        service.postIdReturnValue = .failure(.notFound)

        let viewModel = try await loadedViewModel(post: FeedPreviewData.textPost)

        #expect(viewModel.context.viewState.visibleLoadState == .notAvailable)
    }

    /// A read that failed is "couldn't load", never "not available".
    @Test
    func aFailedReadIsNotNotAvailable() async throws {
        service.postIdReturnValue = .failure(.transport)

        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.visibleLoadState == .failed)
    }

    @Test
    func aFailedReReadKeepsThePostTheListShowed() async {
        service.postIdReturnValue = .failure(.transport)
        let viewModel = FeedPostScreenViewModel(postID: FeedPreviewData.textPost.id,
                                                post: FeedPreviewData.textPost,
                                                feedService: service,
                                                engagement: FeedEngagementController.make(service, userIndicatorController: UserIndicatorControllerMock()),
                                                clientProxy: clientProxy,
                                                mediaProvider: MediaProviderMock(.init()),
                                                userIndicatorController: UserIndicatorControllerMock())

        // The state does not change, so there is nothing to observe: read again directly.
        await viewModel.load()

        #expect(service.postIdCalled)
        #expect(viewModel.context.viewState.visibleLoadState == .loaded(FeedItem(post: FeedPreviewData.textPost)))
    }

    @Test
    func aBlockedAuthorsPostIsNotAvailable() async throws {
        service.postIdReturnValue = .success(FeedPreviewData.textPost)
        let viewModel = try await loadedViewModel()

        let hidden = deferFulfillment(viewModel.context.observe(\.viewState.blockedUserIDs)) { !$0.isEmpty }
        ignoredUsers.send([FeedPreviewData.textPost.author.userID])
        try await hidden.fulfill()

        #expect(viewModel.context.viewState.visibleLoadState == .notAvailable)
    }

    // MARK: - Delete (lane I2)

    private static let ownPost = FeedPreviewData.post(id: FeedPreviewData.textPost.id, author: FeedPreviewData.ann, minutesAgo: 1,
                                                      text: "Mine", state: .held, heldReason: .filter, isAuthor: true)

    @Test
    func onlyTheAuthorCanDelete() async throws {
        service.postIdReturnValue = .success(FeedPreviewData.textPost)
        let viewModel = try await loadedViewModel()
        #expect(!viewModel.context.viewState.canDelete)

        viewModel.context.send(viewAction: .delete)
        #expect(viewModel.context.alertInfo == nil)
    }

    @Test
    func deletingAsksFirstAndClosesOnceTheServerSaysItWent() async throws {
        service.postIdReturnValue = .success(Self.ownPost)
        service.deletePostIdReturnValue = .success(())
        let viewModel = try await loadedViewModel()
        #expect(viewModel.context.viewState.canDelete)

        viewModel.context.send(viewAction: .delete)
        let alert = try #require(viewModel.context.alertInfo)
        #expect(alert.id == .confirmDelete)
        #expect(!service.deletePostIdCalled)

        let deleted = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .deleted = action { true } else { false }
        }
        alert.secondaryButton?.action?()
        try await deleted.fulfill()
        #expect(service.deletePostIdReceivedId == Self.ownPost.id)
    }

    @Test
    func aFailedDeleteNeverLooksDeleted() async throws {
        service.postIdReturnValue = .success(Self.ownPost)
        service.deletePostIdReturnValue = .failure(.transport)
        let viewModel = try await loadedViewModel()
        var actions = 0
        let cancellable = viewModel.actionsPublisher.sink { _ in actions += 1 }

        await viewModel.deletePost()

        #expect(actions == 0)
        #expect(viewModel.context.alertInfo?.id == .deleteFailed)
        #expect(viewModel.context.viewState.visibleLoadState == .loaded(FeedItem(post: Self.ownPost)))
        _ = cancellable
    }

    /// A held post is not in the feed, and a refusal is not the connection (L-b).
    @Test(arguments: [(FeedError.transport, UntranslatedL10n.screenFeedPostDeleteFailedMessage),
                      (.unavailable, UntranslatedL10n.screenFeedPostDeleteFailedUnavailableMessage),
                      (.rateLimited(retryAfterSeconds: 10), UntranslatedL10n.screenFeedPostDeleteFailedTryShortlyMessage),
                      (.temporarilyUnavailable(retryAfterSeconds: nil), UntranslatedL10n.screenFeedPostDeleteFailedTryShortlyMessage),
                      (.forbidden, UntranslatedL10n.screenFeedPostDeleteFailedAccountRestrictedMessage),
                      (.server(status: 500), UntranslatedL10n.screenFeedPostDeleteFailedServerMessage)])
    func aFailedDeleteSaysWhy(error: FeedError, message: String) async throws {
        service.postIdReturnValue = .success(Self.ownPost)
        service.deletePostIdReturnValue = .failure(error)
        let viewModel = try await loadedViewModel()

        await viewModel.deletePost()

        #expect(viewModel.context.alertInfo?.message == message)
    }

    /// `404` on a delete is "no post of yours with this id": it is gone already.
    @Test
    func aPostAlreadyGoneIsDeleted() async throws {
        service.postIdReturnValue = .success(Self.ownPost)
        service.deletePostIdReturnValue = .failure(.notFound)
        let viewModel = try await loadedViewModel()
        var deleted = false
        let cancellable = viewModel.actionsPublisher.sink { action in
            if case .deleted = action { deleted = true }
        }

        await viewModel.deletePost()

        #expect(deleted)
        _ = cancellable
    }
}
