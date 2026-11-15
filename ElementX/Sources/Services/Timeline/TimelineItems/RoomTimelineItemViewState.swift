//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRustSDK

final class RoomTimelineItemViewState: Identifiable, Equatable, ObservableObject {
    @Published var type: RoomTimelineItemType
    @Published var groupStyle: TimelineGroupStyle
    /// AGENT-PLATFORM (Brief 0083, question 359): all the row reads from the timeline's state.
    @Published var rowContext: TimelineRowContext
    
    /// Contains all the identification info of the item, `uniqueID`, `eventID` and `transactionID`
    var identifier: TimelineItemIdentifier {
        type.id
    }
    
    init(type: RoomTimelineItemType, groupStyle: TimelineGroupStyle, rowContext: TimelineRowContext = .init()) {
        self.type = type
        self.groupStyle = groupStyle
        self.rowContext = rowContext
    }
    
    convenience init(item: RoomTimelineItemProtocol, groupStyle: TimelineGroupStyle, rowContext: TimelineRowContext = .init()) {
        self.init(type: .init(item: item), groupStyle: groupStyle, rowContext: rowContext)
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 359): takes the row's newest build, assigning only what changed, as whatever
    /// is assigned re-renders the row, equal or not.
    /// - Returns: Whether anything changed.
    func update(item: RoomTimelineItemProtocol, groupStyle: TimelineGroupStyle) -> Bool {
        let type = RoomTimelineItemType(item: item)
        let isTypeChanged = !self.type.isDrawnAlike(type)
        let isGroupStyleChanged = self.groupStyle != groupStyle
        
        if isTypeChanged {
            self.type = type
        }
        if isGroupStyleChanged {
            self.groupStyle = groupStyle
        }
        return isTypeChanged || isGroupStyleChanged
    }
    
    func update(rowContext: TimelineRowContext) {
        if self.rowContext != rowContext {
            self.rowContext = rowContext
        }
    }
    
    // MARK: - Equatable
    
    static func == (lhs: RoomTimelineItemViewState, rhs: RoomTimelineItemViewState) -> Bool {
        #if DEBUG
        TimelineSignposts.rowComparisons += 1
        #endif
        return lhs === rhs || (lhs.type == rhs.type && lhs.groupStyle == rhs.groupStyle) // AGENT-PLATFORM (Brief 0083, question 359)
    }
    
    // MARK: Identifiable
    
    /// The `timelineID` of the item, used for the timeline view level identification, do not use for any business logic use `identifier` instead
    var id: TimelineItemIdentifier.UniqueID {
        identifier.uniqueID
    }
    
    /// The timestamp of the item if available (separator date or event timestamp), `nil` otherwise.
    var timestamp: Date? {
        type.timestamp
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 364): the newest event drawn here, a folded group being many.
    var newestEventItemID: TimelineItemIdentifier? {
        if case .group(let group) = type {
            return group.itemIDs.last { $0.eventID != nil }
        }
        return identifier.eventID != nil ? identifier : nil
    }
}

enum RoomTimelineItemType: Equatable {
    case text(TextRoomTimelineItem)
    case separator(SeparatorRoomTimelineItem)
    case image(ImageRoomTimelineItem)
    case video(VideoRoomTimelineItem)
    case audio(AudioRoomTimelineItem)
    case file(FileRoomTimelineItem)
    case gallery(GalleryRoomTimelineItem)
    case emote(EmoteRoomTimelineItem)
    case notice(NoticeRoomTimelineItem)
    case redacted(RedactedRoomTimelineItem)
    case encrypted(EncryptedRoomTimelineItem)
    case readMarker(ReadMarkerRoomTimelineItem)
    case paginationIndicator(PaginationIndicatorRoomTimelineItem)
    case sticker(StickerRoomTimelineItem)
    case unsupported(UnsupportedRoomTimelineItem)
    case timelineStart(TimelineStartRoomTimelineItem)
    case state(StateRoomTimelineItem)
    case group(CollapsibleTimelineItem)
    case location(LocationRoomTimelineItem)
    case poll(PollRoomTimelineItem)
    case voice(VoiceMessageRoomTimelineItem)
    case callInvite(CallInviteRoomTimelineItem)
    case callNotification(CallNotificationRoomTimelineItem)
    case liveLocation(LiveLocationRoomTimelineItem)
    // AGENT-PLATFORM (Brief 0066)
    case interactivePost(InteractivePostRoomTimelineItem)
    case interactiveDraft(InteractiveDraftRoomTimelineItem)
    case interactiveGenerating(InteractiveGeneratingRoomTimelineItem)
    // AGENT-PLATFORM (Brief 0073): a client-rendered notice card.
    case spiralNotice(SpiralNoticeRoomTimelineItem)
    // AGENT-PLATFORM (decision 371): a call's summary as a card.
    case callSummary(CallSummaryRoomTimelineItem)
    
