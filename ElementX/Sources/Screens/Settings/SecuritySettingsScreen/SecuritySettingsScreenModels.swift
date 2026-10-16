//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (decision 187): the Security hub — the sign-in phrase,
// devices and sessions, the recovery key and the screen lock in one place.
// The Spiral feature is built on Element's `SettingsScreenModels.swift`.
//

import Foundation

enum SecuritySettingsScreenViewModelAction: Equatable {
    case newPhrase
    case manageAccount(url: URL)
    case linkNewDevice
    case secureBackup
    case appLock
}

struct SecuritySettingsScreenViewState: BindableState {
    var accountProfileURL: URL?
    var showLinkNewDeviceButton: Bool
    var showEncryption = false
    var showEncryptionBadge = false
    
    var bindings = SecuritySettingsScreenViewStateBindings()
}

struct SecuritySettingsScreenViewStateBindings {
    /// «New sign-in phrase» asks before Face ID (Brief 0075).
    var alertInfo: AlertInfo<SecuritySettingsScreenAlertType>?
}

enum SecuritySettingsScreenAlertType: Hashable {
    case newPhrase
}

enum SecuritySettingsScreenViewAction {
    case newPhrase
    case confirmNewPhrase
    case manageAccount(url: URL)
    case linkNewDevice
    case secureBackup
    case appLock
}

extension SessionSecurityState {
    /// The Encryption row stays hidden until the session knows whether it is verified.
    var showsEncryptionSettings: Bool {
        verificationState != .unknown
    }
    
    /// Element's "set up recovery" nudge: a verified session whose recovery is off or incomplete.
    /// The main Settings screen shows it on the Security row, the hub on Encryption.
    var needsRecoverySetup: Bool {
        switch (verificationState, recoveryState) {
        case (.verified, .disabled), (.verified, .incomplete): true
        default: false
        }
    }
}
