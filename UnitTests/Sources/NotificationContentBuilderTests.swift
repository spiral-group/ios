//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Dynamic
import MatrixRustSDK
import MatrixRustSDKMocks
@testable import Spiral
import Testing
import UserNotifications

// `@MainActor` because this target defaults to that isolation and
// `UNNotificationSoundName`'s unannotated initialiser is inferred to need it —
// the NSE builds the same value freely because that target is nonisolated.
// Xcode 27 began enforcing this.
@MainActor
struct NotificationContentBuilderTests {
    var notificationContentBuilder: NotificationContentBuilder
    var mediaProvider: MediaProviderMock
    var notificationContent: UNMutableNotificationContent
    
    init() async {
        notificationContent = .init()
        let stringBuilder = RoomMessageEventStringBuilder(attributedStringBuilder: AttributedStringBuilder(mentionBuilder: PlainMentionBuilder()),
                                                          style: .plain)
        mediaProvider = MediaProviderMock(.init())
        notificationContentBuilder = await NotificationContentBuilder(messageEventStringBuilder: stringBuilder,
                                                                      userSession: NSEUserSessionMock(.init()))
    }
    
    @Test
    mutating func dmMessageNotification() async {
        let notificationItem = NotificationItemProxyMock(.init(roomID: "!test:matrix.org",
                                                               receiverID: "@bob:matrix.org",
                                                               senderDisplayName: "Alice",
                                                               roomDisplayName: "Alice",
                                                               roomJoinedMembers: 2,
                                                               isRoomDirect: true,
                                                               isRoomPrivate: true,
                                                               isNoisy: true))
        // Via a local: an actor-isolated property cannot be passed `inout` to an
        // async call. Written back because `process` REPLACES the content when
        // it builds a communication notification, so a local alone would drop
        // exactly what these tests are checking.
        var content = notificationContent
        await notificationContentBuilder.process(notificationContent: &content,
                                                 notificationItem: notificationItem,
                                                 mediaProvider: mediaProvider)
        notificationContent = content
        
        let communicationContext = Dynamic(notificationContent, memberName: "communicationContext")
        // Checking if nil without using asObject always fails
        #expect(communicationContext.displayName.asObject == nil)
        #expect(communicationContext.sender.displayName == "Alice")
        #expect(notificationContent.body == "Hello world!")
        #expect(notificationContent.categoryIdentifier == NotificationConstants.Category.message)
        #expect(notificationContent.threadRootEventID == nil)
        #expect(notificationContent.sound != nil)
        // Remember we remove the @ due to an iOS bug
        #expect(notificationContent.threadIdentifier == "bob:matrix.org!test:matrix.org")
        #expect(notificationContent.attachments == [])
    }
    
    @Test
    mutating func dmMessageNotificationWithMention() async {
        let notificationItem = NotificationItemProxyMock(.init(roomID: "!test:matrix.org",
                                                               receiverID: "@bob:matrix.org",
                                                               senderDisplayName: "Alice",
                                                               roomDisplayName: "Alice",
                                                               roomJoinedMembers: 2,
                                                               isRoomDirect: true,
                                                               isRoomPrivate: true,
                                                               isNoisy: true,
                                                               hasMention: true))
        
        // Via a local: an actor-isolated property cannot be passed `inout` to an
        // async call. Written back because `process` REPLACES the content when
        // it builds a communication notification, so a local alone would drop
        // exactly what these tests are checking.
        var content = notificationContent
        await notificationContentBuilder.process(notificationContent: &content,
                                                 notificationItem: notificationItem,
                                                 mediaProvider: mediaProvider)
        notificationContent = content
        
        let communicationContext = Dynamic(notificationContent, memberName: "communicationContext")
        // Checking if nil without using asObject always fails
        #expect(communicationContext.displayName.asObject == nil)
        #expect(communicationContext.sender.displayName == L10n.notificationSenderMentionReply("Alice"))
        #expect(notificationContent.body == "Hello world!")
        #expect(notificationContent.categoryIdentifier == NotificationConstants.Category.message)
        #expect(notificationContent.threadRootEventID == nil)
        #expect(notificationContent.sound != nil)
        // Remember we remove the @ due to an iOS bug
        #expect(notificationContent.threadIdentifier == "bob:matrix.org!test:matrix.org")
        #expect(notificationContent.attachments == [])
        // AGENT-PLATFORM (§ 5.82): a mention in a message opens the room as before.
        #expect(notificationContent.spiralPostEventID == nil)
    }
    
