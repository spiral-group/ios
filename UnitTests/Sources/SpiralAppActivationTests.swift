//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (security pass 2, posts H2 · M2 · L3): what a post may do in
// the reader's name, and how often.
//
// A post's code used to write, ping and take the whole screen on its own
// word that the reader had asked. These pin the native answer: a touch the
// host saw itself, recently, and buckets that let a tap's burst through and
// a flood not.
//

import Foundation
@testable import Spiral
import SwiftUI
import Testing

extension SpiralAppActivation {
    /// A reader who has just touched the post.
    static func touched() -> SpiralAppActivation {
        let activation = SpiralAppActivation()
        activation.recordTouch()
        return activation
    }
}

@MainActor
struct SpiralAppActivationTests {
    /// A clock a test moves by hand.
    private final class Clock {
        var now: TimeInterval = 1000
    }

    private static func activation(_ clock: Clock) -> SpiralAppActivation {
        SpiralAppActivation { clock.now }
    }

    private static let write = SpiralAppCapability.stateSharedWrite.rawValue
    private nonisolated static let increment = Data(#"{"op":{"incr":{"path":["n"],"by":1}}}"#.utf8)

    // MARK: - The touch

    @Test
    func noTouchIsNoActivation() {
        #expect(!Self.activation(Clock()).hasRecentTouch)
    }

    @Test
    func aTouchCountsForTheWindowAndNoLonger() {
        let clock = Clock()
        let activation = Self.activation(clock)

        activation.recordTouch()
        clock.now += SpiralAppActivation.window
        #expect(activation.hasRecentTouch)

        clock.now += 0.01
        #expect(!activation.hasRecentTouch)
    }

    @Test
    func aTouchThatScrolledTheTimelineIsTakenBack() {
        let activation = Self.activation(Clock())
        activation.recordTouch()

        activation.revokeTouch()

        #expect(!activation.hasRecentTouch)
    }

    // MARK: - Writes (H2, decision 235)

    private nonisolated static let badge = Data(#"{"op":{"incr":{"path":["n"],"by":1}},"summary":{"line":"1","notify":"badge"}}"#.utf8)

    /// A defender's phone answering a shot, a field typed on the keyboard:
    /// a silent write needs no touch (decision 235).
    @Test(arguments: [SpiralAppActivationTests.increment, SpiralAppActivationTests.badge])
    func aSilentWriteWithNobodyTouchingThePostPasses(args: Data) async {
        let session = SpiralAppPreviewSession(userID: "@a:spiral.md", members: [:])

        let reply = await session.answer(method: Self.write, args: args, activation: Self.activation(Clock()))

        #expect(reply.contains(#""ok":true"#))
        #expect(session.snapshot.seq == 1)
    }

    // MARK: - Pings (H2, decision 235)

    private static let me = "@a:spiral.md"
    private static let bob = "@bob:spiral.md"
    private static let carol = "@carol:spiral.md"

    /// A room where `bob` has just made a move — a shot this phone answers.
    private static func room(shotBy shooter: String = bob) -> JoinedRoomProxyMock {
        let people = [me, bob, carol].map { RoomMemberProxyMock(with: .init(userID: $0, membership: .join)) }
        let room = JoinedRoomProxyMock(.init(members: people, ownUserID: me))
        room.loadSpiralAppRelationsForReturnValue = .success(["""
        {"type":"com.spiral.app.action","event_id":"$shot","sender":"\(shooter)","origin_server_ts":10,
         "content":{"m.relates_to":{"rel_type":"m.reference","event_id":"$post"},"seq":1,
                    "op":{"set":{"path":"shot","value":1}}}}
        """])
        room.sendSpiralRawEventTypeContentReturnValue = .success(())
        room.subscribeToSpiralEventsTypesListenerReturnValue = .failure(.sdkError(PingTestError.noSubscription))
        return room
    }

    private enum PingTestError: Error { case noSubscription }

    private static func session(_ room: JoinedRoomProxyMock) async -> SpiralAppPostSession {
        let session = SpiralAppPostSession(postEventID: "$post", roomProxy: room, feed: SpiralAppActionFeed(roomProxy: room))
        await session.start()
        return session
    }

    private static func written(_ room: JoinedRoomProxyMock) -> [[String: Any]] {
        room.sendSpiralRawEventTypeContentReceivedInvocations.compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.content.utf8)) as? [String: Any]
        }
    }

    private static func mentions(_ action: [String: Any]?) -> [String]? {
        (action?["m.mentions"] as? [String: Any])?["user_ids"] as? [String]
    }

    private static func ping(_ users: [String]) -> Data {
        let named = users.map { "\"\($0)\"" }.joined(separator: ",")
        let field = users.isEmpty ? "" : #","notify_users":[\#(named)]"#
        return Data(#"{"op":{"incr":{"path":["n"],"by":1}},"summary":{"line":"your move","notify":"ping"\#(field)}}"#.utf8)
    }

    /// Sea Battle: the defender's phone answers a hit by itself, and the
    /// shooter must still hear «your move».
    @Test
    func anUntouchedAnswerPingsTheMoverItAnswers() async throws {
        let room = Self.room()
        let session = await Self.session(room)

        let reply = await session.answer(method: Self.write, args: Self.ping([Self.bob]), activation: Self.activation(Clock()))

        #expect(reply.contains(#""ok":true"#))
        let action = try #require(Self.written(room).first)
        #expect(Self.mentions(action) == [Self.bob])
        #expect((action["summary"] as? [String: Any])?["notify"] as? String == "ping")
    }

    @Test
    func anUntouchedPingDropsAnyoneItDoesNotAnswer() async {
        let room = Self.room()
        let session = await Self.session(room)

        _ = await session.answer(method: Self.write, args: Self.ping([Self.carol, Self.bob]), activation: Self.activation(Clock()))
        _ = await session.answer(method: Self.write, args: Self.ping([Self.carol]), activation: Self.activation(Clock()))

        let written = Self.written(room)
        #expect(written.count == 2, "an untouched write did not go out")
        #expect(Self.mentions(written[0]) == [Self.bob])
        #expect((written[0]["summary"] as? [String: Any])?["notify_users"] as? [String] == [Self.bob])
        #expect(Self.mentions(written[1]) == nil, "an uninvolved member was pushed")
        #expect((written[1]["summary"] as? [String: Any])?["notify"] as? String == "badge")
    }

    @Test
    func oneMoveIsAnsweredWithOneUntouchedPing() async {
        let room = Self.room()
        let session = await Self.session(room)

        _ = await session.answer(method: Self.write, args: Self.ping([Self.bob]), activation: Self.activation(Clock()))
        _ = await session.answer(method: Self.write, args: Self.ping([Self.bob]), activation: Self.activation(Clock()))

        let written = Self.written(room)
        #expect(Self.mentions(written[0]) == [Self.bob])
        #expect(Self.mentions(written[1]) == nil, "one move was answered with two pushes")
    }

    @Test
    func anUntouchedPingToTheWholeRoomIsABadge() async throws {
        let room = Self.room()
        let session = await Self.session(room)

        _ = await session.answer(method: Self.write, args: Self.ping([]), activation: Self.activation(Clock()))

        let action = try #require(Self.written(room).first)
        #expect(Self.mentions(action) == nil)
        #expect((action["summary"] as? [String: Any])?["notify"] as? String == "badge")
    }

    @Test
    func aTouchedPingNamesWhomItLikes() async throws {
        let room = Self.room()
        let session = await Self.session(room)

        _ = await session.answer(method: Self.write, args: Self.ping([Self.carol]), activation: .touched())

        let action = try #require(Self.written(room).first)
        #expect(Self.mentions(action) == [Self.carol])
        #expect((action["summary"] as? [String: Any])?["notify"] as? String == "ping")
    }

    // MARK: - The screen (H2, M2)

    @Test
    func anExpandWithoutATouchIsRefused() async {
        let session = SpiralAppPreviewSession(userID: "@a:spiral.md", members: [:])
        var expanded = 0
        session.onExpandRequested = { expanded += 1 }

        let reply = await session.answer(method: SpiralAppCapability.uiExpand.rawValue, args: Data(), activation: Self.activation(Clock()))

        #expect(reply.contains("rejected"))
        #expect(expanded == 0)
    }

    @Test
    func oneTouchOpensTheScreenOnce() async {
        let clock = Clock()
        let activation = Self.activation(clock)
        let session = SpiralAppPreviewSession(userID: "@a:spiral.md", members: [:])
        var expanded = 0
        session.onExpandRequested = { expanded += 1 }

        activation.recordTouch()
        clock.now += 0.1
        _ = await session.answer(method: SpiralAppCapability.uiExpand.rawValue, args: Data(), activation: activation)
        clock.now += 0.1
        _ = await session.answer(method: SpiralAppCapability.uiExpand.rawValue, args: Data(), activation: activation)
        #expect(expanded == 1)

        clock.now += 0.1
        activation.recordTouch()
        clock.now += 0.1
        _ = await session.answer(method: SpiralAppCapability.uiExpand.rawValue, args: Data(), activation: activation)
        #expect(expanded == 2, "a new touch is a new request")
    }

    @Test
    func closingTheViewerNeedsANewTouchToReopenIt() {
        let clock = Clock()
        let activation = Self.activation(clock)

        // The reader plays in the viewer, then taps Done a moment later.
        activation.recordTouch()
        clock.now += 1
        activation.viewerDismissed()
        clock.now += 0.1
        #expect(!activation.consumeForExpand(), "a touch from inside the viewer reopened it")
        #expect(activation.hasRecentTouch, "the same touch may still write")

        clock.now += 0.1
        activation.recordTouch()
        clock.now += 0.1
        #expect(activation.consumeForExpand())
    }

    /// M2: the viewer's chrome is the messenger's. A post's own words used
    /// to be its title, so a post could title itself «Sign in to Spiral».
    @Test
    func theViewerIsNamedForWhoSentThePostNeverByIt() {
        let mallory = SpiralAppViewerAuthor(id: "@mallory:spiral.md", displayName: "Mallory", avatarURL: nil)
        let chrome = SpiralAppViewerChrome(title: "Sign in to Spiral", author: mallory)

        #expect(chrome.title == "Mallory")
        #expect(chrome.subtitle == UntranslatedL10n.spiralAppViewerSubtitle)
        #expect(chrome.safetyLine == UntranslatedL10n.spiralAppViewerBanner, "the safety line stays while it is open")
        #expect(![chrome.title, chrome.subtitle, chrome.safetyLine].contains { $0?.contains("Sign in") == true })
    }

    /// A room post and a draft both name their sender as the room does: by a
    /// disambiguated name, else the id — never a blank header.
    @Test
    func aSenderIsNamedAsTheRoomNamesThem() {
        let named = SpiralAppViewerAuthor(TimelineItemSender(id: "@a:spiral.md", displayName: "Alice", avatarURL: URL(string: "mxc://spiral.md/a")))
        let unnamed = SpiralAppViewerAuthor(TimelineItemSender(id: "@b:spiral.md"))

        #expect(named == SpiralAppViewerAuthor(id: "@a:spiral.md", displayName: "Alice", avatarURL: URL(string: "mxc://spiral.md/a")))
        #expect(unnamed.displayName == "@b:spiral.md")
    }

    /// Our own catalogue's templates keep their title, alone: no author, no safety line.
    @Test
    func aTemplateIsNamedByItsTitleAlone() {
        let chrome = SpiralAppViewerChrome(title: "Poll", author: nil)

        #expect(chrome.title == "Poll")
        #expect(chrome.subtitle == nil)
        #expect(chrome.safetyLine == nil)
        #expect(!chrome.isRehearsal)
    }

    /// A template tried full screen from the catalogue's page is still a rehearsal (question 412): no author, no
    /// room, and the page's banner; a post somebody sent is never one.
    @Test
    func aTemplateTriedFullScreenKeepsTheRehearsalBanner() {
        let tried = SpiralAppViewerChrome(title: "Drawing", author: nil, isRehearsal: true)
        let sent = SpiralAppViewerChrome(title: "Drawing",
                                         author: SpiralAppViewerAuthor(id: "@a:spiral.md", displayName: "Alice", avatarURL: nil),
                                         isRehearsal: true)

        #expect(tried.title == "Drawing")
        #expect(tried.subtitle == nil)
        #expect(tried.safetyLine == nil)
        #expect(tried.isRehearsal)
        #expect(!sent.isRehearsal, "a sent post keeps its author and safety line")
    }

    // MARK: - Haptics (L3)

    @Test
    func hapticsAreTenASecond() {
        let clock = Clock()
        let activation = Self.activation(clock)

        #expect((0..<10).allSatisfy { _ in activation.allowsHaptic() })
        #expect(!activation.allowsHaptic())

        clock.now += 0.1
        #expect(activation.allowsHaptic())
        #expect(!activation.allowsHaptic())
    }

    // MARK: - The bucket

    @Test
    func aBucketGivesItsCapacityThenRefillsAtItsRate() {
        var bucket = SpiralAppTokenBucket(capacity: 3, refillInterval: 1)
        var taken: [Bool] = []
        for moment in [0, 0, 0, 0.5, 1.0, 1.0] {
            taken.append(bucket.take(at: moment))
        }
        #expect(taken == [true, true, true, false, true, false])

        // Never more than its capacity, however long it rests.
        let rested = (0..<4).map { _ in bucket.take(at: 100) }
        #expect(rested == [true, true, true, false])
    }

    @Test
    func theWriteBucketPassesADragOnOurSDK() {
        // One batch per 300 ms coalescing window, for a minute.
        var bucket = SpiralAppTokenBucket.sharedWrites
        let taken = (0..<200).map { bucket.take(at: Double($0) * 0.3) }
        #expect(!taken.contains(false))
    }
}
