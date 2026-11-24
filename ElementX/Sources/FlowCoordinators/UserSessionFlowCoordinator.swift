//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import SwiftState
import SwiftUI

enum UserSessionFlowCoordinatorAction {
    case logout
    case clearCache
    /// Logout and disable App Lock without any confirmation. The user forgot their PIN.
    case forceLogout
}

class UserSessionFlowCoordinator: FlowCoordinatorProtocol {
    // AGENT-PLATFORM: added `.agents` case so the tab bar carries a
    // destination for the agent-platform feature.
    // AGENT-PLATFORM: feed (Brief 0082): `.feed`, second after Chats (D-P9).
    enum HomeTab: Hashable { case chats, feed, spaces, agents, settings } // AGENT-PLATFORM (Brief 0083, question 343): settings, no search tab
    
    private let navigationRootCoordinator: NavigationRootCoordinator
    private let navigationTabCoordinator: NavigationTabCoordinator<HomeTab>
    private let appLockService: AppLockServiceProtocol
    private let flowParameters: CommonFlowParameters
    // periphery:ignore - retaining purpose
    private let presenceService: PresenceService
    
    // AGENT-PLATFORM (Brief 0073): the inviter, and what to do once the welcome is really on screen (1.0.3: the
    // platform records it then, not when it is queued — a queue lost with the app must leave it owed).
    private var pendingInviteWelcome: (inviterUserID: String, onShown: () -> Void)?
    
    private var userSession: UserSessionProtocol {
        flowParameters.userSession
    }
    
    private let onboardingFlowCoordinator: OnboardingFlowCoordinator
    /// AGENT-PLATFORM (1.0.3): how long the sign-in's logo may wait for onboarding's cover, from the session's start.
    var signInCoverTimeout: TimeInterval = 3
    private let onboardingStackCoordinator: NavigationStackCoordinator
    private let chatsTabFlowCoordinator: ChatsTabFlowCoordinator
    private let chatsTabDetails: NavigationTabCoordinator<HomeTab>.TabDetails
    // AGENT-PLATFORM (decision 301): `nil` while `spacesEnabled` is off.
    private let spacesTabFlowCoordinator: SpacesTabFlowCoordinator?
    // AGENT-PLATFORM: Agents tab flow + tab metadata (S150).
    private let agentsTabFlowCoordinator: AgentSpacesTabFlowCoordinator
    private let agentsTabDetails: NavigationTabCoordinator<HomeTab>.TabDetails
    // AGENT-PLATFORM: feed (Brief 0082)
    private let feedTabFlowCoordinator: FeedTabFlowCoordinator
    private let feedTabDetails: NavigationTabCoordinator<HomeTab>.TabDetails
    
    let searchScreenCoordinator: SearchScreenCoordinator? // AGENT-PLATFORM (Brief 0083): readable, so a test can open a result.
    
    // AGENT-PLATFORM (Brief 0083, question 343): Settings is the person's tab, not a sheet.
    private let settingsFlowCoordinator: SettingsFlowCoordinator
    private let settingsStackCoordinator: NavigationStackCoordinator
    private let settingsTabDetails: NavigationTabCoordinator<HomeTab>.TabDetails
    private var settingsTabAvatar: SpiralTabAvatarLoader? // AGENT-PLATFORM
    
    enum State: StateType {
        /// The state machine hasn't started.
        case initial
        /// The root screen for this flow.
        case tabBar
    }
    
    enum Event: EventType {
        /// The flow is being started.
        case start
    }
    
    private let stateMachine: StateMachine<State, Event>
    private var cancellables: Set<AnyCancellable> = []
    
    private let actionsSubject: PassthroughSubject<UserSessionFlowCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<UserSessionFlowCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(isNewLogin: Bool,
         navigationRootCoordinator: NavigationRootCoordinator,
         appLockService: AppLockServiceProtocol,
         flowParameters: CommonFlowParameters) {
        self.navigationRootCoordinator = navigationRootCoordinator
        self.appLockService = appLockService
        self.flowParameters = flowParameters
        presenceService = PresenceService(clientProxy: flowParameters.userSession.clientProxy,
                                          userSettings: flowParameters.userSession.userSettings)
        
        navigationTabCoordinator = NavigationTabCoordinator()
        navigationRootCoordinator.setRootCoordinator(navigationTabCoordinator)
        
        // AGENT-PLATFORM (Brief 0083, question 343): search is Chats' field now, so its coordinator comes first.
        if flowParameters.userSession.userSettings.app.globalSearchEnabled {
            let searchCoordinator = SearchScreenCoordinator(parameters: .init(roomSummaryProvider: flowParameters.userSession.clientProxy.alternateRoomSummaryProvider,
                                                                              userSession: flowParameters.userSession,
                                                                              userIndicatorController: flowParameters.userIndicatorController))
            searchCoordinator.start()
            searchScreenCoordinator = searchCoordinator
        } else {
            searchScreenCoordinator = nil
        }
        
        let chatsSplitCoordinator = NavigationSplitCoordinator(placeholderCoordinator: PlaceholderScreenCoordinator(hideBrandChrome: flowParameters.userSession.userSettings.app.hideBrandChrome))
        chatsTabFlowCoordinator = ChatsTabFlowCoordinator(navigationSplitCoordinator: chatsSplitCoordinator,
                                                          searchContext: searchScreenCoordinator?.context, // AGENT-PLATFORM (Brief 0083, question 343)
                                                          flowParameters: flowParameters)
        chatsTabDetails = .init(tag: HomeTab.chats,
                                title: L10n.screenHomeTabChats,
                                symbol: SpiralTabSymbol.chats, // AGENT-PLATFORM (decision 386): Crest
                                accessibilityIdentifier: A11yIdentifiers.homeTabs.chats)
        
        chatsTabDetails.navigationSplitCoordinator = chatsSplitCoordinator
        
        // AGENT-PLATFORM: feed (Brief 0082)
        let feedSplitCoordinator = NavigationSplitCoordinator(placeholderCoordinator: PlaceholderScreenCoordinator(hideBrandChrome: flowParameters.userSession.userSettings.app.hideBrandChrome))
        feedTabFlowCoordinator = FeedTabFlowCoordinator(navigationSplitCoordinator: feedSplitCoordinator,
                                                        flowParameters: flowParameters)
        feedTabDetails = .init(tag: HomeTab.feed,
                               title: UntranslatedL10n.screenHomeTabFeed,
                               symbol: SpiralTabSymbol.feed, // AGENT-PLATFORM (decision 386): Crest
                               accessibilityIdentifier: A11yIdentifiers.feedScreen.tab)
        feedTabDetails.navigationSplitCoordinator = feedSplitCoordinator
        
        // AGENT-PLATFORM (decision 301): without the flag there is no Spaces tab; spaces open in Chats.
        let spacesTab: NavigationTabCoordinator<HomeTab>.Tab?
        if flowParameters.userSession.userSettings.app.spacesEnabled {
            let spacesSplitCoordinator = NavigationSplitCoordinator(placeholderCoordinator: PlaceholderScreenCoordinator(hideBrandChrome: flowParameters.userSession.userSettings.app.hideBrandChrome))
            spacesTabFlowCoordinator = SpacesTabFlowCoordinator(navigationSplitCoordinator: spacesSplitCoordinator,
                                                                flowParameters: flowParameters)
            let spacesTabDetails = NavigationTabCoordinator<HomeTab>.TabDetails(tag: HomeTab.spaces,
                                                                                title: L10n.screenHomeTabSpaces,
                                                                                icon: \.space,
                                                                                selectedIcon: \.spaceSolid,
                                                                                accessibilityIdentifier: A11yIdentifiers.homeTabs.spaces)
            
            spacesTabDetails.navigationSplitCoordinator = spacesSplitCoordinator
            spacesTab = .init(coordinator: spacesSplitCoordinator, details: spacesTabDetails)
        } else {
            spacesTabFlowCoordinator = nil
            spacesTab = nil
        }
        
        // AGENT-PLATFORM: Agents tab — Brief 0037 rebuild on the
        // Spaces model (Organization = space → Agent = child →
        // Room = deeper). Owns the agent-spaces directory and will
        // host the approvals inbox bell in its nav bar.
        let agentsSplitCoordinator = NavigationSplitCoordinator(placeholderCoordinator: PlaceholderScreenCoordinator(hideBrandChrome: flowParameters.userSession.userSettings.app.hideBrandChrome))
        agentsTabFlowCoordinator = AgentSpacesTabFlowCoordinator(navigationSplitCoordinator: agentsSplitCoordinator,
                                                                 flowParameters: flowParameters)
        agentsTabDetails = .init(tag: HomeTab.agents, title: UntranslatedL10n.screenHomeTabAgents, symbol: SpiralTabSymbol.agents,
                                 accessibilityIdentifier: A11yIdentifiers.homeTabs.agents)
        agentsTabDetails.navigationSplitCoordinator = agentsSplitCoordinator
        
        onboardingStackCoordinator = NavigationStackCoordinator()
        onboardingFlowCoordinator = OnboardingFlowCoordinator(isNewLogin: isNewLogin,
                                                              appLockService: appLockService,
                                                              navigationStackCoordinator: onboardingStackCoordinator,
                                                              flowParameters: flowParameters)
        
        // AGENT-PLATFORM (Brief 0083, question 343): the person's tab, with Settings as its root.
        settingsStackCoordinator = NavigationStackCoordinator()
        settingsFlowCoordinator = SettingsFlowCoordinator(appLockService: appLockService,
                                                          isInSecondaryWindow: false,
                                                          navigationStackCoordinator: settingsStackCoordinator,
                                                          flowParameters: flowParameters)
        settingsTabDetails = .init(tag: HomeTab.settings, title: L10n.commonSettings, icon: \.userProfile, selectedIcon: \.userProfileSolid,
                                   accessibilityIdentifier: A11yIdentifiers.homeScreen.userAvatar)
        
        // AGENT-PLATFORM (decision 301): optional entries, for the Spaces tab.
        let tabEntries: [NavigationTabCoordinator<HomeTab>.Tab?] = [
            .init(coordinator: chatsSplitCoordinator, details: chatsTabDetails),
            .init(coordinator: feedSplitCoordinator, details: feedTabDetails), // AGENT-PLATFORM: feed (Brief 0082)
            spacesTab, // AGENT-PLATFORM (decision 301)
            // AGENT-PLATFORM: third tab for the agents feature.
            .init(coordinator: agentsSplitCoordinator, details: agentsTabDetails),
            .init(coordinator: settingsStackCoordinator, details: settingsTabDetails) // AGENT-PLATFORM (Brief 0083, question 343)
        ]
        
        navigationTabCoordinator.setTabs(tabEntries.compactMap(\.self))
        
        stateMachine = flowParameters.stateMachineFactory.makeUserSessionFlowStateMachine(state: .initial)
        configureStateMachine()
        
        setupObservers()
    }
    
