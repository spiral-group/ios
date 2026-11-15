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
// edit, activity, usage and «В чат». With a `pushedRow` (question 359) it starts
// at one of the owner's entries of the agent's page, on that page's stack: a row,
// or the agent's screen itself for the chat's Settings (question 391).
enum AgentFlowCoordinatorAction {
    /// The agent's screen was popped — the parent tidies its state.
    case finished
    /// Something the tab's list shows changed (a save, a chat, an archive).
    case changed
    case openDM(matrixUserID: String)
    /// From a chat opened on this agent's stack (an activity row's).
    case presentCallScreen(roomProxy: JoinedRoomProxyProtocol, isVoiceCall: Bool)
    case presentAIConsentSettings
    /// The Agents tab, where the person's agent is or will be (question 412).
    case presentAgentsTab
    case verifyUser(userID: String)
}

class AgentFlowCoordinator: FlowCoordinatorProtocol {
    private let selection: AgentSelection
    private let agentPlatformService: AgentPlatformServiceProtocol
    /// AGENT-PLATFORM: platform sync (decision 289): the screens render from it.
    private let agentsStore: AgentsStore
    private let navigationStackCoordinator: NavigationStackCoordinator
    private let flowParameters: CommonFlowParameters
    /// The entry this flow was pushed for; `nil` for the agent's screen as the stack's root.
    private let pushedRow: AgentPageRow?
    /// Where a pushed flow's stack stood when it started.
    private let initialCoordinator: CoordinatorProtocol?
    /// Brings the chat this flow was pushed from back to the front when asked for its room, and says whether it did.
    /// From a profile's sheet it takes every chat, which opens in Chats rather than inside the sheet (end-stage review,
    /// 2026-11-14). `nil` when the flow didn't start in a chat, which has nothing to return to.
    private let showOriginRoom: ((_ roomID: String) -> Bool)?

    private var agent: AgentSpaceAgentCard {
        selection.card
    }

    private weak var agentDetailScreenCoordinator: AgentDetailScreenCoordinator?
    private weak var agentChatsScreenCoordinator: AgentChatsScreenCoordinator?
    private weak var agentInRoomScreenCoordinator: AgentInRoomScreenCoordinator?
    private weak var armToolCoordinator: ArmToolScreenCoordinator?
    // periphery:ignore - retaining purpose
    private var roomFlowCoordinator: RoomFlowCoordinator?

    enum State: StateType {
        /// The state machine hasn't started.
        case initial
        /// The flow's first screen: the agent's, or the row it was pushed for.
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
         agentsStore: AgentsStore,
         navigationStackCoordinator: NavigationStackCoordinator,
         flowParameters: CommonFlowParameters,
         pushedRow: AgentPageRow? = nil,
         showOriginRoom: ((_ roomID: String) -> Bool)? = nil) {
        self.selection = selection
        self.agentPlatformService = agentPlatformService
        self.agentsStore = agentsStore
        self.navigationStackCoordinator = navigationStackCoordinator
        self.flowParameters = flowParameters
        self.pushedRow = pushedRow
        self.showOriginRoom = showOriginRoom
        initialCoordinator = navigationStackCoordinator.stackCoordinators.last ?? navigationStackCoordinator.rootCoordinator

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
        guard pushedRow != nil else {
            navigationStackCoordinator.popToRoot(animated: animated)
            return
        }
        roomFlowCoordinator?.clearRoute(animated: animated)
        if let initialCoordinator {
            navigationStackCoordinator.pop(to: initialCoordinator, animated: animated)
        }
    }

    // MARK: - Private

