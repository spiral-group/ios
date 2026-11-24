//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). `spiral.md/feed/<id>` opens one post on
// the Feed tab; nothing else under `/feed` is a link.
//

import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct SpiralFeedLinkTests {
    private static let postID = "01933f2a-7c2e-7b44-9a51-3f1e2d4c5b01"
    private let parser = AppRouteURLParser(appSettings: AppSettings.volatile())

    @Test
    func aPostLinkRoutesToThePost() throws {
        for string in ["https://spiral.md/feed/\(Self.postID)",
                       "https://SPIRAL.md/feed/\(Self.postID)/",
                       "spiral:///feed/\(Self.postID)",
                       "https://spiral.md/feed/\(Self.postID.uppercased())?utm=x#top"] {
            let url = try #require(URL(string: string))
            #expect(parser.route(from: url) == .feedPost(postID: Self.postID), "\(string)")
        }
    }

    @Test
    func anythingElseUnderFeedIsNotALink() throws {
        for string in ["https://spiral.md/feed", "https://spiral.md/feed/", "https://spiral.md/feed/not-a-uuid",
                       "https://spiral.md/feed/\(Self.postID)/comments", "https://spiral.md/feed//\(Self.postID)",
                       "https://example.org/feed/\(Self.postID)", "spiral://feed/\(Self.postID)", "http://spiral.md/feed/\(Self.postID)"] {
            let url = try #require(URL(string: string))
            #expect(SpiralFeedLink.parse(url) == nil, "\(string)")
            #expect(parser.route(from: url) != .feedPost(postID: Self.postID), "\(string)")
        }
    }

    @Test
    func theLinkRoundTrips() throws {
        let link = try #require(SpiralFeedLink(postID: Self.postID))
        #expect(link.webURL.absoluteString == "https://spiral.md/feed/\(Self.postID)")
        #expect(SpiralFeedLink.parse(link.webURL) == link)
    }

    @Test
    func aPostLinkIsReplayedAfterSignIn() {
        #expect(!AppRoute.feedPost(postID: Self.postID).isAuthenticationRoute)
    }
}

struct FeedTabFlowCoordinatorTests {
    @Test
    func theTransitionTable() {
        typealias Flow = FeedTabFlowCoordinator
        let states: [Flow.State] = [.initial, .feed, .authorSheet]
        let events: [Flow.Event] = [.start, .presentAuthor, .dismissedAuthor]
        let expected: [Flow.State: [Flow.Event: Flow.State]] = [
            .initial: [.start: .feed],
            .feed: [.presentAuthor: .authorSheet],
            .authorSheet: [.dismissedAuthor: .feed]
        ]
        for state in states {
            for event in events {
                #expect(Flow.nextState(from: state, on: event) == expected[state]?[event], "\(state) on \(event)")
            }
        }
    }
}

/// The tab's screens, driven through their view models: each screen
/// coordinator is started once, by the stack that shows it, so one tap is
/// one move (a second start doubled every action, and a second author tap
/// with no route was a `fatalError`).
@MainActor
struct FeedTabFlowCoordinatorNavigationTests {
    @Test
    func oneTapIsOnePushAndOneAuthorSheet() async throws {
        let post = FeedPreviewData.textPost
        let feed = FeedServiceMock.empty()
        feed.latestCursorLimitReturnValue = .success(FeedPage(items: [post], nextCursor: nil, pinned: nil))
        feed.postIdReturnValue = .success(post)
        feed.authorPostsUserIDCursorLimitReturnValue = .success(FeedPage(items: [post], nextCursor: nil, pinned: nil))
        let splitCoordinator = NavigationSplitCoordinator(placeholderCoordinator: PlaceholderScreenCoordinator(hideBrandChrome: false))
        let flowCoordinator = FeedTabFlowCoordinator(navigationSplitCoordinator: splitCoordinator, flowParameters: Self.flowParameters(feed: feed))
        flowCoordinator.start(animated: false)

        let stack = try #require(splitCoordinator.sidebarCoordinator as? NavigationStackCoordinator)
        let latest = try #require((stack.rootCoordinator as? FeedScreenCoordinator)?.viewModel as? FeedScreenViewModel)
        let loaded = deferFulfillment(latest.context.observe(\.viewState.visibleItems.count)) { $0 == 1 }
        try await loaded.fulfill()

        latest.context.send(viewAction: .card(postID: post.id, .openPost))
        latest.context.send(viewAction: .card(postID: post.id, .openPost)) // A double tap.
        #expect(stack.stackCoordinators.count == 1)

        let postScreen = try #require((stack.stackCoordinators.last as? FeedPostScreenCoordinator)?.viewModel as? FeedPostScreenViewModel)
        postScreen.context.send(viewAction: .card(.openAuthor))
        let sheet = try #require(splitCoordinator.sheetCoordinator as? NavigationStackCoordinator)
        let author = try #require((sheet.rootCoordinator as? FeedAuthorScreenCoordinator)?.viewModel as? FeedAuthorScreenViewModel)
        #expect(sheet.stackCoordinators.isEmpty)

        let authorLoaded = deferFulfillment(author.context.observe(\.viewState.postsState)) { $0 != .loading }
        try await authorLoaded.fulfill()
        author.context.send(viewAction: .card(postID: post.id, .openPost))
        #expect(splitCoordinator.sheetCoordinator == nil)
        #expect(stack.stackCoordinators.count == 1, "the post was already on top: it isn't stacked twice")

        // Back on Latest, an author tap opens the sheet again: the dismissal was routed.
        latest.context.send(viewAction: .card(postID: post.id, .openAuthor))
        #expect(splitCoordinator.sheetCoordinator is NavigationStackCoordinator)
    }