    func start(animated: Bool) {
        stateMachine.tryEvent(.start)
    }
    
    func stop() {
        // Audit W6-6-1: a live call must be torn down BEFORE this flow is
        // deallocated. The overlay's teardown lives in the navigation
        // module's `didSet`, which never fires on deallocation — signing
        // out with a minimized call left the session running with no
        // screen, no Matrix leave, a ghost CallKit call, and a process-
        // wide audio-ownership hold that silenced every later call until
        // relaunch.
        if navigationTabCoordinator.overlayCoordinator != nil {
            MXLog.warning("Stopping the user session with a live call overlay; tearing the call down first")
            navigationTabCoordinator.setOverlayCoordinator(nil)
        }
        flowParameters.callKitService.tearDownCallSession(forRoomID: nil)
        chatsTabFlowCoordinator.stop()
        // AGENT-PLATFORM: platform sync (decisions 154, 289): the session's sync
        // stream must not reconnect with the ended session's token.
        flowParameters.userSession.platformSync?.stop()
        // AGENT-PLATFORM (1.0.3): nor may presence: an ended session's screens can
        // outlive it, and its poll kept refreshing the dead token on every foreground.
        flowParameters.userSession.presenceObserverService?.stop()
        presenceService.stop() // AGENT-PLATFORM (1.0.3): the own presence PUTs too.
        removeSignInCover() // AGENT-PLATFORM (1.0.3): no sign-in's logo outlives its session.
    }
    
    func handleAppRoute(_ appRoute: AppRoute, animated: Bool) {
        MXLog.info("Handling app route: \(appRoute)")
        
        switch appRoute {
        case .oAuthCallback, .inviteLink: // AGENT-PLATFORM: .inviteLink (Brief 0073), no .accountProvisioningLink (Brief 0083 L1b)
            break // We always ignore these flows when logged in.
        case .settings, .chatBackupSettings, .aiConsentSettings: // AGENT-PLATFORM: .aiConsentSettings (decision 150)
            if ProcessInfo.processInfo.isiOSAppOnMac, flowParameters.windowManager.secondaryWindowsEnabled {
                startDetachedSettingsFlow()
            } else {
                // AGENT-PLATFORM (Brief 0083, question 343): the route opens the person's tab, at the screen it names.
                settingsStackCoordinator.popToRoot(animated: false)
                if appRoute != .settings {
                    settingsFlowCoordinator.handleAppRoute(appRoute, animated: animated)
                }
                navigationTabCoordinator.selectedTab = .settings
            }
        case .call(let roomID, let isVoiceCall):
            Task { await presentCallScreen(roomID: roomID, isVoiceCall: isVoiceCall) }
        // AGENT-PLATFORM: route approval-detail + verification-detail
        // deep links into the Agents tab. Listed before the chats
        // catch-all so the explicit cases win.
        case .approvalDetail, .verificationDetail, .publicProfile:
            closeSettingsSheet(animated: animated) // AGENT-PLATFORM (DEBT B10)
            agentsTabFlowCoordinator.handleAppRoute(appRoute, animated: animated)
            if navigationTabCoordinator.selectedTab != .agents {
                navigationTabCoordinator.selectedTab = .agents
            }
        case .feedPost, .feedNotices: // AGENT-PLATFORM: feed (Brief 0082)
            closeSettingsSheet(animated: animated) // AGENT-PLATFORM (DEBT B10)
            feedTabFlowCoordinator.handleAppRoute(appRoute, animated: animated)
            if navigationTabCoordinator.selectedTab != .feed {
                navigationTabCoordinator.selectedTab = .feed
            }
        // AGENT-PLATFORM (Brief 0060): `.userProfile` lands on Element's
        // canonical UserProfileScreen — avatar, display name, MXID and a
        // way to message the person.
        //
        // It used to be promoted to our `.publicProfile` screen whenever
        // the MXID was on a homeserver we provision (v1.7.x chore P4,
        // aimed at memory-recall mentions, where browsing the contact's
        // public agents was the point). That test became universally
        // true once spiral.md became the only homeserver (ADR-0060), so
        // EVERY profile link started landing on a screen that reads
        // "no public agents" for anyone who has none. A shared profile
        // link must show the person. `.publicProfile` stays reachable
        // from the agent surfaces, where public agents are the subject.
        case .userProfile, .roomList, .room, .roomAlias, .childRoom, .childRoomAlias,
             .roomDetails, .roomMemberDetails,
             .event, .eventOnRoomAlias, .childEvent, .childEventOnRoomAlias,
             .share, .transferOwnership, .thread,
             .catalogTemplate: // AGENT-PLATFORM (decision 111): the chat picker is the chats tab's.
            closeSettingsSheet(animated: animated) // AGENT-PLATFORM (DEBT B10)
            chatsTabFlowCoordinator.handleAppRoute(appRoute, animated: animated)
            if navigationTabCoordinator.selectedTab != .chats {
                navigationTabCoordinator.selectedTab = .chats
            }
        case .search:
            // AGENT-PLATFORM (Brief 0083, question 343): search is Chats' field when it's available (flag enabled), otherwise ignore.
            if let searchScreenCoordinator {
                closeSettingsSheet(animated: false) // AGENT-PLATFORM (DEBT B10)
                // AGENT-PLATFORM (Brief 0083): in compact width an open room covers Chats, and the field with it.
                if flowParameters.windowManager.mainWindow.traitCollection.horizontalSizeClass == .compact {
                    clearRoute(animated: false)
                }
                navigationTabCoordinator.selectedTab = .chats
                searchScreenCoordinator.presentSearch()
            }
        }
    }

