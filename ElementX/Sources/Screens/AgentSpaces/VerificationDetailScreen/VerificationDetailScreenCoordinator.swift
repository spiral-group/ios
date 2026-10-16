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

struct VerificationDetailScreenCoordinatorParameters {
    let verificationID: String
    let agentPlatformService: any AgentPlatformServiceProtocol
}

enum VerificationDetailScreenCoordinatorAction {
    case dismiss
}

final class VerificationDetailScreenCoordinator: CoordinatorProtocol {
    private let viewModel: VerificationDetailScreenViewModelProtocol

    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<VerificationDetailScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<VerificationDetailScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: VerificationDetailScreenCoordinatorParameters) {
        viewModel = VerificationDetailScreenViewModel(verificationID: parameters.verificationID,
                                                      agentPlatformService: parameters.agentPlatformService)
    }

    func start() {
        viewModel.actionsPublisher
            .sink { [weak self] action in
                MXLog.info("VerificationDetailScreenCoordinator received view-model action: \(action)")
                guard let self else { return }
                switch action {
                case .decided, .dismissed:
                    actionsSubject.send(.dismiss)
                }
            }
            .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(VerificationDetailScreen(context: viewModel.context))
    }
}
