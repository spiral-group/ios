//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum UITestsScreenIdentifier: String {
    case appLockFlow
    case appLockFlowAlternateWindow
    case appLockFlowDisabled
    case appLockFlowDisabledAlternateWindow
    case appLockSetupFlow
    case appLockSetupFlowMandatory
    case appLockSetupFlowUnlock
    case authenticationFlow
    // AGENT-PLATFORM (Brief 0083 L1b): no provisionedAuthenticationFlow, Element's provisioning links are gone.
    case singleProviderAuthenticationFlow
    case multipleProvidersAuthenticationFlow
    case bugReport
    case createPoll
    case encryptionSettings
    case encryptionSettingsOutOfSync
    case encryptionReset
    case linkNewDevice
    case linkNewDeviceWithAppLockPIN
    case roomLayoutBottom
    case roomLayoutMiddle
    case roomLayoutTop
    case roomLayoutHighlight
    case roomMembersListScreenPendingInvites
    case roomMembersFlowWithAssistant // AGENT-PLATFORM (Brief 0078): a profile that can erase what the assistants know.
    case roomPlainNoAvatar
    case roomRolesAndPermissionsFlow
    case roomSmallTimeline
    case roomSmallTimelineIncomingAndSmallPagination
    case roomSmallTimelineLargePagination
    case roomSmallTimelineWithReactions
    case roomSmallTimelineWithReadReceipts
    case roomWithDisclosedPolls
    case roomWithOutgoingPolls
    case roomWithUndisclosedPolls
    case serverSelection
    case spiralTabBarBadge // AGENT-PLATFORM (coverage walk F3)
    case feedPostCard // AGENT-PLATFORM: feed (Brief 0082): a tap on a card's text opens the post.
    case feedScreen // AGENT-PLATFORM: feed (Brief 0082): Latest with its pinned post, on the mock service.
    case interactivePostCatalog // AGENT-PLATFORM (question 412): the catalogue in its sheet, a card opens the post page.
    case interactivePostCatalogIntroduction // AGENT-PLATFORM (question 412): the same, on its first opening.
    case mediaViewer // AGENT-PLATFORM (Brief 0083, question 398): close at the top, share and info at the bottom.
    case sessionVerification
    case startChatFlow
    case userSessionScreen
    case userSessionScreenReply
    case userSessionSpacesFlow
    case autoUpdatingTimeline
}

extension UITestsScreenIdentifier: CustomStringConvertible {
    var description: String {
        rawValue.titlecased()
    }
}

private extension String {
    func titlecased() -> String {
        replacingOccurrences(of: "([A-Z])",
                             with: " $1",
                             options: .regularExpression,
                             range: range(of: self))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
    }
}
