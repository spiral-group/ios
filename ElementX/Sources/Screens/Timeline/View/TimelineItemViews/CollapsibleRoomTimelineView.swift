//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct CollapsibleRoomTimelineView: View {
    enum AccessibilityFocus {
        case disclosure
        case events
    }
    
    // AGENT-PLATFORM (Brief 0083, question 359): the table animates a row's height on a clock of its own, which a SwiftUI animation
    // of the same height can't follow, and the difference spills over the rows beside it. So only the table moves anything here, and
    // the group's rows are never seen while it does: they fade in once the row has opened, and out before it closes.
    private enum Timing {
        /// How long the table takes to all but open a row: 98 % of the way by here on iOS 27.
        static let rowOpening = 0.3
        static let fadeIn = 0.2
        static let fadeOut = 0.12
    }
    
    private let timelineItem: CollapsibleTimelineItem
    private let groupedViewStates: [RoomTimelineItemViewState]
    
    /// What was last asked for, which the chevron shows at once.
    @State private var isExpanded = false
    /// Whether the rows take up room in the row. Closing, they stay until they've faded.
    @State private var hasRows = false
    @State private var rowsOpacity = 0.0
    @State private var rowsAnimation: Animation?
    @State private var closing: Task<Void, Never>?
    @AccessibilityFocusState private var accessibilityFocusState: AccessibilityFocus?
    
    init(timelineItem: CollapsibleTimelineItem) {
        self.timelineItem = timelineItem
        groupedViewStates = timelineItem.items.map { .init(item: $0, groupStyle: .single) }
    }
    
    // AGENT-PLATFORM: a run of tool changes says so; a mixed run stays generic.
    private var title: String {
        timelineItem.isOnlyAgentToolChanges
            ? UntranslatedL10n.screenRoomTimelineToolChanges(timelineItem.items.count)
            : L10n.screenRoomTimelineStateChanges(timelineItem.items.count)
    }
    
    var body: some View {
        VStack(spacing: 0.0) {
            Button(action: toggle) {
                HStack(alignment: .center, spacing: 4) {
                    Text(title)
                        .font(.compound.bodySM)
                    CompoundIcon(\.chevronRight, size: .small, relativeTo: .compound.bodySM)
                        .accessibilityLabel(isExpanded ? L10n.screenRoomGroupedStateEventsReduce : L10n.screenRoomGroupedStateEventsExpand)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.elementDefault, value: isExpanded)
                }
                .foregroundColor(.compound.textSecondary)
                .chatBackgroundChip() // AGENT-PLATFORM (Brief 0083, question 357)
                .padding(.horizontal, 36.0)
                .padding(.vertical, 12.0)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.top, 8.0)
            .accessibilityFocused($accessibilityFocusState, equals: .disclosure)
            
            // Outside the `if`, so that rows arriving at 0 have an opacity to animate from.
            VStack(spacing: 0.0) {
                if hasRows {
                    VStack(spacing: 0.0) {
                        ForEach(groupedViewStates) { viewState in
                            RoomTimelineItemView(viewState: viewState)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityFocused($accessibilityFocusState, equals: .events)
                }
            }
            .animation(rowsAnimation) { $0.opacity(rowsOpacity) }
        }
        .onChange(of: isExpanded) { _, newValue in
            accessibilityFocusState = newValue ? .events : .disclosure
        }
    }
    
    private func toggle() {
        isExpanded.toggle()
        closing?.cancel()
        
        if UIAccessibility.isVoiceOverRunning || UIAccessibility.isReduceMotionEnabled {
            rowsAnimation = nil
            hasRows = isExpanded
            rowsOpacity = isExpanded ? 1 : 0
        } else if isExpanded {
            // Pressed again while fading out, the row hasn't closed and there's nothing to wait for.
            rowsAnimation = Animation.easeOut(duration: Timing.fadeIn).delay(hasRows ? 0 : Timing.rowOpening).disabledDuringTests()
            hasRows = true
            rowsOpacity = 1
        } else {
            rowsAnimation = Animation.easeIn(duration: Timing.fadeOut).disabledDuringTests()
            rowsOpacity = 0
            closing = Task {
                try? await Task.sleep(for: .seconds(Timing.fadeOut))
                guard !Task.isCancelled else { return }
                hasRows = false
            }
        }
    }
}

struct CollapsibleRoomTimelineView_Previews: PreviewProvider, TestablePreview {
    static let item = CollapsibleTimelineItem(items: [
        SeparatorRoomTimelineItem(id: .virtual(uniqueID: .init("First separator")), timestamp: .mock),
        SeparatorRoomTimelineItem(id: .virtual(uniqueID: .init("Second separator")), timestamp: .mock)
    ])
    
    // AGENT-PLATFORM (question 357): a run of tool changes names itself.
    static let toolChangesItem = CollapsibleTimelineItem(items: (0..<3).map { index in
        StateRoomTimelineItem(id: .virtual(uniqueID: .init("Tool change \(index)")),
                              body: "You turned on Record calls",
                              timestamp: .mock,
                              isOutgoing: false,
                              isEditable: false,
                              canBeRepliedTo: false,
                              sender: .init(id: ""),
                              isAgentToolChange: true)
    })
    
    static var previews: some View {
        VStack(spacing: 0) {
            CollapsibleRoomTimelineView(timelineItem: item)
            CollapsibleRoomTimelineView(timelineItem: toolChangesItem)
        }
    }
}