    private func configureStateMachine() {
        stateMachine.addRoutes(event: .start, transitions: [.initial => .agentDetail]) { [weak self] _ in
            self?.presentFirstScreen()
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
            self?.agentChatsScreenCoordinator?.reload()
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

    private func presentFirstScreen() {
        let finished: () -> Void = { [weak self] in self?.actionsSubject.send(.finished) }
        switch pushedRow {
        case nil:
            presentAgentDetail()
        case .activity:
            pushAgentActivity(filter: .all, dismissalCallback: finished)
        case .usage:
            pushAgentUsage(dismissalCallback: finished)
        case .chats:
            pushAgentChats(dismissalCallback: finished)
        case .settings:
            presentAgentDetail()
        }
    }

    private func presentAgentDetail() {
        let parameters = AgentDetailScreenCoordinatorParameters(selection: selection,
                                                                agentPlatformService: agentPlatformService,
                                                                clientProxy: flowParameters.userSession.clientProxy,
                                                                mediaProvider: flowParameters.userSession.mediaProvider,
                                                                userIndicatorController: flowParameters.userIndicatorController,
                                                                store: agentsStore)
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
                    if pushedRow == nil {
                        actionsSubject.send(.openDM(matrixUserID: agent.matrixUserID))
                    } else {
                        openDM()
                    }
                case .addToChat(let agentRoomIDs):
                    presentRoomPicker(agentRoomIDs: agentRoomIDs)
                case .addedToChat:
                    actionsSubject.send(.changed)
                case .archived, .gone:
                    actionsSubject.send(.changed)
                    // Taking the screen away ends the flow (its dismissal sends `.finished`).
                    if pushedRow == nil {
                        navigationStackCoordinator.setRootCoordinator(nil)
                    } else if let initialCoordinator {
                        navigationStackCoordinator.pop(to: initialCoordinator)
                    }
                }
            }
            .store(in: &cancellables)

        agentDetailScreenCoordinator = coordinator

        let finished: () -> Void = { [weak self] in self?.actionsSubject.send(.finished) }
        if pushedRow == nil {
            navigationStackCoordinator.setRootCoordinator(coordinator, dismissalCallback: finished)
        } else {
            navigationStackCoordinator.push(coordinator, dismissalCallback: finished)
        }
    }

