//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `RoomMembersFlowCoordinator.swift`.
// A child flow coordinator for a chat's tools, reached from the composer "+",
// the in-chat active-tools banner and the chat's page: one screen, then a tool's
// form, its read-only page or the kinds to add (question 359, item 12). Modelled
// on `RoomMembersFlowCoordinator`: it owns an internal `StateMachine`, shares the
// parent's `NavigationStackCoordinator`, pushes each screen via its own events,
// and bubbles `.finished` up so the parent can restore its previous state +
// refresh the banner. Screen coordinators are NEVER `start()`ed manually — the
// navigation stack starts them on push; only this flow coordinator gets `start()`.
//

import Combine
import SwiftState
import SwiftUI

enum AgentToolsFlowCoordinatorAction {
    /// The flow finished — the parent restores its state + refreshes the banner.
    case finished
    /// The "…" menu's profile: the sheet is closed, and the parent shows it.
    case presentProfile(userID: String)
}

final class AgentToolsFlowCoordinator: FlowCoordinatorProtocol {
    /// The flow's states + events + transition table live in the standalone
    /// `AgentToolsFlowStateMachine`; this coordinator owns the side-effects
    /// (presenting screens) via its transition handler.
    typealias Event = AgentToolsFlowStateMachine.Event

    private let roomID: String
    private let roomProxy: JoinedRoomProxyProtocol
    private let agentPlatformService: AgentPlatformServiceProtocol
    /// Platform sync (decision 289): the screens render from it.
    private let agentsStore: AgentsStore
    /// The room's navigation stack — the flow presents its sheet on this.
    private let navigationStackCoordinator: NavigationStackCoordinator
    /// The sheet's OWN navigation stack — every screen of the flow is its root
    /// or a push inside it, so the whole flow lives in one sheet.
    private let sheetStackCoordinator = NavigationStackCoordinator()
    private let flowParameters: CommonFlowParameters

    private let stateMachine: AgentToolsFlowStateMachine
    private var cancellables = Set<AnyCancellable>()

    /// The agents the sheet opened something for. States reference them by `agentID`.
    private var resolvedAgents: [AgentSummary] = []
    /// The tool a pending EDIT form seeds from, keyed by `toolID`. Kept out of
    /// `State`, which must be `Hashable`; `armTool` carries the `editingToolID`.
    private var pendingEdit: [String: ActiveToolDetail] = [:]
    /// The tool the read-only page is about to show.
    private var pendingToolDetail: ToolDetail?

    /// The form on the stack — kept so the pickers can feed their selection back.
    private weak var armToolCoordinator: ArmToolScreenCoordinator?
    /// The root — read again after an add-agent invite or a form.
    private weak var agentSheetCoordinator: AgentSheetScreenCoordinator?

    private func agent(for id: String) -> AgentSummary? {
        resolvedAgents.first { $0.agentID == id }
    }

    /// Cache an agent so the presenters can look it up by id.
    private func rememberAgent(_ summary: AgentSummary) {
        guard !resolvedAgents.contains(where: { $0.agentID == summary.agentID }) else { return }
        resolvedAgents.append(summary)
    }

    private let actionsSubject: PassthroughSubject<AgentToolsFlowCoordinatorAction, Never> = .init()
    var actions: AnyPublisher<AgentToolsFlowCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(roomID: String,
         roomProxy: JoinedRoomProxyProtocol,
         agentPlatformService: AgentPlatformServiceProtocol,
         agentsStore: AgentsStore,
         navigationStackCoordinator: NavigationStackCoordinator,
         flowParameters: CommonFlowParameters) {
        self.roomID = roomID
        self.roomProxy = roomProxy
        self.agentPlatformService = agentPlatformService
        self.agentsStore = agentsStore
        self.navigationStackCoordinator = navigationStackCoordinator
        self.flowParameters = flowParameters

        stateMachine = flowParameters.stateMachineFactory.makeAgentToolsFlowStateMachine(state: .initial)
        configureStateMachine()
    }

    func start(animated: Bool) {
        stateMachine.processEvent(.presentAgentSheet)
    }

    func handleAppRoute(_ appRoute: AppRoute, animated: Bool) {
        // No deep-link entry points into the agent-tools flow.
    }

