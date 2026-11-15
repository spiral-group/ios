//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083 phase 4, the room's timeline): rooms that show
// every piece the timeline draws, so the gates and the snapshots reach them: a
// group with many senders, a notice and read receipts, then reactions, a thread,
// media, an edit, an authenticity warning, a reply and a failed send, then the
// ticks' states, and the time on files, voice, polls, stickers and media. Each
// fits the snapshots' iPhone SE, since the timeline is anchored to the bottom.
//

import Combine
import SwiftUI

struct RoomScreenTimeline_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let groupViewModels = makeViewModels(name: "Design team", items: groupItems)
    static let groupNoticeViewModels = makeViewModels(name: "Design team", items: groupNoticeItems)
    // Question 392: typing takes the member count's line.
    static let groupTypingViewModels = makeViewModels(name: "Design team", items: groupItems, typingMembers: ["Mira Testova"])
    static let reactionsViewModels = makeViewModels(name: "Weekend trip", items: reactionsItems)
    static let repliesViewModels = makeViewModels(name: "Weekend trip", items: repliesItems)
    static let ticksViewModels = makeViewModels(name: "Helena Ortiz", items: ticksItems)
    static let filesViewModels = makeViewModels(name: "Weekend trip", items: filesItems)
    static let pollViewModels = makeViewModels(name: "Weekend trip", items: pollItems)
    static let mediaViewModels = makeViewModels(name: "Weekend trip", items: mediaItems)
    static let captionedViewModels = makeViewModels(name: "Weekend trip", items: captionedItems)
    static let uncaptionedReplyViewModels = makeViewModels(name: "Weekend trip", items: uncaptionedReplyItems)
    static let galleryAndMapViewModels = makeViewModels(name: "Weekend trip", items: galleryAndMapItems)
    static let composerViewModel = ComposerToolbarViewModel.mock()
    
    static var previews: some View {
        room(groupViewModels)
            .previewDisplayName("Group")
        room(groupNoticeViewModels)
            .previewDisplayName("Group with a notice")
        room(groupTypingViewModels)
            .previewDisplayName("Group, someone typing")
        room(reactionsViewModels)
            .previewDisplayName("Reactions and a thread")
        room(repliesViewModels)
            .previewDisplayName("Replies and a failed send")
        room(ticksViewModels)
            .previewDisplayName("Ticks")
        room(filesViewModels)
            .previewDisplayName("Files and voice")
        room(pollViewModels)
            .previewDisplayName("Poll")
        room(mediaViewModels)
            .previewDisplayName("Media and a sticker")
        room(captionedViewModels)
            .previewDisplayName("A reply on a captioned photo")
        room(uncaptionedReplyViewModels)
            .previewDisplayName("A reply on a photo")
        room(galleryAndMapViewModels)
            .previewDisplayName("A gallery and a map")
    }
    
    static func room(_ viewModels: RoomScreen_Previews.ViewModels, composer: ComposerToolbarViewModel? = nil) -> some View {
        ElementNavigationStack {
            RoomScreen(context: viewModels.room.context,
                       timelineContext: viewModels.timeline.context,
                       composerToolbar: ComposerToolbar(context: (composer ?? composerViewModel).context))
        }
    }
    
    static func makeViewModels(name: String,
                               items: [RoomTimelineItemProtocol],
                               typingMembers: [String] = [],
                               contentScannerService: ContentScannerServiceProtocol? = nil) -> RoomScreen_Previews.ViewModels {
        let roomProxy = JoinedRoomProxyMock(.init(id: "!\(name.lowercased().replacingOccurrences(of: " ", with: "-")):spiral.md",
                                                  name: name,
                                                  hasOngoingCall: false,
                                                  members: [.mockMe] + people.map { RoomMemberProxyMock(with: .init(userID: $0.id, displayName: $0.displayName, membership: .join)) }))
        roomProxy.typingMembersPublisher = CurrentValueSubject(typingMembers).asCurrentValuePublisher()
        let userSettings = UserSettings.mock()
        userSettings.app.threadsEnabled = true
        userSettings.account.sharePresence = !typingMembers.isEmpty // The timeline drops typing without it.
        let userSession = UserSessionMock(.init(userSettings: userSettings, contentScannerService: contentScannerService))
        
        let roomViewModel = RoomScreenViewModel.mock(roomProxyMock: roomProxy, userSession: userSession)
        let timelineViewModel = TimelineViewModel(roomProxy: roomProxy,
                                                  timelineController: TimelineControllerMock(.init(timelineItems: items)),
                                                  userSession: userSession,
                                                  mediaPlayerProvider: MediaPlayerProviderMock(),
                                                  userIndicatorController: UserIndicatorControllerMock(),
                                                  appMediator: AppMediatorMock(.init()),
                                                  analyticsService: AnalyticsServiceMock(.init()),
                                                  emojiProvider: EmojiProvider(userSettings: userSettings),
                                                  linkMetadataProvider: LinkMetadataProvider(),
                                                  timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        return .init(room: roomViewModel, timeline: timelineViewModel)
    }
    
    // MARK: - People
    
    static let helena = TimelineItemSender(id: "@helena:spiral.md", displayName: "Helena Ortiz")
    static let jacob = TimelineItemSender(id: "@jacob:spiral.md", displayName: "Jacob", status: .mock(text: "Rowing", emoji: "🚣‍♂️"))
    static let marcus = TimelineItemSender(id: "@marcus:spiral.md", displayName: "Marcus Lee")
    static let priya = TimelineItemSender(id: "@priya:spiral.md", displayName: "Priya Shah")
    private static let calendar = TimelineItemSender(id: "@calendar:spiral.md", displayName: "Calendar")
    static let me = TimelineItemSender(id: RoomMemberProxyMock.mockMe.userID, displayName: "Me")
    private static let people = [helena, jacob, marcus, priya, calendar]
    
    // MARK: - A group with many senders
    
    private static var groupItems: [RoomTimelineItemProtocol] {
        [
            SeparatorRoomTimelineItem(id: .virtual(uniqueID: .init("yesterday")), timestamp: time(minute: 30 - 24 * 60)),
            StateRoomTimelineItem(id: event("joined"),
                                  body: "Priya Shah joined the room",
                                  timestamp: time(minute: 30 - 24 * 60),
                                  isOutgoing: false,
                                  isEditable: false,
                                  canBeRepliedTo: false,
                                  sender: priya),
            text("offsite", "Morning all! Who's in for the offsite on Friday?", from: helena, minute: 31 - 24 * 60),
            text("headcount", "We need a headcount by tonight.", from: helena, minute: 31 - 24 * 60),
            text("in", "Count me in 🙋‍♂️", from: jacob, minute: 33 - 24 * 60),
            text("garden", "Can we go somewhere with a garden this time?", from: marcus, minute: 34 - 24 * 60),
            text("windows", "Last year's room had no windows.", from: marcus, minute: 35 - 24 * 60)
        ]
    }
    
    private static var groupNoticeItems: [RoomTimelineItemProtocol] {
        [
            SeparatorRoomTimelineItem(id: .virtual(uniqueID: .init("today")), timestamp: time(minute: 38)),
            text("greenhouse", "I booked the greenhouse at Kew 🌿", from: priya, minute: 38),
            NoticeRoomTimelineItem(id: event("reminder"),
                                   timestamp: time(minute: 39),
                                   isOutgoing: false,
                                   isEditable: false,
                                   canBeRepliedTo: true,
                                   sender: calendar,
                                   content: .init(body: "Reminder: the offsite is on Friday at 10:00.")),
            text("perfect", "Perfect, see you all there!", from: me, minute: 41),
            text("snacks", "I'll bring the snacks 🥨", from: me, minute: 41,
                 properties: .init(orderedReadReceipts: [helena, jacob, marcus, priya].map { ReadReceipt(userID: $0.id, formattedTimestamp: nil) }))
        ]
    }
    
    // MARK: - Reactions, a thread, media, an edit and a warning
    
    private static var reactionsItems: [RoomTimelineItemProtocol] {
        [
            SeparatorRoomTimelineItem(id: .virtual(uniqueID: .init("today")), timestamp: time(minute: 30)),
            image("cabin", caption: "The cabin 🏡", from: helena, minute: 30),
            text("lake", "Looks amazing. Is there a lake?", from: jacob, minute: 31,
                 properties: .init(isEdited: true, encryptionAuthenticity: .unsignedDevice(color: .red))),
            text("kayaks", "Two minutes' walk. Kayaks included!", from: helena, minute: 32,
                 properties: .init(reactions: [
                     AggregatedReaction(accountOwnerID: me.id, key: "🛶", senders: [me, jacob, marcus].map { ReactionSender(id: $0.id, timestamp: .mock) }),
                     AggregatedReaction(accountOwnerID: me.id, key: "😍", senders: [ReactionSender(id: priya.id, timestamp: .mock)])
                 ], encryptionAuthenticity: .notGuaranteed(color: .gray))),
            text("driving", "Who's driving?", from: marcus, minute: 33,
                 properties: .init(threadSummary: .loaded(senderID: priya.id,
                                                          sender: priya,
                                                          latestEventContent: .message(.text(.init(body: "I can take four people and the bags"))),
                                                          numberOfReplies: 3)))
        ]
    }
    
    // MARK: - A reply, own media and a failed send
    
    private static var repliesItems: [RoomTimelineItemProtocol] {
        [
            text("kayaks", "Two minutes' walk. Kayaks included!", from: helena, minute: 32),
            text("wetsuit", "Then I'm bringing my wetsuit", from: me, minute: 35,
                 properties: .init(replyDetails: .loaded(sender: helena,
                                                         eventID: "$kayaks",
                                                         eventContent: .message(.text(.init(body: "Two minutes' walk. Kayaks included!")))))),
            image("view", caption: nil, from: me, minute: 36),
            text("list", "Sending the packing list now", from: me, minute: 37,
                 properties: .init(deliveryStatus: .sendingFailed(.unknown(reason: nil)))),
            text("signal", "Back on Wi-Fi, trying again", from: me, minute: 40,
                 properties: .init(deliveryStatus: .sent))
        ]
    }
    
    // MARK: - The ticks' states: read, read through a later message, sent, sending and failed
    
    private static var ticksItems: [RoomTimelineItemProtocol] {
        [
            text("garden", "Can we go somewhere with a garden this time?", from: helena, minute: 34),
            text("kew", "Kew has a greenhouse you can book", from: me, minute: 35),
            text("booked", "Booked it", from: me, minute: 36,
                 properties: .init(orderedReadReceipts: [ReadReceipt(userID: helena.id, formattedTimestamp: nil)])),
            text("friday", "See you on Friday at ten, by the main gate. It's a long walk from the station, so give yourself time.",
                 from: me, minute: 37),
            text("ok", "Ok", from: me, minute: 38, properties: .init(deliveryStatus: .sending)),
            text("list", "Sending the packing list now", from: me, minute: 39,
                 properties: .init(deliveryStatus: .sendingFailed(.unknown(reason: nil))))
        ]
    }
    
    // MARK: - Files, voice, a poll, media and a sticker
    
    private static var filesItems: [RoomTimelineItemProtocol] {
        [
            file("route", caption: nil, from: helena, minute: 30),
            file("tickets", caption: nil, from: me, minute: 31),
            file("menu", caption: "The menu for Friday", from: me, minute: 32),
            audio("song", from: me, minute: 33),
            voice("message", from: helena, minute: 34),
            voice("answer", from: me, minute: 35)
        ]
    }
    
    private static var pollItems: [RoomTimelineItemProtocol] {
        [
            text("lunch", "Let's settle lunch", from: helena, minute: 30),
            PollRoomTimelineItem.mock(poll: .disclosed(), isOutgoing: true, isEditable: true)
        ]
    }
    
    private static var mediaItems: [RoomTimelineItemProtocol] {
        [
            image("cabin", caption: nil, from: helena, minute: 30),
            image("view", caption: "The view from the jetty", from: me, minute: 31),
            sticker("thumbs", from: me, minute: 32)
        ]
    }
    
    private static var captionedItems: [RoomTimelineItemProtocol] {
        [
            text("kayaks", "Two minutes' walk. Kayaks included!", from: helena, minute: 30),
            image("jetty", caption: "The kayaks are by the jetty", from: me, minute: 31,
                  properties: .init(replyDetails: .loaded(sender: helena,
                                                          eventID: "$kayaks",
                                                          eventContent: .message(.text(.init(body: "Two minutes' walk. Kayaks included!"))))))
        ]
    }
    
    private static var uncaptionedReplyItems: [RoomTimelineItemProtocol] {
        [
            text("kayaks", "Two minutes' walk. Kayaks included!", from: helena, minute: 30),
            image("jetty", caption: nil, from: me, minute: 31,
                  properties: .init(replyDetails: .loaded(sender: helena,
                                                          eventID: "$kayaks",
                                                          eventContent: .message(.text(.init(body: "Two minutes' walk. Kayaks included!"))))))
        ]
    }
    
    private static var galleryAndMapItems: [RoomTimelineItemProtocol] {
        [
            GalleryRoomTimelineItem(id: event("trip"),
                                    timestamp: time(minute: 30),
                                    isOutgoing: true,
                                    isEditable: false,
                                    canBeRepliedTo: true,
                                    sender: me,
                                    content: .init(body: "Gallery (2 items)",
                                                   caption: "Everything from the trip",
                                                   items: [.mockImage(index: 0), .mockImage(index: 1)])),
            LocationRoomTimelineItem(id: event("meet"),
                                     timestamp: time(minute: 31),
                                     isOutgoing: true,
                                     isEditable: false,
                                     canBeRepliedTo: true,
                                     sender: me,
                                     content: .init(body: "The jetty", geoURI: .init(latitude: 41.902782, longitude: 12.496366)),
                                     properties: .init(replyDetails: .loaded(sender: helena,
                                                                             eventID: "$kayaks",
                                                                             eventContent: .message(.text(.init(body: "Where do we meet?"))))))
        ]
    }
    
    // MARK: - Helpers
    
    static func file(_ id: String, caption: String?, from sender: TimelineItemSender, minute: Int) -> FileRoomTimelineItem {
        FileRoomTimelineItem(id: event(id),
                             timestamp: time(minute: minute),
                             isOutgoing: sender.id == me.id,
                             isEditable: false,
                             canBeRepliedTo: true,
                             sender: sender,
                             content: .init(filename: "\(id).pdf", caption: caption, source: nil, fileSize: 2_400_000, thumbnailSource: nil, contentType: nil))
    }
    
    private static func audio(_ id: String, from sender: TimelineItemSender, minute: Int) -> AudioRoomTimelineItem {
        AudioRoomTimelineItem(id: event(id),
                              timestamp: time(minute: minute),
                              isOutgoing: sender.id == me.id,
                              isEditable: false,
                              canBeRepliedTo: true,
                              sender: sender,
                              content: .init(filename: "\(id).ogg", duration: 100, waveform: nil, source: nil, fileSize: nil, contentType: nil))
    }
    
    static func voice(_ id: String, from sender: TimelineItemSender, minute: Int) -> VoiceMessageRoomTimelineItem {
        VoiceMessageRoomTimelineItem(id: event(id),
                                     timestamp: time(minute: minute),
                                     isOutgoing: sender.id == me.id,
                                     isEditable: false,
                                     canBeRepliedTo: true,
                                     sender: sender,
                                     content: .init(filename: "\(id).ogg",
                                                    duration: 100,
                                                    waveform: EstimatedWaveform.mockWaveform,
                                                    source: nil,
                                                    fileSize: nil,
                                                    contentType: nil))
    }
    
    private static func sticker(_ id: String, from sender: TimelineItemSender, minute: Int) -> StickerRoomTimelineItem {
        StickerRoomTimelineItem(id: event(id),
                                body: "A thumbs up",
                                timestamp: time(minute: minute),
                                isOutgoing: sender.id == me.id,
                                isEditable: false,
                                canBeRepliedTo: true,
                                sender: sender,
                                imageInfo: .mockImage,
                                blurhash: "L%KUc%kqS$RP?Ks,WEf8OlrqaekW")
    }
    
    static func text(_ id: String, _ body: String, from sender: TimelineItemSender, minute: Int,
                     properties: RoomTimelineItemProperties = .init()) -> TextRoomTimelineItem {
        TextRoomTimelineItem(id: event(id),
                             timestamp: time(minute: minute),
                             isOutgoing: sender.id == me.id,
                             isEditable: sender.id == me.id,
                             canBeRepliedTo: true,
                             sender: sender,
                             content: .init(body: body),
                             properties: properties)
    }
    
    static func image(_ id: String, caption: String?, from sender: TimelineItemSender, minute: Int,
                      properties: RoomTimelineItemProperties = .init()) -> ImageRoomTimelineItem {
        ImageRoomTimelineItem(id: event(id),
                              timestamp: time(minute: minute),
                              isOutgoing: sender.id == me.id,
                              isEditable: false,
                              canBeRepliedTo: true,
                              sender: sender,
                              content: .init(filename: "\(id).jpg",
                                             caption: caption,
                                             imageInfo: .mockImage,
                                             thumbnailInfo: .mockThumbnail,
                                             blurhash: "L%KUc%kqS$RP?Ks,WEf8OlrqaekW",
                                             contentType: .jpeg),
                              properties: properties)
    }
    
    static func event(_ id: String) -> TimelineItemIdentifier {
        .event(uniqueID: .init(id), eventOrTransactionID: .eventID("$\(id)"))
    }
    
    /// Minutes around 9:41, the snapshots' time.
    static func time(minute: Int) -> Date {
        Date.mock.addingTimeInterval(TimeInterval((minute - 41) * 60))
    }
}
