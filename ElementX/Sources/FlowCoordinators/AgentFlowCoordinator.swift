//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
import SwiftState

// AGENT-PLATFORM: Brief 0037, reworked by the Agents tab step B (decision
// 191). One instance per opened agent, rooted at the agent's screen on the
// tab's detail stack: its chats, the agent in one chat with its tools, the
// edit, activity, usage and «В чат».
enum AgentFlowCoordinatorAction {
    /// The agent's screen was popped — the parent tidies its state.
    case finished
    /// Something the tab's list shows changed (a save, a chat, an archive).
    case changed
    case openDM(matrixUserID: String)
    /// From a chat opened on this agent's stack (an activity row's).
    case presentCallScreen(roomProxy: JoinedRoomProxyProtocol, isVoiceCall: Bool)
    case presentAIConsentSettings
    case verifyUser(userID: String)
}

class AgentFlowCoordinator: FlowCoordinatorProtocol {
    private let selection: AgentSelection
    private let agentPlatformService: AgentPlatformServiceProtocol
    private let navigationStackCoordinator: NavigationStackCoordinator
    private let flowParameters: CommonFlowParameters

    private var agent: AgentSpaceAgentCard {
        selection.card
    }

    private weak var agentDetailScreenCoordinator: AgentDetailScreenCoordinator?
    private weak var agentInRoomScreenCoordinator: AgentInRoomScreenCoordinator?
    private weak var armToolCoordinator: ArmToolScreenCoordinator?
    // periphery:ignore - retaining purpose
    private var roomFlowCoordinator: RoomFlowCoordinator?

    enum State: StateType {
        /// The state machine hasn't started.
        case initial
        /// The agent's screen, the flow's root.
        case agentDetail
        /// The agent in one chat is pushed.
        case agentInRoom
        /// The edit is pushed.
        case agentEdit
    }

    enum Event: EventType {
        /// The flow is being started.
        case start
        /// Push the agent in one chat. An `AgentRoomEntry` must be provided in the `userInfo`.
        case selectRoom
        /// The agent-in-chat screen has been popped.
        case deselectRoom
        /// Push the edit.
        case editAgent
        /// The edit has been popped.
        case dismissedEditAgent
    }

    private let stateMachine: StateMachine<State, Event>
    private var cancellables: Set<AnyCancellable> = []

    private let actionsSubject: PassthroughSubject<AgentFlowCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentFlowCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(selection: AgentSelection,
         agentPlatformService: AgentPlatformServiceProtocol,
         navigationStackCoordinator: NavigationStackCoordinator,
         flowParameters: CommonFlowParameters) {
        self.selection = selection
        self.agentPlatformService = agentPlatformService
        self.navigationStackCoordinator = navigationStackCoordinator
        self.flowParameters = flowParameters

        stateMachine = .init(state: .initial)
        configureStateMachine()
    }

    func start(animated: Bool) {
        stateMachine.tryEvent(.start)
    }

    func handleAppRoute(_ appRoute: AppRoute, animated: Bool) {
        clearRoute(animated: animated)
    }

    func clearRoute(animated: Bool) {
        navigationStackCoordinator.popToRoot(animated: animated)
    }

    // MARK: - Private

    private func configureStateMachine() {
        stateMachine.addRoutes(event: .start, transitions: [.initial => .agentDetail]) { [weak self] _ in
            self?.presentAgentDetail()
        }

        stateMachine.addRouteMapping { event, fromState, userInfo in
            guard event == .selectRoom, case .agentDetail = fromState else { return nil }
            guard userInfo is AgentRoomEntry else { fatalError("A room must be provided.") }
            return .agentInRoom
        } handler: { [weak self] context in
            guard let self, let room = context.userInfo as? AgentRoomEntry else { return }
            presentAgentInRoom(room: room)
        }

        stateMachine.addRoutes(event: .deselectRoom, transitions: [.agentInRoom => .agentDetail]) { [weak self] _ in
            // The agent's chats may have changed (tools, remove-from-chat).
            self?.agentDetailScreenCoordinator?.reload()
        }

        stateMachine.addRoutes(event: .editAgent, transitions: [.agentDetail => .agentEdit]) { [weak self] _ in
            self?.presentAgentEdit()
        }

        stateMachine.addRoutes(event: .dismissedEditAgent, transitions: [.agentEdit => .agentDetail]) { [weak self] _ in
            self?.agentDetailScreenCoordinator?.reload()
        }

        stateMachine.addErrorHandler { context in
            fatalError("Unexpected transition: \(context)")
        }
    }

