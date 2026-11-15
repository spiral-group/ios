//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import MatrixRustSDK
import SwiftUI
import UserNotifications

/// Handles one account's notifications: its pusher, whether they're on, its unread count and which of its
/// delivered notifications to remove. The `NotificationManager` does the removing, through this service's actions.
final class NotificationService: NotificationServiceProtocol {
    private let clientProxy: ClientProxyProtocol
    private let userSettings: UserSettings
    // AGENT-PLATFORM (Brief 0043, ADR-0057): the Spiral push registry.
    private let agentPlatformService: AgentPlatformServiceProtocol?
    
    /// The APNs token, unknown until the app registers for remote notifications.
    private var deviceToken: Data?
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject = PassthroughSubject<NotificationServiceAction, Never>()
    var actionsPublisher: AnyPublisher<NotificationServiceAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    private let badgeCountSubject: CurrentValueSubject<Int, Never>
    var badgeCountPublisher: CurrentValuePublisher<Int, Never> {
        badgeCountSubject.asCurrentValuePublisher()
    }
    
    var userID: String {
        clientProxy.userID
    }
    
    var isEnabled: Bool {
        userSettings.account.enableNotifications
    }
    
    init(clientProxy: ClientProxyProtocol, userSettings: UserSettings, agentPlatformService: AgentPlatformServiceProtocol? = nil) {
        self.clientProxy = clientProxy
        self.userSettings = userSettings
        self.agentPlatformService = agentPlatformService
        // AGENT-PLATFORM: the badge counts the room list's own truth, see `attentionCount(in:)`.
        badgeCountSubject = .init(Self.attentionCount(in: clientProxy.staticRoomSummaryProvider.roomListPublisher.value,
                                                      accountSettings: userSettings.account))
        
        setupSubscriptions()
    }
    
    func register(deviceToken: Data) async {
        self.deviceToken = deviceToken
        // A failure is retried on the next launch, which registers the token again.
        await updatePusher(isEnabled: isEnabled)
    }
    
    func requestAuthorization() {
        actionsSubject.send(.requestAuthorization)
    }
    
    func removeDeliveredMessageNotifications(for roomID: String) {
        actionsSubject.send(.removeDeliveredNotifications { $0.request.content.roomID == roomID })
    }
    
    func removeDeliveredNotificationsForFullyReadRooms(_ rooms: [RoomSummary]) {
        let roomsToLastMessageDates = rooms
            .filter { $0.hasUnreadMessages == false }
            .reduce(into: [:]) { partialResult, roomSummary in
                partialResult[roomSummary.id] = roomSummary.lastMessageDate
            }
        guard !roomsToLastMessageDates.isEmpty else { return }
        
        actionsSubject.send(.removeDeliveredNotifications { notification in
            guard let roomID = notification.request.content.roomID,
                  let lastMessageDate = roomsToLastMessageDates[roomID] else {
                return false
            }
            
            // The delivery date is later than the event's so only use it for notifications without an event date.
            let notificationDate = notification.request.content.eventDate ?? notification.date
            // Truncated to seconds to match `RoomSummary.lastMessageDate`.
            return notificationDate.timeIntervalSince1970.rounded(.down) <= lastMessageDate.timeIntervalSince1970
        })
    }
    
    func tearDown() async {
        await updatePusher(isEnabled: false)
        actionsSubject.send(.removeDeliveredNotifications { _ in true })
    }
    
    // MARK: - Private
    
    private func setupSubscriptions() {
        let roomListPublisher = clientProxy.staticRoomSummaryProvider.roomListPublisher
        
        Task { [weak self] in
            for await roomSummaries in roomListPublisher.values {
                guard let self else { return }
                
                // Sent even when unchanged as the extension may have moved the app badge since.
                // AGENT-PLATFORM: from the room list, not `totalUnreadNotifications` (see `attentionCount(in:)`).
                badgeCountSubject.send(Self.attentionCount(in: roomSummaries, accountSettings: userSettings.account))
                removeDeliveredNotificationsForFullyReadRooms(roomSummaries)
            }
        }
        .store(in: &cancellables)
        
        // AGENT-PLATFORM: opening an invite marks it seen without the room list emitting, so the count is redone.
        userSettings.account.seenInvitesPublisher
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                badgeCountSubject.send(Self.attentionCount(in: clientProxy.staticRoomSummaryProvider.roomListPublisher.value,
                                                           accountSettings: userSettings.account))
            }
            .store(in: &cancellables)
        
