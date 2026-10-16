//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import SwiftUI

struct AgentBlockedScreenCoordinatorParameters {
    let agent: AgentSpaceAgentCard
    let agentPlatformService: AgentPlatformServiceProtocol
    let userIndicatorController: UserIndicatorControllerProtocol
}

/// The agent screen reads its count again when this is popped.
final class AgentBlockedScreenCoordinator: CoordinatorProtocol {
    private let viewModel: AgentBlockedScreenViewModelProtocol

    init(parameters: AgentBlockedScreenCoordinatorParameters) {
        viewModel = AgentBlockedScreenViewModel(agent: parameters.agent,
                                                agentPlatformService: parameters.agentPlatformService,
                                                userIndicatorController: parameters.userIndicatorController)
    }

    func toPresentable() -> AnyView {
        AnyView(AgentBlockedScreen(context: viewModel.context))
    }
}
