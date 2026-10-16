//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

nonisolated enum NotificationConstants {
    enum UserInfoKey {
        static let roomIdentifier = "room_id"
        static let eventIdentifier = "event_id"
        static let threadRootEventIdentifier = "thread_root_event_id"
        static let unreadCount = "unread_count"
        static let pusherNotificationClientIdentifier = "pusher_notification_client_identifier"
        static let receiverIdentifier = "receiver_id"
        // AGENT-PLATFORM: the approval a Spiral direct push names;
        // lets the app open ApprovalDetailScreen directly on tap.
        static let agentApprovalIdentifier = "agent_approval_id"
        // AGENT-PLATFORM: the verification a Spiral direct push
        // names; opens VerificationDetailScreen on tap.
        static let agentVerificationIdentifier = "agent_verification_id"
        // AGENT-PLATFORM (Brief 0066, § 5.82): the Interactive Post a game's
        // ping was made in; a tap opens the room on it.
        static let spiralPostEventIdentifier = "spiral_post_event_id"
    }
    
    enum Category {
        static let message = "message"
        static let invite = "invite"
        // AGENT-PLATFORM: an approval's push. Opens
        // ApprovalDetailScreen on tap; Approve / Reject on the lock
        // screen.
        static let approval = "agent-platform.approval"
        // AGENT-PLATFORM: notifications carrying an
        // `agentVerificationIdentifier` userInfo key (S157.a).
        // Opens VerificationDetailScreen on tap. NO inline
        // actions on the lock screen — confirming a verification
        // requires the owner to visually compare the SAS emoji
        // grid, which is impossible from a notification banner,
        // and reject-without-confirm is a footgun (strict-SAS
        // "rubber-stamping defeats the point" rationale). Tap
        // is the only affordance.
        static let verification = "agent-platform.verification"
        // AGENT-PLATFORM: an approval that asks to block someone (operator
        // question 88). Tap-only: the owner sees whom it blocks on the card
        // before deciding, so the lock screen offers no Approve or Reject.
        static let blockRequest = "agent-platform.approval.block-request"
    }
    
    enum Action {
        static let inlineReply = "inline-reply"
        // AGENT-PLATFORM: the approval category's lock-screen actions
        // (`ApprovalActionRunner`).
        static let approvalApprove = "agent-platform.approval.approve"
        static let approvalReject = "agent-platform.approval.reject"
    }
}
