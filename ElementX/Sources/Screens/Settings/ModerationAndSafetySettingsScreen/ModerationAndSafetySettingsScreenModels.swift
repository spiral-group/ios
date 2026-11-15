//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM (decision 187): Spiral's «Privacy» screen — upstream's Moderation
// and safety plus the third-party AI consent row (it replaced our trimmed
// AdvancedSettingsScreen, which upstream deleted in #6288).

import Foundation
import UIKit

enum ModerationAndSafetySettingsScreenViewModelAction {
    case blockedUsers
}

struct ModerationAndSafetySettingsScreenViewState: BindableState {
    var hideInviteAvatars: Bool
    var isWaitingHideInviteAvatars = false
    
    var timelineMediaVisibility: TimelineMediaVisibility
    var isWaitingTimelineMediaVisibility = false
    
    var showBlockedUsers = false
    
    // AGENT-PLATFORM (Brief 0083, question 359): consent to third-party AI (Brief 0078 phase 2). One read state,
    // which `init` starts: the row stands from the first frame, so nothing moves when the read answers.
    var aiConsent = ModerationAndSafetyAIConsent.unavailable
    var isWaitingAIConsent = false
    
    var bindings: ModerationAndSafetySettingsScreenViewStateBindings
}

// AGENT-PLATFORM (Brief 0083, question 359): the consent row. The switch writes only what was just read.
nonisolated enum ModerationAndSafetyAIConsent: Equatable {
    /// No platform on this account: no row.
    case unavailable
    /// This opening's read is out. The value is what this session last knew, `nil` before any read; neither takes a tap.
    case reading(isGranted: Bool?)
    /// This opening's read answered: the switch takes taps.
    case answered(isGranted: Bool)
    /// Decision 150: this opening's read failed. It is never "no consent", and a remembered value doesn't stand in for it.
    case failed
    
    var isGranted: Bool? {
        switch self {
        case .reading(let isGranted): isGranted
        case .answered(let isGranted): isGranted
        case .unavailable, .failed: nil
        }
    }
    
    var takesTaps: Bool {
        if case .answered = self { true } else { false }
    }
}

struct ModerationAndSafetySettingsScreenViewStateBindings {
    private let userSettings: UserSettings
    
    init(userSettings: UserSettings) {
        self.userSettings = userSettings
    }
    
    var sharePresence: Bool {
        get { userSettings.account.sharePresence }
        set { userSettings.account.sharePresence = newValue }
    }
}

enum ModerationAndSafetySettingsScreenViewAction {
    case updateHideInviteAvatars(Bool)
    case updateTimelineMediaVisibility(TimelineMediaVisibility)
    case blockedUsers
    case updateAIConsent(Bool) // AGENT-PLATFORM (Brief 0078 phase 2)
    case retryAIConsent // AGENT-PLATFORM (decision 150)
}