    @Test
    mutating func dmMessageNotificationWithThread() async {
        let notificationItem = NotificationItemProxyMock(.init(roomID: "!test:matrix.org",
                                                               receiverID: "@bob:matrix.org",
                                                               senderDisplayName: "Alice",
                                                               roomDisplayName: "Alice",
                                                               roomJoinedMembers: 2,
                                                               isRoomDirect: true,
                                                               isRoomPrivate: true,
                                                               isNoisy: true,
                                                               hasMention: false,
                                                               threadRootEventID: "thread"))
        
        // Via a local: an actor-isolated property cannot be passed `inout` to an
        // async call. Written back because `process` REPLACES the content when
        // it builds a communication notification, so a local alone would drop
        // exactly what these tests are checking.
        var content = notificationContent
        await notificationContentBuilder.process(notificationContent: &content,
                                                 notificationItem: notificationItem,
                                                 mediaProvider: mediaProvider)
        notificationContent = content
        
        let communicationContext = Dynamic(notificationContent, memberName: "communicationContext")
        #expect(communicationContext.displayName == L10n.commonThread)
        #expect(communicationContext.sender.displayName == "Alice")
        #expect(notificationContent.body == "Hello world!")
        #expect(notificationContent.categoryIdentifier == NotificationConstants.Category.message)
        #expect(notificationContent.threadRootEventID != nil)
        #expect(notificationContent.sound != nil)
        // Remember we remove the @ due to an iOS bug
        #expect(notificationContent.threadIdentifier == "bob:matrix.org!test:matrix.orgthread")
        #expect(notificationContent.attachments == [])
    }
    
    @Test
    mutating func dmMessageNotificationWithThreadAndMention() async {
        let notificationItem = NotificationItemProxyMock(.init(roomID: "!test:matrix.org",
                                                               receiverID: "@bob:matrix.org",
                                                               senderDisplayName: "Alice",
                                                               roomDisplayName: "Alice",
                                                               roomJoinedMembers: 2,
                                                               isRoomDirect: true,
                                                               isRoomPrivate: true,
                                                               isNoisy: true,
                                                               hasMention: true,
                                                               threadRootEventID: "thread"))
        
        // Via a local: an actor-isolated property cannot be passed `inout` to an
        // async call. Written back because `process` REPLACES the content when
        // it builds a communication notification, so a local alone would drop
        // exactly what these tests are checking.
        var content = notificationContent
        await notificationContentBuilder.process(notificationContent: &content,
                                                 notificationItem: notificationItem,
                                                 mediaProvider: mediaProvider)
        notificationContent = content
        
        let communicationContext = Dynamic(notificationContent, memberName: "communicationContext")
        #expect(communicationContext.displayName == L10n.commonThread)
        #expect(communicationContext.sender.displayName == L10n.notificationSenderMentionReply("Alice"))
        #expect(notificationContent.body == "Hello world!")
        #expect(notificationContent.categoryIdentifier == NotificationConstants.Category.message)
        #expect(notificationContent.threadRootEventID != nil)
        #expect(notificationContent.sound != nil)
        // Remember we remove the @ due to an iOS bug
        #expect(notificationContent.threadIdentifier == "bob:matrix.org!test:matrix.orgthread")
        #expect(notificationContent.attachments == [])
    }
    
    @Test
    mutating func roomMessageNotification() async {
        let notificationItem = NotificationItemProxyMock(.init(roomID: "!testroom:matrix.org",
                                                               receiverID: "@bob:matrix.org",
                                                               senderDisplayName: "Alice",
                                                               roomDisplayName: "General",
                                                               roomJoinedMembers: 5,
                                                               isRoomDirect: false,
                                                               isRoomPrivate: false,
                                                               isNoisy: false))
        
        // Via a local: an actor-isolated property cannot be passed `inout` to an
        // async call. Written back because `process` REPLACES the content when
        // it builds a communication notification, so a local alone would drop
        // exactly what these tests are checking.
        var content = notificationContent
        await notificationContentBuilder.process(notificationContent: &content,
                                                 notificationItem: notificationItem,
                                                 mediaProvider: mediaProvider)
        notificationContent = content
        let communicationContext = Dynamic(notificationContent, memberName: "communicationContext")
        
        #expect(communicationContext.displayName == "General")
        #expect(communicationContext.sender.displayName == "Alice")
        #expect(notificationContent.body == "Hello world!")
        #expect(notificationContent.categoryIdentifier == NotificationConstants.Category.message)
        #expect(notificationContent.threadRootEventID == nil)
        #expect(notificationContent.sound == nil)
        // Remember we remove the @ due to an iOS bug
        #expect(notificationContent.threadIdentifier == "bob:matrix.org!testroom:matrix.org")
        #expect(notificationContent.attachments == [])
    }
    
