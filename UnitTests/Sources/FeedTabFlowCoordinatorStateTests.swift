//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The Feed tab's transition table with the
// composer sheet of lane I2: one sheet at a time, back to Latest on dismissal;
// its sheets in the running flow (lane I3); Activity, who liked and the tab's
// badge (lane I5).
//

import Combine
@testable import Spiral
import Testing

@MainActor
struct FeedTabFlowCoordinatorStateTests {
    @Test
    func theComposerOpensFromLatestOnlyAndReturnsThere() {
        #expect(FeedTabFlowCoordinator.nextState(from: .feed, on: .presentComposer) == .composerSheet)
        #expect(FeedTabFlowCoordinator.nextState(from: .composerSheet, on: .dismissedComposer) == .feed)
        #expect(FeedTabFlowCoordinator.nextState(from: .authorSheet, on: .presentComposer) == nil)
        #expect(FeedTabFlowCoordinator.nextState(from: .composerSheet, on: .presentAuthor) == nil)
        #expect(FeedTabFlowCoordinator.nextState(from: .composerSheet, on: .dismissedAuthor) == nil)
        #expect(FeedTabFlowCoordinator.nextState(from: .initial, on: .presentComposer) == nil)
    }

    /// Lane I3 on B4: a report opens from Latest or a post, one sheet at a time.
    @Test
    func theReportOpensFromLatestOnlyAndReturnsThere() {
        #expect(FeedTabFlowCoordinator.nextState(from: .feed, on: .presentReport) == .reportSheet)
        #expect(FeedTabFlowCoordinator.nextState(from: .reportSheet, on: .dismissedReport) == .feed)
        #expect(FeedTabFlowCoordinator.nextState(from: .reportSheet, on: .presentReport) == nil)
        #expect(FeedTabFlowCoordinator.nextState(from: .shareSheet, on: .presentReport) == nil)
        #expect(FeedTabFlowCoordinator.nextState(from: .reportSheet, on: .presentAuthor) == nil)
        #expect(FeedTabFlowCoordinator.nextState(from: .authorSheet, on: .dismissedReport) == nil)
    }

    /// Lane I5: who liked opens from Latest or a post, one sheet at a time.
    @Test
    func theLikersOpenFromLatestOnlyAndReturnThere() {
        #expect(FeedTabFlowCoordinator.nextState(from: .feed, on: .presentLikers) == .likersSheet)
        #expect(FeedTabFlowCoordinator.nextState(from: .likersSheet, on: .dismissedLikers) == .feed)
        #expect(FeedTabFlowCoordinator.nextState(from: .likersSheet, on: .presentLikers) == nil)
        #expect(FeedTabFlowCoordinator.nextState(from: .likersSheet, on: .presentAuthor) == nil)
        #expect(FeedTabFlowCoordinator.nextState(from: .authorSheet, on: .presentLikers) == nil)
        #expect(FeedTabFlowCoordinator.nextState(from: .feed, on: .dismissedLikers) == nil)
    }
}

/// The share sheet in the tab's flow: one at a time, and a late answer
/// closes only the sheet it came from.
@MainActor
struct FeedTabFlowCoordinatorSheetTests {
    private let feed = FeedServiceMock.empty()
    private let indicators = UserIndicatorControllerMock()
    private let splitCoordinator = NavigationSplitCoordinator(placeholderCoordinator: PlaceholderScreenCoordinator(hideBrandChrome: false))
    private let post = FeedPreviewData.textPost
    private let sync = PlatformSyncServiceMock.unavailable()

    init() {
        feed.latestCursorLimitReturnValue = .success(FeedPage(items: [post], nextCursor: nil, pinned: nil))
        feed.postIdReturnValue = .success(post)
    }

    private func startedFlow() async throws -> (FeedTabFlowCoordinator, FeedScreenViewModel) {
        let flowCoordinator = FeedTabFlowCoordinator(navigationSplitCoordinator: splitCoordinator, flowParameters: flowParameters())
        flowCoordinator.start(animated: false)
        let stack = try #require(splitCoordinator.sidebarCoordinator as? NavigationStackCoordinator)
        let latest = try #require((stack.rootCoordinator as? FeedScreenCoordinator)?.viewModel as? FeedScreenViewModel)
        let loaded = deferFulfillment(latest.context.observe(\.viewState.visibleItems.count)) { $0 == 1 }
        try await loaded.fulfill()
        return (flowCoordinator, latest)
    }

