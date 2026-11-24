//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import CallKit
import Combine
import Foundation
import MatrixRustSDKMocks
import PushKit
@testable import Spiral
import SwiftUI
import Synchronization
import Testing

@MainActor
struct UserSessionFlowCoordinatorTests {
    private var userSessionFlowCoordinator: UserSessionFlowCoordinator!
    private var rootCoordinator: NavigationRootCoordinator!
    private let userIndicatorController: UserIndicatorControllerMock
    private let clientProxy: ClientProxyMock
    private let userSession: UserSessionMock
    private let callKitService: CallKitServiceMock
    private let stateMachineFactory = PublishedStateMachineFactory()
    private let mainWindow = SizeClassWindow()
    
    private let networkReachabilitySubject: CurrentValueSubject<NetworkMonitorReachability, Never> = .init(.reachable)
    private let homeserverReachabilitySubject: CurrentValueSubject<HomeserverReachability, Never> = .init(.reachable)
    /// Settings is the last tab, and a tab's root.
    private var settingsStack: NavigationStackCoordinator? {
        tabCoordinator?.tabCoordinators.last as? NavigationStackCoordinator
    }
    
    private var tabCoordinator: NavigationTabCoordinator<UserSessionFlowCoordinator.HomeTab>? {
        rootCoordinator?.rootCoordinator as? NavigationTabCoordinator
    }
    
    private var chatsSplitCoordinator: NavigationSplitCoordinator? {
        tabCoordinator?.tabCoordinators.first as? NavigationSplitCoordinator
    }
    
    private var detailCoordinator: CoordinatorProtocol? {
        chatsSplitCoordinator?.detailCoordinator
    }
    
    private var detailNavigationStack: NavigationStackCoordinator? {
        detailCoordinator as? NavigationStackCoordinator
    }
    
    init() async throws {
        let clientProxy = ClientProxyMock(.init(userID: "hi@bob", roomSummaryProvider: RoomSummaryProviderMock(.init(state: .loaded(.mockRooms)))))
        clientProxy.homeserverReachabilityPublisher = homeserverReachabilitySubject.asCurrentValuePublisher()
        self.clientProxy = clientProxy
        let callKitService = CallKitServiceMock(.init())
        self.callKitService = callKitService
        
        userIndicatorController = UserIndicatorControllerMock()
        
        userSession = UserSessionMock(.init(clientProxy: clientProxy))
        
        startCoordinator(callKitService: callKitService)
    }
    
    /// A fresh coordinator over `callKitService`: the mock, or a real service
    /// for the call paths whose state lives in it.
    private mutating func startCoordinator(callKitService: CallKitServiceProtocol, signInCover: CoordinatorProtocol? = nil,
                                           signInCoverTimeout: TimeInterval = 3,
                                           configureSettings: (AppSettings) -> Void = { _ in }) {
        rootCoordinator = NavigationRootCoordinator()
        rootCoordinator.setCoverCoordinator(signInCover) // AGENT-PLATFORM (1.0.3): the logo the OAuth sign-in leaves.
        
        let networkMonitor = NetworkMonitorMock(.init())
        networkMonitor.reachabilityPublisher = networkReachabilitySubject.asCurrentValuePublisher()
        let appMediator = AppMediatorMock(.init())
        appMediator.networkMonitor = networkMonitor
        (appMediator.windowManager as? WindowManagerMock)?.mainWindow = mainWindow
        
        configureSettings(userSession.userSettings.app)
        
        let flowParameters = CommonFlowParameters(userSession: userSession,
                                                  availableSessionsPublisher: .init([.init(userSession: userSession)]),
                                                  bugReportService: BugReportServiceMock(.init()),
                                                  callKitService: callKitService,
                                                  timelineControllerFactory: TimelineControllerFactoryMock(.init()),
                                                  emojiProvider: EmojiProvider(userSettings: userSession.userSettings),
                                                  linkMetadataProvider: LinkMetadataProvider(),
                                                  appMediator: appMediator,
                                                  analytics: AnalyticsServiceMock(.init()),
                                                  userIndicatorController: userIndicatorController,
                                                  stateMachineFactory: stateMachineFactory)
        
        userSessionFlowCoordinator = UserSessionFlowCoordinator(isNewLogin: false,
                                                                navigationRootCoordinator: rootCoordinator,
                                                                appLockService: AppLockServiceMock(),
                                                                flowParameters: flowParameters)
        userSessionFlowCoordinator.signInCoverTimeout = signInCoverTimeout // AGENT-PLATFORM (1.0.3)
        
        userSessionFlowCoordinator.start()
    }
    
    // MARK: Navigation
    
    @Test
    func initialState() {
        #expect(chatsSplitCoordinator != nil)
        #expect(detailCoordinator == nil)
    }
    
    @Test
    mutating func settingsPresentation() async throws {
        try await process(route: .settings)
        #expect(tabCoordinator?.selectedTab == .settings)
        #expect(settingsStack?.rootCoordinator is SettingsScreenCoordinator)
    }
    
    /// AGENT-PLATFORM (DEBT B10): a notification tap under the Link new device sheet opened the room behind it.
    @Test
    mutating func aRouteToAnotherTabClosesTheSheetOverSettings() async throws {
        try await process(route: .settings)
        let linkNewDevice = NavigationStackCoordinator()
        linkNewDevice.setRootCoordinator(BlankFormCoordinator())
        try #require(settingsStack).setSheetCoordinator(linkNewDevice)
        
        try await process(route: .room(roomID: "1", via: []), expectedChatsState: .roomList(detailState: .room(roomID: "1")))
        
        #expect(tabCoordinator?.selectedTab == .chats)
        #expect(settingsStack?.sheetCoordinator == nil)
        
        try #require(settingsStack).setSheetCoordinator(linkNewDevice)
        try await process(route: .feedPost(postID: "1"))
        #expect(tabCoordinator?.selectedTab == .feed)
        #expect(settingsStack?.sheetCoordinator == nil)
    }
    
    /// AGENT-PLATFORM (DEBT B10): a route keeps what a call keeps, a recovery key being noted down, say.
    @Test
    mutating func aRouteToAnotherTabKeepsTheSheetsTheirPersonCantSwipeAway() async throws {
        try await process(route: .settings)
        let keyStack = NavigationStackCoordinator()
        keyStack.setRootCoordinator(SwipeRefusingScreen())
        try #require(settingsStack).setSheetCoordinator(keyStack)
        
        try await process(route: .room(roomID: "1", via: []), expectedChatsState: .roomList(detailState: .room(roomID: "1")))
        
        #expect(settingsStack?.sheetCoordinator === keyStack)
    }
    
    // AGENT-PLATFORM (decisions 150, 187): «Open Settings» lands on Privacy,
    // whose first row is the AI consent toggle.
    @Test
    mutating func aiConsentRouteOpensPrivacy() async throws {
        try await process(route: .aiConsentSettings)
        #expect(tabCoordinator?.selectedTab == .settings)
        let stack = try #require(settingsStack)
        #expect(stack.rootCoordinator is SettingsScreenCoordinator)
        #expect(stack.stackCoordinators.last is ModerationAndSafetySettingsScreenCoordinator)
    }
    
    // AGENT-PLATFORM (decision 187): «Sign out», not upstream's «Remove this device».
    @Test
    func signOutConfirmationSaysSignOut() async throws {
        clientProxy.isOnlyDeviceLeftReturnValue = .success(false)
        await userSessionFlowCoordinator.runLogoutFlow()
        
        let alert = try #require(rootCoordinator.alertInfo)
        #expect(alert.title == UntranslatedL10n.screenSignoutConfirmationDialogTitleSpiral)
        #expect(alert.message == UntranslatedL10n.screenSignoutConfirmationDialogContentSpiral)
        #expect(alert.primaryButton.title == UntranslatedL10n.screenSignoutConfirmationDialogSubmitSpiral)
        #expect(alert.primaryButton.role == .destructive)
    }
    
    // AGENT-PLATFORM (decision 187): upstream's recovery warning, with the «Sign out» button.
    @Test
    func signingOutTheLastDeviceWithoutRecoveryWarnsAndSaysSignOut() async throws {
        clientProxy.isOnlyDeviceLeftReturnValue = .success(true)
        clientProxy.secureBackupController = SecureBackupControllerMock(.init(recoveryState: .disabled))
        await userSessionFlowCoordinator.runLogoutFlow()
        
        let alert = try #require(rootCoordinator.alertInfo)
        #expect(alert.title == L10n.screenSignoutRecoveryDisabledTitle)
        #expect(alert.primaryButton.title == UntranslatedL10n.screenSignoutConfirmationDialogSubmitSpiral)
    }
    
    @Test
    mutating func roomPresentation() async throws {
        try await process(route: .room(roomID: "1", via: []), expectedChatsState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailCoordinator != nil)
    }
    
