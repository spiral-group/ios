//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRustSDK

enum MessageForwardingScreenViewModelAction {
    case dismiss
    case sent(roomIDs: [String])
}

struct MessageForwardingScreenViewState: BindableState {
    // AGENT-PLATFORM: feed (Brief 0082): the source names the screen.
    var title = L10n.commonForwardTo
    /// The recently visited rooms, never filtered by the search query.
    var suggestedRooms: [MessageForwardingRoom] = []
    var rooms: [MessageForwardingRoom] = []
    var selectedRoomIDs: Set<String> = []
    // AGENT-PLATFORM: feed (Brief 0082): one send at a time; Send and Cancel wait for it.
    var isForwarding = false
    let maxRoomSelectionCount = 5
    var bindings = MessageForwardingScreenViewStateBindings()
    
    var showsSuggestions: Bool {
        bindings.searchQuery.isEmpty && !suggestedRooms.isEmpty
    }
    
    /// Every room appears once: the suggested ones are left out unless searching.
    var chats: [MessageForwardingRoom] {
        guard showsSuggestions else { return rooms }
        
        let suggestedRoomIDs = Set(suggestedRooms.map(\.id))
        return rooms.filter { !suggestedRoomIDs.contains($0.id) }
    }
    
    var isAtRoomSelectionLimit: Bool {
        selectedRoomIDs.count >= maxRoomSelectionCount
    }
}

struct MessageForwardingScreenViewStateBindings {
    var searchQuery = ""
}

enum MessageForwardingScreenViewAction {
    case cancel
    case send
    case selectRoom(roomID: String)
    case reachedTop
    case reachedBottom
}

struct MessageForwardingRoom: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let avatar: RoomAvatar
}

extension MessageForwardingRoom {
    init(summary: RoomSummary) {
        self.init(id: summary.id,
                  title: summary.name,
                  description: summary.roomListDescription,
                  avatar: summary.avatar)
    }
}

struct MessageForwardingPayload: Hashable {
    /// The source items' timeline IDs. Only necessary for a rough Hashable conformance.
    let ids: [TimelineItemIdentifier]
    /// The source items' room ID.
    let roomID: String
    /// The contents to be forwarded, in timeline order.
    let contents: [RoomMessageEventContentWithoutRelation]
    
    static func == (lhs: MessageForwardingPayload, rhs: MessageForwardingPayload) -> Bool {
        lhs.ids == rhs.ids && lhs.roomID == rhs.roomID
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ids)
        hasher.combine(roomID)
    }
}

// AGENT-PLATFORM: feed (Brief 0082). What is forwarded may come from outside
// a timeline: a feed post is shared with the text the server builds per room.
protocol MessageForwardingSource {
    var title: String { get }
    /// A room the picker leaves out.
    func excludes(_ room: RoomSummary) -> Bool
    /// The contents to send into the room in order, or what to tell the person when there are none.
    func contents(for roomID: String) async -> Result<[RoomMessageEventContentWithoutRelation], MessageForwardingSourceError>
    /// The toast after a send without failures, or `nil` when the flow tells the person itself.
    func sentMessage(roomCount: Int) -> String?
    /// The send is over: the rooms sent to, and those that could not be (rooms left unsent by a dismissal are neither).
    func didFinish(sentRoomIDs: [String], failedRoomIDs: [String])
    /// Whether a dismissal mid-send leaves the rooms not yet reached unsent; upstream's forward finishes every room.
    var stopsWhenDismissed: Bool { get }
}

struct MessageForwardingSourceError: Error {
    let message: String
}

// AGENT-PLATFORM: feed (Brief 0082). Timeline items forward as before.
extension MessageForwardingPayload: MessageForwardingSource {
    var title: String {
        L10n.commonForwardTo
    }

    func excludes(_ room: RoomSummary) -> Bool {
        room.id == roomID
    }

    func contents(for roomID: String) async -> Result<[RoomMessageEventContentWithoutRelation], MessageForwardingSourceError> {
        .success(contents)
    }

    /// The flow opens the room when there is a single one, otherwise the user stays here and needs to know it worked.
    func sentMessage(roomCount: Int) -> String? {
        roomCount > 1 ? L10n.screenRoomMessagesForwarded(contents.count) : nil
    }

    func didFinish(sentRoomIDs: [String], failedRoomIDs: [String]) { }

    var stopsWhenDismissed: Bool {
        false
    }
}
