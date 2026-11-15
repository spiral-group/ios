//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AnalyticsEvents
import Combine
import MatrixRustSDK
import SwiftUI

enum ChatsTabFlowCoordinatorAction {
    case switchToChatsTab
    case showChatBackupSettings
    case sessionVerification(SessionVerificationScreenFlow)
    case showCallScreen(roomProxy: JoinedRoomProxyProtocol, isVoiceCall: Bool)
    case showAIConsentSettings // AGENT-PLATFORM (decision 150)
    case showAgentsTab // AGENT-PLATFORM (question 412)
    case hideCallScreenOverlay
    case logout
}

class ChatsTabFlowCoordinator: FlowCoordinatorProtocol {
    private let navigationSplitCoordinator: NavigationSplitCoordinator
    private let flowParameters: CommonFlowParameters
    
    private var userSession: UserSessionProtocol {
        flowParameters.userSession
    }
    
    private let stateMachine: ChatsTabFlowCoordinatorStateMachine
    
    private var roomFlowCoordinator: RoomFlowCoordinator?
    // periphery:ignore - retaining purpose
    private var spaceFlowCoordinator: SpaceFlowCoordinator?
    // AGENT-PLATFORM (Brief 0083, question 359): one of the owner's rows, from an agent's profile in a sheet.
    private(set) var agentRowFlowCoordinator: AgentRowFlowCoordinator? // AGENT-PLATFORM: read by the tests
    
    private var bugReportFlowCoordinator: BugReportFlowCoordinator?
    // periphery:ignore - retaining purpose
    private var encryptionResetFlowCoordinator: EncryptionResetFlowCoordinator?
    // periphery:ignore - retaining purpose
    private var startChatFlowCoordinator: StartChatFlowCoordinator?
    
    private var cancellables = Set<AnyCancellable>()
    
    private let sidebarNavigationStackCoordinator: NavigationStackCoordinator
    
    private let selectedRoomSubject = CurrentValueSubject<String?, Never>(nil)
    private let searchContext: SearchScreenViewModelType.Context? // AGENT-PLATFORM (Brief 0083, question 343)
    
    private let actionsSubject: PassthroughSubject<ChatsTabFlowCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<ChatsTabFlowCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(navigationSplitCoordinator: NavigationSplitCoordinator,
         searchContext: SearchScreenViewModelType.Context? = nil, // AGENT-PLATFORM (Brief 0083, question 343)
         flowParameters: CommonFlowParameters) {
        self.searchContext = searchContext
        stateMachine = flowParameters.stateMachineFactory.makeChatsTabFlowStateMachine()
        self.navigationSplitCoordinator = navigationSplitCoordinator
        self.flowParameters = flowParameters
        
        sidebarNavigationStackCoordinator = NavigationStackCoordinator(navigationSplitCoordinator: navigationSplitCoordinator)
        navigationSplitCoordinator.setSidebarCoordinator(sidebarNavigationStackCoordinator)
        
        setupStateMachine()
        setupObservers()
    }
    
    func start(animated: Bool) {
        stateMachine.processEvent(.start)
        // AGENT-PLATFORM (412): a catalogue template's post is titled in the reader's language from the titles the
        // last catalogue read kept (`SpiralAppTemplateTitles`); read it once per session, so a reader who never
        // opens the catalogue has them too.
        if !ProcessInfo.isRunningTests {
            let catalogURL = flowParameters.userSession.userSettings.app.interactiveCatalogURL
            Task.detached(priority: .utility) { _ = await SpiralAppCatalog.fetch(from: catalogURL) }
        }
    }
    
    func stop() { }
    
    func isDisplayingRoomScreen(withRoomID roomID: String) -> Bool {
        stateMachine.isDisplayingRoomScreen(withRoomID: roomID)
    }
    
    // MARK: - FlowCoordinatorProtocol
    
    func handleAppRoute(_ appRoute: AppRoute, animated: Bool) {
        MXLog.info("Handling app route: \(appRoute)")
        
        Task {
            await asyncHandleAppRoute(appRoute, animated: animated)
        }
    }
    
    func clearRoute(animated: Bool) {
        roomFlowCoordinator?.clearRoute(animated: animated)
    }
    
    // MARK: - Private
    