    /// Message on a pushed agent's screen: the agent's DM, which goes back to it when this flow started there.
    private func openDM() {
        guard case .success(let roomID?) = flowParameters.userSession.clientProxy.directRoomForUserID(agent.matrixUserID) else {
            MXLog.error("No DM with \(agent.matrixUserID) to open from its pushed screen")
            return
        }
        openChat(roomID: roomID)
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
                                                                           store: agentsStore,
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
                                                                          store: agentsStore,
                                                                          userIndicatorController: flowParameters.userIndicatorController))
        navigationStackCoordinator.push(coordinator) { [weak self] in
            self?.agentDetailScreenCoordinator?.reload()
        }
    }
    
    /// Activity: a row opens its chat or its approval (G5). «Ждут вашего
    /// решения» opens it on that filter.
    private func pushAgentActivity(filter: ActionOutcomeFilter, dismissalCallback: (() -> Void)? = nil) {
        let coordinator = AgentActivityScreenCoordinator(parameters: .init(agentID: agent.agentID,
                                                                           initialFilter: filter,
                                                                           store: agentsStore,
                                                                           clientProxy: flowParameters.userSession.clientProxy))
        coordinator.actionsPublisher
            .sink { [weak self] (action: AgentActivityScreenCoordinatorAction) in
                guard let self else { return }
                switch action {
                case .openRoom(let roomID):
                    openChat(roomID: roomID)
                case .openApproval(let approvalID):
                    pushApprovalDetail(approvalID: approvalID)
                }
            }
            .store(in: &cancellables)
        navigationStackCoordinator.push(coordinator, dismissalCallback: dismissalCallback)
    }

    /// «Open chat» of the agent in one chat. A chat this flow started from is shown by that chat's own flow, so it isn't
    /// stacked twice; any other opens as an activity row's does.
    func openChat(roomID: String) {
        if showOriginRoom?(roomID) == true {
            return
        }
        openRoom(roomID: roomID)
    }
    
    /// An activity row's chat, pushed on this stack as the Spaces tab pushes
    /// a space's room, so back returns to the activity rather than leaving
    /// the owner on the Chats tab with the Agents stack behind.
    func openRoom(roomID: String) {
        // A second tap on a cold room would start a second flow, and push the room twice.
        guard roomFlowCoordinator == nil else {
            MXLog.info("A chat is already opening on the agent's stack")
            return
        }
        
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
                case .presentAgentsTab: // AGENT-PLATFORM (question 412)
                    actionsSubject.send(.presentAgentsTab)
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
    private func pushAgentUsage(dismissalCallback: (() -> Void)? = nil) {
        let coordinator = AgentUsageScreenCoordinator(parameters: .init(agentID: agent.agentID,
                                                                        store: agentsStore))
        navigationStackCoordinator.push(coordinator, dismissalCallback: dismissalCallback)
    }

    /// The agent's chats on a screen of their own, from its page (question 359).
    private func pushAgentChats(dismissalCallback: @escaping () -> Void) {
        let coordinator = AgentChatsScreenCoordinator(parameters: .init(agent: agent,
                                                                        clientProxy: flowParameters.userSession.clientProxy,
                                                                        store: agentsStore))
        coordinator.actionsPublisher
            .sink { [weak self] (action: AgentChatsScreenCoordinatorAction) in
                guard let self else { return }
                switch action {
                case .selectRoom(let room):
                    stateMachine.tryEvent(.selectRoom, userInfo: room)
                case .gone:
                    actionsSubject.send(.changed)
                    navigationStackCoordinator.pop()
                }
            }
            .store(in: &cancellables)

        agentChatsScreenCoordinator = coordinator
        navigationStackCoordinator.push(coordinator, dismissalCallback: dismissalCallback)
    }

    /// Outreach queue (company outreach role only): list + the add-targets push.
    private func pushOutreachQueue() {
        let coordinator = OutreachQueueListScreenCoordinator(parameters: .init(agentID: agent.agentID,
                                                                               store: agentsStore))
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
                                                              store: agentsStore,
                                                              userSession: flowParameters.userSession,
                                                              navigationStackCoordinator: navigationStackCoordinator,
                                                              userIndicatorController: flowParameters.userIndicatorController,
                                                              orientationManager: flowParameters.appMediator.windowManager)
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
                case .openChat(let roomID):
                    openChat(roomID: roomID)
                case .removed:
                    // The pop's completion fires .deselectRoom, which reloads the agent.
                    actionsSubject.send(.changed)
                    navigationStackCoordinator.pop()
                case .addTool:
                    pushAddTool(room: room)
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

    private func pushAddTool(room: AgentRoomEntry) {
        let coordinator = AddToolScreenCoordinator(parameters: .init(roomID: room.roomID,
                                                                     agentID: agent.agentID,
                                                                     agentDisplayName: agent.displayName,
                                                                     store: agentsStore))
        coordinator.actionsPublisher
            .sink { [weak self] (action: AddToolScreenCoordinatorAction) in
                switch action {
                case .selectKind(let kind):
                    self?.pushArmTool(room: room, mode: .create(kind))
                }
            }
            .store(in: &cancellables)

        navigationStackCoordinator.push(coordinator) { [weak self] in
            // Tools may have changed — refresh the chat screen under us.
            self?.agentInRoomScreenCoordinator?.reload()
        }
    }

    private func pushArmTool(room: AgentRoomEntry, mode: ArmToolScreenCoordinatorParameters.Mode) {
        // Call translation is personal (ADR-0094 D9, row 14): its own screen, as from the chat's Tools.
        guard !mode.isCallTranslation else {
            let coordinator = CallTranslationToolScreenCoordinator(parameters: .init(roomID: room.roomID,
                                                                                     agentID: agent.agentID,
                                                                                     agentDisplayName: agent.displayName,
                                                                                     agentPlatformService: agentPlatformService))
            navigationStackCoordinator.push(coordinator) { [weak self] in
                self?.agentInRoomScreenCoordinator?.reload()
            }
            return
        }
        guard let coordinator = ArmToolScreenCoordinator(parameters: .init(roomID: room.roomID,
                                                                           agentID: agent.agentID,
                                                                           agentDisplayName: agent.displayName,
                                                                           mode: mode,
                                                                           agentPlatformService: agentPlatformService,
                                                                           store: agentsStore)) else { return }
        coordinator.actionsPublisher
            .sink { [weak self] (action: ArmToolScreenCoordinatorAction) in
                guard let self else { return }
                switch action {
                case .finished:
                    // Back to the chat screen, past the kinds when there were any.
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
