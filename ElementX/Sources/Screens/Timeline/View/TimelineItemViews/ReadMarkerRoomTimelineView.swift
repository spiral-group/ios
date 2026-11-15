//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct ReadMarkerRoomTimelineView: View {
    var body: some View {
        // AGENT-PLATFORM (Brief 0083, the room's timeline): the label between two rules, centred and in sentence
        // case, as the day line is. Element drew it in capitals at the trailing end, over one rule.
        HStack(spacing: 8) {
            rule
            
            Text(L10n.screenRoomTimelineReadMarkerTitle)
                .font(.compound.bodyXSSemibold)
                .foregroundColor(.compound.textLinkExternal) // AGENT-PLATFORM (Brief 0083, question 357): textActionAccent reads 4.65:1 on the dark surface, which the audit fails
                .chatBackgroundChip() // AGENT-PLATFORM (Brief 0083, question 357)
            
            rule
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    private var rule: some View {
        Rectangle()
            .frame(height: 0.5)
            .foregroundColor(.compound.borderAccentPrimary)
    }
}

struct ReadMarkerRoomTimelineView_Previews: PreviewProvider, TestablePreview {
    static let viewModel = TimelineViewModel.mock
    
    static var previews: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoomTimelineItemView(viewState: .init(type: .separator(.init(id: .virtual(uniqueID: .init("Separator")), timestamp: .mock)), groupStyle: .single))
            RoomTimelineItemView(viewState: .init(type: .text(.init(id: .randomEvent,
                                                                    timestamp: .mock,
                                                                    isOutgoing: true,
                                                                    isEditable: false,
                                                                    canBeRepliedTo: true,
                                                                    sender: .init(id: "1", displayName: "Bob"),
                                                                    content: .init(body: "This is another message"))), groupStyle: .single))
            
            ReadMarkerRoomTimelineView()
            
            RoomTimelineItemView(viewState: .init(type: .separator(.init(id: .virtual(uniqueID: .init("Separator")), timestamp: .mock)), groupStyle: .single))
            RoomTimelineItemView(viewState: .init(type: .text(.init(id: .randomEvent,
                                                                    timestamp: .mock,
                                                                    isOutgoing: false,
                                                                    isEditable: false,
                                                                    canBeRepliedTo: true,
                                                                    sender: .init(id: "", displayName: "Alice"),
                                                                    content: .init(body: "This is a message"))), groupStyle: .single))
        }
        .environmentObject(viewModel.context)
    }
}
