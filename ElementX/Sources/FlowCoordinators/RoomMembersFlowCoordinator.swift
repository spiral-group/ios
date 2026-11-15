//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftState
import SwiftUI

enum RoomMembersFlowCoordinatorAction {
    case finished
    case presentCallScreen(roomProxy: JoinedRoomProxyProtocol, isVoiceCall: Bool)
    case presentAIConsentSettings // AGENT-PLATFORM (decision 150)
    /// The Agents tab, where the person's agent is or will be (question 412).
    case presentAgentsTab
    case verifyUser(userID: String)
}

enum RoomMembersFlowCoordinatorEntryPoint: Hashable {
    /// To be used in a room when a member name is tapped
    case roomMember(userID: String)
    /// To be used in the context of room details, space details etc.
    case roomMembersList
}

final class RoomMembersFlowCoordinator: FlowCoordinatorProtocol {
    indirect enum State: StateType {
        /// The state machine hasn't started.
        case initial
        /// The room members list
        case roomMembersList
        /// The details for a member of the room
        case roomMemberDetails(userID: String, previousState: State)
        /// In case the details won't load because the user has left the room we load the profile
        case userProfile(userID: String, previousState: State)
        /// The invite users screen
        case inviteUsersScreen
        /// A room flow has been started
        case roomFlow(roomID: String, previousState: State)
        /// AGENT-PLATFORM (Brief 0083, question 359): one of the owner's rows of an agent's page.
        case agentRowFlow(previousState: State)
    }
    
    enum Event: EventType {
        case presentRoomMembersList
        
        case presentRoomMemberDetails(userID: String)
        case dismissedRoomMemberDetails
        
        case presentInviteUsersScreen
        case dismissedInviteUsersScreen
        
        case presentUserProfile(userID: String)
        case dismissedUserProfile
        
        case startRoomFlow(roomID: String, via: [String], eventID: String?)
        case stopRoomFlow
        
        /// AGENT-PLATFORM (Brief 0083, question 359)
        case startAgentRowFlow(row: AgentPageRow, card: AgentSpaceAgentCard)
        case stopAgentRowFlow
    }
    
    private let entryPoint: RoomMembersFlowCoordinatorEntryPoint
    private let roomProxy: JoinedRoomProxyProtocol
    private let navigationStackCoordinator: NavigationStackCoordinator
    /// The last coordinator in the `navigationStackCoordinator` stack at the initial state
    private let initialCoordinator: CoordinatorProtocol?
    private let flowParameters: CommonFlowParameters
    
    private let stateMachine: StateMachine<State, Event>
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<RoomMembersFlowCoordinatorAction, Never> = .init()
    var actions: AnyPublisher<RoomMembersFlowCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    private var childFlowCoordinator: FlowCoordinatorProtocol?
    /// How an agent's «Open chat» returns to the room the members were opened from. `nil` for a flow with no such room.
    private let showOriginRoom: ((_ roomID: String) -> Bool)?
    
    init(entryPoint: RoomMembersFlowCoordinatorEntryPoint,
         roomProxy: JoinedRoomProxyProtocol,
         navigationStackCoordinator: NavigationStackCoordinator,
         flowParameters: CommonFlowParameters,
         showOriginRoom: ((_ roomID: String) -> Bool)? = nil) {
        self.showOriginRoom = showOriginRoom
        self.entryPoint = entryPoint
        self.roomProxy = roomProxy
        self.flowParameters = flowParameters
        self.navigationStackCoordinator = navigationStackCoordinator
        initialCoordinator = navigationStackCoordinator.stackCoordinators.last ?? navigationStackCoordinator.rootCoordinator
        
        stateMachine = flowParameters.stateMachineFactory.makeMembersFlowStateMachine(state: .initial)
        configureStateMachine()
    }
    
    func start(animated: Bool) {
        switch entryPoint {
        case .roomMember(let userID):
            stateMachine.tryEvent(.presentRoomMemberDetails(userID: userID), userInfo: animated)
        case .roomMembersList:
            stateMachine.tryEvent(.presentRoomMembersList, userInfo: animated)
        }
    }
    
