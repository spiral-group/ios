//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenViewModel.swift`.
//

import Combine
import SwiftUI

typealias AgentPickerScreenViewModelType = StateStoreViewModelV2<AgentPickerScreenViewState, AgentPickerScreenViewAction>

/// Drives `AgentPickerScreen`. A static single-select over the caller's
/// own agents in the room (already fetched by the flow), emitting the
/// chosen agent so the coordinator can push its capabilities.
class AgentPickerScreenViewModel: AgentPickerScreenViewModelType, AgentPickerScreenViewModelProtocol {
    private let actionsSubject: PassthroughSubject<AgentPickerScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentPickerScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(agents: [AgentPickerItem]) {
        super.init(initialViewState: AgentPickerScreenViewState(agents: agents))
    }

    override func process(viewAction: AgentPickerScreenViewAction) {
        MXLog.info("AgentPickerScreenViewModel received view action: \(viewAction)")

        switch viewAction {
        case .selectAgent(let id):
            guard let agent = state.agents.first(where: { $0.id == id }) else { return }
            actionsSubject.send(.selectAgent(agent))
        case .done:
            actionsSubject.send(.dismiss)
        }
    }
}
