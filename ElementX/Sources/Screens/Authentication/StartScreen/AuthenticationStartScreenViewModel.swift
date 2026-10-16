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
    private let provisioningParameters: AccountProvisioningParameters?
    private let appMediator: AppMediatorProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    // AGENT-PLATFORM (Brief 0073 / ADR-0008).
    private let appSettings: AppSettings
    private let inviteLinkResolver: InviteLinkResolverProtocol
    
    private let canReportProblem: Bool
    
    private var actionsSubject: PassthroughSubject<AuthenticationStartScreenViewModelAction, Never> = .init()
    
    var actions: AnyPublisher<AuthenticationStartScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(authenticationService: AuthenticationServiceProtocol,
         provisioningParameters: AccountProvisioningParameters?,
         isBugReportServiceEnabled: Bool,
         appMediator: AppMediatorProtocol,
         appSettings: AppSettings,
         mediaProvider: MediaProviderProtocol?,
         notificationCenter: NotificationCenter = .default,
         userIndicatorController: UserIndicatorControllerProtocol,
         inviteLinkResolver: InviteLinkResolverProtocol = InviteLinkResolver()) {
        self.authenticationService = authenticationService
        self.provisioningParameters = provisioningParameters
        self.appMediator = appMediator
        self.userIndicatorController = userIndicatorController
        self.appSettings = appSettings
        self.inviteLinkResolver = inviteLinkResolver
        canReportProblem = isBugReportServiceEnabled
        
        let isQRCodeScanningSupported = !ProcessInfo.processInfo.isiOSAppOnMac
        let classicAppAccountProvider = authenticationService.classicAppAccount?.serverName
        let isClassicAppAccountAllowed = classicAppAccountProvider.map { appSettings.accountProviders.contains($0) } ?? false
        
        let initialViewState = if !appSettings.allowOtherAccountProviders {
            // AGENT-PLATFORM: closed-deployment branch still honours
            // appSettings.showCreateAccountButton instead of forcing false.
            // Our v1.0 SaaS only offers spiral.md but MAS allows open
            // signup, so the Create Account button must remain available.
            AuthenticationStartScreenViewState(serverName: appSettings.accountProviders.count == 1 ? appSettings.accountProviders[0] : nil,
                                               showCreateAccountButton: appSettings.showCreateAccountButton,
                                               showQRCodeLoginButton: isQRCodeScanningSupported && appSettings.qrCodeLoginEnabled,
                                               classicAppMode: isClassicAppAccountAllowed ? authenticationService.classicAppAccount.map { .welcomeBack($0) } : nil,
                                               hideBrandChrome: appSettings.hideBrandChrome,
                                               registrationRequiresInvite: appSettings.registrationRequiresInvite)
        } else if let provisioningParameters {
            // We only show the "Sign in to …" button when using a provisioning link.
            AuthenticationStartScreenViewState(serverName: provisioningParameters.accountProvider,
                                               showCreateAccountButton: false,
                                               showQRCodeLoginButton: false,
                                               classicAppMode: nil,
                                               hideBrandChrome: appSettings.hideBrandChrome,
                                               registrationRequiresInvite: appSettings.registrationRequiresInvite)
        } else {
            // The default configuration.
            AuthenticationStartScreenViewState(serverName: nil,
                                               showCreateAccountButton: appSettings.showCreateAccountButton,
                                               showQRCodeLoginButton: isQRCodeScanningSupported && appSettings.qrCodeLoginEnabled,
                                               classicAppMode: authenticationService.classicAppAccount.map { .welcomeBack($0) },
                                               hideBrandChrome: appSettings.hideBrandChrome,
                                               registrationRequiresInvite: appSettings.registrationRequiresInvite)
        }
        
        super.init(initialViewState: initialViewState, mediaProvider: mediaProvider)
        
        // AGENT-PLATFORM (Brief 0073): the invitation arrives through the
        // app coordinator (deep link) or the paste sheet; either way it
        // lands in AppSettings and the banner follows.
        state.pendingInvite = appSettings.pendingInvite
        appSettings.pendingInvitePublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .weakAssign(to: \.state.pendingInvite, on: self)
            .store(in: &cancellables)
        
        notificationCenter.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.reloadClassicAppAccount()
            }
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
            // AGENT-PLATFORM (Brief 0073): without an invitation in hand, ask
            // for one first — the screen also lets the person go on without.
            if state.pendingInvite == nil {
                state.pastedInviteError = nil
                state.bindings.pastedInviteText = ""
                state.bindings.showInvitePasteSheet = true
            } else {
                Task { await register() }
            }
            
        case .continueWithClassic(let account):
            Task { await login(classicAppAccount: account) }
        case .otherOptions(let account):
            state.classicAppMode = .otherOptions(account)
        case .closeOtherOptions(let account):
            state.classicAppMode = .welcomeBack(account)
        case .openClassicApp:
            guard let classicAppDeepLinkURL = InfoPlistReader.main.classicAppDeepLinkURL else { return }
            appMediator.open(classicAppDeepLinkURL)
            
        case .usePastedInvite:
            Task { await usePastedInvite() }
        case .registerWithoutInvite:
            // Invite-only: the button is not shown; refuse the action too.
            guard !state.registrationRequiresInvite else { return }
            state.bindings.showInvitePasteSheet = false
            Task { await register() }
        }
    }
    
    // MARK: - Invitations (Brief 0073 / ADR-0008)
    
    // AGENT-PLATFORM: checks the pasted link against the public landing
    // endpoint before accepting it, so a dead link is refused here and not
    // three screens later on the identity page.
    private func usePastedInvite() async {
        guard let link = SpiralInviteLink.parse(pastedText: state.bindings.pastedInviteText) else {
            state.pastedInviteError = UntranslatedL10n.screenInvitePasteInvalid
            return
        }
        
        state.isCheckingPastedInvite = true
        defer { state.isCheckingPastedInvite = false }
        
        switch await inviteLinkResolver.resolve(link) {
        case .success(.valid(let inviter)):
            appSettings.pendingInvite = PendingInvite(token: link.token,
                                                      inviterDisplayName: inviter?.displayName,
                                                      inviterUserID: inviter?.mxid)
            state.pastedInviteError = nil
            state.bindings.showInvitePasteSheet = false
            await register()
        case .success(.expired):
            state.pastedInviteError = UntranslatedL10n.screenInvitePasteExpired
        case .success(.exhausted):
            state.pastedInviteError = UntranslatedL10n.screenInvitePasteExhausted
        case .success(.invalid):
            state.pastedInviteError = UntranslatedL10n.screenInvitePasteInvalid
        case .failure:
            state.pastedInviteError = UntranslatedL10n.screenInvitePasteUnavailable
        }
    }
    
    // MARK: - Private
    
    private func login(classicAppAccount: ClassicAppAccount? = nil) async {
        if let classicAppAccount {
            if classicAppAccount.state.availableSecrets == .requiresBackup {
                state.bindings.showClassicAppBackupInstructions = true
            } else {
                await configureAccountProvider(classicAppAccount.serverName,
                                               loginHint: "mxid:\(classicAppAccount.userID)",
                                               fallbackHomeserverURL: classicAppAccount.homeserverURL)
            }
        } else if let serverName = state.serverName {
            await configureAccountProvider(serverName, loginHint: provisioningParameters?.loginHint)
        } else {
            actionsSubject.send(.login) // No need to configure anything here, continue the flow.
        }
    }
    
    // AGENT-PLATFORM (ADR-0005 auth v2): the register twin of `login()` —
    // with the single fixed provider we configure it and jump straight to
    // OAuth; only a provider-less build falls through to the legacy flow.
    private func register() async {
        if let serverName = state.serverName {
            await configureAccountProvider(serverName, flow: .register)
        } else {
            actionsSubject.send(.register)
        }
    }
    
    private func configureAccountProvider(_ accountProvider: String,
                                          loginHint: String? = nil,
                                          fallbackHomeserverURL: URL? = nil,
                                          flow: AuthenticationFlow = .login) async {
        startLoading()
        defer { stopLoading() }
        
        if case .failure = await authenticationService.configure(for: accountProvider, flow: flow) {
            // Try the fallback URL before showing an error.
            if let fallbackHomeserverURL,
               case .success = await authenticationService.configure(for: fallbackHomeserverURL.absoluteString, flow: flow) {
                // Fallback succeeded, continue with the flow.
            } else {
                // As the server was provisioned, we don't worry about the specifics and show a generic error to the user.
                // Element Classic accounts aren't shown for unsupported servers either, so nothing to do here.
                displayError()
                return
            }
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
    
    @CancellableTask private var reloadClassicAppSecretsTask: Task<Void, Never>?
    private func reloadClassicAppAccount() {
        guard case let .welcomeBack(classicAppAccount) = state.classicAppMode else { return }
        
        reloadClassicAppSecretsTask = Task { [weak self] in
            await self?.authenticationService.refreshClassicAppAccountState()
            
            guard !Task.isCancelled else { return }
            
            if let availableSecrets = classicAppAccount.state.availableSecrets, availableSecrets != .requiresBackup {
                await MainActor.run { self?.state.bindings.showClassicAppBackupInstructions = false }
            }
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
