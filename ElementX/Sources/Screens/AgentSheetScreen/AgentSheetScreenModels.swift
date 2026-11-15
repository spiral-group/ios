//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0035/0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenModels.swift`.
// A chat's tools (question 359, item 12, board A): the one screen behind the
// chat's "+". Each of the person's agents as a group with its tools, other
// people's agents with theirs, read-only, then "Add agent". It renders
// `GET /rooms/:room_id/tools` from the session store.
//

import Compound
import SwiftUI

// MARK: - ViewModel → Coordinator actions

enum AgentSheetScreenViewModelAction: Equatable {
    /// "Add a tool" or "All tools": the kinds this agent can take here.
    case addTool(AgentSummary)
    /// A quick row: the form of one kind, straight away.
    case addToolOfKind(AgentToolKind, AgentSummary)
    /// One of the person's own tools.
    case editTool(ActiveToolDetail, AgentSummary)
    /// Someone else's tool, read-only.
    case viewTool(ToolDetail)
    case addAgent
    /// The "…" menu's profile.
    case viewProfile(userID: String)
    case dismiss
}

// MARK: - View ↔ ViewModel state

/// One tool's row.
struct AgentSheetTool: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: KeyPath<CompoundIcons, Image>
    /// On, but the catalogue says it can't fire here: the row offers only turning it off.
    var isUnavailable = false
}

/// What stands in an own agent's group with no tools yet (board 4).
enum AgentSheetQuickAdd: Equatable {
    /// It has tools, so "Add a tool" stands there.
    case none
    /// The catalogue is on its way: the rows hold their place.
    case loading
    /// Rows straight to the form; `hasMore` adds "All tools".
    case kinds([AgentToolKind], hasMore: Bool)
    /// The catalogue couldn't be read, so nothing says what fires here.
    case failed
}

/// An agent and its tools.
struct AgentSheetGroup: Equatable, Identifiable {
    let agent: AgentSummary
    /// "Bohdan's agent", under someone else's agent.
    var ownerLine: String?
    let tools: [AgentSheetTool]
    var quickAdd = AgentSheetQuickAdd.none
    /// The owner's own chat with the agent is theirs with it: the agent stays.
    var canRemoveFromChat = false
    
    var id: String {
        agent.id
    }
}

enum AgentSheetListState: Equatable {
    /// `GET /rooms/:room_id/tools` in flight.
    case loading
    /// The person's own agents (editable) and other participants' agents with tools (read-only). Brief 0043 P4:
    /// everyone sees the room's full tool picture, each edits only their own.
    case loaded(mine: [AgentSheetGroup], others: [AgentSheetGroup])
    /// The read failed: Retry, never "no tools".
    case failed
}

struct AgentSheetScreenViewState: BindableState {
    /// The chat's name, under the title.
    let roomName: String?
    var listState: AgentSheetListState = .loading
    /// The agent on its way out of the chat.
    var removingAgentID: String?
    /// The sync's state at the top while the stream is not live (decision 289).
    var syncStatus: PlatformSyncStatus?
    var bindings = AgentSheetScreenViewStateBindings()
}

struct AgentSheetScreenViewStateBindings {
    var alertInfo: AlertInfo<AgentSheetScreenAlertType>?
}

enum AgentSheetScreenAlertType: Hashable {
    case confirmRemove
    case removeFailed
    case turnOffFailed
    /// A tool whose kind, trigger or scope this build does not know.
    case needsUpdate
    /// A listed tool that can't fire for this agent here.
    case unavailable
}

// MARK: - View → ViewModel actions

enum AgentSheetScreenViewAction {
    /// Retry after a failed read of the room's tools.
    case retry
    /// Retry after a failed read of an agent's catalogue.
    case retryCatalog(agentID: String)
    case selectTool(agentID: String, toolID: String)
    case addTool(agentID: String)
    case addToolOfKind(AgentToolKind, agentID: String)
    case viewProfile(agentID: String)
    case removeAgent(agentID: String)
    case addAgent
    case done
}
