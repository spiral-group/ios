//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `RoomMembersFlowCoordinator.swift`.
// A child flow coordinator for the agent-tools surface
// reached from the composer "+" Agent item and the in-chat active-tools
// banner. Modelled on `RoomMembersFlowCoordinator`: it owns an internal
// `StateMachine`, shares the parent's `NavigationStackCoordinator`, pushes
// each screen via its own events, and bubbles `.finished` up so the parent
// can restore its previous state + refresh the banner. Screen coordinators
// are NEVER `start()`ed manually — the navigation stack starts them on
// push; only this flow coordinator gets `start()`.
//

import Combine
import SwiftState
import SwiftUI

enum AgentToolsFlowCoordinatorAction {
    /// The flow finished — the parent restores its state + refreshes the banner.
    case finished
}

/// Where the flow was entered from — drives whether it opens the EDIT surface
/// (the active-tools list) or the CREATE surface (the capabilities catalog).
enum AgentToolsFlowEntryPoint: Hashable {
    /// The in-chat banner → the active-tools list (edit existing tools).
    case banner
    /// The composer "+" Agent item → the capabilities catalog (create a tool).
    case composer
}

final class AgentToolsFlowCoordinator: FlowCoordinatorProtocol {
    /// The flow's states + events + transition table live in the standalone
    /// `AgentToolsFlowStateMachine`; this coordinator owns the side-effects
    /// (presenting screens) via its transition handler.
    typealias Event = AgentToolsFlowStateMachine.Event

    private let roomID: String
    private let roomProxy: JoinedRoomProxyProtocol
    private let agentPlatformService: AgentPlatformServiceProtocol
    /// The room's navigation stack — the flow presents its sheet on this.
    private let navigationStackCoordinator: NavigationStackCoordinator
    /// The sheet's OWN navigation stack — every agent-tools screen (picker /
    /// capabilities / arm / member) is a root/push inside this, so the whole
    /// flow lives in one sheet.
    private let sheetStackCoordinator = NavigationStackCoordinator()
    private let flowParameters: CommonFlowParameters

    private let stateMachine: AgentToolsFlowStateMachine
    private var cancellables = Set<AnyCancellable>()

    /// The caller's own agents, resolved once at flow start. States reference
    /// them by `agentID`.
    private var resolvedAgents: [AgentSummary] = []
    /// The active tool a pending arm/edit form seeds from, keyed by
    /// `(agentID, capability)`. Kept out of `State` (which must be `Hashable`).
    private var pendingArm: [String: ActiveCapabilityTool] = [:]
    /// The tool a pending EDIT form seeds from, keyed by `toolID`. Kept out of
    /// `State`; `armTool` carries the `editingToolID` to look it up.
    private var pendingEdit: [String: ActiveToolDetail] = [:]
    /// What an agent does in this chat, read before its agent-in-chat screen
    /// opens, keyed by `agentID`. Kept out of `State` like the two above.
    private var pendingRoomEntries: [String: AgentRoomEntry] = [:]
    /// Whether the flow was entered from the banner (edit) or composer (create).
    private let entryPoint: AgentToolsFlowEntryPoint
    /// The tools-list coordinator currently on the stack — refreshed after an
    /// edit so the rows reflect the change.
    private weak var toolsListCoordinator: AgentToolsListScreenCoordinator?

    /// The arm-tool coordinator currently on the stack — kept so the member
    /// picker can feed its selection back into the open arm form.
    private weak var armToolCoordinator: ArmToolScreenCoordinator?
    /// The capabilities coordinator currently on the stack — kept so an
    /// arm/disable can refresh the on/off rows behind the popped form.
    private weak var capabilitiesCoordinator: AgentCapabilitiesScreenCoordinator?
    /// The agent-sheet coordinator (composer root) — refreshed after an
    /// add-agent invite so the new agent appears.
    private weak var agentSheetCoordinator: AgentSheetScreenCoordinator?
    /// The agent-in-chat screen — refreshed when the catalog or a form pops
    /// back to it.
    private weak var agentInRoomCoordinator: AgentInRoomScreenCoordinator?

    private func agent(for id: String) -> AgentSummary? {
        resolvedAgents.first { $0.agentID == id }
    }

    /// Cache an agent (from the sheet's selection or a fresh add) so the
    /// capabilities / arm presenters can look it up by id.
    private func rememberAgent(_ summary: AgentSummary) {
        guard !resolvedAgents.contains(where: { $0.agentID == summary.agentID }) else { return }
        resolvedAgents.append(summary)
    }

