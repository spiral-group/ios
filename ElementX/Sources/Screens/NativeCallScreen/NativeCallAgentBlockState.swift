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
    /// What the owner was not sent, for the pill to name it (question 383).
    enum Delivery: Equatable {
        case summary
        case recording
    }

    /// The agent's display name, "Alex Sample · assistant"; the pill shows the owner part of it.
    let name: String
    let event: NativeCallAgentEvent
    /// The shown agent's MXID: its avatar, and what its Halo samples the voice by.
    var agentUserID = ""
    /// One's own agent, which the pill calls "Your assistant".
    var isOwn = false
    var isLeaving = false
    /// A summary is armed: notes have no other mark on screen, so the pill says so even under a recording.
    var isTakingNotes = false
    var failedDelivery: Delivery?
    /// Your assistant was called while the call still rings (scenario 9.4): it comes when someone answers.
    var joinsWhenAnswered = false
    /// The other agents in the call, in roster order; the first sits stacked behind the shown one's avatar.
    var otherAgentUserIDs: [String] = []

    var otherAgentCount: Int {
        otherAgentUserIDs.count
    }

    /// The block for the presentation's shown agent, among every agent in the call.
    init(_ agent: NativeCallAgentPresentation.Agent, among agents: [NativeCallAgentPresentation.Agent]) {
        name = agent.displayName
        event = agent.shown.event
        agentUserID = agent.mxid
        isOwn = agent.isOwn
        isLeaving = agent.shown.presence == .leaving
        isTakingNotes = agent.shown.isSummaryArmed
        failedDelivery = if agent.control?.summary.delivery == .failed {
            .summary
        } else if agent.control?.recording.delivery == .failed {
            .recording
        } else {
            nil
        }
        otherAgentUserIDs = agents.map(\.mxid).filter { $0 != agent.mxid }
    }

    /// A block from its parts, for previews and the lab.
    init(name: String,
         event: NativeCallAgentEvent,
         agentUserID: String = "",
         isOwn: Bool = false,
         isLeaving: Bool = false,
         isTakingNotes: Bool = false,
         failedDelivery: Delivery? = nil,
         joinsWhenAnswered: Bool = false,
         otherAgentUserIDs: [String] = []) {
        self.name = name
        self.event = event
        self.agentUserID = agentUserID
        self.isOwn = isOwn
        self.isLeaving = isLeaving
        self.isTakingNotes = isTakingNotes
        self.failedDelivery = failedDelivery
        self.joinsWhenAnswered = joinsWhenAnswered
        self.otherAgentUserIDs = otherAgentUserIDs
    }
}
