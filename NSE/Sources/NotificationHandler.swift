//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import CallKit
import MatrixRustSDK
import Synchronization
import UserNotifications

nonisolated class NotificationHandler {
    private let userSession: NSEUserSession
    private let contentHandler: (UNNotificationContent) -> Void
    private var notificationContent: UNMutableNotificationContent
    private let tag: String
    
    private let notificationContentBuilder: NotificationContentBuilder
    
    private var userSettings: UserSettings {
        userSession.userSettings
    }
    
    init(userSession: NSEUserSession,
         contentHandler: @escaping (UNNotificationContent) -> Void,
         notificationContent: UNMutableNotificationContent,
         tag: String) {
        self.userSession = userSession
        self.contentHandler = contentHandler
        self.notificationContent = notificationContent
        self.tag = tag
        
        let eventStringBuilder = RoomMessageEventStringBuilder(attributedStringBuilder: AttributedStringBuilder(mentionBuilder: PlainMentionBuilder()),
                                                               style: .plain)
        
        notificationContentBuilder = NotificationContentBuilder(messageEventStringBuilder: eventStringBuilder,
                                                                userSession: userSession)
    }
    
    func processEvent(_ eventID: String, roomID: String) async {
        MXLog.info("\(tag) Processing event: \(eventID) in room: \(roomID)")
        
        // The pusher of an account with its notifications off can outlive a failed deletion.
        guard userSettings.account.enableNotifications else {
            MXLog.error("\(tag) Received a push for an account with notifications off, discarding.")
            discardNotification(updatingBadge: false) // AGENT-PLATFORM (§ 5.83): the client filtered it.
            return
        }

        // AGENT-PLATFORM (Brief 0066, § 5.83): the badge is NOT the server's
        // `unread_count`. That number is how many rooms the server holds an
        // unanswered notification for — and in an encrypted room it counts
        // every hidden action, in buckets no receipt clears (a thread's,
        // a room's whose last notifying event is hidden). One push arrived
        // with `unread_count = 4` while the notification centre held one
        // notification and the room list nothing unread. The badge is the
        // rooms this phone has a notification for, this one included; the
        // app recomputes it from the room list on every open
        // (`NotificationService.attentionCount`).
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        notificationContent.badge = Self.badge(roomsWithDeliveredNotifications: Set(delivered.compactMap(\.request.content.roomID)),
                                               roomID: roomID) as NSNumber
        MXLog.info("\(tag) New badge value: \(notificationContent.badge?.stringValue ?? "nil")")
        
        guard let notificationItemProxy = await userSession.notificationItemProxy(roomID: roomID, eventID: eventID) else {
            // AGENT-PLATFORM (§ 5.83): nothing could be shown — the fetch failed
            // (network, token). Upstream showed the app's name over the word
            // «Notification»; that tells nobody anything.
            MXLog.error("\(tag) Failed retrieving notification item, discarding")
            discardNotification(updatingBadge: false)
            return
        }
        
        if Self.hasNothingToShow(notificationItemProxy) {
            // AGENT-PLATFORM (§ 5.83): the event could not be decrypted (no room
            // key yet). Most often one of our hidden actions after a reinstall;
            // a real message that cannot be decrypted is as unreadable in the
            // app as here. Upstream showed «Notification».
            MXLog.warning("\(tag) Undecryptable event, discarding")
            discardNotification(updatingBadge: false)
            return
        }
        
        switch await preprocessNotification(notificationItemProxy) {
        case .processedShouldDiscard, .unsupportedShouldDiscard:
            discardNotification(updatingBadge: false)
        case .shouldDisplay:
            if userSettings.app.hideQuietNotificationAlerts, !notificationItemProxy.isNoisy {
                discardNotification()
                return
            }
            
            await notificationContentBuilder.process(notificationContent: &notificationContent,
                                                     notificationItem: notificationItemProxy,
                                                     mediaProvider: userSession.mediaProvider)
            
            deliverNotification()
        case .shouldDisplayMissedCall:
            await notificationContentBuilder.process(notificationContent: &notificationContent,
                                                     notificationItem: notificationItemProxy,
                                                     mediaProvider: userSession.mediaProvider)
            notificationContent.body = UntranslatedL10n.notificationMissedCall
            deliverNotification()
        }
    }
    
    /// The badge once this notification is delivered: the rooms that have one
    /// on this phone, this room counted whether or not it already had one.
    static func badge(roomsWithDeliveredNotifications rooms: Set<String>, roomID: String) -> Int {
        rooms.union([roomID]).count
    }
    
    /// An event with no words to put in a notification: one the SDK could
    /// not decrypt. Everything else — a message, a custom event the builder
    /// knows, an invite (no timeline event at all) — has something to say.
    static func hasNothingToShow(_ item: NotificationItemProxyProtocol) -> Bool {
        guard case let .timeline(event) = item.event else { return false }
        if case .messageLike(.roomEncrypted) = try? event.content() { return true }
        return false
    }
    
    /// AGENT-PLATFORM (decision 371): a call's summary is the one custom message people get a push for, as it says what
    /// the agent said. It reads as its `body`.
    static func isPushedAsAMessage(_ messageType: MessageType) -> Bool {
        guard case .other(let msgtype, _, let data) = messageType else { return false }
        return SpiralCallSummary(msgtype: msgtype, data: data) != nil
    }
    
    func handleTimeExpiration() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content
        MXLog.info("\(tag) Extension time will expire")
        deliverNotification()
    }
    
    // MARK: - Private
    
    private func deliverNotification() {
        // AGENT-PLATFORM (§ 5.83): the badge was computed in `processEvent` from this phone's
        // notifications; upstream's per-delivery increment of `lastKnownBadgeCount` is not used.
        MXLog.info("\(tag) Delivering notification")
        contentHandler(notificationContent)
    }
    
    /// Drop the alert.
    ///
    /// `updatingBadge` separates two very different reasons for discarding.
    /// When the USER asked for quiet alerts the badge is the whole point of
    /// the notification, so it must still be carried. When the CLIENT filtered
    /// the event out — a type it never renders, a redaction, a call handed to
    /// CallKit — importing the server's count is precisely the mismatch the
    /// user reported: in an encrypted room the homeserver can only match the
    /// blanket "encrypted event" rule, so it counted an event we are in the
    /// middle of deciding not to show. Leaving the badge alone lets the app's
    /// own recompute (`NotificationService.attentionCount`) own the number.
    private func discardNotification(updatingBadge: Bool = true) {
        MXLog.info("\(tag) Discarding notification")
        
        let content = UNMutableNotificationContent()
        if updatingBadge {
            // AGENT-PLATFORM (§ 5.83): the badge computed above, from this
            // phone's notifications — never the server's `unread_count`.
            content.badge = notificationContent.badge
            MXLog.info("\(tag) New badge value: \(content.badge?.stringValue ?? "nil")")
        }
        
        contentHandler(content)
    }
    
    private func preprocessNotification(_ itemProxy: NotificationItemProxyProtocol) async -> NotificationProcessingResult {
        guard case let .timeline(event) = itemProxy.event else {
            return .shouldDisplay
        }
        
        switch try? event.content() {
        case .messageLike(let messageContent):
            switch messageContent {
            case .poll,
                 .sticker:
                return .shouldDisplay
            case .roomEncrypted:
                // AGENT-PLATFORM (§ 5.83): caught earlier (`hasNothingToShow`);
                // kept here so the switch stays exhaustive and the answer is one.
                return .unsupportedShouldDiscard
            case .roomMessage(let messageType, _):
                switch messageType {
                // AGENT-PLATFORM (Brief 0066): an Interactive Post announces
                // itself like any other message. It is listed beside the rest
                // rather than special-cased earlier, which is the whole point
                // of it being a message type: no push rule to install, and no
                // branch ahead of this switch to keep in step with it.
                case .emote, .image, .audio, .video, .file, .notice, .text, .location, .gallery, .interactivePost, .interactiveDraft:
                    return .shouldDisplay
                case .other:
                    return Self.isPushedAsAMessage(messageType) ? .shouldDisplay : .unsupportedShouldDiscard
                }
            case .roomRedaction(let redactedEventID, _):
                guard let redactedEventID else {
                    MXLog.error("Unable to handle redact notification due to missing event ID")
                    return .processedShouldDiscard
                }
                
                let deliveredNotifications = await UNUserNotificationCenter.current().deliveredNotifications()
                
                if let targetNotification = deliveredNotifications.first(where: { $0.request.content.eventID == redactedEventID }) {
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [targetNotification.request.identifier])
                    userSettings.app.lastKnownBadgeCount = max(0, userSettings.app.lastKnownBadgeCount - 1)
                }
                
                return .processedShouldDiscard
            case .rtcNotification(let notificationType, let expirationTimestamp, let callIntent):
                return await handleCallNotification(notificationType: notificationType,
                                                    rtcNotifyEventID: event.eventId(),
                                                    timestamp: event.timestamp(),
                                                    expirationTimestamp: expirationTimestamp,
                                                    ringingRoom: .init(roomID: itemProxy.roomID,
                                                                       displayName: itemProxy.roomDisplayName,
                                                                       isDM: itemProxy.isDM),
                                                    callerID: itemProxy.senderID,
                                                    callerDisplayName: itemProxy.senderDisplayName,
                                                    callerAvatarMediaSource: itemProxy.isDM ? itemProxy.senderAvatarMediaSource : itemProxy.roomAvatarMediaSource,
                                                    callIntent: callIntent)
            case .callAnswer,
                 .callInvite,
                 .callHangup,
                 .callCandidates,
                 .keyVerificationReady,
                 .keyVerificationStart,
                 .keyVerificationCancel,
                 .keyVerificationAccept,
                 .keyVerificationKey,
                 .keyVerificationMac,
                 .keyVerificationDone,
                 .reactionContent,
                 .beacon:
                return .unsupportedShouldDiscard
            }
        case .state(let stateContent):
            switch stateContent {
            case .beaconInfo:
                return .shouldDisplay
            default:
                return .unsupportedShouldDiscard
            }
        case .none:
            // AGENT-PLATFORM (§ 5.73): a game's move that names this user —
            // the one custom event this extension shows.
            return itemProxy.spiralAction == nil ? .unsupportedShouldDiscard : .shouldDisplay
        }
    }
    
    /// The ringing room as the VoIP payload needs it — one value instead of
    /// three loose parameters (SwiftLint caps the count, and these travel
    /// together anyway).
    private struct RingingRoom {
        let roomID: String
        let displayName: String
        let isDM: Bool
    }
    
    /// Handle incoming call notifications.
    /// - Returns: A boolean indicating whether the notification was handled and should now be discarded.
    private func handleCallNotification(notificationType: RtcNotificationType,
                                        rtcNotifyEventID: String,
                                        timestamp: Timestamp,
                                        expirationTimestamp: Timestamp,
                                        ringingRoom: RingingRoom,
                                        callerID: String,
                                        callerDisplayName: String?,
                                        callerAvatarMediaSource: MediaSourceProxy?,
                                        callIntent: RtcCallIntent?) async -> NotificationProcessingResult {
        let roomID = ringingRoom.roomID
        let roomDisplayName = ringingRoom.displayName
        // Handle incoming VoIP calls, show the native OS call screen
        // https://developer.apple.com/documentation/callkit/sending-end-to-end-encrypted-voip-calls
        //
        // The way this works is the following:
        // - the NSE receives the notification and decrypts it
        // - checks if it's still time relevant (max 10 seconds old) and whether it should ring
        // - otherwise it goes on to show it as a normal notification
        // - if it should ring then it discards the notification but invokes `reportNewIncomingVoIPPushPayload`
        // so that the main app can handle it
        // - the main app picks this up in `PKPushRegistry.didReceiveIncomingPushWith` and
        // `CXProvider.reportNewIncomingCall` to show the system UI and handle actions on it.
        // N.B. this flow works properly only when background processing capabilities are enabled
        guard notificationType == .ring else {
            MXLog.info("Non-ringing call notification, handling as push notification")
            return .shouldDisplay
        }
        
        // Check to see if a call is still ongoing
        if let room = userSession.roomForIdentifier(roomID) { // Try to get call details from the room info
            if !room.hasActiveRoomCall() { // If I don't have an active call wait a bit and make sure
                // Local `Mutex` holder for the SDK subscription token — keeps it alive across the
                // await without needing `[weak self]`, which would force this class to be `Sendable`.
                let observationToken = Mutex<TaskHandle?>(nil)
                let expiringTask = ExpiringTaskRunner {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        observationToken.withLock { state in
                            state = room.subscribeToRoomInfoUpdates(listener: SDKListener { info in
                                if info.hasRoomCall {
                                    MXLog.info("Received room info update and the room has an active call now.")
                                    continuation.resume()
                                } else {
                                    MXLog.info("Received a room info update but the room still doesn't have an ongoing call.")
                                }
                            })
                        }
                    }
                }
                
                try? await expiringTask.run(timeout: Duration.seconds(5)) // Wait 5 seconds or just use whatever is available
                // Release the SDK subscription explicitly once we no longer need updates.
                observationToken.withLock { $0 = nil }
                
                guard room.hasActiveRoomCall() else {
                    // The ring is already over: showing "Incoming call" for a
                    // call nobody can answer is a lie the user acts on. This
                    // is also the ONLY notification the callee gets when the
                    // app was dead while the caller gave up — CallKit's
                    // `.unanswered` writes to Recents, never the lock screen.
                    MXLog.info("The room no longer has an ongoing call, displaying it as a missed call")
                    return .shouldDisplayMissedCall
                }
            }
        } else {
            // Audit wave 8 — this branch used to gate the ring on
            // `abs(timestamp.timeIntervalSinceNow) < 15`, the same
            // server-time-versus-device-clock comparison W6-5-3 removed from
            // the payload and from the app. It survived one function above
            // the fix. A device more than 15 seconds out in EITHER direction
            // — no NTP after a cold boot, a hand-set clock, a bad carrier
            // time zone — downgraded every call on this path to a silent
            // banner, invisibly, forever.
            //
            // There is no server-derived replacement: measuring delivery
            // delay needs a local `now`, which is the thing being removed. So
            // the gate goes. What is left is stronger anyway — the ring
            // carries the server's own lifetime, the app caps it at 90 s, and
            // the room-info observer and decline listener retire it the
            // moment the call is actually over. Ringing a little late is
            // recoverable; never ringing is not.
            MXLog.info("No room to corroborate the call with; ringing on the notification's own lifetime")
        }
        
        var callerAvatarData: Data?
        if let callerAvatarMediaSource,
           case let .success(data) = await userSession.mediaProvider.loadThumbnailForSource(source: callerAvatarMediaSource,
                                                                                            size: .init(width: 100, height: 100)) {
            callerAvatarData = data
        }

        // Audit W6-5-3 — a duration derived from two SERVER timestamps, so
        // the device's own clock never enters the arithmetic. Sending the
        // absolute expiry instead made the main app compare a server
        // deadline against its local wall clock, and a device running ahead
        // of the homeserver reported every ring as already missed.
        //
        // Transit time is deliberately not subtracted: doing so would need
        // a local `now`, which is the thing we are getting rid of. The cost
        // is a ring that may last a second or two past the server's intent,
        // against a 90 s cap, which is nothing next to losing the ring
        // entirely.
        let remainingRingSeconds = max(0,
                                       (Int(expirationTimestamp) - Int(timestamp)) / 1000)
        var payload = [CallKitNotificationKey.isDM.rawValue: ringingRoom.isDM,
                       CallKitNotificationKey.roomID.rawValue: roomID,
                       CallKitNotificationKey.roomDisplayName.rawValue: roomDisplayName,
                       CallKitNotificationKey.callerID.rawValue: callerID,
                       CallKitNotificationKey.callerDisplayName.rawValue: callerDisplayName ?? roomDisplayName,
                       CallKitNotificationKey.remainingRingSeconds.rawValue: remainingRingSeconds,
                       CallKitNotificationKey.rtcNotifyEventID.rawValue: rtcNotifyEventID,
                       CallKitNotificationKey.isVoiceCall.rawValue: callIntent == RtcCallIntent.audio] as [String: Any]
        payload[CallKitNotificationKey.callerAvatarData.rawValue] = callerAvatarData
        
        do {
            try await CXProvider.reportNewIncomingVoIPPushPayload(payload)
            MXLog.info("Call notification delegated to CallKit")
        } catch {
            MXLog.error("Failed reporting voip call with error: \(error). Handling as push notification")
            return .shouldDisplay
        }
        
        return .processedShouldDiscard
    }
    
    private enum NotificationProcessingResult {
        case shouldDisplay
        /// A ring that is already over — display it, but as the missed call
        /// it is, not as the incoming call it no longer is.
        case shouldDisplayMissedCall
        case processedShouldDiscard
        case unsupportedShouldDiscard
    }
}
