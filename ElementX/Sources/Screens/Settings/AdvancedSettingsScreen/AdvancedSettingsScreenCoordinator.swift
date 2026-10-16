//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct AdvancedSettingsScreenCoordinatorParameters {
    let appSettings: AppSettings
    let clientProxy: ClientProxyProtocol
    let userIndicatorController: UserIndicatorControllerProtocol
    let agentPlatformService: AgentPlatformServiceProtocol? // AGENT-PLATFORM (Brief 0078 phase 2)
}

// AGENT-PLATFORM (decision 187): Blocked users opens from here, as in upstream's ModerationAndSafetySettingsScreen.
enum AdvancedSettingsScreenCoordinatorAction {
    case blockedUsers
}

final class AdvancedSettingsScreenCoordinator: CoordinatorProtocol {
    private var viewModel: AdvancedSettingsScreenViewModelProtocol
    
    private let actionsSubject: PassthroughSubject<AdvancedSettingsScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AdvancedSettingsScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    init(parameters: AdvancedSettingsScreenCoordinatorParameters) {
        viewModel = AdvancedSettingsScreenViewModel(advancedSettings: parameters.appSettings,
                                                    clientProxy: parameters.clientProxy,
                                                    userIndicatorController: parameters.userIndicatorController,
                                                    agentPlatformService: parameters.agentPlatformService)
        
        viewModel.actionsPublisher
            .sink { [weak self] action in
                switch action {
                case .blockedUsers:
                    self?.actionsSubject.send(.blockedUsers)
                }
            }
            .store(in: &cancellables)
    }
    
    func toPresentable() -> AnyView {
        AnyView(AdvancedSettingsScreen(context: viewModel.context))
    }
}