    @Test
    mutating func roomMessageNotificationWithMention() async {
        let notificationItem = NotificationItemProxyMock(.init(roomID: "!testroom:matrix.org",
                                                               receiverID: "@bob:matrix.org",
                                                               senderDisplayName: "Alice",
                                                               roomDisplayName: "General",
                                                               roomJoinedMembers: 5,
                                                               isRoomDirect: false,
                                                               isRoomPrivate: false,
                                                               isNoisy: true,
                                                               hasMention: true))
        
        // Via a local: an actor-isolated property cannot be passed `inout` to an
        // async call. Written back because `process` REPLACES the content when
        // it builds a communication notification, so a local alone would drop
        // exactly what these tests are checking.
        var content = notificationContent
        await notificationContentBuilder.process(notificationContent: &content,
                                                 notificationItem: notificationItem,
                                                 mediaProvider: mediaProvider)
        notificationContent = content
        
        let communicationContext = Dynamic(notificationContent, memberName: "communicationContext")
        #expect(communicationContext.displayName == "General")
        #expect(communicationContext.sender.displayName == L10n.notificationSenderMentionReply("Alice"))
        #expect(notificationContent.body == "Hello world!")
        #expect(notificationContent.categoryIdentifier == NotificationConstants.Category.message)
        #expect(notificationContent.threadRootEventID == nil)
        #expect(notificationContent.sound != nil)
        #expect(notificationContent.threadIdentifier == "bob:matrix.org!testroom:matrix.org")
        #expect(notificationContent.attachments == [])
    }
    
    @Test
    mutating func roomMessageNotificationWithThread() async {
        let notificationItem = NotificationItemProxyMock(.init(roomID: "!testroom:matrix.org",
                                                               receiverID: "@bob:matrix.org",
                                                               senderDisplayName: "Alice",
                                                               roomDisplayName: "General",
                                                               roomJoinedMembers: 5,
                                                               isRoomDirect: false,
                                                               isRoomPrivate: false,
                                                               isNoisy: false,
                                                               threadRootEventID: "thread123"))
        
        // Via a local: an actor-isolated property cannot be passed `inout` to an
        // async call. Written back because `process` REPLACES the content when
        // it builds a communication notification, so a local alone would drop
        // exactly what these tests are checking.
        var content = notificationContent
        await notificationContentBuilder.process(notificationContent: &content,
                                                 notificationItem: notificationItem,
                                                 mediaProvider: mediaProvider)
        notificationContent = content
        
        let communicationContext = Dynamic(notificationContent, memberName: "communicationContext")
        #expect(communicationContext.displayName == L10n.notificationThreadInRoom("General"))
        #expect(communicationContext.sender.displayName == "Alice")
        #expect(notificationContent.body == "Hello world!")
        #expect(notificationContent.categoryIdentifier == NotificationConstants.Category.message)
        #expect(notificationContent.threadRootEventID != nil)
        #expect(notificationContent.sound == nil)
        #expect(notificationContent.threadIdentifier == "bob:matrix.org!testroom:matrix.orgthread123")
        #expect(notificationContent.attachments == [])
    }
    
    @Test
    mutating func liveLocationStartNotification() async {
        let event = TimelineEventSDKMock()
        event.eventIdReturnValue = UUID().uuidString
        event.timestampReturnValue = 0
        event.contentReturnValue = .state(content: .beaconInfo)
        
        let notificationItem = NotificationItemProxyMock(.init(event: .timeline(event: event),
                                                               roomID: "!test:matrix.org",
                                                               receiverID: "@bob:matrix.org",
                                                               senderDisplayName: "Alice",
                                                               roomDisplayName: "Alice",
                                                               roomJoinedMembers: 2,
                                                               isRoomDirect: true,
                                                               isRoomPrivate: true,
                                                               isNoisy: true))
        
        // Via a local: an actor-isolated property cannot be passed `inout` to an
        // async call. Written back because `process` REPLACES the content when
        // it builds a communication notification, so a local alone would drop
        // exactly what these tests are checking.
        var content = notificationContent
        await notificationContentBuilder.process(notificationContent: &content,
                                                 notificationItem: notificationItem,
                                                 mediaProvider: mediaProvider)
        notificationContent = content
        
        let communicationContext = Dynamic(notificationContent, memberName: "communicationContext")
        #expect(communicationContext.sender.displayName == "Alice")
        #expect(notificationContent.body == L10n.notificationLiveLocationStartedBody)
        #expect(notificationContent.categoryIdentifier == NotificationConstants.Category.message)
        #expect(notificationContent.sound != nil)
    }
    
