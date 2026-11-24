//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The Feed tab, second after Chats (D-P9),
// in the split shell of the Spaces and Agents tabs. Latest is the root; a
// post, Activity and the notices push on the same stack (as the Agents tab's
// details do); an author, the composer (lane I2), the chat picker of a share,
// a report (lane I3) and who liked a post (lane I5) open as sheets; a report
// from the author sheet opens over it, and a person in who-liked opens in
// that sheet. Cross-tab moves (a chat with the author) bubble up. The tab's
// badge is the unread activity and notices. The tab renders the session's
// `FeedStore`, which the session's one sync stream (`PlatformSync`, decision
// 289) feeds.
//

import Combine
import SwiftState
import SwiftUI

enum FeedTabFlowCoordinatorAction {
    /// A chat opened from the author sheet, shown on the Chats tab.
    case openRoom(roomID: String)
}

class FeedTabFlowCoordinator: FlowCoordinatorProtocol {
    private let flowParameters: CommonFlowParameters
    private let navigationSplitCoordinator: NavigationSplitCoordinator
    private let sidebarNavigationStackCoordinator: NavigationStackCoordinator

    enum State: StateType {
        /// The state machine hasn't started.
        case initial
        /// Latest, with any posts pushed over it.
        case feed
        /// The author sheet is presented.
        case authorSheet
        /// The composer sheet is presented (lane I2).
        case composerSheet
        /// The chat picker of a share is presented (lane I3).
        case shareSheet
        /// The report screen is presented (lane I3 on B4).
        case reportSheet
        /// Who liked a post is presented (lane I5).
        case likersSheet
    }

    enum Event: EventType {
        case start
        /// A `FeedAuthor` must be provided in the `userInfo`.
        case presentAuthor
        case dismissedAuthor
        case presentComposer
        case dismissedComposer
        /// A `FeedPost` must be provided in the `userInfo`.
        case presentShare
        case dismissedShare
        /// A `FeedReportTarget` must be provided in the `userInfo`.
        case presentReport
        case dismissedReport
        /// A post id (`String`) must be provided in the `userInfo`.
        case presentLikers
        case dismissedLikers
    }

    private let stateMachine: StateMachine<State, Event>
    private var cancellables: Set<AnyCancellable> = []
    /// Over the session's store, shared by every feed screen: a like one at a time across them.
    private var engagement: FeedEngagementController?

