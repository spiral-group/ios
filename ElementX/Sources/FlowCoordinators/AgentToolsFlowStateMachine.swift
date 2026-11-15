//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: the standalone state machine for the agent-tools flow
// (Brief 0035/0036 / ADR-0048), extracted from `AgentToolsFlowCoordinator`
// so the transition table lives in one testable place (mirrors
// `ChatsTabFlowCoordinatorStateMachine`). The coordinator owns the
// side-effects (presenting screens) via `addTransitionHandler`; this type
// owns only the pure `(fromState, event) → toState` routing.
//

import Combine
import Foundation
import SwiftState

class AgentToolsFlowStateMachine {
    /// State carries only `Hashable` identifiers (mirroring
    /// `RoomMembersFlowCoordinator`, whose states hold a bare `userID`). The
    /// heavier values — the resolved agents and the capability being armed —
    /// live in the coordinator's caches and are looked up by id.
    indirect enum State: StateType {
        /// The flow hasn't started.
        case initial
        /// A chat's tools: every agent in the chat with its tools, and "Add agent".
        case agentSheet
        /// The "Add agent" picker (invite one of the caller's other agents).
        case addAgentPicker(previousState: State)
        /// The kinds of tool an own agent can take here.
        case addTool(agentID: String, previousState: State)
        /// The form. `editingToolID` non-nil = editing an existing tool (seeded
        /// from `pendingEdit`); nil = creating.
        case armTool(agentID: String, kind: AgentToolKind, editingToolID: String?, previousState: State)
        /// Someone else's tool, read-only.
        case toolDetail(previousState: State)
        /// The room-member multi-select for a member-carrying scope.
        case memberPicker(previousState: State)
        /// The shared language picker (target language for a translate tool).
        case languagePicker(previousState: State)
    }

    enum Event: EventType {
        case presentAgentSheet
        case presentAddAgentPicker
        case dismissedAddAgentPicker
        case presentAddTool(agentID: String)
        case dismissedAddTool

        case presentArmTool(agentID: String, kind: AgentToolKind, editingToolID: String?)
        case dismissedArmTool

        case presentToolDetail
        case dismissedToolDetail

        case presentMemberPicker(current: [String])
        case dismissedMemberPicker

        case presentLanguagePicker(languages: [AgentLanguage], current: String)
        case dismissedLanguagePicker
    }

    private let stateMachine: StateMachine<State, Event>

    var state: State {
        stateMachine.state
    }

    init(state: State = .initial) {
        stateMachine = StateMachine(state: state)
        configure()
    }

    private func configure() {
        stateMachine.addRouteMapping { event, fromState, _ in
            switch (fromState, event) {
            case (.initial, .presentAgentSheet):
                return .agentSheet

            case (.agentSheet, .presentAddAgentPicker):
                return .addAgentPicker(previousState: fromState)
            case (.addAgentPicker(let previousState), .dismissedAddAgentPicker):
                return previousState

            // After an add-agent invite: skip the (popped) picker so the new
            // agent's kinds sit directly on the sheet — back → sheet.
            case (.addAgentPicker(let previousState), .presentAddTool(let agentID)):
                return .addTool(agentID: agentID, previousState: previousState)
            case (.agentSheet, .presentAddTool(let agentID)):
                return .addTool(agentID: agentID, previousState: fromState)
            case (.addTool(_, let previousState), .dismissedAddTool):
                return previousState

            // The form opens from a kind, or from the sheet: a tool, or a quick row.
            case (.addTool, .presentArmTool(let agentID, let kind, let editingToolID)),
                 (.agentSheet, .presentArmTool(let agentID, let kind, let editingToolID)):
                return .armTool(agentID: agentID, kind: kind, editingToolID: editingToolID, previousState: fromState)
            case (.armTool(_, _, _, let previousState), .dismissedArmTool):
                return previousState

            case (.agentSheet, .presentToolDetail):
                return .toolDetail(previousState: fromState)
            case (.toolDetail(let previousState), .dismissedToolDetail):
                return previousState

            case (.armTool, .presentMemberPicker):
                return .memberPicker(previousState: fromState)
            case (.memberPicker(let previousState), .dismissedMemberPicker):
                return previousState

            case (.armTool, .presentLanguagePicker):
                return .languagePicker(previousState: fromState)
            case (.languagePicker(let previousState), .dismissedLanguagePicker):
                return previousState

            default:
                return nil
            }
        }
    }

    /// Attempt to move the machine to another state through an event.
    func processEvent(_ event: Event) {
        stateMachine.tryEvent(event)
    }

    /// Register a callback for every transition (the coordinator presents
    /// screens here).
    func addTransitionHandler(_ handler: @escaping StateMachine<State, Event>.Handler) {
        stateMachine.addAnyHandler(.any => .any, handler: handler)
    }
}
