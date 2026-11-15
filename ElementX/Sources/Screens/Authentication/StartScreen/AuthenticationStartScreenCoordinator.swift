//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct AuthenticationStartScreenParameters {
    let authenticationService: AuthenticationServiceProtocol
    // AGENT-PLATFORM (Brief 0083 L1b): no provisioningParameters, Element's provisioning links are gone.
    let isBugReportServiceEnabled: Bool
    // AGENT-PLATFORM (Brief 0083 L1b): no appMediator or mediaProvider, only Element Classic's account used them.
    let appSettings: AppSettings
    let userIndicatorController: UserIndicatorControllerProtocol
}

enum AuthenticationStartScreenCoordinatorAction {
    case loginWithQR
    case login
    case register
    
    case loginDirectlyWithOAuth(data: OAuthAuthorizationDataProxy, window: UIWindow)
    case loginDirectlyWithPassword(loginHint: String?)
    
    case reportProblem
    case developerOptions
}

final class AuthenticationStartScreenCoordinator: CoordinatorProtocol {
    private var viewModel: AuthenticationStartScreenViewModelProtocol
    private let actionsSubject: PassthroughSubject<AuthenticationStartScreenCoordinatorAction, Never> = .init()
    private var cancellables = Set<AnyCancellable>()
    
    var actions: AnyPublisher<AuthenticationStartScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: AuthenticationStartScreenParameters) {
        viewModel = AuthenticationStartScreenViewModel(authenticationService: parameters.authenticationService,
                                                       isBugReportServiceEnabled: parameters.isBugReportServiceEnabled,
                                                       appSettings: parameters.appSettings,
                                                       userIndicatorController: parameters.userIndicatorController) // AGENT-PLATFORM (Brief 0083 L1b)
    }
    
    // MARK: - Public
    
    func start() {
        viewModel.actions
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .loginWithQR:
                    actionsSubject.send(.loginWithQR)
                case .login:
                    actionsSubject.send(.login)
                case .register:
                    actionsSubject.send(.register)
                    
                case .loginDirectlyWithOAuth(let data, let window):
                    actionsSubject.send(.loginDirectlyWithOAuth(data: data, window: window))
                case .loginDirectlyWithPassword(let loginHint):
                    actionsSubject.send(.loginDirectlyWithPassword(loginHint: loginHint))
                    
                case .reportProblem:
                    actionsSubject.send(.reportProblem)
                case .developerOptions:
                    actionsSubject.send(.developerOptions)
                }
            }
            .store(in: &cancellables)
    }
    
    func toPresentable() -> AnyView {
        AnyView(AuthenticationStartScreen(context: viewModel.context))
    }
}
