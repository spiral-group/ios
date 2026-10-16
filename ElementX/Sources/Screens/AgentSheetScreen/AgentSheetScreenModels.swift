//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0035/0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenModels.swift`.
// The agent bottom-sheet reached from the composer "+"
// "Agents" item — the root of the room → agent → tool flow. Lists the
// caller's own agents present in the room (avatar + name + a one-line tool
// summary) and an "Add agent" affordance. Tapping an agent opens its
// capabilities; "Add agent" opens the picker of the caller's other agents to
// invite. Reads `GET /rooms/:room_id/tools` for the joined agents + their
// active tools.
//

import Foundation

// MARK: - ViewModel → Coordinator actions

enum AgentSheetScreenViewModelAction {
    /// User picked an agent already in the room — open its capabilities.
    case selectAgent(AgentSummary)
    /// User tapped "Add agent" — open the picker of agents to invite.
    case addAgent
    /// User dismissed the sheet.
    case dismiss
}

// MARK: - View ↔ ViewModel state

enum AgentSheetListState: Equatable {
    /// `GET /rooms/:room_id/tools` in flight.
    case loading
    /// Resolved lists: the caller's own agents (editable) and other
    /// participants' agents that have tools armed (read-only). Brief
    /// 0043 P4 — everyone sees the room's full tool picture, each edits
    /// only their own.
    case loaded(mine: [AgentSummary], others: [AgentSummary])
    /// The fetch failed. Inline retry.
    case failed
}

struct AgentSheetScreenViewState: BindableState {
    var listState: AgentSheetListState = .loading
    /// The agent whose screen is being opened; other taps wait for it.
    var openingAgentID: String?
    var bindings = AgentSheetScreenViewStateBindings()

    /// The caller's own (editable) agents.
    var agents: [AgentSummary] {
        if case .loaded(let mine, _) = listState { return mine }
        return []
    }

    /// Other participants' agents with armed tools (read-only).
    var otherAgents: [AgentSummary] {
        if case .loaded(_, let others) = listState { return others }
        return []
    }

    /// True when the caller has no agent of their own in this room —
    /// the sheet shows a "add your agent" CTA rather than an empty row.
    var hasNoOwnAgent: Bool {
        if case .loaded(let mine, _) = listState { return mine.isEmpty }
        return false
    }
}

struct AgentSheetScreenViewStateBindings {
    var alertInfo: AlertInfo<AgentSheetScreenAlertType>?
}

enum AgentSheetScreenAlertType: Hashable {
    case loadFailed
}

// MARK: - View → ViewModel actions

enum AgentSheetScreenViewAction {
    /// `.onAppear` — fetch the room's agents.
    case appeared
    /// Retry after a failed fetch.
    case retry
    /// User tapped an agent row.
    case selectAgent(id: String)
    /// User tapped "Add agent".
    case addAgent
    /// User tapped Done / dismissed.
    case done
}