        // The settings screen turns notifications on and off through `AccountSettings.enableNotifications`.
        userSettings.account.enableNotificationsPublisher
            .dropFirst()
            .sink { [weak self] isEnabled in
                self?.enableNotificationsChanged(to: isEnabled)
            }
            .store(in: &cancellables)
    }
    
    private func enableNotificationsChanged(to isEnabled: Bool) {
        MXLog.info("Notifications turned \(isEnabled ? "on" : "off") for \(userID)")
        // The extension drops pushes for an account turned off, so a pusher that fails to update is fixed on the next launch.
        Task { await updatePusher(isEnabled: isEnabled) }
        
        if isEnabled {
            requestAuthorization()
        }
    }
    
    /// Sets the pusher when enabled and deletes it otherwise. Nothing to update until the device token is known.
    private func updatePusher(isEnabled: Bool) async {
        guard let deviceToken else { return }
        
        let identifiers = PusherIdentifiers(pushkey: deviceToken.base64EncodedString(), appId: userSettings.app.pusherAppID)
        do {
            if isEnabled {
                try await clientProxy.setPusher(with: pusherConfiguration(for: identifiers))
                MXLog.info("Set pusher succeeded")
                await registerSpiralPushDevice(pushkey: identifiers.pushkey)
            } else {
                try await clientProxy.deletePusher(with: identifiers)
                MXLog.info("Delete pusher succeeded")
            }
        } catch {
            MXLog.error("Updating the pusher failed: \(error)")
        }
    }
    
    /// AGENT-PLATFORM (Brief 0043, ADR-0057): mirror the device into the Spiral
    /// push registry so the orchestrator can notify this device directly (no
    /// Matrix carrier event). Best-effort — the hub/SSE reconciles when a push
    /// is lost.
    private func registerSpiralPushDevice(pushkey: String) async {
        guard let agentPlatformService else { return }
        switch await agentPlatformService.registerPushDevice(pushkey: pushkey, appID: userSettings.app.pusherAppID) {
        case .success:
            MXLog.info("Spiral push device registered")
        case .failure(let error):
            MXLog.error("Spiral push device registration failed: \(error)")
        }
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
    /// the badge reads the same counters as the dots, though it counts only
    /// rooms that matter (`countsTowardsBadge`, decision 256). (Upstream 26.10
    /// publishes the SDK's `totalUnreadNotifications`, the server's number.)
    private static func attentionCount(in rooms: [RoomSummary], accountSettings: AccountSettings) -> Int {
        let seenInvites = accountSettings.seenInvites
        return rooms.filter { $0.countsTowardsBadge(seenInvites: seenInvites) }.count // AGENT-PLATFORM: badge (decision 256)
    }
    
    private func pusherConfiguration(for identifiers: PusherIdentifiers) throws -> PusherConfiguration {
        let defaultPayload = APNSPayload(aps: APSInfo(mutableContent: 1,
                                                      alert: APSAlert(locKey: "Notification",
                                                                      locArgs: [])),
                                         pusherNotificationClientIdentifier: clientProxy.pusherNotificationClientIdentifier)
        
        return try PusherConfiguration(identifiers: identifiers,
                                       kind: .http(data: .init(url: userSettings.app.pushGatewayNotifyEndpoint.absoluteString,
                                                               format: .eventIdOnly,
                                                               defaultPayload: defaultPayload.toJsonString())),
                                       appDisplayName: "\(InfoPlistReader.main.bundleDisplayName) (iOS)",
                                       deviceDisplayName: UIDevice.current.name,
                                       profileTag: pusherProfileTag(),
                                       lang: Bundle.app.preferredLocalizations.first ?? "en",
                                       // Otherwise accounts on the same homeserver delete each other's pusher.
                                       append: userSettings.app.multiAccountEnabled)
    }
    
    private func pusherProfileTag() -> String {
        if let currentTag = userSettings.app.pusherProfileTag {
            return currentTag
        }
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        let newTag = (0..<16).map { _ in
            let offset = Int.random(in: 0..<chars.count)
            return String(chars[chars.index(chars.startIndex, offsetBy: offset)])
        }.joined()
        
        userSettings.app.pusherProfileTag = newTag
        return newTag
    }
}