    func asyncHandleAppRoute(_ appRoute: AppRoute, animated: Bool) async {
        showLoadingIndicator(delay: .seconds(0.5))
        defer { hideLoadingIndicator() }
        
        await clearPresentedSheets(animated: animated)
        
        switch appRoute {
        case .room(let roomID, let via):
            stateMachine.processEvent(.selectRoom(roomID: roomID, via: via, entryPoint: .room), userInfo: .init(animated: animated))
        case .roomAlias(let alias):
            switch await userSession.clientProxy.resolveRoomAlias(alias) {
            case .success(let resolved): await asyncHandleAppRoute(.room(roomID: resolved.roomId, via: resolved.servers), animated: animated)
            case .failure(let error): showAliasFailure(error) // AGENT-PLATFORM (re-walk R8)
            }
        case .childRoom(let roomID, let via):
            if let roomFlowCoordinator {
                roomFlowCoordinator.handleAppRoute(appRoute, animated: animated)
            } else {
                stateMachine.processEvent(.selectRoom(roomID: roomID, via: via, entryPoint: .room), userInfo: .init(animated: animated))
            }
        case .childRoomAlias(let alias):
            switch await userSession.clientProxy.resolveRoomAlias(alias) {
            case .success(let resolved): await asyncHandleAppRoute(.childRoom(roomID: resolved.roomId, via: resolved.servers), animated: animated)
            case .failure(let error): showAliasFailure(error) // AGENT-PLATFORM (re-walk R8)
            }
            
        case .roomDetails(let roomID):
            if case .room(roomID) = stateMachine.state.detailState {
                roomFlowCoordinator?.handleAppRoute(appRoute, animated: animated)
            } else {
                stateMachine.processEvent(.selectRoom(roomID: roomID, via: [], entryPoint: .roomDetails), userInfo: .init(animated: animated))
            }
        case .roomList:
            roomFlowCoordinator?.clearRoute(animated: animated)
        case .roomMemberDetails:
            roomFlowCoordinator?.handleAppRoute(appRoute, animated: animated)
        case .thread(let roomID, let threadRootEventID, let focusEventID):
            stateMachine.processEvent(.selectRoom(roomID: roomID,
                                                  via: [],
                                                  entryPoint: .thread(rootEventID: threadRootEventID,
                                                                      focusEventID: focusEventID)),
                                      userInfo: .init(animated: animated))
        case .event(let eventID, let roomID, let via):
            stateMachine.processEvent(.selectRoom(roomID: roomID, via: via, entryPoint: .eventID(eventID)), userInfo: .init(animated: animated))
        case .eventOnRoomAlias(let eventID, let alias):
            switch await userSession.clientProxy.resolveRoomAlias(alias) {
            case .success(let resolved): await asyncHandleAppRoute(.event(eventID: eventID, roomID: resolved.roomId, via: resolved.servers), animated: animated)
            case .failure(let error): showAliasFailure(error) // AGENT-PLATFORM (re-walk R8)
            }
            
        case .childEvent:
            roomFlowCoordinator?.handleAppRoute(appRoute, animated: animated)
        case .childEventOnRoomAlias(let eventID, let alias):
            switch await userSession.clientProxy.resolveRoomAlias(alias) {
            case .success(let resolved): await asyncHandleAppRoute(.childEvent(eventID: eventID, roomID: resolved.roomId, via: resolved.servers), animated: animated)
            case .failure(let error): showAliasFailure(error) // AGENT-PLATFORM (re-walk R8)
            }
            
        case .userProfile(let userID):
            stateMachine.processEvent(.showUserProfileScreen(userID: userID), userInfo: .init(animated: animated))
        case .share(let payload):
            if let roomID = payload.roomID {
                stateMachine.processEvent(.selectRoom(roomID: roomID,
                                                      via: [],
                                                      entryPoint: .share(payload)),
                                          userInfo: .init(animated: animated))
            } else {
                stateMachine.processEvent(.showShareExtensionRoomList(sharePayload: payload), userInfo: .init(animated: animated))
            }
        case .transferOwnership(let roomID):
            if case .room(roomID) = stateMachine.state.detailState {
                roomFlowCoordinator?.handleAppRoute(appRoute, animated: animated)
            } else {
                stateMachine.processEvent(.presentTransferOwnershipScreen(roomID: roomID))
            }
        case .chatBackupSettings:
            actionsSubject.send(.showChatBackupSettings)
        case .catalogTemplate(let templateID, let roomID?): // AGENT-PLATFORM (decision 111)
            stateMachine.processEvent(.selectRoom(roomID: roomID, via: [], entryPoint: .catalogTemplate(templateID)),
                                      userInfo: .init(animated: animated))
        case .catalogTemplate(let templateID, nil):
            await handleCatalogLink(templateID: templateID, animated: animated)
        case .oAuthCallback, .inviteLink, .settings, .call, .search, .aiConsentSettings: // AGENT-PLATFORM: .inviteLink (Brief 0073), .aiConsentSettings (decision 150), no .accountProvisioningLink (Brief 0083 L1b)
            break // These routes cannot be handled.
        case .approvalDetail, .verificationDetail, .publicProfile:
            break // AGENT-PLATFORM: handled by AgentsTabFlowCoordinator.
        case .feedPost, .feedNotices:
            break // AGENT-PLATFORM: feed (Brief 0082): handled by FeedTabFlowCoordinator.
        }
    }
    
    private func clearPresentedSheets(animated: Bool) async {
        if navigationSplitCoordinator.sheetCoordinator == nil {
            return
        }
        
        navigationSplitCoordinator.setSheetCoordinator(nil, animated: animated)
        
        // Prevents system crashes when presenting a sheet if another one was already shown
        try? await Task.sleep(for: .seconds(0.25))
    }
    
