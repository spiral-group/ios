//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359 item 16): what a row reads from the timeline's state, as a value of its own.
//

import SwiftUI

/// All that a row takes from the timeline's state. Each row holds its own, so it re-renders when this changes for that row,
/// and a typing notice, a read receipt or a pin elsewhere reach no row at all. A row that read the view state directly re-rendered
/// on every change to it.
struct TimelineRowContext: Equatable {
    var timelineKind = TimelineKind.live
    var isDM = false
    var areThreadsEnabled = true
    /// Whether a draft in this thread updates a published post.
    var updatesLivePost = false
    /// The room a draft in this thread publishes to, when it isn't this one.
    var publishRoomName: String?
    
    var isSelecting = false
    var selectedCount = 0
    var isSelected = false
    
    var isPinned = false
    /// Whether an own message shows two ticks.
    var isRead = false
    var areReactionsCollapsed = true
    var isLiveLocationStopped = false
    /// AGENT-PLATFORM (decision 371): kept out of the row, which a table reuses and scrolls away.
    var isCallSummaryExpanded = false
    /// AGENT-PLATFORM (1.0.3 A3): what the assistant's welcome offers under its hello.
    var spiralWelcomeExtras = SpiralWelcomeExtras.none
}

extension TimelineRowContext {
    /// What's drawn beside an own message's time. A failed send has its mark instead, a pinned message neither.
    func deliveryStatus(of timelineItem: EventBasedTimelineItemProtocol,
                        adjustedDeliveryStatus: TimelineItemDeliveryStatus?) -> TimelineDeliveryStatusView.Status? {
        guard timelineItem.isOutgoing, timelineKind != .pinned else { return nil }
        
        switch adjustedDeliveryStatus {
        case .sending:
            return .sending
        case .sendingFailed:
            return nil
        case .sent, .none:
            return isRead ? .read : .sent
        }
    }
}

extension EnvironmentValues {
    /// This row's context, set by `RoomTimelineItemView`.
    @Entry var timelineRowContext = TimelineRowContext()
}

/// What a quote's preview watches, as its mentions show the names of the room's members. Observable by itself, so that a change
/// of the members redraws the quotes and leaves the rows around them alone.
@Observable
final class TimelineMembersRevision {
    var value = 0
}

/// The parts of the timeline's state the rows' contexts are made from. Comparing these is what keeps a change to the rest of the
/// state away from the rows, and it's cheap: nearly every update leaves these sets sharing their storage.
struct TimelineRowContextInputs: Equatable {
    let timelineKind: TimelineKind
    let isDM: Bool
    let areThreadsEnabled: Bool
    let updatesLivePost: Bool
    let publishRoomName: String?
    let messageSelection: TimelineMessageSelectionState
    let pinnedEventIDs: Set<String>
    let readOwnItemIDs: Set<TimelineItemIdentifier.UniqueID>
    let showReadReceipts: Bool
    let reactionsCollapsed: [TimelineItemIdentifier: Bool]
    let stoppedLiveLocationIDs: Set<TimelineItemIdentifier>
    let expandedCallSummaries: Set<TimelineItemIdentifier>
    let spiralWelcomeExtras: SpiralWelcomeExtras // AGENT-PLATFORM (1.0.3 A3)
    
    init(_ viewState: TimelineViewState) {
        timelineKind = viewState.timelineKind
        isDM = viewState.isDM
        areThreadsEnabled = viewState.areThreadsEnabled
        updatesLivePost = viewState.spiralUpdatableLivePost != nil
        publishRoomName = viewState.spiralPublishRoom?.name
        messageSelection = viewState.messageSelection
        pinnedEventIDs = viewState.pinnedEventIDs
        readOwnItemIDs = viewState.timelineState.readOwnItemIDs
        showReadReceipts = viewState.showReadReceipts
        reactionsCollapsed = viewState.bindings.reactionsCollapsed
        stoppedLiveLocationIDs = viewState.stoppedLiveLocationIDs
        expandedCallSummaries = viewState.bindings.expandedCallSummaries
        spiralWelcomeExtras = viewState.spiralWelcomeExtras
    }
    
    func rowContext(for itemID: TimelineItemIdentifier) -> TimelineRowContext {
        TimelineRowContext(timelineKind: timelineKind,
                           isDM: isDM,
                           areThreadsEnabled: areThreadsEnabled,
                           updatesLivePost: updatesLivePost,
                           publishRoomName: publishRoomName,
                           isSelecting: messageSelection.isActive,
                           selectedCount: messageSelection.count,
                           isSelected: messageSelection.contains(itemID.eventID),
                           isPinned: timelineKind != .pinned && itemID.eventID.map(pinnedEventIDs.contains) == true,
                           isRead: showReadReceipts && readOwnItemIDs.contains(itemID.uniqueID),
                           areReactionsCollapsed: reactionsCollapsed[itemID] ?? true,
                           isLiveLocationStopped: stoppedLiveLocationIDs.contains(itemID),
                           isCallSummaryExpanded: expandedCallSummaries.contains(itemID),
                           spiralWelcomeExtras: spiralWelcomeExtras)
    }
}
