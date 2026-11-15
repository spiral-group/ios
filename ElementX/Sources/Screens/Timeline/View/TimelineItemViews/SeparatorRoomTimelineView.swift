//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

struct SeparatorRoomTimelineView: View {
    let timelineItem: SeparatorRoomTimelineItem
    
    var body: some View {
        Text(timelineItem.timestamp.formattedDateSeparator())
            .font(.compound.bodyXSSemibold) // AGENT-PLATFORM (Brief 0083): Messages' small day line
            .foregroundColor(.compound.textSecondary) // AGENT-PLATFORM (Brief 0083): quieter, as the reviewer-path storyboard draws it
            .chatBackgroundChip() // AGENT-PLATFORM (Brief 0083, question 357)
            // AGENT-PLATFORM (Brief 0083, end stage): the element is the chip, not the row's paddings around it: the
            // audit measured the day's text against the picture under those paddings.
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 36.0)
            .padding(.top, 16) // AGENT-PLATFORM (Brief 0083): a day starts with more room above than below
            .padding(.bottom, 4)
    }
}

struct SeparatorRoomTimelineView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        let item = SeparatorRoomTimelineItem(id: .virtual(uniqueID: .init("Separator")),
                                             timestamp: .mock)
        SeparatorRoomTimelineView(timelineItem: item)
    }
}
