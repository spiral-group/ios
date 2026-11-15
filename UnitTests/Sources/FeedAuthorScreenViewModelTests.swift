//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The author sheet: their posts, a global
// block behind a confirmation, and Message into an existing or new chat.
//

import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct FeedAuthorScreenViewModelTests {
    private let service = FeedServiceMock()
    private let clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md"))

    private let engagement: FeedEngagementController

    init() {
        engagement = .make(service)
        clientProxy.ignoredUsersPublisher = CurrentValueSubject<[String]?, Never>([]).asCurrentValuePublisher()
        service.authorPostsUserIDCursorLimitReturnValue = .success(FeedPage(items: [FeedPreviewData.textPost], nextCursor: nil, pinned: nil))
        service.ownPostsCursorLimitReturnValue = .success(FeedPage(items: [], nextCursor: nil, pinned: nil))
    }

    private func loadedViewModel(author: FeedAuthor = FeedPreviewData.ann) async throws -> FeedAuthorScreenViewModel {
        let viewModel = FeedAuthorScreenViewModel(author: author,
                                                  feedService: service,
                                                  engagement: engagement,
                                                  clientProxy: clientProxy,
                                                  mediaProvider: MediaProviderMock(.init()),
                                                  userIndicatorController: UserIndicatorControllerMock())
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.postsState)) { $0 != .loading }
        try await loaded.fulfill()
        return viewModel
    }

    @Test
    func theirPostsAreReadByTheirMXID() async throws {
        let viewModel = try await loadedViewModel()

        #expect(service.authorPostsUserIDCursorLimitReceivedArguments?.userID == FeedPreviewData.ann.userID)
        #expect(viewModel.context.viewState.postsState == .loaded([FeedItem(post: FeedPreviewData.textPost)], loadMore: .exhausted))
        #expect(viewModel.context.viewState.isOwnProfile == false)
    }

    /// Decision 289: hidden, it leaves at once; shown again (from another device too), the sheet reads its first page again.
    @Test
    func aPostShownAgainComesBackToTheSheet() async throws {
        let viewModel = try await loadedViewModel()
        viewModel.context.send(viewAction: .appeared)
        let shown = FeedPreviewData.textPost

        engagement.store.apply([.hidden(postID: shown.id)])
        #expect(engagement.store.list(.author(userID: shown.author.userID))?.ids == [])

        let back = deferFulfillment(viewModel.context.observe(\.viewState.postsState)) { state in
            if case .loaded(let items, _) = state { items.map(\.id) == [shown.id] } else { false }
        }
        engagement.store.apply([.unhidden(postID: shown.id)])
        try await back.fulfill()
        #expect(service.authorPostsUserIDCursorLimitCallsCount == 2)
    }

    @Test
    func anAuthorNotThereIsNotAvailableAndAFailureIsNot() async throws {
        service.authorPostsUserIDCursorLimitReturnValue = .failure(.notFound)
        #expect(try await loadedViewModel().context.viewState.postsState == .notAvailable)

        service.authorPostsUserIDCursorLimitReturnValue = .failure(.transport)
        #expect(try await loadedViewModel().context.viewState.postsState == .failed)
    }

    /// An empty page with a cursor is not "No posts yet": the sheet reads on, as Latest does.
    @Test
    func anEmptyPageWithACursorIsReadPast() async throws {
        let posts = FeedPreviewData.posts(2)
        service.authorPostsUserIDCursorLimitClosure = { _, cursor, _ in
            switch cursor {
            case nil: .success(FeedPage(items: [], nextCursor: "c1", pinned: nil))
            case "c1": .success(FeedPage(items: [], nextCursor: "c2", pinned: nil))
            default: .success(FeedPage(items: posts, nextCursor: nil, pinned: nil))
            }
        }
        let viewModel = FeedAuthorScreenViewModel(author: FeedPreviewData.ann,
                                                  feedService: service,
                                                  engagement: engagement,
                                                  clientProxy: clientProxy,
                                                  mediaProvider: MediaProviderMock(.init()),
                                                  userIndicatorController: UserIndicatorControllerMock())

        let shown = deferFulfillment(viewModel.context.observe(\.viewState.postsState)) { state in
            if case .loaded(let items, .exhausted) = state { items.count == 2 } else { false }
        }
        try await shown.fulfill()

        #expect(viewModel.context.viewState.isEmpty == false)
        #expect(service.authorPostsUserIDCursorLimitCallsCount == 3)
    }

    @Test
    func onlyAFinishedEmptyReadIsNoPosts() async throws {
        service.authorPostsUserIDCursorLimitReturnValue = .success(FeedPage(items: [], nextCursor: nil, pinned: nil))

        #expect(try await loadedViewModel().context.viewState.isEmpty)
    }

    @Test
    func mediaIsHiddenUntilTheSettingArrives() {
        let viewModel = FeedAuthorScreenViewModel(author: FeedPreviewData.ann,
                                                  feedService: service,
                                                  engagement: engagement,
                                                  clientProxy: clientProxy,
                                                  mediaProvider: MediaProviderMock(.init()),
                                                  userIndicatorController: UserIndicatorControllerMock())

        #expect(viewModel.context.viewState.hidesMedia)
    }

    @Test
    func theOwnSheetIsMarkedOwn() async throws {
        let viewModel = try await loadedViewModel(author: FeedAuthor(userID: "@me:spiral.md", name: "Me", avatarURL: nil, bio: nil, isOfficial: false, isNameWithheld: false))

        #expect(viewModel.context.viewState.isOwnProfile)
    }

    // MARK: - Block

    /// The confirmation says the block is global, and only its confirm blocks.
    @Test
    func blockAsksFirstAndSaysItIsGlobal() async throws {
        let viewModel = try await loadedViewModel()

        viewModel.context.send(viewAction: .block)

        let alert = try #require(viewModel.context.alertInfo)
        #expect(alert.id == .confirmBlock)
        #expect(alert.message == UntranslatedL10n.screenFeedAuthorBlockMessage)
        #expect(clientProxy.ignoreUserCalled == false)

        let dismissed = deferFulfillment(viewModel.actionsPublisher) { if case .dismiss = $0 { true } else { false } }
        alert.secondaryButton?.action?()
        try await dismissed.fulfill()

        #expect(clientProxy.ignoreUserReceivedUserID == FeedPreviewData.ann.userID)
    }

    @Test
    func aFailedBlockSaysSo() async throws {
        clientProxy.ignoreUserReturnValue = .failure(.sdkError(ClientProxyMockError.generic))
        let viewModel = try await loadedViewModel()

        viewModel.context.send(viewAction: .block)
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo?.id)) { $0 == .blockFailed }
        viewModel.context.alertInfo?.secondaryButton?.action?()
        try await failed.fulfill()
    }

    // MARK: - Message

    @Test
    func messageOpensTheExistingChat() async throws {
        clientProxy.directRoomOrPendingInviteForUserIDClosure = { _ in .success("!dm:spiral.md") }
        let viewModel = try await loadedViewModel()

        let opened = deferFulfillment(viewModel.actionsPublisher) { if case .openRoom("!dm:spiral.md") = $0 { true } else { false } }
        viewModel.context.send(viewAction: .message)
        try await opened.fulfill()
        #expect(clientProxy.createDirectRoomWithExpectedRoomNameCalled == false)
    }

    @Test
    func messageAsksBeforeStartingANewChat() async throws {
        clientProxy.directRoomOrPendingInviteForUserIDClosure = { _ in .success(nil) }
        clientProxy.createDirectRoomWithExpectedRoomNameReturnValue = .success("!new:spiral.md")
        let viewModel = try await loadedViewModel()

        viewModel.context.send(viewAction: .message)
        let alert = try #require(viewModel.context.alertInfo)
        #expect(alert.id == .confirmStartChat)

        let opened = deferFulfillment(viewModel.actionsPublisher) { if case .openRoom("!new:spiral.md") = $0 { true } else { false } }
        alert.secondaryButton?.action?()
        try await opened.fulfill()
    }

    /// Decision 272: a chat would show the real display name the feed filter withheld.
    @Test
    func messageIsRefusedForAnAuthorWhoseNameIsWithheld() async throws {
        clientProxy.directRoomOrPendingInviteForUserIDClosure = { _ in .success("!dm:spiral.md") }
        let viewModel = try await loadedViewModel(author: FeedPreviewData.withheld)
        var actions: [FeedAuthorScreenViewModelAction] = []
        let subscription = viewModel.actionsPublisher.sink { actions.append($0) }

        viewModel.context.send(viewAction: .message)
        await Task.yield()

        #expect(!clientProxy.directRoomOrPendingInviteForUserIDCalled)
        #expect(!clientProxy.createDirectRoomWithExpectedRoomNameCalled)
        #expect(viewModel.context.alertInfo == nil)
        #expect(actions.isEmpty)
        #expect(!viewModel.context.viewState.canMessage)
        subscription.cancel()
    }

    @Test
    func anAuthorShownByNameCanBeMessagedAndBlocked() async throws {
        let viewModel = try await loadedViewModel()

        #expect(viewModel.context.viewState.canMessage)
        #expect(viewModel.context.viewState.canBlock)
    }

    /// Operator, 2026-11-13: nobody reads the official account's chats, and blocking it would ignore Spiral itself.
    @Test
    func theOfficialAccountHasReportButNoMessageOrBlock() async throws {
        clientProxy.directRoomOrPendingInviteForUserIDClosure = { _ in .success("!dm:spiral.md") }
        let viewModel = try await loadedViewModel(author: FeedPreviewData.spiral)
        var actions: [FeedAuthorScreenViewModelAction] = []
        let subscription = viewModel.actionsPublisher.sink { actions.append($0) }

        #expect(!viewModel.context.viewState.canMessage)
        #expect(!viewModel.context.viewState.canBlock)

        viewModel.context.send(viewAction: .message)
        viewModel.context.send(viewAction: .block)
        await Task.yield()

        #expect(!clientProxy.directRoomOrPendingInviteForUserIDCalled)
        #expect(!clientProxy.createDirectRoomWithExpectedRoomNameCalled)
        #expect(!clientProxy.ignoreUserCalled)
        #expect(viewModel.context.alertInfo == nil)
        #expect(actions.isEmpty)
        subscription.cancel()

        let reported = deferFulfillment(viewModel.actionsPublisher) { if case .report(.author(FeedPreviewData.spiral.userID)) = $0 { true } else { false } }
        viewModel.context.send(viewAction: .report)
        try await reported.fulfill()
    }

    /// Block and Report stay for an author whose name is withheld.
    @Test
    func blockAndReportStayForAnAuthorWhoseNameIsWithheld() async throws {
        let viewModel = try await loadedViewModel(author: FeedPreviewData.withheld)

        viewModel.context.send(viewAction: .block)
        #expect(viewModel.context.alertInfo?.id == .confirmBlock)
        // M1: the alert names the neutral name, never the localpart.
        #expect(viewModel.context.alertInfo?.title == UntranslatedL10n.screenFeedAuthorBlockTitle(UntranslatedL10n.screenFeedAuthorWithheldName))
        #expect(viewModel.context.viewState.author.shownUserID == nil)

        let reported = deferFulfillment(viewModel.actionsPublisher) { if case .report(.author(FeedPreviewData.withheld.userID)) = $0 { true } else { false } }
        viewModel.context.send(viewAction: .report)
        try await reported.fulfill()
    }

    // MARK: - Own posts (lane I2)

    @Test
    func theOwnSheetReadsEveryStateOfTheirPosts() async throws {
        let me = FeedAuthor(userID: "@me:spiral.md", name: "Me", avatarURL: nil, bio: nil, isOfficial: false, isNameWithheld: false)
        let held = FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000501", author: me, minutesAgo: 1, text: "Held",
                                        state: .held, heldReason: .filter, isAuthor: true)
        service.ownPostsCursorLimitReturnValue = .success(FeedPage(items: [held], nextCursor: nil, pinned: nil))

        let viewModel = try await loadedViewModel(author: me)

        #expect(service.ownPostsCursorLimitCalled)
        #expect(!service.authorPostsUserIDCursorLimitCalled)
        #expect(viewModel.context.viewState.postsState == .loaded([FeedItem(post: held)], loadMore: .exhausted))
        #expect(FeedAuthorScreen.ownStateLabel(held) == UntranslatedL10n.screenFeedPostHeldLabel)
        #expect(FeedAuthorScreen.ownStateLabel(FeedPreviewData.textPost) == nil)
    }

    /// Decision 289: a post gone for the person (`feed.post_state` → gone) leaves the sheet at once.
    @Test
    func aPostGoneLeavesTheSheetAtOnce() async throws {
        let viewModel = try await loadedViewModel()

        let gone = deferFulfillment(viewModel.context.observe(\.viewState.postsState)) { $0 == .loaded([], loadMore: .exhausted) }
        engagement.store.apply([.postState(postID: FeedPreviewData.textPost.id, state: .other("gone"))])
        try await gone.fulfill()
    }

    /// `422 idempotency-key-reused`: an earlier version is published, which the own sheet, shown, reads in.
    @Test
    func anEarlierVersionPublishedIsReadIntoTheOwnSheet() async throws {
        let me = FeedAuthor(userID: "@me:spiral.md", name: "Me", avatarURL: nil, bio: nil, isOfficial: false, isNameWithheld: false)
        let viewModel = try await loadedViewModel(author: me)
        viewModel.context.send(viewAction: .appeared)
        #expect(viewModel.context.viewState.postsState == .loaded([], loadMore: .exhausted))

        let earlier = FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000503", author: me, minutesAgo: 1, text: "Earlier",
                                           isAuthor: true)
        service.ownPostsCursorLimitReturnValue = .success(FeedPage(items: [earlier], nextCursor: nil, pinned: nil))
        service.createPostTextIdempotencyKeyReturnValue = .failure(.idempotencyKeyReused)
        let readIn = deferFulfillment(viewModel.context.observe(\.viewState.postsState)) { $0 == .loaded([FeedItem(post: earlier)], loadMore: .exhausted) }
        await engagement.store.publishPost(text: "Later", idempotencyKey: UUID())
        try await readIn.fulfill()
    }

    /// The own sheet reads on past empty pages in `/feed/me/posts`, never in the public route.
    @Test
    func theOwnSheetReadsOnInItsOwnRoute() async throws {
        let me = FeedAuthor(userID: "@me:spiral.md", name: "Me", avatarURL: nil, bio: nil, isOfficial: false, isNameWithheld: false)
        let held = FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000502", author: me, minutesAgo: 1, text: "Held",
                                        state: .held, isAuthor: true)
        service.ownPostsCursorLimitClosure = { cursor, _ in
            cursor == nil ? .success(FeedPage(items: [], nextCursor: "c1", pinned: nil)) : .success(FeedPage(items: [held], nextCursor: nil, pinned: nil))
        }
        let viewModel = FeedAuthorScreenViewModel(author: me,
                                                  feedService: service,
                                                  engagement: engagement,
                                                  clientProxy: clientProxy,
                                                  mediaProvider: MediaProviderMock(.init()),
                                                  userIndicatorController: UserIndicatorControllerMock())

        let shown = deferFulfillment(viewModel.context.observe(\.viewState.postsState)) { $0 == .loaded([FeedItem(post: held)], loadMore: .exhausted) }
        try await shown.fulfill()

        #expect(service.ownPostsCursorLimitCallsCount == 2)
        #expect(!service.authorPostsUserIDCursorLimitCalled)
    }
}
