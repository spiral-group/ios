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

struct AgentToolsListScreenCoordinatorParameters {
    let roomID: String
    let agentID: String
    let agentDisplayName: String
    let agentPlatformService: any RoomToolsServiceProtocol
}

enum AgentToolsListScreenCoordinatorAction {
    /// Edit an existing tool (the flow presents the seeded arm form).
    case editTool(ActiveToolDetail)
    /// Add a new tool (the flow presents a fresh create form).
    case addTool
    /// Dismiss the sheet.
    case dismiss
}

final class AgentToolsListScreenCoordinator: CoordinatorProtocol {
    private let viewModel: AgentToolsListScreenViewModel

    private let actionsSubject: PassthroughSubject<AgentToolsListScreenCoordinatorAction, Never> = .init()
    private var cancellables = Set<AnyCancellable>()

    var actionsPublisher: AnyPublisher<AgentToolsListScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: AgentToolsListScreenCoordinatorParameters) {
        viewModel = AgentToolsListScreenViewModel(roomID: parameters.roomID,
                                                  agentID: parameters.agentID,
                                                  agentDisplayName: parameters.agentDisplayName,
                                                  agentPlatformService: parameters.agentPlatformService)
    }

    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .editTool(let tool):
                actionsSubject.send(.editTool(tool))
            case .addTool:
                actionsSubject.send(.addTool)
            case .dismiss:
                actionsSubject.send(.dismiss)
            }
        }
        .store(in: &cancellables)
    }

    /// Called by the flow coordinator once an edit/create form dismisses so
    /// the list reflects the change.
    func refresh() {
        viewModel.reload()
    }

    func toPresentable() -> AnyView {
        AnyView(AgentToolsListScreen(context: viewModel.context))
    }
}
