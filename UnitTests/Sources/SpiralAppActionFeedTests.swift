//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 5.16): one subscription, and each
// post hearing only itself.
//
// Both properties are invisible from a session: it cannot tell whether it is
// the only subscriber, nor whether the actions it was handed were filtered for
// it or merely happened to match. So they are asserted here.
//

@testable import ElementX
import Foundation
import MatrixRustSDK
import Testing

@MainActor
struct SpiralAppActionFeedTests {
    @Test
    func manyPostsOpenOneSubscription() async {
        let room = Self.room()
        let feed = SpiralAppActionFeed(roomProxy: room)

        for index in 0..<4 {
            _ = await feed.listen(toPost: "$post\(index)") { _ in }
        }

        #expect(room.subscribeToSpiralEventsTypesListenerCallsCount == 1)
        #expect(feed.listenedPostCount == 4)
    }

    @Test
    func theRoomIsNotSubscribedUntilSomeoneListens() async {
        let room = Self.room()
        let feed = SpiralAppActionFeed(roomProxy: room)

        #expect(feed.isSubscribed == false)
        _ = await feed.listen(toPost: "$post") { _ in }
        #expect(feed.isSubscribed == true)
    }

    @Test
    func theLastListenerToLeaveClosesTheSubscription() async {
        // A room nobody is watching should cost nothing — otherwise every room
        // ever opened keeps a live handle for the session's lifetime.
        let room = Self.room()
        let feed = SpiralAppActionFeed(roomProxy: room)

        let first = await feed.listen(toPost: "$a") { _ in }
        let second = await feed.listen(toPost: "$b") { _ in }

        feed.stopListening(first)
        #expect(feed.isSubscribed == true, "closed while someone was still listening")

        feed.stopListening(second)
        #expect(feed.isSubscribed == false)
    }

    @Test
    func anActionReachesOnlyThePostItNames() async {
        let room = Self.room()
        let feed = SpiralAppActionFeed(roomProxy: room)

        var mine: [SpiralObservedEvent] = []
        var theirs: [SpiralObservedEvent] = []
        _ = await feed.listen(toPost: "$mine") { mine += $0 }
        _ = await feed.listen(toPost: "$theirs") { theirs += $0 }

        await Self.deliver([Self.action(on: "$mine", seq: 1),
                            Self.action(on: "$theirs", seq: 1),
                            Self.action(on: "$mine", seq: 2)],
                           to: room)

        #expect(mine.count == 2)
        #expect(theirs.count == 1)
    }

    @Test
    func anActionForAPostNobodyIsWatchingIsDropped() async {
        let room = Self.room()
        let feed = SpiralAppActionFeed(roomProxy: room)

        var mine: [SpiralObservedEvent] = []
        _ = await feed.listen(toPost: "$mine") { mine += $0 }

        await Self.deliver([Self.action(on: "$somewhere-else", seq: 1)], to: room)

        #expect(mine.isEmpty)
    }

    @Test
    func aStoppedListenerHearsNothingMore() async {
        let room = Self.room()
        let feed = SpiralAppActionFeed(roomProxy: room)

        var heard: [SpiralObservedEvent] = []
        let token = await feed.listen(toPost: "$mine") { heard += $0 }
        feed.stopListening(token)

        await Self.deliver([Self.action(on: "$mine", seq: 1)], to: room)

        #expect(heard.isEmpty)
    }

    // MARK: - Reading the envelope

    @Test
    func theEnvelopeNamesThePostAnActionBelongsTo() {
        let json = Self.actionJSON(on: "$post", seq: 7)
        #expect(SpiralAppActionFeed.postEventID(ofRawEventJSON: json) == "$post")
    }

    @Test
    func somethingThatIsNotAReferenceNamesNoPost() {
        // A thread reply carries `m.relates_to` too. Routing on the presence of
        // the key alone would hand app state to a post that never asked.
        let json = """
        {"type":"com.spiral.app.action","event_id":"$a","sender":"@a:s.md","origin_server_ts":1,
         "content":{"m.relates_to":{"rel_type":"m.thread","event_id":"$post"}}}
        """
        #expect(SpiralAppActionFeed.postEventID(ofRawEventJSON: json) == nil)
    }

    @Test
    func anEventOfAnotherTypeNamesNoPost() {
        let json = """
        {"type":"m.room.message","event_id":"$a","sender":"@a:s.md","origin_server_ts":1,
         "content":{"m.relates_to":{"rel_type":"m.reference","event_id":"$post"}}}
        """
        #expect(SpiralAppActionFeed.postEventID(ofRawEventJSON: json) == nil)
    }

    // MARK: - Helpers

    private static func room() -> JoinedRoomProxyMock {
        let room = JoinedRoomProxyMock(.init(id: "!room:spiral.md"))
        room.loadSpiralAppRelationsForReturnValue = .success([])
        room.subscribeToSpiralEventsTypesListenerReturnValue = .failure(.sdkError(FeedTestError.noHandle))
        return room
    }

    /// Hand a batch to whatever listener the feed registered with the room.
    ///
    /// `SDKListener.onMainActor` delivers through an `AsyncStream` consumed by a
    /// task, so the caller has to give that task its turn before looking.
    private static func deliver(_ events: [SpiralObservedEvent], to room: JoinedRoomProxyMock) async {
        guard let listener = room.subscribeToSpiralEventsTypesListenerReceivedArguments?.listener else {
            Issue.record("the feed never subscribed")
            return
        }
        listener.onEvents(events: events)
        try? await Task.sleep(for: .milliseconds(50))
    }

    private static func action(on postEventID: String, seq: Int) -> SpiralObservedEvent {
        SpiralObservedEvent(eventId: "$action-\(postEventID)-\(seq)",
                            eventType: SpiralAppAction.eventType,
                            eventJson: actionJSON(on: postEventID, seq: seq),
                            timestamp: 1,
                            origin: .sync,
                            isUtd: false)
    }

    private static func actionJSON(on postEventID: String, seq: Int) -> String {
        """
        {"type":"com.spiral.app.action","event_id":"$action\(seq)","sender":"@a:spiral.md",
         "origin_server_ts":1,
         "content":{"m.relates_to":{"rel_type":"m.reference","event_id":"\(postEventID)"},
                    "seq":\(seq),"state":{"count":\(seq)}}}
        """
    }

    private enum FeedTestError: Error {
        case noHandle
    }
}