    @Test
    mutating func roomPresentationLeavesTheSettingsTab() async throws {
        try await process(route: .settings)
        #expect(tabCoordinator?.selectedTab == .settings)
        #expect(settingsStack?.rootCoordinator is SettingsScreenCoordinator)
        #expect(detailCoordinator == nil)
        
        try await process(route: .room(roomID: "1", via: []),
                          expectedChatsState: .roomList(detailState: .room(roomID: "1")))
        #expect(tabCoordinator?.selectedTab == .chats)
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailCoordinator != nil)
    }
    
    @Test
    mutating func childRoomPresentation() async throws {
        try await process(route: .room(roomID: "1", via: []), expectedChatsState: .roomList(detailState: .room(roomID: "1")))
        let detailNavigationStack = try #require(detailNavigationStack, "There must be a navigation stack.")
        #expect(detailNavigationStack.rootCoordinator is RoomScreenCoordinator)
        #expect(detailCoordinator != nil)
        
        let deferred = deferFulfillment(detailNavigationStack.observe(\.stackCoordinators.count)) { $0 == 1 }
        try await process(route: .childRoom(roomID: "2", via: []))
        try await deferred.fulfill()
        #expect(detailNavigationStack.rootCoordinator is RoomScreenCoordinator)
        #expect(detailCoordinator != nil)
        #expect(detailNavigationStack.stackCoordinators.count == 1)
        #expect(detailNavigationStack.stackCoordinators.first is RoomScreenCoordinator)
    }
    
    @Test
    mutating func shareMediaRouteWithoutRoom() async throws {
        try await process(route: .settings)
        #expect(tabCoordinator?.selectedTab == .settings)
        #expect(settingsStack?.rootCoordinator is SettingsScreenCoordinator)
        #expect(chatsSplitCoordinator?.sheetCoordinator == nil)
        
        let sharePayload: ShareExtensionPayload = .mediaFiles(roomID: nil, mediaFiles: [.init(url: .picturesDirectory, suggestedName: nil)])
        try await process(route: .share(sharePayload),
                          expectedChatsState: .shareExtensionRoomList(sharePayload: sharePayload))
        #expect(tabCoordinator?.sheetCoordinator == nil)
        #expect((chatsSplitCoordinator?.sheetCoordinator as? NavigationStackCoordinator)?.rootCoordinator is RoomSelectionScreenCoordinator)
    }
    
    @Test
    mutating func shareMediaRouteWithRoom() async throws {
        try await process(route: .event(eventID: "1", roomID: "1", via: []), expectedChatsState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(tabCoordinator?.sheetCoordinator == nil)
        #expect(chatsSplitCoordinator?.sheetCoordinator == nil)
        
        let sharePayload: ShareExtensionPayload = .mediaFiles(roomID: "2", mediaFiles: [.init(url: .picturesDirectory, suggestedName: nil)])
        try await process(route: .share(sharePayload),
                          expectedChatsState: .roomList(detailState: .room(roomID: "2")))
        
        let splitCoordinator = try #require(chatsSplitCoordinator)
        let deferredSheet = deferFulfillment(splitCoordinator.observe(\.sheetCoordinatorID)) { $0 != nil }
        try await deferredSheet.fulfill()
        
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(tabCoordinator?.sheetCoordinator == nil)
        #expect((splitCoordinator.sheetCoordinator as? NavigationStackCoordinator)?.rootCoordinator is MediaUploadPreviewScreenCoordinator)
    }
    
    @Test
    mutating func shareTextRouteWithoutRoom() async throws {
        try await process(route: .settings)
        #expect(tabCoordinator?.selectedTab == .settings)
        #expect(settingsStack?.rootCoordinator is SettingsScreenCoordinator)
        #expect(chatsSplitCoordinator?.sheetCoordinator == nil)
        
        let sharePayload: ShareExtensionPayload = .text(roomID: nil, text: "Important Text")
        try await process(route: .share(sharePayload),
                          expectedChatsState: .shareExtensionRoomList(sharePayload: sharePayload))
        #expect(tabCoordinator?.sheetCoordinator == nil)
        #expect((chatsSplitCoordinator?.sheetCoordinator as? NavigationStackCoordinator)?.rootCoordinator is RoomSelectionScreenCoordinator)
    }
    
    @Test
    mutating func shareTextRouteWithRoom() async throws {
        try await process(route: .event(eventID: "1", roomID: "1", via: []), expectedChatsState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(tabCoordinator?.sheetCoordinator == nil)
        #expect(chatsSplitCoordinator?.sheetCoordinator == nil)
        
        let sharePayload: ShareExtensionPayload = .text(roomID: "2", text: "Important text")
        try await process(route: .share(sharePayload),
                          expectedChatsState: .roomList(detailState: .room(roomID: "2")))
        
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(tabCoordinator?.sheetCoordinator == nil)
        #expect(chatsSplitCoordinator?.sheetCoordinator == nil, "The media upload sheet shouldn't be shown when sharing text.")
    }
    
    // MARK: Search (AGENT-PLATFORM, Brief 0083)
    
    @Test
    func openingASearchResultClosesSearch() async throws {
        let search = try #require(userSessionFlowCoordinator.searchScreenCoordinator)
        search.presentSearch()
        search.context.searchQuery = "Room"
        
        let deferred = deferFulfillment(stateMachineFactory.chatsTabFlowStatePublisher) { $0 == .roomList(detailState: .room(roomID: "1")) }
        search.context.send(viewAction: .selectRoom(roomID: "1"))
        try await deferred.fulfill()
        
        #expect(!search.context.isSearchPresented)
        #expect(search.context.searchQuery.isEmpty)
    }
    
    @Test
    func openingAMessageResultClosesSearch() async throws {
        let search = try #require(userSessionFlowCoordinator.searchScreenCoordinator)
        search.presentSearch()
        
        let deferred = deferFulfillment(stateMachineFactory.chatsTabFlowStatePublisher) { $0 == .roomList(detailState: .room(roomID: "1")) }
        search.context.send(viewAction: .selectMessage(roomID: "1", eventID: "$event"))
        try await deferred.fulfill()
        
        #expect(!search.context.isSearchPresented)
    }
    
    @Test
    func askingForAHiddenSearchKeepsTheFieldsFocus() throws {
        let search = try #require(userSessionFlowCoordinator.searchScreenCoordinator)
        search.presentSearch()
        search.context.isFieldReturning = true
        
        search.presentSearch()
        
        #expect(!search.context.isFieldReturning)
    }
    
    @Test
    mutating func searchInCompactWidthClearsTheRoomCoveringChats() async throws {
        mainWindow.horizontalSizeClass = .compact
        let search = try #require(userSessionFlowCoordinator.searchScreenCoordinator)
        try await process(route: .room(roomID: "1", via: []), expectedChatsState: .roomList(detailState: .room(roomID: "1")))
        
        try await process(route: .search, expectedChatsState: .roomList(detailState: nil))
        
        try await waitFor { detailCoordinator == nil }
        #expect(tabCoordinator?.selectedTab == .chats)
        #expect(search.context.isSearchPresented)
    }
    
    @Test
    mutating func searchInRegularWidthKeepsTheRoomBesideChats() async throws {
        mainWindow.horizontalSizeClass = .regular
        let search = try #require(userSessionFlowCoordinator.searchScreenCoordinator)
        try await process(route: .room(roomID: "1", via: []), expectedChatsState: .roomList(detailState: .room(roomID: "1")))
        
        try await process(route: .search)
        
        #expect(detailCoordinator != nil)
        #expect(search.context.isSearchPresented)
    }
    
    // MARK: Indicators
    
    /// AGENT-PLATFORM (ADR-0087): the route an approval push resolves to —
    /// a first contact's included — opens the approval card on the Agents tab,
    /// above the notifications hub.
    @Test
    func approvalRouteOpensTheApprovalCardOnTheAgentsTab() throws {
        let platform = AgentPlatformServiceMock()
        platform.feed = FeedServiceMock.empty() // AGENT-PLATFORM: feed (Brief 0082)
        platform.sync = PlatformSyncServiceMock.unavailable() // AGENT-PLATFORM: platform sync (decision 289)
        platform.fetchNotificationsActivityCursorLimitReturnValue = .success(.init(needsAction: [], activity: [], nextActivityCursor: nil,
                                                                                   lastSeenAt: nil, unseenCount: 0))
        platform.listMyAgentSpacesReturnValue = .success(.init(spaces: [], provisioningStatus: .ready))
        userSession.agentPlatformService = platform
        userSession.agentsStore = AgentsStore(service: platform)
        
        userSessionFlowCoordinator.handleAppRoute(.approvalDetail(approvalID: "approval-1"), animated: false)
        
        let tabCoordinator = try #require(tabCoordinator)
        #expect(tabCoordinator.selectedTab == .agents)
        let agentsIndex = try #require(tabCoordinator.tabTags.firstIndex(of: .agents)) // AGENT-PLATFORM: the Spaces tab is optional (decision 301)
        let agentsSplitCoordinator = try #require(tabCoordinator.tabCoordinators[agentsIndex] as? NavigationSplitCoordinator)
        let agentsStack = try #require(agentsSplitCoordinator.sidebarCoordinator as? NavigationStackCoordinator)
        #expect(agentsStack.stackCoordinators.last is ApprovalDetailScreenCoordinator)
        #expect(agentsStack.stackCoordinators.dropLast().last is NotificationsHubScreenCoordinator)
    }
    
    // MARK: Spaces (AGENT-PLATFORM, decision 301)
    
    @Test
    func theTabsLeaveOutSpacesWhenSpacesAreHidden() throws {
        let tabCoordinator = try #require(tabCoordinator)
        #expect(tabCoordinator.tabTags == [.chats, .feed, .agents, .settings])
    }
    
    @Test
    mutating func theTabsIncludeSpacesWhenSpacesAreEnabled() throws {
        startCoordinator(callKitService: callKitService) { $0.spacesEnabled = true }
        
        let tabCoordinator = try #require(tabCoordinator)
        #expect(tabCoordinator.tabTags == [.chats, .feed, .spaces, .agents, .settings])
    }
    
    /// A space link, a notification or an accepted space invite: the space opens in Chats.
    @Test
    mutating func aSpaceRouteOpensTheSpaceInChatsWhenSpacesAreHidden() async throws {
        let space = try #require([SpaceServiceRoom].mockJoinedSpaces.first)
        clientProxy.spaceService = SpaceServiceProxyMock(.populated)
        clientProxy.roomForIdentifierClosure = { roomID in
            .joined(JoinedRoomProxyMock(.init(id: roomID, name: space.name, isSpace: true)))
        }
        let tabCoordinator = try #require(tabCoordinator)
        tabCoordinator.selectedTab = .agents
        
        try await process(route: .room(roomID: space.id, via: []), expectedChatsState: .roomList(detailState: .space))
        
        #expect(tabCoordinator.selectedTab == .chats)
        #expect(!tabCoordinator.tabTags.contains(.spaces))
        try await waitFor { detailNavigationStack?.rootCoordinator is SpaceScreenCoordinator }
    }
    
    // MARK: Invite welcome (AGENT-PLATFORM, Brief 0073)
    
    /// A session whose only onboarding step is the AI consent prompt, whose
    /// consent read waits on `gate`.
    private mutating func startWithAIConsentRead(needsDecision: Bool, gate: LookupGate, signInCover: CoordinatorProtocol? = nil) {
        let platform = AgentPlatformServiceMock()
        platform.fetchAIConsentClosure = {
            await gate.wait()
            return .success(AIConsent(isGranted: !needsDecision, currentVersion: "1", decidedVersion: nil))
        }
        platform.feed = FeedServiceMock.empty() // AGENT-PLATFORM: feed (Brief 0082)
        platform.sync = PlatformSyncServiceMock.unavailable() // AGENT-PLATFORM: platform sync (decision 289)
        platform.fetchNotificationsActivityCursorLimitReturnValue = .success(.init(needsAction: [], activity: [], nextActivityCursor: nil,
                                                                                   lastSeenAt: nil, unseenCount: 0))
        platform.listMyAgentSpacesReturnValue = .success(.init(spaces: [], provisioningStatus: .ready))
        userSession.agentPlatformService = platform
        userSession.agentsStore = AgentsStore(service: platform) // AGENT-PLATFORM (Brief 0083, question 359): the consent's read goes through it.
        userSession.userSettings.account.hasRunIdentityConfirmationOnboarding = true
        startCoordinator(callKitService: callKitService, signInCover: signInCover) { settings in
            settings.hasRunNotificationPermissionsOnboarding = true
        }
    }
    
    /// G05 (1 run in 5): the welcome, offered before the consent read came
    /// back, showed at once and the consent prompt then replaced it for good.
    /// It now waits for onboarding to settle.
    @Test
    mutating func theInviteWelcomeWaitsForTheAIConsentPrompt() async throws {
        let gate = LookupGate()
        startWithAIConsentRead(needsDecision: true, gate: gate)
        
        userSessionFlowCoordinator.presentInviteWelcome(inviterUserID: "@inviter:spiral.md")
        #expect(!(tabCoordinator?.fullScreenCoverCoordinator is InviteWelcomeScreenCoordinator),
                "the welcome must not show before onboarding knows whether to ask about AI")
        
        gate.open()
        try await waitForCover { $0 is NavigationStackCoordinator }
        #expect(tabCoordinator?.fullScreenCoverCoordinator is NavigationStackCoordinator, "the consent prompt is up")
    }
    
    @Test
    mutating func theInviteWelcomeShowsOnceOnboardingHasNothingToAsk() async throws {
        let gate = LookupGate()
        startWithAIConsentRead(needsDecision: false, gate: gate)
        
        var shownCount = 0
        userSessionFlowCoordinator.presentInviteWelcome(inviterUserID: "@inviter:spiral.md") { shownCount += 1 }
        #expect(tabCoordinator?.fullScreenCoverCoordinator == nil)
        #expect(shownCount == 0, "queued, not shown: nothing to record yet")
        
        gate.open()
        try await waitForCover { $0 is InviteWelcomeScreenCoordinator }
        #expect(tabCoordinator?.fullScreenCoverCoordinator is InviteWelcomeScreenCoordinator)
        #expect(shownCount == 1, "recorded once it is on screen")
    }
    
    /// A session that starts unverified, so onboarding opens on identity
    /// confirmation; the consent read (nothing to ask) waits on `gate`.
    @discardableResult
    private mutating func startUnverified(gate: LookupGate, signInCover: CoordinatorProtocol? = nil,
                                          signInCoverTimeout: TimeInterval = 3) -> CurrentValueSubject<SessionSecurityState, Never> {
        let securityState = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .unverified, recoveryState: .enabled))
        userSession.sessionSecurityStatePublisher = securityState.asCurrentValuePublisher()
        let platform = AgentPlatformServiceMock()
        platform.fetchAIConsentClosure = {
            await gate.wait()
            return .success(AIConsent(isGranted: true, currentVersion: "1", decidedVersion: "1"))
        }
        platform.feed = FeedServiceMock.empty() // AGENT-PLATFORM: feed (Brief 0082)
        platform.sync = PlatformSyncServiceMock.unavailable() // AGENT-PLATFORM: platform sync (decision 289)
        platform.fetchNotificationsActivityCursorLimitReturnValue = .success(.init(needsAction: [], activity: [], nextActivityCursor: nil,
                                                                                   lastSeenAt: nil, unseenCount: 0))
        platform.listMyAgentSpacesReturnValue = .success(.init(spaces: [], provisioningStatus: .ready))
        userSession.agentPlatformService = platform
        userSession.agentsStore = AgentsStore(service: platform) // AGENT-PLATFORM (Brief 0083, question 359): the consent's read goes through it.
        startCoordinator(callKitService: callKitService, signInCover: signInCover, signInCoverTimeout: signInCoverTimeout) { settings in
            settings.hasRunNotificationPermissionsOnboarding = true
        }
        return securityState
    }
    
    /// Taps Skip on the identity confirmation screen onboarding is showing.
    private func skipIdentityConfirmation() async throws {
        let onboarding = try #require(onboardingStack)
        // AGENT-PLATFORM (1.0.3): the screen opens once the account's identity is found, after a wait on the logo.
        try await waitFor { onboarding.rootCoordinator is IdentityConfirmationScreenCoordinator }
        let screen = try #require(onboarding.rootCoordinator as? IdentityConfirmationScreenCoordinator)
        let viewModel = try #require(Mirror(reflecting: screen).descendant("viewModel") as? IdentityConfirmationScreenViewModelProtocol)
        viewModel.context.send(viewAction: .skip)
    }
    
    private var onboardingStack: NavigationStackCoordinator? {
        Mirror(reflecting: userSessionFlowCoordinator!).descendant("onboardingStackCoordinator") as? NavigationStackCoordinator
    }
    
    /// Fable review of 298fcce87: skipping identity confirmation leaves the
    /// session unverified, which counted as an onboarding step still due, so
    /// the welcome stayed pending at the end of onboarding and was lost.
    @Test
    mutating func theInviteWelcomeShowsWhenOnboardingEndsUnverified() async throws {
        let gate = LookupGate()
        startUnverified(gate: gate)
        #expect(tabCoordinator?.fullScreenCoverCoordinator is NavigationStackCoordinator, "onboarding opens on identity confirmation")
        
        userSessionFlowCoordinator.presentInviteWelcome(inviterUserID: "@inviter:spiral.md")
        #expect(!(tabCoordinator?.fullScreenCoverCoordinator is InviteWelcomeScreenCoordinator))
        
        gate.open()
        try await Task.sleep(for: .milliseconds(50)) // the consent read's task
        try await skipIdentityConfirmation()
        try await waitForCover { $0 is InviteWelcomeScreenCoordinator }
        #expect(tabCoordinator?.fullScreenCoverCoordinator is InviteWelcomeScreenCoordinator)
    }
    
    /// Onboarding finishing under another cover (the in-app incoming call
    /// screen took its place) neither removes that cover nor puts the welcome
    /// over it; the welcome waits.
    @Test
    mutating func onboardingEndingUnderAnotherCoverLeavesItAndTheWelcomeWaits() async throws {
        let gate = LookupGate()
        let securityState = startUnverified(gate: gate)
        userSessionFlowCoordinator.presentInviteWelcome(inviterUserID: "@inviter:spiral.md")
        // Past identity confirmation, onboarding waits for the consent answer. Verified
        // meanwhile, so an unverified session doesn't start onboarding over again.
        try await skipIdentityConfirmation()
        securityState.send(.init(verificationState: .verified, recoveryState: .enabled))
        
        let call = BlankFormCoordinator()
        tabCoordinator?.setFullScreenCoverCoordinator(call)
        gate.open()
        try await Task.sleep(for: .milliseconds(100))
        
        #expect(tabCoordinator?.fullScreenCoverCoordinator === call, "the other cover stays")
    }
    
    /// A settled session (nothing to onboard, nothing to ask) whose in-app
    /// ring is driven through the returned subject; the welcome is offered
    /// while the ring is up, so it waits.
    private mutating func startRingingWithAWaitingWelcome() async throws -> PassthroughSubject<CallKitServiceAction, Never> {
        let ringActions = PassthroughSubject<CallKitServiceAction, Never>()
        callKitService.actions = ringActions.eraseToAnyPublisher()
        callKitService.isAcceptedRingLiveForRoomIDReturnValue = true
        let gate = LookupGate()
        gate.open()
        startWithAIConsentRead(needsDecision: false, gate: gate)
        try await Task.sleep(for: .milliseconds(50)) // the consent read's task
        // The consent is read; the call screens run without the platform, as the other call tests do.
        userSession.agentPlatformService = nil
        clientProxy.roomForIdentifierClosure = { roomID in .joined(Self.callableRoom(id: roomID)) }
        
        ringActions.send(.startInAppRinging(roomID: "1", callerDisplayName: "Bob", callerAvatarData: nil, isVoiceCall: true, rtcNotificationID: nil))
        try await waitFor { tabCoordinator?.fullScreenCoverCoordinator is NativeCallIncomingScreenCoordinator }
        userSessionFlowCoordinator.presentInviteWelcome(inviterUserID: "@inviter:spiral.md")
        #expect(tabCoordinator?.fullScreenCoverCoordinator is NativeCallIncomingScreenCoordinator, "the ring stays up")
        return ringActions
    }
    
    /// Fable review of 3301d3ed2: accepting the in-app ring put the welcome up
    /// as a cover over the call screen. It waits for the call to end.
    @Test
    mutating func acceptingTheInAppRingLeavesTheWelcomeForAfterTheCall() async throws {
        _ = try await startRingingWithAWaitingWelcome()
        let incoming = try #require(tabCoordinator?.fullScreenCoverCoordinator as? NativeCallIncomingScreenCoordinator)
        
        incoming.send(.accept)
        try await waitFor { tabCoordinator?.overlayCoordinator is NativeCallScreenCoordinator }
        #expect(!(tabCoordinator?.fullScreenCoverCoordinator is InviteWelcomeScreenCoordinator), "no welcome over the call")
        
        // The mocked call fails and its screen goes after showing the end.
        try await waitFor(attempts: 600) { tabCoordinator?.overlayCoordinator == nil }
        try await waitFor { tabCoordinator?.fullScreenCoverCoordinator is InviteWelcomeScreenCoordinator }
        #expect(tabCoordinator?.fullScreenCoverCoordinator is InviteWelcomeScreenCoordinator, "the welcome after the call")
    }
    
    @Test
    mutating func aRingThatEndsUnansweredLetsTheWelcomeShow() async throws {
        let ringActions = try await startRingingWithAWaitingWelcome()
        
        ringActions.send(.stopInAppRinging(roomID: "1"))
        try await waitFor { tabCoordinator?.fullScreenCoverCoordinator is InviteWelcomeScreenCoordinator }
        #expect(tabCoordinator?.fullScreenCoverCoordinator is InviteWelcomeScreenCoordinator)
    }
    
    /// The cover is set from the consent read's task; this waits on that state, at most 2 s.
    private func waitForCover(_ predicate: (CoordinatorProtocol?) -> Bool) async throws {
        for _ in 0..<200 where !predicate(tabCoordinator?.fullScreenCoverCoordinator) {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    
    /// AGENT-PLATFORM: platform sync (decision 289, review I7 L1): the
    /// session's one stream is the session's, not the Feed tab's: the session
    /// flow opens it for every tab, and its stop (sign-out) ends it for good.
    @Test
    mutating func theSessionOpensItsSyncStreamAndSignOutEndsIt() async throws {
        let platform = AgentPlatformServiceMock()
        platform.feed = FeedServiceMock.empty()
        platform.fetchAIConsentReturnValue = .success(AIConsent(isGranted: true, currentVersion: "1", decidedVersion: "1"))
        platform.fetchNotificationsActivityCursorLimitReturnValue = .success(.init(needsAction: [], activity: [], nextActivityCursor: nil,
                                                                                   lastSeenAt: nil, unseenCount: 0))
        platform.listMyAgentSpacesReturnValue = .success(.init(spaces: [], provisioningStatus: .ready))
        let sync = PlatformSyncServiceMock()
        let ended = Ended()
        sync.openSinceClosure = { _ in
            .success(PlatformSyncEventStream { continuation in
                continuation.yield(.ready(position: "p0", fresh: false))
                continuation.onTermination = { _ in ended.flag.withLock { $0 = true } }
            })
        }
        platform.sync = sync
        let agentsStore = AgentsStore(service: platform)
        let feedStore = FeedStore(feedService: platform.feed, currentUserID: "hi@bob")
        userSession.agentPlatformService = platform
        userSession.agentsStore = agentsStore
        userSession.feedStore = feedStore
        userSession.platformSync = PlatformSync(service: sync, feedStore: feedStore, agentsStore: agentsStore, isApplicationInBackground: { false })
        startCoordinator(callKitService: callKitService)

        for _ in 0..<300 where agentsStore.connectionState != .live {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(agentsStore.connectionState == .live)
        #expect(feedStore.connectionState == .live)

        userSessionFlowCoordinator.stop()
        for _ in 0..<300 where !ended.flag.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(ended.flag.withLock { $0 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(sync.openSinceCallsCount == 1)
        #expect(agentsStore.connectionState == .idle)
    }

    private final class Ended: Sendable {
        let flag = Mutex(false)
    }

    /// AGENT-PLATFORM: platform sync (decision 289): the Agents tab badge is
    /// what waits for the owner, held by the session from its start, so it
    /// follows the stream's `approval.changed` while the person is anywhere.
    @Test
    mutating func theSessionHoldsWhatWaitsForTheAgentsBadge() async {
        let platform = AgentPlatformServiceMock()
        platform.feed = FeedServiceMock.empty()
        platform.sync = PlatformSyncServiceMock.unavailable()
        platform.fetchNotificationsActivityCursorLimitReturnValue = .success(.init(needsAction: [], activity: [], nextActivityCursor: nil,
                                                                                   lastSeenAt: nil, unseenCount: 0))
        platform.listMyAgentSpacesReturnValue = .success(.init(spaces: [], provisioningStatus: .ready))
        platform.fetchAIConsentReturnValue = .success(AIConsent(isGranted: true, currentVersion: "1", decidedVersion: "1"))
        let store = AgentsStore(service: platform)
        userSession.agentPlatformService = platform
        userSession.agentsStore = store
        startCoordinator(callKitService: callKitService)
        
        #expect(store.isShown(.needsAction))
        await store.settle()
        #expect(store.needsAction?.isEmpty == true)
    }
    
    @Test
    func reachabilityIndicators() async throws {
        // Given a flow in its initial state.
        try await Task.sleep(for: .milliseconds(100))
        
        // Then no reachability indicators should be shown.
        #expect(!userIndicatorController.submitIndicatorDelayCalled)
        #expect(retractReachabilityIndicatorCallsCount == 1) // The initial state removes the indicator.
        
        // When the homeserver becomes unreachable.
        homeserverReachabilitySubject.send(.unreachable)
        try await Task.sleep(for: .milliseconds(100))
        
        // Then a server unreachable indicator should be shown.
        #expect(userIndicatorController.submitIndicatorDelayCallsCount == 1)
        #expect(userIndicatorController.submitIndicatorDelayReceivedArguments?.indicator.title == L10n.commonServerUnreachable)
        #expect(retractReachabilityIndicatorCallsCount == 1)
        
        // When the network also becomes unreachable.
        networkReachabilitySubject.send(.unreachable)
        try await Task.sleep(for: .milliseconds(100))
        
        // Then the server unreachable indicator should be replaced with an offline indicator.
        #expect(userIndicatorController.submitIndicatorDelayCallsCount == 2)
        #expect(userIndicatorController.submitIndicatorDelayReceivedArguments?.indicator.title == L10n.commonOffline)
        #expect(retractReachabilityIndicatorCallsCount == 1)
        
        // When the homeserver becomes reachable again.
        homeserverReachabilitySubject.send(.reachable)
        try await Task.sleep(for: .milliseconds(100))
        
        // Then there should still be an offline indicator (as we don't yet support air-gapped servers on iOS).
        #expect(userIndicatorController.submitIndicatorDelayCallsCount == 3)
        #expect(userIndicatorController.submitIndicatorDelayReceivedArguments?.indicator.title == L10n.commonOffline)
        #expect(retractReachabilityIndicatorCallsCount == 1)
        
        // When the network becomes reachable again.
        networkReachabilitySubject.send(.reachable)
        try await Task.sleep(for: .milliseconds(100))
        
        // Then the indicator should be hidden now as everything is back to normal
        #expect(userIndicatorController.submitIndicatorDelayCallsCount == 3)
        #expect(retractReachabilityIndicatorCallsCount == 2)
        
        // When the client is suspended.
        homeserverReachabilitySubject.send(.suspended)
        try await Task.sleep(for: .milliseconds(100))
        
        // Then no unreachable indicator should be shown as the pause is intentional.
        #expect(userIndicatorController.submitIndicatorDelayCallsCount == 3)
        #expect(retractReachabilityIndicatorCallsCount == 3)
    }
    
    // MARK: - Calls (AGENT-PLATFORM, Brief 0067 call audit 2026-09-05)
    
    /// The user answered from CallKit, then pressed End while the room was
    /// still being looked up. The lookup used to resume into a fresh call
    /// screen — a new CallKit call, a MatrixRTC join, a published microphone —
    /// for a call the user had just refused. Now the resume sees the call's
    /// generation has moved and presents nothing.
    @Test
    func endingAnAnsweredCallDuringRoomLookupPresentsNothing() async throws {
        let ongoing = CurrentValueSubject<String?, Never>("1")
        callKitService.ongoingCallRoomIDPublisher = ongoing.asCurrentValuePublisher()
        let gate = LookupGate()
        clientProxy.roomForIdentifierClosure = { roomID in
            await gate.wait()
            return .joined(Self.callableRoom(id: roomID))
        }
        
        userSessionFlowCoordinator.handleAppRoute(.call(roomID: "1", isVoiceCall: true), animated: true)
        try await Task.sleep(for: .milliseconds(50))
        
        // End from the system UI: CallKit no longer holds the call.
        ongoing.send(nil)
        gate.open()
        try await Task.sleep(for: .milliseconds(100))
        
        #expect(tabCoordinator?.overlayCoordinator == nil,
                "a call the user ended during the lookup must not come back as a call screen")
    }
    
    /// Control: the same route with the call still held presents the screen —
    /// the generation check must not swallow a legitimate answer.
    @Test
    func anAnsweredCallStillHeldAfterRoomLookupIsPresented() async throws {
        callKitService.ongoingCallRoomIDPublisher = CurrentValueSubject<String?, Never>("1").asCurrentValuePublisher()
        clientProxy.roomForIdentifierClosure = { roomID in .joined(Self.callableRoom(id: roomID)) }
        
        userSessionFlowCoordinator.handleAppRoute(.call(roomID: "1", isVoiceCall: true), animated: true)
        try await Task.sleep(for: .milliseconds(100))
        
        #expect(tabCoordinator?.overlayCoordinator is NativeCallScreenCoordinator)
    }
    
    // MARK: - In-app ring answers (follow-up L1)
    
    /// The in-app fallback ring is not CallKit's ongoing call until its screen
    /// registers, so the re-check above never covered it: a caller who hung up
    /// while the room was being looked up still got a call screen — and, the
    /// room no longer showing the call, one that rang them back.
    @Test
    mutating func aCallerHangingUpDuringAnInAppAnswerGetsNoScreenAndNoRing() async throws {
        let ring = try await ringInApp(roomShowsTheCall: true)
        let gate = LookupGate()
        // The fresh proxy reads the room as it is after the hang-up.
        let room = Self.callableRoom(id: ring.roomID, hasOngoingCall: false)
        let rtcSession = try #require(try room.matrixRTCSessionReturnValue.get() as? MatrixRTCSessionMock)
        clientProxy.roomForIdentifierClosure = { _ in
            await gate.wait()
            return .joined(room)
        }
        
        ring.screen.send(.accept)
        try await Task.sleep(for: .milliseconds(50))
        ring.roomInfo.send(RoomInfoProxyMock(.init(id: ring.roomID, hasOngoingCall: false)))
        try await Task.sleep(for: .milliseconds(50))
        gate.open()
        try await Task.sleep(for: .milliseconds(200))
        
        #expect(tabCoordinator?.overlayCoordinator == nil, "a call the caller ended during the lookup must not get a screen")
        #expect(!rtcSession.joinEncryptMediaNotificationMediaLanguageCalled, "nobody is called back")
    }
    
    /// Answering must never turn into calling: an in-app answer whose room
    /// does not show the call yet (the ring outran the sync) joins it without
    /// ringing anyone.
    @Test
    mutating func anInAppAnswerJoinsWithoutRinging() async throws {
        let ring = try await ringInApp(roomShowsTheCall: false)
        let room = Self.callableRoom(id: ring.roomID, hasOngoingCall: false)
        let rtcSession = try #require(try room.matrixRTCSessionReturnValue.get() as? MatrixRTCSessionMock)
        clientProxy.roomForIdentifierClosure = { _ in .joined(room) }
        
        ring.screen.send(.accept)
        try await waitFor { rtcSession.joinEncryptMediaNotificationMediaLanguageCalled }
        
        #expect(tabCoordinator?.overlayCoordinator is NativeCallScreenCoordinator, "a live ring is answered")
        #expect(rtcSession.joinEncryptMediaNotificationMediaLanguageReceivedArguments?.notification == nil, "an answer sends no ring")
    }
    
    /// The caller hung up and redialled during the in-app answer's lookup,
    /// and the redial reached CallKit, where the user answered it. Giving up
    /// on the first ring used to tear its room's call down by the room —
    /// ending the redial the user was now in.
    @Test
    mutating func aRedialAnsweredFromCallKitDuringAnInAppAnswerStaysUp() async throws {
        let ring = try await ringInApp(roomShowsTheCall: true)
        let gate = LookupGate()
        let room = Self.callableRoom(id: ring.roomID)
        clientProxy.roomForIdentifierClosure = { _ in
            await gate.wait()
            return .joined(room)
        }
        
        ring.screen.send(.accept)
        try await Task.sleep(for: .milliseconds(50))
        ring.callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in completion(nil) }
        let redial = PKPushPayloadMock().updatingExpiration(Date(), lifetime: 30)
        redial.dict[CallKitNotificationKey.roomID.rawValue] = ring.roomID
        redial.dict[CallKitNotificationKey.rtcNotifyEventID.rawValue] = "$redial"
        await waitForConfirmation { confirmation in
            ring.service.pushRegistry(PKPushRegistry(queue: nil), didReceiveIncomingPushWith: redial, for: .voIP) { confirmation() }
        }
        let redialID = try #require(ring.callProvider.reportNewIncomingCallWithUpdateCompletionReceivedInvocations.last?.uuid)
        ring.service.provider(CXProvider(configuration: CXProviderConfiguration()), perform: CXAnswerCallAction(call: redialID))
        #expect(ring.service.ongoingCallRoomIDPublisher.value == ring.roomID, "precondition: the redial is the live call")
        gate.open()
        try await Task.sleep(for: .milliseconds(200))
        
        #expect(ring.service.ongoingCallRoomIDPublisher.value == ring.roomID, "the answered redial stays up")
        let ends = ring.callController.requestedTransactions.flatMap(\.actions).compactMap { $0 as? CXEndCallAction }
        #expect(!ends.contains { $0.callUUID == redialID }, "nobody asks CallKit to end it")
    }
    
    /// N1 review: an outgoing call still connecting when its room rings in
    /// the app (CallKit refused it: Do Not Disturb). Accepting the ring
    /// returns to the outgoing screen, so the ring never got a screen of its
    /// own. The user hangs up before the outgoing call registers: the ring
    /// outlived the screen, and the room's next call adopted it, a call
    /// CallKit never had.
    @Test
    mutating func anInAppAnswerReturningToAnOutgoingScreenEndsWithIt() async throws {
        let roomID = "!room:example.com"
        let callProvider = CXProviderMock(.init())
        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(CXErrorCodeIncomingCallError(.filteredByDoNotDisturb))
        }
        let callController = CallControllerStub()
        let service = CallKitService(callProvider: callProvider, callController: callController)
        let room = Self.callableRoom(id: roomID, hasOngoingCall: false)
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        let rtcSession = try #require(try room.matrixRTCSessionReturnValue.get() as? MatrixRTCSessionMock)
        let join = LookupGate()
        rtcSession.joinEncryptMediaNotificationMediaLanguageClosure = { _, _, _, _ in
            await join.wait()
            return .success(())
        }
        clientProxy.roomForIdentifierClosure = { _ in .joined(room) }
        service.setClientProxy(clientProxy)
        startCoordinator(callKitService: service)

        userSessionFlowCoordinator.handleAppRoute(.call(roomID: roomID, isVoiceCall: true), animated: true)
        try await waitFor { tabCoordinator?.overlayCoordinator is NativeCallScreenCoordinator }
        let outgoing = try #require(tabCoordinator?.overlayCoordinator as? NativeCallScreenCoordinator)
        let push = PKPushPayloadMock().updatingExpiration(Date(), lifetime: 30)
        push.dict[CallKitNotificationKey.roomID.rawValue] = roomID
        await waitForConfirmation { confirmation in
            service.pushRegistry(PKPushRegistry(queue: nil), didReceiveIncomingPushWith: push, for: .voIP) { confirmation() }
        }
        try await waitFor { tabCoordinator?.fullScreenCoverCoordinator is NativeCallIncomingScreenCoordinator }
        let incoming = try #require(tabCoordinator?.fullScreenCoverCoordinator as? NativeCallIncomingScreenCoordinator)
        incoming.send(.accept)
        // The answer returned to the outgoing screen and bound it to the ring.
        try await waitFor { outgoing.callKitID != nil }
        #expect(tabCoordinator?.overlayCoordinator === outgoing)

        outgoing.stop()
        try await waitFor(attempts: 300) { service.callKitID(forRoomID: roomID) == nil }

        #expect(service.callKitID(forRoomID: roomID) == nil, "the accepted ring goes with the screen it landed on")
        #expect(rtcSession.leaveCalled)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room", isVoiceCall: true)
        let starts = callController.requestedTransactions.flatMap(\.actions).compactMap { $0 as? CXStartCallAction }
        #expect(starts.count == 1, "the room's next call is a CallKit call")
        join.open()
    }
    
    /// Residual of the call follow-ups: a call route to a room whose screen
    /// still shows its call's end (it stays up 1.5 s, or 3 s after a failure)
    /// returned to that dead screen, so no call started.
    @Test
    func aCallRouteReplacesAnEndedCallScreen() async throws {
        let room = Self.callableRoom(id: "1")
        let rtcSession = try #require(try room.matrixRTCSessionReturnValue.get() as? MatrixRTCSessionMock)
        clientProxy.roomForIdentifierClosure = { _ in .joined(room) }
        userSessionFlowCoordinator.handleAppRoute(.call(roomID: "1", isVoiceCall: true), animated: true)
        try await waitFor { tabCoordinator?.overlayCoordinator is NativeCallScreenCoordinator }
        let ended = try #require(tabCoordinator?.overlayCoordinator as? NativeCallScreenCoordinator)
        // The SFU refuses the session, so the call fails and its screen shows it.
        try await waitFor { rtcSession.leaveCalled }
        try await Task.sleep(for: .milliseconds(50))

        userSessionFlowCoordinator.handleAppRoute(.call(roomID: "1", isVoiceCall: true), animated: true)

        try await waitFor { (tabCoordinator?.overlayCoordinator as? NativeCallScreenCoordinator).map { $0 !== ended } ?? false }
        #expect(tabCoordinator?.overlayCoordinator is NativeCallScreenCoordinator)
        #expect(tabCoordinator?.overlayCoordinator !== ended, "a fresh screen, not the dead one")
    }

    /// Audit C6 still holds: a re-tap while the call connects returns to its
    /// live screen rather than racing a second join.
    @Test
    func aCallRouteReturnsToAConnectingCallScreen() async throws {
        let room = Self.callableRoom(id: "1")
        let rtcSession = try #require(try room.matrixRTCSessionReturnValue.get() as? MatrixRTCSessionMock)
        let join = LookupGate()
        rtcSession.joinEncryptMediaNotificationMediaLanguageClosure = { _, _, _, _ in
            await join.wait()
            return .success(())
        }
        clientProxy.roomForIdentifierClosure = { _ in .joined(room) }
        userSessionFlowCoordinator.handleAppRoute(.call(roomID: "1", isVoiceCall: true), animated: true)
        try await waitFor { tabCoordinator?.overlayCoordinator is NativeCallScreenCoordinator }
        let connecting = try #require(tabCoordinator?.overlayCoordinator as? NativeCallScreenCoordinator)
        try await waitFor { rtcSession.joinEncryptMediaNotificationMediaLanguageCalled }
        // Behind its bar, so the re-tap's return to it shows.
        tabCoordinator?.setOverlayPresentationMode(.minimized)

        userSessionFlowCoordinator.handleAppRoute(.call(roomID: "1", isVoiceCall: true), animated: true)
        try await waitFor { tabCoordinator?.overlayPresentationMode == .fullScreen }

        #expect(tabCoordinator?.overlayCoordinator === connecting)
        #expect(rtcSession.joinEncryptMediaNotificationMediaLanguageCallsCount == 1, "no second join")
        join.open()
    }

    // MARK: - Replacing an ended screen while a call is parked (M1 review)

    /// A call route to B while B's screen shows its call's end and A is
    /// parked. B's late teardown brought A back over B's fresh screen, and
    /// the fresh call's registration ended A under it: A's screen stayed up
    /// with its session live and no CallKit call, B's fresh screen parked out
    /// of reach. B's call goes at the route now; A stays parked until the
    /// fresh call registers and replaces it.
    @Test
    mutating func aCallRouteOverAnEndedScreenKeepsTheParkedCallUntilTheNewCallRegisters() async throws {
        let parked = try await aCallParkedBehindAnEndedOne()
        let freshB = Self.callableRoom(id: parked.roomB.id)
        let bJoin = LookupGate()
        try Self.holdJoin(of: freshB, on: bJoin)
        let rooms = [parked.roomA, freshB]
        clientProxy.roomForIdentifierClosure = { roomID in rooms.first { $0.id == roomID }.map { .joined($0) } }

        userSessionFlowCoordinator.handleAppRoute(.call(roomID: freshB.id, isVoiceCall: true), animated: true)
        try await waitFor { (tabCoordinator?.overlayCoordinator as? NativeCallScreenCoordinator).map { $0 !== parked.bScreen && $0.callRoomID == freshB.id } ?? false }
        let bScreen = try #require(tabCoordinator?.overlayCoordinator as? NativeCallScreenCoordinator)
        // B's call is ended once, whichever teardown takes it.
        try await waitFor { parked.endActions(for: parked.b) == 1 }
        #expect(parked.service.heldCallPublisher.value?.roomID == parked.roomA.id, "A stays parked")
        #expect(parked.aScreen.isParked)

        await parked.service.setupCallSession(roomID: freshB.id, roomDisplayName: "Room B", isVoiceCall: true)

        #expect(parked.endActions(for: parked.a) == 1, "B's fresh call replaces A")
        try await waitFor { parked.aSession.leaveCalled }
        #expect(tabCoordinator?.overlayCoordinator === bScreen)
        #expect(parked.service.ongoingCallRoomIDPublisher.value == freshB.id)
        parked.aJoin.open()
        bJoin.open()
    }

    /// The third-room variant: a call to C over B's ended screen. B's late
    /// teardown brought A back over C's screen, resumed, for the moments
    /// until C registered and ended it. B's call goes at the route now, as
    /// on a route to its own room, and A stays parked until C replaces it.
    @Test
    mutating func aCallToAThirdRoomOverAnEndedScreenKeepsTheParkedCallUntilItRegisters() async throws {
        let parked = try await aCallParkedBehindAnEndedOne()
        let roomC = Self.callableRoom(id: "!c:example.com")
        let cJoin = LookupGate()
        try Self.holdJoin(of: roomC, on: cJoin)
        let rooms = [parked.roomA, parked.roomB, roomC]
        clientProxy.roomForIdentifierClosure = { roomID in rooms.first { $0.id == roomID }.map { .joined($0) } }

        userSessionFlowCoordinator.handleAppRoute(.call(roomID: roomC.id, isVoiceCall: true), animated: true)
        let cScreen = try await waitForCallScreen(roomID: roomC.id)
        // B's call is ended once, whichever teardown takes it.
        try await waitFor { parked.endActions(for: parked.b) == 1 }
        #expect(parked.service.heldCallPublisher.value?.roomID == parked.roomA.id, "A stays parked")
        #expect(parked.aScreen.isParked)
        #expect(!parked.callController.requestedTransactions.flatMap(\.actions).contains { ($0 as? CXSetHeldCallAction).map { $0.callUUID == parked.a && !$0.isOnHold } ?? false },
                "A is not resumed")

        await parked.service.setupCallSession(roomID: roomC.id, roomDisplayName: "Room C", isVoiceCall: true)

        #expect(parked.endActions(for: parked.a) == 1, "C's call replaces A")
        try await waitFor { parked.aSession.leaveCalled }
        #expect(tabCoordinator?.overlayCoordinator === cScreen)
        #expect(parked.service.ongoingCallRoomIDPublisher.value == roomC.id)
        parked.aJoin.open()
        cJoin.open()
    }

    /// A route to the parked room over B's ended screen is still a swap: B's
    /// call is the one CallKit holds, A the one it resumes.
    @Test
    mutating func aRouteToTheParkedRoomOverAnEndedScreenStillSwaps() async throws {
        let parked = try await aCallParkedBehindAnEndedOne()
        let transactionsBefore = parked.callController.requestedTransactions.count

        userSessionFlowCoordinator.handleAppRoute(.call(roomID: parked.roomA.id, isVoiceCall: true), animated: true)

        try await waitFor { parked.callController.requestedTransactions.count > transactionsBefore }
        let swap = parked.callController.requestedTransactions.last?.actions.compactMap { $0 as? CXSetHeldCallAction } ?? []
        #expect(swap.contains { $0.callUUID == parked.b && $0.isOnHold })
        #expect(swap.contains { $0.callUUID == parked.a && !$0.isOnHold })
        #expect(parked.endActions(for: parked.b) == 0, "B's call is not taken down first")
        parked.aJoin.open()
    }

    /// Residual of the second-accept round: a second in-app accept, of a
    /// third room, gives up the first one's screen. With A parked behind that
    /// screen, its dismissal brought A's screen forward until the second
    /// answer's screen parked it again. A's screen stays parked now.
    @Test
    mutating func aScreenGivenUpByANewerAcceptLeavesTheParkedScreenParked() async throws {
        let parked = try await aCallParkedForAnInAppAccept()
        let lookup = LookupGate()

        try await acceptASecondInAppRing(over: parked, lookup: lookup)
        try await waitFor { tabCoordinator?.overlayCoordinator !== parked.b1Screen }

        #expect(tabCoordinator?.overlayCoordinator == nil, "A's screen is not brought forward")
        #expect(parked.aScreen.isParked)
        #expect(parked.service.heldCallPublisher.value?.roomID == parked.roomA.id, "A stays parked for the second answer")

        lookup.open()
        let b2Screen = try await waitForCallScreen(roomID: parked.roomB2.id)
        #expect(tabCoordinator?.overlayCoordinator === b2Screen)
        #expect(parked.aScreen.isParked, "A's screen waits behind the second answer's")
        parked.openJoins()
    }

    /// The second accept's ring ending while its room is looked up: the call
    /// parked for it comes back, and with it its screen.
    @Test
    mutating func theParkedScreenComesBackWhenTheNewerAcceptNeverStarts() async throws {
        let parked = try await aCallParkedForAnInAppAccept()
        let lookup = LookupGate()
        try await acceptASecondInAppRing(over: parked, lookup: lookup)
        try await waitFor { tabCoordinator?.overlayCoordinator !== parked.b1Screen }

        parked.b2Info.send(RoomInfoProxyMock(.init(id: parked.roomB2.id, hasOngoingCall: false)))
        try await waitFor { !parked.service.isAcceptedRingLive(forRoomID: parked.roomB2.id) }
        lookup.open()
        try await waitFor { parked.service.heldCallPublisher.value == nil }
        try await waitFor { tabCoordinator?.overlayCoordinator === parked.aScreen }

        #expect(tabCoordinator?.overlayCoordinator === parked.aScreen, "A's screen comes back")
        #expect(!parked.aScreen.isParked)
        #expect(parked.service.heldCallPublisher.value == nil)
        #expect(parked.service.ongoingCallRoomIDPublisher.value == parked.roomA.id)
        #expect(parked.callController.requestedTransactions.flatMap(\.actions).contains { ($0 as? CXSetHeldCallAction).map { $0.callUUID == parked.a && !$0.isOnHold } ?? false },
                "A is resumed")
        parked.openJoins()
    }

    /// A answered from the CallKit banner and on its screen, then a ring of B1
    /// in the app (CallKit refused it) accepted: B1's screen is up and still
    /// connecting, so unregistered, with A's screen parked behind it.
    private mutating func aCallParkedForAnInAppAccept() async throws -> ParkedForAnAccept {
        let callProvider = CXProviderMock(.init())
        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in completion(nil) }
        let callController = CallControllerStub()
        let service = CallKitService(callProvider: callProvider, callController: callController)
        let joins = (a: LookupGate(), b1: LookupGate(), b2: LookupGate())
        let roomA = Self.callableRoom(id: "!a:example.com")
        try Self.holdJoin(of: roomA, on: joins.a)
        let roomB1 = Self.callableRoom(id: "!b1:example.com")
        try Self.holdJoin(of: roomB1, on: joins.b1)
        let roomB2 = Self.callableRoom(id: "!b2:example.com")
        try Self.holdJoin(of: roomB2, on: joins.b2)
        let b2Info = CurrentValueSubject<RoomInfoProxyProtocol, Never>(roomB2.infoPublisher.value)
        roomB2.infoPublisher = b2Info.asCurrentValuePublisher()
        let rooms = [roomA, roomB1, roomB2]
        clientProxy.roomForIdentifierClosure = { roomID in rooms.first { $0.id == roomID }.map { .joined($0) } }
        service.setClientProxy(clientProxy)
        startCoordinator(callKitService: service)

        let a = try await answerFromCallKit(roomID: roomA.id, notification: "$a", service: service, callProvider: callProvider)
        let aScreen = try await waitForCallScreen(roomID: roomA.id)
        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(CXErrorCodeIncomingCallError(.filteredByDoNotDisturb))
        }
        try await ringInApp(roomID: roomB1.id, notification: "$b1", service: service).send(.accept)
        let b1Screen = try await waitForCallScreen(roomID: roomB1.id)
        #expect(aScreen.isParked, "precondition: A is parked behind B1's screen")
        return ParkedForAnAccept(service: service, callController: callController, roomA: roomA, roomB2: roomB2, b2Info: b2Info,
                                 a: a, aScreen: aScreen, b1Screen: b1Screen, joins: [joins.a, joins.b1, joins.b2])
    }

    /// A ring of B2 in the app, accepted while its room's lookup for the
    /// screen waits on `lookup`. The service's observer of B2 is in place
    /// first.
    private mutating func acceptASecondInAppRing(over parked: ParkedForAnAccept, lookup: LookupGate) async throws {
        try await waitFor { tabCoordinator?.fullScreenCoverCoordinator == nil }
        let incoming = try await ringInApp(roomID: parked.roomB2.id, notification: "$b2", service: parked.service)
        let rooms = [parked.roomA, parked.roomB2]
        clientProxy.roomForIdentifierClosure = { roomID in
            if roomID == parked.roomB2.id {
                await lookup.wait()
            }
            return rooms.first { $0.id == roomID }.map { .joined($0) }
        }
        incoming.send(.accept)
    }

    /// A ring of `roomID` that CallKit refused, ringing in the app.
    private func ringInApp(roomID: String, notification: String, service: CallKitService) async throws -> NativeCallIncomingScreenCoordinator {
        let push = PKPushPayloadMock().updatingExpiration(Date(), lifetime: 30)
        push.dict[CallKitNotificationKey.roomID.rawValue] = roomID
        push.dict[CallKitNotificationKey.rtcNotifyEventID.rawValue] = notification
        await waitForConfirmation { confirmation in
            service.pushRegistry(PKPushRegistry(queue: nil), didReceiveIncomingPushWith: push, for: .voIP) { confirmation() }
        }
        try await waitFor { tabCoordinator?.fullScreenCoverCoordinator is NativeCallIncomingScreenCoordinator }
        // The service's observer of the ringing room is in place.
        try await Task.sleep(for: .milliseconds(50))
        return try #require(tabCoordinator?.fullScreenCoverCoordinator as? NativeCallIncomingScreenCoordinator)
    }

    /// A real service with A parked behind B, both answered from the CallKit
    /// banner and on their screens, and B's screen showing its call's end
    /// (its SFU refused the session). A's join waits, so A stays connecting.
    private mutating func aCallParkedBehindAnEndedOne() async throws -> ParkedBehindEnded {
        let callProvider = CXProviderMock(.init())
        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in completion(nil) }
        let callController = CallControllerStub()
        let service = CallKitService(callProvider: callProvider, callController: callController)
        let roomA = Self.callableRoom(id: "!a:example.com")
        let aJoin = LookupGate()
        try Self.holdJoin(of: roomA, on: aJoin)
        let roomB = Self.callableRoom(id: "!b:example.com")
        let rooms = [roomA, roomB]
        clientProxy.roomForIdentifierClosure = { roomID in rooms.first { $0.id == roomID }.map { .joined($0) } }
        service.setClientProxy(clientProxy)
        startCoordinator(callKitService: service)

        let a = try await answerFromCallKit(roomID: roomA.id, notification: "$a", service: service, callProvider: callProvider)
        let aScreen = try await waitForCallScreen(roomID: roomA.id)
        let b = try await answerFromCallKit(roomID: roomB.id, notification: "$b", service: service, callProvider: callProvider)
        let bScreen = try await waitForCallScreen(roomID: roomB.id)
        #expect(aScreen.isParked, "precondition: A is parked behind B")
        try await waitFor { bScreen.hasCallEnded }
        return try ParkedBehindEnded(service: service,
                                     callController: callController,
                                     roomA: roomA,
                                     roomB: roomB,
                                     a: a,
                                     aScreen: aScreen,
                                     aSession: #require(try roomA.matrixRTCSessionReturnValue.get() as? MatrixRTCSessionMock),
                                     aJoin: aJoin,
                                     b: b,
                                     bScreen: bScreen)
    }

    /// A ring of `roomID` reported to CallKit, answered from its banner, and
    /// routed to its screen.
    private func answerFromCallKit(roomID: String, notification: String, service: CallKitService, callProvider: CXProviderMock) async throws -> UUID {
        let push = PKPushPayloadMock().updatingExpiration(Date(), lifetime: 30)
        push.dict[CallKitNotificationKey.roomID.rawValue] = roomID
        push.dict[CallKitNotificationKey.rtcNotifyEventID.rawValue] = notification
        await waitForConfirmation { confirmation in
            service.pushRegistry(PKPushRegistry(queue: nil), didReceiveIncomingPushWith: push, for: .voIP) { confirmation() }
        }
        let callKitID = try #require(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedInvocations.last?.uuid)
        service.provider(CXProvider(configuration: CXProviderConfiguration()), perform: CXAnswerCallAction(call: callKitID))
        userSessionFlowCoordinator.handleAppRoute(.call(roomID: roomID, isVoiceCall: true), animated: true)
        return callKitID
    }

    /// The call screen of `roomID` once it is on screen.
    private func waitForCallScreen(roomID: String) async throws -> NativeCallScreenCoordinator {
        try await waitFor { (tabCoordinator?.overlayCoordinator as? NativeCallScreenCoordinator)?.callRoomID == roomID }
        return try #require(tabCoordinator?.overlayCoordinator as? NativeCallScreenCoordinator)
    }

    /// The room's next call session joins only once `gate` opens: its screen stays connecting.
    private static func holdJoin(of room: JoinedRoomProxyMock, on gate: LookupGate) throws {
        let rtcSession = try #require(try room.matrixRTCSessionReturnValue.get() as? MatrixRTCSessionMock)
        rtcSession.joinEncryptMediaNotificationMediaLanguageClosure = { _, _, _, _ in
            await gate.wait()
            return .success(())
        }
    }

    /// A real `CallKitService` behind a fresh coordinator, ringing in the app
    /// because CallKit refused the ring.
    private mutating func ringInApp(roomShowsTheCall: Bool, withSheetsOpen: Bool = false) async throws -> InAppRing {
        let roomID = "!room:example.com"
        let callProvider = CXProviderMock(.init())
        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(CXErrorCodeIncomingCallError(.filteredByDoNotDisturb))
        }
        let callController = CallControllerStub()
        let service = CallKitService(callProvider: callProvider, callController: callController)
        
        let observedRoom = JoinedRoomProxyMock(.init(id: roomID, hasOngoingCall: roomShowsTheCall))
        let roomInfo = CurrentValueSubject<RoomInfoProxyProtocol, Never>(observedRoom.infoPublisher.value)
        observedRoom.infoPublisher = roomInfo.asCurrentValuePublisher()
        observedRoom.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        clientProxy.roomForIdentifierClosure = { _ in .joined(observedRoom) }
        service.setClientProxy(clientProxy)
        
        startCoordinator(callKitService: service)
        if withSheetsOpen {
            try openSheetsAboveTheTabs()
        }
        
        let push = PKPushPayloadMock().updatingExpiration(Date(), lifetime: 30)
        push.dict[CallKitNotificationKey.roomID.rawValue] = roomID
        await waitForConfirmation { confirmation in
            service.pushRegistry(PKPushRegistry(queue: nil), didReceiveIncomingPushWith: push, for: .voIP) { confirmation() }
        }
        try await waitFor { tabCoordinator?.fullScreenCoverCoordinator is NativeCallIncomingScreenCoordinator }
        let screen = try #require(tabCoordinator?.fullScreenCoverCoordinator as? NativeCallIncomingScreenCoordinator)
        // The service's observer of the ringing room is in place.
        try await Task.sleep(for: .milliseconds(50))
        return InAppRing(roomID: roomID, roomInfo: roomInfo, screen: screen, service: service, callProvider: callProvider, callController: callController)
    }
    
    private static func callableRoom(id: String, hasOngoingCall: Bool = true) -> JoinedRoomProxyMock {
        let roomProxy = JoinedRoomProxyMock(.init(id: id, name: "Room \(id)", hasOngoingCall: hasOngoingCall))
        roomProxy.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        let rtcSession = MatrixRTCSessionMock()
        rtcSession.underlyingOwnIdentity = "@alice:matrix.org:DEVICE"
        rtcSession.underlyingUpdates = Empty().eraseToAnyPublisher()
        rtcSession.joinEncryptMediaNotificationMediaLanguageReturnValue = .success(())
        rtcSession.setMediaReturnValue = .success(())
        rtcSession.rtcNotificationEventIDReturnValue = "$ring:matrix.org"
        rtcSession.transportCredentialsReturnValue = .failure(.roomInvalid)
        rtcSession.leaveReturnValue = .success(())
        rtcSession.membershipsReturnValue = .success([.init(userID: "@bob:matrix.org", deviceID: "BOB", identity: "@bob:matrix.org:BOB")])
        roomProxy.matrixRTCSessionReturnValue = .success(rtcSession)
        return roomProxy
    }
    
    // MARK: - Helpers
    
    private func process(route: AppRoute,
                         expectedUserSessionState: UserSessionFlowCoordinator.State? = nil,
                         expectedChatsState: ChatsTabFlowCoordinatorStateMachine.State? = nil) async throws {
        // Keep the previous root coordinator alive while waiting, otherwise a newly presented
        // coordinator could be allocated at the same address and be mistaken for it below.
        let previousDetailRootCoordinator = chatsSplitCoordinator?.detailRootCoordinator
        let previousDetailRootCoordinatorID = previousDetailRootCoordinator.map { ObjectIdentifier($0) }
        
        let deferredUserSession: DeferredFulfillment<UserSessionFlowCoordinator.State>? = if let expectedUserSessionState {
            deferFulfillment(stateMachineFactory.userSessionFlowStatePublisher) { $0 == expectedUserSessionState }
        } else {
            nil
        }
        
        let deferredChatsState: DeferredFulfillment<ChatsTabFlowCoordinatorStateMachine.State>? = if let expectedChatsState {
            deferFulfillment(stateMachineFactory.chatsTabFlowStatePublisher) { $0 == expectedChatsState }
        } else {
            nil
        }
        
        userSessionFlowCoordinator.handleAppRoute(route, animated: true)
        try await deferredUserSession?.fulfill()
        try await deferredChatsState?.fulfill()
        
        // The state machines' states change before the coordinators have updated their stacks,
        // so also wait for the navigation side effects implied by the expected states.
        switch expectedUserSessionState {
        case .tabBar:
            let tabCoordinator = try #require(tabCoordinator)
            let deferredSheet = deferFulfillment(tabCoordinator.observe(\.sheetCoordinatorID)) { $0 == nil }
            try await deferredSheet.fulfill()
        default:
            break
        }
        
        switch expectedChatsState {
        case .roomList(detailState: .some(.room)):
            let splitCoordinator = try #require(chatsSplitCoordinator)
            let deferredDetail = deferFulfillment(splitCoordinator.observe(\.detailRootCoordinatorID)) { $0 != nil && $0 != previousDetailRootCoordinatorID }
            try await deferredDetail.fulfill()
        case .shareExtensionRoomList:
            let splitCoordinator = try #require(chatsSplitCoordinator)
            let deferredSheet = deferFulfillment(splitCoordinator.observe(\.sheetCoordinatorID)) { $0 != nil }
            try await deferredSheet.fulfill()
        default:
            break
        }
        
        withExtendedLifetime(previousDetailRootCoordinator) { }
    }
    
    private func waitFor(attempts: Int = 200, _ condition: () -> Bool) async throws {
        for _ in 0..<attempts {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for the expected state")
    }
    
    /// Other services retract indicators, so this filters based on the reachability ID.
    private var retractReachabilityIndicatorCallsCount: Int {
        userIndicatorController
            .retractIndicatorWithIdReceivedInvocations
            .filter { $0 == "com.spiral.reachability.notification" } // AGENT-PLATFORM (Brief 0083 L1b)
            .count
    }
}

