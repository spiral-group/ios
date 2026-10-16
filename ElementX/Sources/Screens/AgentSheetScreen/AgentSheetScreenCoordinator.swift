//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0035/0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenCoordinator.swift`.
//

import Combine
import SwiftUI

struct AgentSheetScreenCoordinatorParameters {
    let roomID: String
    let agentPlatformService: any RoomToolsServiceProtocol
    /// Loads agent avatars for the rows.
    let mediaProvider: MediaProviderProtocol?
}

enum AgentSheetScreenCoordinatorAction {
    /// User picked an agent already in the room.
    case selectAgent(AgentSummary)
    /// User tapped "Add agent".
    case addAgent
    /// User dismissed.
    case dismiss
}

final class AgentSheetScreenCoordinator: CoordinatorProtocol {
    private let viewModel: AgentSheetScreenViewModel
    private let mediaProvider: MediaProviderProtocol?

    private let actionsSubject: PassthroughSubject<AgentSheetScreenCoordinatorAction, Never> = .init()
    private var cancellables = Set<AnyCancellable>()

    var actionsPublisher: AnyPublisher<AgentSheetScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: AgentSheetScreenCoordinatorParameters) {
        viewModel = AgentSheetScreenViewModel(roomID: parameters.roomID,
                                              agentPlatformService: parameters.agentPlatformService)
        mediaProvider = parameters.mediaProvider
    }

    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .selectAgent(let agent):
                actionsSubject.send(.selectAgent(agent))
            case .addAgent:
                actionsSubject.send(.addAgent)
            case .dismiss:
                actionsSubject.send(.dismiss)
            }
        }
        .store(in: &cancellables)
    }

    /// Re-pull the agents (after an add-agent invite or an arm/disable).
    func reload() {
        viewModel.reload()
    }

    func finishOpeningAgent() {
        viewModel.finishOpeningAgent()
    }

    func toPresentable() -> AnyView {
        AnyView(AgentSheetScreen(context: viewModel.context, mediaProvider: mediaProvider))
    }
}
