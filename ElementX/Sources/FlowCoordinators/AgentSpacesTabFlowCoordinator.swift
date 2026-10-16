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
// 191). The literal sibling of `SpacesTabFlowCoordinator`: same split
// shell and state-machine shape. The root lists every space with its
// agents; an agent opens its own flow on the detail stack. Company
// create/edit and new role agents are sheets over the split.
enum AgentSpacesTabFlowCoordinatorAction {
    /// The user tapped their avatar — same affordance as the Chats and
    /// Spaces tabs; the parent presents the settings flow.
    case showSettings
    /// The owner asked to open a DM with one of their agents. Handled
    /// by the parent because the Agents tab knows nothing about Chats.
    case openDMWithAgent(matrixUserID: String)
    /// A visitor's chat from the hub, opened on the Chats tab.
    case openRoom(roomID: String)
    /// From a chat opened on an agent's stack.
    case presentCallScreen(roomProxy: JoinedRoomProxyProtocol, isVoiceCall: Bool)
    case presentAIConsentSettings
    case verifyUser(userID: String)
}

class AgentSpacesTabFlowCoordinator: FlowCoordinatorProtocol {
    private let flowParameters: CommonFlowParameters
    private let navigationSplitCoordinator: NavigationSplitCoordinator
    private let sidebarNavigationStackCoordinator: NavigationStackCoordinator
    private let detailNavigationStackCoordinator: NavigationStackCoordinator
    
    // periphery:ignore - retaining purpose
    private var agentFlowCoordinator: AgentFlowCoordinator?
    private weak var agentSpacesScreenCoordinator: AgentSpacesScreenCoordinator?
    
    enum State: StateType {
        /// The state machine hasn't started.
        case initial
        /// The root screen for this flow.
        case agentSpacesScreen(selectedAgentID: String?)
        /// The create-company sheet is presented (artboard 0037-H). On iPad
        /// the agent beside it stays open.
        case createCompanyFlow(selectedAgentID: String?)
        /// The notifications hub is pushed (the bell; Brief 0041 D4).
        case notificationsHub(selectedAgentID: String?)
    }
    
    enum Event: EventType {
        /// The flow is being started.
        case start
        /// Request presentation for a particular agent.
        ///
        /// An `AgentSelection` must be provided in the `userInfo`.
        case selectAgent
        /// The agent's flow has been dismissed.
        case deselectAgent
        /// Present the create-company sheet.
        case startCreateCompanyFlow
        /// The create-company sheet was dismissed.
        case dismissedCreateCompanyFlow
        /// Push the notifications hub (bell tap or notification deep-link).
        case openNotificationsHub
        /// The notifications hub was popped.
        case popNotificationsHub
    }
    
    private let stateMachine: StateMachine<State, Event>
    private var cancellables: Set<AnyCancellable> = []
    
    private let actionsSubject: PassthroughSubject<AgentSpacesTabFlowCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentSpacesTabFlowCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(navigationSplitCoordinator: NavigationSplitCoordinator, flowParameters: CommonFlowParameters) {
        self.navigationSplitCoordinator = navigationSplitCoordinator
        self.flowParameters = flowParameters
        
        sidebarNavigationStackCoordinator = NavigationStackCoordinator(navigationSplitCoordinator: navigationSplitCoordinator)
        detailNavigationStackCoordinator = NavigationStackCoordinator(navigationSplitCoordinator: navigationSplitCoordinator)
        
        navigationSplitCoordinator.setSidebarCoordinator(sidebarNavigationStackCoordinator)
        
        stateMachine = .init(state: .initial)
        configureStateMachine()
    }
    
    func start(animated: Bool) {
        stateMachine.tryEvent(.start)
    }
    
    func handleAppRoute(_ appRoute: AppRoute, animated: Bool) {
        switch appRoute {
        case .approvalDetail(let approvalID):
            // Notification tap: pop to root, open the bell hub, push
            // the decide screen (Brief 0038 I2 re-attach shape).
            clearRoute(animated: false)
            if case .agentSpacesScreen = stateMachine.state {
                stateMachine.tryEvent(.openNotificationsHub)
            }
            pushApprovalDetail(approvalID: approvalID)
        case .verificationDetail(let verificationID):
            // Notification tap: the SAS decide screen pushes straight on
            // the tab root (the banner is the in-flow entry; a push
            // notification skips the drill-down).
            clearRoute(animated: false)
            pushVerificationDetail(verificationID: verificationID)
        case .publicProfile(let targetMXID):
            // Marketplace-seed profile (restored screen): the person's
            // publicly-contactable agents.
            clearRoute(animated: false)
            pushPublicProfile(targetMXID: targetMXID)
        default:
            clearRoute(animated: animated)
        }
    }
    
