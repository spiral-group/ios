//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: the agent's AI use against its daily limit (Brief 0079 3c).
//

import SwiftUI

struct AgentUsageScreenCoordinatorParameters {
    let agentID: String
    let agentPlatformService: any AgentPlatformServiceProtocol
}

final class AgentUsageScreenCoordinator: CoordinatorProtocol {
    private let viewModel: AgentUsageScreenViewModelProtocol

    init(parameters: AgentUsageScreenCoordinatorParameters) {
        viewModel = AgentUsageScreenViewModel(agentID: parameters.agentID,
                                              agentPlatformService: parameters.agentPlatformService)
    }

    /// Read-only: the screen publishes nothing.
    func start() { }

    func toPresentable() -> AnyView {
        AnyView(AgentUsageScreen(context: viewModel.context))
    }
}