    private func setupStateMachine() {
        stateMachine.addTransitionHandler { [weak self] context in
            guard let self else { return }
            
            let userInfo = context.userInfo as? ChatsTabFlowCoordinatorStateMachine.EventUserInfo
            let animated = userInfo?.animated ?? true
            
            switch (context.fromState, context.event, context.toState) {
            case (.initial, .start, .roomList):
                presentHomeScreen()
            case(.roomList(let detailState), .selectRoom(let roomID, let via, let entryPoint), .roomList):
                handleSelectRoomTransition(roomID: roomID, via: via, entryPoint: entryPoint, detailState: detailState, animated: animated)
            case(.roomList, .deselectRoom, .roomList):
                dismissRoomFlow(animated: animated)
                
            case(.roomList, .startSpaceFlow, .roomList):
                guard let spaceRoomListProxy = userInfo?.spaceRoomListProxy else { fatalError("A space room list proxy is required.") }
                startSpaceFlow(spaceRoomListProxy: spaceRoomListProxy, animated: animated)
            case (.roomList, .finishedSpaceFlow, .roomList):
                dismissSpaceFlow(animated: animated)
                
            case (.roomList, .feedbackScreen, .feedbackScreen):
                bugReportFlowCoordinator = BugReportFlowCoordinator(parameters: .init(presentationMode: .sheet(sidebarNavigationStackCoordinator),
                                                                                      userIndicatorController: flowParameters.userIndicatorController,
                                                                                      bugReportService: flowParameters.bugReportService,
                                                                                      userSession: userSession))
                bugReportFlowCoordinator?.actionsPublisher.sink { [weak self] action in
                    switch action {
                    case .complete:
                        self?.stateMachine.processEvent(.dismissedFeedbackScreen)
                    }
                }
                .store(in: &cancellables)
                
                bugReportFlowCoordinator?.start()
            case (.feedbackScreen, .dismissedFeedbackScreen, .roomList):
                break
                
            case (.roomList, .showRecoveryKeyScreen, .recoveryKeyScreen):
                presentRecoveryKeyScreen(animated: animated)
            case (.recoveryKeyScreen, .dismissedRecoveryKeyScreen, .roomList):
                break
                
            case (.roomList, .startEncryptionResetFlow, .encryptionResetFlow):
                startEncryptionResetFlow(animated: animated)
            case (.encryptionResetFlow, .finishedEncryptionResetFlow, .roomList):
                encryptionResetFlowCoordinator = nil
                
            case (.roomList, .startStartChatFlow, .startChatFlow):
                startStartChatFlow(animated: animated)
            case (.startChatFlow, .finishedStartChatFlow, .roomList):
                startChatFlowCoordinator = nil
                
            case (.roomList, .showRoomDirectorySearchScreen, .roomDirectorySearchScreen):
                presentRoomDirectorySearch()
            case (.roomDirectorySearchScreen, .dismissedRoomDirectorySearchScreen, .roomList):
                break // AGENT-PLATFORM (1.0.2): sent by the cover's dismissal
                
            case (_, .showUserProfileScreen(let userID), .userProfileScreen):
                presentUserProfileScreen(userID: userID, animated: animated)
            case (.userProfileScreen, .dismissedUserProfileScreen, .roomList):
                break
                
            case (.roomList, .presentReportRoomScreen(let roomID), .reportRoomScreen):
                Task { await self.presentReportRoom(for: roomID) }
            case (.reportRoomScreen, .dismissedReportRoomScreen, .roomList):
                break
                
            case (.roomList, .presentDeclineAndBlockScreen(let userID, let roomID), .declineAndBlockUserScreen):
                presentDeclineAndBlockScreen(userID: userID, roomID: roomID)
            case (.declineAndBlockUserScreen, .dismissedDeclineAndBlockScreen, .roomList):
                break
                
            case (.roomList, .presentTransferOwnershipScreen(let roomID), .transferOwnershipScreen):
                Task { await self.presentTransferOwnershipScreen(roomID: roomID) }
            case (.transferOwnershipScreen, .dismissedTransferOwnershipScreen, .roomList):
                break
                
            case (.roomList(let roomListSelectedRoomID), .showShareExtensionRoomList, .shareExtensionRoomList(let sharePayload)):
                Task {
                    if roomListSelectedRoomID != nil {
                        self.clearRoute(animated: animated)
                        try? await Task.sleep(for: .seconds(1.5))
                    }
                    
                    self.presentRoomSelectionScreen(sharePayload: sharePayload, animated: animated)
                }
            case (.shareExtensionRoomList, .dismissedShareExtensionRoomList, .roomList):
                dismissRoomSelectionScreen()
                
            // AGENT-PLATFORM (decision 111): the share picker's shape, for a catalogue link.
            case (.roomList(let roomListSelectedRoomID), .showCatalogRoomList, .catalogRoomList(let templateID)):
                presentCatalogRoomSelectionScreen(templateID: templateID, clearingRoom: roomListSelectedRoomID != nil, animated: animated)
            case (.catalogRoomList, .dismissedCatalogRoomList, .roomList):
                dismissRoomSelectionScreen()
                
            default:
                fatalError("Unknown transition: \(context)")
            }
        }
        
        stateMachine.addTransitionHandler { [weak self] context in
            switch context.toState {
            case .roomList(detailState: .room(let detailStateRoomID)):
                self?.selectedRoomSubject.send(detailStateRoomID)
            case .roomList(detailState: .space):
                // We don't show joined spaces in the room list yet so clear the selected room when accepting a space invite.
                self?.selectedRoomSubject.send(nil)
            case .roomList(detailState: nil):
                self?.selectedRoomSubject.send(nil)
            default:
                break
            }
        }
        
        stateMachine.addErrorHandler { context in
            if context.fromState == context.toState {
                MXLog.error("Failed transition from equal states: \(context.fromState)")
            } else {
                fatalError("Failed transition with context: \(context)")
            }
        }
    }
    
    private func handleSelectRoomTransition(roomID: String, via: [String], entryPoint: RoomFlowCoordinatorEntryPoint, detailState: ChatsTabFlowCoordinatorStateMachine.DetailState?, animated: Bool) {
        if case .room(roomID) = detailState,
           !entryPoint.isEventID, // Don't reuse the existing room so the live timeline is hidden while the detached timeline is loading.
           let roomFlowCoordinator {
            let route: AppRoute = switch entryPoint {
            case .room: .room(roomID: roomID, via: via)
            case .roomDetails: .roomDetails(roomID: roomID)
            case .eventID(let eventID): .event(eventID: eventID, roomID: roomID, via: via) // ignored.
            case .share(let payload): .share(payload)
            case .catalogTemplate(let templateID): .catalogTemplate(templateID: templateID, roomID: roomID) // AGENT-PLATFORM (decision 111)
            case .transferOwnership: .transferOwnership(roomID: roomID)
            case .thread(let rootEventID, let focusEventID): .thread(roomID: roomID, threadRootEventID: rootEventID, focusEventID: focusEventID)
            }
            roomFlowCoordinator.handleAppRoute(route, animated: animated)
        } else {
            if case .space = detailState {
                dismissRoomFlow(animated: animated)
            }
            startRoomFlow(roomID: roomID,
                          via: via,
                          entryPoint: entryPoint,
                          detached: false,
                          animated: animated)
        }
        actionsSubject.send(.hideCallScreenOverlay) // Turn any active call into a PiP so that navigation from a notification is visible to the user.
    }
    
