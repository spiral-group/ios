//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 357): a real chat on the room's background, a screen at a time, then the rows that sit
// straight on it, so the column can be read as a phone shows it.
//

import Compound
import MatrixRustSDK
import SwiftUI

struct SpiralConversation_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static var previews: some View {
        SpiralConversation.screens
    }
}

enum SpiralConversation {
    private typealias Room = RoomScreenTimeline_Previews
    
    private static let arrangingViewModels = Room.makeViewModels(name: "Weekend trip", items: arrangingItems)
    private static let picturesViewModels = Room.makeViewModels(name: "Weekend trip", items: picturesItems)
    private static let planningViewModels = Room.makeViewModels(name: "Weekend trip", items: planningItems)
    private static let afterwardsViewModels = Room.makeViewModels(name: "Weekend trip", items: afterwardsItems)
    private static let callsInADMViewModels = Room.makeViewModels(name: "Helena Ortiz", items: callsInADMItems)
    private static let callsInAGroupViewModels = Room.makeViewModels(name: "Weekend trip", items: callsInAGroupItems)
    private static let noticesViewModels = Room.makeViewModels(name: "Helena's Assistant", items: noticesItems)
    private static let workViewModels = Room.makeViewModels(name: "Helena's Assistant", items: workItems)
    private static let blockedViewModels = Room.makeViewModels(name: "Weekend trip",
                                                               items: blockedItems,
                                                               contentScannerService: ContentScannerServiceMock(.init(scanResult: false)))
    private static let rowsViewModels = Room.makeViewModels(name: "Weekend trip", items: rowsItems, typingMembers: ["Jacob"])
    private static let longRunViewModels = Room.makeViewModels(name: "Weekend trip", items: longRunItems)
    
    @ViewBuilder
    static var screens: some View {
        Room.room(arrangingViewModels)
            .previewDisplayName("1 Arranging")
        Room.room(picturesViewModels)
            .previewDisplayName("2 Pictures and voice")
        Room.room(planningViewModels)
            .previewDisplayName("3 Planning")
        Room.room(afterwardsViewModels)
            .previewDisplayName("4 Afterwards")
        Room.room(rowsViewModels)
            .snapshotPreferences(expect: rowsViewModels.timeline.context.$viewState.map { !$0.typingMembers.isEmpty })
            .previewDisplayName("5 Rows on the background")
        Room.room(arrangingViewModels, composer: ComposerToolbar_Previews.suggestionsViewModel)
            .previewDisplayName("6 The mention list")
        Room.room(callsInADMViewModels)
            .previewDisplayName("7 Calls in a DM")
        Room.room(callsInAGroupViewModels)
            .previewDisplayName("8 Calls in a group")
        Room.room(noticesViewModels)
            .previewDisplayName("9 An agent's notices")
        Room.room(workViewModels)
            .previewDisplayName("10 A draft being made")
        Room.room(blockedViewModels)
            .previewDisplayName("11 Blocked files")
        Room.room(longRunViewModels)
            .previewDisplayName("12 A long run")
    }
    
    // MARK: - The chat
    
    private static var arrangingItems: [RoomTimelineItemProtocol] {
        [
            SeparatorRoomTimelineItem(id: .virtual(uniqueID: .init("today")), timestamp: Room.time(minute: 2)),
            Room.text("map", "Who's bringing the map on Saturday?", from: Room.helena, minute: 2),
            Room.text("got", "I've got it", from: Room.me, minute: 4),
            Room.text("booking", "And the cabin booking came through", from: Room.me, minute: 4),
            Room.file("cabin-booking", caption: nil, from: Room.me, minute: 5),
            Room.text("parking", "Is parking included?", from: Room.jacob, minute: 7),
            Room.text("spaces", "Yes, two spaces by the gate", from: Room.me, minute: 8,
                      properties: .init(replyDetails: quote(Room.jacob, "Is parking included?"))),
            Room.text("perfect", "Perfect, thank you!", from: Room.helena, minute: 9,
                      properties: .init(replyDetails: quote(Room.me, "Yes, two spaces by the gate"))),
            Room.text("eight", "Leaving at eight, so we get there before the rain", from: Room.me, minute: 11,
                      properties: .init(reactions: reactions("👍"),
                                        orderedReadReceipts: [ReadReceipt(userID: Room.helena.id, formattedTimestamp: nil)]))
        ]
    }
    
