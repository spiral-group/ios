//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (decision 187): the Security hub. Every row opens a
// presenter `SettingsFlowCoordinator` already had.
// The Spiral feature is built on Element's `SettingsScreenCoordinator.swift`.
//

import Combine
import SwiftUI

struct SecuritySettingsScreenCoordinatorParameters {
    let userSession: UserSessionProtocol
    let appSettings: AppSettings
}

enum SecuritySettingsScreenCoordinatorAction {
    case newPhrase(addsFirstPhrase: Bool)
    case addApple
    case manageAccount(url: URL)
    case linkNewDevice
    case secureBackup
    case appLock
}

final class SecuritySettingsScreenCoordinator: CoordinatorProtocol {
    private let viewModel: SecuritySettingsScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<SecuritySettingsScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<SecuritySettingsScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: SecuritySettingsScreenCoordinatorParameters) {
        viewModel = SecuritySettingsScreenViewModel(userSession: parameters.userSession,
                                                    appSettings: parameters.appSettings)
        
        viewModel.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .newPhrase(let addsFirstPhrase):
                    actionsSubject.send(.newPhrase(addsFirstPhrase: addsFirstPhrase))
                case .addApple:
                    actionsSubject.send(.addApple)
                case .manageAccount(let url):
                    actionsSubject.send(.manageAccount(url: url))
                case .linkNewDevice:
                    actionsSubject.send(.linkNewDevice)
                case .secureBackup:
                    actionsSubject.send(.secureBackup)
                case .appLock:
                    actionsSubject.send(.appLock)
                }
            }
            .store(in: &cancellables)
    }
    
    /// A New phrase or Add Apple flow ended, whatever its outcome: the rows read the
    /// account again and the rows take taps again.
    func signInFlowFinished() {
        viewModel.signInFlowFinished()
    }
    
    func toPresentable() -> AnyView {
        AnyView(SecuritySettingsScreen(context: viewModel.context))
    }
}
