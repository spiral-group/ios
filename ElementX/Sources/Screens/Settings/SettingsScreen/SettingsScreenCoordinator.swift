//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct SettingsScreenCoordinatorParameters {
    let userSession: UserSessionProtocol
    let isBugReportServiceEnabled: Bool
    let isInSecondaryWindow: Bool
    let userIndicatorController: UserIndicatorControllerProtocol
}

enum SettingsScreenCoordinatorAction {
    case userDetails
    case userStatusEmojiPicker(EmojiPickerScreenContinuation)
    case invitePeople // AGENT-PLATFORM (Brief 0073).
    case security // AGENT-PLATFORM (decision 187).
    case privacy // AGENT-PLATFORM (decision 187).
    case notifications
    case yourData // AGENT-PLATFORM (Brief 0078).
    case appearanceAndMedia // AGENT-PLATFORM (decision 187).
    case analytics
    case bugReport
    case about
    case labs
    case developerOptions
    case logout
    case deactivateAccount
}

final class SettingsScreenCoordinator: CoordinatorProtocol {
    private var viewModel: SettingsScreenViewModelProtocol
    
    private let actionsSubject: PassthroughSubject<SettingsScreenCoordinatorAction, Never> = .init()
    var actions: AnyPublisher<SettingsScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Setup
    
    init(parameters: SettingsScreenCoordinatorParameters) {
        viewModel = SettingsScreenViewModel(userSession: parameters.userSession,
                                            isBugReportServiceEnabled: parameters.isBugReportServiceEnabled,
                                            isInSecondaryWindow: parameters.isInSecondaryWindow,
                                            userIndicatorController: parameters.userIndicatorController)
        
        viewModel.actions
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                    
                case .userDetails:
                    actionsSubject.send(.userDetails)
                case let .userStatusEmojiPicker(continuation):
                    actionsSubject.send(.userStatusEmojiPicker(continuation))
                case .invitePeople: // AGENT-PLATFORM (Brief 0073).
                    actionsSubject.send(.invitePeople)
                case .security: // AGENT-PLATFORM (decision 187).
                    actionsSubject.send(.security)
                case .privacy: // AGENT-PLATFORM (decision 187).
                    actionsSubject.send(.privacy)
                case .notifications:
                    actionsSubject.send(.notifications)
                case .yourData: // AGENT-PLATFORM (Brief 0078).
                    actionsSubject.send(.yourData)
                case .appearanceAndMedia: // AGENT-PLATFORM (decision 187).
                    actionsSubject.send(.appearanceAndMedia)
                case .analytics:
                    actionsSubject.send(.analytics)
                case .reportBug:
                    actionsSubject.send(.bugReport)
                case .about:
                    actionsSubject.send(.about)
                case .labs:
                    actionsSubject.send(.labs)
                case .developerOptions:
                    actionsSubject.send(.developerOptions)
                case .logout:
                    actionsSubject.send(.logout)
                case .deactivateAccount:
                    actionsSubject.send(.deactivateAccount)
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public
    
    func toPresentable() -> AnyView {
        AnyView(SettingsScreen(context: viewModel.context))
    }
}
