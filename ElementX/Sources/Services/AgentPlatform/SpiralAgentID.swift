//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: whether a Matrix ID is one of the platform's agents. Its own
// file so the NSE can ask too: a notice previews as a notice only from an agent.
//

import Foundation

/// Agents live in their own application-service namespaces — `@assistant-<owner>:…`
/// (personal) and `@agent-<slug>-<n>:…` (company) — so the ID says, and the
/// display name does not have to (§ 5.64).
///
/// Any server's namespace on purpose: agents live only on our own homeserver
/// (ADR-0082's exclusive namespaces). Where a foreign `@assistant-…` must count
/// as a person — a call's peer, a room grant — `SpiralAgentRoomGrants.isLocalAgent`
/// adds the server.
nonisolated enum SpiralAgentID {
    enum Kind {
        case assistant
        case agent
    }
    
    static func isAgent(_ userID: String) -> Bool {
        kind(of: userID) != nil
    }
    
    /// Which of the two an agent's ID says it is; `nil` for anyone else.
    static func kind(of userID: String) -> Kind? {
        guard userID.hasPrefix("@"), let colon = userID.firstIndex(of: ":") else { return nil }
        let localpart = userID[userID.index(after: userID.startIndex)..<colon]
        if localpart.hasPrefix("assistant-") {
            return .assistant
        }
        return localpart.hasPrefix("agent-") ? .agent : nil
    }
}