    private func setupObservers() {
        userSession.clientProxy.actionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .receivedDecryptionError(let info):
                    processDecryptionError(info)
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    private func processDecryptionError(_ info: UnableToDecryptInfo) {
        let timeToDecryptMs: Int
        if let unsignedTimeToDecryptMs = info.timeToDecryptMs {
            timeToDecryptMs = Int(unsignedTimeToDecryptMs)
        } else {
            timeToDecryptMs = -1
        }
        
        let errorName: AnalyticsEvent.Error.Name = switch info.cause {
        case .unknown: .OlmKeysNotSentError
        case .unknownDevice, .unsignedDevice: .ExpectedSentByInsecureDevice
        case .verificationViolation: .ExpectedVerificationViolation
        case .sentBeforeWeJoined: .ExpectedDueToMembership
        case .historicalMessageAndBackupIsDisabled, .historicalMessageAndDeviceIsUnverified: .HistoricalMessage
        case .withheldForUnverifiedOrInsecureDevice: .RoomKeysWithheldForUnverifiedDevice
        case .withheldBySender: .OlmKeysNotSentError
        }
        
        flowParameters.analytics.trackError(context: nil,
                                            domain: .E2EE,
                                            name: errorName,
                                            timeToDecryptMillis: timeToDecryptMs,
                                            eventLocalAgeMillis: Int(truncatingIfNeeded: info.eventLocalAgeMillis),
                                            isFederated: info.ownHomeserver != info.senderHomeserver,
                                            isMatrixDotOrg: info.ownHomeserver == "matrix.org",
                                            userTrustsOwnIdentity: info.userTrustsOwnIdentity,
                                            wasVisibleToUser: nil)
    }
    
    private func presentHomeScreen() {
        let parameters = HomeScreenCoordinatorParameters(userSession: userSession,
                                                         availableSessionsPublisher: flowParameters.availableSessionsPublisher,
                                                         bugReportService: flowParameters.bugReportService,
                                                         selectedRoomPublisher: selectedRoomSubject.asCurrentValuePublisher(),
                                                         analyticsService: flowParameters.analytics,
                                                         userIndicatorController: flowParameters.userIndicatorController,
                                                         searchContext: searchContext) // AGENT-PLATFORM (Brief 0083, question 343)
        let coordinator = HomeScreenCoordinator(parameters: parameters)
        
        coordinator.actions
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .presentRoom(let roomID):
                    handleAppRoute(.room(roomID: roomID, via: []), animated: true)
                case .detachRoom(let roomID):
                    startRoomFlow(roomID: roomID, via: [], entryPoint: .room, detached: true, animated: true)
                case .presentRoomDetails(let roomID):
                    handleAppRoute(.roomDetails(roomID: roomID), animated: true)
                case .presentReportRoom(let roomID):
                    stateMachine.processEvent(.presentReportRoomScreen(roomID: roomID))
                case .presentSpace(let spaceRoomListProxy):
                    stateMachine.processEvent(.startSpaceFlow, userInfo: .init(animated: true, spaceRoomListProxy: spaceRoomListProxy))
                case .roomLeft(let roomID):
                    if case .roomList(detailState: .room(let detailStateRoomID)) = stateMachine.state,
                       detailStateRoomID == roomID {
                        clearRoute(animated: true)
                    }
                case .presentFeedbackScreen:
                    stateMachine.processEvent(.feedbackScreen)
                case .presentSecureBackupSettings:
                    actionsSubject.send(.showChatBackupSettings)
                case .presentRecoveryKeyScreen:
                    stateMachine.processEvent(.showRecoveryKeyScreen)
                case .presentEncryptionResetScreen:
                    stateMachine.processEvent(.startEncryptionResetFlow)
                case .presentStartChatScreen:
                    stateMachine.processEvent(.startStartChatFlow)
                case .logout:
                    actionsSubject.send(.logout)
                case .presentDeclineAndBlock(let userID, let roomID):
                    stateMachine.processEvent(.presentDeclineAndBlockScreen(userID: userID, roomID: roomID))
                case .transferOwnership(let roomIdentifier):
                    handleAppRoute(.transferOwnership(roomID: roomIdentifier), animated: true)
                }
            }
            .store(in: &cancellables)
        