    func clearRoute(animated: Bool) {
        sidebarNavigationStackCoordinator.popToRoot(animated: animated)
        if case .notificationsHub = stateMachine.state {
            stateMachine.tryEvent(.popNotificationsHub)
        }
    }
    
    // MARK: - Private
    
    /// The whole transition table, pure so a test can walk every state ×
    /// event. An agent's flow can end under any surface — archived, or its
    /// screen popped on iPhone while the bell hub is up — so `.deselectAgent`
    /// is accepted from every started state and only clears the selection.
    static func nextState(from state: State, on event: Event, selectedAgentID: String? = nil) -> State? {
        switch (state, event) {
        case (.initial, .start):
            return .agentSpacesScreen(selectedAgentID: nil)
        case (.agentSpacesScreen, .selectAgent):
            return selectedAgentID.map { .agentSpacesScreen(selectedAgentID: $0) }
        case (.agentSpacesScreen, .deselectAgent):
            return .agentSpacesScreen(selectedAgentID: nil)
        case (.createCompanyFlow, .deselectAgent):
            return .createCompanyFlow(selectedAgentID: nil)
        case (.notificationsHub, .deselectAgent):
            return .notificationsHub(selectedAgentID: nil)
        case (.agentSpacesScreen(let selected), .startCreateCompanyFlow):
            return .createCompanyFlow(selectedAgentID: selected)
        case (.createCompanyFlow(let selected), .dismissedCreateCompanyFlow):
            return .agentSpacesScreen(selectedAgentID: selected)
        case (.agentSpacesScreen(let selected), .openNotificationsHub):
            return .notificationsHub(selectedAgentID: selected)
        case (.notificationsHub(let selected), .popNotificationsHub):
            return .agentSpacesScreen(selectedAgentID: selected)
        default:
            return nil
        }
    }
    
    private func configureStateMachine() {
        stateMachine.addRouteMapping { event, fromState, userInfo in
            guard let event else { return nil }
            var selectedAgentID: String?
            if event == .selectAgent {
                guard let selection = userInfo as? AgentSelection else { fatalError("An agent must be provided.") }
                selectedAgentID = selection.card.agentID
            }
            return Self.nextState(from: fromState, on: event, selectedAgentID: selectedAgentID)
        } handler: { [weak self] context in
            self?.handleTransition(context)
        }
        
        stateMachine.addErrorHandler { context in
            fatalError("Unexpected transition: \(context)")
        }
    }
    
    private func handleTransition(_ context: StateMachine<State, Event>.Context) {
        switch context.event {
        case .start:
            presentAgentSpacesScreen()
        case .selectAgent:
            guard let selection = context.userInfo as? AgentSelection else { return }
            startAgentFlow(selection: selection)
        case .deselectAgent:
            navigationSplitCoordinator.setDetailCoordinator(nil) // If we forget to do this, the tab bar remains hidden.
            agentFlowCoordinator = nil
        case .startCreateCompanyFlow:
            startCreateCompanyFlow()
        case .dismissedCreateCompanyFlow:
            // The new company shows as its own section, with «Новый агент».
            agentSpacesScreenCoordinator?.reload()
        case .openNotificationsHub:
            presentNotificationsHub()
        case .popNotificationsHub, .none:
            break
        }
    }
    
    /// The bell surface (Brief 0041 D4): the notifications hub —
    /// pinned needs-action union + chronological activity feed. The
    /// decide flows stay on the existing detail screens.
    private func presentNotificationsHub() {
        guard let approvalsStreamService = flowParameters.userSession.approvalsStreamService,
              let agentPlatformService = flowParameters.userSession.agentPlatformService else { return }
        
        let coordinator = NotificationsHubScreenCoordinator(parameters: .init(approvalsStreamService: approvalsStreamService,
                                                                              agentPlatformService: agentPlatformService,
                                                                              clientProxy: flowParameters.userSession.clientProxy,
                                                                              userIndicatorController: flowParameters.userIndicatorController))
        coordinator.actionsPublisher
            .sink { [weak self] (action: NotificationsHubScreenCoordinatorAction) in
                switch action {
                case .presentApprovalDetail(let id):
                    self?.pushApprovalDetail(approvalID: id)
                case .presentVerificationDetail(let id):
                    self?.pushVerificationDetail(verificationID: id)
                case .openRoom(let roomID):
                    self?.actionsSubject.send(.openRoom(roomID: roomID))
                case .presentVisitorSettings(let agent):
                    self?.pushVisitorSettings(agent: agent)
                }
            }
            .store(in: &cancellables)
        
        sidebarNavigationStackCoordinator.push(coordinator) { [weak self] in
            self?.stateMachine.tryEvent(.popNotificationsHub)
        }
    }
    
