//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: client-rendered notices (Brief 0073).
//
// A notice is an event, not a line the assistant said: it draws as a card
// of its own, the way an ended call does — no bubble, no sender, the
// whole tile is the tap target.
//

import Foundation

nonisolated struct SpiralNoticeRoomTimelineItem: RoomTimelineItemProtocol, Equatable {
    let id: TimelineItemIdentifier
    let timestamp: Date
    let sender: TimelineItemSender
    let notice: SpiralNotice
}
