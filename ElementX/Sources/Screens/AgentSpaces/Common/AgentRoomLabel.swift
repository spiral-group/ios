//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (coverage walk F9): the hub, an agent's activity and an
// approval card name the room an agent acted in. The owner reads its name,
// never its Matrix id.
//

import Foundation

enum AgentRoomLabel {
    /// The room's name on this device, or a neutral phrase when this device
    /// doesn't know it (a visitor's chat with the agent, which the owner isn't in).
    /// Nil only when there is no room.
    static func text(for roomID: String?, clientProxy: any ClientProxyProtocol) -> String? {
        guard let roomID, !roomID.isEmpty else { return nil }
        return name(for: roomID, clientProxy: clientProxy) ?? UntranslatedL10n.commonAConversation
    }
    
    /// The room's name on this device; nil when it has none, for a caller with its own wording.
    static func name(for roomID: String, clientProxy: any ClientProxyProtocol) -> String? {
        // A room with no name of its own can come back named by its ID.
        guard let name = clientProxy.roomSummaryForIdentifier(roomID)?.name.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty, name != roomID else {
            return nil
        }
        return name
    }
}

extension AgentRoomLabel {
    /// The names this device has for the agent's chats, by room id; a chat it isn't in has none.
    static func deviceRoomNames(of rooms: [AgentRoomEntry], clientProxy: any ClientProxyProtocol) -> [String: String] {
        rooms.reduce(into: [String: String]()) { names, room in
            names[room.roomID] = name(for: room.roomID, clientProxy: clientProxy)
        }
    }
    
    /// The owner's own DM with the agent, as this device knows it.
    static func ownerDMRoomID(agentMatrixUserID: String, clientProxy: any ClientProxyProtocol) -> String? {
        guard case .success(let roomID?) = clientProxy.directRoomForUserID(agentMatrixUserID) else { return nil }
        return roomID
    }
}

extension AgentRoomEntry {
    /// The owner's DM with the agent is titled after the agent; it reads
    /// as the owner's chat with it instead. Any other chat on this device
    /// reads as it does there (`deviceName`): the server, which counts the
    /// agent as a member, names a DM the agent was added to «X and Y».
    /// Someone else's DM with the agent is titled by that person.
    func title(ownerDMRoomID: String?, agentName: String, deviceName: String?) -> String {
        if roomID == ownerDMRoomID {
            return UntranslatedL10n.screenAgentRoomOwnerDm
        }
        if let deviceName {
            return deviceName
        }
        // Never surface a raw room ID as a title.
        guard let displayName else { return L10n.commonNoRoomName }
        if kind == "dm", let person = Self.otherMember(in: displayName, agentName: agentName) {
            return person
        }
        return displayName
    }
    
    /// The server names a chat without a name by its members, as the Matrix
    /// spec does for the owner, who isn't in a visitor's DM: the agent and
    /// the person joined by an English «and», in Matrix ID order. Read back
    /// out of that, the person is what the owner wants to see.
    private static func otherMember(in name: String, agentName: String) -> String? {
        let joiner = " and "
        if name.hasPrefix(agentName + joiner) {
            return String(name.dropFirst(agentName.count + joiner.count))
        }
        if name.hasSuffix(joiner + agentName) {
            return String(name.dropLast(agentName.count + joiner.count))
        }
        return nil
    }
}