    private static var picturesItems: [RoomTimelineItemProtocol] {
        [
            Room.image("cabin", caption: nil, from: Room.helena, minute: 14),
            Room.text("lake", "Is there a lake?", from: Room.jacob, minute: 15),
            Room.image("jetty", caption: "Two minutes' walk, kayaks included", from: Room.me, minute: 16,
                       properties: .init(reactions: reactions("❤️"))),
            Room.voice("directions", from: Room.helena, minute: 18),
            Room.voice("answer", from: Room.me, minute: 19),
            Room.text("heard", "And the key is under the blue pot", from: Room.me, minute: 19)
        ]
    }
    
    private static var planningItems: [RoomTimelineItemProtocol] {
        [
            Room.text("where", "Where do we meet?", from: Room.marcus, minute: 21),
            LocationRoomTimelineItem(id: Room.event("meet"),
                                     timestamp: Room.time(minute: 22),
                                     isOutgoing: true,
                                     isEditable: false,
                                     canBeRepliedTo: true,
                                     sender: Room.me,
                                     content: .init(body: "The jetty", geoURI: .init(latitude: 41.902782, longitude: 12.496366)),
                                     properties: .init(replyDetails: quote(Room.marcus, "Where do we meet?"))),
            PollRoomTimelineItem.mock(poll: .disclosed(createdByAccountOwner: true), isOutgoing: true, isEditable: false)
        ]
    }
    
    private static var afterwardsItems: [RoomTimelineItemProtocol] {
        [
            GalleryRoomTimelineItem(id: Room.event("trip"),
                                    timestamp: Room.time(minute: 30),
                                    isOutgoing: true,
                                    isEditable: false,
                                    canBeRepliedTo: true,
                                    sender: Room.me,
                                    content: .init(body: "Gallery (3 items)",
                                                   caption: "Everything from the trip",
                                                   items: [.mockImage(index: 0), .mockImage(index: 1), .mockImage(index: 2)])),
            Room.text("lovely", "These are lovely", from: Room.priya, minute: 32),
            RedactedRoomTimelineItem(id: Room.event("removed"),
                                     body: L10n.commonMessageRemoved,
                                     timestamp: Room.time(minute: 34),
                                     isOutgoing: true,
                                     isEditable: false,
                                     canBeRepliedTo: false,
                                     sender: Room.me),
            Room.file("receipts", caption: "The receipts, for splitting", from: Room.me, minute: 36),
            Room.text("next", "Same time next year?", from: Room.me, minute: 37,
                      properties: .init(threadSummary: .loaded(senderID: Room.jacob.id,
                                                               sender: Room.jacob,
                                                               latestEventContent: .message(.text(.init(body: "Count me in"))),
                                                               numberOfReplies: 2))),
            Room.text("sending", "Booking it now", from: Room.me, minute: 38, properties: .init(deliveryStatus: .sending)),
            Room.text("failed", "Here's the link", from: Room.me, minute: 38, properties: .init(deliveryStatus: .sendingFailed(.unknown(reason: nil))))
        ]
    }
    
    private static var rowsItems: [RoomTimelineItemProtocol] {
        [
            TimelineStartRoomTimelineItem(name: "Weekend trip"),
            SeparatorRoomTimelineItem(id: .virtual(uniqueID: .init("today")), timestamp: Room.time(minute: 2)),
            stateItem("joined", "Priya Shah joined the room"),
            CollapsibleTimelineItem(items: [stateItem("name", "Helena Ortiz changed the room name"), stateItem("topic", "Helena Ortiz changed the topic")]),
            CallNotificationRoomTimelineItem(id: Room.event("call"),
                                             timestamp: Room.time(minute: 3),
                                             sender: Room.helena,
                                             isDM: false,
                                             isVoiceCall: true,
                                             callState: .tombstoned(outcome: .groupCall(duration: 310, ownUserJoined: true))),
            Room.text("seen", "Everyone's sorted for Saturday", from: Room.me, minute: 4),
            ReadMarkerRoomTimelineItem(id: .virtual(uniqueID: .init("marker"))),
            Room.text("new", "One more thing about the cabin", from: Room.helena, minute: 6)
        ]
    }
    