    private func presentAgentDetail() {
        let parameters = AgentDetailScreenCoordinatorParameters(selection: selection,
                                                                agentPlatformService: agentPlatformService,
                                                                clientProxy: flowParameters.userSession.clientProxy,
                                                                mediaProvider: flowParameters.userSession.mediaProvider,
                                                                userIndicatorController: flowParameters.userIndicatorController,
                                                                approvalsStreamService: flowParameters.userSession.approvalsStreamService)
        let coordinator = AgentDetailScreenCoordinator(parameters: parameters)

        coordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .selectRoom(let room):
                    stateMachine.tryEvent(.selectRoom, userInfo: room)
                case .showEdit:
                    stateMachine.tryEvent(.editAgent)
                case .showVerification(let id):
                    pushVerificationDetail(verificationID: id)
                case .showActivity:
                    pushAgentActivity(filter: .all)
                case .showPendingApprovals:
                    pushAgentActivity(filter: .pendingConsent)
                case .showSettings(let section):
                    pushSettings(section: section)
                case .showBlocked:
                    pushBlockedUsers()
                case .changed:
                    actionsSubject.send(.changed)
                case .showUsage:
                    pushAgentUsage()
                case .showQueue:
                    pushOutreachQueue()
                case .message:
                    actionsSubject.send(.openDM(matrixUserID: agent.matrixUserID))
                case .addToChat(let agentRoomIDs):
                    presentRoomPicker(agentRoomIDs: agentRoomIDs)
                case .addedToChat:
                    actionsSubject.send(.changed)
                case .archived:
                    actionsSubject.send(.changed)
                    // Removing the root ends the flow (its dismissal sends `.finished`).
                    navigationStackCoordinator.setRootCoordinator(nil)
                }
            }
            .store(in: &cancellables)

        agentDetailScreenCoordinator = coordinator

        navigationStackCoordinator.setRootCoordinator(coordinator) { [weak self] in
            self?.actionsSubject.send(.finished)
        }
    }

    // MARK: «В чат»

    /// The app's chat picker, offering only chats the agent can usefully
    /// join; the chosen chat gets the agent (invite, then the agent accepts
    /// — ADR-0017).
    private func presentRoomPicker(agentRoomIDs: Set<String>) {
        let stackCoordinator = NavigationStackCoordinator()
        let agentUserID = agent.matrixUserID
        let coordinator = RoomSelectionScreenCoordinator(parameters: .init(userSession: flowParameters.userSession,
                                                                           roomSummaryProvider: flowParameters.userSession.clientProxy.alternateRoomSummaryProvider,
                                                                           confirmTitle: UntranslatedL10n.actionAddAgentToChat,
                                                                           roomFilter: { $0.canTakeAgent(matrixUserID: agentUserID, agentRoomIDs: agentRoomIDs) },
                                                                           emptyState: .init(title: UntranslatedL10n.screenAgentDetailAddToChatEmptyTitle,
                                                                                             message: UntranslatedL10n.screenAgentDetailAddToChatEmptyMessage)))
        coordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .dismiss:
                    navigationStackCoordinator.setSheetCoordinator(nil)
                case .confirm(let roomID):
                    navigationStackCoordinator.setSheetCoordinator(nil)
                    agentDetailScreenCoordinator?.addToChat(roomID: roomID)
                }
            }
            .store(in: &cancellables)

        stackCoordinator.setRootCoordinator(coordinator)
        navigationStackCoordinator.setSheetCoordinator(stackCoordinator)
    }

    // MARK: Pushes

    /// Verification decide screen — the banner's destination. On pop the
    /// detail's reload clears the banner if the request was decided.
    private func pushVerificationDetail(verificationID: String) {
        let coordinator = VerificationDetailScreenCoordinator(parameters: .init(verificationID: verificationID,
                                                                                agentPlatformService: agentPlatformService))
        coordinator.actionsPublisher
            .sink { [weak self] (action: VerificationDetailScreenCoordinatorAction) in
                switch action {
                case .dismiss:
                    self?.navigationStackCoordinator.pop()
                }
            }
            .store(in: &cancellables)

        navigationStackCoordinator.push(coordinator) { [weak self] in
            self?.agentDetailScreenCoordinator?.reload()
        }
    }

    /// One of «Настройки» (decision 194).
    private func pushSettings(section: AgentSettingsSection) {
        let coordinator = AgentSettingsScreenCoordinator(parameters: .init(agent: agent,
                                                                           section: section,
                                                                           agentPlatformService: agentPlatformService,
                                                                           userIndicatorController: flowParameters.userIndicatorController))
        coordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .changed:
                    actionsSubject.send(.changed)
                case .dismiss:
                    navigationStackCoordinator.pop()
                }
            }
            .store(in: &cancellables)
        navigationStackCoordinator.push(coordinator) { [weak self] in
            self?.agentDetailScreenCoordinator?.reload()
        }
    }
    
    /// «Заблокированные»: the people this agent blocks (decision 194).
    private func pushBlockedUsers() {
        let coordinator = AgentBlockedScreenCoordinator(parameters: .init(agent: agent,
                                                                          agentPlatformService: agentPlatformService,
                                                                          userIndicatorController: flowParameters.userIndicatorController))
        navigationStackCoordinator.push(coordinator) { [weak self] in
            self?.agentDetailScreenCoordinator?.reload()
        }
    }
    
    /// Activity: a row opens its chat or its approval (G5). «Ждут вашего
    /// решения» opens it on that filter.
    private func pushAgentActivity(filter: ActionOutcomeFilter) {
        let coordinator = AgentActivityScreenCoordinator(parameters: .init(agentID: agent.agentID,
                                                                           initialFilter: filter,
                                                                           agentPlatformService: agentPlatformService,
                                                                           clientProxy: flowParameters.userSession.clientProxy))
        coordinator.actionsPublisher
            .sink { [weak self] (action: AgentActivityScreenCoordinatorAction) in
                guard let self else { return }
                switch action {
                case .openRoom(let roomID):
                    openRoom(roomID: roomID)
                case .openApproval(let approvalID):
                    pushApprovalDetail(approvalID: approvalID)
                }
            }
            .store(in: &cancellables)
        navigationStackCoordinator.push(coordinator)
    }

    /// An activity row's chat, pushed on this stack as the Spaces tab pushes
    /// a space's room, so back returns to the activity rather than leaving
    /// the owner on the Chats tab with the Agents stack behind.
    func openRoom(roomID: String) {
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
                case .presentAIConsentSettings:
                    actionsSubject.send(.presentAIConsentSettings)
                case .verifyUser(let userID):
                    actionsSubject.send(.verifyUser(userID: userID))
                case .continueWithSpaceFlow:
                    // An agent acts in chats, never in a space; nothing to continue.
                    MXLog.error("An activity row's room \(roomID) is a space")
                    roomFlowCoordinator = nil
                case .finished:
                    roomFlowCoordinator = nil
                }
            }
            .store(in: &cancellables)
        
        roomFlowCoordinator = coordinator
        coordinator.handleAppRoute(.room(roomID: roomID, via: []), animated: true)
    }

    private func pushApprovalDetail(approvalID: String) {
        let coordinator = ApprovalDetailScreenCoordinator(parameters: .init(approvalID: approvalID,
                                                                            agentPlatformService: agentPlatformService,
                                                                            clientProxy: flowParameters.userSession.clientProxy))
        coordinator.actionsPublisher
            .sink { [weak self] (action: ApprovalDetailScreenCoordinatorAction) in
                switch action {
                case .dismiss:
                    self?.navigationStackCoordinator.pop()
                }
            }
            .store(in: &cancellables)
        navigationStackCoordinator.push(coordinator)
    }

    /// The agent's AI use against its daily limit (Brief 0079 3c).
    private func pushAgentUsage() {
        let coordinator = AgentUsageScreenCoordinator(parameters: .init(agentID: agent.agentID,
                                                                        agentPlatformService: agentPlatformService))
        navigationStackCoordinator.push(coordinator)
    }

    /// Outreach queue (company outreach role only): list + the add-targets push.
    private func pushOutreachQueue() {
        let coordinator = OutreachQueueListScreenCoordinator(parameters: .init(agentID: agent.agentID,
                                                                               agentPlatformService: agentPlatformService))
        coordinator.actionsPublisher
            .sink { [weak self] (action: OutreachQueueListScreenCoordinatorAction) in
                switch action {
                case .presentAddTargets(let agentID):
                    self?.pushOutreachQueueAdd(agentID: agentID)
                case .dismiss:
                    self?.navigationStackCoordinator.pop()
                }
            }
            .store(in: &cancellables)
        navigationStackCoordinator.push(coordinator)
    }

    private func pushOutreachQueueAdd(agentID: String) {
        let coordinator = OutreachQueueAddScreenCoordinator(parameters: .init(agentID: agentID,
                                                                              agentPlatformService: agentPlatformService))
        coordinator.actionsPublisher
            .sink { [weak self] (action: OutreachQueueAddScreenCoordinatorAction) in
                switch action {
                case .enqueued, .dismiss:
                    self?.navigationStackCoordinator.pop()
                }
            }
            .store(in: &cancellables)
        navigationStackCoordinator.push(coordinator)
    }

    // MARK: Edit

    /// Pushed, the shape of «Изменить профиль» (step B.3).
    private func presentAgentEdit() {
        let parameters = AgentEditScreenCoordinatorParameters(agent: agent,
                                                              agentPlatformService: agentPlatformService,
                                                              userSession: flowParameters.userSession,
                                                              navigationStackCoordinator: navigationStackCoordinator,
                                                              userIndicatorController: flowParameters.userIndicatorController,
                                                              orientationManager: flowParameters.appMediator.windowManager,
                                                              appSettings: flowParameters.appSettings)
        let coordinator = AgentEditScreenCoordinator(parameters: parameters)

        coordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .saved:
                    actionsSubject.send(.changed)
                    navigationStackCoordinator.pop()
                case .cancel:
                    navigationStackCoordinator.pop()
                }
            }
            .store(in: &cancellables)

        navigationStackCoordinator.push(coordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissedEditAgent)
        }
    }

    // MARK: The agent in one chat

    private func presentAgentInRoom(room: AgentRoomEntry) {
        let parameters = AgentInRoomScreenCoordinatorParameters(agent: .init(card: agent),
                                                                room: room,
                                                                agentPlatformService: agentPlatformService,
                                                                clientProxy: flowParameters.userSession.clientProxy,
                                                                mediaProvider: flowParameters.userSession.mediaProvider)
        let coordinator = AgentInRoomScreenCoordinator(parameters: parameters)

        coordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .removed:
                    // The pop's completion fires .deselectRoom, which reloads the agent.
                    actionsSubject.send(.changed)
                    navigationStackCoordinator.pop()
                case .addTool:
                    pushCapabilitiesCatalog(room: room)
                case .editTool(let detail):
                    pushArmTool(room: room, mode: .edit(detail))
                }
            }
            .store(in: &cancellables)

        agentInRoomScreenCoordinator = coordinator

        navigationStackCoordinator.push(coordinator) { [weak self] in
            self?.stateMachine.tryEvent(.deselectRoom)
        }
    }

    // MARK: Tools — the Brief 0036 arm flow on roomID + agentID, so it works
    // for chats the owner isn't in (a visitor's DM). The member picker is the
    // one step that needs the owner in the chat.

    private func pushCapabilitiesCatalog(room: AgentRoomEntry) {
        let coordinator = AgentCapabilitiesScreenCoordinator(parameters: .init(roomID: room.roomID,
                                                                               agentID: agent.agentID,
                                                                               agentDisplayName: agent.displayName,
                                                                               agentPlatformService: agentPlatformService,
                                                                               showsDoneButton: false))
        coordinator.actionsPublisher
            .sink { [weak self] (action: AgentCapabilitiesScreenCoordinatorAction) in
                switch action {
                case .presentArmTool(let capability, let active):
                    self?.pushArmTool(room: room, mode: .create(capability: capability, active: active))
                case .dismiss:
                    self?.navigationStackCoordinator.pop()
                }
            }
            .store(in: &cancellables)

        navigationStackCoordinator.push(coordinator) { [weak self] in
            // Tools may have changed — refresh the chat screen under us.
            self?.agentInRoomScreenCoordinator?.reload()
        }
    }

    private func pushArmTool(room: AgentRoomEntry, mode: ArmToolScreenCoordinatorParameters.Mode) {
        let coordinator = ArmToolScreenCoordinator(parameters: .init(roomID: room.roomID,
                                                                     agentID: agent.agentID,
                                                                     agentDisplayName: agent.displayName,
                                                                     mode: mode,
                                                                     agentPlatformService: agentPlatformService))
        coordinator.actionsPublisher
            .sink { [weak self] (action: ArmToolScreenCoordinatorAction) in
                guard let self else { return }
                switch action {
                case .finished:
                    // Back to the chat screen, past the catalog when there was one.
                    if let agentInRoomScreenCoordinator {
                        navigationStackCoordinator.pop(to: agentInRoomScreenCoordinator)
                    } else {
                        navigationStackCoordinator.pop()
                    }
                    agentInRoomScreenCoordinator?.reload()
                case .selectMembers(let current):
                    pushToolMemberPicker(room: room, current: current)
                case .selectLanguage(let languages, let current):
                    pushLanguagePicker(languages: languages, current: current)
                }
            }
            .store(in: &cancellables)

        armToolCoordinator = coordinator
        navigationStackCoordinator.push(coordinator)
    }

    private func pushToolMemberPicker(room: AgentRoomEntry, current: [String]) {
        Task { [weak self] in
            guard let self else { return }
            await pushToolMemberPickerResolved(room: room, current: current)
        }
    }

    private func pushToolMemberPickerResolved(room: AgentRoomEntry, current: [String]) async {
        // The picker needs the member list, which this device has only when
        // the owner is in the chat.
        guard case .joined(let roomProxy) = await flowParameters.userSession.clientProxy.roomForIdentifier(room.roomID) else {
            flowParameters.userIndicatorController.submitIndicator(
                UserIndicator(id: "agent-member-picker-unavailable",
                              type: .toast,
                              title: UntranslatedL10n.screenAgentInRoomMemberPickerUnavailable,
                              icon: \.info))
            return
        }

        let coordinator = ToolMemberPickerScreenCoordinator(parameters: .init(roomProxy: roomProxy,
                                                                              agentMatrixUserID: agent.matrixUserID,
                                                                              preselectedMemberIDs: current,
                                                                              mediaProvider: flowParameters.userSession.mediaProvider))
        coordinator.actionsPublisher
            .sink { [weak self] (action: ToolMemberPickerScreenCoordinatorAction) in
                switch action {
                case .confirm(let members):
                    self?.armToolCoordinator?.applyMemberSelection(members)
                    self?.navigationStackCoordinator.pop()
                }
            }
            .store(in: &cancellables)

        navigationStackCoordinator.push(coordinator)
    }

    private func pushLanguagePicker(languages: [AgentLanguage], current: String) {
        let coordinator = LanguagePickerScreenCoordinator(parameters: .init(languages: languages, selectedCode: current))
        coordinator.actionsPublisher
            .sink { [weak self] (action: LanguagePickerScreenCoordinatorAction) in
                switch action {
                case .selected(let code):
                    self?.armToolCoordinator?.applyLanguageSelection(code)
                    self?.navigationStackCoordinator.pop()
                }
            }
            .store(in: &cancellables)

        navigationStackCoordinator.push(coordinator)
    }
}
