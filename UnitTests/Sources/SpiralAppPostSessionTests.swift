//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007): what an action is computed FROM.
//
// These exist because of something a device run showed and no unit test had:
// tapping twice inside one round trip produced one increment. Both actions
// were computed from the last CONFIRMED state, both claimed the same `seq`,
// and last-write-wins kept one.
//
// The fold is not at fault — an action carries the full state its sender
// computed, and a `seq` collision is exactly how the schema says to notice
// two senders working from the same base. The fault is that the second tap
// had no reason to be working from a stale base: we wrote the first one
// ourselves and knew about it.
//

import Combine
import Compound
@testable import ElementX
import Foundation
import SwiftUI
import Testing

@MainActor
struct SpiralAppPostSessionTests {
    // MARK: - Helpers

    private static let postEventID = "$post"

    /// A room that accepts every write and records what it was given, and
    /// whose relations never return anything — so the session is driven
    /// purely by what the test does, not by a fixture.
    private static func room(relations: [String] = []) -> JoinedRoomProxyMock {
        let room = JoinedRoomProxyMock(.init())
        room.loadSpiralAppRelationsForReturnValue = .success(relations)
        room.sendSpiralRawEventTypeContentReturnValue = .success(())
        room.subscribeToSpiralEventsTypesListenerReturnValue = .failure(.sdkError(SpiralTestError.noSubscription))
        return room
    }

    private enum SpiralTestError: Error { case noSubscription }