    private func armKey(_ agentID: String, _ capability: AgentCapability) -> String {
        "\(agentID)|\(capability.rawValue)"
    }

    private let actionsSubject: PassthroughSubject<AgentToolsFlowCoordinatorAction, Never> = .init()
    var actions: AnyPublisher<AgentToolsFlowCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(roomID: String,
         entryPoint: AgentToolsFlowEntryPoint,
         roomProxy: JoinedRoomProxyProtocol,
         agentPlatformService: AgentPlatformServiceProtocol,
         navigationStackCoordinator: NavigationStackCoordinator,
         flowParameters: CommonFlowParameters) {
        self.roomID = roomID
        self.entryPoint = entryPoint
        self.roomProxy = roomProxy
        self.agentPlatformService = agentPlatformService
        self.navigationStackCoordinator = navigationStackCoordinator
        self.flowParameters = flowParameters

        stateMachine = flowParameters.stateMachineFactory.makeAgentToolsFlowStateMachine(state: .initial)
        configureStateMachine()
    }

    func start(animated: Bool) {
        Task { await resolveAndPresent() }
    }

    func handleAppRoute(_ appRoute: AppRoute, animated: Bool) {
        // No deep-link entry points into the agent-tools flow.
    }

    func clearRoute(animated: Bool) {
        navigationStackCoordinator.setSheetCoordinator(nil, animated: animated)
    }

    // MARK: - Presentation resolution

    /// Entry depends on where the flow was opened from.
    ///
    /// - Composer "+" "Agents" → the **agent bottom-sheet** (room → agent →
    ///   tool): it owns its own fetch and renders the caller's agents (0/1/N)
    ///   as avatar rows + "Add agent". No pre-resolve needed here.
    /// - In-chat banner → resolve the caller's own agents and open the EDIT
    ///   surface (tools list; the picker first when there's more than one).
    private func resolveAndPresent() async {
        switch entryPoint {
        case .composer:
            stateMachine.processEvent(.presentAgentSheet)
        case .banner:
            await resolveBannerEntry()
        }
    }

    /// The banner edit path needs a concrete agent up front.
    private func resolveBannerEntry() async {
        let roomTools = await agentPlatformService.fetchRoomTools(roomID: roomID)

        guard case .success(let tools) = roomTools else {
            MXLog.info("AgentToolsFlowCoordinator: failed to read room tools for \(roomID)")
            flowParameters.userIndicatorController.submitIndicator(.init(title: L10n.errorUnknown))
            actionsSubject.send(.finished)
            return
        }

        let ownAgents = tools.agents.filter(\.isMine)
        guard !ownAgents.isEmpty else {
            // Brief 0043 P4: the banner may be showing OTHER
            // participants' tools (aggregate) — the caller has no agent
            // of their own here. Don't dead-end with an error; open the
            // agent sheet, which renders the read-only "other
            // participants" section + an "add your agent" CTA.
            MXLog.info("AgentToolsFlowCoordinator: no own agent in room \(roomID); presenting sheet")
            stateMachine.processEvent(.presentAgentSheet)
            return
        }

        resolvedAgents = ownAgents.map(AgentSummary.init(entry:))
        if ownAgents.count == 1 {
            stateMachine.processEvent(.presentToolsList(agentID: ownAgents[0].agentID))
        } else {
            stateMachine.processEvent(.presentAgentPicker)
        }
    }

    // MARK: - State machine

