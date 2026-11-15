//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import UIKit

nonisolated struct StateRoomTimelineItem: EventBasedTimelineItemProtocol, Equatable {
    let id: TimelineItemIdentifier
    let body: String
    let timestamp: Date
    let isOutgoing: Bool
    let isEditable: Bool
    let canBeRepliedTo: Bool
    
    let sender: TimelineItemSender
    
    /// AGENT-PLATFORM: a row for a `com.spiral.tools` state event, which a fold names.
    var isAgentToolChange = false
    /// AGENT-PLATFORM: the agent's echo of this user's own tool change, which isn't new to them.
    var isAgentToolChangeByYou = false
    
    var properties = RoomTimelineItemProperties()
}
