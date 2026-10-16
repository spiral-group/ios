//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import UserNotifications

protocol NotificationManagerDelegate: AnyObject {
    func shouldDisplayInAppNotification(content: UNNotificationContent) -> Bool
    func notificationTapped(content: UNNotificationContent) async
    func handleInlineReply(_ service: NotificationManagerProtocol,
                           content: UNNotificationContent,
                           replyText: String) async
    // AGENT-PLATFORM: invoked by an Approve/Reject UNNotificationAction
    // tap on an approval-category notification. Runs in the main app
    // process (background-launched if necessary); guarded by
    // UIApplication.beginBackgroundTask in the implementation so the
    // POST completes even if the user dismisses the notification UI
    // immediately. See LEARNING.md L154-4 for the architectural
    // rationale ("don't use background URLSession for sub-second POSTs").
    func handleApprovalAction(_ service: NotificationManagerProtocol,
                              content: UNNotificationContent,
                              decision: ApprovalDecision) async
    func registerForRemoteNotifications()
    func unregisterForRemoteNotifications()
}

// MARK: - NotificationManagerProtocol

// sourcery: AutoMockable
protocol NotificationManagerProtocol: AnyObject {
    var delegate: NotificationManagerDelegate? { get set }
    
    func start()
    func register(with deviceToken: Data) async -> Bool
    func registrationFailed(with error: Error)
    func showLocalNotification(with title: String, subtitle: String?) async
    func setUserSession(_ userSession: UserSessionProtocol?)
    
    func requestAuthorization()
    
    func removeDeliveredMessageNotifications(for roomID: String) async
    
    func removeDeliveredNotificationsForFullyReadRooms(_ rooms: [RoomSummary]) async
    /// AGENT-PLATFORM: recompute the icon badge from the room list's own
    /// truth. See `NotificationManager.updateBadgeCount`.
    func updateBadgeCount(with rooms: [RoomSummary]) async
}