    init(item: RoomTimelineItemProtocol) {
        switch item {
        case let item as TextRoomTimelineItem:
            self = .text(item)
        case let item as ImageRoomTimelineItem:
            self = .image(item)
        case let item as VideoRoomTimelineItem:
            self = .video(item)
        case let item as AudioRoomTimelineItem:
            self = .audio(item)
        case let item as FileRoomTimelineItem:
            self = .file(item)
        case let item as GalleryRoomTimelineItem:
            self = .gallery(item)
        case let item as SeparatorRoomTimelineItem:
            self = .separator(item)
        case let item as NoticeRoomTimelineItem:
            self = .notice(item)
        case let item as EmoteRoomTimelineItem:
            self = .emote(item)
        case let item as RedactedRoomTimelineItem:
            self = .redacted(item)
        case let item as EncryptedRoomTimelineItem:
            self = .encrypted(item)
        case let item as ReadMarkerRoomTimelineItem:
            self = .readMarker(item)
        case let item as PaginationIndicatorRoomTimelineItem:
            self = .paginationIndicator(item)
        case let item as StickerRoomTimelineItem:
            self = .sticker(item)
        case let item as InteractivePostRoomTimelineItem:
            self = .interactivePost(item)
        case let item as InteractiveDraftRoomTimelineItem:
            self = .interactiveDraft(item)
        case let item as InteractiveGeneratingRoomTimelineItem:
            self = .interactiveGenerating(item)
        case let item as SpiralNoticeRoomTimelineItem:
            self = .spiralNotice(item)
        case let item as CallSummaryRoomTimelineItem:
            self = .callSummary(item)
        case let item as UnsupportedRoomTimelineItem:
            self = .unsupported(item)
        case let item as TimelineStartRoomTimelineItem:
            self = .timelineStart(item)
        case let item as StateRoomTimelineItem:
            self = .state(item)
        case let item as CollapsibleTimelineItem:
            self = .group(item)
        case let item as LocationRoomTimelineItem:
            self = .location(item)
        case let item as PollRoomTimelineItem:
            self = .poll(item)
        case let item as VoiceMessageRoomTimelineItem:
            self = .voice(item)
        case let item as CallInviteRoomTimelineItem:
            self = .callInvite(item)
        case let item as CallNotificationRoomTimelineItem:
            self = .callNotification(item)
        case let item as LiveLocationRoomTimelineItem:
            self = .liveLocation(item)
        default:
            fatalError("Unknown timeline item")
        }
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 359): whether the row would draw the same. `==` knows a folded group by its IDs,
    /// which is enough for an animation to go by and not for a fold, as it draws the items in it.
    func isDrawnAlike(_ other: RoomTimelineItemType) -> Bool {
        guard self == other else { return false }
        guard case .group(let group) = self, case .group(let otherGroup) = other else { return true }
        return zip(group.items, otherGroup.items).allSatisfy { RoomTimelineItemType(item: $0) == RoomTimelineItemType(item: $1) }
    }
    
    var id: TimelineItemIdentifier {
        switch self {
        case .text(let item as RoomTimelineItemProtocol),
             .separator(let item as RoomTimelineItemProtocol),
             .image(let item as RoomTimelineItemProtocol),
             .video(let item as RoomTimelineItemProtocol),
             .audio(let item as RoomTimelineItemProtocol),
             .file(let item as RoomTimelineItemProtocol),
             .gallery(let item as RoomTimelineItemProtocol),
             .emote(let item as RoomTimelineItemProtocol),
             .notice(let item as RoomTimelineItemProtocol),
             .redacted(let item as RoomTimelineItemProtocol),
             .encrypted(let item as RoomTimelineItemProtocol),
             .readMarker(let item as RoomTimelineItemProtocol),
             .paginationIndicator(let item as RoomTimelineItemProtocol),
             .sticker(let item as RoomTimelineItemProtocol),
             .unsupported(let item as RoomTimelineItemProtocol),
             .timelineStart(let item as RoomTimelineItemProtocol),
             .state(let item as RoomTimelineItemProtocol),
             .group(let item as RoomTimelineItemProtocol),
             .location(let item as RoomTimelineItemProtocol),
             .poll(let item as RoomTimelineItemProtocol),
             .voice(let item as RoomTimelineItemProtocol),
             .callInvite(let item as RoomTimelineItemProtocol),
             .callNotification(let item as RoomTimelineItemProtocol),
             .liveLocation(let item as RoomTimelineItemProtocol),
             .interactivePost(let item as RoomTimelineItemProtocol),
             .interactiveDraft(let item as RoomTimelineItemProtocol),
             .interactiveGenerating(let item as RoomTimelineItemProtocol),
             .spiralNotice(let item as RoomTimelineItemProtocol),
             .callSummary(let item as RoomTimelineItemProtocol):
            return item.id
        }
    }
    
    /// The timestamp of the item if available.
    /// Returns the separator date for `.separator`, the event timestamp for all event-based
    /// items, the timestamp of the first event inside a `.group`, and `nil` for virtual items
    /// that carry no timestamp (read marker, pagination indicator, timeline start).
    var timestamp: Date? {
        switch self {
        case .separator(let item):
            return item.timestamp
        case .text(let item):
            return item.timestamp
        case .image(let item):
            return item.timestamp
        case .video(let item):
            return item.timestamp
        case .audio(let item):
            return item.timestamp
        case .file(let item):
            return item.timestamp
        case .gallery(let item):
            return item.timestamp
        case .emote(let item):
            return item.timestamp
        case .notice(let item):
            return item.timestamp
        case .redacted(let item):
            return item.timestamp
        case .encrypted(let item):
            return item.timestamp
        case .sticker(let item):
            return item.timestamp
        case .interactivePost(let item):
            return item.timestamp
        case .interactiveDraft(let item):
            return item.timestamp
        case .interactiveGenerating(let item):
            return item.timestamp
        case .unsupported(let item):
            return item.timestamp
        case .state(let item):
            return item.timestamp
        case .location(let item):
            return item.timestamp
        case .poll(let item):
            return item.timestamp
        case .voice(let item):
            return item.timestamp
        case .callInvite(let item):
            return item.timestamp
        case .callNotification(let item):
            return item.timestamp
        case .spiralNotice(let item):
            return item.timestamp
        case .callSummary(let item):
            return item.timestamp
        case .liveLocation(let item):
            return item.timestamp
        case .group(let item):
            return (item.items.first { $0 is EventBasedTimelineItemProtocol } as? EventBasedTimelineItemProtocol)?.timestamp
        case .readMarker, .paginationIndicator, .timelineStart:
            return nil
        }
    }
}
