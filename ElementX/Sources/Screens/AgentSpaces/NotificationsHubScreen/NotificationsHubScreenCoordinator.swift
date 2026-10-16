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

struct NotificationsHubScreenCoordinatorParameters {
    let approvalsStreamService: any ApprovalsStreamServiceProtocol
    let agentPlatformService: any AgentPlatformServiceProtocol
    /// Names the rooms rows and cards name by ID (coverage walk F9).
    let clientProxy: any ClientProxyProtocol
    let userIndicatorController: any UserIndicatorControllerProtocol
}

enum NotificationsHubScreenCoordinatorAction {
    case presentApprovalDetail(id: String)
    case presentVerificationDetail(id: String)
    case openRoom(roomID: String)
    case presentVisitorSettings(agent: AgentSpaceAgentCard)
}

/// The bell target (Brief 0041 D4) — replaces the retired
/// ApprovalsInbox. The decide surfaces stay the existing detail
/// screens; this coordinator only routes.
final class NotificationsHubScreenCoordinator: CoordinatorProtocol {
    private let viewModel: NotificationsHubScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<NotificationsHubScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<NotificationsHubScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: NotificationsHubScreenCoordinatorParameters) {
        viewModel = NotificationsHubScreenViewModel(approvalsStreamService: parameters.approvalsStreamService,
                                                    agentPlatformService: parameters.agentPlatformService,
                                                    clientProxy: parameters.clientProxy,
                                                    userIndicatorController: parameters.userIndicatorController)
    }

    func start() {
        viewModel.actionsPublisher
            .sink { [weak self] action in
                switch action {
                case .selectApproval(let id):
                    self?.actionsSubject.send(.presentApprovalDetail(id: id))
                case .selectVerification(let id):
                    self?.actionsSubject.send(.presentVerificationDetail(id: id))
                case .openRoom(let roomID):
                    self?.actionsSubject.send(.openRoom(roomID: roomID))
                case .showVisitorSettings(let agent):
                    self?.actionsSubject.send(.presentVisitorSettings(agent: agent))
                }
            }
            .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(NotificationsHubScreen(context: viewModel.context))
    }
}