        sidebarNavigationStackCoordinator.setRootCoordinator(coordinator)
    }
    
    private func presentReportRoom(for roomID: String) async {
        guard let roomProxyType = await userSession.clientProxy.roomForIdentifier(roomID),
              case let .joined(roomProxy) = roomProxyType else {
            MXLog.error("Failed to get room proxy for room: \(roomID)")
            return
        }
        
        let navigationStackCoordinator = NavigationStackCoordinator()
        let coordinator = ReportRoomScreenCoordinator(parameters: .init(roomProxy: roomProxy,
                                                                        userIndicatorController: flowParameters.userIndicatorController))
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .dismiss(let shouldLeaveRoom):
                if shouldLeaveRoom,
                   case .roomList(detailState: .room(let detailStateRoomID)) = stateMachine.state,
                   detailStateRoomID == roomID {
                    clearRoute(animated: true)
                }
                navigationSplitCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)
        navigationStackCoordinator.setRootCoordinator(coordinator)
        navigationSplitCoordinator.setSheetCoordinator(navigationStackCoordinator) { [weak self] in
            self?.stateMachine.processEvent(.dismissedReportRoomScreen)
        }
    }
    
    private func presentDeclineAndBlockScreen(userID: String, roomID: String) {
        let stackCoordinator = NavigationStackCoordinator()
        let coordinator = DeclineAndBlockScreenCoordinator(parameters: .init(userID: userID,
                                                                             roomID: roomID,
                                                                             clientProxy: userSession.clientProxy,
                                                                             userIndicatorController: flowParameters.userIndicatorController))
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .dismiss:
                navigationSplitCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)
        
        stackCoordinator.setRootCoordinator(coordinator)
        navigationSplitCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.stateMachine.processEvent(.dismissedDeclineAndBlockScreen)
        }
    }
    
    private func presentTransferOwnershipScreen(roomID: String) async {
        guard case let .joined(roomProxy) = await userSession.clientProxy.roomForIdentifier(roomID) else {
            return
        }
        // The screen requires listening to the membership state changes
        await roomProxy.subscribeForUpdates()
        
        let parameters = RoomChangeRolesScreenCoordinatorParameters(mode: .owner,
                                                                    roomProxy: roomProxy,
                                                                    mediaProvider: userSession.mediaProvider,
                                                                    userIndicatorController: flowParameters.userIndicatorController,
                                                                    analytics: flowParameters.analytics)
        let stackCoordinator = NavigationStackCoordinator()
        let coordinator = RoomChangeRolesScreenCoordinator(parameters: parameters)
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .complete:
                navigationSplitCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)
        
        stackCoordinator.setRootCoordinator(coordinator)
        navigationSplitCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.stateMachine.processEvent(.dismissedTransferOwnershipScreen)
        }
    }
    
    // MARK: Room Flow
    
    private func startRoomFlow(roomID: String,
                               via: [String],
                               entryPoint: RoomFlowCoordinatorEntryPoint,
                               detached: Bool,
                               animated: Bool) {
        let navigationStackCoordinator = NavigationStackCoordinator(navigationSplitCoordinator: detached ? nil : navigationSplitCoordinator)
        
        let coordinator = RoomFlowCoordinator(roomID: roomID,
                                              isChildFlow: false,
                                              navigationStackCoordinator: navigationStackCoordinator,
                                              flowParameters: flowParameters)
        
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .presentCallScreen(let roomProxy, let isVoiceCall):
                actionsSubject.send(.showCallScreen(roomProxy: roomProxy, isVoiceCall: isVoiceCall))
            case .presentAIConsentSettings: // AGENT-PLATFORM (decision 150)
                actionsSubject.send(.showAIConsentSettings)
            case .presentAgentsTab: // AGENT-PLATFORM (question 412)
                actionsSubject.send(.showAgentsTab)
            case .verifyUser(let userID):
                actionsSubject.send(.sessionVerification(.userInitiator(userID: userID)))
            case .continueWithSpaceFlow(let spaceRoomListProxy):
                stateMachine.processEvent(.startSpaceFlow, userInfo: .init(animated: false, spaceRoomListProxy: spaceRoomListProxy))
            case .finished:
                stateMachine.processEvent(.deselectRoom)
            }
        }
        .store(in: &cancellables)
        
        if detached {
            flowParameters.windowManager.registerCoordinator(navigationStackCoordinator,
                                                             flowCoordinator: coordinator,
                                                             forWindowType: .room(roomID: roomID))
        } else {
            roomFlowCoordinator = coordinator
            navigationSplitCoordinator.setDetailCoordinator(navigationStackCoordinator, animated: animated)
        }
        
        switch entryPoint {
        case .room:
            coordinator.handleAppRoute(.room(roomID: roomID, via: via), animated: animated)
        case .eventID(let eventID):
            coordinator.handleAppRoute(.event(eventID: eventID, roomID: roomID, via: via), animated: animated)
        case .roomDetails:
            coordinator.handleAppRoute(.roomDetails(roomID: roomID), animated: animated)
        case .share(let payload):
            coordinator.handleAppRoute(.share(payload), animated: animated)
        case .catalogTemplate(let templateID): // AGENT-PLATFORM (decision 111)
            coordinator.handleAppRoute(.catalogTemplate(templateID: templateID, roomID: roomID), animated: animated)
        case .transferOwnership:
            coordinator.handleAppRoute(.transferOwnership(roomID: roomID), animated: animated)
        case .thread(let rootEventID, let focusEventID):
            coordinator.handleAppRoute(.thread(roomID: roomID, threadRootEventID: rootEventID, focusEventID: focusEventID), animated: animated)
        }
        
        Task {
            let _ = await userSession.clientProxy.trackRecentlyVisitedRoom(roomID)
            
            userSession.notificationService.removeDeliveredMessageNotifications(for: roomID)
        }
    }
    
    private func dismissRoomFlow(animated: Bool) {
        // THIS MUST BE CALLED *AFTER* THE FLOW HAS TIDIED UP THE STACK OR IT CAN CAUSE A CRASH.
        navigationSplitCoordinator.setDetailCoordinator(nil, animated: animated)
        roomFlowCoordinator = nil
    }
    
    // MARK: Space Flow
    
    private func startSpaceFlow(spaceRoomListProxy: SpaceRoomListProxyProtocol, animated: Bool) {
        let navigationStackCoordinator = NavigationStackCoordinator(navigationSplitCoordinator: navigationSplitCoordinator)
        let coordinator = SpaceFlowCoordinator(entryPoint: .space(spaceRoomListProxy),
                                               spaceServiceProxy: userSession.clientProxy.spaceService,
                                               isChildFlow: false,
                                               navigationStackCoordinator: navigationStackCoordinator,
                                               flowParameters: flowParameters)
        coordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .presentCallScreen(let roomProxy, let isVoiceCall):
                    actionsSubject.send(.showCallScreen(roomProxy: roomProxy, isVoiceCall: isVoiceCall))
                case .presentAIConsentSettings: // AGENT-PLATFORM (decision 150)
                    actionsSubject.send(.showAIConsentSettings)
                case .presentAgentsTab: // AGENT-PLATFORM (question 412)
                    actionsSubject.send(.showAgentsTab)
                case .verifyUser(let userID):
                    actionsSubject.send(.sessionVerification(.userInitiator(userID: userID)))
                case .finished:
                    stateMachine.processEvent(.finishedSpaceFlow)
                }
            }
            .store(in: &cancellables)
        
        spaceFlowCoordinator = coordinator
        
        navigationSplitCoordinator.setDetailCoordinator(navigationStackCoordinator, animated: animated)
        
        coordinator.start()
    }
    
    private func dismissSpaceFlow(animated: Bool) {
        // Based on dismissRoomFlow, past me was very insistent that this must happen after the flow has tidied the stack 😅.
        navigationSplitCoordinator.setDetailCoordinator(nil, animated: animated)
        roomFlowCoordinator = nil
    }
    
    // MARK: Start Chat
    
    private func startStartChatFlow(animated: Bool) {
        let navigationStackCoordinator = NavigationStackCoordinator()
        let coordinator = StartChatFlowCoordinator(entryPoint: .startChat,
                                                   userDiscoveryService: UserDiscoveryService(clientProxy: userSession.clientProxy),
                                                   navigationStackCoordinator: navigationStackCoordinator,
                                                   flowParameters: flowParameters)
        
        coordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .finished(let result):
                    navigationSplitCoordinator.setSheetCoordinator(nil)
                    
                    switch result {
                    case .room(let roomID):
                        stateMachine.processEvent(.selectRoom(roomID: roomID, via: [], entryPoint: .room))
                    case .space(let spaceRoomListProxy):
                        // This also automatically handles selecting the space.
                        stateMachine.processEvent(.selectRoom(roomID: spaceRoomListProxy.id, via: [], entryPoint: .room))
                    case .cancelled:
                        break
                    }
                case .showRoomDirectory:
                    navigationSplitCoordinator.setSheetCoordinator(nil)
                    stateMachine.processEvent(.showRoomDirectorySearchScreen)
                case .showUserProfile(let userID): // AGENT-PLATFORM (Brief 0073).
                    navigationSplitCoordinator.setSheetCoordinator(nil)
                    handleAppRoute(.userProfile(userID: userID), animated: true)
                }
            }
            .store(in: &cancellables)
        
        startChatFlowCoordinator = coordinator
        coordinator.start()
        
        navigationSplitCoordinator.setSheetCoordinator(navigationStackCoordinator, animated: animated) { [weak self] in
            self?.stateMachine.processEvent(.finishedStartChatFlow)
        }
    }
    
    // MARK: Secure backup
    
    private func presentRecoveryKeyScreen(animated: Bool) {
        let sheetNavigationStackCoordinator = NavigationStackCoordinator()
        let parameters = SecureBackupRecoveryKeyScreenCoordinatorParameters(secureBackupController: userSession.clientProxy.secureBackupController,
                                                                            userIndicatorController: flowParameters.userIndicatorController,
                                                                            isModallyPresented: true)
        
        let coordinator = userSession.userHooks.recoveryKeyScreenHook.makeCoordinator(parameters: parameters)
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .complete:
                navigationSplitCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)
        
        sheetNavigationStackCoordinator.setRootCoordinator(coordinator)
        
        navigationSplitCoordinator.setSheetCoordinator(sheetNavigationStackCoordinator, animated: animated) { [weak self] in
            self?.stateMachine.processEvent(.dismissedRecoveryKeyScreen)
        }
    }
    
    private func startEncryptionResetFlow(animated: Bool) {
        let sheetNavigationStackCoordinator = NavigationStackCoordinator()
        let parameters = EncryptionResetFlowCoordinatorParameters(userSession: userSession,
                                                                  appMediator: flowParameters.appMediator,
                                                                  userIndicatorController: flowParameters.userIndicatorController,
                                                                  navigationStackCoordinator: sheetNavigationStackCoordinator,
                                                                  windowManger: flowParameters.windowManager)
        
        let coordinator = EncryptionResetFlowCoordinator(parameters: parameters)
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .resetComplete:
                navigationSplitCoordinator.setSheetCoordinator(nil)
            case .cancel:
                navigationSplitCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)
        
        coordinator.start()
        encryptionResetFlowCoordinator = coordinator
        
        navigationSplitCoordinator.setSheetCoordinator(sheetNavigationStackCoordinator, animated: animated) { [weak self] in
            self?.stateMachine.processEvent(.finishedEncryptionResetFlow)
        }
    }
    
    // MARK: Room Directory Search
    
    private func presentRoomDirectorySearch() {
        let coordinator = RoomDirectorySearchScreenCoordinator(parameters: .init(userSession: userSession,
                                                                                 userIndicatorController: flowParameters.userIndicatorController))
        
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .selectAlias(let alias):
                navigationSplitCoordinator.setFullScreenCoverCoordinator(nil)
                handleAppRoute(.roomAlias(alias), animated: true)
            case .selectRoomID(let roomID):
                navigationSplitCoordinator.setFullScreenCoverCoordinator(nil)
                handleAppRoute(.room(roomID: roomID, via: []), animated: true)
            case .dismiss:
                navigationSplitCoordinator.setFullScreenCoverCoordinator(nil)
            }
        }
        .store(in: &cancellables)
        
        // AGENT-PLATFORM (1.0.2, Fable review of 93d0663ef): the state follows the cover however it goes. A call
        // screen coming up closes it too, and the state used to stay on the directory, so no chat opened again.
        navigationSplitCoordinator.setFullScreenCoverCoordinator(coordinator) { [weak self] in
            self?.stateMachine.processEvent(.dismissedRoomDirectorySearchScreen)
        }
    }
    
    // MARK: User Profile
    
    private func presentUserProfileScreen(userID: String, animated: Bool) {
        clearRoute(animated: animated)
        
        let navigationStackCoordinator = NavigationStackCoordinator()
        let parameters = UserProfileScreenCoordinatorParameters(userID: userID,
                                                                isPresentedModally: true,
                                                                userSession: userSession,
                                                                analytics: flowParameters.analytics,
                                                                userIndicatorController: flowParameters.userIndicatorController)
        let coordinator = UserProfileScreenCoordinator(parameters: parameters)
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .openDirectChat(let roomID):
                navigationSplitCoordinator.setSheetCoordinator(nil)
                stateMachine.processEvent(.selectRoom(roomID: roomID, via: [], entryPoint: .room))
            case .startCall(let roomProxy, let isVoiceCall):
                // A sheet stays above the call screen: without this it covers the call until Done.
                navigationSplitCoordinator.setSheetCoordinator(nil)
                actionsSubject.send(.showCallScreen(roomProxy: roomProxy, isVoiceCall: isVoiceCall))
            case .dismiss:
                navigationSplitCoordinator.setSheetCoordinator(nil)
            case .openAgentRow(let row, let card): // AGENT-PLATFORM (Brief 0083, question 359)
                startAgentRowFlow(row: row, card: card, on: navigationStackCoordinator)
            }
        }
        .store(in: &cancellables)
        
        navigationStackCoordinator.setRootCoordinator(coordinator, animated: false)
        navigationSplitCoordinator.setSheetCoordinator(navigationStackCoordinator, animated: animated) { [weak self] in
            self?.agentRowFlowCoordinator = nil // AGENT-PLATFORM (Brief 0083, question 359)
            self?.stateMachine.processEvent(.dismissedUserProfileScreen)
        }
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 359): one of the owner's rows of an agent's page, inside the profile's sheet.
    func startAgentRowFlow(row: AgentPageRow, card: AgentSpaceAgentCard, on navigationStackCoordinator: NavigationStackCoordinator) {
        guard let coordinator = AgentRowFlowCoordinator(row: row,
                                                        card: card,
                                                        navigationStackCoordinator: navigationStackCoordinator,
                                                        flowParameters: flowParameters,
                                                        showOriginRoom: { [weak self] in self?.showRoomFromProfile(roomID: $0) ?? false }) else {
            MXLog.warning("ChatsTabFlowCoordinator: no agent platform: cannot open an agent's row")
            flowParameters.userIndicatorController.submitIndicator(.init(title: L10n.errorUnknown))
            return
        }
        
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .finished:
                agentRowFlowCoordinator = nil
            case .presentCallScreen(let roomProxy, let isVoiceCall):
                // A sheet stays above the call screen, as for the profile's own Call.
                navigationSplitCoordinator.setSheetCoordinator(nil)
                actionsSubject.send(.showCallScreen(roomProxy: roomProxy, isVoiceCall: isVoiceCall))
            case .presentAIConsentSettings:
                navigationSplitCoordinator.setSheetCoordinator(nil)
                actionsSubject.send(.showAIConsentSettings)
            case .presentAgentsTab: // AGENT-PLATFORM (question 412)
                navigationSplitCoordinator.setSheetCoordinator(nil)
                actionsSubject.send(.showAgentsTab)
            case .verifyUser(let userID):
                navigationSplitCoordinator.setSheetCoordinator(nil)
                actionsSubject.send(.sessionVerification(.userInitiator(userID: userID)))
            }
        }
        .store(in: &cancellables)
        
        agentRowFlowCoordinator = coordinator
        coordinator.start(animated: true)
    }
    
    /// AGENT-PLATFORM (end-stage review, 2026-11-14): a chat asked for on an agent's page in the profile's sheet, by its
    /// Message or an activity row, opens in Chats as the profile's own Message does: the sheet closes, taking the page's
    /// flow with it, and the room is selected. Pushed on the sheet's stack, the chat stayed inside the sheet.
    func showRoomFromProfile(roomID: String) -> Bool {
        navigationSplitCoordinator.setSheetCoordinator(nil)
        stateMachine.processEvent(.selectRoom(roomID: roomID, via: [], entryPoint: .room))
        return true
    }
    
    // MARK: Sharing
    
    private func presentRoomSelectionScreen(sharePayload: ShareExtensionPayload, animated: Bool) {
        let roomSummaryProvider = userSession.clientProxy.alternateRoomSummaryProvider
        
        let stackCoordinator = NavigationStackCoordinator()
        
        let coordinator = RoomSelectionScreenCoordinator(parameters: .init(userSession: userSession,
                                                                           roomSummaryProvider: roomSummaryProvider))
        
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .dismiss:
                navigationSplitCoordinator.setSheetCoordinator(nil)
            case .confirm(let roomID):
                let sharePayload = switch sharePayload {
                case .mediaFiles(_, let mediaFiles):
                    ShareExtensionPayload.mediaFiles(roomID: roomID, mediaFiles: mediaFiles)
                case .text(_, let text):
                    ShareExtensionPayload.text(roomID: roomID, text: text)
                }
                
                navigationSplitCoordinator.setSheetCoordinator(nil)
                
                stateMachine.processEvent(.selectRoom(roomID: roomID,
                                                      via: [],
                                                      entryPoint: .share(sharePayload)),
                                          userInfo: .init(animated: animated))
            }
        }
        .store(in: &cancellables)
        
        stackCoordinator.setRootCoordinator(coordinator)
        
        navigationSplitCoordinator.setSheetCoordinator(stackCoordinator, animated: animated) { [weak self] in
            self?.stateMachine.processEvent(.dismissedShareExtensionRoomList)
        }
    }
    
    private func dismissRoomSelectionScreen() {
        navigationSplitCoordinator.setSheetCoordinator(nil)
    }
    
    // MARK: Catalogue links (AGENT-PLATFORM, decision 111)
    
    /// A template the catalogue has asks which chat it goes to; one it
    /// doesn't have, or that this build can't run, says so and asks nothing.
    private func handleCatalogLink(templateID: String, animated: Bool) async {
        switch await SpiralAppCatalog.resolve(templateID, from: flowParameters.userSession.userSettings.app.interactiveCatalogURL) {
        case .template:
            stateMachine.processEvent(.showCatalogRoomList(templateID: templateID), userInfo: .init(animated: animated))
        case .needsNewerApp:
            MXLog.info("[SpiralApp] catalogue link to \(templateID) needs a newer build")
            showLinkIndicator(title: UntranslatedL10n.screenRoomInteractivePostLinkNeedsUpdate)
        case .unknown:
            MXLog.info("[SpiralApp] catalogue link to \(templateID), which the catalogue doesn't list")
            showLinkIndicator(title: UntranslatedL10n.screenRoomInteractivePostLinkNotInCatalogue)
        case .unavailable:
            MXLog.error("[SpiralApp] catalogue unavailable for a link to \(templateID)")
            showFailureIndicator()
        }
    }
    
    /// As the share picker does, a chat on screen is closed first.
    private func presentCatalogRoomSelectionScreen(templateID: String, clearingRoom: Bool, animated: Bool) {
        Task {
            if clearingRoom {
                clearRoute(animated: animated)
                try? await Task.sleep(for: .seconds(1.5))
            }
            presentCatalogRoomSelectionScreen(templateID: templateID, animated: animated)
        }
    }
    
    private func presentCatalogRoomSelectionScreen(templateID: String, animated: Bool) {
        let stackCoordinator = NavigationStackCoordinator()
        let coordinator = RoomSelectionScreenCoordinator(parameters: .init(userSession: userSession,
                                                                           roomSummaryProvider: userSession.clientProxy.alternateRoomSummaryProvider,
                                                                           confirmTitle: L10n.actionContinue))
        
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .dismiss:
                navigationSplitCoordinator.setSheetCoordinator(nil)
            case .confirm(let roomID):
                navigationSplitCoordinator.setSheetCoordinator(nil)
                stateMachine.processEvent(.selectRoom(roomID: roomID, via: [], entryPoint: .catalogTemplate(templateID)),
                                          userInfo: .init(animated: animated))
            }
        }
        .store(in: &cancellables)
        
        stackCoordinator.setRootCoordinator(coordinator)
        
        navigationSplitCoordinator.setSheetCoordinator(stackCoordinator, animated: animated) { [weak self] in
            self?.stateMachine.processEvent(.dismissedCatalogRoomList)
        }
    }
    
    /// AGENT-PLATFORM (re-walk R8): an alias nobody holds is a dead link,
    /// said the way a catalogue link to a gone template is; any other failure
    /// is an error.
    private func showAliasFailure(_ error: ClientProxyError) {
        if case .failedResolvingRoomAlias = error {
            showLinkIndicator(title: UntranslatedL10n.screenRoomAliasLinkNotFound)
        } else {
            showFailureIndicator()
        }
    }
    
    /// AGENT-PLATFORM: a link the app can't open, said in its own words.
    private func showLinkIndicator(title: String) {
        flowParameters.userIndicatorController.submitIndicator(UserIndicator(id: Self.failureIndicatorIdentifier,
                                                                             type: .toast,
                                                                             title: title))
    }
    
    // MARK: Toasts and loading indicators
    
    private static let loadingIndicatorIdentifier = "\(ChatsTabFlowCoordinator.self)-Loading"
    private static let failureIndicatorIdentifier = "\(ChatsTabFlowCoordinator.self)-Failure"
    
    private func showLoadingIndicator(delay: Duration? = nil) {
        flowParameters.userIndicatorController.submitIndicator(UserIndicator(id: Self.loadingIndicatorIdentifier,
                                                                             type: .modal,
                                                                             title: L10n.commonLoading,
                                                                             persistent: true),
                                                               delay: delay)
    }
    
    private func hideLoadingIndicator() {
        flowParameters.userIndicatorController.retractIndicatorWithId(Self.loadingIndicatorIdentifier)
    }
    
    private func showFailureIndicator() {
        flowParameters.userIndicatorController.submitIndicator(UserIndicator(id: Self.failureIndicatorIdentifier,
                                                                             type: .toast,
                                                                             title: L10n.errorUnknown,
                                                                             icon: \.close))
    }
}