    private func configureStateMachine() {
        // The transition table lives in `AgentToolsFlowStateMachine`; here we
        // only react to transitions by presenting / tearing down screens.
        stateMachine.addTransitionHandler { [weak self] context in
            guard let self else { return }
            switch (context.fromState, context.event, context.toState) {
            case (.initial, .presentAgentSheet, .agentSheet):
                presentAgentSheet()

            case (_, .presentAddAgentPicker, .addAgentPicker):
                presentAddAgentPicker()
            case (.addAgentPicker, .dismissedAddAgentPicker, _):
                break

            case (.initial, .presentAgentPicker, .agentPicker):
                presentAgentPicker()

            case (_, .presentAgentInRoom(let agentID), .agentInRoom):
                presentAgentInRoom(agentID: agentID)
            case (.agentInRoom, .dismissedAgentInRoom, _):
                agentInRoomCoordinator = nil
                agentSheetCoordinator?.reload()

            case (_, .presentToolsList(let agentID), .toolsList):
                presentToolsList(agentID: agentID)
            case (.toolsList, .dismissedToolsList, _):
                toolsListCoordinator = nil

            case (.addAgentPicker, .presentCapabilities(let agentID), .capabilities):
                // Reached from the add-agent picker after an invite: pop the
                // picker (without firing its dismissed event — we're replacing
                // it, not returning) so capabilities sits on the sheet root.
                sheetStackCoordinator.pop()
                presentCapabilities(agentID: agentID)
            case (_, .presentCapabilities(let agentID), .capabilities):
                presentCapabilities(agentID: agentID)
            case (.capabilities, .dismissedCapabilities, _):
                capabilitiesCoordinator = nil
                // Back on the agent-sheet or the agent in this chat — refresh so
                // the tools reflect an arm/disable made in capabilities.
                agentSheetCoordinator?.reload()
                agentInRoomCoordinator?.reload()

            case (_, .presentArmTool(let agentID, let capability, let editingToolID), .armTool):
                presentArmTool(agentID: agentID, capability: capability, editingToolID: editingToolID)
            case (.armTool, .dismissedArmTool, _):
                armToolCoordinator = nil

            case (.armTool(let agentID, _, _, _), .presentMemberPicker(let current), .memberPicker):
                presentMemberPicker(agentID: agentID, current: current)
            case (.memberPicker, .dismissedMemberPicker, _):
                break

            case (_, .presentLanguagePicker(let languages, let current), .languagePicker):
                presentLanguagePicker(languages: languages, current: current)
            case (.languagePicker, .dismissedLanguagePicker, _):
                break

            default:
                fatalError("Unhandled transition: \(context.fromState) -> \(context.event)")
            }
        }
    }

    // MARK: - Presenters

    /// Present the sheet stack on the room (once, when the flow's first
    /// screen becomes the sheet root). The interactive-dismiss completion
    /// bubbles `.finished` so the parent restores its state.
    private func presentSheet() {
        navigationStackCoordinator.setSheetCoordinator(sheetStackCoordinator) { [weak self] in
            self?.actionsSubject.send(.finished)
        }
    }

    // MARK: - Presentation helpers

    /// Make `coordinator` the sheet's root and present the sheet on the room.
    private func presentAsRoot(_ coordinator: any CoordinatorProtocol) {
        sheetStackCoordinator.setRootCoordinator(coordinator)
        presentSheet()
    }

    /// Push `coordinator` onto the sheet stack; its swipe/back dismissal fires
    /// `dismissEvent` so the state machine returns to the previous state.
    private func pushScreen(_ coordinator: any CoordinatorProtocol, onDismissed dismissEvent: Event) {
        sheetStackCoordinator.push(coordinator) { [weak self] in
            self?.stateMachine.processEvent(dismissEvent)
        }
    }

    /// Root when this screen is the flow's first (`isSheetRoot`), otherwise a
    /// push whose dismissal fires `dismissEvent`.
    private func presentRootOrPush(_ coordinator: any CoordinatorProtocol, onDismissed dismissEvent: Event) {
        if isSheetRoot {
            presentAsRoot(coordinator)
        } else {
            pushScreen(coordinator, onDismissed: dismissEvent)
        }
    }

    private func presentAgentPicker() {
        let coordinator = AgentPickerScreenCoordinator(parameters: .init(agents: resolvedAgents.map(Self.pickerItem)))

        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .selectAgent(let item):
                // The picker is the banner (edit) path's multi-agent chooser →
                // open the agent's active-tools list.
                stateMachine.processEvent(.presentToolsList(agentID: item.agentID))
            case .dismiss:
                navigationStackCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)

