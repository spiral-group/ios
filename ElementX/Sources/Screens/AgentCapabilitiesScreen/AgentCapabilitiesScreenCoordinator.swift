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

struct AgentCapabilitiesScreenCoordinatorParameters {
    /// The room whose tool state we read + arm into.
    let roomID: String
    /// The agent whose capabilities these are.
    let agentID: String
    let agentDisplayName: String
    let agentPlatformService: any RoomToolsServiceProtocol
    /// «Готово» closes a sheet; a pushed screen has its back chevron instead.
    var showsDoneButton = true
}

enum AgentCapabilitiesScreenCoordinatorAction {
    /// User tapped a capability — the agent-tools flow presents the arm
    /// form. `active` seeds the form for a "manage / turn off" flow.
    case presentArmTool(AgentCapability, active: ActiveCapabilityTool?)
    /// User dismissed the sheet.
    case dismiss
}

final class AgentCapabilitiesScreenCoordinator: CoordinatorProtocol {
    private let viewModel: AgentCapabilitiesScreenViewModel

    private let actionsSubject: PassthroughSubject<AgentCapabilitiesScreenCoordinatorAction, Never> = .init()
    private var cancellables = Set<AnyCancellable>()

    var actionsPublisher: AnyPublisher<AgentCapabilitiesScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: AgentCapabilitiesScreenCoordinatorParameters) {
        viewModel = AgentCapabilitiesScreenViewModel(roomID: parameters.roomID,
                                                     agentID: parameters.agentID,
                                                     agentDisplayName: parameters.agentDisplayName,
                                                     showsDoneButton: parameters.showsDoneButton,
                                                     agentPlatformService: parameters.agentPlatformService)
    }

    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .selectCapability(let capability, let active):
                actionsSubject.send(.presentArmTool(capability, active: active))
            case .dismiss:
                actionsSubject.send(.dismiss)
            }
        }
        .store(in: &cancellables)
    }

    /// Called by the flow coordinator once an arm/disable form dismisses,
    /// so the capability rows reflect the change.
    func refresh() {
        viewModel.reload()
    }

    func toPresentable() -> AnyView {
        AnyView(AgentCapabilitiesScreen(context: viewModel.context))
    }
}