    /// A double tap on Share, or a share while another sheet is up, is
    /// dropped: it used to reach the state machine's `fatalError`.
    @Test
    func aSecondPresentWhileASheetIsUpIsIgnored() async throws {
        let (flowCoordinator, latest) = try await startedFlow()

        latest.context.send(viewAction: .card(postID: post.id, .share))
        let picker = try #require(splitCoordinator.sheetCoordinator as? NavigationStackCoordinator)
        #expect(picker.rootCoordinator is MessageForwardingScreenCoordinator)

        latest.context.send(viewAction: .card(postID: post.id, .share))
        latest.context.send(viewAction: .card(postID: post.id, .openAuthor))
        latest.context.send(viewAction: .compose)

        #expect(splitCoordinator.sheetCoordinator === picker)
        withExtendedLifetime(flowCoordinator) { }
    }

    /// A second tap on an author (on Latest or in a post), the composer or
    /// one's own posts before the sheet covers the list is dropped; it used
    /// to reach the state machine's `fatalError` (DEBT, I1 review).
    @Test
    func aSecondTapBeforeTheSheetCoversTheListIsIgnored() async throws {
        let (flowCoordinator, latest) = try await startedFlow()

        latest.context.send(viewAction: .card(postID: post.id, .openAuthor))
        let author = try #require(splitCoordinator.sheetCoordinator as? NavigationStackCoordinator)
        #expect(author.rootCoordinator is FeedAuthorScreenCoordinator)
        latest.context.send(viewAction: .card(postID: post.id, .openAuthor))
        latest.context.send(viewAction: .openOwnPosts)
        #expect(splitCoordinator.sheetCoordinator === author)

        splitCoordinator.setSheetCoordinator(nil)
        latest.context.send(viewAction: .compose)
        let composer = try #require(splitCoordinator.sheetCoordinator as? NavigationStackCoordinator)
        #expect(composer.rootCoordinator is FeedComposerScreenCoordinator)
        latest.context.send(viewAction: .compose)
        latest.context.send(viewAction: .card(postID: post.id, .openAuthor))
        #expect(splitCoordinator.sheetCoordinator === composer)

        splitCoordinator.setSheetCoordinator(nil)
        latest.context.send(viewAction: .card(postID: post.id, .openPost))
        let stack = try #require(splitCoordinator.sidebarCoordinator as? NavigationStackCoordinator)
        let opened = try #require((stack.stackCoordinators.last as? FeedPostScreenCoordinator)?.viewModel as? FeedPostScreenViewModel)
        opened.context.send(viewAction: .card(.openAuthor))
        let postsAuthor = try #require(splitCoordinator.sheetCoordinator as? NavigationStackCoordinator)
        opened.context.send(viewAction: .card(.openAuthor))
        #expect(splitCoordinator.sheetCoordinator === postsAuthor)
        withExtendedLifetime(flowCoordinator) { }
    }

    /// The first picker's send ends after a link closed it and a second
    /// picker opened: the second stays up, and the toast names both counts.
    @Test
    func aLateAnswerOfAClosedPickerLeavesTheNewOneUp() async throws {
        let (flowCoordinator, latest) = try await startedFlow()

        latest.context.send(viewAction: .card(postID: post.id, .share))
        let first = try #require(splitCoordinator.sheetCoordinator as? NavigationStackCoordinator)
        flowCoordinator.handleAppRoute(.feedPost(postID: post.id), animated: false)
        #expect(splitCoordinator.sheetCoordinator == nil)
        latest.context.send(viewAction: .card(postID: post.id, .share))
        let second = try #require(splitCoordinator.sheetCoordinator as? NavigationStackCoordinator)

        flowCoordinator.handleShareAction(.sent(roomIDs: ["1", "2"]), from: first, failedRoomCount: 1)
        #expect(splitCoordinator.sheetCoordinator === second)
        #expect(indicators.submitIndicatorDelayReceivedArguments?.indicator.title == UntranslatedL10n.screenFeedSharedPartly(2, 1))

        flowCoordinator.handleShareAction(.sent(roomIDs: ["1"]), from: second, failedRoomCount: 0)
        #expect(splitCoordinator.sheetCoordinator == nil)
        #expect(indicators.submitIndicatorDelayReceivedArguments?.indicator.title == UntranslatedL10n.screenFeedShared(1))
    }

