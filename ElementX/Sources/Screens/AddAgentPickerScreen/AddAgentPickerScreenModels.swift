//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0035/0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenModels.swift`.
// The "Add agent" picker reached from the agent-sheet.
// Lists the agents of every space the caller may act for — their Personal
// space and the companies they own (`GET /me/agent-spaces`, then
// `GET /agent-spaces/:id` per space; re-walk R1) — and, by crossing
// with the room's agents (`GET /rooms/:id/tools`), marks which are already
// in the chat. Tapping an addable agent invites it (`roomProxy.invite`);
// the backend auto-accepts an own agent's invite, so it joins almost
// immediately (ADR-0017: invite, never a client force-join).
//

import Foundation

// MARK: - ViewModel → Coordinator actions

enum AddAgentPickerScreenViewModelAction {
    /// An agent was invited (and, for an own agent, auto-joins). Carries the
    /// full item so the flow can open the new agent's tool kinds directly
    /// (name + ids in hand — no need to wait for the room read to catch up).
    case invited(AddAgentItem)
    /// User dismissed without inviting.
    case dismiss
}

// MARK: - Domain

/// One of the caller's own agents, projected from `PersonalAgentSummary`
/// (which carries no display name) crossed with the room's joined agents.
struct AddAgentItem: Equatable, Identifiable {
    var id: String {
        agentID
    }

    let agentID: String
    let matrixUserID: String
    /// The agent's own name from the listing. (The comment here used to say
    /// "the API has no display name" — it does, and always did; this picker
    /// was simply title-casing the MXID instead of reading it.)
    let displayName: String
    /// The agent's avatar when it has one; `nil` falls back to a letter
    /// drawn from `displayName`.
    let avatarURL: URL?
    /// Whether this agent is already joined/invited in the room.
    let isInRoom: Bool
}

// MARK: - View ↔ ViewModel state

/// One space the person may act for (their Personal space or a company
/// they own) with its agents — a section of the picker.
struct AddAgentSection: Equatable, Identifiable {
    /// The space's org id.
    let id: String
    let title: String
    let agents: [AddAgentItem]
}

enum AddAgentPickerListState: Equatable {
    case loading
    case loaded(sections: [AddAgentSection])
    case failed
}

struct AddAgentPickerScreenViewState: BindableState {
    var listState: AddAgentPickerListState = .loading
    /// The agentID currently being invited (row shows a spinner + disabled).
    var invitingAgentID: String?
    /// The room's members and agents have answered: until then the list shows, but takes no invite.
    var isRoomRead = false
    var bindings = AddAgentPickerScreenViewStateBindings()

    var sections: [AddAgentSection] {
        if case .loaded(let sections) = listState { return sections }
        return []
    }

    var agents: [AddAgentItem] {
        sections.flatMap(\.agents)
    }
}

struct AddAgentPickerScreenViewStateBindings {
    var alertInfo: AlertInfo<AddAgentPickerScreenAlertType>?
}

enum AddAgentPickerScreenAlertType: Hashable {
    case inviteFailed
}

// MARK: - View → ViewModel actions

enum AddAgentPickerScreenViewAction {
    case retry
    /// User tapped an addable agent row.
    case invite(id: String)
    case done
}