    /// AGENT-PLATFORM (§ 5.73): a game's move that mentions the reader — a
    /// custom event the SDK cannot type — is shown as a mention from the
    /// player who moved, in the room; and it names the post the move was made
    /// in, which a tap opens the room on (§ 5.82).
    @Test
    mutating func spiralActionMentionNotification() async throws {
        let event = TimelineEventSDKMock()
        event.eventIdReturnValue = UUID().uuidString
        event.timestampReturnValue = 0 // the 26.10 builder dates the notification from the event
        event.contentThrowableError = NotificationTestError.customEvent
        let raw = #"{"type":"com.spiral.app.action","content":{"m.relates_to":{"rel_type":"m.reference","event_id":"$post"},"m.mentions":{"user_ids":["@bob:matrix.org"]},"summary":{"line":"Alice placed X"}}}"#
        let action = try #require(SpiralActionNotification(rawEvent: raw, receiverID: "@bob:matrix.org"))
        let notificationItem = NotificationItemProxyMock(.init(event: .timeline(event: event),
                                                               roomID: "!testroom:matrix.org",
                                                               receiverID: "@bob:matrix.org",
                                                               senderDisplayName: "Alice",
                                                               roomDisplayName: "General",
                                                               roomJoinedMembers: 5,
                                                               isRoomDirect: false,
                                                               isRoomPrivate: false,
                                                               isNoisy: true,
                                                               hasMention: true,
                                                               spiralAction: action))

        var content = notificationContent
        await notificationContentBuilder.process(notificationContent: &content,
                                                 notificationItem: notificationItem,
                                                 mediaProvider: mediaProvider)
        notificationContent = content

        let communicationContext = Dynamic(notificationContent, memberName: "communicationContext")
        #expect(communicationContext.displayName == "General")
        #expect(communicationContext.sender.displayName == L10n.notificationSenderMentionReply("Alice"))
        #expect(notificationContent.body == action.body())
        #expect(notificationContent.categoryIdentifier == NotificationConstants.Category.message)
        #expect(notificationContent.sound != nil)
        #expect(notificationContent.spiralPostEventID == "$post")
        #expect(notificationContent.roomID == "!testroom:matrix.org")
    }

    private enum NotificationTestError: Error { case customEvent }

    @Test
    mutating func otherStateEventNotification() async {
        let event = TimelineEventSDKMock()
        event.eventIdReturnValue = UUID().uuidString
        event.timestampReturnValue = 0
        event.contentReturnValue = .state(content: .roomName)
        
        let notificationItem = NotificationItemProxyMock(.init(event: .timeline(event: event),
                                                               roomID: "!test:matrix.org",
                                                               receiverID: "@bob:matrix.org",
                                                               senderDisplayName: "Alice",
                                                               roomDisplayName: "Alice",
                                                               roomJoinedMembers: 2,
                                                               isRoomDirect: true,
                                                               isRoomPrivate: true,
                                                               isNoisy: true))
        
        // Via a local: an actor-isolated property cannot be passed `inout` to an
        // async call. Written back because `process` REPLACES the content when
        // it builds a communication notification, so a local alone would drop
        // exactly what these tests are checking.
        var content = notificationContent
        await notificationContentBuilder.process(notificationContent: &content,
                                                 notificationItem: notificationItem,
                                                 mediaProvider: mediaProvider)
        notificationContent = content
        
        #expect(notificationContent.body == L10n.notification)
    }
    
    @Test
    mutating func roomMessageNotificationWithThreadAndMention() async {
        let notificationItem = NotificationItemProxyMock(.init(roomID: "!testroom:matrix.org",
                                                               receiverID: "@bob:matrix.org",
                                                               senderDisplayName: "Alice",
                                                               roomDisplayName: "General",
                                                               roomJoinedMembers: 5,
                                                               isRoomDirect: false,
                                                               isRoomPrivate: false,
                                                               isNoisy: true,
                                                               hasMention: true,
                                                               threadRootEventID: "thread123"))
        // Via a local: an actor-isolated property cannot be passed `inout` to an
        // async call. Written back because `process` REPLACES the content when
        // it builds a communication notification, so a local alone would drop
        // exactly what these tests are checking.
        var content = notificationContent
        await notificationContentBuilder.process(notificationContent: &content,
                                                 notificationItem: notificationItem,
                                                 mediaProvider: mediaProvider)
        notificationContent = content
        let communicationContext = Dynamic(notificationContent, memberName: "communicationContext")
        #expect(communicationContext.displayName == L10n.notificationThreadInRoom("General"))
        #expect(communicationContext.sender.displayName == L10n.notificationSenderMentionReply("Alice"))
        #expect(notificationContent.body == "Hello world!")
        #expect(notificationContent.categoryIdentifier == NotificationConstants.Category.message)
        #expect(notificationContent.threadRootEventID != nil)
        #expect(notificationContent.sound != nil)
        #expect(notificationContent.threadIdentifier == "bob:matrix.org!testroom:matrix.orgthread123")
        #expect(notificationContent.attachments == [])
    }
}
