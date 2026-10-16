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

struct ApprovalDetailScreenCoordinatorParameters {
    let approvalID: String
    let agentPlatformService: any AgentPlatformServiceProtocol
    /// Names a block request's person and group, which it carries only by ID.
    let clientProxy: any ClientProxyProtocol
}

enum ApprovalDetailScreenCoordinatorAction {
    /// Decision applied + delivered (or dismissed after send-
    /// failure). Parent flow pops the screen; SSE has already
    /// pushed the row off the list view.
    case dismiss
}

final class ApprovalDetailScreenCoordinator: CoordinatorProtocol {
    private let viewModel: ApprovalDetailScreenViewModelProtocol

    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<ApprovalDetailScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<ApprovalDetailScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: ApprovalDetailScreenCoordinatorParameters) {
        viewModel = ApprovalDetailScreenViewModel(approvalID: parameters.approvalID,
                                                  agentPlatformService: parameters.agentPlatformService,
                                                  clientProxy: parameters.clientProxy)
    }

    func start() {
        viewModel.actionsPublisher
            .sink { [weak self] action in
                MXLog.info("ApprovalDetailScreenCoordinator received view-model action: \(action)")
                guard let self else { return }
                switch action {
                case .decisionFinalised:
                    actionsSubject.send(.dismiss)
                }
            }
            .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(ApprovalDetailScreen(context: viewModel.context))
    }
}
