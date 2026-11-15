//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

// AGENT-PLATFORM: Brief 0037, artboard 0037-E — one agent inside one
// room: what it does here (active tools) + the destructive remove.

enum AgentInRoomScreenViewModelAction {
    /// "Open chat": the chat itself, not the agent's part in it.
    case openChat(roomID: String)
    /// The agent left the room — the flow pops and reloads upstream.
    case removed
    /// "+ Add a tool" — the flow opens the kinds, then the form, for this room.
    case addTool
    /// A tool was tapped: its form, to change or turn it off.
    case editTool(ActiveToolDetail)
}

/// The agent the screen is about, from its card on the Agents tab.
struct AgentInRoomScreenAgent: Equatable {
    let agentID: String
    let matrixUserID: String
    let displayName: String
}

extension AgentInRoomScreenAgent {
    init(card: AgentSpaceAgentCard) {
        self.init(agentID: card.agentID, matrixUserID: card.matrixUserID, displayName: card.displayName)
    }
}

struct AgentInRoomScreenViewState: BindableState {
    let agent: AgentInRoomScreenAgent
    /// Mutable: reloaded after a tool is turned off / armed.
    var room: AgentRoomEntry
    /// The owner's DM with this agent, so it is titled as that.
    let ownerDMRoomID: String?
    /// The chat's name on this device; `nil` for a chat this device isn't in.
    let deviceRoomName: String?
    /// Display names of the people the tools' audiences list, as far as this
    /// device's copy of the chat knows them.
    var memberNames: [String: String] = [:]
    
    var isRemoving = false
    /// The tool whose form is being opened (row spinner).
    var openingToolID: String?
    
    var bindings = AgentInRoomScreenViewStateBindings()
    
    var roomTitle: String {
        room.title(ownerDMRoomID: ownerDMRoomID, agentName: agent.displayName, deviceName: deviceRoomName)
    }
    
    /// The owner's own chat with the agent is theirs with it: the agent stays.
    var canRemoveFromRoom: Bool {
        room.roomID != ownerDMRoomID
    }
}

struct AgentInRoomScreenViewStateBindings {
    var alertInfo: AlertInfo<AgentInRoomScreenAlertType>?
}

enum AgentInRoomScreenAlertType: Hashable {
    case confirmRemove
    case removeFailed
    case toolUnavailable
}

enum AgentInRoomScreenViewAction {
    /// "Open chat" tapped.
    case openChat
    /// The destructive row was tapped — asks for confirmation first.
    case removeTapped
    /// Confirmation accepted — actually leave the room.
    case confirmRemove
    /// "+ Add a tool" tapped.
    case addTool
    /// A tool row was tapped.
    case selectTool(id: String)
}
