//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0066, § 5.83): what the notification extension
// decides before it shows anything — the badge, and whether there is
// anything to show.
//

@testable import ElementX
import MatrixRustSDK
import MatrixRustSDKMocks
import Testing

struct NotificationHandlerTests {
    /// The badge is the rooms this phone has a notification for, this one
    /// included — never the server's `unread_count`, which counted rooms
    /// whose only «unread» was a hidden action no receipt had reached.
    @Test
    func theBadgeCountsRoomsWithANotificationOnThisPhone() {
        #expect(NotificationHandler.badge(roomsWithDeliveredNotifications: [], roomID: "!a") == 1, "the first notification is one")
        #expect(NotificationHandler.badge(roomsWithDeliveredNotifications: ["!a"], roomID: "!a") == 1, "a second one in the same room is still one room")
        #expect(NotificationHandler.badge(roomsWithDeliveredNotifications: ["!a", "!b"], roomID: "!c") == 3)
        #expect(NotificationHandler.badge(roomsWithDeliveredNotifications: ["!a", "!b"], roomID: "!b") == 2)
    }

    /// An event the SDK could not decrypt has no words for a notification;
    /// upstream showed the app's name over «Notification».
    @Test
    func anUndecryptableEventHasNothingToShow() {
        let encrypted = TimelineEventSDKMock()
        encrypted.contentReturnValue = .messageLike(content: .roomEncrypted)
        #expect(NotificationHandler.hasNothingToShow(proxy(.timeline(event: encrypted))))

        let message = TimelineEventSDKMock()
        message.contentReturnValue = .messageLike(content: .roomMessage(messageType: .text(content: .init(body: "hi", formatted: nil)), inReplyToEventId: nil))
        #expect(!NotificationHandler.hasNothingToShow(proxy(.timeline(event: message))))

        // A custom event the SDK cannot type — a game's move — is the
        // builder's to read (§ 5.73), not nothing.
        let custom = TimelineEventSDKMock()
        custom.contentThrowableError = NotificationTestError.customEvent
        #expect(!NotificationHandler.hasNothingToShow(proxy(.timeline(event: custom))))

        #expect(!NotificationHandler.hasNothingToShow(proxy(.invite(sender: "@alice:spiral.md"))), "an invite has no timeline event and is shown")
    }

    private enum NotificationTestError: Error { case customEvent }

    private func proxy(_ event: NotificationEvent) -> NotificationItemProxyMock {
        NotificationItemProxyMock(.init(event: event,
                                        roomID: "!room:spiral.md",
                                        receiverID: "@bob:spiral.md",
                                        senderDisplayName: "Alice",
                                        roomDisplayName: "Alice",
                                        roomJoinedMembers: 2,
                                        isRoomDirect: true,
                                        isRoomPrivate: true,
                                        isNoisy: true))
    }
}
