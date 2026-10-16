//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063, Phase 1 of the native call UI plan): the
// agent block's state — a PROJECTION of `NativeCallAgentPresentation`.
//
// The block answers one question — "who is the agent and what do I hear?"
// — with ONE event at a time. The ladder that picks the event, and every
// fact feeding it, lives in the presentation derive; this type only
// carries the active agent's verdict to the view, already worded.

import Foundation

struct NativeCallAgentBlockState: Equatable {
    let name: String
    let event: NativeCallAgentEvent
    /// `1 of 2 agents` when the call holds more than one; nil otherwise.
    /// The block shows the ACTIVE agent, so a second one has to be
    /// disclosed somewhere — this line says the sheet has the rest.
    let agentCountLine: String?
    /// The shown agent's MXID — what the wave samples its voice level by.
    var agentUserID = ""

    init(name: String, event: NativeCallAgentEvent, agentCountLine: String?, agentUserID: String = "") {
        self.name = name
        self.event = event
        self.agentCountLine = agentCountLine
        self.agentUserID = agentUserID
    }

    /// The block for the presentation's active agent.
    init(_ agent: NativeCallAgentPresentation.Agent) {
        self.init(name: agent.displayName,
                  event: agent.shown.event,
                  agentCountLine: NativeCallAgentStatusCopy.agentCountLine(agent.ordinal),
                  agentUserID: agent.mxid)
    }

    /// The wave replaces the identity glyph only while the agent is on the
    /// air — translating, or answering in a conversation.
    var isAiring: Bool {
        if case .airing = event { return true }
        return false
    }
}
