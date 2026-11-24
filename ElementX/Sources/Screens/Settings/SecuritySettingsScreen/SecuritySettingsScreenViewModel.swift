//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (decision 187): the Security hub.
// The Spiral feature is built on Element's `SettingsScreenViewModel.swift`.
//

import Combine
import SwiftUI

typealias SecuritySettingsScreenViewModelType = StateStoreViewModelV2<SecuritySettingsScreenViewState, SecuritySettingsScreenViewAction>

class SecuritySettingsScreenViewModel: SecuritySettingsScreenViewModelType, SecuritySettingsScreenViewModelProtocol {
    private let actionsSubject: PassthroughSubject<SecuritySettingsScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<SecuritySettingsScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    private let agentPlatformService: AgentPlatformServiceProtocol?
    private let accountSettings: AccountSettings
    private var signInMethodsTask: Task<Void, Never>?
    /// A New phrase or Add Apple flow is running; a second tap starts nothing until it ends.
    private var isSignInFlowRunning = false
    
    init(userSession: UserSessionProtocol, appSettings: AppSettings) {
        agentPlatformService = userSession.agentPlatformService
        accountSettings = userSession.userSettings.account
        // The last answer draws the rows on the first frame; the refresh below changes them only if it differs.
        let cachedSignInMethods = agentPlatformService != nil ? accountSettings.signInMethods : nil
        super.init(initialViewState: .init(showLinkNewDeviceButton: appSettings.linkNewDeviceEnabled,
                                           signInMethods: cachedSignInMethods ?? .unknown))
        
        appSettings.linkNewDeviceEnabledPublisher
            .weakAssign(to: \.state.showLinkNewDeviceButton, on: self)
            .store(in: &cancellables)
        
        userSession.sessionSecurityStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] securityState in
                self?.state.showEncryption = securityState.showsEncryptionSettings
                self?.state.showEncryptionBadge = securityState.needsRecoverySetup
            }
            .store(in: &cancellables)
        
        Task { await state.accountProfileURL = userSession.clientProxy.accountURL(action: .profile) }
        loadSignInMethods()
    }
    
    isolated deinit {
        signInMethodsTask?.cancel()
    }
    
    /// A failure keeps what is shown: the cached answer, or unknown on the
    /// very first read (today's wording, no Apple row).
    func loadSignInMethods() {
        guard let agentPlatformService else { return }
        signInMethodsTask?.cancel()
        signInMethodsTask = Task { [weak self] in
            let result = await agentPlatformService.fetchSignInMethods()
            // Signed out meanwhile: the account's settings are gone and stay gone.
            guard !Task.isCancelled, let self, !accountSettings.isReset else { return }
            switch result {
            case .success(let answer):
                let methods = answer.filling(from: state.signInMethods)
                if state.signInMethods != methods {
                    state.signInMethods = methods
                }
                if accountSettings.signInMethods != methods {
                    accountSettings.signInMethods = methods
                }
            case .failure(let error):
                MXLog.warning("Sign-in methods unknown: \(error)")
            }
        }
    }
    
    /// The flow ended, whatever its outcome: a sheet closed after the server already changed
    /// the account, or a failure, may still have changed what the account has.
    func signInFlowFinished() {
        isSignInFlowRunning = false
        loadSignInMethods()
    }
    
    override func process(viewAction: SecuritySettingsScreenViewAction) {
        switch viewAction {
        case .newPhrase:
            let addsFirstPhrase = state.signInMethods.addsFirstPhrase
            state.bindings.alertInfo = AlertInfo(id: .newPhrase,
                                                 title: state.phraseRowTitle,
                                                 message: addsFirstPhrase ? UntranslatedL10n.screenSettingsAddPhraseMessage : UntranslatedL10n.screenSettingsNewPhraseMessage,
                                                 primaryButton: .init(title: L10n.actionContinue) { [weak self] in
                                                     self?.process(viewAction: .confirmNewPhrase)
                                                 },
                                                 secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
        case .confirmNewPhrase:
            guard !isSignInFlowRunning else { return }
            isSignInFlowRunning = true
            actionsSubject.send(.newPhrase(addsFirstPhrase: state.signInMethods.addsFirstPhrase))
        case .addApple:
            guard !isSignInFlowRunning else { return }
            isSignInFlowRunning = true
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
}
