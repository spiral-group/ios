//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias AIConsentPromptScreenViewModelType = StateStoreViewModelV2<AIConsentPromptScreenViewState, AIConsentPromptScreenViewAction>

/// Brief 0078 phase 2 (App Review 5.1.2(i)): asks before anything the person
/// writes or says reaches third-party AI, and records the answer on the
/// server, which applies it.
class AIConsentPromptScreenViewModel: AIConsentPromptScreenViewModelType, AIConsentPromptScreenViewModelProtocol {
    private let agentPlatformService: AgentPlatformServiceProtocol
    private let actionsSubject: PassthroughSubject<AIConsentPromptScreenViewModelAction, Never> = .init()
    
    var actionsPublisher: AnyPublisher<AIConsentPromptScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(agentPlatformService: AgentPlatformServiceProtocol, privacyURL: URL) {
        self.agentPlatformService = agentPlatformService
        super.init(initialViewState: .init(privacyURL: privacyURL))
    }
    
    override func process(viewAction: AIConsentPromptScreenViewAction) {
        guard !state.isSaving else { return }
        // Set before the task starts, so a second tap meanwhile can't save twice.
        state.isSaving = true
        switch viewAction {
        case .allow:
            Task { await record(granted: true) }
        case .notNow:
            Task { await record(granted: false) }
        }
    }
    
    /// Once answered the buttons stay off: the screen is still on screen
    /// while the next one comes in, and a tap then must not answer again.
    private func record(granted: Bool) async {
        switch await agentPlatformService.setAIConsent(granted: granted) {
        case .success:
            MXLog.info("Recorded the AI consent decision (granted: \(granted)).")
            actionsSubject.send(.done)
        case .failure(let error):
            MXLog.error("Recording the AI consent decision failed: \(error)")
            if granted {
                state.isSaving = false
                state.bindings.alertInfo = .init(id: .saveFailed,
                                                 title: L10n.commonError,
                                                 message: UntranslatedL10n.screenAiConsentPromptFailed)
            } else {
                // Nothing reaches AI without a grant, so an unsaved «Not now»
                // only means the prompt comes back next time.
                actionsSubject.send(.done)
            }
        }
    }
}