    /// A visitor's entry for a chat this device doesn't have: the assistant's
    /// «Общение с людьми», where the owner decides how it treats them.
    private func pushVisitorSettings(agent: AgentSpaceAgentCard) {
        guard let agentPlatformService = flowParameters.userSession.agentPlatformService else { return }
        
        let coordinator = AgentSettingsScreenCoordinator(parameters: .init(agent: agent,
                                                                           section: .people,
                                                                           agentPlatformService: agentPlatformService,
                                                                           userIndicatorController: flowParameters.userIndicatorController))
        coordinator.actionsPublisher
            .sink { [weak self] action in
                switch action {
                case .changed:
                    self?.agentSpacesScreenCoordinator?.reload()
                case .dismiss:
                    self?.sidebarNavigationStackCoordinator.pop()
                }
            }
            .store(in: &cancellables)
        sidebarNavigationStackCoordinator.push(coordinator)
    }
    
    /// Detail push — also the `.approvalDetail` notification deep-link
    /// target (no state-machine case: peer-detail convention).
    private func pushApprovalDetail(approvalID: String) {
        guard let agentPlatformService = flowParameters.userSession.agentPlatformService else { return }
        
        let coordinator = ApprovalDetailScreenCoordinator(parameters: .init(approvalID: approvalID,
                                                                            agentPlatformService: agentPlatformService,
                                                                            clientProxy: flowParameters.userSession.clientProxy))
        popOnDismiss(coordinator)
        sidebarNavigationStackCoordinator.push(coordinator)
    }
    
    /// A decision applied on the detail screen pops it — the same contract
    /// the verification detail has. The approval push used to leave the
    /// screen up after "Approve" (pre-merge review
    /// 2026-09-08, iOS P2: an action nobody subscribed to).
    private func popOnDismiss(_ coordinator: ApprovalDetailScreenCoordinator) {
        coordinator.actionsPublisher
            .sink { [weak self] (action: ApprovalDetailScreenCoordinatorAction) in
                switch action {
                case .dismiss:
                    self?.sidebarNavigationStackCoordinator.pop()
                }
            }
            .store(in: &cancellables)
    }
    
    private func pushVerificationDetail(verificationID: String) {
        guard let agentPlatformService = flowParameters.userSession.agentPlatformService else { return }
        
        let coordinator = VerificationDetailScreenCoordinator(parameters: .init(verificationID: verificationID,
                                                                                agentPlatformService: agentPlatformService))
        coordinator.actionsPublisher
            .sink { [weak self] (action: VerificationDetailScreenCoordinatorAction) in
                switch action {
                case .dismiss:
                    self?.sidebarNavigationStackCoordinator.pop()
                }
            }
            .store(in: &cancellables)
        
        sidebarNavigationStackCoordinator.push(coordinator)
    }
    
    private func pushPublicProfile(targetMXID: String) {
        guard let agentPlatformService = flowParameters.userSession.agentPlatformService else { return }
        
        let coordinator = PublicProfileScreenCoordinator(parameters: .init(targetMXID: targetMXID,
                                                                           currentUserMXID: flowParameters.userSession.clientProxy.userID,
                                                                           agentPlatformService: agentPlatformService))
        coordinator.actionsPublisher
            .sink { [weak self] (action: PublicProfileScreenCoordinatorAction) in
                switch action {
                case .contactAgent(let matrixUserID):
                    self?.actionsSubject.send(.openDMWithAgent(matrixUserID: matrixUserID))
                case .dismiss:
                    self?.sidebarNavigationStackCoordinator.pop()
                }
            }
            .store(in: &cancellables)
        
        sidebarNavigationStackCoordinator.push(coordinator)
    }
    
