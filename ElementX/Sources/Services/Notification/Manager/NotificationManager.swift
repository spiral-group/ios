//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
import UIKit
import UserNotifications

final class NotificationManager: NSObject, NotificationManagerProtocol {
    private let notificationCenter: UserNotificationCenterProtocol
    private let appSettings: AppSettings
    
    private var userSession: UserSessionProtocol?
    
    private var cancellables = Set<AnyCancellable>()
    private var notificationsEnabled = false
    
    init(notificationCenter: UserNotificationCenterProtocol,
         appSettings: AppSettings) {
        self.notificationCenter = notificationCenter
        self.appSettings = appSettings
        super.init()
    }
    
    // MARK: NotificationManagerProtocol
    
    weak var delegate: NotificationManagerDelegate?
    
    func start() {
        let replyAction = UNTextInputNotificationAction(identifier: NotificationConstants.Action.inlineReply,
                                                        title: L10n.actionQuickReply,
                                                        options: [])
        let messageCategory = UNNotificationCategory(identifier: NotificationConstants.Category.message,
                                                     actions: [replyAction],
                                                     intentIdentifiers: [],
                                                     options: [])
        
        let inviteCategory = UNNotificationCategory(identifier: NotificationConstants.Category.invite,
                                                    actions: [],
                                                    intentIdentifiers: [],
                                                    options: [])

        // AGENT-PLATFORM: an approval's push. A tap opens the card;
        // the inline Approve / Reject run in the main app's
        // background-launched process (no NSE, no background
        // URLSession — see LEARNING.md L154-4 for the rationale).
        //
        // `.authenticationRequired`: device must be unlocked before
        // the action body runs, even if the user has actions
        // visible on the lock screen. The button itself shows up
        // pre-unlock; tapping it defers execution until Face ID /
        // passcode succeeds. Matches Element Classic's choice
        // (`PushNotificationService.m:54`) for write-mutating
        // actions.
        //
        // `.destructive`: red colour treatment for Reject only.
        let approveAction = UNNotificationAction(identifier: NotificationConstants.Action.approvalApprove,
                                                 title: UntranslatedL10n.actionApprovalApprove,
                                                 options: [.authenticationRequired])
        let rejectAction = UNNotificationAction(identifier: NotificationConstants.Action.approvalReject,
                                                title: UntranslatedL10n.actionApprovalReject,
                                                options: [.authenticationRequired, .destructive])
        let approvalCategory = UNNotificationCategory(identifier: NotificationConstants.Category.approval,
                                                      actions: [approveAction, rejectAction],
                                                      intentIdentifiers: [],
                                                      options: [])

        // AGENT-PLATFORM: Brief 0041 C6 — the verification family was the
        // only marker category NOT registered (tap-only by design — strict
        // SAS forbids inline decisions, DECISIONS S157.a — but the category
        // must still be known to the system so its default-tap routing and
        // future thread grouping behave like its two siblings).
        let verificationCategory = UNNotificationCategory(identifier: NotificationConstants.Category.verification,
                                                          actions: [],
                                                          intentIdentifiers: [],
                                                          options: [])

        // AGENT-PLATFORM: operator question 88 — a request to block someone
        // is tap-to-review only: the card says whom it blocks before the
        // owner decides, so the lock screen offers no Approve or Reject.
        let blockRequestCategory = UNNotificationCategory(identifier: NotificationConstants.Category.blockRequest,
                                                          actions: [],
                                                          intentIdentifiers: [],
                                                          options: [])

        notificationCenter.setNotificationCategories([messageCategory, inviteCategory, approvalCategory, verificationCategory, blockRequestCategory])
        notificationCenter.delegate = self
        
        notificationsEnabled = appSettings.enableNotifications
        MXLog.info("App setting 'enableNotifications' is '\(notificationsEnabled)'")
        
        // Listen for changes to AppSettings.enableNotifications
        appSettings.enableNotificationsPublisher
            .sink { [weak self] newValue in
                self?.enableNotifications(newValue)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.removeReceivedWhileOfflineNotification()
            }
            .store(in: &cancellables)
    }
    