    func handleAppRoute(_ appRoute: AppRoute, animated: Bool) {
        MXLog.info("Handling app route: \(appRoute)")
        
        switch appRoute {
        case .roomMemberDetails(let userID):
            if case .roomFlow = stateMachine.state, let childFlowCoordinator {
                childFlowCoordinator.handleAppRoute(appRoute, animated: animated)
            } else {
                stateMachine.tryEvent(.presentRoomMemberDetails(userID: userID), userInfo: animated)
            }
        case .childRoom(let roomID, let via):
            if case .roomFlow = stateMachine.state, let childFlowCoordinator {
                childFlowCoordinator.handleAppRoute(appRoute, animated: animated)
            } else {
                stateMachine.tryEvent(.startRoomFlow(roomID: roomID, via: via, eventID: nil), userInfo: animated)
            }
        case .childEvent(let eventID, let roomID, let via):
            if case .roomFlow = stateMachine.state, let childFlowCoordinator {
                childFlowCoordinator.handleAppRoute(appRoute, animated: animated)
            } else {
                stateMachine.tryEvent(.startRoomFlow(roomID: roomID, via: via, eventID: eventID), userInfo: animated)
            }
        case .roomAlias, .childRoomAlias, .eventOnRoomAlias, .childEventOnRoomAlias:
            break // These are converted to a room ID route one level above.
        case .oAuthCallback, .inviteLink, // AGENT-PLATFORM: .inviteLink (Brief 0073), no .accountProvisioningLink (Brief 0083 L1b)
             .roomList, .room, .roomDetails, .event,
             .userProfile, .call, .settings, .chatBackupSettings,
             .share, .transferOwnership, .thread, .search:
            break
        case .approvalDetail, .verificationDetail, .publicProfile:
            break // AGENT-PLATFORM: handled by AgentsTabFlowCoordinator.
        case .aiConsentSettings:
            break // AGENT-PLATFORM (decision 150): handled by the settings flow.
        case .catalogTemplate:
            break // AGENT-PLATFORM (decision 111): handled by ChatsTabFlowCoordinator.
        case .feedPost, .feedNotices:
            break // AGENT-PLATFORM: feed (Brief 0082): handled by FeedTabFlowCoordinator.
        }
    }
    
    func clearRoute(animated: Bool) {
        childFlowCoordinator?.clearRoute(animated: animated)
        navigationStackCoordinator.setSheetCoordinator(nil, animated: animated)
        
        guard let initialCoordinator else {
            return
        }
        navigationStackCoordinator.pop(to: initialCoordinator, animated: animated)
    }
    
    private func configureStateMachine() {
        stateMachine.addRouteMapping { event, fromState, _ in
            switch (fromState, event) {
            case (.initial, .presentRoomMembersList):
                return .roomMembersList
                
            case (_, .presentRoomMemberDetails(let userID)):
                return .roomMemberDetails(userID: userID, previousState: fromState)
            case (.roomMemberDetails(_, let previousState), .dismissedRoomMemberDetails):
                return previousState
                
            case (.roomMembersList, .presentInviteUsersScreen):
                return .inviteUsersScreen
            case (.inviteUsersScreen, .dismissedInviteUsersScreen):
                return .roomMembersList
                
            case (.roomMemberDetails(_, let previousState), .presentUserProfile(let userID)):
                return .userProfile(userID: userID, previousState: previousState)
            case (.userProfile(_, let previousState), .dismissedUserProfile):
                return previousState
                
            case (_, .startRoomFlow(let roomID, _, _)):
                return .roomFlow(roomID: roomID, previousState: fromState)
            case (.roomFlow(_, let previousState), .stopRoomFlow):
                return previousState
                
            case (_, .startAgentRowFlow): // AGENT-PLATFORM (Brief 0083, question 359)
                return .agentRowFlow(previousState: fromState)
            case (.agentRowFlow(let previousState), .stopAgentRowFlow):
                return previousState
                
            default:
                return nil
            }
        }
        
        stateMachine.addAnyHandler(.any => .any) { [weak self] context in
            guard let self else { return }
            let animated = context.userInfo as? Bool ?? true
            switch (context.fromState, context.event, context.toState) {
            case (.initial, .presentRoomMembersList, .roomMembersList):
                presentRoomMembersList()
                
            case (_, .presentRoomMemberDetails, .roomMemberDetails(let userID, _)):
                presentRoomMemberDetails(userID: userID, animated: animated)
                
            case (.roomMemberDetails, .dismissedRoomMemberDetails, .initial):
                actionsSubject.send(.finished)
            case (.roomMemberDetails, .dismissedRoomMemberDetails, .roomMembersList):
                break
                
            case (.roomMembersList, .presentInviteUsersScreen, .inviteUsersScreen):
                presentInviteUsersScreen()
            case (.inviteUsersScreen, .dismissedInviteUsersScreen, .roomMembersList):
                break
                
            case (.roomMemberDetails, .presentUserProfile, .userProfile(let userID, _)):
                replaceRoomMemberDetailsWithUserProfile(userID: userID)
                
            case (.userProfile, .dismissedUserProfile, .initial):
                actionsSubject.send(.finished)
            case (.userProfile, .dismissedUserProfile, _):
                break
                
            case (_, .startRoomFlow(let roomID, let via, let eventID), .roomFlow):
                startRoomFlow(roomID: roomID, via: via, eventID: eventID, animated: animated)
            case (.roomFlow, .stopRoomFlow, _):
                childFlowCoordinator = nil
                
            case (_, .startAgentRowFlow(let row, let card), .agentRowFlow): // AGENT-PLATFORM (Brief 0083, question 359)
                startAgentRowFlow(row: row, card: card, animated: animated)
            case (.agentRowFlow, .stopAgentRowFlow, _):
                childFlowCoordinator = nil
                
            default:
                fatalError("Unhandled transition")
            }
        }
    }
    
