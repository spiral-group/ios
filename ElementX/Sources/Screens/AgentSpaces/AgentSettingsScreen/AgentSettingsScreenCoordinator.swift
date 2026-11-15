//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import SwiftUI

struct AgentSettingsScreenCoordinatorParameters {
    let agent: AgentSpaceAgentCard
    let section: AgentSettingsSection
    let agentPlatformService: AgentPlatformServiceProtocol
    let store: AgentsStore
    let userIndicatorController: UserIndicatorControllerProtocol
}

enum AgentSettingsScreenCoordinatorAction {
    case changed
    case dismiss
}

final class AgentSettingsScreenCoordinator: CoordinatorProtocol {
    private let viewModel: AgentSettingsScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<AgentSettingsScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentSettingsScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: AgentSettingsScreenCoordinatorParameters) {
        viewModel = AgentSettingsScreenViewModel(agent: parameters.agent,
                                                 section: parameters.section,
                                                 agentPlatformService: parameters.agentPlatformService,
                                                 store: parameters.store,
                                                 userIndicatorController: parameters.userIndicatorController)
    }

    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            switch action {
            case .changed:
                self?.actionsSubject.send(.changed)
            case .dismiss:
                self?.actionsSubject.send(.dismiss)
            }
        }
        .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(AgentSettingsScreen(context: viewModel.context))
    }
}