private struct ParkedBehindEnded {
    let service: CallKitService
    let callController: CallControllerStub
    let roomA: JoinedRoomProxyMock
    let roomB: JoinedRoomProxyMock
    let a: UUID
    let aScreen: NativeCallScreenCoordinator
    let aSession: MatrixRTCSessionMock
    let aJoin: LookupGate
    let b: UUID
    let bScreen: NativeCallScreenCoordinator

    func endActions(for callKitID: UUID) -> Int {
        callController.requestedTransactions.flatMap(\.actions).compactMap { $0 as? CXEndCallAction }.count { $0.callUUID == callKitID }
    }
}

private struct ParkedForAnAccept {
    let service: CallKitService
    let callController: CallControllerStub
    let roomA: JoinedRoomProxyMock
    let roomB2: JoinedRoomProxyMock
    /// What the service's observer of B2's ring sees.
    let b2Info: CurrentValueSubject<RoomInfoProxyProtocol, Never>
    let a: UUID
    let aScreen: NativeCallScreenCoordinator
    let b1Screen: NativeCallScreenCoordinator
    let joins: [LookupGate]

    func openJoins() {
        joins.forEach { $0.open() }
    }
}

private struct InAppRing {
    let roomID: String
    /// What the service's observer of the ringing room sees.
    let roomInfo: CurrentValueSubject<RoomInfoProxyProtocol, Never>
    let screen: NativeCallIncomingScreenCoordinator
    let service: CallKitService
    let callProvider: CXProviderMock
    let callController: CallControllerStub
}

