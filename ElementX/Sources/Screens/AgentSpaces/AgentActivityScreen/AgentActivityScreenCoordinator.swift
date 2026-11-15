//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreenCoordinator.swift`.

import Combine
import SwiftUI

struct AgentActivityScreenCoordinatorParameters {
    let agentID: String
    var initialFilter: ActionOutcomeFilter = .all
    let store: AgentsStore
    /// Names the rooms rows happened in (coverage walk F9).
    let clientProxy: any ClientProxyProtocol
}

enum AgentActivityScreenCoordinatorAction {
    case openRoom(roomID: String)
    case openApproval(approvalID: String)
}

final class AgentActivityScreenCoordinator: CoordinatorProtocol {
    private let viewModel: AgentActivityScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<AgentActivityScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentActivityScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: AgentActivityScreenCoordinatorParameters) {
        viewModel = AgentActivityScreenViewModel(agentID: parameters.agentID,
                                                 initialFilter: parameters.initialFilter,
                                                 store: parameters.store,
                                                 clientProxy: parameters.clientProxy)
    }

    /// G5: a row opens its approval, else its chat.
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            switch action {
            case .openRoom(let roomID):
                self?.actionsSubject.send(.openRoom(roomID: roomID))
            case .openApproval(let approvalID):
                self?.actionsSubject.send(.openApproval(approvalID: approvalID))
            }
        }
        .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(AgentActivityScreen(context: viewModel.context))
    }
}
