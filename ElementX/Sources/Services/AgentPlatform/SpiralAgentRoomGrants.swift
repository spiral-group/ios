//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066 § 5.88): what a person's client grants an
// agent when the person adds it to their room.
//
// An agent joins at the default power level, below `state_default`, so the
// two state types it keeps about ITSELF are refused: `com.spiral.tools` (the
// tools it runs here — the banner every member sees) and
// `io.element.functional_members` (that it is a service member, so clients
// still treat a two-person room as a DM). The platform used to make room by
// rewriting `m.room.power_levels` as the room's admin; that was a change in
// a person's room the person never made, and it is gone. The person's own
// client makes it, on the person's own action — adding the agent — and only
// where the person may edit power levels.
//

import Foundation

nonisolated enum SpiralAgentRoomGrants {
    /// The state types an agent maintains about itself in a room.
    static let stateTypes = ["com.spiral.tools", "io.element.functional_members"]

    /// Whether `userID` is one of THIS server's agents — the two exclusive
    /// namespaces of the platform's application service. An agent of another
    /// server is a stranger and gets nothing.
    static func isLocalAgent(_ userID: String, ownUserID: String) -> Bool {
        guard SpiralAppPostSession.isAgent(userID),
              let agentServer = serverName(of: userID),
              let ownServer = serverName(of: ownUserID) else {
            return false
        }
        return agentServer == ownServer
    }

    private static func serverName(of userID: String) -> Substring? {
        guard userID.hasPrefix("@"), let colon = userID.firstIndex(of: ":") else { return nil }
        let server = userID[userID.index(after: colon)...]
        return server.isEmpty ? nil : server
    }
}
