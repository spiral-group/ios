//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007): an Interactive Post as a timeline
// row.
//
// Deliberately carries only what the event said. The artifact's bytes, the
// running app and its shared state all live elsewhere — the row is recycled
// whenever it leaves the screen, and anything expensive kept here would be
// built and thrown away with it.
//

import Foundation

nonisolated struct InteractivePostRoomTimelineItem: EventBasedTimelineItemProtocol, Equatable {
    let id: TimelineItemIdentifier
    /// What a client shows when it cannot run the app: the post's title, or
    /// the newest action's `summary.line` once there is one.
    let body: String
    let timestamp: Date
    let isOutgoing: Bool
    let isEditable: Bool
    let canBeRepliedTo: Bool

    let sender: TimelineItemSender

    /// Where the artifact is and what shape it is, from the event itself.
    let post: SpiralAppPost

    var properties = RoomTimelineItemProperties()
}
