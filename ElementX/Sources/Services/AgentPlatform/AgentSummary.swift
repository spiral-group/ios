//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: a shared, UI-ready projection of one agent (Brief
// 0035/0036 / ADR-0048), not present upstream. The agent-tools surfaces
// (the "+" agent sheet, the multi-agent picker, the flow coordinator's
// resolved-agent cache) all need the same lightweight triple — id + MXID
// + display name — plus a one-line status. This
// is that single type, so screens don't each define a near-identical
// `…Item` struct and the flow doesn't round-trip through `RoomToolAgentEntry`
// (which drops `tools`) and fake it back.
//
// It is a *summary* — a ready-for-a-row value, NOT the full read model:
// `statusLine` is already localised and `activeToolCount` is a count, so a
// consumer never reaches back into `RoomToolView`. Build it from a
// `RoomToolAgentEntry` via `init(entry:)`.
//

import Foundation

/// A UI-ready summary of one agent in a room.
nonisolated struct AgentSummary: Equatable, Identifiable {
    var id: String {
        agentID
    }

    let agentID: String
    let matrixUserID: String
    let displayName: String
    /// How many active tools this agent has in the room.
    let activeToolCount: Int
    /// A localised one-line status ("Translating to English", "No tools
    /// yet · tap to set up"). Computed once at projection time.
    let statusLine: String
    /// Brief 0043 P4: whether the caller owns this agent. Only own
    /// agents are editable; others are read-only rows so every
    /// participant SEES the room's full tool picture.
    var isMine = true

    /// A human name derived from an MXID localpart when no display name is
    /// available: `@assistant-alice:host` → "Assistant-alice".
    static func displayName(fromMatrixUserID mxid: String) -> String {
        let localpart = mxid.hasPrefix("@") ? String(mxid.dropFirst()) : mxid
        let name = localpart.split(separator: ":").first.map(String.init) ?? localpart
        return name.isEmpty ? mxid : name.localizedCapitalized
    }
}

nonisolated extension AgentSummary {
    /// Project a room read-model entry into a summary, computing the
    /// one-line status from its active tools.
    init(entry: RoomToolAgentEntry) {
        self.init(agentID: entry.agentID,
                  matrixUserID: entry.matrixUserID,
                  displayName: entry.displayName,
                  activeToolCount: entry.tools.count,
                  statusLine: Self.statusLine(for: entry),
                  isMine: entry.isMine)
    }

    /// The caller's own agents in a room, as summaries.
    static func ownAgents(in roomTools: RoomToolsView) -> [AgentSummary] {
        roomTools.agents.filter(\.isMine).map(AgentSummary.init(entry:))
    }

    /// Brief 0043 P4: OTHER participants' agents (read-only rows) — so
    /// everyone sees the room's full tool picture. Only agents that
    /// actually have tools armed are worth showing.
    static func otherAgents(in roomTools: RoomToolsView) -> [AgentSummary] {
        roomTools.agents
            .filter { !$0.isMine && !$0.tools.isEmpty }
            .map(AgentSummary.init(entry:))
    }

    /// A synthetic summary for a just-added agent that hasn't landed in the
    /// room read-model yet (it auto-joins) — carries no tools.
    static func justJoined(agentID: String, matrixUserID: String, displayName: String) -> AgentSummary {
        AgentSummary(agentID: agentID,
                     matrixUserID: matrixUserID,
                     displayName: displayName,
                     activeToolCount: 0,
                     statusLine: UntranslatedL10n.screenAgentSheetNoTools)
    }

    /// The one-line status: the single active tool's summary when there's
    /// exactly one translate tool, otherwise a plain active count, or a
    /// "no tools yet" prompt.
    private static func statusLine(for entry: RoomToolAgentEntry) -> String {
        guard !entry.tools.isEmpty else {
            return UntranslatedL10n.screenAgentSheetNoTools
        }
        if entry.tools.count == 1 {
            switch entry.tools[0].params {
            case .translate(let language):
                return UntranslatedL10n.screenAgentToolsListTitleTranslate(TranslationLanguageDisplayName.localizedName(for: language))
            case .liveTranslate(let languages, _):
                if let language = languages.first {
                    return UntranslatedL10n.screenAgentToolsListTitleTranslate(TranslationLanguageDisplayName.localizedName(for: language))
                }
            default:
                break
            }
        }
        return UntranslatedL10n.screenAgentsToolCount(entry.tools.count)
    }
}
