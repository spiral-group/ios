//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import Spiral
import Testing

struct TimelineItemMenuActionProviderTests {
    @Test
    func seenByIsOfferedOnceSomeoneHasRead() throws {
        let item = makeLiveLocationItem(isLive: false)
        
        let read = try #require(makeActions(for: item, hasReaders: true))
        let unread = try #require(makeActions(for: item, hasReaders: false))
        
        #expect(read.actions.contains(.seenBy))
        #expect(!unread.actions.contains(.seenBy))
    }
    
    @Test
    func liveLocationShareIsNotForwardable() throws {
        let item = makeLiveLocationItem(isLive: true)
        let actions = try #require(makeActions(for: item))
        
        let hasForward = actions.actions.contains(where: \.isForward)
        #expect(!hasForward)
    }
    
    @Test
    func endedLiveLocationShareIsNotForwardable() throws {
        let item = makeLiveLocationItem(isLive: false)
        let actions = try #require(makeActions(for: item))
        
        let hasForward = actions.actions.contains(where: \.isForward)
        #expect(!hasForward)
    }
    
    @Test
    func pollIsNotForwardable() throws {
        let item = PollRoomTimelineItem.mock(poll: .emptyDisclosed)
        let actions = try #require(makeActions(for: item))
        
        let hasForward = actions.actions.contains(where: \.isForward)
        #expect(!hasForward)
    }
    
    @Test
    func textMessageIsForwardable() throws {
        let item = TextRoomTimelineItem(id: .randomEvent,
                                        timestamp: .mock,
                                        isOutgoing: false,
                                        isEditable: false,
                                        canBeRepliedTo: true,
                                        sender: .init(id: "@alice:matrix.org"),
                                        content: .init(body: "Hello"))
        let actions = try #require(makeActions(for: item))
        
        let hasForward = actions.actions.contains(where: \.isForward)
        #expect(hasForward)
    }
    
    @Test
    func redactedMessageIsNotForwardable() throws {
        let item = RedactedRoomTimelineItem(id: .randomEvent,
                                            body: "Message removed",
                                            timestamp: .mock,
                                            isOutgoing: false,
                                            isEditable: false,
                                            canBeRepliedTo: false,
                                            sender: .init(id: "@alice:matrix.org"))
        let actions = try #require(makeActions(for: item))
        
        let hasForward = actions.actions.contains(where: \.isForward)
        #expect(!hasForward)
    }
    
    @Test
    func encryptedMessageIsNotForwardable() throws {
        let item = EncryptedRoomTimelineItem(id: .randomEvent,
                                             body: "",
                                             encryptionType: .unknown,
                                             timestamp: .mock,
                                             isOutgoing: false,
                                             isEditable: false,
                                             canBeRepliedTo: false,
                                             sender: .init(id: "@alice:matrix.org"))
        let actions = try #require(makeActions(for: item))
        
        let hasForward = actions.actions.contains(where: \.isForward)
        #expect(!hasForward)
    }
    
    @Test
    func localEchoIsNotForwardable() throws {
        let item = makeTextItem(id: .event(uniqueID: .init("local"), eventOrTransactionID: .transactionID("txn")))
        let actions = try #require(makeActions(for: item))
        
        let hasForward = actions.actions.contains(where: \.isForward)
        #expect(!hasForward)
    }
    
    // MARK: - Interactive Posts
    
    // AGENT-PLATFORM (Brief 0066): an Interactive Post is event-based but not an
    // `EventBasedMessageTimelineItemProtocol`, so every `as?` to that protocol is a
    // place where a post can quietly behave unlike a text bubble — as replies did.
    
    /// A reply to something in a thread belongs in that thread.
    ///
    /// The provider read `isThreaded` through a cast that a post fails, so a
    /// reply to a post inside a thread was posted to the room instead. The
    /// property is on the BASE protocol, so the cast never bought anything;
    /// this test stops it coming back as a "tidy-up".
    @Test
    func replyingToAThreadedPostStaysInItsThread() throws {
        let actions = try #require(makeThreadsOffActions(for: makePost(isThreaded: true)))
        
        #expect(actions.actions.contains(.reply(isThread: true)),
                "a post in a thread offered a reply that would leave it")
    }
    
    @Test
    func replyingToAPostOutsideAThreadIsAnOrdinaryReply() throws {
        let actions = try #require(makeThreadsOffActions(for: makePost(isThreaded: false)))
        
        #expect(actions.actions.contains(.reply(isThread: false)))
    }
    
    /// The same question asked of a text bubble, so the two cannot drift.
    @Test
    func aThreadedTextMessageBehavesIdentically() throws {
        var item = makeTextItem()
        item.properties.isThreaded = true
        
        let actions = try #require(makeThreadsOffActions(for: item))
        
        #expect(actions.actions.contains(.reply(isThread: true)))
    }
    
    // MARK: - Helpers
    
    private func makeTextItem(id: TimelineItemIdentifier = .randomEvent) -> TextRoomTimelineItem {
        .init(id: id,
              timestamp: .mock,
              isOutgoing: false,
              isEditable: false,
              canBeRepliedTo: true,
              sender: .init(id: "@alice:matrix.org"),
              content: .init(body: "Hello"))
    }
    
    private func makeLiveLocationItem(isLive: Bool) -> LiveLocationRoomTimelineItem {
        .init(id: .randomEvent,
              timestamp: .mock,
              isOutgoing: false,
              isEditable: false,
              canBeRepliedTo: true,
              sender: .init(id: "@alice:matrix.org"),
              content: .init(isLive: isLive, timeoutDate: .mock, lastGeoURI: nil))
    }
    
    private func makeActions(for item: RoomTimelineItemProtocol, timelineKind: TimelineKind = .live, hasReaders: Bool = false) -> TimelineItemMenuActions? {
        TimelineItemMenuActionProvider(timelineItem: item,
                                       canCurrentUserSendMessage: true,
                                       canCurrentUserRedactSelf: true,
                                       canCurrentUserRedactOthers: false,
                                       canCurrentUserPin: true,
                                       pinnedEventIDs: [],
                                       isViewSourceEnabled: true,
                                       areThreadsEnabled: true,
                                       timelineKind: timelineKind,
                                       emojiProvider: EmojiProvider(userSettings: .mock()),
                                       hasReaders: hasReaders)
            .makeActions()
    }
    
    // AGENT-PLATFORM (Brief 0066): the Interactive Post fixtures.
    private func makePost(isThreaded: Bool) -> InteractivePostRoomTimelineItem {
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
    private func makeThreadsOffActions(for item: RoomTimelineItemProtocol) -> TimelineItemMenuActions? {
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
            .makeActions()
    }
}

private extension TimelineItemMenuAction {
    var isForward: Bool {
        if case .forward = self {
            return true
        }
        return false
    }
}
