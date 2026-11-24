//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias AuthenticationStartScreenViewModelType = StateStoreViewModelV2<AuthenticationStartScreenViewState, AuthenticationStartScreenViewAction>

class AuthenticationStartScreenViewModel: AuthenticationStartScreenViewModelType, AuthenticationStartScreenViewModelProtocol {
    private let authenticationService: AuthenticationServiceProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    // AGENT-PLATFORM (Brief 0073 / ADR-0008).
    private let appSettings: AppSettings
    
    private let canReportProblem: Bool
    
    private var actionsSubject: PassthroughSubject<AuthenticationStartScreenViewModelAction, Never> = .init()
    
    var actions: AnyPublisher<AuthenticationStartScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    // AGENT-PLATFORM (Brief 0083 L1b): no provisioningParameters (Element's provisioning links), and no
    // appMediator, mediaProvider or notificationCenter: they opened, drew and refreshed the Element Classic account.
    init(authenticationService: AuthenticationServiceProtocol,
         isBugReportServiceEnabled: Bool,
         appSettings: AppSettings,
         userIndicatorController: UserIndicatorControllerProtocol) {
        self.authenticationService = authenticationService
        self.userIndicatorController = userIndicatorController
        self.appSettings = appSettings
        canReportProblem = isBugReportServiceEnabled
        
        let isQRCodeScanningSupported = !ProcessInfo.processInfo.isiOSAppOnMac
        
        let initialViewState = if !appSettings.allowOtherAccountProviders {
            // AGENT-PLATFORM: closed-deployment branch still honours
            // appSettings.showCreateAccountButton instead of forcing false.
            // Our v1.0 SaaS only offers spiral.md but MAS allows open
            // signup, so the Create Account button must remain available.
            AuthenticationStartScreenViewState(serverNameOrBaseURL: appSettings.accountProviders.count == 1 ? appSettings.accountProviders[0].serverNameOrBaseURL : nil,
                                               showCreateAccountButton: appSettings.showCreateAccountButton,
                                               showQRCodeLoginButton: isQRCodeScanningSupported && appSettings.qrCodeLoginEnabled,
                                               hideBrandChrome: appSettings.hideBrandChrome)
        } else { // AGENT-PLATFORM (Brief 0083 L1b): no provisioning link branch
            // The default configuration.
            AuthenticationStartScreenViewState(serverNameOrBaseURL: nil,
                                               showCreateAccountButton: appSettings.showCreateAccountButton,
                                               showQRCodeLoginButton: isQRCodeScanningSupported && appSettings.qrCodeLoginEnabled,
                                               hideBrandChrome: appSettings.hideBrandChrome)
        }
        
        super.init(initialViewState: initialViewState)
        
        // AGENT-PLATFORM (Brief 0073): the invitation arrives through the
        // app coordinator (a deep link or the App Clip); it lands in
        // AppSettings and the banner follows.
        state.pendingInvite = appSettings.pendingInvite
        appSettings.pendingInvitePublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .weakAssign(to: \.state.pendingInvite, on: self)
            .store(in: &cancellables)
    }
    
    override func process(viewAction: AuthenticationStartScreenViewAction) {
        switch viewAction {
        case .updateWindow(let window):
            guard state.window != window else { return }
            state.window = window
        case .reportProblem:
            if canReportProblem {
                actionsSubject.send(.reportProblem)
            }
        case .developerOptions:
            actionsSubject.send(.developerOptions)
            
        case .loginWithQR:
            actionsSubject.send(.loginWithQR)
        case .login:
            Task { await login() }
        case .register:
            // AGENT-PLATFORM (ADR-0005 auth v2): a public single-server
            // messenger goes straight into the provider's OIDC flow —
            // never via the server-confirmation screen. Mirrors `.login`;
            // the identity page itself offers the create-account path
            // (MAS's `prompt=create` is broken upstream, element-hq/
            // matrix-authentication-service#3429, so login/register share
            // one authorization URL on this stack).
            //
            // AGENT-PLATFORM (1.0.3, operator 2026-11-21): no invitation screen here. An invitation that came with a link
            // or the App Clip rides along; without one, the web registration's first step asks for it, with the inviter's
            // name and the used-up and expired cases.
            Task { await register() }
        }
    }
    
    // MARK: - Private
    
    private func login() async { // AGENT-PLATFORM (Brief 0083 L1b): no Element Classic account
        if let serverNameOrBaseURL = state.serverNameOrBaseURL {
            await loginDirectly(using: serverNameOrBaseURL) // AGENT-PLATFORM (Brief 0083 L1b): no provisioning link's login hint
        } else {
            actionsSubject.send(.login) // No need to configure anything here, continue the flow.
        }
    }
    
    // AGENT-PLATFORM (ADR-0005 auth v2): the register twin of `login()` —
    // with the single fixed provider we configure it and jump straight to
    // OAuth; only a provider-less build falls through to the legacy flow.
    private func register() async {
        if let serverNameOrBaseURL = state.serverNameOrBaseURL {
            await loginDirectly(using: serverNameOrBaseURL, flow: .register)
        } else {
            actionsSubject.send(.register)
        }
    }
    
    // AGENT-PLATFORM (Brief 0083 L1b): no fallback URL, only the Classic account had one.
    private func loginDirectly(using serverNameOrBaseURL: String,
                               loginHint: String? = nil,
                               flow: AuthenticationFlow = .login) async { // AGENT-PLATFORM (ADR-0005): `flow`
        startLoading()
        defer { stopLoading() }
        
        if case .failure = await authenticationService.configure(for: serverNameOrBaseURL, flow: flow) {
            // As the server was provisioned, we don't worry about the specifics and show a generic error to the user.
            displayError()
            return
        }
        
        guard authenticationService.homeserver.value.loginMode.supportsOAuthFlow else {
            actionsSubject.send(.loginDirectlyWithPassword(loginHint: loginHint))
            return
        }
        
        guard let window = state.window else {
            displayError()
            return
        }
        
        switch await authenticationService.urlForOAuthLogin(loginHint: loginHint) {
        case .success(let oAuthData):
            actionsSubject.send(.loginDirectlyWithOAuth(data: oAuthData, window: window))
        case .failure:
            displayError()
        }
    }
    
    // MARK: - User Indicators
    
    private let loadingIndicatorID = "\(AuthenticationStartScreenViewModel.self)-Loading"
    
    private func startLoading() {
        userIndicatorController.submitIndicator(UserIndicator(id: loadingIndicatorID,
                                                              type: .modal,
                                                              title: L10n.commonLoading,
                                                              persistent: true))
    }
    
    private func stopLoading() {
        userIndicatorController.retractIndicatorWithId(loadingIndicatorID)
    }
    
    private func displayError() {
        state.bindings.alertInfo = AlertInfo(id: .genericError)
    }
}