/// CallKit transactions that succeed without reaching the system.
private final class CallControllerStub: CXCallControllerProtocol {
    private(set) var requestedTransactions = [CXTransaction]()

    func request(_ transaction: CXTransaction) async throws {
        requestedTransactions.append(transaction)
    }

    func request(_ transaction: CXTransaction, completion: @escaping @Sendable (Error?) -> Void) {
        requestedTransactions.append(transaction)
        completion(nil)
    }
}

/// A manually-opened suspension point for scripting "the user acted while
/// this lookup was in flight".
private final class LookupGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if isOpen {
                    continuation.resume()
                } else {
                    continuations.append(continuation)
                }
            }
        }
    }

    func open() {
        let waiting: [CheckedContinuation<Void, Never>] = lock.withLock {
            isOpen = true
            defer { continuations.removeAll() }
            return continuations
        }
        waiting.forEach { $0.resume() }
    }
}

/// A window whose size class a test sets: a bare window has none.
private final class SizeClassWindow: UIWindow {
    var horizontalSizeClass = UIUserInterfaceSizeClass.compact
    
    override var traitCollection: UITraitCollection {
        UITraitCollection(horizontalSizeClass: horizontalSizeClass)
    }
}

// MARK: - The call screen on top (1.0.2)

// An extension, so the suite's body stays within SwiftLint's length; the tests run in the same suite.
extension UserSessionFlowCoordinatorTests {
    /// AGENT-PLATFORM (1.0.2, DEBT "a call under the sheet"): the call screen is the tab view's overlay, which every
    /// sheet and cover sits above: answered with Settings open, the call ran with its controls hidden. The sheets
    /// close, and the viewers over the app are told to.
    @Test
    func aCallClosesTheSheetsAboveItsScreen() async throws {
        callKitService.ongoingCallRoomIDPublisher = CurrentValueSubject<String?, Never>("1").asCurrentValuePublisher()
        clientProxy.roomForIdentifierClosure = { roomID in .joined(Self.callableRoom(id: roomID)) }
        try openSheetsAboveTheTabs()
        let viewersTold = Mutex(0)
        let observer = NotificationCenter.default.addObserver(forName: .callScreenWillCoverTheApp, object: nil, queue: nil) { _ in
            viewersTold.withLock { $0 += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        
        userSessionFlowCoordinator.handleAppRoute(.call(roomID: "1", isVoiceCall: true), animated: true)
        try await waitFor { tabCoordinator?.overlayCoordinator is NativeCallScreenCoordinator }
        
        try expectNoSheetAboveTheTabs()
        #expect(viewersTold.withLock { $0 } == 1, "the media and post viewers are told to close")
    }
    
    /// The in-app ring is a cover of the tab view, which can't present while a sheet is up there or in a tab.
    @Test
    mutating func theInAppRingClosesTheSheetsSoItCanShow() async throws {
        let ring = try await ringInApp(roomShowsTheCall: true, withSheetsOpen: true)
        
        #expect(tabCoordinator?.fullScreenCoverCoordinator === ring.screen)
        try expectNoSheetAboveTheTabs()
    }
    
    /// The ring is above an ongoing call on purpose (G15): a call screen coming up under it leaves it there.
    @Test
    mutating func aCallScreenComingUpLeavesTheInAppRingAboveIt() async throws {
        let ring = try await ringInApp(roomShowsTheCall: true)
        clientProxy.roomForIdentifierClosure = { roomID in .joined(Self.callableRoom(id: roomID)) }
        
        userSessionFlowCoordinator.handleAppRoute(.call(roomID: "!other:example.com", isVoiceCall: true), animated: true)
        _ = try await waitForCallScreen(roomID: "!other:example.com")
        
        #expect(tabCoordinator?.fullScreenCoverCoordinator === ring.screen, "the ring stays up")
    }
    
    /// Fable review of 93d0663ef: closing onboarding's cover left its flow mid-step, so identity confirmation, AI
    /// consent and the invite welcome were skipped for the run. Onboarding stays; the call waits under it.
    @Test
    mutating func aCallLeavesOnboardingAboveItsScreen() async throws {
        startUnverified(gate: LookupGate())
        let onboarding = try #require(onboardingStack)
        #expect(tabCoordinator?.fullScreenCoverCoordinator === onboarding, "precondition: onboarding is up")
        
        try await routeACall()
        
        #expect(tabCoordinator?.fullScreenCoverCoordinator === onboarding)
    }
    
    /// The welcome is consumed as it shows: closing its cover lost it for good.
    @Test
    mutating func aCallLeavesTheInviteWelcomeAboveItsScreen() async throws {
        let gate = LookupGate()
        startWithAIConsentRead(needsDecision: false, gate: gate)
        userSessionFlowCoordinator.presentInviteWelcome(inviterUserID: "@inviter:spiral.md")
        gate.open()
        try await waitForCover { $0 is InviteWelcomeScreenCoordinator }
        
        try await routeACall()
        
        #expect(tabCoordinator?.fullScreenCoverCoordinator is InviteWelcomeScreenCoordinator)
    }
    
    /// Fable review of 93d0663ef: the directory's cover had no dismissal callback, so a call closing it left the
    /// Chats state on the directory and no chat opened until a relaunch.
    @Test
    func aCallClosesTheRoomDirectoryAndTheChatsStateFollows() async throws {
        let flow = try #require(userSessionFlowCoordinator)
        let chatsState = try #require(Mirror(reflecting: flow).descendant("chatsTabFlowCoordinator", "stateMachine") as? ChatsTabFlowCoordinatorStateMachine)
        clientProxy.roomDirectorySearchProxyReturnValue = RoomDirectorySearchProxyMock(.init(results: []))
        chatsState.processEvent(.showRoomDirectorySearchScreen)
        try await waitFor { chatsSplitCoordinator?.fullScreenCoverCoordinator is RoomDirectorySearchScreenCoordinator }
        
        try await routeACall()
        
        #expect(chatsSplitCoordinator?.fullScreenCoverCoordinator == nil)
        guard case .roomList = chatsState.state else {
            Issue.record("the Chats state stayed on \(chatsState.state)")
            return
        }
    }
    
    /// Fable review of 93d0663ef: a recovery key to note down, a PIN being set, a device-owner check holding a
    /// continuation. Their person can't swipe them away; a call doesn't either. The post catalogue refuses the swipe
    /// too, but only against a gesture clash (review of ee42fd8a4): a call closes it, so a ring can present.
    @Test
    func aCallLeavesTheSheetsTheirPersonCantSwipeAway() async throws {
        let keyStack = NavigationStackCoordinator()
        keyStack.setRootCoordinator(BlankFormCoordinator())
        keyStack.push(SwipeRefusingScreen())
        let catalogue = NavigationStackCoordinator()
        catalogue.isInteractiveDismissDisabled = true
        try #require(chatsSplitCoordinator).setSheetCoordinator(keyStack)
        try #require(settingsStack).setSheetCoordinator(catalogue)
        try #require(tabCoordinator).setSheetCoordinator(BlankFormCoordinator())
        
        try await routeACall()
        
        #expect(chatsSplitCoordinator?.sheetCoordinator === keyStack)
        #expect(settingsStack?.sheetCoordinator == nil, "the post catalogue refuses the swipe for a gesture clash, not to keep anything")
        #expect(tabCoordinator?.sheetCoordinator == nil, "a sheet that lets go still closes")
    }
    
    /// A route back to a call living behind its bar returns to its full screen, which a sheet would cover.
    @Test
    func aCallRouteBackToItsBarClosesTheSheets() async throws {
        let (screen, join) = try await aMinimizedCallUnderSheets()
        
        userSessionFlowCoordinator.handleAppRoute(.call(roomID: screen.callRoomID, isVoiceCall: true), animated: true)
        try await waitFor { tabCoordinator?.overlayPresentationMode == .fullScreen }
        
        #expect(tabCoordinator?.overlayCoordinator === screen)
        try expectNoSheetAboveTheTabs()
        join.open()
    }
    
    /// The call bar's tap (and the PiP window's restore button) brings the full screen back over any sheet.
    @Test
    func expandingTheCallBarClosesTheSheets() async throws {
        let (screen, join) = try await aMinimizedCallUnderSheets()
        let viewModel = try #require(Mirror(reflecting: screen).descendant("viewModel") as? NativeCallScreenViewModelProtocol)
        
        viewModel.context.send(viewAction: .expand)
        try await waitFor { tabCoordinator?.overlayPresentationMode == .fullScreen }
        
        try expectNoSheetAboveTheTabs()
        join.open()
    }
    
    /// A parked call's screen coming back (the newer accept never started) closes the sheets opened meanwhile.
    @Test
    mutating func theParkedScreenComingBackClosesTheSheets() async throws {
        let parked = try await aCallParkedForAnInAppAccept()
        let lookup = LookupGate()
        try await acceptASecondInAppRing(over: parked, lookup: lookup)
        try await waitFor { tabCoordinator?.overlayCoordinator !== parked.b1Screen }
        try openSheetsAboveTheTabs()
        
        parked.b2Info.send(RoomInfoProxyMock(.init(id: parked.roomB2.id, hasOngoingCall: false)))
        try await waitFor { !parked.service.isAcceptedRingLive(forRoomID: parked.roomB2.id) }
        lookup.open()
        try await waitFor { tabCoordinator?.overlayCoordinator === parked.aScreen }
        
        #expect(tabCoordinator?.overlayCoordinator === parked.aScreen)
        try expectNoSheetAboveTheTabs()
        parked.openJoins()
    }
    
    /// A call answered from CallKit (still held), routed to its screen.
    private func routeACall() async throws {
        userSession.agentPlatformService = nil // The call screens run without the platform, as the other call tests do.
        callKitService.ongoingCallRoomIDPublisher = CurrentValueSubject<String?, Never>("1").asCurrentValuePublisher()
        clientProxy.roomForIdentifierClosure = { roomID in .joined(Self.callableRoom(id: roomID)) }
        userSessionFlowCoordinator.handleAppRoute(.call(roomID: "1", isVoiceCall: true), animated: true)
        try await waitFor { tabCoordinator?.overlayCoordinator is NativeCallScreenCoordinator }
    }
    
    /// A call behind its bar, connecting until `join` opens, with sheets opened over the tabs since.
    private func aMinimizedCallUnderSheets() async throws -> (screen: NativeCallScreenCoordinator, join: LookupGate) {
        let room = Self.callableRoom(id: "1")
        let join = LookupGate()
        try Self.holdJoin(of: room, on: join)
        clientProxy.roomForIdentifierClosure = { _ in .joined(room) }
        userSessionFlowCoordinator.handleAppRoute(.call(roomID: "1", isVoiceCall: true), animated: true)
        let screen = try await waitForCallScreen(roomID: "1")
        tabCoordinator?.setOverlayPresentationMode(.minimized)
        try openSheetsAboveTheTabs()
        return (screen, join)
    }
    
    /// A sheet over the tab view, and one in the Chats split and in the Settings stack.
    private func openSheetsAboveTheTabs() throws {
        try #require(tabCoordinator).setSheetCoordinator(BlankFormCoordinator())
        try #require(chatsSplitCoordinator).setSheetCoordinator(BlankFormCoordinator())
        try #require(settingsStack).setSheetCoordinator(BlankFormCoordinator())
    }
    
    private func expectNoSheetAboveTheTabs() throws {
        #expect(tabCoordinator?.sheetCoordinator == nil, "the tab view's sheet")
        #expect(chatsSplitCoordinator?.sheetCoordinator == nil, "the Chats split's sheet")
        #expect(settingsStack?.sheetCoordinator == nil, "the Settings stack's sheet")
    }
}

/// A screen its person can't swipe away, like the recovery key's.
private final class SwipeRefusingScreen: HoldsItsModalAboveACall { }

// MARK: - Sign-in cover (AGENT-PLATFORM, 1.0.3)

extension UserSessionFlowCoordinatorTests {
    /// Operator, 2026-11-23: Chats showed for a moment between the sign-in and onboarding's cover. The sign-in's
    /// logo stays over the tabs while onboarding's cover is on its way.
    @Test
    mutating func theSignInLogoStaysWhileOnboardingCoversTheTabs() async throws {
        let gate = LookupGate()
        startUnverified(gate: gate, signInCover: PlaceholderScreenCoordinator(hideBrandChrome: false))
        #expect(tabCoordinator?.fullScreenCoverCoordinator is NavigationStackCoordinator, "onboarding is presenting")
        #expect(rootCoordinator.coverCoordinator is PlaceholderScreenCoordinator, "the tabs stay hidden until it is on screen")
        
        // Onboarding ends before its cover ever appeared (no window here): the logo goes with it.
        gate.open()
        try await Task.sleep(for: .milliseconds(50)) // the consent read's task
        try await skipIdentityConfirmation()
        try await waitFor { tabCoordinator?.fullScreenCoverCoordinator == nil }
        try await waitFor { rootCoordinator.coverCoordinator == nil }
    }
    
    /// Fable review (1.0.3 sign-up flashes): a cover that never appears (one doesn't show over a sheet a route opened
    /// meanwhile) left the logo over the app until relaunch. It goes after the timeout.
    @Test
    mutating func theSignInLogoGoesWhenOnboardingsCoverNeverAppears() async throws {
        startUnverified(gate: LookupGate(), signInCover: PlaceholderScreenCoordinator(hideBrandChrome: false), signInCoverTimeout: 0.2)
        #expect(rootCoordinator.coverCoordinator is PlaceholderScreenCoordinator)
        
        try await waitFor { rootCoordinator.coverCoordinator == nil }
        #expect(tabCoordinator?.fullScreenCoverCoordinator is NavigationStackCoordinator, "onboarding itself stays")
    }
    
    /// The timeout takes only the logo it was set for, not a later one.
    @Test
    mutating func theSignInLogosTimeoutLeavesALaterCover() async throws {
        startUnverified(gate: LookupGate(), signInCover: PlaceholderScreenCoordinator(hideBrandChrome: false), signInCoverTimeout: 0.2)
        let laterCover = PlaceholderScreenCoordinator(hideBrandChrome: false)
        rootCoordinator.setCoverCoordinator(laterCover)
        
        try await Task.sleep(for: .milliseconds(400))
        #expect(rootCoordinator.coverCoordinator === laterCover)
    }
    
    /// Fable review: a session that ends (sign-out, soft logout, clear cache) takes its logo with it.
    @Test
    mutating func stoppingTheSessionTakesTheSignInLogoAway() {
        startUnverified(gate: LookupGate(), signInCover: PlaceholderScreenCoordinator(hideBrandChrome: false))
        #expect(rootCoordinator.coverCoordinator != nil)
        
        userSessionFlowCoordinator.stop()
        #expect(rootCoordinator.coverCoordinator == nil)
    }
    
    /// With nothing for onboarding to show yet, the tabs are what the person gets: the logo goes at once.
    @Test
    mutating func theSignInLogoGoesWhenOnboardingHasNothingToShow() {
        let gate = LookupGate()
        startWithAIConsentRead(needsDecision: false, gate: gate, signInCover: PlaceholderScreenCoordinator(hideBrandChrome: false))
        #expect(tabCoordinator?.fullScreenCoverCoordinator == nil)
        #expect(rootCoordinator.coverCoordinator == nil)
        gate.open()
    }
}

/// AGENT-PLATFORM (1.0.3, Fable review of the sign-up flashes): the logo the OAuth sign-in puts up while the callback
/// is exchanged goes again whenever the sign-in doesn't go through.
@MainActor
struct AuthenticationFlowSignInCoverTests {
    @Test
    func aSignInThatDoesNotGoThroughTakesTheLogoAway() {
        let rootCoordinator = NavigationRootCoordinator()
        let appSettings = AppSettings.volatile()
        let service = AuthenticationService(userSessionManager: UserSessionManagerMock(.init()),
                                            encryptionKeyProvider: EncryptionKeyProvider(),
                                            clientFactory: ClientFactoryMock(.init()),
                                            appSettings: appSettings,
                                            appHooks: AppHooks())
        let flow = AuthenticationFlowCoordinator(authenticationService: service,
                                                 bugReportService: BugReportServiceMock(.init()),
                                                 navigationRootCoordinator: rootCoordinator,
                                                 appMediator: AppMediatorMock(.init()),
                                                 appSettings: appSettings,
                                                 appHooks: AppHooks(),
                                                 userIndicatorController: UserIndicatorControllerMock())
        flow.start()
        
        rootCoordinator.setCoverCoordinator(PlaceholderScreenCoordinator(hideBrandChrome: false))
        flow.finishOAuthAuthentication(with: .failure(.oAuthError(.unknown)))
        #expect(rootCoordinator.coverCoordinator == nil, "a failed exchange")
        
        rootCoordinator.setCoverCoordinator(PlaceholderScreenCoordinator(hideBrandChrome: false))
        flow.finishOAuthAuthentication(with: .success(UserSessionMock(.init())))
        #expect(rootCoordinator.coverCoordinator != nil, "a sign-in keeps it for the session")
        
        flow.finishOAuthAuthentication(with: .success(UserSessionMock(.init())))
        #expect(rootCoordinator.coverCoordinator == nil, "a sign-in the flow no longer takes")
    }
}

/// AGENT-PLATFORM (1.0.3, Fable review): a cancel on the web page comes back as an OAuth error response; it gets no logo
/// (which only flashed before the start screen came back), a callback that can sign in does.
@MainActor
struct OAuthCallbackErrorResponseTests {
    @Test
    func aCancelOrErrorIsAnErrorResponse() throws {
        let cancelled = try #require(URL(string: "io.element:/callback?error=access_denied&state=abc"))
        let inFragment = try #require(URL(string: "io.element:/callback#error=server_error&state=abc"))
        #expect(OAuthAuthenticationPresenter.isErrorResponse(cancelled))
        #expect(OAuthAuthenticationPresenter.isErrorResponse(inFragment))
    }
    
    @Test
    func aCodeIsNotAnErrorResponse() throws {
        let code = try #require(URL(string: "io.element:/callback?code=xyz&state=abc"))
        let codeInFragment = try #require(URL(string: "io.element:/callback#code=xyz&state=abc"))
        #expect(!OAuthAuthenticationPresenter.isErrorResponse(code))
        #expect(!OAuthAuthenticationPresenter.isErrorResponse(codeInFragment))
    }
}

// MARK: - Signing out (AGENT-PLATFORM, 1.0.3)

extension UserSessionFlowCoordinatorTests {
    /// AGENT-PLATFORM (1.0.3): a deleted or signed out account kept polling
    /// presence with its dead token on every foreground (the operator's log,
    /// 2026-11-23). The session flow's stop, which every sign-out path runs,
    /// ends the presence poll for good.
    @Test
    mutating func signOutStopsThePresencePoll() async throws {
        let notificationCenter = NotificationCenter()
        let asked = Asked()
        let presenceClient = ClientProxyMock(.init(userID: "hi@bob"))
        presenceClient.userPresenceForClosure = { userID in
            asked.count.withLock { $0 += 1 }
            return .success(UserPresence(userID: userID, state: .online, lastActiveAgo: 5, currentlyActive: true, receivedAt: Date()))
        }
        let service = PresenceObserverService(clientProxy: presenceClient,
                                              notificationCenter: notificationCenter,
                                              initialApplicationState: .active,
                                              tickInterval: 0.05,
                                              focusedInterval: 0.1,
                                              listInterval: 0.1)
        userSession.presenceObserverService = service
        startCoordinator(callKitService: callKitService)
        service.observe("@alice:spiral.md")
        for _ in 0..<300 where asked.count.withLock({ $0 }) == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(asked.count.withLock { $0 } > 0)
        
        userSessionFlowCoordinator.stop()
        try await Task.sleep(for: .milliseconds(100))
        let before = asked.count.withLock { $0 }
        notificationCenter.post(name: UIApplication.willResignActiveNotification, object: nil)
        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        service.observe("@alice:spiral.md")
        try await Task.sleep(for: .milliseconds(400))
        
        #expect(asked.count.withLock { $0 } == before, "the ended session kept polling presence")
    }
    
    fileprivate final class Asked: Sendable {
        let count = Mutex(0)
    }
}