    /// A double tap on a person in who-liked pushes their screen once.
    @Test
    func aDoubleTapInWhoLikedIsOnePush() async throws {
        let post = FeedPreviewData.engagedPost
        let feed = FeedServiceMock.empty()
        feed.latestCursorLimitReturnValue = .success(FeedPage(items: [post], nextCursor: nil, pinned: nil))
        feed.likersPostIDCursorLimitReturnValue = .success(FeedLikersPage(items: [FeedLiker(author: post.author, likedAt: .now)], nextCursor: nil))
        let splitCoordinator = NavigationSplitCoordinator(placeholderCoordinator: PlaceholderScreenCoordinator(hideBrandChrome: false))
        let flowCoordinator = FeedTabFlowCoordinator(navigationSplitCoordinator: splitCoordinator, flowParameters: Self.flowParameters(feed: feed))
        flowCoordinator.start(animated: false)
        let stack = try #require(splitCoordinator.sidebarCoordinator as? NavigationStackCoordinator)
        let latest = try #require((stack.rootCoordinator as? FeedScreenCoordinator)?.viewModel as? FeedScreenViewModel)
        try await deferFulfillment(latest.context.observe(\.viewState.visibleItems.count)) { $0 == 1 }.fulfill()

        latest.context.send(viewAction: .card(postID: post.id, .openLikers))
        let sheet = try #require(splitCoordinator.sheetCoordinator as? NavigationStackCoordinator)
        let likers = try #require((sheet.rootCoordinator as? FeedLikersScreenCoordinator)?.viewModel as? FeedLikersScreenViewModel)
        try await deferFulfillment(likers.context.observe(\.viewState.likers.count)) { $0 == 1 }.fulfill()

        likers.context.send(viewAction: .openAuthor(userID: post.author.userID))
        likers.context.send(viewAction: .openAuthor(userID: post.author.userID))
        #expect(sheet.stackCoordinators.count == 1)
    }

    /// A send that finishes after its composer closed, and after a link and
    /// another sheet, leaves the sheet that is up now alone.
    @Test
    func aSendFinishingAfterTheComposerClosedLeavesTheOtherSheet() async throws {
        let feed = FeedServiceMock.empty()
        let release = Flag()
        feed.createPostTextIdempotencyKeyClosure = { _, _ in
            while !release.isSet {
                try? await Task.sleep(for: .milliseconds(5))
            }
            return .success(FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000701", author: FeedPreviewData.ann, minutesAgo: 0,
                                                 text: "Hello feed", isAuthor: true))
        }
        let splitCoordinator = NavigationSplitCoordinator(placeholderCoordinator: PlaceholderScreenCoordinator(hideBrandChrome: false))
        let flowCoordinator = FeedTabFlowCoordinator(navigationSplitCoordinator: splitCoordinator, flowParameters: Self.flowParameters(feed: feed))
        flowCoordinator.start(animated: false)
        let stack = try #require(splitCoordinator.sidebarCoordinator as? NavigationStackCoordinator)
        let latest = try #require((stack.rootCoordinator as? FeedScreenCoordinator)?.viewModel)

        latest.context.send(viewAction: .compose)
        let composerSheet = try #require(splitCoordinator.sheetCoordinator as? NavigationStackCoordinator)
        // Kept alive, so the late answer reaches the flow.
        let composerCoordinator = try #require(composerSheet.rootCoordinator as? FeedComposerScreenCoordinator)
        let composer = composerCoordinator.viewModel
        composer.context.text = "Hello feed"
        // The store's observer moves the pending post into Latest's view state a beat after the send.
        let shownAsSending = deferFulfillment(latest.context.observe(\.viewState.pendingPosts.count)) { $0 == 1 }
        composer.context.send(viewAction: .post)
        try await shownAsSending.fulfill()
        while !feed.createPostTextIdempotencyKeyCalled {
            await Task.yield()
        }
        // Decision 289: the composer closes at once; the store sends the post, shown on Latest as sending.
        #expect(splitCoordinator.sheetCoordinator == nil)

        flowCoordinator.handleAppRoute(.feedPost(postID: "01933f2a-0000-7000-8000-000000000702"), animated: false)
        latest.context.send(viewAction: .openOwnPosts)
        let authorSheet = try #require(splitCoordinator.sheetCoordinator as? NavigationStackCoordinator)
        #expect(authorSheet.rootCoordinator is FeedAuthorScreenCoordinator)

        let sent = deferFulfillment(latest.context.observe(\.viewState.pendingPosts)) { $0.isEmpty }
        release.isSet = true
        try await sent.fulfill()

        #expect(splitCoordinator.sheetCoordinator === authorSheet)
        withExtendedLifetime(composerCoordinator) { }
    }

    private static func flowParameters(feed: FeedServiceMock) -> CommonFlowParameters {
        let clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md"))
        clientProxy.ignoredUsersPublisher = CurrentValueSubject<[String]?, Never>([]).asCurrentValuePublisher()
        let platform = AgentPlatformServiceMock()
        platform.feed = feed
        platform.sync = PlatformSyncServiceMock.unavailable()
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
                                    userIndicatorController: UserIndicatorControllerMock(),
                                    stateMachineFactory: StateMachineFactory())
    }
}

@MainActor
private final class Flag {
    var isSet = false
}
