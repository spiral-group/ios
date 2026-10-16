//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenCoordinator.swift`.
//

import Combine
import SwiftUI

struct AgentPickerScreenCoordinatorParameters {
    let agents: [AgentPickerItem]
}

enum AgentPickerScreenCoordinatorAction {
    case selectAgent(AgentPickerItem)
    case dismiss
}

final class AgentPickerScreenCoordinator: CoordinatorProtocol {
    private let viewModel: AgentPickerScreenViewModel

    private let actionsSubject: PassthroughSubject<AgentPickerScreenCoordinatorAction, Never> = .init()
    private var cancellables = Set<AnyCancellable>()

    var actionsPublisher: AnyPublisher<AgentPickerScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: AgentPickerScreenCoordinatorParameters) {
        viewModel = AgentPickerScreenViewModel(agents: parameters.agents)
    }

    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .selectAgent(let agent):
                actionsSubject.send(.selectAgent(agent))
            case .dismiss:
                actionsSubject.send(.dismiss)
            }
        }
        .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(AgentPickerScreen(context: viewModel.context))
    }
}