    /// The `content` of every action the session wrote, parsed.
    private static func written(_ room: JoinedRoomProxyMock) -> [[String: Any]] {
        room.sendSpiralRawEventTypeContentReceivedInvocations.compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.content.utf8)) as? [String: Any]
        }
    }

    /// The `by` of an action carrying a single `incr`, if that is what it is.
    ///
    /// Actions assert on their OPERATION rather than on a state blob: the
    /// blob left the wire when it turned out to be 85–90 % of an event that
    /// nothing read.
    private static func incrementBy(_ action: [String: Any]) -> Int? {
        ((action["op"] as? [String: Any])?["incr"] as? [String: Any])?["by"] as? Int
    }

    /// The appended item of an action carrying a single `listAppend`.
    private static func appendedItem(_ action: [String: Any]) -> String? {
        ((action["op"] as? [String: Any])?["listAppend"] as? [String: Any])?["item"] as? String
    }

    private static func session(_ room: JoinedRoomProxyMock) async -> SpiralAppPostSession {
        let session = SpiralAppPostSession(postEventID: postEventID,
                                           roomProxy: room,
                                           feed: SpiralAppActionFeed(roomProxy: room))
        await session.start()
        return session
    }

    // MARK: - The defect

    @Test
    func aSecondTapBeforeTheFirstComesBackStillCounts() async {
        // The device case, reduced: two operations with nothing arriving in
        // between. Before the fix both wrote count 1 and seq 1.
        let room = Self.room()
        let session = await Self.session(room)

        _ = await session.apply(.increment(path: ["count"], by: 1))
        _ = await session.apply(.increment(path: ["count"], by: 1))

        let actions = Self.written(room)
        #expect(actions.count == 2)
        #expect(actions[0]["seq"] as? Int == 1)
        #expect(actions[1]["seq"] as? Int == 2)
        // Both carry the increment itself, not a computed total: what the
        // room folds is the operations, and a second `incr 1` is what makes
        // the count two even though neither action says "two".
        #expect(Self.incrementBy(actions[0]) == 1)
        #expect(Self.incrementBy(actions[1]) == 1)
    }

    /// An action is its operation. The whole state used to ride along beside
    /// it and was 85–90 % of the event — 11.5 KB on a drawing fifteen strokes
    /// old, carrying 900 bytes of new fact, growing with every stroke for
    /// everyone in the room. The fold never read it: a blob is a checkpoint
    /// only when an action has no operation, and none did.
    @Test
    func anActionCarriesItsOperationAndNotTheWholeState() async {
        let room = Self.room()
        let session = await Self.session(room)

        _ = await session.apply(.set(path: ["title"], value: .string("Обід")))

        let written = Self.written(room)
        #expect(written.count == 1)
        #expect(written[0]["op"] != nil, "the operation is the point of the action")
        #expect(written[0]["state"] == nil, "the state blob is back on the wire")
    }

    @Test
    func aBurstNumbersItselfInOrder() async {
        let room = Self.room()
        let session = await Self.session(room)

        for _ in 0..<5 {
            _ = await session.apply(.increment(path: ["count"], by: 1))
        }

        #expect(Self.written(room).compactMap { $0["seq"] as? Int } == [1, 2, 3, 4, 5])
    }

    @Test
    func operationsOtherThanCountersAlsoStack() async {
        // `incr` is the obvious victim, but anything reading the previous
        // value is: a list would append to the same empty array twice.
        let room = Self.room()
        let session = await Self.session(room)

        _ = await session.apply(.listAppend(path: ["items"], item: .string("a")))
        _ = await session.apply(.listAppend(path: ["items"], item: .string("b")))

        let written = Self.written(room)
        #expect(written.count == 2)
        #expect(Self.appendedItem(written[0]) == "a")
        #expect(Self.appendedItem(written[1]) == "b")
    }

    // MARK: - Not replaying what was never written

    @Test
    func aRefusedWriteIsNotReplayed() async {
        // A send that failed left nothing in the room, so replaying it would
        // invent a change no other client will ever see.
        let room = Self.room()
        let session = await Self.session(room)

        room.sendSpiralRawEventTypeContentReturnValue = .failure(.sdkError(SpiralTestError.noSubscription))
        _ = await session.apply(.increment(path: ["count"], by: 1))

        room.sendSpiralRawEventTypeContentReturnValue = .success(())
        _ = await session.apply(.increment(path: ["count"], by: 1))

        let actions = Self.written(room)
        #expect(actions.count == 2)
        // The second write is the first SURVIVING one, so it starts again at 1.
        #expect(actions[1]["seq"] as? Int == 1)
        #expect(Self.incrementBy(actions[1]) == 1)
    }

    /// 6.11 A2 — the LOCAL ECHO. The app is shown the working state the
    /// moment an operation is pending, at the pending seq, so the fold it
    /// adopts when `apply` resolves already holds the tap and nothing
    /// flickers back. It does not double: the SDK's `adopt` replaces its own
    /// optimistic copy with the pushed state rather than stacking on it.
    @Test
    func aPendingOperationIsEchoedToTheAppBeforeTheRoomConfirmsIt() async {
        let room = Self.room()
        let session = await Self.session(room)

        _ = await session.apply(.increment(path: ["count"], by: 1))

        #expect(session.workingState == .object(["count": .number(1)]))
        #expect(session.snapshot.state == .object(["count": .number(1)]))
        #expect(session.snapshot.seq == 1)
    }

    @Test
    func aFailedSendTakesItsEchoBack() async {
        let room = Self.room()
        let session = await Self.session(room)
        room.sendSpiralRawEventTypeContentReturnValue = .failure(.sdkError(SpiralTestError.noSubscription))

        _ = await session.apply(.increment(path: ["count"], by: 1))

        #expect(session.snapshot.state == .object([:]))
        #expect(session.snapshot.seq == 0)
    }

    // MARK: - What the post says where its code is not running

    @Test
    func aSummaryRidesAlongWithTheAction() async {
        // The only thing a client can show without executing the app: the
        // timeline card, a push, a search snapshot.
        let room = Self.room()
        let session = await Self.session(room)

        _ = await session.apply(.increment(path: ["count"], by: 1),
                                summary: ["line": "1 tap", "notify": "badge"])

        let written = Self.written(room).first
        let summary = written?["summary"] as? [String: Any]
        #expect(summary?["line"] as? String == "1 tap")
        #expect(summary?["notify"] as? String == "badge")
    }

    @Test
    func anActionWithoutASummaryCarriesNoSummaryKey() async {
        // An app that says nothing must not write an empty object that a
        // native card would then try to render.
        let room = Self.room()
        let session = await Self.session(room)

        _ = await session.apply(.increment(path: ["count"], by: 1))

        #expect(Self.written(room).first?["summary"] == nil)
    }

    // MARK: - What an app is allowed to know

    @Test
    func contextNamesTheViewerTheRoomAndThePost() async {
        let room = Self.room()
        let session = await Self.session(room)

        let context = session.context
        #expect(context["postId"] as? String == Self.postEventID)
        #expect(context["roomId"] as? String == room.id)
        #expect(context["userId"] as? String == room.ownUserID)
    }

    @Test
    func membersAreOnlyPeopleActuallyInTheRoom() async {
        // An app counting "3 of 5" must not count someone who left or was
        // only invited.
        let room = Self.room()
        room.membersPublisher = CurrentValueSubject([
            RoomMemberProxyMock(with: .init(userID: "@joined:spiral.md",
                                            displayName: "Joined",
                                            membership: .join)),
            RoomMemberProxyMock(with: .init(userID: "@left:spiral.md",
                                            displayName: "Left",
                                            membership: .leave)),
            RoomMemberProxyMock(with: .init(userID: "@invited:spiral.md",
                                            displayName: "Invited",
                                            membership: .invite))
        ]).asCurrentValuePublisher()

        let session = await Self.session(room)
        let members = await session.members()["members"] as? [[String: Any]]

        #expect(members?.count == 1)
        #expect(members?.first?["userId"] as? String == "@joined:spiral.md")
    }

    @Test
    func anAppThatAsksBeforeTheRosterLoadsGetsTheRoster() async {
        // A room shows its posts before its roster loads, and
        // `useRoomMembers` asks once: answered with nobody but us, an app
        // showed an empty room for good (2026-09-22).
        let room = Self.room()
        let me = RoomMemberProxyMock(with: .init(userID: "@me:spiral.md", displayName: "Me", membership: .join))
        let anya = RoomMemberProxyMock(with: .init(userID: "@anya:spiral.md", displayName: "Anya", membership: .join))
        let roster = CurrentValueSubject<[RoomMemberProxyProtocol], Never>([me])
        room.membersPublisher = roster.asCurrentValuePublisher()
        room.updateMembersClosure = { roster.send([me, anya]) }

        let session = await Self.session(room)
        let members = await session.members()["members"] as? [[String: Any]]

        #expect(room.updateMembersCallsCount == 1)
        #expect(members?.count == 2)
    }

    @Test
    func aLoadedRosterIsNotFetchedAgain() async {
        // Every post in a room asks; a roster already there must not send
        // each of them to the server.
        let room = Self.room()
        room.membersPublisher = CurrentValueSubject([
            RoomMemberProxyMock(with: .init(userID: "@me:spiral.md", displayName: "Me", membership: .join)),
            RoomMemberProxyMock(with: .init(userID: "@anya:spiral.md", displayName: "Anya", membership: .join))
        ]).asCurrentValuePublisher()

        let session = await Self.session(room)
        let members = await session.members()["members"] as? [[String: Any]]

        #expect(room.updateMembersCallsCount == 0)
        #expect(members?.count == 2)
    }

    // MARK: - People, not agents; avatars as the messenger has them (§ 5.64)

    @Test
    func theAgentIsNotAPersonInTheRoom() async {
        let room = Self.room()
        room.membersPublisher = CurrentValueSubject([
            RoomMemberProxyMock(with: .init(userID: "@me:spiral.md", displayName: "Me", membership: .join)),
            RoomMemberProxyMock(with: .init(userID: "@anya:spiral.md", displayName: "Anya", membership: .join)),
            RoomMemberProxyMock(with: .init(userID: "@assistant-me:spiral.md", displayName: "Assistant Me 2", membership: .join)),
            RoomMemberProxyMock(with: .init(userID: "@agent-sales-1:spiral.md", displayName: "Sales", membership: .join))
        ]).asCurrentValuePublisher()

        let session = await Self.session(room)
        let members = await session.members()["members"] as? [[String: Any]]

        #expect(members?.map { $0["userId"] as? String } == ["@me:spiral.md", "@anya:spiral.md"])
        #expect(room.updateMembersCallsCount == 0, "two people is a roster; the agent did not make it look empty")
        #expect(SpiralAppPostSession.isAgent("@agentsmith:spiral.md") == false, "a person whose name starts with agent")
        #expect(SpiralAppPostSession.isAgent("assistant-x:spiral.md") == false)
    }

    /// The frame has no network, so an avatar travels as the messenger's own
    /// thumbnail in a `data:` URL; one that does not load is simply absent.
    @Test
    func anAvatarIsHandedOverAsAThumbnail() async throws {
        let media = MediaProviderMock(.init())
        media.loadThumbnailForSourceSourceSizeClosure = { source, size in
            #expect(size == SpiralAppPostSession.avatarSize)
            return source.url == .mockMXCUserAvatar ? .success(Data([0xFF, 0xD8, 0xFF])) : .failure(.failedRetrievingImage)
        }
        let members: [RoomMemberProxyProtocol] = [
            RoomMemberProxyMock(with: .init(userID: "@a:spiral.md", displayName: "A", avatarURL: .mockMXCUserAvatar, membership: .join)),
            RoomMemberProxyMock(with: .init(userID: "@b:spiral.md", displayName: "B", avatarURL: .mockMXCImage, membership: .join)),
            RoomMemberProxyMock(with: .init(userID: "@c:spiral.md", displayName: "C", membership: .join))
        ]

        let payload = await SpiralAppPostSession.membersPayload(members, mediaProvider: media)
        let entries = try #require(payload["members"] as? [[String: Any]])

        #expect(entries[0]["avatarUrl"] as? String == "data:image/jpeg;base64,/9j/")
        #expect(entries[1]["avatarUrl"] == nil, "a thumbnail that did not load leaves the placeholder")
        #expect(entries[2]["avatarUrl"] == nil)
        #expect(media.loadThumbnailForSourceSourceSizeCallsCount == 2, "no fetch for a member without an avatar")
    }

    /// The kit colours a placeholder avatar by Compound's own hash so a post
    /// shows the same colour the room list shows for the same person; this
    /// pins the number the kit's test pins (`decorativeIndex`).
    @Test
    func thePlaceholderColourIsTheMessengers() {
        // Compound's `String.hashCode`: the sum of the code points, mod the six
        // decorative colours. Pinned here as the same number the kit pins.
        let sum = "@emmm:spiral.md".unicodeScalars.reduce(0) { $0 + Int($1.value) }
        #expect(sum % 6 + 1 == 5)
        // And the id with that sum lands on the same colour as one whose sum
        // is 4 — i.e. the messenger reads the same slot.
        #expect(Color.compound.decorativeColor(for: "@emmm:spiral.md") == Color.compound.decorativeColor(for: "\u{04}"))
    }

    // MARK: - The roster follows the room (§ 5.67)

    /// Someone joining while the post is mounted is published as a new
    /// roster; a name changing is not; the agent joining is not.
    @Test
    func theRosterIsPublishedWhenThePeopleChange() async throws {
        let room = Self.room()
        let me = RoomMemberProxyMock(with: .init(userID: "@me:spiral.md", displayName: "Me", membership: .join))
        let roster = CurrentValueSubject<[RoomMemberProxyProtocol], Never>([me])
        room.membersPublisher = roster.asCurrentValuePublisher()
        let session = await Self.session(room)

        var published: [[String]] = []
        let cancellable = session.membersPublisher.sink { payload in
            published.append((payload["members"] as? [[String: Any]])?.compactMap { $0["userId"] as? String } ?? [])
        }
        defer { cancellable.cancel() }

        roster.send([me, RoomMemberProxyMock(with: .init(userID: "@me:spiral.md", displayName: "Me!", membership: .join))].suffix(1).map { $0 })
        roster.send([me, RoomMemberProxyMock(with: .init(userID: "@assistant-me:spiral.md", displayName: "Assistant", membership: .join))])
        roster.send([me, RoomMemberProxyMock(with: .init(userID: "@anya:spiral.md", displayName: "Anya", membership: .join))])
        try await Task.sleep(for: .milliseconds(200))

        #expect(published == [["@me:spiral.md", "@anya:spiral.md"]])
    }

    // MARK: - «Your move» (§ 5.73, § 5.74)

    /// One raw action by `sender` that pinged `mentions`.
    private static func rawAction(_ eventID: String, ts: UInt64, sender: String, mentions: [String] = []) -> String {
        let pinged = mentions.isEmpty ? "" : #","m.mentions":{"user_ids":["\#(mentions.joined(separator: "\",\""))"]}"#
        return """
        {"type":"com.spiral.app.action","event_id":"\(eventID)","sender":"\(sender)","origin_server_ts":\(ts),
         "content":{"m.relates_to":{"rel_type":"m.reference","event_id":"$post"},"seq":\(ts),
                    "op":{"incr":{"path":"n","by":1}}\(pinged)}}
        """
    }

    /// An action that names someone carries the mention itself: the mention
    /// rule reads `m.mentions` whatever the event's type, so the named person
    /// is pushed and nobody else is (§ 5.73). Never oneself or an agent, and
    /// no message beside the move.
    @Test
    func namingSomeoneInASummaryMentionsThemOnTheActionItself() async {
        let room = Self.room()
        let session = await Self.session(room)
        let me = room.ownUserID
        let bob = "@bob:spiral.md"

        _ = await session.apply(.increment(path: ["n"], by: 1), summary: ["line": "e2–e4", "notify_users": [bob, bob, me, "@assistant-me:spiral.md"]])
        _ = await session.apply(.increment(path: ["n"], by: 1), summary: ["line": "quiet"])

        let sent = room.sendSpiralRawEventTypeContentReceivedInvocations
        #expect(sent.allSatisfy { $0.type == SpiralAppAction.eventType }, "no message beside the move")
        let actions = Self.written(room)
        #expect(actions.count == 2)
        #expect((actions[0]["m.mentions"] as? [String: Any])?["user_ids"] as? [String] == [bob], "once each, never oneself or an agent")
        #expect(actions[1]["m.mentions"] == nil)
    }

    /// Pinged and not answered: not pinged again — however many actions name
    /// them, and however fast. It was once a minute per person per session,
    /// and in a quick game of chess that swallowed three replies in five
    /// (§ 5.74). Our own action still on its way counts as a ping already.
    @Test
    func someonePingedIsNotPingedAgainUntilTheyAct() async {
        let bob = "@bob:spiral.md"
        let me = JoinedRoomProxyMock(.init()).ownUserID

        // We pinged Bob, and he has not touched the post since.
        let waiting = Self.room(relations: [Self.rawAction("$1", ts: 1, sender: me, mentions: [bob])])
        let quiet = await Self.session(waiting)
        _ = await quiet.apply(.increment(path: ["n"], by: 1), summary: ["notify_users": [bob]])
        #expect(Self.written(waiting)[0]["m.mentions"] == nil, "Bob has not answered the last ping")

        // Bob moved after it: he has answered, and this move is news again.
        let answered = Self.room(relations: [Self.rawAction("$1", ts: 1, sender: me, mentions: [bob]),
                                             Self.rawAction("$2", ts: 2, sender: bob, mentions: [me])])
        let quick = await Self.session(answered)
        _ = await quick.apply(.increment(path: ["n"], by: 1), summary: ["notify_users": [bob]])
        _ = await quick.apply(.increment(path: ["n"], by: 1), summary: ["notify_users": [bob]])
        let written = Self.written(answered)
        #expect((written[0]["m.mentions"] as? [String: Any])?["user_ids"] as? [String] == [bob], "a reply a second ago still counts")
        #expect(written[1]["m.mentions"] == nil, "our first ping is still on its way")
    }

    // MARK: - Refusing to brick the post

    @Test
    func aStatePastTheBudgetIsRefusedRatherThanWritten() async {
        // Every action carries the whole state and a Matrix event caps at
        // 64 KB, so an app that only grows would one day write a state no
        // event can hold — and from then on nothing could be written at all,
        // including whatever would shrink it back.
        let room = Self.room()
        let session = await Self.session(room)

        let huge = String(repeating: "x", count: 20 * 1024)
        let result = await session.apply(.set(path: ["blob"], value: .string(huge)))

        if case .failure(.stateTooLarge) = result { } else {
            Issue.record("a state past the budget was written")
        }
        #expect(room.sendSpiralRawEventTypeContentCalled == false)
    }

    @Test
    func aRefusedOversizeDoesNotPoisonTheNextWrite() async {
        // The refusal happens before the operation joins `pending`, so the
        // app can carry on rather than being stuck behind its own mistake.
        let room = Self.room()
        let session = await Self.session(room)

        _ = await session.apply(.set(path: ["blob"], value: .string(String(repeating: "x", count: 20 * 1024))))
        _ = await session.apply(.increment(path: ["count"], by: 1))

        let written = Self.written(room)
        // The oversized write never left, so the only action is the one that
        // followed it — and it carries its own operation, nothing of the
        // state that was refused.
        #expect(written.count == 1)
        #expect(Self.incrementBy(written[0]) == 1)
        #expect(written[0]["seq"] as? Int == 1)
    }

    // MARK: - Owned paths

    @Test
    func aWriteIntoSomeoneElsesNamespaceIsRefusedBeforeItIsSent() async {
        // `by.<userId>` is that user's. The fold would drop the action on
        // every phone anyway; refusing here tells the app now.
        let room = Self.room()
        let session = await Self.session(room)

        let result = await session.apply(.set(path: ["by", "@other:spiral.md", "vote"], value: .string("A")))

        if case .failure(.notOwner) = result { } else {
            Issue.record("a write into another user's namespace was sent")
        }
        #expect(room.sendSpiralRawEventTypeContentCalled == false)
        #expect(SpiralAppPostError.notOwner.bridgeCode == "rejected")
    }

    @Test
    func aWriteIntoOnesOwnNamespaceGoesThrough() async {
        let room = Self.room()
        let session = await Self.session(room)

        let result = await session.apply(.set(path: ["by", room.ownUserID, "vote"], value: .string("A")))

        if case .failure = result {
            Issue.record("a write into the sender's own namespace was refused")
        }
        #expect(Self.written(room).count == 1)
    }

    @Test
    func aBatchWithOneForeignMemberIsRefusedWhole() async {
        let room = Self.room()
        let session = await Self.session(room)

        let result = await session.apply(.batch([
            .increment(path: ["count"], by: 1),
            .set(path: ["by", "@other:spiral.md", "vote"], value: .string("A"))
        ]))

        if case .failure(.notOwner) = result { } else {
            Issue.record("a batch carrying a foreign write was sent")
        }
        #expect(room.sendSpiralRawEventTypeContentCalled == false)
    }

    // MARK: - Time

    @Test
    func theClockIsNeverEarlierThanTheNewestAction() async {
        // A phone whose clock is behind must not make a deadline that has
        // passed look open: the room's newest event is a floor.
        let farFuture: UInt64 = 4_102_444_800_000 // 2100-01-01
        let room = Self.room(relations: ["""
        {"type":"com.spiral.app.action","event_id":"$late","sender":"@a:spiral.md",
         "origin_server_ts":\(farFuture),
         "content":{"m.relates_to":{"rel_type":"m.reference","event_id":"$post"},
                    "seq":1,"op":{"set":{"path":"n","value":1}},"state":{"n":1}}}
        """])
        let session = await Self.session(room)

        let time = session.time
        #expect(time["floor"] as? UInt64 == farFuture)
        #expect(time["now"] as? UInt64 == farFuture, "the clock was allowed to run behind the room")
    }

    @Test
    func theClockIsTheWallClockWhenTheRoomIsQuiet() async {
        let room = Self.room()
        let session = await Self.session(room)
        let before = UInt64(Date().timeIntervalSince1970 * 1000)

        let time = session.time

        #expect(time["floor"] as? UInt64 == 0)
        #expect((time["now"] as? UInt64 ?? 0) >= before)
        #expect((time["now"] as? UInt64 ?? 0) <= before + 5000)
    }

    // MARK: - Refusing to build on a hole

    @Test
    func nothingIsWrittenWhileTheStateIsStillLoading() async {
        // Publishing a full-state snapshot computed from an incomplete read
        // would make every other client adopt the hole.
        let room = JoinedRoomProxyMock(.init())
        room.loadSpiralAppRelationsForReturnValue = .failure(.sdkError(SpiralTestError.noSubscription))
        room.sendSpiralRawEventTypeContentReturnValue = .success(())
        room.subscribeToSpiralEventsTypesListenerReturnValue = .failure(.sdkError(SpiralTestError.noSubscription))

        let session = await Self.session(room)
        let result = await session.apply(.increment(path: ["count"], by: 1))

        #expect(session.snapshot.readiness == .loading)
        if case .failure(.stateNotReady) = result { } else {
            Issue.record("a write was allowed from a state the reader could not vouch for")
        }
        #expect(room.sendSpiralRawEventTypeContentCalled == false)
    }
}
