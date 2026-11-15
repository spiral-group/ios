//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum SecureBackupRecoveryKeyScreenViewModelAction {
    case done(mode: SecureBackupRecoveryKeyScreenViewMode)
    case cancel
}

enum SecureBackupRecoveryKeyScreenViewMode {
    case setupRecovery
    case changeRecovery
    case fixRecovery
    case unknown
}

struct SecureBackupRecoveryKeyScreenViewState: BindableState {
    /// Whether the screen is presented modally or within a navigation stack.
    var isModallyPresented: Bool
    
    var mode: SecureBackupRecoveryKeyScreenViewMode
    
    var recoveryKey: String?
    var isGeneratingKey = false
    var doneButtonEnabled = false
    
    var bindings: SecureBackupRecoveryKeyScreenViewBindings
    
    // AGENT-PLATFORM (Brief 0083, decision 314): Spiral's copy, through `Untranslated.strings`' `*_spiral` keys.
    var title: String {
        switch mode {
        case .setupRecovery:
            return recoveryKey == nil ? UntranslatedL10n.screenRecoveryKeySetupTitleSpiral : UntranslatedL10n.screenRecoveryKeySaveTitleSpiral
        case .changeRecovery:
            return recoveryKey == nil ? UntranslatedL10n.screenRecoveryKeyChangeTitleSpiral : UntranslatedL10n.screenRecoveryKeySaveTitleSpiral
        case .fixRecovery:
            return UntranslatedL10n.screenRecoveryKeyConfirmTitleSpiral
        case .unknown:
            return UntranslatedL10n.screenRecoveryKeyUnknownTitleSpiral
        }
    }
    
    var subtitle: String? {
        switch mode {
        case .setupRecovery:
            return recoveryKey == nil ? UntranslatedL10n.screenRecoveryKeySetupDescriptionSpiral : UntranslatedL10n.screenRecoveryKeySaveDescriptionSpiral
        case .changeRecovery:
            return recoveryKey == nil ? UntranslatedL10n.screenRecoveryKeyChangeDescriptionSpiral : UntranslatedL10n.screenRecoveryKeySaveDescriptionSpiral
        case .fixRecovery:
            return UntranslatedL10n.screenRecoveryKeyConfirmDescriptionSpiral
        case .unknown:
            return UntranslatedL10n.screenRecoveryKeyUnknownDescriptionSpiral
        }
    }
    
    var recoveryKeySubtitle: String? {
        switch mode {
        case .setupRecovery:
            return recoveryKey == nil ? UntranslatedL10n.screenRecoveryKeySetupGenerateKeyDescriptionSpiral : UntranslatedL10n.screenRecoveryKeySaveKeyDescriptionSpiral
        case .changeRecovery:
            return recoveryKey == nil ? UntranslatedL10n.screenRecoveryKeyChangeGenerateKeyDescriptionSpiral : UntranslatedL10n.screenRecoveryKeySaveKeyDescriptionSpiral
        case .fixRecovery:
            return UntranslatedL10n.screenRecoveryKeyConfirmKeyDescriptionSpiral
        default:
            return nil
        }
    }
}

struct SecureBackupRecoveryKeyScreenViewBindings {
    var confirmationRecoveryKey = ""
    var alertInfo: AlertInfo<UUID>?
}

enum SecureBackupRecoveryKeyScreenViewAction {
    case generateKey
    case copyKey
    case keySaved
    case confirmKey
    case done
    case cancel
    /// The recovery state wasn't known when the screen opened: read it again.
    case retry
}
