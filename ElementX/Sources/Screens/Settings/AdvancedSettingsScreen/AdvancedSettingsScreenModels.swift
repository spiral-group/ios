//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM (decision 187): this is «Privacy» now. Appearance, media
// compression and View source moved out, the live-location slider is gone,
// Blocked users moved in. Upstream deleted the screen in #6288: at the sync
// it maps onto ModerationAndSafetySettingsScreen plus our AI consent row.

import Foundation

enum AdvancedSettingsScreenViewModelAction { // AGENT-PLATFORM (decision 187)
    case blockedUsers
}

struct AdvancedSettingsScreenViewState: BindableState {
    var timelineMediaVisibility: TimelineMediaVisibility
    var hideInviteAvatars: Bool
    var isWaitingTimelineMediaVisibility = false
    var isWaitingHideInviteAvatars = false
    // AGENT-PLATFORM (Brief 0078 phase 2): consent to third-party AI as the
    // server reports it; `nil` until known, and the row stays hidden.
    var aiConsentGranted: Bool?
    var isWaitingAIConsent = false
    /// AGENT-PLATFORM (decision 150): a failed read shows a retry row; it is never read as "no consent".
    var aiConsentLoadFailed = false
    var showBlockedUsers = false // AGENT-PLATFORM (decision 187)
    var bindings: AdvancedSettingsScreenViewStateBindings
}

@dynamicMemberLookup
struct AdvancedSettingsScreenViewStateBindings {
    private let advancedSettings: AdvancedSettingsProtocol
    
    init(advancedSettings: AdvancedSettingsProtocol) {
        self.advancedSettings = advancedSettings
    }
    
    subscript<Setting>(dynamicMember keyPath: ReferenceWritableKeyPath<AdvancedSettingsProtocol, Setting>) -> Setting {
        get { advancedSettings[keyPath: keyPath] }
        set { advancedSettings[keyPath: keyPath] = newValue }
    }
}

enum AdvancedSettingsScreenViewAction {
    case updateTimelineMediaVisibility(TimelineMediaVisibility)
    case updateHideInviteAvatars(Bool)
    case updateAIConsent(Bool) // AGENT-PLATFORM (Brief 0078 phase 2)
    case retryAIConsent // AGENT-PLATFORM (decision 150)
    case blockedUsers // AGENT-PLATFORM (decision 187)
}

protocol AdvancedSettingsProtocol: AnyObject {
    var sharePresence: Bool { get set }
}

extension AppSettings: AdvancedSettingsProtocol { }
