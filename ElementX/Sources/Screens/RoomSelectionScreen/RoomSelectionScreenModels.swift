//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRustSDK

enum RoomSelectionScreenViewModelAction {
    case dismiss
    case confirm(roomID: String)
}

/// AGENT-PLATFORM (Agents tab polish): why a filtered picker has nothing to
/// offer, and what to do about it.
struct RoomSelectionScreenEmptyState: Equatable {
    let title: String
    let message: String
}

struct RoomSelectionScreenViewState: BindableState {
    /// AGENT-PLATFORM (decision 111): the confirm button's label.
    let confirmTitle: String
    /// AGENT-PLATFORM: shown when the loaded list offers no chat at all.
    var emptyState: RoomSelectionScreenEmptyState?
    var rooms: [RoomSelectionRoom] = []
    var selectedRoomID: String?
    /// Whether the room list has been read, so an empty list means none.
    var isListLoaded = false
    var bindings = RoomSelectionScreenViewStateBindings()
    
    /// A search that matches nothing keeps the usual blank list.
    var showsEmptyState: Bool {
        emptyState != nil && isListLoaded && rooms.isEmpty && bindings.searchQuery.isEmpty
    }
}

struct RoomSelectionScreenViewStateBindings {
    var searchQuery = ""
}

enum RoomSelectionScreenViewAction {
    case cancel
    case confirm
    case selectRoom(roomID: String)
    case reachedTop
    case reachedBottom
}

struct RoomSelectionRoom: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let avatar: RoomAvatar
}