    private func startCreateCompanyFlow() {
        guard let agentPlatformService = flowParameters.userSession.agentPlatformService else { return }
        
        let stackCoordinator = NavigationStackCoordinator()
        let coordinator = CreateCompanyScreenCoordinator(parameters: .init(agentPlatformService: agentPlatformService,
                                                                           userSession: flowParameters.userSession,
                                                                           navigationStackCoordinator: stackCoordinator,
                                                                           userIndicatorController: flowParameters.userIndicatorController,
                                                                           orientationManager: flowParameters.appMediator.windowManager,
                                                                           appSettings: flowParameters.appSettings))
        
        coordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .created, .cancel:
                    navigationSplitCoordinator.setSheetCoordinator(nil)
                }
            }
            .store(in: &cancellables)
        
        stackCoordinator.setRootCoordinator(coordinator)
        
        navigationSplitCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissedCreateCompanyFlow)
        }
    }
    
    /// A new role agent in a company — a sheet like Element's create-room
    /// sheets, deliberately not a state-machine case (it never nests).
    private func presentCreateAgentSheet(company: AgentSpaceSummary) {
        guard let agentPlatformService = flowParameters.userSession.agentPlatformService else { return }
        
        let stackCoordinator = NavigationStackCoordinator()
        let coordinator = CreateAgentScreenCoordinator(parameters: .init(companyID: company.orgID,
                                                                         companyName: company.displayName,
                                                                         agentPlatformService: agentPlatformService))
        coordinator.actionsPublisher
            .sink { [weak self] action in
                switch action {
                case .created, .cancel:
                    self?.navigationSplitCoordinator.setSheetCoordinator(nil)
                }
            }
            .store(in: &cancellables)
        
        stackCoordinator.setRootCoordinator(coordinator)
        navigationSplitCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.agentSpacesScreenCoordinator?.reload()
        }
    }
    
    /// Company profile edit (Brief 0039 S4b) — a sheet like the create
    /// forms; the coordinator self-encapsulates the media pickers.
    private func presentCompanyEditSheet(detail: AgentSpaceDetail) {
        guard let agentPlatformService = flowParameters.userSession.agentPlatformService else { return }
        
        let stackCoordinator = NavigationStackCoordinator()
        let coordinator = CompanyEditScreenCoordinator(parameters: .init(detail: detail,
                                                                         agentPlatformService: agentPlatformService,
                                                                         userSession: flowParameters.userSession,
                                                                         navigationStackCoordinator: stackCoordinator,
                                                                         userIndicatorController: flowParameters.userIndicatorController,
                                                                         orientationManager: flowParameters.appMediator.windowManager,
                                                                         appSettings: flowParameters.appSettings))
        coordinator.actionsPublisher
            .sink { [weak self] action in
                switch action {
                case .saved, .dismiss:
                    self?.navigationSplitCoordinator.setSheetCoordinator(nil)
                }
            }
            .store(in: &cancellables)
        
        stackCoordinator.setRootCoordinator(coordinator)
        navigationSplitCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.agentSpacesScreenCoordinator?.reload()
        }
    }
    
    private func startAgentFlow(selection: AgentSelection) {
        guard let agentPlatformService = flowParameters.userSession.agentPlatformService else { return }
        
        let coordinator = AgentFlowCoordinator(selection: selection,
                                               agentPlatformService: agentPlatformService,
                                               navigationStackCoordinator: detailNavigationStackCoordinator,
                                               flowParameters: flowParameters)
        
        coordinator.actionsPublisher
            .sink { [weak self, weak coordinator] action in
                guard let self else { return }
                switch action {
                case .finished:
                    // A flow replaced by the next agent's ends too; only the open one deselects.
                    guard coordinator === agentFlowCoordinator else { return }
                    stateMachine.tryEvent(.deselectAgent)
                case .changed:
                    agentSpacesScreenCoordinator?.reload()
                case .openDM(let matrixUserID):
                    actionsSubject.send(.openDMWithAgent(matrixUserID: matrixUserID))
                case .presentCallScreen(let roomProxy, let isVoiceCall):
                    actionsSubject.send(.presentCallScreen(roomProxy: roomProxy, isVoiceCall: isVoiceCall))
                case .presentAIConsentSettings:
                    actionsSubject.send(.presentAIConsentSettings)
                case .verifyUser(let userID):
                    actionsSubject.send(.verifyUser(userID: userID))
                }
            }
            .store(in: &cancellables)
        
        agentFlowCoordinator = coordinator
        
        if navigationSplitCoordinator.detailCoordinator !== detailNavigationStackCoordinator {
            navigationSplitCoordinator.setDetailCoordinator(detailNavigationStackCoordinator)
        }
        
        coordinator.start(animated: true)
    }
    
    private func presentAgentSpacesScreen() {
        // The agent-platform service is optional on UserSession (nil
        // when the homeserver isn't one we provision) — degrade to the
        // placeholder exactly like the pre-rebuild tab did.
        guard let agentPlatformService = flowParameters.userSession.agentPlatformService else {
            sidebarNavigationStackCoordinator.setRootCoordinator(PlaceholderScreenCoordinator(hideBrandChrome: flowParameters.appSettings.hideBrandChrome))
            return
        }
        
        let coordinator = AgentSpacesScreenCoordinator(parameters: .init(userSession: flowParameters.userSession,
                                                                         agentPlatformService: agentPlatformService))
        
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .selectAgent(let selection):
                stateMachine.tryEvent(.selectAgent, userInfo: selection)
            case .showSettings:
                actionsSubject.send(.showSettings)
            case .showCreateCompany:
                stateMachine.tryEvent(.startCreateCompanyFlow)
            case .showCreateAgent(let company):
                presentCreateAgentSheet(company: company)
            case .showEditCompany(let detail):
                presentCompanyEditSheet(detail: detail)
            case .showNotifications:
                stateMachine.tryEvent(.openNotificationsHub)
            }
        }
        .store(in: &cancellables)
        
        agentSpacesScreenCoordinator = coordinator
        sidebarNavigationStackCoordinator.setRootCoordinator(coordinator)
    }
}
