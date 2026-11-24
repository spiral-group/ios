//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import MatrixRustSDKMocks
@testable import Spiral
import Testing
import UIKit

@MainActor
final class AuthenticationStartScreenViewModelTests {
    var clientFactory: ClientFactoryMock!
    var client: ClientSDKMock!
    var appSettings: AppSettings!
    var authenticationService: AuthenticationServiceProtocol!
    
    var viewModel: AuthenticationStartScreenViewModel!
    var context: AuthenticationStartScreenViewModel.Context {
        viewModel.context
    }
    
    /// Set by `setAllowedAccountProviders` so the default setup doesn't clobber
    /// a provider list a `singleProvider*` test has explicitly configured.
    private var didOverrideAccountProviders = false
    
    init() {
        appSettings = AppSettings.volatile()
    }
    
    @Test
    func initialState() async throws {
        // Given a view model for the open upstream shape.
        await setupViewModel()
        #expect(authenticationService.homeserver.value.loginMode == .unknown)
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesCallsCount == 0)
        
        // When tapping any of the buttons on the screen
        let actions: [(AuthenticationStartScreenViewAction, AuthenticationStartScreenViewModelAction)] = [
            (.loginWithQR, .loginWithQR),
            (.login, .login),
            // AGENT-PLATFORM (1.0.3): Create account goes straight on, no invitation screen.
            (.register, .register),
            (.reportProblem, .reportProblem)
        ]
        
