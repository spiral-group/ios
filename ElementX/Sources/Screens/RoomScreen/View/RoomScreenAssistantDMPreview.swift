//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083): the assistant's DM as a room preview, with the
// reviewer-path storyboard's sample content (canvas v11, step 5), and a DM with
// a person, whose presence is the header's subtitle.
//

import Combine
import SwiftUI

extension RoomScreen_Previews {
    /// The owner's DM with their assistant: the welcome notice, the owner's "hello", the
    /// assistant's reply and a note it relayed from another room.
    static func makeAssistantDMViewModels() -> ViewModels {
        let assistant = RoomMemberProxyMock(with: .init(userID: assistantID, displayName: assistantName, membership: .join))
        // A member who left: the relayed note names its sender from the room's members, without a profile request.
        let relayer = RoomMemberProxyMock(with: .init(userID: marcusID, displayName: marcusName, membership: .leave))
        let roomProxy = JoinedRoomProxyMock(.init(id: "!assistant-dm:spiral.md",
                                                  name: assistantName,
                                                  isDirect: true,
                                                  hasOngoingCall: false,
                                                  members: [.mockMe, assistant, relayer],
                                                  heroes: [assistant]))

        let clientProxy = ClientProxyMock(.init())
        clientProxy.roomSummaryForIdentifierReturnValue = .mock(id: relayedRoomID, name: "Design meetup")
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))

        let roomViewModel = RoomScreenViewModel.mock(roomProxyMock: roomProxy, userSession: userSession)
        let timelineViewModel = TimelineViewModel(roomProxy: roomProxy,
                                                  timelineController: TimelineControllerMock(.init(timelineItems: assistantDMItems)),
                                                  userSession: userSession,
                                                  mediaPlayerProvider: MediaPlayerProviderMock(),
                                                  userIndicatorController: UserIndicatorControllerMock(),
                                                  appMediator: AppMediatorMock(.init()),
                                                  analyticsService: AnalyticsServiceMock(.init()),
                                                  emojiProvider: EmojiProvider(userSettings: userSession.userSettings),
                                                  linkMetadataProvider: LinkMetadataProvider(),
                                                  timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        return .init(room: roomViewModel, timeline: timelineViewModel)
    }

    /// The owner's DM with a person who is online: assistants have no presence, so only a person's DM shows the
    /// subtitle. No call is on, so the header has the DM's own call buttons. The owner's last messages carry what
    /// draws on an own bubble in colours of its own: a pill, code in a quote, a link, a file and a failed send.
    static func makeDMWithPresenceViewModels() -> ViewModels {
        let marcus = RoomMemberProxyMock(with: .init(userID: marcusID, displayName: marcusName, membership: .join))
        let roomProxy = JoinedRoomProxyMock(.init(id: "!marcus-dm:spiral.md",
                                                  name: marcusName,
                                                  isDirect: true,
                                                  hasOngoingCall: false,
                                                  members: [.mockMe, marcus],
                                                  heroes: [marcus]))

        // "online" whenever the snapshot runs, as `RoomHeaderView_Previews` has it.
        let presenceObserverService = PresenceObserverServiceMock()
        presenceObserverService.underlyingPresencePublisher = CurrentValueSubject([marcusID: UserPresence(userID: marcusID,
                                                                                                          state: .online,
                                                                                                          lastActiveAgo: 2,
                                                                                                          currentlyActive: true,
                                                                                                          receivedAt: .now)])
            .asCurrentValuePublisher()
        let userSession = UserSessionMock(.init())
        userSession.presenceObserverService = presenceObserverService

        let roomViewModel = RoomScreenViewModel.mock(roomProxyMock: roomProxy, userSession: userSession)
        let timelineViewModel = TimelineViewModel(roomProxy: roomProxy,
                                                  timelineController: TimelineControllerMock(.init(timelineItems: dmWithPresenceItems)),
                                                  userSession: userSession,
                                                  mediaPlayerProvider: MediaPlayerProviderMock(),
                                                  userIndicatorController: UserIndicatorControllerMock(),
                                                  appMediator: AppMediatorMock(.init()),
                                                  analyticsService: AnalyticsServiceMock(.init()),
                                                  emojiProvider: EmojiProvider(userSettings: userSession.userSettings),
                                                  linkMetadataProvider: LinkMetadataProvider(),
                                                  timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        return .init(room: roomViewModel, timeline: timelineViewModel)
    }

    /// A group with an agent in it (decision 357): the header's rounded square, and the badge beside the agent's
    /// messages where a person's stand too.
    static func makeGroupWithAgentViewModels() -> ViewModels {
        let roomProxy = JoinedRoomProxyMock(.init(id: "!design-meetup:spiral.md",
                                                  name: "Design meetup",
                                                  hasOngoingCall: false,
                                                  members: [.mockMe,
                                                            RoomMemberProxyMock(with: .init(userID: assistantID, displayName: assistantName, membership: .join)),
                                                            RoomMemberProxyMock(with: .init(userID: marcusID, displayName: marcusName, membership: .join))]))
        let userSession = UserSessionMock(.init(clientProxy: ClientProxyMock(.init())))
        let roomViewModel = RoomScreenViewModel.mock(roomProxyMock: roomProxy, userSession: userSession)
        let timelineViewModel = TimelineViewModel(roomProxy: roomProxy,
                                                  timelineController: TimelineControllerMock(.init(timelineItems: groupWithAgentItems)),
                                                  userSession: userSession,
                                                  mediaPlayerProvider: MediaPlayerProviderMock(),
                                                  userIndicatorController: UserIndicatorControllerMock(),
                                                  appMediator: AppMediatorMock(.init()),
                                                  analyticsService: AnalyticsServiceMock(.init()),
                                                  emojiProvider: EmojiProvider(userSettings: .mock()),
                                                  linkMetadataProvider: LinkMetadataProvider(),
                                                  timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        return .init(room: roomViewModel, timeline: timelineViewModel)
    }

    private static let assistantID = "@assistant-appreview:spiral.md"
    private static let assistantName = "App Review · assistant"
    private static let marcusID = "@marcus:spiral.md"
    private static let marcusName = "Marcus Lee"
    private static let relayedRoomID = "!design-meetup:spiral.md"

    private static var assistantDMItems: [RoomTimelineItemProtocol] {
        let assistantSender = TimelineItemSender(id: assistantID, displayName: assistantName)
        return [
            SeparatorRoomTimelineItem(id: .virtual(uniqueID: .init("today")), timestamp: .now),
            notice(id: "welcome",
                   minute: 40,
                   sender: assistantSender,
                   facts: #"{"kind":"welcome","owner_display_name":"App Review","agent_display_name":"App Review · assistant","behavior":"personal_assistant"}"#),
            TextRoomTimelineItem(id: event("hello"),
                                 timestamp: time(minute: 41),
                                 isOutgoing: true,
                                 isEditable: true,
                                 canBeRepliedTo: true,
                                 sender: .init(id: RoomMemberProxyMock.mockMe.userID, displayName: "App Review"),
                                 content: .init(body: "hello"),
                                 properties: .init(orderedReadReceipts: [ReadReceipt(userID: assistantID, formattedTimestamp: nil)])),
            TextRoomTimelineItem(id: event("reply"),
                                 timestamp: time(minute: 41),
                                 isOutgoing: false,
                                 isEditable: false,
                                 canBeRepliedTo: true,
                                 sender: assistantSender,
                                 content: .init(body: "Hi! I’m here. Ask me to pass on a message, remember someone, or sum up a chat.")),
            notice(id: "relayed",
                   minute: 42,
                   sender: assistantSender,
                   facts: #"{"kind":"relayed_to_owner","note":"Marcus is running 20 minutes late and asks you to start without him.","from_user_id":"\#(marcusID)","room_id":"\#(relayedRoomID)"}"#)
        ]
    }

    private static var groupWithAgentItems: [RoomTimelineItemProtocol] {
        [
            SeparatorRoomTimelineItem(id: .virtual(uniqueID: .init("today")), timestamp: .now),
            TextRoomTimelineItem(id: event("ask"),
                                 timestamp: time(minute: 40),
                                 isOutgoing: false,
                                 isEditable: false,
                                 canBeRepliedTo: true,
                                 sender: .init(id: marcusID, displayName: marcusName),
                                 content: .init(body: "Can someone sum up what we agreed?")),
            TextRoomTimelineItem(id: event("summary"),
                                 timestamp: time(minute: 41),
                                 isOutgoing: false,
                                 isEditable: false,
                                 canBeRepliedTo: true,
                                 sender: .init(id: assistantID, displayName: assistantName),
                                 content: .init(body: "You agreed on Thursday at 10, in the small room.")),
            TextRoomTimelineItem(id: event("thanks"),
                                 timestamp: time(minute: 42),
                                 isOutgoing: true,
                                 isEditable: true,
                                 canBeRepliedTo: true,
                                 sender: .init(id: RoomMemberProxyMock.mockMe.userID, displayName: "App Review"),
                                 content: .init(body: "Thanks!"))
        ]
    }

    private static var dmWithPresenceItems: [RoomTimelineItemProtocol] {
        [
            SeparatorRoomTimelineItem(id: .virtual(uniqueID: .init("today")), timestamp: .now),
            TextRoomTimelineItem(id: event("late"),
                                 timestamp: time(minute: 40),
                                 isOutgoing: false,
                                 isEditable: false,
                                 canBeRepliedTo: true,
                                 sender: .init(id: marcusID, displayName: marcusName),
                                 content: .init(body: "Running 20 minutes late. Start without me?")),
            TextRoomTimelineItem(id: event("sure"),
                                 timestamp: time(minute: 41),
                                 isOutgoing: true,
                                 isEditable: true,
                                 canBeRepliedTo: true,
                                 sender: .init(id: RoomMemberProxyMock.mockMe.userID, displayName: "App Review"),
                                 content: .init(body: "Sure, see you there."),
                                 properties: .init(orderedReadReceipts: [ReadReceipt(userID: marcusID, formattedTimestamp: nil)])),
            TextRoomTimelineItem(id: event("door-code"),
                                 timestamp: time(minute: 41),
                                 isOutgoing: true,
                                 isEditable: true,
                                 canBeRepliedTo: true,
                                 sender: .init(id: RoomMemberProxyMock.mockMe.userID, displayName: "App Review"),
                                 content: .init(body: "Marcus Lee here's the door code: Gate 4512, then the lift. The place: spiral.md/venue",
                                                formattedBody: AttributedStringBuilder(mentionBuilder: MentionBuilder())
                                                    .fromHTML(doorCodeHTML))),
            failedFile
        ]
    }

    /// A pill, code in a quote and a link.
    private static var doorCodeHTML: String {
        #"<a href="https://matrix.to/#/\#(marcusID)">\#(marcusName)</a> here's the door code:"#
            + "<blockquote>Gate <code>4512</code>, then the lift</blockquote>"
            + #"The place: <a href="https://spiral.md/venue">spiral.md/venue</a>"#
    }

    /// A file the owner sent while offline: the send failed.
    private static var failedFile: FileRoomTimelineItem {
        var item = FileRoomTimelineItem(id: event("venue-map"),
                                        timestamp: time(minute: 42),
                                        isOutgoing: true,
                                        isEditable: false,
                                        canBeRepliedTo: true,
                                        sender: .init(id: RoomMemberProxyMock.mockMe.userID, displayName: "App Review"),
                                        content: .init(filename: "venue-map.pdf",
                                                       source: try? MediaSourceProxy(url: .mockMXCFile, mimeType: nil),
                                                       fileSize: 1_200_000,
                                                       thumbnailSource: nil,
                                                       contentType: nil))
        item.properties.deliveryStatus = .sendingFailed(.unknown(reason: nil))
        return item
    }

    private static func notice(id: String, minute: Int, sender: TimelineItemSender, facts: String) -> SpiralNoticeRoomTimelineItem {
        SpiralNoticeRoomTimelineItem(id: event(id),
                                     timestamp: time(minute: minute),
                                     sender: sender,
                                     notice: SpiralNotice(msgtype: SpiralNotice.msgtype,
                                                          data: #"{"com.spiral.notice":"# + facts + "}")!) // swiftlint:disable:this force_unwrapping
    }

    private static func event(_ id: String) -> TimelineItemIdentifier {
        .event(uniqueID: .init(id), eventOrTransactionID: .eventID("$\(id)"))
    }

    /// 9:40, 9:41 and 9:42, as the storyboard has them.
    private static func time(minute: Int) -> Date {
        Date.mock.addingTimeInterval(TimeInterval((minute - 41) * 60))
    }
}
