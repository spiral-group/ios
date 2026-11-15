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
    func register(with deviceToken: Data) async
    func registrationFailed(with error: Error)
    func showLocalNotification(with title: String, subtitle: String?) async
    
    /// Starts handling a live account's notifications, replacing the service it had before (e.g. after clearing the cache).
    func add(_ service: NotificationServiceProtocol)
    func remove(userID: String)
    /// Resets the app badge and stops receiving notifications, once no account is signed in.
    func reset()
    /// AGENT-PLATFORM: writes the accounts' badge counts to the icon again, over
    /// whatever the extension left there.
    func updateAppBadgeCount()
}
