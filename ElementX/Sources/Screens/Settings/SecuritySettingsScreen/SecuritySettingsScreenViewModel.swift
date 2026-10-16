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
    
    init(userSession: UserSessionProtocol, appSettings: AppSettings) {
        super.init(initialViewState: .init(showLinkNewDeviceButton: appSettings.linkNewDeviceEnabled))
        
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
    }
    
    override func process(viewAction: SecuritySettingsScreenViewAction) {
        switch viewAction {
        case .newPhrase:
            state.bindings.alertInfo = AlertInfo(id: .newPhrase,
                                                 title: UntranslatedL10n.screenSettingsNewPhraseTitle,
                                                 message: UntranslatedL10n.screenSettingsNewPhraseMessage,
                                                 primaryButton: .init(title: L10n.actionContinue) { [weak self] in
                                                     self?.process(viewAction: .confirmNewPhrase)
                                                 },
                                                 secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
        case .confirmNewPhrase:
            actionsSubject.send(.newPhrase)
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
