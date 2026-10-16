//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct CreateAgentScreenCoordinatorParameters {
    let companyID: String
    let companyName: String
    let agentPlatformService: AgentPlatformServiceProtocol
}

enum CreateAgentScreenCoordinatorAction {
    case created
    case cancel
}

final class CreateAgentScreenCoordinator: CoordinatorProtocol {
    private let viewModel: CreateAgentScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<CreateAgentScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<CreateAgentScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: CreateAgentScreenCoordinatorParameters) {
        viewModel = CreateAgentScreenViewModel(companyID: parameters.companyID,
                                               companyName: parameters.companyName,
                                               agentPlatformService: parameters.agentPlatformService)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            switch action {
            case .created:
                self?.actionsSubject.send(.created)
            case .cancel:
                self?.actionsSubject.send(.cancel)
            }
        }
        .store(in: &cancellables)
    }
    
    func toPresentable() -> AnyView {
        AnyView(CreateAgentScreen(context: viewModel.context))
    }
}
