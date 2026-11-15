//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: the «New» divider needs something new under it. The SDK
// places its read marker before the first event from someone else after the
// fully-read one, but the app renders no row for some of those events —
// `m.call.member` above all, sent by every call. After a call the divider
// stood alone at the bottom of the chat.
//

import Foundation
import MatrixRustSDK
@testable import Spiral
import Testing

@MainActor
struct TimelineControllerReadMarkerTests {
    private static let ownUserID = "@alice:matrix.org"
    private static let peerID = "@bob:matrix.org"
    private static let ownAgentID = "@assistant-alice:matrix.org"
    private static let foreignAgentID = "@assistant-alice:evil.example"

    @Test
    func aMarkerFollowedOnlyByHiddenCallMembershipsIsNotShown() async throws {
        let items = try await buildItems([.text("hello before the call", sender: Self.peerID),
                                          .ownText("calling you"),
                                          .readMarker,
                                          .callMember(sender: Self.peerID),
                                          .callMember(sender: Self.ownUserID),
                                          .callMember(sender: Self.peerID)])

        #expect(!items.contains { $0 is ReadMarkerRoomTimelineItem })
        #expect(items.count == 2)
    }

    @Test
    func aMarkerFollowedOnlyByOwnRowsIsNotShown() async throws {
        let items = try await buildItems([.text("hello", sender: Self.peerID),
                                          .readMarker,
                                          .callMember(sender: Self.peerID),
                                          .ownText("my reply")])

        #expect(!items.contains { $0 is ReadMarkerRoomTimelineItem })
    }

    @Test
    func aMarkerWithANewMessageAfterTheHiddenRowsStays() async throws {
        let items = try await buildItems([.text("hello", sender: Self.peerID),
                                          .readMarker,
                                          .callMember(sender: Self.peerID),
                                          .text("are you there?", sender: Self.peerID)])

        #expect(items.count == 3)
        #expect(items[1] is ReadMarkerRoomTimelineItem)
    }

    @Test
    func aMarkerAtTheEndIsNotShown() async throws {
        let items = try await buildItems([.text("hello", sender: Self.peerID), .readMarker])

        #expect(items.count == 1)
        #expect(items.first is TextRoomTimelineItem)
    }

    @Test
    func aMarkerFollowedOnlyByTheAgentsEchoOfYourChangeIsNotShown() async throws {
        let items = try await buildItems([.text("hello", sender: Self.peerID),
                                          .readMarker,
                                          .toolChange(sender: Self.ownAgentID, stateKey: Self.ownAgentID, by: Self.ownUserID)])

        #expect(!items.contains { $0 is ReadMarkerRoomTimelineItem })
        #expect(items.count == 2, "the row itself stays")
    }

    @Test
    func aMarkerFollowedOnlyByTheFallbackEchoIsNotShown() async throws {
        let items = try await buildItems([.text("hello", sender: Self.peerID),
                                          .readMarker,
                                          .toolChangeFallback(sender: Self.ownAgentID, by: Self.ownUserID)])

        #expect(!items.contains { $0 is ReadMarkerRoomTimelineItem })
        #expect(items.count == 2, "the row itself stays")
    }

    @Test
    func aMessageAfterTheEchoKeepsTheMarker() async throws {
        let items = try await buildItems([.text("hello", sender: Self.peerID),
                                          .readMarker,
                                          .toolChange(sender: Self.ownAgentID, stateKey: Self.ownAgentID, by: Self.ownUserID),
                                          .text("are you there?", sender: Self.peerID)])

        #expect(items[1] is ReadMarkerRoomTimelineItem)
    }

    @Test
    func aForgedOwnerKeepsTheMarker() async throws {
        let forgeries: [TimelineItemProxy] = [.toolChange(sender: Self.peerID, stateKey: Self.peerID, by: Self.ownUserID),
                                              .toolChange(sender: Self.peerID, stateKey: Self.ownAgentID, by: Self.ownUserID),
                                              .toolChange(sender: Self.foreignAgentID, stateKey: Self.foreignAgentID, by: Self.ownUserID),
                                              .toolChangeFallback(sender: Self.ownAgentID, by: Self.peerID)]
        for forgery in forgeries {
            let items = try await buildItems([.text("hello", sender: Self.peerID), .readMarker, forgery])
            #expect(items[1] is ReadMarkerRoomTimelineItem)
        }
    }