    // MARK: - Reports and notices (lane I3 on B4)

    /// A report from a card is a sheet; a second one while it is up is dropped,
    /// and its Done closes only the sheet it came from.
    @Test
    func aReportFromACardIsOneSheet() async throws {
        let (flowCoordinator, latest) = try await startedFlow()

        latest.context.send(viewAction: .card(postID: post.id, .report))
        let sheet = try #require(splitCoordinator.sheetCoordinator as? NavigationStackCoordinator)
        let report = try #require(sheet.rootCoordinator as? FeedReportScreenCoordinator)
        #expect(report.viewModel.context.viewState.target == .post(id: post.id))

        latest.context.send(viewAction: .card(postID: post.id, .report))
        latest.context.send(viewAction: .card(postID: post.id, .share))
        #expect(splitCoordinator.sheetCoordinator === sheet)

        report.viewModel.context.send(viewAction: .dismiss)
        #expect(splitCoordinator.sheetCoordinator == nil)
        withExtendedLifetime(flowCoordinator) { }
    }

    /// The author sheet's Report opens over it; closing the report leaves the author sheet up.
    @Test
    func aReportFromTheAuthorSheetOpensOverIt() async throws {
        let (flowCoordinator, latest) = try await startedFlow()
        latest.context.send(viewAction: .card(postID: post.id, .openAuthor))
        let authorStack = try #require(splitCoordinator.sheetCoordinator as? NavigationStackCoordinator)
        let author = try #require((authorStack.rootCoordinator as? FeedAuthorScreenCoordinator)?.viewModel as? FeedAuthorScreenViewModel)

        author.context.send(viewAction: .report)
        let reportStack = try #require(authorStack.sheetCoordinator as? NavigationStackCoordinator)
        let report = try #require(reportStack.rootCoordinator as? FeedReportScreenCoordinator)
        #expect(report.viewModel.context.viewState.target == .author(userID: post.author.userID))

        author.context.send(viewAction: .report)
        #expect(authorStack.sheetCoordinator === reportStack)

        report.viewModel.context.send(viewAction: .dismiss)
        #expect(authorStack.sheetCoordinator == nil)
        #expect(splitCoordinator.sheetCoordinator === authorStack)
        withExtendedLifetime(flowCoordinator) { }
    }

    /// A notice push lands on the notices over Latest, once however often it is tapped.
    @Test
    func theNoticesRouteOpensTheNoticesOnce() async throws {
        let (flowCoordinator, _) = try await startedFlow()
        let stack = try #require(splitCoordinator.sidebarCoordinator as? NavigationStackCoordinator)

        flowCoordinator.handleAppRoute(.feedNotices, animated: false)
        flowCoordinator.handleAppRoute(.feedNotices, animated: false)

        #expect(stack.stackCoordinators.count == 1)
        #expect(stack.stackCoordinators.first is FeedNoticesScreenCoordinator)
    }

    // MARK: - Activity and who liked (lane I5)

    /// The bell opens Activity (once); "From Spiral" opens the notices over it, and an entry its post at the comment.
    @Test
    func theBellOpensActivityAndItsWayToTheNoticesAndThePost() async throws {
        feed.activityCursorLimitReturnValue = .success(FeedActivityPage(items: FeedPreviewData.activity, nextCursor: nil, unread: 0))
        let (flowCoordinator, latest) = try await startedFlow()
        let stack = try #require(splitCoordinator.sidebarCoordinator as? NavigationStackCoordinator)

        latest.context.send(viewAction: .openActivity)
        latest.context.send(viewAction: .openActivity)
        #expect(stack.stackCoordinators.count == 1)
        let activity = try #require((stack.stackCoordinators.first as? FeedActivityScreenCoordinator)?.viewModel as? FeedActivityScreenViewModel)

        activity.context.send(viewAction: .openNotices)
        #expect(stack.stackCoordinators.last is FeedNoticesScreenCoordinator)

        let loaded = deferFulfillment(activity.context.observe(\.viewState.items.count)) { $0 > 0 }
        try await loaded.fulfill()
        let reply = try #require(FeedPreviewData.activity.first { $0.kind == .reply })
        activity.context.send(viewAction: .open(entryID: reply.id))
        let post = try #require((stack.stackCoordinators.last as? FeedPostScreenCoordinator)?.viewModel as? FeedPostScreenViewModel)
        #expect(post.context.viewState.postID == reply.postID)
        #expect(post.context.viewState.focusedCommentID == reply.commentID)
        withExtendedLifetime(flowCoordinator) { }
    }

