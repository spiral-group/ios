//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import SwiftUI

struct AgentChatsScreenCoordinatorParameters {
    let agent: AgentSpaceAgentCard
    let clientProxy: ClientProxyProtocol
    let store: AgentsStore
}

enum AgentChatsScreenCoordinatorAction {
    case selectRoom(AgentRoomEntry)
    case gone
}

final class AgentChatsScreenCoordinator: CoordinatorProtocol {
    private let viewModel: AgentChatsScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<AgentChatsScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentChatsScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: AgentChatsScreenCoordinatorParameters) {
        viewModel = AgentChatsScreenViewModel(agent: parameters.agent,
                                              clientProxy: parameters.clientProxy,
                                              store: parameters.store)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            switch action {
            case .selectRoom(let room):
                self?.actionsSubject.send(.selectRoom(room))
            case .gone:
                self?.actionsSubject.send(.gone)
            }
        }
        .store(in: &cancellables)
    }
    
    /// Re-fetch after a change deeper in the flow.
    func reload() {
        Task { await viewModel.reload() }
    }
    
    func toPresentable() -> AnyView {
        AnyView(AgentChatsScreen(context: viewModel.context))
    }
}
