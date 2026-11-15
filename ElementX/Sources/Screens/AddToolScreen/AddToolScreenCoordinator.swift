//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import SwiftUI

struct AddToolScreenCoordinatorParameters {
    let roomID: String
    let agentID: String
    let agentDisplayName: String
    let store: AgentsStore
}

enum AddToolScreenCoordinatorAction {
    case selectKind(AgentToolKind)
}

final class AddToolScreenCoordinator: CoordinatorProtocol {
    private let viewModel: AddToolScreenViewModel
    
    private let actionsSubject: PassthroughSubject<AddToolScreenCoordinatorAction, Never> = .init()
    private var cancellables = Set<AnyCancellable>()
    
    var actionsPublisher: AnyPublisher<AddToolScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: AddToolScreenCoordinatorParameters) {
        viewModel = AddToolScreenViewModel(roomID: parameters.roomID,
                                           agentID: parameters.agentID,
                                           agentDisplayName: parameters.agentDisplayName,
                                           store: parameters.store)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .selectKind(let kind):
                actionsSubject.send(.selectKind(kind))
            }
        }
        .store(in: &cancellables)
    }
    
    func toPresentable() -> AnyView {
        AnyView(AddToolScreen(context: viewModel.context))
    }
}