    // AGENT-PLATFORM (Brief 0083, question 359): bubbles 2 pt apart, wider and narrower than their neighbours, for what lies between them.
    private static var longRunItems: [RoomTimelineItemProtocol] {
        [
            Room.text("morning", "Morning!", from: Room.helena, minute: 40),
            Room.text("address", "Did everyone get the cabin's address?", from: Room.helena, minute: 40),
            Room.text("bridge", "It's the last one before the lake, past the little bridge and the old boat shed", from: Room.helena, minute: 40),
            Room.text("door", "Blue door", from: Room.helena, minute: 40),
            Room.text("okay", "Ok", from: Room.helena, minute: 40),
            Room.text("gotIt", "Got it", from: Room.me, minute: 41),
            Room.text("food", "We'll bring the food", from: Room.me, minute: 41),
            Room.text("pan", "And the big pan", from: Room.me, minute: 41),
            Room.text("barbecue", "Is there a barbecue, or should we pack the little one from last summer?", from: Room.me, minute: 41),
            Room.text("yes", "Yes", from: Room.me, minute: 41)
        ]
    }
    
    // AGENT-PLATFORM (Brief 0083, question 359): every state a call has, on the side of whoever called.
    private static var callsInADMItems: [RoomTimelineItemProtocol] {
        [
            call("outgoing", from: Room.me, minute: 3, .tombstoned(outcome: .answered(duration: 45))),
            call("incoming", from: Room.helena, minute: 10, .tombstoned(outcome: .answered(duration: 120))),
            call("missed", from: Room.helena, minute: 17, .tombstoned(outcome: .missed)),
            call("cancelled", from: Room.me, minute: 25, .tombstoned(outcome: .cancelled)),
            call("video", from: Room.me, minute: 30, isVoiceCall: false, .tombstoned(outcome: .answered(duration: 300))),
            call("missedVideo", from: Room.helena, minute: 34, isVoiceCall: false, .tombstoned(outcome: .missed)),
            call("declined", from: Room.helena, minute: 36, .tombstoned(outcome: .declined(byMe: true))),
            call("theyDeclined", from: Room.me, minute: 37, .tombstoned(outcome: .declined(byMe: false))),
            call("live", from: Room.helena, minute: 38, .active(activeMembers: [Room.helena.id], isJoined: false, callStartTimestamp: Room.time(minute: 38))),
            Room.text("thanks", "Thanks, we talked", from: Room.me, minute: 39)
        ]
    }
    
    private static var callsInAGroupItems: [RoomTimelineItemProtocol] {
        let agent = TimelineItemSender(id: "@assistant-helena:spiral.md", displayName: "Helena's Assistant")
        let bridged = TimelineItemSender(id: "@whatsapp_447700900123:spiral.md")
        return [
            call("helena", from: Room.helena, minute: 2, isDM: false, .tombstoned(outcome: .groupCall(duration: 754, ownUserJoined: true))),
            call("unjoined", from: Room.marcus, minute: 21, isDM: false, isVoiceCall: false, .tombstoned(outcome: .groupCall(duration: 92, ownUserJoined: false))),
            call("agent", from: agent, minute: 24, isDM: false, .tombstoned(outcome: .groupCall(duration: 61, ownUserJoined: true))),
            call("bridged", from: bridged, minute: 26, isDM: false, .tombstoned(outcome: .unclassified)),
            call("ownLive", from: Room.me, minute: 30, isDM: false,
                 .active(activeMembers: [Room.helena.id, Room.marcus.id], isJoined: false, callStartTimestamp: Room.time(minute: 30))),
            call("live", from: Room.jacob, minute: 33, isDM: false, isVoiceCall: false,
                 .active(activeMembers: [Room.jacob.id, Room.helena.id, Room.marcus.id], isJoined: false, callStartTimestamp: Room.time(minute: 33)))
        ]
    }
    
    // AGENT-PLATFORM (Brief 0083, question 359): the chat's other cards, in the calls' family.
    private static let assistant = TimelineItemSender(id: "@assistant-helena:spiral.md", displayName: "Helena's Assistant")
    
