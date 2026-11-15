//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066): what the message menu offers, for the kinds of
// item that are not `EventBasedMessageTimelineItemProtocol`.
//
// That protocol is the one most of the provider is written against, and an
// Interactive Post is not one — it is an event-based item that is not a
// "message item" in the type sense. Every `as?` to it is therefore a place
// where a post can quietly get different behaviour from a text bubble, which
// is exactly what happened to replies.
//

@testable import Spiral
import Testing

@MainActor
struct InteractivePostMenuActionProviderTests {
    /// A reply to something in a thread belongs in that thread.
    ///
    /// The provider read `isThreaded` through a cast that a post fails, so a
    /// reply to a post inside a thread was posted to the room instead — a
    /// message answering something nobody else could see it answering.
    ///
    /// The property is on the BASE protocol, so the cast never bought anything;
    /// removing it is what fixes this, and this test is what stops it coming
    /// back as a "tidy-up".
    @Test
    func replyingToAThreadedPostStaysInItsThread() throws {
        let actions = try #require(Self.provider(for: Self.post(isThreaded: true)).makeActions())

        #expect(actions.actions.contains(.reply(isThread: true)),
                "a post in a thread offered a reply that would leave it")
    }

    @Test
    func replyingToAPostOutsideAThreadIsAnOrdinaryReply() throws {
        let actions = try #require(Self.provider(for: Self.post(isThreaded: false)).makeActions())

        #expect(actions.actions.contains(.reply(isThread: false)))
    }

    /// The same question asked of a text bubble, so the two cannot drift.
    @Test
    func aThreadedTextMessageBehavesIdentically() throws {
        var item = TextRoomTimelineItem(id: .randomEvent,
                                        timestamp: .mock,
                                        isOutgoing: false,
                                        isEditable: false,
                                        canBeRepliedTo: true,
                                        sender: .init(id: "@a:spiral.md"),
                                        content: .init(body: "hello"))
        item.properties.isThreaded = true

        let actions = try #require(Self.provider(for: item).makeActions())

        #expect(actions.actions.contains(.reply(isThread: true)))
    }

    // MARK: - Helpers

    private static func post(isThreaded: Bool) -> InteractivePostRoomTimelineItem {
        var item = InteractivePostRoomTimelineItem(id: .randomEvent,
                                                   body: "a counter",
                                                   timestamp: .mock,
                                                   isOutgoing: false,
                                                   isEditable: false,
                                                   canBeRepliedTo: true,
                                                   sender: .init(id: "@a:spiral.md"),
                                                   post: SpiralAppPost(.init(body: "a counter",
                                                                             appId: "counter",
                                                                             runtime: "1",
                                                                             title: "a counter",
                                                                             aspect: "4:3",
                                                                             stateChannel: "matrix",
                                                                             sha256: String(repeating: "a", count: 64),
                                                                             url: "mxc://spiral.md/abc",
                                                                             fileJson: nil)))
        item.properties.isThreaded = isThreaded
        return item
    }

    /// Threads OFF, because that is when the reply action carries the thread
    /// itself. With them on there is a separate `replyInThread` and this
    /// question does not arise.
    private static func provider(for item: RoomTimelineItemProtocol) -> TimelineItemMenuActionProvider {
        TimelineItemMenuActionProvider(timelineItem: item,
                                       canCurrentUserSendMessage: true,
                                       canCurrentUserRedactSelf: false,
                                       canCurrentUserRedactOthers: false,
                                       canCurrentUserPin: false,
                                       pinnedEventIDs: [],
                                       isViewSourceEnabled: false,
                                       areThreadsEnabled: false,
                                       timelineKind: .live,
                                       emojiProvider: EmojiProvider(userSettings: .mock()))
    }
}
