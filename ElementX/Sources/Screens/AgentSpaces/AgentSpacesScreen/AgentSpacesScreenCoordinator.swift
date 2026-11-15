//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct AgentSpacesScreenCoordinatorParameters {
    let userSession: UserSessionProtocol
    let store: AgentsStore
}

enum AgentSpacesScreenCoordinatorAction {
    case selectAgent(AgentSelection)
    case showCreateCompany
    case showCreateAgent(AgentSpaceSummary)
    case showEditCompany(AgentSpaceDetail)
    case showNotifications
}

final class AgentSpacesScreenCoordinator: CoordinatorProtocol {
    private let viewModel: AgentSpacesScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<AgentSpacesScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentSpacesScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: AgentSpacesScreenCoordinatorParameters) {
        viewModel = AgentSpacesScreenViewModel(userSession: parameters.userSession,
                                               store: parameters.store)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .selectAgent(let selection):
                actionsSubject.send(.selectAgent(selection))
            case .showCreateCompany:
                actionsSubject.send(.showCreateCompany)
            case .showCreateAgent(let company):
                actionsSubject.send(.showCreateAgent(company))
            case .showEditCompany(let detail):
                actionsSubject.send(.showEditCompany(detail))
            case .showNotifications:
                actionsSubject.send(.showNotifications)
            }
        }
        .store(in: &cancellables)
    }
    
    /// Read the spaces now — the flow coordinator calls this when the
    /// person's own change elsewhere (create company, archive agent, …) changed them.
    func reload() {
        viewModel.reload()
    }
    
    func toPresentable() -> AnyView {
        AnyView(AgentSpacesScreen(context: viewModel.context))
    }
}