    private func presentRoomMembersList() {
        let coordinator = RoomMembersListScreenCoordinator(parameters: .init(userSession: flowParameters.userSession,
                                                                             roomProxy: roomProxy,
                                                                             userIndicatorController: flowParameters.userIndicatorController,
                                                                             analytics: flowParameters.analytics))
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .invite:
                stateMachine.tryEvent(.presentInviteUsersScreen)
            case .selectedMember(let member):
                stateMachine.tryEvent(.presentRoomMemberDetails(userID: member.userID))
            }
        }
        .store(in: &cancellables)
        
        navigationStackCoordinator.push(coordinator) { [weak self] in
            self?.actionsSubject.send(.finished)
        }
    }
    
    private func presentRoomMemberDetails(userID: String, animated: Bool) {
        let params = RoomMemberDetailsScreenCoordinatorParameters(userID: userID,
                                                                  roomProxy: roomProxy,
                                                                  userSession: flowParameters.userSession,
                                                                  analytics: flowParameters.analytics,
                                                                  userIndicatorController: flowParameters.userIndicatorController)
        let coordinator = RoomMemberDetailsScreenCoordinator(parameters: params)
        
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .openUserProfile:
                stateMachine.tryEvent(.presentUserProfile(userID: userID))
            case .openDirectChat(let roomID):
                stateMachine.tryEvent(.startRoomFlow(roomID: roomID, via: [], eventID: nil))
            case .startCall(let roomProxy, let isVoiceCall):
                actionsSubject.send(.presentCallScreen(roomProxy: roomProxy, isVoiceCall: isVoiceCall))
            case .verifyUser(let userID):
                actionsSubject.send(.verifyUser(userID: userID))
            case .openAgentRow(let row, let card): // AGENT-PLATFORM (Brief 0083, question 359)
                stateMachine.tryEvent(.startAgentRowFlow(row: row, card: card))
            }
        }
        .store(in: &cancellables)
        
        navigationStackCoordinator.push(coordinator, animated: animated) { [weak self] in
            self?.stateMachine.tryEvent(.dismissedRoomMemberDetails)
        }
    }
    
    private func presentInviteUsersScreen() {
        let stackCoordinator = NavigationStackCoordinator()
        let inviteParameters = InviteUsersScreenCoordinatorParameters(userSession: flowParameters.userSession,
                                                                      roomType: .existingRoom(roomProxy: roomProxy),
                                                                      isSkippable: false,
                                                                      userDiscoveryService: UserDiscoveryService(clientProxy: flowParameters.userSession.clientProxy),
                                                                      userIndicatorController: flowParameters.userIndicatorController)
        
        let coordinator = InviteUsersScreenCoordinator(parameters: inviteParameters)
        stackCoordinator.setRootCoordinator(coordinator)
        
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .dismiss:
                navigationStackCoordinator.setSheetCoordinator(nil)
            case .openRoom:
                break
            }
        }
        .store(in: &cancellables)
        
        navigationStackCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissedInviteUsersScreen)
        }
    }
    
    private func replaceRoomMemberDetailsWithUserProfile(userID: String) {
        let parameters = UserProfileScreenCoordinatorParameters(userID: userID,
                                                                isPresentedModally: false,
                                                                userSession: flowParameters.userSession,
                                                                analytics: flowParameters.analytics,
                                                                userIndicatorController: flowParameters.userIndicatorController)
        let coordinator = UserProfileScreenCoordinator(parameters: parameters)
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .openDirectChat(let roomID):
                stateMachine.tryEvent(.startRoomFlow(roomID: roomID, via: [], eventID: nil))
            case .startCall(let roomProxy, let isVoiceCall):
                actionsSubject.send(.presentCallScreen(roomProxy: roomProxy, isVoiceCall: isVoiceCall))
            case .dismiss:
                break // Not supported when pushed.
            case .openAgentRow(let row, let card): // AGENT-PLATFORM (Brief 0083, question 359)
                stateMachine.tryEvent(.startAgentRowFlow(row: row, card: card))
            }
        }
        .store(in: &cancellables)
        
        // Replace the RoomMemberDetailsScreen without any animation.
        // If this pop and push happens before the previous navigation is completed it might break screen presentation logic
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) { [self] in
            navigationStackCoordinator.pop(animated: false)
            navigationStackCoordinator.push(coordinator, animated: false) { [weak self] in
                self?.stateMachine.tryEvent(.dismissedUserProfile)
            }
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, question 359)
    private func startAgentRowFlow(row: AgentPageRow, card: AgentSpaceAgentCard, animated: Bool) {
        guard let coordinator = AgentRowFlowCoordinator(row: row,
                                                        card: card,
                                                        navigationStackCoordinator: navigationStackCoordinator,
                                                        flowParameters: flowParameters,
                                                        showOriginRoom: showOriginRoom) else {
            MXLog.warning("RoomMembersFlowCoordinator: no agent platform: cannot open an agent's row")
            flowParameters.userIndicatorController.submitIndicator(.init(title: L10n.errorUnknown))
            stateMachine.tryEvent(.stopAgentRowFlow)
            return
        }
        
        coordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .finished:
                    stateMachine.tryEvent(.stopAgentRowFlow)
                case .presentCallScreen(let roomProxy, let isVoiceCall):
                    actionsSubject.send(.presentCallScreen(roomProxy: roomProxy, isVoiceCall: isVoiceCall))
                case .presentAIConsentSettings:
                    actionsSubject.send(.presentAIConsentSettings)
                case .presentAgentsTab: // AGENT-PLATFORM (question 412)
                    actionsSubject.send(.presentAgentsTab)
                case .verifyUser(let userID):
                    actionsSubject.send(.verifyUser(userID: userID))
                }
            }
            .store(in: &cancellables)
        
        childFlowCoordinator = coordinator
        coordinator.start(animated: animated)
    }
    
    private func startRoomFlow(roomID: String, via: [String], eventID: String?, animated: Bool) {
        let coordinator = RoomFlowCoordinator(roomID: roomID,
                                              isChildFlow: true,
                                              navigationStackCoordinator: navigationStackCoordinator,
                                              flowParameters: flowParameters)
        coordinator.actions
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .presentCallScreen(let roomProxy, let isVoiceCall):
                    actionsSubject.send(.presentCallScreen(roomProxy: roomProxy, isVoiceCall: isVoiceCall))
                case .presentAIConsentSettings: // AGENT-PLATFORM (decision 150)
                    actionsSubject.send(.presentAIConsentSettings)
                case .presentAgentsTab: // AGENT-PLATFORM (question 412)
                    actionsSubject.send(.presentAgentsTab)
                case .verifyUser(let userID):
                    actionsSubject.send(.verifyUser(userID: userID))
                case .continueWithSpaceFlow:
                    fatalError("Will never trigger because only direct chats can be displayed in this flow")
                case .finished:
                    stateMachine.tryEvent(.stopRoomFlow)
                }
            }
            .store(in: &cancellables)
        
        childFlowCoordinator = coordinator
        if let eventID {
            coordinator.handleAppRoute(.event(eventID: eventID, roomID: roomID, via: via), animated: animated)
        } else {
            coordinator.handleAppRoute(.room(roomID: roomID, via: via), animated: animated)
        }
    }
}