    private let actionsSubject: PassthroughSubject<FeedTabFlowCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<FeedTabFlowCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    /// The Feed tab's badge (lane I5): unread activity and unread notices, as the server last counted them.
    var badgeCountPublisher: AnyPublisher<Int, Never> {
        guard let service = flowParameters.userSession.agentPlatformService?.feed else { return Just(0).eraseToAnyPublisher() }
        return service.activityUnreadPublisher.prepend(0)
            .combineLatest(service.noticesUnreadPublisher.prepend(0))
            .map { $0 + $1 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    init(navigationSplitCoordinator: NavigationSplitCoordinator, flowParameters: CommonFlowParameters) {
        self.navigationSplitCoordinator = navigationSplitCoordinator
        self.flowParameters = flowParameters

        sidebarNavigationStackCoordinator = NavigationStackCoordinator(navigationSplitCoordinator: navigationSplitCoordinator)
        navigationSplitCoordinator.setSidebarCoordinator(sidebarNavigationStackCoordinator)

        stateMachine = .init(state: .initial)
        configureStateMachine()
    }

    func start(animated: Bool) {
        stateMachine.tryEvent(.start)
    }

    func handleAppRoute(_ appRoute: AppRoute, animated: Bool) {
        switch appRoute {
        case .feedPost(let postID):
            // A link always lands on the post right above Latest, so back returns to the tab root.
            clearRoute(animated: false)
            pushPost(postID: postID, post: nil)
        case .feedNotices:
            clearRoute(animated: false)
            pushNotices()
        default:
            break
        }
    }

    func clearRoute(animated: Bool) {
        if [.authorSheet, .composerSheet, .shareSheet, .reportSheet, .likersSheet].contains(stateMachine.state) {
            navigationSplitCoordinator.setSheetCoordinator(nil, animated: animated)
        }
        sidebarNavigationStackCoordinator.popToRoot(animated: animated)
    }

    // MARK: - State machine

    /// The whole transition table, pure so a test can walk every state × event.
    static func nextState(from state: State, on event: Event) -> State? {
        switch (state, event) {
        case (.initial, .start): .feed
        case (.feed, .presentAuthor): .authorSheet
        case (.authorSheet, .dismissedAuthor): .feed
        case (.feed, .presentComposer): .composerSheet
        case (.composerSheet, .dismissedComposer): .feed
        case (.feed, .presentShare): .shareSheet
        case (.shareSheet, .dismissedShare): .feed
        case (.feed, .presentReport): .reportSheet
        case (.reportSheet, .dismissedReport): .feed
        case (.feed, .presentLikers): .likersSheet
        case (.likersSheet, .dismissedLikers): .feed
        default: nil
        }
    }

    private func configureStateMachine() {
        stateMachine.addRouteMapping { event, fromState, _ in
            event.flatMap { Self.nextState(from: fromState, on: $0) }
        } handler: { [weak self] context in
            guard let self else { return }
            switch context.event {
            case .start:
                presentFeedScreen()
            case .presentAuthor:
                guard let author = context.userInfo as? FeedAuthor else { fatalError("An author must be provided.") }
                presentAuthorSheet(author)
            case .presentComposer:
                presentComposerSheet()
            case .presentShare:
                guard let post = context.userInfo as? FeedPost else { fatalError("A post must be provided.") }
                presentShareSheet(post)
            case .presentReport:
                guard let target = context.userInfo as? FeedReportTarget else { fatalError("A report target must be provided.") }
                presentReportSheet(target)
            case .presentLikers:
                guard let postID = context.userInfo as? String else { fatalError("A post id must be provided.") }
                presentLikersSheet(postID: postID)
            case .dismissedAuthor, .dismissedComposer, .dismissedShare, .dismissedReport, .dismissedLikers, .none:
                break
            }
        }

        stateMachine.addErrorHandler { context in
            fatalError("Unexpected transition: \(context)")
        }
    }

    /// A sheet asked for while the state allows none (a double tap, a sheet
    /// already up or closing) is dropped here rather than reaching the error handler.
    func present(_ event: Event, userInfo: Any? = nil) {
        guard Self.nextState(from: stateMachine.state, on: event) != nil else {
            MXLog.info("Ignoring \(event) in \(stateMachine.state)")
            return
        }
        stateMachine.tryEvent(event, userInfo: userInfo)
    }

    // MARK: - Screens

    /// The session's feed and the engagement controller over its store; `nil` without the agent platform.
    private func feed() -> (service: FeedServiceProtocol, engagement: FeedEngagementController)? {
        guard let store = flowParameters.userSession.feedStore else { return nil }
        if let engagement {
            return (store.feedService, engagement)
        }
        let engagement = FeedEngagementController(store: store, userIndicatorController: flowParameters.userIndicatorController)
        self.engagement = engagement
        return (store.feedService, engagement)
    }

    // The stacks start the screen coordinators they show; a start here as
    // well subscribed twice, so every action ran twice.
    private func presentFeedScreen() {
        // The agent-platform service is optional on the session: degrade to the
        // placeholder like the Agents tab, so the split layout stays intact.
        guard case let (feedService, engagement)? = feed() else {
            sidebarNavigationStackCoordinator.setRootCoordinator(PlaceholderScreenCoordinator(hideBrandChrome: flowParameters.userSession.userSettings.app.hideBrandChrome))
            return
        }

        let coordinator = FeedScreenCoordinator(parameters: .init(feedService: feedService,
                                                                  engagement: engagement,
                                                                  clientProxy: flowParameters.userSession.clientProxy,
                                                                  mediaProvider: flowParameters.userSession.mediaProvider,
                                                                  userIndicatorController: flowParameters.userIndicatorController))
        coordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .openPost(let post):
                    pushPost(postID: post.id, post: post)
                case .openAuthor(let author):
                    present(.presentAuthor, userInfo: author)
                case .compose:
                    present(.presentComposer)
                case .openOwnPosts:
                    present(.presentAuthor, userInfo: ownAuthor)
                case .share(let post):
                    present(.presentShare, userInfo: post)
                case .report(let target):
                    present(.presentReport, userInfo: target)
                case .openActivity:
                    pushActivity()
                case .openLikers(let postID):
                    present(.presentLikers, userInfo: postID)
                case .published(let post):
                    showPublished(post)
                }
            }
            .store(in: &cancellables)

        // The badges are read when the sync stream is first ready, and on `feed.activity` / `feed.notice`.
        sidebarNavigationStackCoordinator.setRootCoordinator(coordinator)
    }