    func requestAuthorization() {
        guard appSettings.enableNotifications, !userSession.isNil else { return }
        Task {
            do {
                let permissionGranted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
                MXLog.info("Permission granted: \(permissionGranted)")
                await MainActor.run {
                    if permissionGranted {
                        self.delegate?.registerForRemoteNotifications()
                    }
                }
            } catch {
                MXLog.error("Request authorization failed: \(error)")
            }
        }
    }
    
    func register(with deviceToken: Data) async -> Bool {
        guard let userSession else {
            return false
        }
        let pusherSet = await setPusher(with: deviceToken, clientProxy: userSession.clientProxy)
        // AGENT-PLATFORM (Brief 0043, ADR-0057): mirror the device into
        // the Spiral push registry so the orchestrator can notify this
        // device directly (no Matrix carrier event). Best-effort — the
        // hub/SSE reconciles when a push is lost.
        if pusherSet, let agentPlatformService = userSession.agentPlatformService {
            switch await agentPlatformService.registerPushDevice(pushkey: deviceToken.base64EncodedString(),
                                                                 appID: appSettings.pusherAppID) {
            case .success:
                MXLog.info("Spiral push device registered")
            case .failure(let error):
                MXLog.error("Spiral push device registration failed: \(error)")
            }
        }
        return pusherSet
    }
    
    func setUserSession(_ userSession: UserSessionProtocol?) {
        self.userSession = userSession
        
        // If notification permissions were given previously then attempt re-registering
        // for remote notifications on startup. Otherwise let the onboarding flow handle it
        Task { [weak self] in
            guard let self else { return }
            
            if await notificationCenter.authorizationStatus() == .authorized, appSettings.enableNotifications {
                await MainActor.run { [weak self] in
                    self?.delegate?.registerForRemoteNotifications()
                }
            }
            
            let settings = await notificationCenter.notificationSettings()
            MXLog.info("Notification sound enabled: \(settings.soundSetting == .enabled)")
        }
    }
    
    func registrationFailed(with error: Error) {
        MXLog.error("Device token registration failed with error: \(error)")
    }
    
    func showLocalNotification(with title: String, subtitle: String?) async {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle {
            content.subtitle = subtitle
        }
        let request = UNNotificationRequest(identifier: ProcessInfo.processInfo.globallyUniqueString,
                                            content: content,
                                            trigger: nil)
        do {
            try await notificationCenter.add(request)
            MXLog.info("Show local notification succeeded")
        } catch {
            MXLog.error("Show local notification failed: \(error)")
        }
    }
    
