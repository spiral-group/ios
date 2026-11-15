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

struct OutreachQueueListScreenCoordinatorParameters {
    let agentID: String
    let store: AgentsStore
}

enum OutreachQueueListScreenCoordinatorAction {
    case presentAddTargets(agentID: String)
    case dismiss
}

final class OutreachQueueListScreenCoordinator: CoordinatorProtocol {
    private let parameters: OutreachQueueListScreenCoordinatorParameters
    private let viewModel: OutreachQueueListScreenViewModelProtocol

    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<OutreachQueueListScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<OutreachQueueListScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: OutreachQueueListScreenCoordinatorParameters) {
        self.parameters = parameters
        viewModel = OutreachQueueListScreenViewModel(agentID: parameters.agentID,
                                                     store: parameters.store)
    }

    func start() {
        viewModel.actionsPublisher
            .sink { [weak self] action in
                MXLog.info("OutreachQueueListScreenCoordinator received view-model action: \(action)")
                guard let self else { return }
                switch action {
                case .openAddTargets:
                    actionsSubject.send(.presentAddTargets(agentID: parameters.agentID))
                case .dismissed:
                    actionsSubject.send(.dismiss)
                }
            }
            .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(OutreachQueueListScreen(context: viewModel.context))
    }
}