    private static var noticesItems: [RoomTimelineItemProtocol] {
        [
            notice("welcome", #"{"kind":"welcome","owner_display_name":"Helena","agent_display_name":"Helena's Assistant","behavior":"personal_assistant"}"#, minute: 2),
            notice("failed", #"{"kind":"reply_failed"}"#, minute: 4),
            notice("passed", #"{"kind":"message_passed_to_owner","owner_display_name":"Helena"}"#, minute: 6),
            notice("referral", #"{"kind":"referral_joined","joined_user_id":"@marcus:spiral.md","joined_display_name":"Marcus Lee"}"#, minute: 8),
            notice("consent", #"{"kind":"ai_consent_needed","agent_display_name":"Helena's Assistant"}"#, minute: 10)
        ].compactMap(\.self)
    }
    
    private static var workItems: [RoomTimelineItemProtocol] {
        [
            generating("fresh", isFresh: true),
            generating("lost", isFresh: false),
            InteractiveDraftRoomTimelineItem(id: Room.event("draft"),
                                             body: "Where do we eat?",
                                             timestamp: Room.time(minute: 11),
                                             isOutgoing: false,
                                             isEditable: false,
                                             canBeRepliedTo: false,
                                             sender: assistant,
                                             // A digest that fails: a sound draft starts a web view, which a snapshot waits on.
                                             draft: SpiralAppDraft(InteractiveDraftContent(body: "Where do we eat?",
                                                                                           title: "Where do we eat?",
                                                                                           aspect: "16:9",
                                                                                           manifestJson: "{}",
                                                                                           source: "",
                                                                                           sha256: String(repeating: "0", count: 64),
                                                                                           version: 1,
                                                                                           generatedByAgentId: nil,
                                                                                           targetRoomId: nil)))
        ]
    }
    
    private static var blockedItems: [RoomTimelineItemProtocol] {
        [
            Room.file("theirs", caption: nil, from: Room.helena, minute: 14),
            Room.file("mine", caption: nil, from: Room.me, minute: 15),
            Room.image("theirPhoto", caption: nil, from: Room.jacob, minute: 16),
            Room.image("myPhoto", caption: "From the jetty", from: Room.me, minute: 17)
        ]
    }
    
    private static func notice(_ id: String, _ facts: String, minute: Int) -> SpiralNoticeRoomTimelineItem? {
        SpiralNotice(msgtype: SpiralNotice.msgtype, data: #"{"com.spiral.notice":\#(facts)}"#).map {
            SpiralNoticeRoomTimelineItem(id: Room.event(id), timestamp: Room.time(minute: minute), sender: assistant, notice: $0)
        }
    }
    
    /// A fresh card is dated on a day to come, so it's never stale.
    private static func generating(_ id: String, isFresh: Bool) -> InteractiveGeneratingRoomTimelineItem {
        InteractiveGeneratingRoomTimelineItem(id: Room.event(id),
                                              body: "Creating draft v1…",
                                              timestamp: isFresh ? DateComponents(calendar: .current, year: 2100, month: 1, day: 9, hour: 9, minute: 41).date ?? .mock : .mock,
                                              isOutgoing: false,
                                              isEditable: false,
                                              canBeRepliedTo: false,
                                              sender: assistant)
    }
    
    private static func call(_ id: String,
                             from sender: TimelineItemSender,
                             minute: Int,
                             isDM: Bool = true,
                             isVoiceCall: Bool = true,
                             _ state: CallNotificationRoomTimelineItem.CallState) -> CallNotificationRoomTimelineItem {
        CallNotificationRoomTimelineItem(id: Room.event(id),
                                         timestamp: Room.time(minute: minute),
                                         sender: sender,
                                         isDM: isDM,
                                         isVoiceCall: isVoiceCall,
                                         callState: state,
                                         isOutgoing: sender.id == Room.me.id)
    }
    
    private static func stateItem(_ id: String, _ body: String) -> StateRoomTimelineItem {
        StateRoomTimelineItem(id: Room.event(id),
                              body: body,
                              timestamp: Room.time(minute: 3),
                              isOutgoing: false,
                              isEditable: false,
                              canBeRepliedTo: false,
                              sender: Room.helena)
    }
    
    private static func quote(_ sender: TimelineItemSender, _ body: String) -> TimelineItemReplyDetails {
        .loaded(sender: sender, eventID: "$quoted", eventContent: .message(.text(.init(body: body))))
    }
    
    private static func reactions(_ key: String) -> [AggregatedReaction] {
        [AggregatedReaction(accountOwnerID: Room.me.id, key: key, senders: [ReactionSender(id: Room.helena.id, timestamp: .mock)])]
    }
}
