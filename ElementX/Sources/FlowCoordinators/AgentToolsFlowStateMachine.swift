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
        /// The agent bottom-sheet (composer entry) — the caller's own agents
        /// in the room + "Add agent". The room → agent → tool root.
        case agentSheet
        /// The "Add agent" picker (invite one of the caller's other agents).
        case addAgentPicker(previousState: State)
        /// Choosing which of the caller's own agents to manage (>1 agent).
        case agentPicker
        /// One agent in this chat, from the sheet: its tools here, «Добавить
        /// инструмент» and «Убрать агента из чата» (the Agents tab's screen).
        case agentInRoom(agentID: String, previousState: State)
        /// The active-tools edit list for a resolved agent (banner entry).
        case toolsList(agentID: String, previousState: State)
        /// The capabilities catalog for a resolved agent (composer entry).
        case capabilities(agentID: String, previousState: State)
        /// The arm / edit form. `editingToolID` non-nil = editing an existing
        /// tool (seeded from `pendingEdit`); nil = creating.
        case armTool(agentID: String, capability: AgentCapability, editingToolID: String?, previousState: State)
        /// The room-member multi-select for a member-carrying scope.
        case memberPicker(previousState: State)
        /// The shared language picker (target language for a translate tool).
        case languagePicker(previousState: State)
    }

    enum Event: EventType {
        case presentAgentSheet
        case presentAddAgentPicker
        case dismissedAddAgentPicker
        case presentAgentPicker
        case presentAgentInRoom(agentID: String)
        case dismissedAgentInRoom
        case presentToolsList(agentID: String)
        case dismissedToolsList
        case presentCapabilities(agentID: String)
        case dismissedCapabilities

        case presentArmTool(agentID: String, capability: AgentCapability, editingToolID: String?)
        case dismissedArmTool

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

            case (.initial, .presentAgentPicker):
                return .agentPicker

            case (.agentSheet, .presentAgentInRoom(let agentID)):
                return .agentInRoom(agentID: agentID, previousState: fromState)
            case (.agentInRoom(_, let previousState), .dismissedAgentInRoom):
                return previousState

            case (_, .presentToolsList(let agentID)):
                return .toolsList(agentID: agentID, previousState: fromState)
            case (.toolsList(_, let previousState), .dismissedToolsList):
                return previousState

            // After an add-agent invite: skip the (popped) picker so the new
            // agent's capabilities sits directly on the sheet — back → sheet.
            case (.addAgentPicker(let previousState), .presentCapabilities(let agentID)):
                return .capabilities(agentID: agentID, previousState: previousState)
            case (_, .presentCapabilities(let agentID)):
                return .capabilities(agentID: agentID, previousState: fromState)
            case (.capabilities(_, let previousState), .dismissedCapabilities):
                return previousState

            // Arm/edit can be reached from the catalog (capabilities), the edit
            // list (toolsList) or a tool on the agent-in-chat screen.
            case (.capabilities(let agentID, _), .presentArmTool(_, let capability, let editingToolID)),
                 (.toolsList(let agentID, _), .presentArmTool(_, let capability, let editingToolID)),
                 (.agentInRoom(let agentID, _), .presentArmTool(_, let capability, let editingToolID)):
                return .armTool(agentID: agentID, capability: capability, editingToolID: editingToolID, previousState: fromState)
            case (.armTool(_, _, _, let previousState), .dismissedArmTool):
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