    @Test
    func aChangeTheSystemMadeKeepsTheMarker() async throws {
        for change in [TimelineItemProxy.toolChange(sender: Self.ownAgentID, stateKey: Self.ownAgentID, by: Self.ownUserID, actor: "system"),
                       .toolChangeFallback(sender: Self.ownAgentID, by: Self.ownUserID, actor: "system")] {
            let items = try await buildItems([.text("hello", sender: Self.peerID), .readMarker, change])
            #expect(items[1] is ReadMarkerRoomTimelineItem)
        }
    }

    @Test
    func aSnapshotRowKeepsTheMarker() async throws {
        // It doesn't say who acted, so it doesn't read "You" either.
        let items = try await buildItems([.text("hello", sender: Self.peerID),
                                          .readMarker,
                                          .toolChange(sender: Self.ownAgentID, stateKey: Self.ownAgentID, by: Self.ownUserID, actor: nil)])

        #expect(items[1] is ReadMarkerRoomTimelineItem)
    }

    // MARK: - Helpers

    private func buildItems(_ proxies: [TimelineItemProxy]) async throws -> [RoomTimelineItemProtocol] {
        let provider = SignallingTimelineItemProviderMock(itemProxies: proxies)
        let roomProxy = JoinedRoomProxyMock(.init(name: "Bob", isDirect: true))
        let controller = TimelineController(roomProxy: roomProxy,
                                            timelineProxy: TimelineProxyMock(.init(timelineItemProvider: provider)),
                                            initialFocussedEventID: nil,
                                            timelineItemFactory: RoomTimelineItemFactory(userID: Self.ownUserID,
                                                                                         attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                                                                         stateEventStringBuilder: RoomStateEventStringBuilder(userID: Self.ownUserID)),
                                            mediaProvider: MediaProviderMock(.init()),
                                            userSettings: .mock())

        let deferred = deferFulfillment(controller.callbacks) { callback in
            if case .updatedTimelineItems = callback { true } else { false }
        }
        try await deferred.fulfill()

        return controller.timelineItems
    }
}

private extension TimelineItemProxy {
    static var readMarker: TimelineItemProxy {
        .virtual(.readMarker, uniqueID: .init(UUID().uuidString))
    }

    static func text(_ body: String, sender: String) -> TimelineItemProxy {
        event(sender: sender, isOwn: false, content: textContent(body))
    }

    static func ownText(_ body: String) -> TimelineItemProxy {
        event(sender: "@alice:matrix.org", isOwn: true, content: textContent(body))
    }

    static func callMember(sender: String) -> TimelineItemProxy {
        event(sender: sender,
              isOwn: sender == "@alice:matrix.org",
              content: .state(stateKey: "_\(sender)_DEVICE_m.call", content: .custom(eventType: "org.matrix.msc3401.call.member")))
    }

    static func toolChange(sender: String, stateKey: String, by: String, actor: String? = "owner") -> TimelineItemProxy {
        let json = """
        {"type":"com.spiral.tools","state_key":"\(stateKey)","sender":"\(sender)",
         "content":{"by":"\(by)","at":1000,"tools":[{"tool":"summarize","enabled":true}]\(changes(actor: actor))}}
        """
        let content = TimelineItemContent.state(stateKey: stateKey, content: .custom(eventType: "com.spiral.tools"))
        return .event(EventTimelineItemProxy(item: EventTimelineItem(configuration: .init(sender: sender, originalJSON: json, content: content)),
                                             uniqueID: .init(UUID().uuidString)))
    }

    static func toolChangeFallback(sender: String, by: String, actor: String = "owner") -> TimelineItemProxy {
        let json = """
        {"type":"com.spiral.tools.changed","sender":"\(sender)",
         "content":{"by":"\(by)","at":1000,"tools":[{"tool":"summarize","enabled":true}],"fallback":true\(changes(actor: actor))}}
        """
        return .event(EventTimelineItemProxy(item: .mockOtherMessageLike(sender: sender, originalJSON: json), uniqueID: .init(UUID().uuidString)))
    }

    private static func changes(actor: String?) -> String {
        actor.map { #","changes":[{"action":"armed","tool":"summarize","actor":"\#($0)"}]"# } ?? ""
    }

    private static func event(sender: String, isOwn: Bool, content: TimelineItemContent) -> TimelineItemProxy {
        .event(EventTimelineItemProxy(item: EventTimelineItem(configuration: .init(sender: sender, isOwn: isOwn, content: content)),
                                      uniqueID: .init(UUID().uuidString)))
    }

    private static func textContent(_ body: String) -> TimelineItemContent {
        .msgLike(content: .init(kind: .message(content: .init(msgType: .text(content: .init(body: body, formatted: nil)),
                                                              body: body,
                                                              isEdited: false,
                                                              mentions: nil)),
                                inReplyTo: nil,
                                threadRoot: nil,
                                threadSummary: nil))
    }
}