    func clearRoute(animated: Bool) {
        chatsTabFlowCoordinator.clearRoute(animated: animated)
    }
    
    /// AGENT-PLATFORM (DEBT B10): Settings is a tab now, so a route to another tab closes the sheet over Settings
    /// (Link new device, say) as upstream closed the Settings sheet itself. A sheet a call leaves up stays.
    private func closeSettingsSheet(animated: Bool) {
        guard let sheet = settingsStackCoordinator.sheetCoordinator,
              !NavigationTabCoordinator<HomeTab>.modalRefusesToBeClosedByACall(sheet) else {
            return
        }
        settingsStackCoordinator.setSheetCoordinator(nil, animated: animated)
    }
    
    // MARK: - Invite welcome (AGENT-PLATFORM, Brief 0073)
    
    /// After an invited registration: who invited you, and a way to write to
    /// them. Waits until onboarding has settled (G05: the consent read could
    /// start onboarding after the welcome showed, and its cover replaced it).
    func presentInviteWelcome(inviterUserID: String, onShown: @escaping () -> Void = { }) {
        pendingInviteWelcome = (inviterUserID, onShown)
        showPendingInviteWelcomeIfOnboardingSettled()
    }
    
    /// `replacingCover`: only onboarding's own dismissal hands its cover over; any other cover stays.
    private func showPendingInviteWelcomeIfOnboardingSettled(replacingCover: Bool = false) {
        guard replacingCover || navigationTabCoordinator.fullScreenCoverCoordinator == nil,
              onboardingFlowCoordinator.isSettled,
              let pending = pendingInviteWelcome.take() else {
            return
        }
        showInviteWelcome(inviterUserID: pending.inviterUserID)
        pending.onShown()
    }
    
