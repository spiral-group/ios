//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

enum MediaEventsTimelineScreenViewModelAction {
    case displayMessageForwarding(MessageForwardingPayload)
    case viewInRoomTimeline(TimelineItemIdentifier)
}

enum MediaEventsTimelineScreenMode {
    case media
    case files
}

struct MediaEventsTimelineGroup: Identifiable {
    var id: String
    var title: String
    var items: [RoomTimelineItemViewState]
}

struct MediaEventsTimelineScreenViewState: BindableState {
    var isBackPaginating = false
    var shouldShowEmptyState = false
    /// AGENT-PLATFORM (1.0.3 B14): the last page failed to load. It stays until Retry, so it neither reads as loading nor
    /// reads again by itself.
    var hasFailedToLoad = false
    
    var screenMode: MediaEventsTimelineScreenMode
    var groups = [MediaEventsTimelineGroup]()
    
    var activeTimelineContext: TimelineViewModel.Context
    
    var bindings: MediaEventsTimelineScreenViewStateBindings
}

struct MediaEventsTimelineScreenViewStateBindings {
    var mediaPreviewViewModel: TimelineMediaPreviewViewModel?
    var mediaPreviewSheetViewModel: TimelineMediaPreviewViewModel?
}

enum MediaEventsTimelineScreenViewAction {
    case changeScreenMode(MediaEventsTimelineScreenMode)
    case oldestItemDidAppear
    case oldestItemDidDisappear
    case tappedItem(item: RoomTimelineItemViewState)
    case longPressedItem(item: RoomTimelineItemViewState)
    case retry // AGENT-PLATFORM (1.0.3 B14)
}
