//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

enum SettingsScreenViewModelAction {
    
    case userDetails
    case userStatusEmojiPicker(EmojiPickerScreenContinuation)
    case invitePeople // AGENT-PLATFORM (Brief 0073).
    // AGENT-PLATFORM (decision 187): the sign-in phrase, devices, Encryption,
    // Screen lock and Link new device are in the Security hub; Blocked users
    // is in Privacy (Advanced settings re-purposed).
    case security
    case privacy
    case notifications
    case yourData // AGENT-PLATFORM (Brief 0078).
    case appearanceAndMedia // AGENT-PLATFORM (decision 187).
    case analytics
    case reportBug
    case about
    // periphery:ignore - AGENT-PLATFORM (decision 188): Labs has no row; kept for upstream syncs.
    case labs
    case developerOptions
    case logout
    case deactivateAccount
}

struct SettingsScreenViewState: BindableState {
    var deviceID: String?
    var userProfile: UserProfile
    /// AGENT-PLATFORM (1.0.3, operator 2026-11-19): the account owner's spiral.md link, shared from the bar.
    /// `nil` when no link can be built (an ID on another homeserver), and the bar shows no share button.
    let shareLink: URL?
    var showUserStatusInput = false
    var showAccountDeactivation: Bool
    /// AGENT-PLATFORM (Brief 0078): the exports, for a Spiral account.
    var showYourData = false
    var showDeveloperOptions: Bool
    
    /// AGENT-PLATFORM (decision 187): Element's "set up recovery" badge, on the Security row.
    var showSecuritySectionBadge = false
    
    let showAnalyticsSettings: Bool
    
    let isBugReportServiceEnabled: Bool
    
    let navigationBarVisibility: Visibility
    
    var bindings: SettingsScreenViewStateBindings
    
    var userStatusRowMode: SettingsScreenUserStatusRow.Mode {
        if bindings.isShowingCustomStatusField {
            .customStatusInput(emoji: bindings.customStatusEmoji)
        } else if let displayedStatus = userProfile.status.displayed {
            .showingStatus(displayedStatus)
        } else {
            .pickStatusButton
        }
    }
}

struct SettingsScreenViewStateBindings {
    private let userSettings: UserSettings
    
    var isPresentingStatusPicker = false
    var customStatusEmoji: Character = "😄"
    var isShowingCustomStatusField = false {
        didSet {
            if !isShowingCustomStatusField {
                customStatusEmoji = "😄" // Reset the emoji.
            }
        }
    }
    
    var isPresentingAccountDeactivationConfirmation = false
    
    var appAppearance: AppAppearance {
        get { userSettings.app.appAppearance }
        set { userSettings.app.appAppearance = newValue }
    }
    
    init(userSettings: UserSettings) {
        self.userSettings = userSettings
    }
}

enum SettingsScreenViewAction {
    
    case userDetails
    case userStatus(UserStatusAction)
    case invitePeople // AGENT-PLATFORM (Brief 0073).
    case security // AGENT-PLATFORM (decision 187).
    case privacy // AGENT-PLATFORM (decision 187).
    case notifications
    case yourData // AGENT-PLATFORM (Brief 0078).
    case appearanceAndMedia // AGENT-PLATFORM (decision 187).
    case analytics
    case reportBug
    case about
    // periphery:ignore - AGENT-PLATFORM (decision 188): Labs has no row; kept for upstream syncs.
    case labs
    case enableDeveloperOptions
    case developerOptions
    case logout
    case deactivateAccount
    
    enum UserStatusAction {
        /// Show status picker sheet to select a preset status.
        case pickStatus
        /// Dismiss the picker sheet and show the custom status input.
        case customStatus
        /// Show the emoji picker to select the emoji for the custom status.
        case pickCustomEmoji
        /// Set the user's status to the provided value.
        case set(UserStatus.Raw)
        /// Clears the user's currently displayed status.
        case clear
        /// Cancel user status picking/input.
        case cancel
    }
}
