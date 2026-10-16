//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenModels.swift`.
// The "Active tools" edit surface — reached from the
// in-chat active-tools banner ("Manage"). Unlike the capabilities screen
// (a per-capability on/off list reached from the composer "+" to CREATE a
// tool), this lists the agent's REAL armed tools as individual rows so
// each can be edited or turned off. Every field an edit form needs is
// already in hand from `fetchRoomTools` for the caller's own agent, so no
// extra backend call is required to build the list or seed an edit.
//

import Foundation

// MARK: - ViewModel → Coordinator actions

enum AgentToolsListScreenViewModelAction {
    /// User tapped a tool row — the flow presents the arm form seeded for
    /// editing (replace = disable old + arm new).
    case editTool(ActiveToolDetail)
    /// User tapped "Add a tool" — the flow presents a fresh create form.
    case addTool
    /// User dismissed the sheet.
    case dismiss
}

// MARK: - Domain

/// One armed tool, projected from a `RoomToolView` for the caller's own
/// agent (so `toolID` + typed `params` + `trigger` are all present). This
/// is a lifecycle-stable UI facade — the screens never touch the raw
/// read-model / generated types.
struct ActiveToolDetail: Equatable, Identifiable {
    /// Backend tool id — needed to `disableTool` on edit/turn-off.
    let toolID: String
    /// The capability family this tool belongs to (drives the row icon).
    let capability: AgentCapability
    /// Full typed params (the WHAT) — seeds the edit form.
    let params: ToolParams
    /// Full typed trigger (the WHEN) — seeds the edit form's scope/members.
    let trigger: TriggerKind
    /// A short human title, e.g. "Translate → English".
    let title: String
    /// A short human subtitle, e.g. "Everyone except me · on message".
    let subtitle: String
    /// Whether the catalogue says this tool's kind can fire for this agent
    /// here. The server may still list one that can't (decision 168: a
    /// company agent's call tool); it is shown as not available, never armed.
    var canFire = true

    var id: String {
        toolID
    }

    /// An edit replaces the tool, so one whose trigger or scope this build
    /// does not know (a newer platform's, decision 96) is not edited here:
    /// the form would write a trigger the user never saw.
    var isEditable: Bool {
        switch trigger {
        case .unknown:
            false
        case .onMessage(let scope), .onVoiceCall(let scope):
            if case .unknown = scope { false } else { true }
        }
    }
}

// MARK: - View ↔ ViewModel state

enum AgentToolsListState: Equatable {
    /// `GET /rooms/:room_id/tools` in flight.
    case loading
    /// Resolved with the caller's own agent's armed tools (may be empty).
    case loaded(tools: [ActiveToolDetail])
    /// The fetch failed. Inline retry.
    case failed
}

struct AgentToolsListScreenViewState: BindableState {
    /// Display name of the agent whose tools these are.
    let agentDisplayName: String
    var listState: AgentToolsListState = .loading
    var bindings: AgentToolsListScreenViewStateBindings

    var tools: [ActiveToolDetail] {
        if case .loaded(let tools) = listState { return tools }
        return []
    }

    var isLoading: Bool {
        if case .loading = listState { return true }
        return false
    }

    var isLoadedEmpty: Bool {
        if case .loaded(let tools) = listState { return tools.isEmpty }
        return false
    }
}

struct AgentToolsListScreenViewStateBindings {
    var alertInfo: AlertInfo<AgentToolsListScreenAlertType>?
}

enum AgentToolsListScreenAlertType: Hashable {
    case loadFailed
    case turnOffFailed
    /// A tool whose trigger or scope this build does not know.
    case needsUpdate
    /// A listed tool that can't fire for this agent here.
    case unavailable
}

// MARK: - View → ViewModel actions

enum AgentToolsListScreenViewAction {
    /// `.onAppear` — fetch the armed tools.
    case appeared
    /// Retry after a failed fetch.
    case retry
    /// User tapped a tool row — edit it.
    case selectTool(id: String)
    /// User turned a tool off (destructive row).
    case turnOffTool(id: String)
    /// User tapped "Add a tool".
    case addTool
    /// User tapped Done.
    case done
}