    func clearRoute(animated: Bool) {
        navigationStackCoordinator.setSheetCoordinator(nil, animated: animated)
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

            case (.addAgentPicker, .presentAddTool(let agentID), .addTool):
                // Reached from the add-agent picker after an invite: pop the
                // picker (without firing its dismissed event — we're replacing
                // it, not returning) so the kinds sit on the sheet root.
                sheetStackCoordinator.pop()
                presentAddTool(agentID: agentID)
            case (_, .presentAddTool(let agentID), .addTool):
                presentAddTool(agentID: agentID)
            case (.addTool, .dismissedAddTool, _):
                break

            case (_, .presentArmTool(let agentID, let kind, let editingToolID), .armTool):
                presentArmTool(agentID: agentID, kind: kind, editingToolID: editingToolID)
            case (.armTool, .dismissedArmTool, _):
                armToolCoordinator = nil
                // Call translation stores as it changes: its list row is read again on the way back.
                agentSheetCoordinator?.reload()

            case (_, .presentToolDetail, .toolDetail):
                presentToolDetail()
            case (.toolDetail, .dismissedToolDetail, _):
                break

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

    /// Push `coordinator` onto the sheet stack; its swipe/back dismissal fires
    /// `dismissEvent` so the state machine returns to the previous state.
    private func pushScreen(_ coordinator: any CoordinatorProtocol, onDismissed dismissEvent: Event) {
        sheetStackCoordinator.push(coordinator) { [weak self] in
            self?.stateMachine.processEvent(dismissEvent)
        }
    }

    /// The one screen as the sheet's root, presented on the room. The
    /// interactive-dismiss completion bubbles `.finished` so the parent restores its state.
    private func presentAgentSheet() {
        let coordinator = AgentSheetScreenCoordinator(parameters: .init(roomID: roomID,
                                                                        roomProxy: roomProxy,
                                                                        store: agentsStore,
                                                                        agentPlatformService: agentPlatformService,
                                                                        clientProxy: flowParameters.userSession.clientProxy,
                                                                        mediaProvider: flowParameters.userSession.mediaProvider))
        agentSheetCoordinator = coordinator

        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .addTool(let agent):
                rememberAgent(agent)
                stateMachine.processEvent(.presentAddTool(agentID: agent.agentID))
            case .addToolOfKind(let kind, let agent):
                rememberAgent(agent)
                stateMachine.processEvent(.presentArmTool(agentID: agent.agentID, kind: kind, editingToolID: nil))
            case .editTool(let detail, let agent):
                guard let kind = detail.kind else { return }
                rememberAgent(agent)
                pendingEdit[detail.toolID] = detail
                stateMachine.processEvent(.presentArmTool(agentID: agent.agentID, kind: kind, editingToolID: detail.toolID))
            case .viewTool(let detail):
                pendingToolDetail = detail
                stateMachine.processEvent(.presentToolDetail)
            case .addAgent:
                stateMachine.processEvent(.presentAddAgentPicker)
            case .viewProfile(let userID):
                // The profile is the room's to show, once the sheet is gone.
                navigationStackCoordinator.setSheetCoordinator(nil)
                actionsSubject.send(.presentProfile(userID: userID))
            case .dismiss:
                navigationStackCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)

        sheetStackCoordinator.setRootCoordinator(coordinator)
        navigationStackCoordinator.setSheetCoordinator(sheetStackCoordinator) { [weak self] in
            self?.actionsSubject.send(.finished)
        }
    }

    private func presentAddAgentPicker() {
        let coordinator = AddAgentPickerScreenCoordinator(parameters: .init(roomID: roomID,
                                                                            roomProxy: roomProxy,
                                                                            store: agentsStore,
                                                                            mediaProvider: flowParameters.userSession.mediaProvider))

        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .invited(let item):
                // We hold the new agent's id + name from the picker, so open
                // its kinds directly (it has no tools: it just joined) instead
                // of bouncing back to the sheet and racing the backend
                // auto-join. The presenter pops the picker so back → sheet.
                rememberAgent(.justJoined(agentID: item.agentID,
                                          matrixUserID: item.matrixUserID,
                                          displayName: item.displayName))
                agentSheetCoordinator?.reload() // so the sheet shows it on back
                stateMachine.processEvent(.presentAddTool(agentID: item.agentID))
            case .dismiss:
                sheetStackCoordinator.pop()
            }
        }
        .store(in: &cancellables)

        pushScreen(coordinator, onDismissed: .dismissedAddAgentPicker)
    }

    private func presentAddTool(agentID: String) {
        guard let agent = agent(for: agentID) else { return }
        let coordinator = AddToolScreenCoordinator(parameters: .init(roomID: roomID,
                                                                     agentID: agent.agentID,
                                                                     agentDisplayName: agent.displayName,
                                                                     store: agentsStore))

        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .selectKind(let kind):
                stateMachine.processEvent(.presentArmTool(agentID: agentID, kind: kind, editingToolID: nil))
            }
        }
        .store(in: &cancellables)

        pushScreen(coordinator, onDismissed: .dismissedAddTool)
    }

    private func presentArmTool(agentID: String, kind: AgentToolKind, editingToolID: String?) {
        guard let agent = agent(for: agentID) else { return }
        // Call translation is personal (ADR-0094 D9, row 14): its own screen, which stores every change at once.
        guard kind != .liveTranslate else {
            if let editingToolID {
                pendingEdit[editingToolID] = nil
            }
            let coordinator = CallTranslationToolScreenCoordinator(parameters: .init(roomID: roomID,
                                                                                     agentID: agent.agentID,
                                                                                     agentDisplayName: agent.displayName,
                                                                                     agentPlatformService: agentPlatformService))
            pushScreen(coordinator, onDismissed: .dismissedArmTool)
            return
        }
        let mode: ArmToolScreenCoordinatorParameters.Mode = if let editingToolID, let detail = pendingEdit.removeValue(forKey: editingToolID) {
            .edit(detail)
        } else {
            .create(kind)
        }
        guard let coordinator = ArmToolScreenCoordinator(parameters: .init(roomID: roomID,
                                                                           agentID: agent.agentID,
                                                                           agentDisplayName: agent.displayName,
                                                                           mode: mode,
                                                                           agentPlatformService: agentPlatformService,
                                                                           store: agentsStore)) else { return }
        armToolCoordinator = coordinator

        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .finished:
                // Back on the one screen, where the change shows. The pops fire the dismissed events, the form's first.
                sheetStackCoordinator.popToRoot()
                agentSheetCoordinator?.reload()
            case .selectMembers(let current):
                stateMachine.processEvent(.presentMemberPicker(current: current))
            case .selectLanguage(let languages, let current):
                stateMachine.processEvent(.presentLanguagePicker(languages: languages, current: current))
            }
        }
        .store(in: &cancellables)

        pushScreen(coordinator, onDismissed: .dismissedArmTool)
    }

    private func presentToolDetail() {
        guard let detail = pendingToolDetail else { return }
        pendingToolDetail = nil
        let coordinator = ToolDetailScreenCoordinator(parameters: .init(detail: detail,
                                                                        mediaProvider: flowParameters.userSession.mediaProvider))
        pushScreen(coordinator, onDismissed: .dismissedToolDetail)
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
}
