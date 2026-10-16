//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0078, GDPR): «Your data».
//

import SwiftUI

struct YourDataScreenCoordinatorParameters {
    let agentPlatformService: AgentPlatformServiceProtocol
    let clientProxy: ClientProxyProtocol
    let userIndicatorController: UserIndicatorControllerProtocol
}

final class YourDataScreenCoordinator: CoordinatorProtocol {
    private let viewModel: YourDataScreenViewModelProtocol

    init(parameters: YourDataScreenCoordinatorParameters) {
        viewModel = YourDataScreenViewModel(agentPlatformService: parameters.agentPlatformService,
                                            clientProxy: parameters.clientProxy,
                                            userIndicatorController: parameters.userIndicatorController)
    }

    func toPresentable() -> AnyView {
        AnyView(YourDataScreen(context: viewModel.context))
    }
}
