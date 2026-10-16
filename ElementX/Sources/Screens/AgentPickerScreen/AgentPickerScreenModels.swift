//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenModels.swift`.
// The agent chooser shown as the root of the agent-
// tools sheet when the room has more than one of the caller's own agents.
// With exactly one own agent the RoomFlow presenter skips this and opens
// the capabilities screen directly. The candidate list is already in hand
// from `fetchRoomTools`, so this screen is a static single-select — no
// async, no service.
//

import Foundation

// MARK: - ViewModel → Coordinator actions

enum AgentPickerScreenViewModelAction {
    /// User picked an agent — the coordinator pushes its capabilities.
    case selectAgent(AgentPickerItem)
    /// User dismissed the sheet.
    case dismiss
}

// MARK: - Domain

/// One selectable agent, projected from a `RoomToolAgentEntry`. Carries
/// the identifiers the downstream capabilities/arm screens need plus a
/// short summary of how many tools it already has armed.
struct AgentPickerItem: Equatable, Identifiable {
    var id: String { agentID }
    let agentID: String
    let matrixUserID: String
    let displayName: String
    /// How many tools this agent has active in the room (drives a subtitle).
    let activeToolCount: Int
}

/// What «+» → Interactive post makes of the owner's agents read
/// (agents-tab B11): a failed read is not "no agents".
enum InteractivePostAgentChoice: Equatable {
    case agents([AgentPickerItem])
    case noAgents
    case readFailed
    
    init(_ result: Result<MyPersonalAgentsView, AgentPlatformError>) {
        switch result {
        case .success(let view) where view.agents.isEmpty:
            self = .noAgents
        case .success(let view):
            self = .agents(view.agents.map { AgentPickerItem(agentID: $0.id,
                                                             matrixUserID: $0.matrixUserID,
                                                             displayName: $0.displayName,
                                                             activeToolCount: 0) })
        case .failure:
            self = .readFailed
        }
    }
}

// MARK: - View ↔ ViewModel state

struct AgentPickerScreenViewState: BindableState {
    let agents: [AgentPickerItem]
    var bindings = AgentPickerScreenViewStateBindings()
}

struct AgentPickerScreenViewStateBindings { }

// MARK: - View → ViewModel actions

enum AgentPickerScreenViewAction {
    case selectAgent(id: String)
    case done
}
