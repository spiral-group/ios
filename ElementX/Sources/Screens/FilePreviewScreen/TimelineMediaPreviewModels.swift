//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

enum TimelineMediaPreviewViewModelAction: Equatable {
    case viewInRoomTimeline(TimelineItemIdentifier)
    case displayMessageForwarding(MessageForwardingPayload)
    case dismiss
}

/// Identifies a media preview item — either a whole timeline item or a single gallery attachment.
nonisolated enum MediaPreviewItemID: Hashable {
    case timelineItem(TimelineItemIdentifier.EventOrTransactionID)
    case galleryItem(GalleryItemID)
    
    /// Identifies by event/transaction ID only, since the unique ID differs across timelines
    /// and matching must survive rebuilding a filtered timeline to fetch the other media.
    init(timelineItem: EventBasedMessageTimelineItemProtocol) {
        guard let id = timelineItem.id.eventOrTransactionID else { fatalError("Virtual items cannot be previewed.") }
        self = .timelineItem(id)
    }
}

struct TimelineMediaPreviewViewState: BindableState {
    /// The data source for all of the preview-able items.
    var dataSource: TimelineMediaPreviewDataSource
    
    /// The media item that is currently being previewed.
    var currentItem: TimelineMediaPreviewItem {
        dataSource.currentItem
    }
    
    /// All of the available actions for the current item.
    var currentItemActions: TimelineItemMenuActions?
    
    /// Whether the current item can be replied to from the viewer: only where a composer is behind it.
    var canReplyToCurrentItem = false
    
    // AGENT-PLATFORM (Brief 0083, question 413): Spiral's own viewer — the bottom bar's forward, and what ⋯ offers.
    /// Forwarding the current item, when the room allows it.
    var forwardAction: TimelineItemMenuAction? {
        currentItemActions?.actions.first { if case .forward = $0 { true } else { false } }
    }
    
    /// What ⋯ offers for the current item: saving, the room's timeline and deleting, where allowed. Forwarding
    /// sits in the bottom bar instead.
    var moreMenuActions: [TimelineItemMenuAction] {
        guard let currentItemActions else { return [] }
        return (currentItemActions.actions + currentItemActions.secondaryActions).filter { action in
            switch action {
            case .viewInRoomTimeline, .downloadMedia, .redact: true
            default: false
            }
        }
    }
    
    /// Asks the pager to show a page it didn't reach by a swipe, such as a tapped thumbnail.
    let pagerDriver = PassthroughSubject<TimelineMediaPreviewPage, Never>()
    
    /// Sends when a media's file has downloaded or failed to, whether it's on screen or loaded ahead of a swipe.
    let mediaDidLoad = PassthroughSubject<MediaPreviewItemID, Never>()
    
    var bindings = TimelineMediaPreviewViewStateBindings()
}

struct TimelineMediaPreviewViewStateBindings {
    /// Whether the bars and the thumbnails are hidden, leaving the media alone on black.
    var isChromeHidden = false
    /// The item whose details sheet is shown.
    var detailsItem: TimelineMediaPreviewItem.Media?
    /// A binding that will present a confirmation to redact the specified item.
    var redactConfirmationItem: TimelineMediaPreviewItem.Media?
    /// A file being saved through the system's document picker.
    var exportFile: TimelineMediaPreviewFileExportPicker.File?
    /// A file that isn't a photo or a video, opened in QuickLook on its own.
    var quickLookItem: MediaPreviewItem?
    var alertInfo: AlertInfo<UUID>?
}

enum TimelineMediaPreviewViewAction {
    /// The pager settled on a page after a swipe.
    case pageChanged(TimelineMediaPreviewPage)
    /// A thumbnail was tapped.
    case showPage(TimelineMediaPreviewPage)
    /// Pages the next swipes are likely to reach, whose files are worth downloading ahead.
    case prefetch([TimelineMediaPreviewPage])
    case toggleChrome
    case showItemDetails(TimelineMediaPreviewItem.Media)
    case menuAction(TimelineItemMenuAction, item: TimelineMediaPreviewItem.Media)
    case redactConfirmation(item: TimelineMediaPreviewItem.Media, reason: String)
    case reply(TimelineMediaPreviewItem.Media)
    case openFile(TimelineMediaPreviewItem.Media)
}
