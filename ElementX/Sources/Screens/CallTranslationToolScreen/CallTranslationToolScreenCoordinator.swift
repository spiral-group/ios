//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import SwiftUI

struct CallTranslationToolScreenCoordinatorParameters {
    let roomID: String
    let agentID: String
    let agentDisplayName: String
    let agentPlatformService: AgentPlatformServiceProtocol
}

final class CallTranslationToolScreenCoordinator: CoordinatorProtocol {
    private let viewModel: CallTranslationToolScreenViewModel

    init(parameters: CallTranslationToolScreenCoordinatorParameters) {
        viewModel = CallTranslationToolScreenViewModel(service: CallTranslationToolService(roomID: parameters.roomID,
                                                                                           agentID: parameters.agentID,
                                                                                           service: parameters.agentPlatformService),
                                                       agentDisplayName: parameters.agentDisplayName)
    }

    func toPresentable() -> AnyView {
        AnyView(CallTranslationToolScreen(context: viewModel.context))
    }
}
