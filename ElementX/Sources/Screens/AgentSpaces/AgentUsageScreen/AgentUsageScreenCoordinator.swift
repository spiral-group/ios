//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: the agent's AI use against its weekly limit (Brief 0079 3c, question 394).
//

import SwiftUI

struct AgentUsageScreenCoordinatorParameters {
    let agentID: String
    let store: AgentsStore
}

final class AgentUsageScreenCoordinator: CoordinatorProtocol {
    private let viewModel: AgentUsageScreenViewModelProtocol

    init(parameters: AgentUsageScreenCoordinatorParameters) {
        viewModel = AgentUsageScreenViewModel(agentID: parameters.agentID,
                                              store: parameters.store)
    }

    /// Read-only: the screen publishes nothing.
    func start() { }

    func toPresentable() -> AnyView {
        AnyView(AgentUsageScreen(context: viewModel.context))
    }
}
