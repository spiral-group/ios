//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: one agent as the chat's tools carry it from screen to screen
// (Brief 0035/0036 / ADR-0048), not present upstream: id + MXID + name + avatar.
// Build it from a `RoomToolAgentEntry` via `init(entry:)`.
//

import Foundation

/// One agent in a room.
nonisolated struct AgentSummary: Equatable, Identifiable {
    var id: String {
        agentID
    }

    let agentID: String
    let matrixUserID: String
    let displayName: String
    /// Brief 0043 P4: whether the caller owns this agent. Only own agents are
    /// editable; everyone SEES the room's full tool picture.
    var isMine = true
    /// The agent's avatar when it has one; `nil` draws its letter. The room's
    /// tools read carries none, so whoever projects the entry supplies it.
    var avatarURL: URL?

    /// A human name derived from an MXID localpart when no display name is
    /// available: `@assistant-alice:host` → "Assistant-alice".
    static func displayName(fromMatrixUserID mxid: String) -> String {
        let localpart = mxid.hasPrefix("@") ? String(mxid.dropFirst()) : mxid
        let name = localpart.split(separator: ":").first.map(String.init) ?? localpart
        return name.isEmpty ? mxid : name.localizedCapitalized
    }
}

nonisolated extension AgentSummary {
    init(entry: RoomToolAgentEntry, avatarURL: URL? = nil) {
        self.init(agentID: entry.agentID,
                  matrixUserID: entry.matrixUserID,
                  displayName: entry.displayName,
                  isMine: entry.isMine,
                  avatarURL: avatarURL)
    }

    /// A just-added agent that hasn't landed in the room read-model yet (it auto-joins).
    static func justJoined(agentID: String, matrixUserID: String, displayName: String) -> AgentSummary {
        AgentSummary(agentID: agentID, matrixUserID: matrixUserID, displayName: displayName)
    }
}