    /// A second ask for the post on top (a double tap, or the post opened again from its author's sheet) is dropped.
    private func pushPost(postID: String, post: FeedPost?, focusedCommentID: String? = nil) {
        guard case let (feedService, engagement)? = feed(),
              (sidebarNavigationStackCoordinator.stackCoordinators.last as? FeedPostScreenCoordinator)?.postID != postID else { return }

        let coordinator = FeedPostScreenCoordinator(parameters: .init(postID: postID,
                                                                      post: post,
                                                                      focusedCommentID: focusedCommentID,
                                                                      feedService: feedService,
                                                                      engagement: engagement,
                                                                      clientProxy: flowParameters.userSession.clientProxy,
                                                                      mediaProvider: flowParameters.userSession.mediaProvider,
                                                                      userIndicatorController: flowParameters.userIndicatorController))
        coordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .openAuthor(let author):
                    present(.presentAuthor, userInfo: author)
                case .deleted:
                    sidebarNavigationStackCoordinator.pop()
                case .share(let post):
                    present(.presentShare, userInfo: post)
                case .report(let target):
                    present(.presentReport, userInfo: target)
                case .openNotices:
                    pushNotices()
                case .openLikers(let postID):
                    present(.presentLikers, userInfo: postID)
                }
            }
            .store(in: &cancellables)

        sidebarNavigationStackCoordinator.push(coordinator)
    }

    private func presentAuthorSheet(_ author: FeedAuthor) {
        let stackCoordinator = NavigationStackCoordinator()
        guard let coordinator = makeAuthorScreen(author, in: stackCoordinator) else { return }
        stackCoordinator.setRootCoordinator(coordinator)
        navigationSplitCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissedAuthor)
        }
    }

    /// An author's screen in `stackCoordinator`, a sheet: their own, or who-liked's (lane I5).
    /// The caller shows it; the stack starts it.
    private func makeAuthorScreen(_ author: FeedAuthor, in stackCoordinator: NavigationStackCoordinator) -> FeedAuthorScreenCoordinator? {
        guard case let (feedService, engagement)? = feed() else { return nil }

        let coordinator = FeedAuthorScreenCoordinator(parameters: .init(author: author,
                                                                        feedService: feedService,
                                                                        engagement: engagement,
                                                                        clientProxy: flowParameters.userSession.clientProxy,
                                                                        mediaProvider: flowParameters.userSession.mediaProvider,
                                                                        userIndicatorController: flowParameters.userIndicatorController))
        coordinator.actionsPublisher
            .sink { [weak self, weak stackCoordinator] action in
                guard let self else { return }
                switch action {
                case .openRoom(let roomID):
                    navigationSplitCoordinator.setSheetCoordinator(nil)
                    actionsSubject.send(.openRoom(roomID: roomID))
                case .openPost(let post):
                    navigationSplitCoordinator.setSheetCoordinator(nil)
                    pushPost(postID: post.id, post: post)
                case .report(let target):
                    presentReport(target, over: stackCoordinator)
                case .dismiss:
                    navigationSplitCoordinator.setSheetCoordinator(nil)
                }
            }
            .store(in: &cancellables)
        return coordinator
    }

    // MARK: - Activity and who liked (lane I5)

    /// Activity pushes over Latest; a second ask while it is on top is dropped.
    private func pushActivity() {
        guard case let (feedService, engagement)? = feed(),
              !(sidebarNavigationStackCoordinator.stackCoordinators.last is FeedActivityScreenCoordinator) else { return }

        let coordinator = FeedActivityScreenCoordinator(parameters: .init(feedService: feedService,
                                                                          store: engagement.store,
                                                                          mediaProvider: flowParameters.userSession.mediaProvider,
                                                                          userIndicatorController: flowParameters.userIndicatorController))
        coordinator.actionsPublisher
            .sink { [weak self] action in
                switch action {
                case .openPost(let postID, let commentID):
                    self?.pushPost(postID: postID, post: nil, focusedCommentID: commentID)
                case .openNotices:
                    self?.pushNotices()
                }
            }
            .store(in: &cancellables)

        sidebarNavigationStackCoordinator.push(coordinator)
    }

    /// Who liked a post; a person opens in the same sheet, with their own actions.
    private func presentLikersSheet(postID: String) {
        guard case let (feedService, engagement)? = feed() else { return }

        let stackCoordinator = NavigationStackCoordinator()
        let coordinator = FeedLikersScreenCoordinator(parameters: .init(postID: postID,
                                                                        feedService: feedService,
                                                                        store: engagement.store,
                                                                        clientProxy: flowParameters.userSession.clientProxy,
                                                                        mediaProvider: flowParameters.userSession.mediaProvider,
                                                                        userIndicatorController: flowParameters.userIndicatorController))
        coordinator.actionsPublisher
            .sink { [weak self, weak stackCoordinator] action in
                guard let self, let stackCoordinator, isSheetUp(stackCoordinator) else { return }
                switch action {
                case .openAuthor(let author):
                    // A double tap pushes one person, not two.
                    guard !(stackCoordinator.stackCoordinators.last is FeedAuthorScreenCoordinator) else { return }
                    if let authorScreen = makeAuthorScreen(author, in: stackCoordinator) {
                        stackCoordinator.push(authorScreen)
                    }
                case .dismiss:
                    navigationSplitCoordinator.setSheetCoordinator(nil)
                }
            }
            .store(in: &cancellables)

        stackCoordinator.setRootCoordinator(coordinator)
        navigationSplitCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissedLikers)
        }
    }

    // MARK: - Notices and reports (lane I3 on B4)

    /// The notices push over Latest; a second ask while they are on top is dropped.
    private func pushNotices() {
        guard case let (feedService, engagement)? = feed(),
              !(sidebarNavigationStackCoordinator.stackCoordinators.last is FeedNoticesScreenCoordinator) else { return }

        let coordinator = FeedNoticesScreenCoordinator(parameters: .init(feedService: feedService,
                                                                         store: engagement.store,
                                                                         userIndicatorController: flowParameters.userIndicatorController))
        coordinator.actionsPublisher
            .sink { [weak self] action in
                switch action {
                case .openPost(let postID):
                    self?.pushPost(postID: postID, post: nil)
                }
            }
            .store(in: &cancellables)

        sidebarNavigationStackCoordinator.push(coordinator)
    }

    private func presentReportSheet(_ target: FeedReportTarget) {
        guard case let (stackCoordinator, coordinator)? = makeReportScreen(target) else { return }
        coordinator.actionsPublisher
            .sink { [weak self, weak stackCoordinator] action in
                guard let self else { return }
                switch action {
                case .dismiss:
                    // A late answer, after a link closed this sheet, closes nothing else.
                    if isSheetUp(stackCoordinator) {
                        navigationSplitCoordinator.setSheetCoordinator(nil)
                    }
                }
            }
            .store(in: &cancellables)

        navigationSplitCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissedReport)
        }
    }

    /// A report asked for on the author sheet opens over it, while that sheet is
    /// the one up and has nothing over it yet (a double tap opens one).
    private func presentReport(_ target: FeedReportTarget, over authorStack: NavigationStackCoordinator?) {
        guard let authorStack, isSheetUp(authorStack), authorStack.sheetCoordinator == nil,
              case let (reportStack, coordinator)? = makeReportScreen(target) else { return }
        coordinator.actionsPublisher
            .sink { [weak authorStack, weak reportStack] action in
                switch action {
                case .dismiss:
                    guard let authorStack, let reportStack, authorStack.sheetCoordinator === reportStack else { return }
                    authorStack.setSheetCoordinator(nil)
                }
            }
            .store(in: &cancellables)

        authorStack.setSheetCoordinator(reportStack)
    }

    /// The stack starts the screen it shows; the caller subscribes before presenting it.
    private func makeReportScreen(_ target: FeedReportTarget) -> (NavigationStackCoordinator, FeedReportScreenCoordinator)? {
        guard let feedService = flowParameters.userSession.agentPlatformService?.feed else { return nil }
        let stackCoordinator = NavigationStackCoordinator()
        let coordinator = FeedReportScreenCoordinator(parameters: .init(target: target, feedService: feedService))
        stackCoordinator.setRootCoordinator(coordinator)
        return (stackCoordinator, coordinator)
    }

    // MARK: - Composer (lane I2)

    /// The person as their own author sheet shows them: it reads their posts in every state.
    private var ownAuthor: FeedAuthor {
        let profile = flowParameters.userSession.clientProxy.userProfilePublisher.value
        return FeedAuthor(userID: flowParameters.userSession.clientProxy.userID,
                          name: profile.displayName,
                          avatarURL: profile.avatarURL,
                          bio: nil,
                          isOfficial: false,
                          isNameWithheld: false)
    }

    private func presentComposerSheet() {
        guard case let (feedService, engagement)? = feed() else { return }

        let stackCoordinator = NavigationStackCoordinator()
        // Started by the stack: starting it here too would double its actions.
        let coordinator = FeedComposerScreenCoordinator(parameters: .init(feedService: feedService,
                                                                          clientProxy: flowParameters.userSession.clientProxy,
                                                                          mediaProvider: flowParameters.userSession.mediaProvider))
        coordinator.actionsPublisher
            .sink { [weak self, weak stackCoordinator] action in
                guard let self else { return }
                // A late answer, after a link closed the composer, must not close the sheet up now.
                let isComposerUp = isSheetUp(stackCoordinator)
                switch action {
                case .send(let text, let idempotencyKey):
                    if isComposerUp {
                        navigationSplitCoordinator.setSheetCoordinator(nil)
                    }
                    // Shown at once on Latest as sending; a refusal stays there with Retry.
                    Task { [weak self] in
                        if case .success(let post) = await engagement.store.publishPost(text: text, idempotencyKey: idempotencyKey) {
                            self?.showPublished(post)
                        }
                    }
                case .dismiss:
                    if isComposerUp {
                        navigationSplitCoordinator.setSheetCoordinator(nil)
                    }
                }
            }
            .store(in: &cancellables)

        stackCoordinator.setRootCoordinator(coordinator)
        navigationSplitCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissedComposer)
        }
    }

    // MARK: - Share (lane I3)

    /// The forwarding screen with the post as its source: the server builds
    /// the message for each chat picked, and bridged chats are left out.
    private func presentShareSheet(_ post: FeedPost) {
        guard let feedService = flowParameters.userSession.agentPlatformService?.feed else { return }

        let stackCoordinator = NavigationStackCoordinator()
        let source = FeedShareForwardingSource(postID: post.id, feedService: feedService)
        let coordinator = MessageForwardingScreenCoordinator(parameters: .init(forwardingPayload: source,
                                                                               userSession: flowParameters.userSession,
                                                                               roomSummaryProvider: flowParameters.userSession.clientProxy.alternateRoomSummaryProvider,
                                                                               userIndicatorController: flowParameters.userIndicatorController))
        coordinator.actions
            .sink { [weak self, weak stackCoordinator] action in
                self?.handleShareAction(action, from: stackCoordinator, failedRoomCount: source.failedRoomCount)
            }
            .store(in: &cancellables)

        stackCoordinator.setRootCoordinator(coordinator)
        navigationSplitCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissedShare)
        }
    }

    /// The picker's end. A late answer, after a link closed this picker and
    /// perhaps another sheet opened, closes nothing: only the sheet it came from.
    func handleShareAction(_ action: MessageForwardingScreenCoordinatorAction, from stackCoordinator: NavigationStackCoordinator?, failedRoomCount: Int) {
        let isPresented = isSheetUp(stackCoordinator)
        switch action {
        case .dismiss:
            if isPresented {
                navigationSplitCoordinator.setSheetCoordinator(nil)
            }
        case .sent(let roomIDs):
            if isPresented {
                navigationSplitCoordinator.setSheetCoordinator(nil)
            }
            // Over the refusals' toasts: it names them too, so none is lost.
            let title = FeedShareForwardingSource.sharedMessage(sent: roomIDs.count, failed: failedRoomCount)
            flowParameters.userIndicatorController.submitIndicator(UserIndicator(type: .toast, title: title, icon: \.checkCircle))
        }
    }

    /// `stackCoordinator` is the sheet presented now, not one closed before it.
    private func isSheetUp(_ stackCoordinator: NavigationStackCoordinator?) -> Bool {
        guard let stackCoordinator else { return false }
        return navigationSplitCoordinator.sheetCoordinator === stackCoordinator
    }

    /// A visible post is in Latest, which reads it in; one held for review is
    /// not, so its author lands on it, with the notice and Delete. So does one
    /// the filter marked sensitive, to read why (decision 278).
    private func showPublished(_ post: FeedPost) {
        switch post.state {
        case .visible where post.content.isSensitive:
            pushPost(postID: post.id, post: post)
        case .visible:
            flowParameters.userIndicatorController.submitIndicator(UserIndicator(type: .toast,
                                                                                 title: UntranslatedL10n.screenFeedComposerPosted,
                                                                                 icon: \.checkCircle))
        case .held, .removed, .hiddenAuthor, .other:
            pushPost(postID: post.id, post: post)
        }
    }
}