    /// The count opens who liked as one sheet; a person opens in it.
    @Test
    func theLikesCountOpensWhoLikedAndAPersonOpensInIt() async throws {
        let liked = FeedPreviewData.engagedPost
        feed.latestCursorLimitReturnValue = .success(FeedPage(items: [liked], nextCursor: nil, pinned: nil))
        feed.likersPostIDCursorLimitReturnValue = .success(FeedLikersPage(items: FeedPreviewData.likers, nextCursor: nil))
        let (flowCoordinator, latest) = try await startedFlow()

        latest.context.send(viewAction: .card(postID: liked.id, .openLikers))
        let sheet = try #require(splitCoordinator.sheetCoordinator as? NavigationStackCoordinator)
        let likers = try #require((sheet.rootCoordinator as? FeedLikersScreenCoordinator)?.viewModel as? FeedLikersScreenViewModel)

        latest.context.send(viewAction: .card(postID: liked.id, .openLikers))
        #expect(splitCoordinator.sheetCoordinator === sheet)

        let loaded = deferFulfillment(likers.context.observe(\.viewState.likers.count)) { $0 > 0 }
        try await loaded.fulfill()
        #expect(feed.likersPostIDCursorLimitReceivedArguments?.postID == liked.id)
        likers.context.send(viewAction: .openAuthor(userID: FeedPreviewData.taras.userID))
        #expect(sheet.stackCoordinators.last is FeedAuthorScreenCoordinator)
        withExtendedLifetime(flowCoordinator) { }
    }

    /// The tab's badge: unread activity and unread notices together, as the server counts them.
    @Test
    func theTabsBadgeAddsActivityAndNotices() async throws {
        let activity = PassthroughSubject<Int, Never>()
        let notices = PassthroughSubject<Int, Never>()
        feed.activityUnreadPublisher = activity.eraseToAnyPublisher()
        feed.noticesUnreadPublisher = notices.eraseToAnyPublisher()
        let flowCoordinator = FeedTabFlowCoordinator(navigationSplitCoordinator: splitCoordinator, flowParameters: flowParameters())

        let five = deferFulfillment(flowCoordinator.badgeCountPublisher) { $0 == 5 }
        activity.send(2)
        notices.send(3)
        try await five.fulfill()

        let one = deferFulfillment(flowCoordinator.badgeCountPublisher) { $0 == 1 }
        activity.send(0)
        notices.send(1)
        try await one.fulfill()
    }

    private func flowParameters() -> CommonFlowParameters {
        let clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md"))
        clientProxy.ignoredUsersPublisher = CurrentValueSubject<[String]?, Never>([]).asCurrentValuePublisher()
        let platform = AgentPlatformServiceMock()
        platform.feed = feed
        platform.sync = sync
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        userSession.agentPlatformService = platform
        userSession.feedStore = FeedStore(feedService: feed, currentUserID: "@me:spiral.md")

        return CommonFlowParameters(userSession: userSession,
                                    availableSessionsPublisher: .init([.init(userSession: userSession)]),
                                    bugReportService: BugReportServiceMock(.init()),
                                    callKitService: CallKitServiceMock(.init()),
                                    timelineControllerFactory: TimelineControllerFactoryMock(.init()),
                                    emojiProvider: EmojiProvider(userSettings: userSession.userSettings),
                                    linkMetadataProvider: LinkMetadataProvider(),
                                    appMediator: AppMediatorMock(.init()),
                                    analytics: AnalyticsServiceMock(.init()),
                                    userIndicatorController: indicators,
                                    stateMachineFactory: StateMachineFactory())
    }
}
