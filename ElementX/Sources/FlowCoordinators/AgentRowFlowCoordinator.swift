//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): one of the owner's entries of an agent's page, opened on the page's own
// stack: a row, or the agent's screen for the chat's Settings (question 391). The chat's page and the profile pages
// share this, so what `AgentFlowCoordinator` sends is sorted out once.
//

import Combine
import Foundation

enum AgentRowFlowCoordinatorAction {
    /// The row's screen was popped: the parent restores its state.
    case finished
    case presentCallScreen(roomProxy: JoinedRoomProxyProtocol, isVoiceCall: Bool)
    case presentAIConsentSettings
    /// The Agents tab, where the person's agent is or will be (question 412).
    case presentAgentsTab
    case verifyUser(userID: String)
}

final class AgentRowFlowCoordinator: FlowCoordinatorProtocol {
    private let agentFlowCoordinator: AgentFlowCoordinator
    private let agentsStore: AgentsStore
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<AgentRowFlowCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentRowFlowCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    /// `nil` without the agent platform, which an own agent's page can't be shown without.
    init?(row: AgentPageRow,
          card: AgentSpaceAgentCard,
          navigationStackCoordinator: NavigationStackCoordinator,
          flowParameters: CommonFlowParameters,
          showOriginRoom: ((_ roomID: String) -> Bool)? = nil) {
        guard let agentPlatformService = flowParameters.userSession.agentPlatformService,
              let agentsStore = flowParameters.userSession.agentsStore else {
            return nil
        }
        self.agentsStore = agentsStore
        agentFlowCoordinator = AgentFlowCoordinator(selection: .init(card: card, companyName: agentsStore.spaces?.companyName(agentID: card.agentID)),
                                                    agentPlatformService: agentPlatformService,
                                                    agentsStore: agentsStore,
                                                    navigationStackCoordinator: navigationStackCoordinator,
                                                    flowParameters: flowParameters,
                                                    pushedRow: row,
                                                    showOriginRoom: showOriginRoom)
        
        agentFlowCoordinator.actionsPublisher
            .sink { [weak self] action in
                self?.handle(action)
            }
            .store(in: &cancellables)
    }
    
    func start(animated: Bool) {
        agentFlowCoordinator.start(animated: animated)
    }
    
    func handleAppRoute(_ appRoute: AppRoute, animated: Bool) {
        agentFlowCoordinator.handleAppRoute(appRoute, animated: animated)
    }
    
    func clearRoute(animated: Bool) {
        agentFlowCoordinator.clearRoute(animated: animated)
    }
    
    func handle(_ action: AgentFlowCoordinatorAction) {
        switch action {
        case .finished:
            actionsSubject.send(.finished)
        case .changed:
            // The page's Chats count reads the spaces. The person's own change: read now, even with a read on its
            // way that left before it (S5; `refresh` would let that older answer stand).
            Task { await agentsStore.reread(.spaces) }
        case .openDM:
            // A pushed agent's screen opens its DM itself; only the Agents tab's root sends this.
            MXLog.error("An agent's pushed entry asked its parent for the DM")
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
}
