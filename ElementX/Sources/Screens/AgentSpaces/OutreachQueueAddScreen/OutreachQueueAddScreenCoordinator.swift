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

struct OutreachQueueAddScreenCoordinatorParameters {
    let agentID: String
    let agentPlatformService: any AgentPlatformServiceProtocol
}

enum OutreachQueueAddScreenCoordinatorAction {
    /// Save succeeded; the parent flow pops + re-renders the
    /// queue list so the new rows surface.
    case enqueued
    case dismiss
}

final class OutreachQueueAddScreenCoordinator: CoordinatorProtocol {
    private let viewModel: OutreachQueueAddScreenViewModelProtocol

    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<OutreachQueueAddScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<OutreachQueueAddScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: OutreachQueueAddScreenCoordinatorParameters) {
        viewModel = OutreachQueueAddScreenViewModel(agentID: parameters.agentID,
                                                    agentPlatformService: parameters.agentPlatformService)
    }

    func start() {
        viewModel.actionsPublisher
            .sink { [weak self] action in
                MXLog.info("OutreachQueueAddScreenCoordinator received view-model action: \(action)")
                guard let self else { return }
                switch action {
                case .enqueued:
                    actionsSubject.send(.enqueued)
                case .dismissed:
                    actionsSubject.send(.dismiss)
                }
            }
            .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(OutreachQueueAddScreen(context: viewModel.context))
    }
}