        for action in actions {
            let deferred = deferFulfillment(viewModel.actions) { $0 == action.1 }
            context.send(viewAction: action.0)
            try await deferred.fulfill()
            
            // Then the authentication service should not be used yet.
            #expect(clientFactory.makeAuthenticationClientServerNameOrBaseURLSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksCallsCount == 0)
            #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesCallsCount == 0)
            #expect(authenticationService.homeserver.value.loginMode == .unknown)
        }
    }
    
    // AGENT-PLATFORM (Brief 0083 L1b): no provisioned* tests, Element's provisioning links are gone.
    
    @Test
    func singleProviderOAuthState() async throws {
        // Given a view model that for an app that only allows the use of a single provider that supports OAuth.
        setAllowedAccountProviders([.generic("company.com")])
        await setupViewModel()
        #expect(authenticationService.homeserver.value.loginMode == .unknown)
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesCallsCount == 0)
        
        // When tapping the login button the authentication service should be used and the screen
        // should request to continue the flow without any server selection needed.
        let deferred = deferFulfillment(viewModel.actions) { $0.isLoginDirectlyWithOAuth }
        context.send(viewAction: .login)
        try await deferred.fulfill()
        
        #expect(clientFactory.makeAuthenticationClientServerNameOrBaseURLSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksCallsCount == 1)
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesCallsCount == 1)
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesReceivedArguments?.prompt == .consent)
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesReceivedArguments?.loginHint == nil)
        #expect(authenticationService.homeserver.value.loginMode == .oAuth(supportsCreatePrompt: false))
    }
    
    @Test
    func singleProviderPasswordState() async throws {
        // Given a view model that for an app that only allows the use of a single provider that does not support OAuth.
        setAllowedAccountProviders([.generic("company.com")])
        await setupViewModel(supportsOAuth: false)
        #expect(authenticationService.homeserver.value.loginMode == .unknown)
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesCallsCount == 0)
        
        // When tapping the login button the authentication service should be used and the screen
        // should request to continue the flow without any server selection needed.
        let deferred = deferFulfillment(viewModel.actions) { $0.isLoginDirectlyWithPassword }
        context.send(viewAction: .login)
        try await deferred.fulfill()
        
        // Then a call to configure service should be made.
        #expect(clientFactory.makeAuthenticationClientServerNameOrBaseURLSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksCallsCount == 1)
        #expect(authenticationService.homeserver.value.loginMode == .password)
    }
    
    // AGENT-PLATFORM (Brief 0083 L1b): no Classic App Account tests, Element Classic's import is gone.
    
    // MARK: - Helpers
    
    // MARK: - Invite links (Brief 0073 / ADR-0008)
    
    @Test
    func pendingInviteRidesOnTheAuthorizationURL() async throws {
        // Given a single-provider app and an invitation the person arrived with.
        setAllowedAccountProviders([.generic("company.com")])
        appSettings.pendingInvite = PendingInvite(token: "Qz8Hf72Kd91", inviterDisplayName: "Alice", inviterUserID: "@alice:spiral.md")
        await setupViewModel()
        #expect(context.viewState.pendingInvite?.inviterDisplayName == "Alice")
        
        // When creating an account.
        let deferred = deferFulfillment(viewModel.actions) { $0.isLoginDirectlyWithOAuth }
        context.send(viewAction: .register)
        let action = try await deferred.fulfill()
        
        // Then the OAuth URL carries the token for MAS → Hydra → identity-login.
        guard case .loginDirectlyWithOAuth(let data, _) = action else {
            Issue.record("Expected the OAuth action")
            return
        }
        let components = try #require(URLComponents(url: data.url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first { $0.name == "spiral_invite" }?.value == "Qz8Hf72Kd91")
        #expect(components.queryItems?.first { $0.name == "spiral_flow" }?.value == "register")
    }
    
    @Test
    func authorizationURLIsUntouchedWithoutAnInvite() async throws {
        setAllowedAccountProviders([.generic("company.com")])
        await setupViewModel()
        #expect(context.viewState.pendingInvite == nil)
        
        let deferred = deferFulfillment(viewModel.actions) { $0.isLoginDirectlyWithOAuth }
        context.send(viewAction: .login)
        let action = try await deferred.fulfill()
        
        guard case .loginDirectlyWithOAuth(let data, _) = action else {
            Issue.record("Expected the OAuth action")
            return
        }
        #expect(data.url.absoluteString == "https://account.company.com/authorize")
    }
    
    /// 1.0.3 (operator, 2026-11-21): no invitation screen — Create account goes straight to the web registration,
    /// whose first step asks for an invitation when none rode along.
    @Test
    func createAccountGoesStraightToTheWebRegistration() async throws {
        setAllowedAccountProviders([.generic("company.com")])
        await setupViewModel()
        
        let deferred = deferFulfillment(viewModel.actions) { $0.isLoginDirectlyWithOAuth }
        context.send(viewAction: .register)
        let action = try await deferred.fulfill()
        
        guard case .loginDirectlyWithOAuth(let data, _) = action else {
            Issue.record("Expected the OAuth action")
            return
        }
        #expect(data.url.absoluteString == "https://account.company.com/authorize?spiral_flow=register")
    }
    
    // AGENT-PLATFORM (Brief 0073): the homeserver has no MSC4108 rendezvous,
    // so the QR sign-in stays hidden until the setting says otherwise.
    @Test
    func qrCodeLoginIsHiddenByDefault() async {
        setAllowedAccountProviders([.generic("company.com")])
        await setupViewModel()
        #expect(!appSettings.qrCodeLoginEnabled)
        #expect(!context.viewState.showQRCodeLoginButton)
    }
    
    // MARK: - Helpers
    
    // AGENT-PLATFORM (Brief 0083 L1b): no provisioning parameters, Classic account or supportsPasswordLogin;
    // only the removed provisioning and Classic tests set them.
    private func setupViewModel(supportsOAuth: Bool = true) async {
        // AGENT-PLATFORM: the fork ships a closed single-provider default
        // (`accountProviders = ["spiral.md"]`, `allowOtherAccountProviders =
        // false`), which changes the start-screen defaults these upstream tests
        // were written against (a provider-less, open configuration). Unless a
        // `singleProvider*` test has explicitly set a provider list, reset to the
        // open upstream shape so the generic OAuth / password behaviour is
        // what's under test.
        if !didOverrideAccountProviders {
            // A non-single list with `allowOtherAccountProviders = true` keeps
            // the VM on its open/default branch (serverName stays nil) —
            // matching the upstream shape these tests assume. An empty list is avoided (some settings consumers
            // index accountProviders[0]).
            setAllowedAccountProviders([.managed(serverName: "matrix.org", baseURL: "https://matrix-client.matrix.org")], allowOtherAccountProviders: true)
        }
        
        // Manually create a configuration as the default account provider setting is immutable.
        client = ClientSDKMock(.init(oAuthLoginURL: supportsOAuth ? "https://account.company.com/authorize" : nil,
                                     supportsOAuthCreatePrompt: false))
        // AGENT-PLATFORM (Brief 0083 L1b): only the server name; the homeserver URL was the Classic account's fallback.
        let configuration = ClientFactoryMock.Configuration(homeserverClients: ["company.com": client])
        
        clientFactory = ClientFactoryMock(configuration)
        authenticationService = AuthenticationService(userSessionManager: UserSessionManagerMock(.init()),
                                                      encryptionKeyProvider: EncryptionKeyProvider(),
                                                      clientFactory: clientFactory,
                                                      appSettings: appSettings,
                                                      appHooks: AppHooks())
        
        viewModel = AuthenticationStartScreenViewModel(authenticationService: authenticationService,
                                                       isBugReportServiceEnabled: true,
                                                       appSettings: appSettings,
                                                       userIndicatorController: UserIndicatorControllerMock())
        
        // Add a fake window in order for the OAuth flow to continue
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            Issue.record("The test host is missing a window scene.")
            return
        }
        viewModel.context.send(viewAction: .updateWindow(UIWindow(windowScene: scene)))
    }
    
    private func setAllowedAccountProviders(_ providers: [AccountProvider], allowOtherAccountProviders: Bool = false) {
        didOverrideAccountProviders = true
        appSettings.override(accountProviders: providers,
                             allowOtherAccountProviders: allowOtherAccountProviders,
                             hideBrandChrome: false,
                             pushGatewayBaseURL: appSettings.pushGatewayBaseURL,
                             oAuthRedirectURL: appSettings.oAuthRedirectURL,
                             oAuthClientURIPath: appSettings.oAuthClientURIPath,
                             websiteURL: appSettings.websiteURL,
                             logoURL: appSettings.logoURL,
                             copyrightURL: appSettings.copyrightURL,
                             acceptableUseURL: appSettings.acceptableUseURL,
                             privacyURL: appSettings.privacyURL,
                             encryptionURL: appSettings.encryptionURL,
                             deviceVerificationURL: appSettings.deviceVerificationURL,
                             chatBackupDetailsURL: appSettings.chatBackupDetailsURL,
                             identityPinningViolationDetailsURL: appSettings.identityPinningViolationDetailsURL,
                             historySharingDetailsURL: appSettings.historySharingDetailsURL, // AGENT-PLATFORM (Brief 0083 L1b): no accountProvisioningHost
                             bugReportApplicationID: appSettings.bugReportApplicationID,
                             analyticsTermsURL: appSettings.analyticsTermsURL,
                             mapTilerConfiguration: AppSettings.bundledMapTilerConfiguration)
    }
}

extension AuthenticationStartScreenViewModelAction {
    var isLoginDirectlyWithOAuth: Bool {
        switch self {
        case .loginDirectlyWithOAuth: true
        default: false
        }
    }
    
    var isLoginDirectlyWithPassword: Bool {
        switch self {
        case .loginDirectlyWithPassword: true
        default: false
        }
    }
}
