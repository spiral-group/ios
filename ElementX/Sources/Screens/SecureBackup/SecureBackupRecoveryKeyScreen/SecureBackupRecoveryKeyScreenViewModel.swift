//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias SecureBackupRecoveryKeyScreenViewModelType = StateStoreViewModelV2<SecureBackupRecoveryKeyScreenViewState, SecureBackupRecoveryKeyScreenViewAction>

class SecureBackupRecoveryKeyScreenViewModel: SecureBackupRecoveryKeyScreenViewModelType, SecureBackupRecoveryKeyScreenViewModelProtocol {
    private let secureBackupController: SecureBackupControllerProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    
    private var actionsSubject: PassthroughSubject<SecureBackupRecoveryKeyScreenViewModelAction, Never> = .init()
    var actions: AnyPublisher<SecureBackupRecoveryKeyScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(secureBackupController: SecureBackupControllerProtocol,
         userIndicatorController: UserIndicatorControllerProtocol,
         isModallyPresented: Bool) {
        self.secureBackupController = secureBackupController
        self.userIndicatorController = userIndicatorController
        
        super.init(initialViewState: .init(isModallyPresented: isModallyPresented,
                                           mode: secureBackupController.recoveryState.value.viewMode,
                                           bindings: .init()))
    }
    
    // MARK: - Public
    
    override func process(viewAction: SecureBackupRecoveryKeyScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")
        
        switch viewAction {
        case .generateKey:
            state.isGeneratingKey = true
            
            Task {
                switch await secureBackupController.generateRecoveryKey(withPassphrase: nil) {
                case .success(let key):
                    state.recoveryKey = key
                case .failure(let error):
                    MXLog.error("Failed generating recovery key with error: \(error)")
                    state.bindings.alertInfo = .init(id: .init())
                }
                
                state.isGeneratingKey = false
            }
        case .copyKey:
            UIPasteboard.general.string = state.recoveryKey
            userIndicatorController.submitIndicator(.init(title: UntranslatedL10n.screenRecoveryKeyCopiedToClipboardSpiral)) // AGENT-PLATFORM (Brief 0083, decision 314)
            state.doneButtonEnabled = true
        case .keySaved:
            state.doneButtonEnabled = true
        case .confirmKey:
            Task {
                showLoadingIndicator()
                
                switch await secureBackupController.confirmRecoveryKey(state.bindings.confirmationRecoveryKey) {
                case .success:
                    actionsSubject.send(.done(mode: state.mode))
                case .failure(let error):
                    MXLog.error("Failed confirming recovery key with error: \(error)")
                    // AGENT-PLATFORM (Brief 0083, decision 314): Spiral's copy.
                    state.bindings.alertInfo = .init(id: .init(),
                                                     title: UntranslatedL10n.screenRecoveryKeyConfirmErrorTitleSpiral,
                                                     message: UntranslatedL10n.screenRecoveryKeyConfirmErrorContentSpiral)
                }
                
                hideLoadingIndicator()
            }
        case .cancel:
            actionsSubject.send(.cancel)
        case .retry:
            // AGENT-PLATFORM (1.0.2): the unknown state had no way out but Cancel.
            state.mode = secureBackupController.recoveryState.value.viewMode
        case .done:
            // AGENT-PLATFORM (Brief 0083, decision 314): Spiral's copy.
            state.bindings.alertInfo = .init(id: .init(),
                                             title: UntranslatedL10n.screenRecoveryKeySetupConfirmationTitleSpiral,
                                             message: UntranslatedL10n.screenRecoveryKeySetupConfirmationDescriptionSpiral,
                                             primaryButton: .init(title: L10n.actionContinue) { [weak self] in
                                                 guard let self else { return }
                                                 actionsSubject.send(.done(mode: state.mode))
                                             },
                                             secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
        }
    }
    
    private static let loadingIndicatorIdentifier = "\(SecureBackupRecoveryKeyScreenViewModel.self)-Loading"
    
    private func showLoadingIndicator() {
        userIndicatorController.submitIndicator(UserIndicator(id: Self.loadingIndicatorIdentifier,
                                                              type: .modal,
                                                              title: L10n.commonLoading,
                                                              persistent: true))
    }
    
    private func hideLoadingIndicator() {
        userIndicatorController.retractIndicatorWithId(Self.loadingIndicatorIdentifier)
    }
}

private extension SecureBackupRecoveryState {
    var viewMode: SecureBackupRecoveryKeyScreenViewMode {
        switch self {
        case .disabled:
            return .setupRecovery
        case .enabled:
            return .changeRecovery
        case .incomplete:
            return .fixRecovery
        default:
            return .unknown
        }
    }
}
