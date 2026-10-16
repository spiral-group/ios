//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import MatrixRustSDK
import Testing

@MainActor
struct TimelineItemFactoryTests {
    @Test
    func callInvite() throws {
        let ownUserID = "@alice:matrix.org"
        let senderUserID = "@bob:matrix.org"
        
        let factory = RoomTimelineItemFactory(userID: ownUserID,
                                              attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                              stateEventStringBuilder: RoomStateEventStringBuilder(userID: ownUserID))
        
        let eventTimelineItem = EventTimelineItem.mockCallInvite(sender: senderUserID)
        
        let eventTimelineItemProxy = EventTimelineItemProxy(item: eventTimelineItem, uniqueID: .init("0"))
        
        let item = try #require(factory.buildTimelineItem(for: eventTimelineItemProxy, isDM: false) as? CallInviteRoomTimelineItem,
                                "Incorrect item type")
        
        #expect(item.isReactable == false)
        #expect(item.canBeRepliedTo == false)
        #expect(item.isEditable == false)
        #expect(item.sender == TimelineItemSender(id: senderUserID))
        #expect(item.properties.isEdited == false)
        #expect(item.properties.reactions == [])
        #expect(item.properties.deliveryStatus == nil)
    }
    
    // AGENT-PLATFORM (calls-in-app walk F7; decisions 171/172): call tiles
    // built from SDK fixtures, one test per row of the call-tiles matrix's
    // expected tiles (`docs/walkthroughs/call-tiles-matrix-2026-10-15.md`).
    // `me` rang: the caller's side; `peer` rang: the callee's side.

    // MARK: DM — answered

    /// D1: answered at +16 s, ended at +156 s; the length is the talk time.
    @Test
    func aDMCallerSeesAnOutgoingCallWithTheTalkTime() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.me, notificationType: "ring",
                                                          answeredBy: [Self.peer], answeredTsMillis: Self.at(16),
                                                          joinedBy: [Self.me, Self.peer], firstJoinedTsMillis: Self.at(16),
                                                          ownUserJoined: true, endedTsMillis: Self.at(156)),
                                     isDM: true)

        Self.expect(tile, .answered(duration: 140),
                    title: UntranslatedL10n.screenNativeCallTileOutgoing, subtitle: "2m 20s")
    }

    @Test
    func aDMCalleeSeesAnIncomingCallWithTheTalkTime() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.peer, notificationType: "ring",
                                                          answeredBy: [Self.me], answeredTsMillis: Self.at(16),
                                                          joinedBy: [Self.peer, Self.me], firstJoinedTsMillis: Self.at(16),
                                                          ownUserJoined: true, endedTsMillis: Self.at(156)),
                                     isDM: true)

        Self.expect(tile, .answered(duration: 140),
                    title: UntranslatedL10n.screenNativeCallTileIncoming, subtitle: "2m 20s")
    }

    /// Without an answer time or an end there is no length to show, and none is made up.
    @Test
    func anAnsweredDMCallWithoutItsTimesShowsNoLength() throws {
        let noStart = try Self.callTile(.mockRtcNotification(sender: Self.me, notificationType: "ring",
                                                             answeredBy: [Self.peer], joinedBy: [Self.me, Self.peer],
                                                             ownUserJoined: true, endedTsMillis: Self.at(156)),
                                        isDM: true)
        let noEnd = try Self.callTile(.mockRtcNotification(sender: Self.me, notificationType: "ring",
                                                           answeredBy: [Self.peer], answeredTsMillis: Self.at(16),
                                                           joinedBy: [Self.me, Self.peer], firstJoinedTsMillis: Self.at(16),
                                                           ownUserJoined: true),
                                      isDM: true)

        Self.expect(noStart, .answered(duration: nil), title: UntranslatedL10n.screenNativeCallTileOutgoing, subtitle: nil)
        Self.expect(noEnd, .answered(duration: nil), title: UntranslatedL10n.screenNativeCallTileOutgoing, subtitle: nil)
    }

    // MARK: DM — late answer

    /// A CallKit answer tapped at the end of the 30 s ring lands after the
    /// SDK's answer window: `answeredBy` is empty, but the call happened.
    @Test
    func aDMCallerSeesALateAnswerAsAnOutgoingCall() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.me, notificationType: "ring",
                                                          joinedBy: [Self.me, Self.peer], firstJoinedTsMillis: Self.at(31),
                                                          ownUserJoined: true, endedTsMillis: Self.at(91)),
                                     isDM: true)

        Self.expect(tile, .answered(duration: 60),
                    title: UntranslatedL10n.screenNativeCallTileOutgoing, subtitle: "1m")
    }

    @Test
    func aDMCalleeSeesALateAnswerAsAnIncomingCall() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.peer, notificationType: "ring",
                                                          joinedBy: [Self.peer, Self.me], firstJoinedTsMillis: Self.at(31),
                                                          ownUserJoined: true, endedTsMillis: Self.at(91)),
                                     isDM: true)

        Self.expect(tile, .answered(duration: 60),
                    title: UntranslatedL10n.screenNativeCallTileIncoming, subtitle: "1m")
    }

    /// A late join with no recorded end yet is still an answer, with no length.
    @Test
    func aDMLateJoinWithNoEndIsAnAnswerWithoutLength() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.peer, notificationType: "ring",
                                                          joinedBy: [Self.peer, Self.me], firstJoinedTsMillis: Self.at(31),
                                                          ownUserJoined: true),
                                     isDM: true)

        Self.expect(tile, .answered(duration: nil), title: UntranslatedL10n.screenNativeCallTileIncoming, subtitle: nil)
    }

    /// The caller's own second device joining is no answer.
    @Test
    func aDMCallerJoiningFromAnotherDeviceIsNoAnswer() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.me, notificationType: "ring",
                                                          joinedBy: [Self.me], ownUserJoined: true, endedTsMillis: Self.at(32)),
                                     isDM: true)

        Self.expect(tile, .cancelled, title: UntranslatedL10n.screenNativeCallTileCancelled, subtitle: nil)
    }

    /// A join after the call had already ended answered nothing.
    @Test
    func aDMJoinAfterTheEndIsNoAnswer() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.me, notificationType: "ring",
                                                          joinedBy: [Self.me, Self.peer], firstJoinedTsMillis: Self.at(40),
                                                          ownUserJoined: true, endedTsMillis: Self.at(32)),
                                     isDM: true)

        Self.expect(tile, .cancelled, title: UntranslatedL10n.screenNativeCallTileCancelled, subtitle: nil)
    }

    // MARK: DM — declined

    @Test
    func aDMCallerSeesTheirCallDeclined() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.me, notificationType: "ring", declinedBy: [Self.peer],
                                                          joinedBy: [Self.me], ownUserJoined: true, endedTsMillis: Self.at(6)),
                                     isDM: true)

        Self.expect(tile, .declined(byMe: false), title: L10n.commonCallDeclined, subtitle: nil)
    }

    @Test
    func aDMCalleeSeesTheyDeclined() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.peer, notificationType: "ring", declinedBy: [Self.me],
                                                          joinedBy: [Self.peer], endedTsMillis: Self.at(6)),
                                     isDM: true)

        Self.expect(tile, .declined(byMe: true), title: L10n.commonCallYouDeclined, subtitle: nil)
    }

    // MARK: DM — unanswered and cancelled

    /// D3: my ring timed out. I missed nothing: a grey cancelled call, no call back.
    @Test
    func aDMCallerSeesTheirUnansweredRingAsCancelled() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.me, notificationType: "ring",
                                                          joinedBy: [Self.me], ownUserJoined: true, endedTsMillis: Self.at(32)),
                                     isDM: true)

        Self.expect(tile, .cancelled, title: UntranslatedL10n.screenNativeCallTileCancelled, subtitle: nil)
    }

    /// D4: I hung up at +8 s.
    @Test
    func aDMCallerSeesTheirCancelledRingAsCancelled() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.me, notificationType: "ring",
                                                          joinedBy: [Self.me], ownUserJoined: true, endedTsMillis: Self.at(8)),
                                     isDM: true)

        Self.expect(tile, .cancelled, title: UntranslatedL10n.screenNativeCallTileCancelled, subtitle: nil)
    }

    @Test
    func aDMCalleeSeesAnUnansweredRingAsMissed() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.peer, notificationType: "ring",
                                                          joinedBy: [Self.peer], endedTsMillis: Self.at(32)),
                                     isDM: true)

        Self.expect(tile, .missed, title: UntranslatedL10n.screenNativeCallTileMissed,
                    subtitle: UntranslatedL10n.screenNativeCallTileCallBack)
    }

    /// Cancel and missed read the same for the callee, by design.
    @Test
    func aDMCalleeSeesACancelledRingAsMissed() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.peer, notificationType: "ring",
                                                          joinedBy: [Self.peer], endedTsMillis: Self.at(8)),
                                     isDM: true)

        Self.expect(tile, .missed, title: UntranslatedL10n.screenNativeCallTileMissed,
                    subtitle: UntranslatedL10n.screenNativeCallTileCallBack)
    }

    // MARK: DM — ongoing

    /// D1b: the active tile's timer counts from the answer, as the call bar
    /// does, not from the ring.
    @Test
    func aDMCallerInTheirOngoingCallHasNoJoinAndCountsFromTheAnswer() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.me, notificationType: "ring",
                                                          activeMembers: [Self.me, Self.peer], callStartTsMillis: Self.at(0),
                                                          isJoined: true,
                                                          answeredBy: [Self.peer], answeredTsMillis: Self.at(16),
                                                          joinedBy: [Self.me, Self.peer], firstJoinedTsMillis: Self.at(17),
                                                          ownUserJoined: true),
                                     isDM: true)

        #expect(tile.callState == .active(activeMembers: [Self.me, Self.peer], isJoined: true,
                                          callStartTimestamp: Self.date(Self.at(16))))
    }

    /// A late answer outside the SDK's answer window counts from the callee's join.
    @Test
    func anOngoingDMCallAnsweredLateCountsFromTheJoin() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.peer, notificationType: "ring",
                                                          activeMembers: [Self.peer, Self.me], callStartTsMillis: Self.at(0),
                                                          isJoined: true,
                                                          joinedBy: [Self.peer, Self.me], firstJoinedTsMillis: Self.at(31),
                                                          ownUserJoined: true),
                                     isDM: true)

        #expect(tile.callState == .active(activeMembers: [Self.peer, Self.me], isJoined: true,
                                          callStartTimestamp: Self.date(Self.at(31))))
    }

    /// Still ringing: Join, and no running timer.
    @Test
    func aDMCalleeNotInTheRingingCallGetsJoinAndNoTimer() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.peer, notificationType: "ring",
                                                          activeMembers: [Self.peer], callStartTsMillis: Self.at(0),
                                                          joinedBy: [Self.peer]),
                                     isDM: true)

        #expect(tile.callState == .active(activeMembers: [Self.peer], isJoined: false, callStartTimestamp: nil))
    }

    // MARK: Group

    /// G2d: B joined at +73 s, past any ring window. Everyone sees the call
    /// with its length from that first join, and no direction.
    @Test
    func aGroupMemberWhoJoinedSeesTheGroupCallWithItsLength() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.peer, notificationType: "ring",
                                                          joinedBy: [Self.peer, Self.me], firstJoinedTsMillis: Self.at(73),
                                                          ownUserJoined: true, endedTsMillis: Self.at(150)),
                                     isDM: false)

        Self.expect(tile, .groupCall(duration: 77, ownUserJoined: true),
                    title: UntranslatedL10n.screenNativeCallTileGroup, subtitle: "1m 17s")
    }

    /// G1: the starter of a call someone answered in time reads the same
    /// group call, not "Outgoing call".
    @Test
    func aGroupCallStarterSeesTheGroupCallNotAnOutgoingCall() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.me, notificationType: "ring",
                                                          answeredBy: [Self.peer], answeredTsMillis: Self.at(17),
                                                          joinedBy: [Self.me, Self.peer], firstJoinedTsMillis: Self.at(17),
                                                          ownUserJoined: true, endedTsMillis: Self.at(46)),
                                     isDM: false)

        Self.expect(tile, .groupCall(duration: 29, ownUserJoined: true),
                    title: UntranslatedL10n.screenNativeCallTileGroup, subtitle: "29s")
    }

    /// The starter's own membership (sent just before the ring) may not be
    /// loaded, so the SDK can't see them join; the starter was in their call.
    @Test
    func aGroupCallStarterIsNeverToldTheyDidNotJoin() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.me, notificationType: "ring",
                                                          joinedBy: [Self.peer], firstJoinedTsMillis: Self.at(17),
                                                          ownUserJoined: false, endedTsMillis: Self.at(46)),
                                     isDM: false)

        Self.expect(tile, .groupCall(duration: 29, ownUserJoined: true),
                    title: UntranslatedL10n.screenNativeCallTileGroup, subtitle: "29s")
    }

    /// G-third: a member who never joined is told so, not "Incoming call · 46s".
    @Test
    func aGroupMemberWhoNeverJoinedIsToldSo() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.peer, notificationType: "ring",
                                                          answeredBy: [Self.third], answeredTsMillis: Self.at(17),
                                                          joinedBy: [Self.peer, Self.third], firstJoinedTsMillis: Self.at(17),
                                                          ownUserJoined: false, endedTsMillis: Self.at(63)),
                                     isDM: false)

        Self.expect(tile, .groupCall(duration: 46, ownUserJoined: false),
                    title: UntranslatedL10n.screenNativeCallTileGroup,
                    subtitle: "46s · \(UntranslatedL10n.screenNativeCallTileNotJoined)")
    }

    /// A decline doesn't hide a group call the others had.
    @Test
    func aGroupCallIDeclinedThatOthersHadIsTheGroupCall() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.peer, notificationType: "ring", declinedBy: [Self.me],
                                                          joinedBy: [Self.peer, Self.third], firstJoinedTsMillis: Self.at(20),
                                                          endedTsMillis: Self.at(80)),
                                     isDM: false)

        Self.expect(tile, .groupCall(duration: 60, ownUserJoined: false),
                    title: UntranslatedL10n.screenNativeCallTileGroup,
                    subtitle: "1m · \(UntranslatedL10n.screenNativeCallTileNotJoined)")
    }

    /// G3b / walk call 0: a group call its starter sat in alone and left.
    @Test
    func aGroupCallNobodyElseJoinedReadsEnded() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.me, joinedBy: [Self.me], ownUserJoined: true,
                                                          endedTsMillis: Self.at(295)),
                                     isDM: false)

        Self.expect(tile, .unclassified, title: UntranslatedL10n.screenNativeCallTileEnded, subtitle: nil)
    }

    @Test
    func aDeclinedGroupCallNobodyJoinedReadsEnded() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.peer, notificationType: "ring", declinedBy: [Self.me],
                                                          joinedBy: [Self.peer], endedTsMillis: Self.at(10)),
                                     isDM: false)

        Self.expect(tile, .declined(byMe: true), title: UntranslatedL10n.screenNativeCallTileEnded, subtitle: nil)
    }

    /// G2a: a running group call keeps its Join, however long nobody joined,
    /// and its timer counts from the first join by someone other than the
    /// starter, never from the ring or an answer.
    @Test
    func aRunningGroupCallKeepsItsJoinAndCountsFromTheFirstJoin() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.peer, notificationType: "ring",
                                                          activeMembers: [Self.peer, Self.third], callStartTsMillis: Self.at(0),
                                                          answeredBy: [Self.third], answeredTsMillis: Self.at(70),
                                                          joinedBy: [Self.peer, Self.third], firstJoinedTsMillis: Self.at(73)),
                                     isDM: false)

        #expect(tile.callState == .active(activeMembers: [Self.peer, Self.third], isJoined: false,
                                          callStartTimestamp: Self.date(Self.at(73))))
    }

    /// A group call its starter still sits in alone: no running timer.
    @Test
    func aGroupCallNobodyElseJoinedYetHasNoTimer() throws {
        let tile = try Self.callTile(.mockRtcNotification(sender: Self.me, notificationType: "ring",
                                                          activeMembers: [Self.me], callStartTsMillis: Self.at(0),
                                                          isJoined: true,
                                                          joinedBy: [Self.me], ownUserJoined: true),
                                     isDM: false)

        #expect(tile.callState == .active(activeMembers: [Self.me], isJoined: true, callStartTimestamp: nil))
    }

    private static let me = "@alice:matrix.org"
    private static let peer = "@bob:matrix.org"
    private static let third = "@carol:matrix.org"

    /// A server timestamp `seconds` after the ring (the fixture's own timestamp).
    private static func at(_ seconds: UInt64) -> UInt64 {
        UInt64(Date.mock.timeIntervalSince1970 * 1000) + seconds * 1000
    }

    private static func date(_ millis: UInt64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }

    private static func callTile(_ item: EventTimelineItem, isDM: Bool) throws -> CallNotificationRoomTimelineItem {
        let factory = RoomTimelineItemFactory(userID: me,
                                              attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                              stateEventStringBuilder: RoomStateEventStringBuilder(userID: me))
        let proxy = EventTimelineItemProxy(item: item, uniqueID: .init("0"))
        return try #require(factory.buildTimelineItem(for: proxy, isDM: isDM) as? CallNotificationRoomTimelineItem,
                            "Incorrect item type")
    }

    private static func expect(_ tile: CallNotificationRoomTimelineItem,
                               _ outcome: CallNotificationRoomTimelineItem.TombstonedOutcome,
                               title: String,
                               subtitle: String?,
                               sourceLocation: SourceLocation = #_sourceLocation) {
        guard case .tombstoned(let actual) = tile.callState else {
            Issue.record("Expected an ended call, got \(tile.callState)", sourceLocation: sourceLocation)
            return
        }
        #expect(actual == outcome, sourceLocation: sourceLocation)
        #expect(tile.tombstoneTitle(for: actual) == title, sourceLocation: sourceLocation)
        #expect(tile.tombstoneSubtitle(for: actual) == subtitle, sourceLocation: sourceLocation)
    }
    
    // AGENT-PLATFORM (Brief 0066): the Interactive Post tests from here down.
    /// An Interactive Post carries what every other message carries.
    ///
    /// This is the only test standing between a post and the state it shipped
    /// in: `properties` was left at its default, so reactions, read receipts
    /// and the edited marker were all dead while the row looked finished. The
    /// reaction was reaching the server the whole time — only the row never
    /// asked for it back.
    @Test
    func interactivePostKeepsMessageProperties() throws {
        let ownUserID = "@alice:matrix.org"
        let senderUserID = "@bob:matrix.org"
        
        let factory = RoomTimelineItemFactory(userID: ownUserID,
                                              attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                              stateEventStringBuilder: RoomStateEventStringBuilder(userID: ownUserID))
        
        let reaction = Reaction(key: "👍", senders: [.init(senderId: ownUserID, timestamp: 1_700_000_000_000)])
        let receipt = Receipt(timestamp: 1_700_000_000_000)
        
        let eventTimelineItem = EventTimelineItem.mockInteractivePost(sender: senderUserID,
                                                                      reactions: [reaction],
                                                                      readReceipts: [senderUserID: receipt],
                                                                      isEdited: true)
        
        let proxy = EventTimelineItemProxy(item: eventTimelineItem, uniqueID: .init("0"))
        
        let item = try #require(factory.buildTimelineItem(for: proxy, isDM: false) as? InteractivePostRoomTimelineItem,
                                "Incorrect item type")
        
        #expect(item.properties.reactions.map(\.key) == ["👍"])
        #expect(item.properties.reactions.first?.senders.map(\.id) == [ownUserID])
        #expect(item.properties.orderedReadReceipts.map(\.userID) == [senderUserID])
        #expect(item.properties.isEdited)
        
        // Taken from the SDK rather than invented here. `canBeRepliedTo` was
        // once derived from whether the post was itself a reply, which said a
        // post you replied to could not be replied to again.
        #expect(item.canBeRepliedTo)
        #expect(item.isEditable == false)
        #expect(item.post.title == "a counter")
    }

    /// A quoted post says it is a post.
    ///
    /// Replies, thread summaries and search results all render whatever the
    /// factory hands them. A post used to arrive as `.message(.text(title))` —
    /// indistinguishable from somebody having typed its name, in the three
    /// places where a reader most needs to know what they are looking at.
    @Test
    func aQuotedPostIsNotMistakenForSomebodyTypingItsName() {
        let factory = RoomTimelineItemFactory(userID: "@alice:matrix.org",
                                              attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                              stateEventStringBuilder: RoomStateEventStringBuilder(userID: "@alice:matrix.org"))

        let post = MessageType.interactivePost(content: .init(body: "a counter",
                                                              appId: "counter",
                                                              runtime: "1",
                                                              title: "a counter",
                                                              aspect: "4:3",
                                                              stateChannel: "matrix",
                                                              sha256: String(repeating: "a", count: 64),
                                                              url: "mxc://spiral.md/abc",
                                                              fileJson: nil))

        #expect(factory.buildEventContent(messageType: post, senderID: "@bob:matrix.org", senderDisplayName: nil)
            == .interactivePost(title: "a counter"))

        // Everything else keeps travelling as it did.
        let text = MessageType.text(content: .init(body: "hello", formatted: nil))
        guard case .message(.text(let content)) = factory.buildEventContent(messageType: text,
                                                                            senderID: "@bob:matrix.org",
                                                                            senderDisplayName: nil) else {
            Issue.record("a text message stopped being a text message")
            return
        }
        #expect(content.body == "hello")
    }
    
    // AGENT-PLATFORM (Brief 0066 § 5.89)
    /// The agent-tools fallback reaches the factory as `.other`. It must come
    /// out as the state row it stands in for — and any other `.other` must
    /// stay hidden, as upstream has it.
    // AGENT-PLATFORM (Brief 0073): only an agent's notice becomes a card; a
    // person sending the same msgtype gets plain text, so nobody can forge a
    // «sign-in phrase changed» card.
    @Test
    func aNoticeIsACardOnlyFromAnAgent() throws {
        let factory = RoomTimelineItemFactory(userID: "@alice:spiral.md",
                                              attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                              stateEventStringBuilder: RoomStateEventStringBuilder(userID: "@alice:spiral.md"))
        
        let fromAgent = EventTimelineItemProxy(item: .mockSpiralNotice(sender: "@assistant-alice:spiral.md"), uniqueID: .init("0"))
        #expect(factory.buildTimelineItem(for: fromAgent, isDM: true) is SpiralNoticeRoomTimelineItem)
        
        let fromPerson = EventTimelineItemProxy(item: .mockSpiralNotice(sender: "@mallory:spiral.md"), uniqueID: .init("1"))
        let item = try #require(factory.buildTimelineItem(for: fromPerson, isDM: true) as? TextRoomTimelineItem)
        #expect(item.content.body == "fallback")
    }
    
    @Test
    func agentToolsFallbackBecomesAStateRow() throws {
        let ownUserID = "@alice:matrix.org"
        let agent = "@assistant-alice:matrix.org"
        let stateEventStringBuilder = RoomStateEventStringBuilder(userID: ownUserID)
        let factory = RoomTimelineItemFactory(userID: ownUserID,
                                              attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                              stateEventStringBuilder: stateEventStringBuilder)
        let fallback = """
        {"type":"com.spiral.tools.changed","sender":"\(agent)",
         "content":{"version":1,"by":"\(ownUserID)","at":1000,"tools":[{"tool":"summarize","enabled":true}],"fallback":true}}
        """
        
        let item = EventTimelineItemProxy(item: .mockOtherMessageLike(sender: agent, originalJSON: fallback), uniqueID: .init("0"))
        let row = try #require(factory.buildTimelineItem(for: item, isDM: false) as? StateRoomTimelineItem,
                               "the fallback is a state row")
        #expect(row.body == stateEventStringBuilder.buildSpiralToolsFallbackString(rawEventJSON: fallback,
                                                                                   sender: TimelineItemSender(id: agent)))
        
        let unknown = #"{"type":"com.example.unknown","sender":"@bob:matrix.org","content":{}}"#
        let other = EventTimelineItemProxy(item: .mockOtherMessageLike(sender: "@bob:matrix.org", originalJSON: unknown), uniqueID: .init("1"))
        #expect(factory.buildTimelineItem(for: other, isDM: false) == nil, "any other custom event stays hidden")
    }
}
