//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum RoomThreadListScreenViewModelAction {
    case presentThread(threadRootEventID: String)
}

struct RoomThreadListScreenViewState: BindableState {
    // AGENT-PLATFORM (Brief 0083, decision 357): what the page shows. An empty list alone can't say which.
    enum Content: Equatable {
        case loading
        case empty
        case failed
        case list
    }
    
    var items = [RoomThreadListItem]()
    
    var paginationState: RoomThreadListPaginationState
    
    /// The last read failed. It stays until Retry, so a failure neither reads as the end of the list nor retries by itself.
    var hasFailedToLoad = false
    
    var bindings: RoomThreadListScreenViewStateBindings
    
    var isPaginating: Bool {
        paginationState == .loading
    }
    
    var content: Content {
        if !items.isEmpty {
            .list
        } else if hasFailedToLoad {
            .failed
        } else if paginationState == .idle(endReached: true) {
            .empty
        } else {
            .loading
        }
    }
}

struct RoomThreadListScreenViewStateBindings { }

enum RoomThreadListScreenViewAction {
    case oldestItemDidAppear
    case oldestItemDidDisappear
    case tappedThread(threadRootEventID: String)
    case retry // AGENT-PLATFORM (Brief 0083, decision 357)
}
