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
    /// AGENT-PLATFORM (1.0.3): how long Retry waits for the recovery state before it says it still can't tell.
    private let retryTimeout: Duration
    private var retryTask: Task<Void, Never>?
    
    private var actionsSubject: PassthroughSubject<SecureBackupRecoveryKeyScreenViewModelAction, Never> = .init()
    var actions: AnyPublisher<SecureBackupRecoveryKeyScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(secureBackupController: SecureBackupControllerProtocol,
         userIndicatorController: UserIndicatorControllerProtocol,
         isModallyPresented: Bool,
         retryTimeout: Duration = .seconds(10)) {
        self.secureBackupController = secureBackupController
        self.userIndicatorController = userIndicatorController
        self.retryTimeout = retryTimeout
        
        super.init(initialViewState: .init(isModallyPresented: isModallyPresented,
                                           mode: secureBackupController.recoveryState.value.viewMode,
                                           bindings: .init()))
        
        // AGENT-PLATFORM (1.0.3): «Couldn't check your recovery key» settles by itself once the state is known (it
        // usually is after the next sync), rather than wait for a tap that only re-read the cached value.
        secureBackupController.recoveryState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recoveryState in
                self?.settleUnknownMode(with: recoveryState)
            }
            .store(in: &cancellables)
    }
    
    // AGENT-PLATFORM (1.0.3): the screen can go away mid-wait (Back, a dismissal, a sign-out); its persistent loader
    // must not outlive it.
    isolated deinit {
        endRetry()
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
            endRetry() // AGENT-PLATFORM (1.0.3)
            actionsSubject.send(.cancel)
        case .retry:
            // AGENT-PLATFORM (1.0.2): the unknown state had no way out but Cancel.
            retry()
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
    
    // MARK: - Unknown state (AGENT-PLATFORM, 1.0.3)
    
    /// Shows the state if it is known, otherwise waits for it with a loader, and says so if it still can't be told.
    private func retry() {
        let mode = secureBackupController.recoveryState.value.viewMode
        guard mode == .unknown else {
            state.mode = mode
            return
        }
        guard retryTask == nil else { return }
        
        // Cancel stays within reach while it waits.
        userIndicatorController.submitIndicator(UserIndicator(id: loadingIndicatorIdentifier,
                                                              type: .modal(progress: .indeterminate, interactiveDismissDisabled: false, allowsInteraction: true),
                                                              title: L10n.commonLoading,
                                                              persistent: true))
        retryTask = Task { [weak self, retryTimeout] in
            try? await Task.sleep(for: retryTimeout)
            guard !Task.isCancelled, let self else { return }
            endRetry()
            guard state.mode == .unknown else { return }
            MXLog.error("The recovery state is still unknown after a retry.")
            state.bindings.alertInfo = .init(id: .init(), title: L10n.commonError, message: L10n.errorNetworkOrServerIssue)
        }
    }
    
    private func settleUnknownMode(with recoveryState: SecureBackupRecoveryState) {
        guard state.mode == .unknown, recoveryState.viewMode != .unknown else { return }
        endRetry()
        state.mode = recoveryState.viewMode
    }
    
    private func endRetry() {
        guard let retryTask else { return }
        retryTask.cancel()
        self.retryTask = nil
        hideLoadingIndicator()
    }
    
    // AGENT-PLATFORM (1.0.3): per screen, so an old screen's late deinit can't take down a newer one's loader.
    private let loadingIndicatorIdentifier = "\(SecureBackupRecoveryKeyScreenViewModel.self)-Loading-\(UUID().uuidString)"
    
    private func showLoadingIndicator() {
        userIndicatorController.submitIndicator(UserIndicator(id: loadingIndicatorIdentifier,
                                                              type: .modal,
                                                              title: L10n.commonLoading,
                                                              persistent: true))
    }
    
    private func hideLoadingIndicator() {
        userIndicatorController.retractIndicatorWithId(loadingIndicatorIdentifier)
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
