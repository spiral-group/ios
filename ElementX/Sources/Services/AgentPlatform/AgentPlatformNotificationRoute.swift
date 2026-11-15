//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: where a tap on an approval, verification or feed push goes.
//

import UserNotifications

extension UNNotificationContent {
    /// The decide screen a Spiral push names — the category and subject id
    /// `SpiralPushContentBuilder` stamped in the NSE. `nil` for any other
    /// notification, which keeps its own road.
    var agentPlatformRoute: AppRoute? {
        switch categoryIdentifier {
        case NotificationConstants.Category.approval, NotificationConstants.Category.blockRequest:
            agentApprovalID.map { .approvalDetail(approvalID: $0) }
        case NotificationConstants.Category.verification:
            agentVerificationID.map { .verificationDetail(verificationID: $0) }
        // Feed (Brief 0082): a post no longer there opens as "This post isn't available".
        case NotificationConstants.Category.feedNotice:
            .feedNotices
        case NotificationConstants.Category.feedPost:
            (userInfo[NotificationConstants.UserInfoKey.feedPostIdentifier] as? String).map { .feedPost(postID: $0.lowercased()) }
        default:
            nil
        }
    }
}
