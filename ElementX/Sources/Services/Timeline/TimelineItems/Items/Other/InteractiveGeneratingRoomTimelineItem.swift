//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0066, § 5.71): the agent's «Створюю чернетку v2…»
// marker — sent into the thread the moment it asks the model for a draft,
// half a minute or more before the draft lands.
//
// Drawn as a card the size the draft will be, where the draft will be; gone
// once anything from the same sender follows it in the thread (the draft, or
// the sentence that it failed). Nothing here is parsed: `body` is the line
// the agent wrote, in the thread's language.
//

import Foundation

nonisolated struct InteractiveGeneratingRoomTimelineItem: EventBasedTimelineItemProtocol, Equatable {
    /// The msgtype the agent sends; anything else with `.other` stays hidden.
    static let msgtype = "com.spiral.app.generating"

    /// A marker older than this with nothing after it: the orchestrator
    /// died mid-generation, and the card says so instead of shimmering on.
    static let staleAfter: TimeInterval = 5 * 60

    let id: TimelineItemIdentifier
    let body: String
    let timestamp: Date
    let isOutgoing: Bool
    let isEditable: Bool
    let canBeRepliedTo: Bool

    let sender: TimelineItemSender

    var properties = RoomTimelineItemProperties()

    /// The items without every marker that something from its own sender
    /// has followed. The thread is a list; the draft that ends a generation
    /// is an item of its own, so the marker is superseded by position, not
    /// by an edit — the agent's history reads `m.thread` relations and an
    /// `m.replace` would be invisible to it.
    static func droppingSuperseded(_ items: [RoomTimelineItemProtocol]) -> [RoomTimelineItemProtocol] {
        var result = [RoomTimelineItemProtocol]()
        result.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            if let marker = item as? InteractiveGeneratingRoomTimelineItem,
               items[(index + 1)...].contains(where: { ($0 as? EventBasedTimelineItemProtocol)?.sender.id == marker.sender.id }) {
                continue
            }
            result.append(item)
        }
        return result
    }
}