    func removeDeliveredMessageNotifications(for roomID: String) async {
        let notificationsIdentifiers = await notificationCenter
            .deliveredNotifications()
            .filter { $0.request.content.roomID == roomID }
            .map(\.request.identifier)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: notificationsIdentifiers)
    }
    
    /// Recompute the app icon badge from what the user would actually see in
    /// the room list.
    ///
    /// AGENT-PLATFORM. The badge had exactly two writers — the NSE, which
    /// copied the homeserver's push count on every notification, and logout,
    /// which zeroed it. Nothing recomputed it when the truth changed: reading
    /// every room left the number sitting there until the *next* push
    /// happened to carry a different one. Verified on a device: the server's
    /// count for the account was 0 while the icon showed 1, and minutes
    /// earlier it had been the reverse.
    ///
    /// The server's number is also not the same quantity the UI shows. In an
    /// encrypted room the homeserver can only match the blanket "encrypted
    /// event" push rule, so it counts events the client deliberately hides —
    /// call notices, agent control flips, reactions — while the room list
    /// counts only what it renders. Deriving from `RoomSummary` here means
    /// the badge answers the same question the dots answer.
    func updateBadgeCount(with rooms: [RoomSummary]) async {
        let seenInvites = appSettings.seenInvites
        let visibility = appSettings.roomListActivityVisibility
        let count = rooms.filter { $0.needsAttention(activityVisibility: visibility, seenInvites: seenInvites) }.count
        
        do {
            try await notificationCenter.setBadgeCount(count)
        } catch {
            // Nothing actionable: the badge simply keeps its previous value
            // until the next recompute, which is the next sync update.
            MXLog.warning("Failed updating the badge count: \(error)")
        }
    }
    
    func removeDeliveredNotificationsForFullyReadRooms(_ rooms: [RoomSummary]) async {
        let roomsToLastMessageDates = rooms
            .filter { $0.hasUnreadMessages == false }
            .reduce(into: [:]) { partialResult, roomSummary in
                partialResult[roomSummary.id] = roomSummary.lastMessageDate
            }
        
        let notificationsIdentifiers = await notificationCenter
            .deliveredNotifications()
            .filter { notification in
                guard let roomID = notification.request.content.roomID,
                      let lastMessageDate = roomsToLastMessageDates[roomID] else {
                    return false
                }
                
                return notification.date <= lastMessageDate
            }
            .map(\.request.identifier)
        
        notificationCenter.removeDeliveredNotifications(withIdentifiers: notificationsIdentifiers)
    }
    
    private func removeReceivedWhileOfflineNotification() {
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [NotificationServiceExtensionActor.receivedWhileOfflineNotificationID])
    }
    
    private func setPusher(with deviceToken: Data, clientProxy: ClientProxyProtocol) async -> Bool {
        do {
            let defaultPayload = APNSPayload(aps: APSInfo(mutableContent: 1,
                                                          alert: APSAlert(locKey: "Notification",
                                                                          locArgs: [])),
                                             pusherNotificationClientIdentifier: clientProxy.pusherNotificationClientIdentifier)
            
            let configuration = try PusherConfiguration(identifiers: .init(pushkey: deviceToken.base64EncodedString(),
                                                                           appId: appSettings.pusherAppID),
                                                        kind: .http(data: .init(url: appSettings.pushGatewayNotifyEndpoint.absoluteString,
                                                                                format: .eventIdOnly,
                                                                                defaultPayload: defaultPayload.toJsonString())),
                                                        appDisplayName: "\(InfoPlistReader.main.bundleDisplayName) (iOS)",
                                                        deviceDisplayName: UIDevice.current.name,
                                                        profileTag: pusherProfileTag(),
                                                        lang: Bundle.app.preferredLocalizations.first ?? "en")
            try await clientProxy.setPusher(with: configuration)
            MXLog.info("Set pusher succeeded")
            return true
        } catch {
            MXLog.error("Set pusher failed: \(error)")
            return false
        }
    }
    
    private func pusherProfileTag() -> String {
        if let currentTag = appSettings.pusherProfileTag {
            return currentTag
        }
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        let newTag = (0..<16).map { _ in
            let offset = Int.random(in: 0..<chars.count)
            return String(chars[chars.index(chars.startIndex, offsetBy: offset)])
        }.joined()
        
        appSettings.pusherProfileTag = newTag
        return newTag
    }
    
    private func enableNotifications(_ enable: Bool) {
        guard notificationsEnabled != enable else { return }
        notificationsEnabled = enable
        MXLog.info("App setting 'enableNotifications' changed to '\(enable)'")
        if enable {
            requestAuthorization()
        } else {
            delegate?.unregisterForRemoteNotifications()
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        guard appSettings.enableInAppNotifications else {
            return []
        }
        guard let delegate else {
            return [.badge, .sound, .list, .banner]
        }
        
        guard delegate.shouldDisplayInAppNotification(content: notification.request.content) else {
            return []
        }
        
        return [.badge, .sound, .list, .banner]
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        switch response.actionIdentifier {
        case NotificationConstants.Action.inlineReply:
            guard let response = response as? UNTextInputNotificationResponse else {
                return
            }
            await delegate?.handleInlineReply(self,
                                              content: response.notification.request.content,
                                              replyText: response.userText)
        // AGENT-PLATFORM: approval action taps land here, in the
        // main app's UNUserNotificationCenterDelegate. The handler
        // runs in the main process even when the app was suspended
        // or not running (iOS background-launches us). See
        // LEARNING.md L154-4 for why we don't need NSE for this.
        case NotificationConstants.Action.approvalApprove:
            await delegate?.handleApprovalAction(self,
                                                 content: response.notification.request.content,
                                                 decision: .approve)
        case NotificationConstants.Action.approvalReject:
            await delegate?.handleApprovalAction(self,
                                                 content: response.notification.request.content,
                                                 decision: .reject)
        case UNNotificationDefaultActionIdentifier:
            await delegate?.notificationTapped(content: response.notification.request.content)
        default:
            break
        }
    }
}

extension UNUserNotificationCenter: UserNotificationCenterProtocol { }