        presentAsRoot(coordinator)
    }

    /// The composer entry: the agent bottom-sheet as the sheet ROOT.
    private func presentAgentSheet() {
        let coordinator = AgentSheetScreenCoordinator(parameters: .init(roomID: roomID,
                                                                        agentPlatformService: agentPlatformService,
                                                                        mediaProvider: flowParameters.userSession.mediaProvider))
        agentSheetCoordinator = coordinator

        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .selectAgent(let summary):
                // Cache the chosen agent so the presenters can look it up by id
                // (the sheet owns the fetch; the flow doesn't).
                rememberAgent(summary)
                Task { await self.openAgentInRoom(agentID: summary.agentID) }
            case .addAgent:
                stateMachine.processEvent(.presentAddAgentPicker)
            case .dismiss:
                navigationStackCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)

        presentAsRoot(coordinator)
    }

    /// An agent on the sheet opens what it does in this chat, the Agents
    /// tab's agent-in-chat screen. It needs the agent's entry for this chat;
    /// when that can't be read, or the chat isn't listed yet (the agent has
    /// only just joined), the catalog opens instead, so a tap always leads on.
    private func openAgentInRoom(agentID: String) async {
        guard case .agentSheet = stateMachine.state else { return }
        defer { agentSheetCoordinator?.finishOpeningAgent() }
        let roomsResult = await agentPlatformService.fetchAgentRooms(agentID: agentID)
        // The sheet may have moved on or closed while the fetch ran.
        guard case .agentSheet = stateMachine.state,
              navigationStackCoordinator.sheetCoordinator === sheetStackCoordinator else { return }
        if case .success(let rooms) = roomsResult,
           let entry = rooms.first(where: { $0.roomID == roomID }) {
            pendingRoomEntries[agentID] = entry
            stateMachine.processEvent(.presentAgentInRoom(agentID: agentID))
        } else {
            MXLog.info("AgentToolsFlowCoordinator: no entry for agent \(agentID) in \(roomID); opening the catalog")
            stateMachine.processEvent(.presentCapabilities(agentID: agentID))
        }
    }

    private func presentAgentInRoom(agentID: String) {
        guard let agent = agent(for: agentID), let entry = pendingRoomEntries.removeValue(forKey: agentID) else { return }
        let coordinator = AgentInRoomScreenCoordinator(parameters: .init(agent: .init(summary: agent),
                                                                         room: entry,
                                                                         agentPlatformService: agentPlatformService,
                                                                         clientProxy: flowParameters.userSession.clientProxy,
                                                                         mediaProvider: flowParameters.userSession.mediaProvider))
        agentInRoomCoordinator = coordinator

        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .removed:
                // The pop fires `.dismissedAgentInRoom`, which reloads the sheet.
                sheetStackCoordinator.pop()
            case .addTool:
                stateMachine.processEvent(.presentCapabilities(agentID: agentID))
            case .editTool(let detail):
                pendingEdit[detail.toolID] = detail
                stateMachine.processEvent(.presentArmTool(agentID: agentID, capability: detail.capability, editingToolID: detail.toolID))
            }
        }
        .store(in: &cancellables)

        pushScreen(coordinator, onDismissed: .dismissedAgentInRoom)
    }

    private func presentAddAgentPicker() {
        let coordinator = AddAgentPickerScreenCoordinator(parameters: .init(roomID: roomID,
                                                                            roomProxy: roomProxy,
                                                                            agentPlatformService: agentPlatformService,
                                                                            mediaProvider: flowParameters.userSession.mediaProvider))

        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .invited(let item):
                // We hold the new agent's id + name from the picker, so open
                // its capabilities directly (all Off — it just joined; a tool
                // can be armed straight away) instead of bouncing back to the
                // sheet and racing the backend auto-join. The presenter pops
                // the picker + pushes capabilities so back → sheet.
                rememberAgent(.justJoined(agentID: item.agentID,
                                          matrixUserID: item.matrixUserID,
                                          displayName: item.displayName))
                agentSheetCoordinator?.reload() // so the sheet shows it on back
                stateMachine.processEvent(.presentCapabilities(agentID: item.agentID))
            case .dismiss:
                sheetStackCoordinator.pop()
            }
        }
        .store(in: &cancellables)

        pushScreen(coordinator, onDismissed: .dismissedAddAgentPicker)
    }

    private func presentCapabilities(agentID: String) {
        guard let agent = agent(for: agentID) else { return }
        let coordinator = AgentCapabilitiesScreenCoordinator(parameters: .init(roomID: roomID,
                                                                               agentID: agent.agentID,
                                                                               agentDisplayName: agent.displayName,
                                                                               agentPlatformService: agentPlatformService,
                                                                               showsDoneButton: isSheetRoot))
        capabilitiesCoordinator = coordinator

        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .presentArmTool(let capability, let active):
                if let active {
                    pendingArm[armKey(agentID, capability)] = active
                }
                stateMachine.processEvent(.presentArmTool(agentID: agentID, capability: capability, editingToolID: nil))
            case .dismiss:
                navigationStackCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)

        // Single-agent from the composer: capabilities is the sheet ROOT.
        // Otherwise (multi-agent, or reached from the picker) it's pushed.
        presentRootOrPush(coordinator, onDismissed: .dismissedCapabilities)
    }

    private func presentToolsList(agentID: String) {
        guard let agent = agent(for: agentID) else { return }
        let coordinator = AgentToolsListScreenCoordinator(parameters: .init(roomID: roomID,
                                                                            agentID: agent.agentID,
                                                                            agentDisplayName: agent.displayName,
                                                                            agentPlatformService: agentPlatformService))
        toolsListCoordinator = coordinator

        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .editTool(let detail):
                pendingEdit[detail.toolID] = detail
                stateMachine.processEvent(.presentArmTool(agentID: agentID, capability: detail.capability, editingToolID: detail.toolID))
            case .addTool:
                stateMachine.processEvent(.presentCapabilities(agentID: agentID))
            case .dismiss:
                navigationStackCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)

        presentRootOrPush(coordinator, onDismissed: .dismissedToolsList)
    }

    private func presentArmTool(agentID: String, capability: AgentCapability, editingToolID: String?) {
        guard let agent = agent(for: agentID) else { return }
        let mode: ArmToolScreenCoordinatorParameters.Mode = {
            if let editingToolID, let detail = pendingEdit.removeValue(forKey: editingToolID) {
                return .edit(detail)
            }
            return .create(capability: capability, active: pendingArm.removeValue(forKey: armKey(agentID, capability)))
        }()
        let coordinator = ArmToolScreenCoordinator(parameters: .init(roomID: roomID,
                                                                     agentID: agent.agentID,
                                                                     agentDisplayName: agent.displayName,
                                                                     mode: mode,
                                                                     agentPlatformService: agentPlatformService))
        armToolCoordinator = coordinator

        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .finished:
                capabilitiesCoordinator?.refresh()
                toolsListCoordinator?.refresh()
                actionsSubject.send(.finished)
                navigationStackCoordinator.setSheetCoordinator(nil)
            case .selectMembers(let current):
                stateMachine.processEvent(.presentMemberPicker(current: current))
            case .selectLanguage(let languages, let current):
                stateMachine.processEvent(.presentLanguagePicker(languages: languages, current: current))
            }
        }
        .store(in: &cancellables)

        pushScreen(coordinator, onDismissed: .dismissedArmTool)
    }

    /// True when the screen being presented is the flow's first screen (the
    /// sheet root) — i.e. we came straight from `.initial`, not via the picker.
    private var isSheetRoot: Bool {
        switch stateMachine.state {
        case .toolsList(_, .initial), .capabilities(_, .initial):
            return true
        default:
            return false
        }
    }

    /// `agentID` is the agent whose arm form is open — taken from the
    /// transition's FROM state: by the time a handler runs, the machine is
    /// already in `.memberPicker`, which is why reading `stateMachine.state`
    /// here never found the agent (re-walk R4).
    private func presentMemberPicker(agentID: String, current: [String]) {
        let coordinator = ToolMemberPickerScreenCoordinator(parameters: .init(roomProxy: roomProxy,
                                                                              agentMatrixUserID: agent(for: agentID)?.matrixUserID,
                                                                              preselectedMemberIDs: current,
                                                                              mediaProvider: flowParameters.userSession.mediaProvider))

        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .confirm(let members):
                armToolCoordinator?.applyMemberSelection(members)
                sheetStackCoordinator.pop()
            }
        }
        .store(in: &cancellables)

        pushScreen(coordinator, onDismissed: .dismissedMemberPicker)
    }

    private func presentLanguagePicker(languages: [AgentLanguage], current: String) {
        let coordinator = LanguagePickerScreenCoordinator(parameters: .init(languages: languages, selectedCode: current))

        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .selected(let code):
                armToolCoordinator?.applyLanguageSelection(code)
                sheetStackCoordinator.pop()
            }
        }
        .store(in: &cancellables)

        pushScreen(coordinator, onDismissed: .dismissedLanguagePicker)
    }

    // MARK: - Helpers

    private static func pickerItem(_ agent: AgentSummary) -> AgentPickerItem {
        AgentPickerItem(agentID: agent.agentID,
                        matrixUserID: agent.matrixUserID,
                        displayName: agent.displayName,
                        activeToolCount: agent.activeToolCount)
    }
}
