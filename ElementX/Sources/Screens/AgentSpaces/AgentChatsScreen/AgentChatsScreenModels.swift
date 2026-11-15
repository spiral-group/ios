//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): the chats an agent is in, opened from its page in a chat or a profile.
//

import Foundation

enum AgentChatsScreenViewModelAction {
    case selectRoom(AgentRoomEntry)
    /// The agent no longer exists (deleted elsewhere).
    case gone
}

struct AgentChatsScreenViewState: BindableState {
    var loadState: AgentChatsScreenLoadState = .loading
    let agentName: String
    /// The card's count: how many rows hold the place while the chats are read.
    let expectedRoomCount: Int
    /// The owner's DM with this agent, so its row reads as that.
    var ownerDMRoomID: String?
    /// The chats' names on this device, by room id; a chat this device isn't in has none.
    var deviceRoomNames: [String: String] = [:]
    /// The sync's state at the top while the stream is not live (decision 289).
    var syncStatus: PlatformSyncStatus?
    
    func title(for room: AgentRoomEntry) -> String {
        room.title(ownerDMRoomID: ownerDMRoomID, agentName: agentName, deviceName: deviceRoomNames[room.roomID])
    }
}

nonisolated enum AgentChatsScreenLoadState: Equatable {
    case loading
    case loaded([AgentRoomEntry])
    case failure
}

enum AgentChatsScreenViewAction {
    case selectRoom(AgentRoomEntry)
    case retry
}
