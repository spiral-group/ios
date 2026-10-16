//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import UserNotifications

protocol UserNotificationCenterProtocol: AnyObject {
    var delegate: UNUserNotificationCenterDelegate? { get set }
    func add(_ request: UNNotificationRequest) async throws
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func deliveredNotifications() async -> [UNNotification]
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func authorizationStatus() async -> UNAuthorizationStatus
    func notificationSettings() async -> UNNotificationSettings
    /// AGENT-PLATFORM: on the protocol so the badge the user sees is
    /// assertable in tests. Before this, the only writers were the NSE and
    /// logout, and neither was reachable from a test.
    func setBadgeCount(_ count: Int) async throws
}

// sourcery: AutoMockable
extension UserNotificationCenterProtocol { }
