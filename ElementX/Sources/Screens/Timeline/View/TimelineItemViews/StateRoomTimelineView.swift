//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

struct StateRoomTimelineView: View {
    let timelineItem: StateRoomTimelineItem
    
    var body: some View {
        Text(timelineItem.body)
            .font(.compound.bodyXS) // AGENT-PLATFORM (Brief 0083): the day line's size, as Messages' room changes
            .multilineTextAlignment(.center)
            .foregroundColor(.compound.textSecondary)
            .chatBackgroundChip() // AGENT-PLATFORM (Brief 0083, question 357)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 36.0)
            .padding(.vertical, 8.0)
    }
}

struct StateRoomTimelineView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        body
    }
    
    static var body: some View {
        VStack(spacing: 0) {
            StateRoomTimelineView(timelineItem: item)
            StateRoomTimelineView(timelineItem: toolChangesItem)
            StateRoomTimelineView(timelineItem: systemToolChangeItem)
        }
    }
    
    static let item = StateRoomTimelineItem(id: .randomVirtual,
                                            body: "Alice joined",
                                            timestamp: .mock,
                                            isOutgoing: false,
                                            isEditable: false,
                                            canBeRepliedTo: true,
                                            sender: .init(id: ""))
    
    // AGENT-PLATFORM (question 357): each action of a tool change on its own line.
    static let toolChangesItem = StateRoomTimelineItem(id: .randomVirtual,
                                                       body: "You turned on Record calls\nYou turned off Translate → Ukrainian",
                                                       timestamp: .mock,
                                                       isOutgoing: false,
                                                       isEditable: false,
                                                       canBeRepliedTo: false,
                                                       sender: .init(id: ""),
                                                       isAgentToolChange: true)
    
    static let systemToolChangeItem = StateRoomTimelineItem(id: .randomVirtual,
                                                            body: "Record calls was turned off for Stage A · assistant",
                                                            timestamp: .mock,
                                                            isOutgoing: false,
                                                            isEditable: false,
                                                            canBeRepliedTo: false,
                                                            sender: .init(id: ""),
                                                            isAgentToolChange: true)
}
