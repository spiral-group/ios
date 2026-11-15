//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 371): a call's summary, drawn as a card. To everything but the row it is the text message it
// reads as, so copying, replying and forwarding take `body`, the whole summary.
//

import Foundation

nonisolated struct CallSummaryRoomTimelineItem: TextBasedRoomTimelineItem, Equatable {
    let id: TimelineItemIdentifier
    let timestamp: Date
    let isOutgoing: Bool
    let isEditable: Bool
    let canBeRepliedTo: Bool
    
    let sender: TimelineItemSender
    
    let content: TextRoomTimelineItemContent
    let summary: SpiralCallSummary
    
    var properties = RoomTimelineItemProperties()
    
    var body: String {
        content.body
    }
    
    var contentType: EventBasedMessageTimelineItemContentType {
        .text(content)
    }
}