    private func showInviteWelcome(inviterUserID: String) {
        let coordinator = InviteWelcomeScreenCoordinator(parameters: .init(inviterUserID: inviterUserID,
                                                                           clientProxy: userSession.clientProxy,
                                                                           mediaProvider: userSession.mediaProvider))
        coordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                navigationTabCoordinator.setFullScreenCoverCoordinator(nil)
                switch action {
                case .openDirectChat(let roomID):
                    handleAppRoute(.room(roomID: roomID, via: []), animated: true)
                case .dismiss:
                    break
                }
            }
            .store(in: &cancellables)
        coordinator.start()
        navigationTabCoordinator.setFullScreenCoverCoordinator(coordinator)
    }
    
    func isDisplayingRoomScreen(withRoomID roomID: String) -> Bool {
        guard navigationTabCoordinator.selectedTab == .chats else { return false }
        return chatsTabFlowCoordinator.isDisplayingRoomScreen(withRoomID: roomID)
    }
    
    // MARK: - Private
    
    private func configureStateMachine() {
        stateMachine.addRoutes(event: .start, transitions: [.initial => .tabBar]) { [weak self] _ in
            guard let self else { return }
            
            chatsTabFlowCoordinator.start()
            settingsFlowCoordinator.handleAppRoute(.settings, animated: false) // AGENT-PLATFORM (Brief 0083, question 343)
            spacesTabFlowCoordinator?.start() // AGENT-PLATFORM (decision 301)
            agentsTabFlowCoordinator.start() // AGENT-PLATFORM: bring up Agents tab.
            feedTabFlowCoordinator.start() // AGENT-PLATFORM: feed (Brief 0082)
            // AGENT-PLATFORM: platform sync (decision 289): the session's one stream, for every tab.
            flowParameters.userSession.platformSync?.start()
            attemptStartingOnboarding()
            // AGENT-PLATFORM (1.0.3): nothing to wait for; else a cover that never appears (one doesn't show over a
            // sheet a route opened meanwhile) must not leave the logo over the app.
            if navigationTabCoordinator.fullScreenCoverCoordinator !== onboardingStackCoordinator {
                removeSignInCover()
            } else {
                removeSignInCover(after: signInCoverTimeout)
            }
            // AGENT-PLATFORM (Brief 0078 phase 2): ask about third-party AI once the server says so.
            Task { [weak self] in
                await self?.onboardingFlowCoordinator.refreshAIConsent()
                self?.attemptStartingOnboarding()
                self?.showPendingInviteWelcomeIfOnboardingSettled()
            }
        }
        
        stateMachine.addErrorHandler { context in
            fatalError("Unexpected transition: \(context)")
        }
    }
    
    // AGENT-PLATFORM: the Agents tab and call observers keep this past upstream's cap.
    // swiftlint:disable:next function_body_length
    private func setupObservers() {
        chatsTabFlowCoordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .switchToChatsTab:
                    navigationTabCoordinator.selectedTab = .chats
                case .showChatBackupSettings:
                    handleAppRoute(.chatBackupSettings, animated: true)
                case .sessionVerification(let flow):
                    presentSessionVerificationScreen(flow: flow)
                case .showCallScreen(let roomProxy, let isVoiceCall):
                    presentCallScreen(roomProxy: roomProxy, voiceOnly: isVoiceCall)
                case .showAIConsentSettings: // AGENT-PLATFORM (decision 150)
                    handleAppRoute(.aiConsentSettings, animated: true)
                case .showAgentsTab: // AGENT-PLATFORM (question 412)
                    showAgentsTab()
                case .hideCallScreenOverlay:
                    hideCallScreenOverlay()
                case .logout:
                    Task { await self.runLogoutFlow() }
                }
            }
            .store(in: &cancellables)
        
        spacesTabFlowCoordinator?.actionsPublisher // AGENT-PLATFORM (decision 301)
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .presentCallScreen(let roomProxy, let isVoiceCall):
                    presentCallScreen(roomProxy: roomProxy, voiceOnly: isVoiceCall)
                case .presentAIConsentSettings: // AGENT-PLATFORM (decision 150)
                    handleAppRoute(.aiConsentSettings, animated: true)
                case .presentAgentsTab: // AGENT-PLATFORM (question 412)
                    showAgentsTab()
                case .verifyUser(let userID):
                    presentSessionVerificationScreen(flow: .userInitiator(userID: userID))
                case .showSettings:
                    handleAppRoute(.settings, animated: true) // AGENT-PLATFORM (Brief 0083, question 343)
                }
            }
            .store(in: &cancellables)
        
        // AGENT-PLATFORM: relay actions from the Agents tab (Brief
        // 0037 rebuild). Keeping the subscription in place means the
        // action enum can grow without touching wiring code each time.
        agentsTabFlowCoordinator.actionsPublisher
            .sink { [weak self] action in
                self?.handleAgentsTabAction(action)
            }
            .store(in: &cancellables)
        
        // AGENT-PLATFORM: feed (Brief 0082)
        feedTabFlowCoordinator.actionsPublisher
            .sink { [weak self] action in
                switch action {
                case .openRoom(let roomID):
                    self?.handleAppRoute(.room(roomID: roomID, via: []), animated: true)
                }
            }
            .store(in: &cancellables)
        // AGENT-PLATFORM: feed (Brief 0082, lane I5): unread activity and notices on the tab.
        feedTabFlowCoordinator.badgeCountPublisher
            .weakAssign(to: \.badgeCount, on: feedTabDetails)
            .store(in: &cancellables)

        // AGENT-PLATFORM: platform sync (decision 289): the Agents tab badge is
        // what waits for the owner, held by the session for as long as it
        // lives, so it moves while the person is in Chats too.
        if let agentsStore = userSession.agentsStore {
            agentsStore.show(.needsAction, by: self)
            agentsStore.observe { [weak self] in
                guard let self else { return false }
                updateAgentsBadge()
                return true
            }
        }
        
        userSession.sessionSecurityStatePublisher
            .map(\.verificationState)
            .filter { $0 != .unknown }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                
                attemptStartingOnboarding()
                showPendingInviteWelcomeIfOnboardingSettled()
                setupSessionVerificationRequestsObserver()
            }
            .store(in: &cancellables)
        
        let reachabilityNotificationID = "com.spiral.reachability.notification" // AGENT-PLATFORM (Brief 0083 L1b)
        userSession.clientProxy.homeserverReachabilityPublisher.removeDuplicates()
            .combineLatest(flowParameters.appMediator.networkMonitor.reachabilityPublisher.removeDuplicates())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] homeserverReachability, networkReachability in
                MXLog.info("Homeserver reachability: \(homeserverReachability)")
                
                guard let self else { return }
                switch (networkReachability, homeserverReachability) {
                case (.unreachable, _):
                    flowParameters.userIndicatorController.submitIndicator(.init(id: reachabilityNotificationID,
                                                                                 title: L10n.commonOffline,
                                                                                 persistent: true))
                case (.reachable, .unreachable):
                    flowParameters.userIndicatorController.submitIndicator(.init(id: reachabilityNotificationID,
                                                                                 title: L10n.commonServerUnreachable,
                                                                                 persistent: true))
                // Don't alarm the user while we've intentionally suspended the client.
                case (.reachable, .reachable), (.reachable, .suspended):
                    flowParameters.userIndicatorController.retractIndicatorWithId(reachabilityNotificationID)
                }
            }
            .store(in: &cancellables)
        
        onboardingFlowCoordinator.actions
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .requestPresentation(let animated):
                    // AGENT-PLATFORM (1.0.3): the sign-in's logo stays over the tabs until onboarding covers them.
                    let onCoverPresented: () -> Void = { [weak self] in self?.removeSignInCover(after: 0.3) }
                    navigationTabCoordinator.setFullScreenCoverCoordinator(onboardingStackCoordinator, animated: animated,
                                                                           presentationCallback: onCoverPresented)
                case .dismiss:
                    // Another cover (the in-app incoming call) may have taken onboarding's
                    // place: it stays, and the welcome waits for it to go.
                    guard navigationTabCoordinator.fullScreenCoverCoordinator === onboardingStackCoordinator else {
                        // No cover at all (a ring took onboarding's place and has gone): the welcome can show.
                        showPendingInviteWelcomeIfOnboardingSettled()
                        break
                    }
                    // The welcome, when it waited for onboarding, takes the cover's place.
                    if pendingInviteWelcome != nil, onboardingFlowCoordinator.isSettled {
                        showPendingInviteWelcomeIfOnboardingSettled(replacingCover: true)
                    } else {
                        navigationTabCoordinator.setFullScreenCoverCoordinator(nil)
                    }
                case .logoutConfirmed:
                    actionsSubject.send(.logout)
                }
            }
            .store(in: &cancellables)
        
        flowParameters.callKitService.actions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                switch action {
                case .endCall:
                    // AGENT-PLATFORM (Brief 0067): the call screen's own view
                    // model ends the call and dismisses; upstream's WebView
                    // dismissal here is gone with the widget (ADR-0079).
                    break
                case .startInAppRinging(let roomID, let callerDisplayName, let callerAvatarData, let isVoiceCall, let rtcNotificationID):
                    // AGENT-PLATFORM (Brief 0063, G15): the CallKit-
                    // unavailable fallback ring.
                    self?.presentInAppIncomingScreen(roomID: roomID,
                                                     callerDisplayName: callerDisplayName,
                                                     callerAvatarData: callerAvatarData,
                                                     isVoiceCall: isVoiceCall,
                                                     rtcNotificationID: rtcNotificationID)
                case .stopInAppRinging(let roomID):
                    self?.dismissInAppIncomingScreen(roomID: roomID)
                case .activeCallChanged(let roomID):
                    // Brief 0068 Slice 2 — call waiting: the parked call is
                    // the active one now; its screen comes forward and the
                    // other one waits behind it.
                    self?.bringHeldCallForward(roomID: roomID)
                default:
                    break
                }
            }
            .store(in: &cancellables)
        setupUnreadNotificationsObserver()
        
        searchScreenCoordinator?.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .presentRoom(let roomID, let eventID):
                    if let eventID {
                        handleAppRoute(.event(eventID: eventID, roomID: roomID, via: []), animated: true)
                    } else {
                        handleAppRoute(.room(roomID: roomID, via: []), animated: true)
                    }
                }
            }
            .store(in: &cancellables)
        
        observeSettingsFlow(settingsFlowCoordinator) // AGENT-PLATFORM (Brief 0083, question 343)
        setupSettingsTabAvatar() // AGENT-PLATFORM (Brief 0083, question 343)
    }

    private func handleAgentsTabAction(_ action: AgentSpacesTabFlowCoordinatorAction) {
        switch action {
        case .openDMWithAgent(let matrixUserID):
            // 'Contact agent' hand-off (Brief 0038 I5): open the existing
            // DM, or create one; either way land in the Chats tab room.
            Task { await openDMWithAgent(matrixUserID: matrixUserID) }
        case .openRoom(let roomID):
            handleAppRoute(.room(roomID: roomID, via: []), animated: true)
        case .presentCallScreen(let roomProxy, let isVoiceCall):
            presentCallScreen(roomProxy: roomProxy, voiceOnly: isVoiceCall)
        case .presentAIConsentSettings: // AGENT-PLATFORM (decision 150)
            handleAppRoute(.aiConsentSettings, animated: true)
        case .presentAgentsTab: // AGENT-PLATFORM (question 412)
            showAgentsTab()
        case .verifyUser(let userID):
            presentSessionVerificationScreen(flow: .userInitiator(userID: userID))
        }
    }

    /// AGENT-PLATFORM (question 412): the Agents tab at its list, where the person's agent is or is being set up —
    /// what «Create an agent» on a post the agent fills in leads to.
    private func showAgentsTab() {
        agentsTabFlowCoordinator.clearRoute(animated: false)
        navigationTabCoordinator.selectedTab = .agents
    }

    /// 'Contact agent' from the public profile: open (or create) the DM
    /// with the agent and route into it on the Chats tab.
    private func openDMWithAgent(matrixUserID: String) async {
        switch userSession.clientProxy.directRoomForUserID(matrixUserID) {
        case .success(.some(let roomID)):
            handleAppRoute(.room(roomID: roomID, via: []), animated: true)
        case .success(.none):
            switch await userSession.clientProxy.createDirectRoom(with: matrixUserID, expectedRoomName: nil) {
            case .success(let roomID):
                handleAppRoute(.room(roomID: roomID, via: []), animated: true)
            case .failure(let error):
                MXLog.error("Failed to create agent DM: \(error)")
            }
        case .failure(let error):
            MXLog.error("Failed to resolve agent DM: \(error)")
        }
    }
    
    /// AGENT-PLATFORM: what waits for the owner, as the store last read it.
    private func updateAgentsBadge() {
        let count = userSession.agentsStore?.needsAction?.count ?? 0
        if agentsTabDetails.badgeCount != count {
            agentsTabDetails.badgeCount = count
        }
    }
    
    // MARK: - Onboarding
    
    // AGENT-PLATFORM (1.0.3, operator 2026-11-23): the logo the sign-in left over the root (`AuthenticationFlowCoordinator`
    // sets it while the OAuth callback is exchanged) hid the tabs, which showed for a moment before onboarding's cover.
    // The cover's `onAppear` can come a frame or two before it is drawn, so the logo under it goes a moment later.
    // Each delayed removal takes only the cover it was scheduled for.
    private func removeSignInCover(after delay: TimeInterval? = nil) {
        guard let cover = navigationRootCoordinator.coverCoordinator else { return }
        guard let delay else {
            navigationRootCoordinator.setCoverCoordinator(nil)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, navigationRootCoordinator.coverCoordinator === cover else { return }
            navigationRootCoordinator.setCoverCoordinator(nil)
        }
    }
    
    private func attemptStartingOnboarding() {
        MXLog.info("Attempting to start onboarding")
        
        if onboardingFlowCoordinator.shouldStart {
            clearRoute(animated: false)
            onboardingFlowCoordinator.start()
        }
    }
    
    // MARK: - Settings
    
    // AGENT-PLATFORM (Brief 0083, question 343): only the Mac's own window builds a flow on demand; the tab's lives with the session.
    private func startDetachedSettingsFlow() {
        let navigationStackCoordinator = NavigationStackCoordinator()
        let coordinator = SettingsFlowCoordinator(appLockService: appLockService,
                                                  isInSecondaryWindow: true,
                                                  navigationStackCoordinator: navigationStackCoordinator,
                                                  flowParameters: flowParameters)
        observeSettingsFlow(coordinator)
        coordinator.handleAppRoute(.settings, animated: false)
        flowParameters.windowManager.registerCoordinator(navigationStackCoordinator,
                                                         flowCoordinator: coordinator,
                                                         forWindowType: .settings)
    }
    
    private func observeSettingsFlow(_ coordinator: SettingsFlowCoordinator) {
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .openUserProfile(let userID): // AGENT-PLATFORM (Brief 0073).
                handleAppRoute(.userProfile(userID: userID), animated: true)
            case .clearCache:
                actionsSubject.send(.clearCache)
            case .runLogoutFlow:
                Task { await self.runLogoutFlow() }
            case .forceLogout:
                actionsSubject.send(.forceLogout)
            }
        }
        .store(in: &cancellables)
    }
    
    // AGENT-PLATFORM (Brief 0083, question 343): the person's tab draws their avatar: the monogram at once, then the photo.
    private func setupSettingsTabAvatar() {
        let mediaProvider = flowParameters.userSession.mediaProvider
        let settingsTabAvatar = SpiralTabAvatarLoader { url in
            guard let source = try? MediaSourceProxy(url: url, mimeType: "image/jpeg") else { return nil }
            return try? await mediaProvider.loadImageRetryingOnReconnection(source, size: Avatars.Size.user(on: .chats).scaledSize).value
        } onChange: { [weak self] avatar in
            self?.settingsTabDetails.avatar = avatar
        }
        self.settingsTabAvatar = settingsTabAvatar
        flowParameters.userSession.clientProxy.userProfilePublisher
            .receive(on: DispatchQueue.main)
            .sink { profile in
                settingsTabAvatar.update(name: profile.displayName, contentID: profile.id, photoURL: profile.avatarURL)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Session Verification
    
    private func setupSessionVerificationRequestsObserver() {
        userSession.clientProxy.sessionVerificationController?.actions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                guard let self, case .receivedVerificationRequest(let details) = action else {
                    return
                }
                
                MXLog.info("Received session verification request")
                
                if details.senderProfile.id == userSession.clientProxy.userID {
                    presentSessionVerificationScreen(flow: .deviceResponder(requestDetails: details))
                } else {
                    presentSessionVerificationScreen(flow: .userResponder(requestDetails: details))
                }
            }
            .store(in: &cancellables)
    }
    
    private func presentSessionVerificationScreen(flow: SessionVerificationScreenFlow) {
        guard let sessionVerificationController = userSession.clientProxy.sessionVerificationController else {
            fatalError("The sessionVerificationController should aways be valid at this point")
        }
        
        let navigationStackCoordinator = NavigationStackCoordinator()
        
        let parameters = SessionVerificationScreenCoordinatorParameters(sessionVerificationControllerProxy: sessionVerificationController,
                                                                        flow: flow,
                                                                        userSession: userSession)
        
        let coordinator = SessionVerificationScreenCoordinator(parameters: parameters)
        
        coordinator.actions
            .sink { [weak self] action in
                switch action {
                case .done:
                    self?.navigationTabCoordinator.setSheetCoordinator(nil)
                }
            }
            .store(in: &cancellables)
        
        navigationStackCoordinator.setRootCoordinator(coordinator)
        
        navigationTabCoordinator.setSheetCoordinator(navigationStackCoordinator)
    }
    
    // MARK: - Calls
    
    private func presentCallScreen(roomID: String, isVoiceCall: Bool, isAnsweringInAppRing: Bool = false) async {
        // AGENT-PLATFORM (Brief 0067, call audit 2026-09-05): an ANSWERED
        // call arrives here with CallKit already holding it as ongoing. The
        // room lookup below suspends, and the user can End from the system
        // UI in that window — `endCall(matching:)` tears the CallKit session
        // down and emits `.endCall`, which nobody handles because no view
        // model exists yet. The lookup then resumed and started a session
        // that knew nothing of the end: a fresh CallKit call, a MatrixRTC
        // join and a published microphone for a call the user had refused.
        // The ongoing-room value is the call's generation: captured before
        // the await, re-checked after it.
        let wasAnsweredCall = flowParameters.callKitService.ongoingCallRoomIDPublisher.value == roomID
        
        guard case let .joined(roomProxy) = await userSession.clientProxy.roomForIdentifier(roomID) else {
            // Audit W6-6-2: this leg can run AFTER a CXAnswerCallAction was
            // fulfilled — the activation-audio claim is held and CallKit
            // shows a live call. Silently returning left both standing for
            // a call that will never exist; the user stared at a lying
            // system UI until they ended it by hand.
            MXLog.error("Cannot present a call for \(roomID): the room is not joined; tearing the CallKit session down")
            flowParameters.callKitService.tearDownCallSession(forRoomID: roomID)
            return
        }
        
        // AGENT-PLATFORM: the scope reads the members this fresh proxy is
        // still loading; the check below covers an end during the wait too.
        await NativeCallConfiguration.awaitFirstMembers(of: roomProxy)
        
        if wasAnsweredCall, flowParameters.callKitService.ongoingCallRoomIDPublisher.value != roomID {
            MXLog.info("The answered call in \(roomID) was ended while its room was being looked up; not presenting it")
            return
        }
        
        // Follow-up L1: the in-app ring is not CallKit's ongoing call until
        // its screen registers, so the check above never saw it end — its
        // generation is the ring itself.
        if isAnsweringInAppRing, !flowParameters.callKitService.isAcceptedRingLive(forRoomID: roomID) {
            MXLog.info("The accepted ring in \(roomID) ended while its room was being looked up; not presenting it")
            // The call parked for it at the tap comes back — unless the
            // room's call went live another way (a redial answered from
            // CallKit), which that route presents; a teardown by room
            // would end it.
            if flowParameters.callKitService.ongoingCallRoomIDPublisher.value != roomID {
                flowParameters.callKitService.tearDownCallSession(forRoomID: roomID)
            }
            return
        }
        
        presentCallScreen(roomProxy: roomProxy, voiceOnly: isVoiceCall, isAnswer: wasAnsweredCall || isAnsweringInAppRing)
    }
    
    private func setupUnreadNotificationsObserver() {
        userSession.notificationService.badgeCountPublisher
            .removeDuplicates()
            .weakAssign(to: \.badgeCount, on: chatsTabDetails)
            .store(in: &cancellables)
    }
    
    private func presentCallScreen(roomProxy: JoinedRoomProxyProtocol, voiceOnly: Bool, isAnswer: Bool = false) {
        // AGENT-PLATFORM (Brief 0063/0067): every room is a native call
        // (ADR-0079 D3); the room's shape only decides scope and whether a
        // fresh call rings or merely notifies.
        let roomInfo = roomProxy.infoPublisher.value
        let media: NativeCallMedia = voiceOnly ? .audio : .video
        let members = roomProxy.membersPublisher.value
        let configuration = NativeCallConfiguration(media: media, roomInfo: roomInfo, members: members, ownUserID: roomProxy.ownUserID)
        MXLog.info("Routing call in \(roomProxy.id): media \(media), scope \(configuration.scope), notification \(String(describing: configuration.freshCallNotification)), hasRoomCall \(roomInfo.hasRoomCall)")
        // AGENT-PLATFORM: what the scope read, so a `.direct` mis-route can be
        // told apart in the log (no members loaded, no heroes in a named room).
        MXLog.info("""
        Routing topology in \(roomProxy.id): isDM \(roomInfo.isDM), isDirect \(roomInfo.isDirect), \
        active \(roomInfo.activeMembersCount), joined \(roomInfo.joinedMembersCount), \
        activeService \(roomInfo.activeServiceMembersCount), serviceMembers \(roomInfo.serviceMembers), \
        members \(members.count), heroes \(roomInfo.heroes.count), hasRawName \(roomInfo.rawName != nil)
        """)
        
        presentNativeCallScreen(roomProxy: roomProxy, configuration: configuration, isAnswer: isAnswer)
    }
    
    // AGENT-PLATFORM (Brief 0063)
    private func presentNativeCallScreen(roomProxy: JoinedRoomProxyProtocol, configuration: NativeCallConfiguration, isAnswer: Bool) {
        // Keyed on the OVERLAY's room, not on `ongoingCallRoomID` (audit C6):
        // the published id only appears at `.ringing`/`.connected`, so during
        // the connect window a re-tap (or a double-tapped Accept) used to
        // pass the old guard, replace the overlay, and race the first
        // session's `leave()` against the second's `join()` on the same
        // device membership — the leave could delete the fresh membership.
        if returnedToExistingCallScreen(for: roomProxy.id, isAnswer: isAnswer) {
            return
        }
        // Read after an ended screen came down: its call is ending by then.
        let isOngoingCall = flowParameters.ongoingCallRoomIDPublisher.value == roomProxy.id
        // Brief 0068 Slice 2: the room whose call is parked behind the active
        // one — a tap on it is a swap, through CallKit, not a second join.
        if let held = heldCallCoordinator, held.callRoomID == roomProxy.id {
            MXLog.info("Swapping to the held call in \(roomProxy.id).")
            flowParameters.callKitService.swapCalls()
            return
        }
        
        // Ring only when starting a fresh call: answering our own CallKit ring
        // or joining a call that is already active in the room must not ring
        // the other members again. An answer never rings, even when the room
        // does not show the call (yet, or any more) — follow-up L1.
        let notifyRoom = !isAnswer && !isOngoingCall && !roomProxy.infoPublisher.value.hasRoomCall
        let coordinator = NativeCallScreenCoordinator(parameters: .init(roomProxy: roomProxy,
                                                                        callKitService: flowParameters.callKitService,
                                                                        agentPlatformService: flowParameters.userSession.agentPlatformService,
                                                                        agentsStore: flowParameters.userSession.agentsStore, // AGENT-PLATFORM: S5
                                                                        isRoomEncrypted: roomProxy.infoPublisher.value.isEncrypted,
                                                                        notifyRoom: notifyRoom,
                                                                        isAnswer: isAnswer,
                                                                        configuration: configuration,
                                                                        appMediator: flowParameters.appMediator,
                                                                        mediaProvider: flowParameters.userSession.mediaProvider))
        
        coordinator.actions
            .sink { [weak self, weak coordinator] action in
                guard let self, let coordinator else { return }
                // Brief 0068 Slice 2: two call screens can be alive; only the
                // one on screen may drive the overlay.
                let isOnScreen = navigationTabCoordinator.overlayCoordinator === coordinator
                switch action {
                case .dismiss:
                    if isOnScreen {
                        dismissCallScreenOnScreen(coordinator)
                    } else if heldCallCoordinator === coordinator {
                        // The parked call ended (from the system UI, or a
                        // third call displaced it): its screen was never on
                        // screen to be torn down, so stop it here.
                        heldCallCoordinator = nil
                        coordinator.isParked = false
                        coordinator.stop()
                    }
                case .minimize:
                    // G13 — back to the chat with the call running; the
                    // coordinator (and the call it owns) stays alive and
                    // renders the bar.
                    guard isOnScreen else { return }
                    navigationTabCoordinator.setOverlayPresentationMode(.minimized)
                case .expand:
                    // Covers the bar tap AND the window's restore button —
                    // either way the full screen returns, so the window goes
                    // (a no-op for the restore path, where AVKit is already
                    // stopping it).
                    guard isOnScreen else { return }
                    coordinator.stopPictureInPictureForFullScreenReturn()
                    dismissModalsCoveringTheCallScreen() // AGENT-PLATFORM (1.0.2): the PiP restore can come under a sheet
                    navigationTabCoordinator.setOverlayPresentationMode(.fullScreen)
                case .pictureInPictureStarted:
                    // The picture lives in the floating window now; the
                    // overlay steps aside so the app underneath is usable.
                    guard isOnScreen else { return }
                    navigationTabCoordinator.setOverlayPresentationMode(.minimized)
                // AGENT-PLATFORM (Brief 0083, question 401): the assistant's "…" menu in the call opens its profile
                // with the call on its bar, as the bar's own way back to the chat does.
                case .showProfile(let userID):
                    guard isOnScreen else { return }
                    navigationTabCoordinator.setOverlayPresentationMode(.minimized)
                    handleAppRoute(.userProfile(userID: userID), animated: true)
                }
            }
            .store(in: &cancellables)
        
        // Brief 0068 Slice 2: an answered second call HOLDS the first — the
        // service parks it synchronously with the answer (both the CallKit
        // banner and the in-app ring), so the held slot names the screen on
        // screen right now. It stays alive behind the new one: `isParked`
        // is what keeps the tab coordinator's teardown of the replaced
        // overlay from stopping the call. An outgoing call while one is
        // live still replaces it; CallKit ends the old one once the new
        // call reaches `setupCallSession`.
        if let current = navigationTabCoordinator.overlayCoordinator as? NativeCallScreenCoordinator,
           flowParameters.callKitService.heldCallPublisher.value?.roomID == current.callRoomID {
            MXLog.info("Parking the call screen for \(current.callRoomID) behind \(roomProxy.id).")
            current.isParked = true
            heldCallCoordinator = current
        }
        dismissModalsCoveringTheCallScreen() // AGENT-PLATFORM (1.0.2)
        navigationTabCoordinator.setOverlayCoordinator(coordinator, animated: true)
        
        flowParameters.analytics.track(screen: .RoomCall)
    }
    
    /// AGENT-PLATFORM (1.0.2, DEBT "a call under the sheet"): the call screen is the tab view's overlay, drawn
    /// under every sheet and cover: answered with Settings open, the call ran with its controls hidden until the
    /// sheet was swiped away. As the screen comes up, the viewers over the app and the modals their owners let go
    /// close — the call wins (the operator, 2026-11-14).
    private func dismissModalsCoveringTheCallScreen(animated: Bool = true) {
        NotificationCenter.default.post(name: .callScreenWillCoverTheApp, object: nil)
        navigationTabCoordinator.dismissModalsCoveringTheOverlay(sparing: callSpares, animated: animated)
    }
    
    /// What a call leaves above its screen (Fable review of 93d0663ef). A sheet goes unless it shows a screen its
    /// person can't swipe away either (``HoldsItsModalAboveACall``). A cover can't be swiped away at all, so its owner may not handle losing it:
    /// only the room directory's does. Onboarding and the invite welcome stay (their flows stall or lose the
    /// welcome when torn down), and so does the in-app ring, above an ongoing call on purpose (G15).
    private func callSpares(_ coordinator: any CoordinatorProtocol, as modal: NavigationTabCoordinator<HomeTab>.OverlayCoveringModal) -> Bool {
        switch modal {
        case .sheet:
            NavigationTabCoordinator<HomeTab>.modalRefusesToBeClosedByACall(coordinator)
        case .fullScreenCover:
            !(coordinator is RoomDirectorySearchScreenCoordinator)
        }
    }
    
    /// The call screen on screen goes. The parked call comes forward the
    /// moment the active one goes. Its promotion (and the CallKit resume) is
    /// asked for NOW, scoped to the ending call — the ending screen's own
    /// teardown lands seconds later, after its session has stopped, and until
    /// then the parked screen would sit "On hold" with no control.
    private func dismissCallScreenOnScreen(_ coordinator: NativeCallScreenCoordinator) {
        navigationTabCoordinator.setOverlayCoordinator(nil)
        guard let held = heldCallCoordinator else {
            showPendingInviteWelcomeIfOnboardingSettled() // AGENT-PLATFORM (Brief 0073): it waited for the call
            return
        }
        flowParameters.callKitService.tearDownCallSession(forRoomID: coordinator.callRoomID, callKitID: coordinator.callKitID)
        // Still parked after that, it waits for a newer in-app accept, which
        // gave this screen up: that answer's screen comes next, or the
        // service brings this one back (`.activeCallChanged`).
        guard flowParameters.callKitService.heldCallPublisher.value?.roomID != held.callRoomID else {
            MXLog.info("The parked call in \(held.callRoomID) stays parked for a newer accept.")
            return
        }
        heldCallCoordinator = nil
        presentParkedCallScreen(held)
    }
    
    /// The call screen on screen, for a route to `roomID`: its room's live
    /// one is returned to, and one that shows its call's end comes down
    /// first. Returns whether it returned.
    private func returnedToExistingCallScreen(for roomID: String, isAnswer: Bool) -> Bool {
        guard let existing = navigationTabCoordinator.overlayCoordinator as? NativeCallScreenCoordinator else { return false }
        if existing.callRoomID == roomID {
            return returnedToCallScreen(existing, isAnswer: isAnswer)
        }
        // Another room's call goes the same way. A route to the parked room
        // is a swap, which needs the ended call there to hold.
        if existing.hasCallEnded, heldCallCoordinator?.callRoomID != roomID {
            replaceEndedCallScreen(existing)
        }
        return false
    }

    /// Returns to the room's screen, unless it shows its call's end ("Call
    /// ended", a failure): that one comes down first, its call over, so the
    /// fresh screen that replaces it does not take that call. Returns whether
    /// it returned.
    private func returnedToCallScreen(_ existing: NativeCallScreenCoordinator, isAnswer: Bool) -> Bool {
        guard !existing.hasCallEnded else {
            replaceEndedCallScreen(existing)
            return false
        }
        returnToCallScreen(existing, isAnswer: isAnswer)
        return true
    }

    /// A screen that shows its call's end, about to be replaced. Like its
    /// dismissal, its call goes now, scoped to it: its own teardown lands
    /// later and brought the parked call back over the fresh screen (M1
    /// review; for another room's route, follow-ups 3). Unlike its dismissal,
    /// the parked screen stays parked: the fresh screen's registration
    /// settles it, an answer keeping it behind, an outgoing call replacing it.
    private func replaceEndedCallScreen(_ existing: NativeCallScreenCoordinator) {
        MXLog.info("Replacing the ended call screen for \(existing.callRoomID).")
        navigationTabCoordinator.setOverlayCoordinator(nil)
        flowParameters.callKitService.tearDownReplacedCallSession(forRoomID: existing.callRoomID, callKitID: existing.callKitID)
    }

    private func returnToCallScreen(_ existing: NativeCallScreenCoordinator, isAnswer: Bool) {
        MXLog.info("Returning to existing native call.")
        // An answer landing here is this screen's call now, so its teardown
        // ends it: a call the screen started and never registered has none
        // of its own, and an in-app ring accepted here outlived the screen and
        // was later adopted by a call CallKit never had (N1 review).
        if isAnswer, let callKitID = flowParameters.callKitService.callKitID(forRoomID: existing.callRoomID) {
            existing.bind(toCallKitID: callKitID)
        }
        // The full screen is coming back by a route that is not the PiP
        // window's restore button — the window must come down or the
        // same call shows twice.
        existing.stopPictureInPictureForFullScreenReturn()
        dismissModalsCoveringTheCallScreen() // AGENT-PLATFORM (1.0.2)
        // G9 — the call may be living behind its bar; returning to it
        // restores the full screen.
        navigationTabCoordinator.setOverlayPresentationMode(.fullScreen)
    }
    
    // AGENT-PLATFORM (Brief 0068 Slice 2): the second call's screen, parked.
    private var heldCallCoordinator: NativeCallScreenCoordinator?
    
    /// Put a parked screen back on screen. `start()` is latched inside the
    /// coordinator, so re-presenting does not re-join the call.
    private func presentParkedCallScreen(_ coordinator: NativeCallScreenCoordinator) {
        coordinator.isParked = false
        dismissModalsCoveringTheCallScreen() // AGENT-PLATFORM (1.0.2)
        navigationTabCoordinator.setOverlayCoordinator(coordinator, animated: true)
    }
    
    private func bringHeldCallForward(roomID: String) {
        if let onScreen = navigationTabCoordinator.overlayCoordinator as? NativeCallScreenCoordinator,
           onScreen.callRoomID == roomID {
            return
        }
        guard let held = heldCallCoordinator, held.callRoomID == roomID else {
            MXLog.warning("No parked call screen for \(roomID) to bring forward.")
            return
        }
        if let current = navigationTabCoordinator.overlayCoordinator as? NativeCallScreenCoordinator {
            current.isParked = true
            heldCallCoordinator = current
        } else {
            heldCallCoordinator = nil
        }
        presentParkedCallScreen(held)
    }
    
    // AGENT-PLATFORM (Brief 0063, G15): the in-app incoming screen — the
    // fallback for the rings CallKit cannot present. Same accept/decline
    // semantics; presented as a full-screen cover so it never competes with
    // an ongoing overlay call.
    private var inAppIncomingRoomID: String?
    /// Drives the in-app ring's haptic pulse (audit T4).
    private var inAppRingingHaptic: Task<Void, Never>?

    private func presentInAppIncomingScreen(roomID: String,
                                            callerDisplayName: String,
                                            callerAvatarData: Data?,
                                            isVoiceCall: Bool,
                                            rtcNotificationID: String?) {
        guard inAppIncomingRoomID == nil else { return }
        inAppIncomingRoomID = roomID
        startInAppRingingHaptic()

        let coordinator = NativeCallIncomingScreenCoordinator(parameters: .init(callerDisplayName: callerDisplayName,
                                                                                callerAvatarData: callerAvatarData,
                                                                                isVoiceCall: isVoiceCall,
                                                                                agentPreflightText: nil))
        // One decision per ring (audit C6). The buttons stay tappable for the
        // dismissal transition's duration, so without the latch a double-tap
        // Accept raced two `presentCallScreen`s, and Accept-then-Decline sent
        // an MSC4310 decline for a call the user had just answered — the
        // caller saw "declined" while the callee was joining.
        var decisionMade = false
        coordinator.actions
            .sink { [weak self] action in
                guard let self else { return }
                guard !decisionMade else {
                    MXLog.info("Ignoring a second decision for the in-app ring: \(action)")
                    return
                }
                decisionMade = true
                // An answer's call screen comes next; the welcome waits for it to end.
                let isAnswer = if case .accept = action { true } else { false }
                dismissInAppIncomingScreen(roomID: roomID, showsWaitingWelcome: !isAnswer)
                switch action {
                case .accept:
                    // Synchronous with the tap — the seconds until
                    // `setupCallSession` must not race the missed-call timer.
                    flowParameters.callKitService.handleInAppRingDecision(roomID: roomID, accepted: true)
                    Task { await self.presentCallScreen(roomID: roomID, isVoiceCall: isVoiceCall, isAnsweringInAppRing: true) }
                case .decline:
                    flowParameters.callKitService.handleInAppRingDecision(roomID: roomID, accepted: false)
                    guard let rtcNotificationID else { return }
                    Task {
                        // MSC4310 — the caller sees an explicit refusal, the
                        // same signal the CallKit decline path sends.
                        guard case let .joined(roomProxy) = await self.userSession.clientProxy.roomForIdentifier(roomID) else { return }
                        _ = await roomProxy.declineCall(notificationID: rtcNotificationID)
                    }
                }
            }
            .store(in: &cancellables)

        // AGENT-PLATFORM (1.0.2, DEBT "a call under the sheet"): a cover can't present over the tab view while
        // a sheet is up there or in a tab, so the ring never showed. What a call may close closes at once,
        // unanimated, so the cover presents in this same pass; a cover already up is replaced below, as before.
        dismissModalsCoveringTheCallScreen(animated: false)
        navigationTabCoordinator.setFullScreenCoverCoordinator(coordinator)
    }

    private func dismissInAppIncomingScreen(roomID: String, showsWaitingWelcome: Bool = true) {
        guard inAppIncomingRoomID == roomID else { return }
        inAppIncomingRoomID = nil
        inAppRingingHaptic?.cancel()
        inAppRingingHaptic = nil
        if navigationTabCoordinator.fullScreenCoverCoordinator is NativeCallIncomingScreenCoordinator {
            navigationTabCoordinator.setFullScreenCoverCoordinator(nil)
            if showsWaitingWelcome {
                showPendingInviteWelcomeIfOnboardingSettled() // AGENT-PLATFORM (Brief 0073): it waited for the ring
            }
        }
    }

    /// Pulse while the in-app incoming screen is up (audit T4).
    ///
    /// A haptic and NOT a ring tone, deliberately. This screen has exactly
    /// one trigger: CallKit refused to report the call. The most common
    /// reason for that refusal is Do Not Disturb or a Focus mode — and we
    /// cannot tell that case apart from a provider misconfiguration or a
    /// region where CallKit is unavailable. Playing audio into a phone whose
    /// owner has explicitly asked for silence would be worse than the
    /// silence this fixes, and a tone would also need an audio session
    /// nobody has activated here: the tone player's own rule is that a tone
    /// may only start on a session the system has already brought up, and
    /// the CallKit-refused path is precisely the one where it has not.
    ///
    /// A haptic needs no session, respects the ring/silent switch by nature,
    /// and is noticeable in the pocket, which is the actual complaint: this
    /// screen used to appear with no cue of any kind.
    private func startInAppRingingHaptic() {
        inAppRingingHaptic?.cancel()
        inAppRingingHaptic = Task { @MainActor in
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            // Roughly the ETSI ring cadence the tone player uses for
            // ringback: a pulse, then a long gap, so it reads as a call
            // rather than a notification.
            while !Task.isCancelled {
                generator.impactOccurred()
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                generator.impactOccurred()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // AGENT-PLATFORM (Brief 0063/0067): the call keeps its own PiP session;
    // for an AUDIO call `startPictureInPicture()` is a no-op by design and
    // minimizing to the bar is the whole answer. Upstream's WebView branch
    // (`callScreenPictureInPictureController` / `dismissCallScreenIfNeeded`)
    // is gone with the widget (ADR-0079).
    private func hideCallScreenOverlay() {
        guard let nativeCallCoordinator = navigationTabCoordinator.overlayCoordinator as? NativeCallScreenCoordinator else {
            return
        }
        MXLog.info("Hiding the call overlay behind picture in picture / the call bar.")
        nativeCallCoordinator.startPictureInPicture()
        navigationTabCoordinator.setOverlayPresentationMode(.minimized)
    }
    
    // MARK: - Logout
    
    // AGENT-PLATFORM (decision 187): internal for tests; the confirmations say
    // «Sign out», not upstream's «Remove this device».
    func runLogoutFlow() async {
        let secureBackupController = userSession.clientProxy.secureBackupController
        
        guard case let .success(isLastDevice) = await userSession.clientProxy.isOnlyDeviceLeft() else {
            navigationRootCoordinator.alertInfo = .init(id: .init())
            return
        }
        
        guard isLastDevice else {
            navigationRootCoordinator.alertInfo = .init(id: .init(),
                                                        title: UntranslatedL10n.screenSignoutConfirmationDialogTitleSpiral,
                                                        message: UntranslatedL10n.screenSignoutConfirmationDialogContentSpiral,
                                                        primaryButton: .init(title: UntranslatedL10n.screenSignoutConfirmationDialogSubmitSpiral, role: .destructive) { [weak self] in
                                                            self?.actionsSubject.send(.logout)
                                                        })
            return
        }
        
        guard secureBackupController.recoveryState.value == .enabled else {
            navigationRootCoordinator.alertInfo = .init(id: .init(),
                                                        title: L10n.screenSignoutRecoveryDisabledTitle,
                                                        message: L10n.screenSignoutRecoveryDisabledSubtitle,
                                                        primaryButton: .init(title: UntranslatedL10n.screenSignoutConfirmationDialogSubmitSpiral, role: .destructive) { [weak self] in // AGENT-PLATFORM (decision 187)
                                                            self?.actionsSubject.send(.logout)
                                                        }, secondaryButton: .init(title: L10n.commonSettings, role: .cancel) { [weak self] in
                                                            self?.chatsTabFlowCoordinator.handleAppRoute(.chatBackupSettings, animated: true)
                                                        })
            return
        }
        
        guard secureBackupController.keyBackupState.value == .enabled else {
            navigationRootCoordinator.alertInfo = .init(id: .init(),
                                                        title: L10n.screenSignoutKeyBackupDisabledTitle,
                                                        message: L10n.screenSignoutKeyBackupDisabledSubtitle,
                                                        primaryButton: .init(title: UntranslatedL10n.screenSignoutConfirmationDialogSubmitSpiral, role: .destructive) { [weak self] in // AGENT-PLATFORM (decision 187)
                                                            self?.actionsSubject.send(.logout)
                                                        }, secondaryButton: .init(title: L10n.commonSettings, role: .cancel) { [weak self] in
                                                            self?.chatsTabFlowCoordinator.handleAppRoute(.chatBackupSettings, animated: true)
                                                        })
            return
        }
        
        presentSecureBackupLogoutConfirmationScreen()
    }
    
    private func presentSecureBackupLogoutConfirmationScreen() {
        let coordinator = SecureBackupLogoutConfirmationScreenCoordinator(parameters: .init(secureBackupController: userSession.clientProxy.secureBackupController,
                                                                                            homeserverReachabilityPublisher: userSession.clientProxy.homeserverReachabilityPublisher))
        
        coordinator.actions
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .cancel:
                    navigationTabCoordinator.setSheetCoordinator(nil)
                case .settings:
                    chatsTabFlowCoordinator.handleAppRoute(.chatBackupSettings, animated: true)
                    navigationTabCoordinator.setSheetCoordinator(nil)
                case .logout:
                    actionsSubject.send(.logout)
                }
            }
            .store(in: &cancellables)
        
        navigationTabCoordinator.setSheetCoordinator(coordinator, animated: true)
    }
}

// AGENT-PLATFORM (1.0.2, DEBT "a call under the sheet"): the viewers presented over the app, outside the
// coordinators (the media viewer, a post played full screen), close on this as a call screen or the in-app ring
// comes up.
extension Notification.Name {
    static let callScreenWillCoverTheApp = Notification.Name("SpiralCallScreenWillCoverTheApp")
}

// AGENT-PLATFORM (1.0.2, Fable review of 93d0663ef): screens their person can't swipe away; a call leaves the
// modal showing them up.
extension SecureBackupRecoveryKeyScreenCoordinator: HoldsItsModalAboveACall { }
extension SecureBackupKeyBackupScreenCoordinator: HoldsItsModalAboveACall { }
extension EncryptionResetScreenCoordinator: HoldsItsModalAboveACall { }
extension EncryptionResetPasswordScreenCoordinator: HoldsItsModalAboveACall { }
extension AppLockSetupPINScreenCoordinator: HoldsItsModalAboveACall { }
extension AppLockSetupBiometricsScreenCoordinator: HoldsItsModalAboveACall { }
extension AppLockScreenCoordinator: HoldsItsModalAboveACall { }
extension BugReportScreenCoordinator: HoldsItsModalAboveACall { }
extension ReportContentScreenCoordinator: HoldsItsModalAboveACall { }
