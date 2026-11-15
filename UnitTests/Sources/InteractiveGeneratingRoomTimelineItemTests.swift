//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, § 5.71): the «generating» marker is shown
// until anything from its sender follows it.
//

import Foundation
@testable import Spiral
import Testing

struct InteractiveGeneratingRoomTimelineItemTests {
    private static let agent = "@assistant-x:spiral.md"
    private static let owner = "@emmm:spiral.md"

    private static func marker(_ body: String = "Створюю чернетку v1…") -> InteractiveGeneratingRoomTimelineItem {
        .init(id: .randomEvent, body: body, timestamp: .mock, isOutgoing: false, isEditable: false, canBeRepliedTo: false, sender: .init(id: agent))
    }

    private static func text(_ body: String, from sender: String) -> TextRoomTimelineItem {
        .init(id: .randomEvent, timestamp: .mock, isOutgoing: sender == owner, isEditable: false, canBeRepliedTo: true,
              sender: .init(id: sender), content: .init(body: body))
    }

    @Test
    func aMarkerWithNothingAfterItStays() {
        let items: [RoomTimelineItemProtocol] = [Self.text("Додай капелюх", from: Self.owner), Self.text("Додаю.", from: Self.agent), Self.marker()]
        let kept = InteractiveGeneratingRoomTimelineItem.droppingSuperseded(items)
        #expect(kept.count == 3)
        #expect(kept.last is InteractiveGeneratingRoomTimelineItem)
    }

    @Test
    func theOwnerWritingWhileItGeneratesDoesNotDismissIt() {
        let items: [RoomTimelineItemProtocol] = [Self.marker(), Self.text("і ще шарф", from: Self.owner)]
        let kept = InteractiveGeneratingRoomTimelineItem.droppingSuperseded(items)
        #expect(kept.count == 2)
        #expect(kept.first is InteractiveGeneratingRoomTimelineItem)
    }

    @Test
    func anythingFromTheAgentAfterItDismissesIt() {
        let items: [RoomTimelineItemProtocol] = [Self.marker(), Self.text("Не вдалося зібрати…", from: Self.agent)]
        let kept = InteractiveGeneratingRoomTimelineItem.droppingSuperseded(items)
        #expect(kept.count == 1)
        #expect(kept.first is TextRoomTimelineItem)
    }

    @Test
    func onlyTheNewestOfTwoMarkersStays() {
        let items: [RoomTimelineItemProtocol] = [Self.marker("v1"), Self.text("ok", from: Self.agent), Self.marker("v2")]
        let kept = InteractiveGeneratingRoomTimelineItem.droppingSuperseded(items)
        #expect(kept.count == 2)
        #expect((kept.last as? InteractiveGeneratingRoomTimelineItem)?.body == "v2")
    }
}
