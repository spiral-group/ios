//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import UserNotifications

nonisolated extension UNNotificationContent {
    @objc var receiverID: String? {
        userInfo[NotificationConstants.UserInfoKey.receiverIdentifier] as? String
    }
    
    @objc var roomID: String? {
        userInfo[NotificationConstants.UserInfoKey.roomIdentifier] as? String
    }
    
    @objc var eventID: String? {
        userInfo[NotificationConstants.UserInfoKey.eventIdentifier] as? String
    }
    
    @objc var eventDate: Date? {
        userInfo[NotificationConstants.UserInfoKey.eventDate] as? Date
    }
    
    @objc var pusherNotificationClientIdentifier: String? {
        userInfo[NotificationConstants.UserInfoKey.pusherNotificationClientIdentifier] as? String
    }
    
    @objc var threadRootEventID: String? {
        userInfo[NotificationConstants.UserInfoKey.threadRootEventIdentifier] as? String
    }
    
    // AGENT-PLATFORM: the approval a Spiral direct push names
    // (`{spiral: {kind: "approval", id}}`, set by
    // `SpiralPushContentBuilder`). Drives the tap-deep-link path: a
    // tap routes to `ApprovalDetailScreen` rather than the standard
    // room-list jump.
    @objc var agentApprovalID: String? {
        userInfo[NotificationConstants.UserInfoKey.agentApprovalIdentifier] as? String
    }

    // AGENT-PLATFORM: the verification a Spiral direct push names
    // (`{spiral: {kind: "verification", id}}`, set by
    // `SpiralPushContentBuilder`). A tap routes to
    // `VerificationDetailScreen`. No inline actions (see
    // Category.verification doc-comment for rationale).
    @objc var agentVerificationID: String? {
        userInfo[NotificationConstants.UserInfoKey.agentVerificationIdentifier] as? String
    }

    // AGENT-PLATFORM (Brief 0066, § 5.82): the post a game's ping was made in.
    @objc var spiralPostEventID: String? {
        userInfo[NotificationConstants.UserInfoKey.spiralPostEventIdentifier] as? String
    }
}

nonisolated extension UNMutableNotificationContent {
    override var receiverID: String? {
        get {
            userInfo[NotificationConstants.UserInfoKey.receiverIdentifier] as? String
        }
        set {
            userInfo[NotificationConstants.UserInfoKey.receiverIdentifier] = newValue
        }
    }
    
    override var roomID: String? {
        get {
            userInfo[NotificationConstants.UserInfoKey.roomIdentifier] as? String
        }
        set {
            userInfo[NotificationConstants.UserInfoKey.roomIdentifier] = newValue
        }
    }
    
    override var eventID: String? {
        get {
            userInfo[NotificationConstants.UserInfoKey.eventIdentifier] as? String
        }
        set {
            userInfo[NotificationConstants.UserInfoKey.eventIdentifier] = newValue
        }
    }
    
    override var eventDate: Date? {
        get {
            userInfo[NotificationConstants.UserInfoKey.eventDate] as? Date
        }
        set {
            userInfo[NotificationConstants.UserInfoKey.eventDate] = newValue
        }
    }
    
    override var threadRootEventID: String? {
        get {
            userInfo[NotificationConstants.UserInfoKey.threadRootEventIdentifier] as? String
        }
        set {
            userInfo[NotificationConstants.UserInfoKey.threadRootEventIdentifier] = newValue
        }
    }

    // AGENT-PLATFORM: setter for the NSE decorator path.
    override var agentApprovalID: String? {
        get {
            userInfo[NotificationConstants.UserInfoKey.agentApprovalIdentifier] as? String
        }
        set {
            userInfo[NotificationConstants.UserInfoKey.agentApprovalIdentifier] = newValue
        }
    }

    // AGENT-PLATFORM: setter for the NSE decorator path (S157.a).
    override var agentVerificationID: String? {
        get {
            userInfo[NotificationConstants.UserInfoKey.agentVerificationIdentifier] as? String
        }
        set {
            userInfo[NotificationConstants.UserInfoKey.agentVerificationIdentifier] = newValue
        }
    }

    // AGENT-PLATFORM (Brief 0066, § 5.82): set by the NSE for a game's ping.
    override var spiralPostEventID: String? {
        get {
            userInfo[NotificationConstants.UserInfoKey.spiralPostEventIdentifier] as? String
        }
        set {
            userInfo[NotificationConstants.UserInfoKey.spiralPostEventIdentifier] = newValue
        }
    }
}
