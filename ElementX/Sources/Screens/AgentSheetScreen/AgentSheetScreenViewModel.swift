//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0035/0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenViewModel.swift`.
//

import Combine
import SwiftUI

typealias AgentSheetScreenViewModelType = StateStoreViewModelV2<AgentSheetScreenViewState, AgentSheetScreenViewAction>

/// Drives `AgentSheetScreen`. Pulls `GET /rooms/:room_id/tools` on
/// `.appeared` / `.retry` and projects the caller's own agent entries into
/// avatar rows with a one-line tool summary. A tap emits the chosen agent;
/// "Add agent" bubbles up so the coordinator can open the invite picker.
class AgentSheetScreenViewModel: AgentSheetScreenViewModelType, AgentSheetScreenViewModelProtocol {
    private let roomID: String
    private let agentPlatformService: any RoomToolsServiceProtocol

    private let actionsSubject: PassthroughSubject<AgentSheetScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentSheetScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(roomID: String, agentPlatformService: any RoomToolsServiceProtocol) {
        self.roomID = roomID
        self.agentPlatformService = agentPlatformService
        super.init(initialViewState: AgentSheetScreenViewState())
    }

    // MARK: - Public

    override func process(viewAction: AgentSheetScreenViewAction) {
        MXLog.info("AgentSheetScreenViewModel received view action: \(viewAction)")

        switch viewAction {
        case .appeared:
            if case .loaded = state.listState { return }
            Task { await loadAgents() }
        case .retry:
            Task { await loadAgents() }
        case .selectAgent(let id):
            // Only own agents are tappable (others render as read-only
            // rows) — defend against a stale tap regardless. A second tap
            // while one opens would push its screen over the first's.
            guard state.openingAgentID == nil,
                  let agent = state.agents.first(where: { $0.id == id }) else { return }
            state.openingAgentID = id
            actionsSubject.send(.selectAgent(agent))
        case .addAgent:
            actionsSubject.send(.addAgent)
        case .done:
            actionsSubject.send(.dismiss)
        }
    }

    /// Re-pull after an arm/disable or an add-agent invite so the rows +
    /// tool summaries reflect the change.
    func reload() {
        Task { await loadAgents() }
    }

    /// The tapped agent's screen opened, or it couldn't: taps count again.
    func finishOpeningAgent() {
        state.openingAgentID = nil
    }

    // MARK: - Private

    private func loadAgents() async {
        state.listState = .loading
        switch await agentPlatformService.fetchRoomTools(roomID: roomID) {
        case .success(let roomTools):
            let mine = AgentSummary.ownAgents(in: roomTools)
            let others = AgentSummary.otherAgents(in: roomTools)
            state.listState = .loaded(mine: mine, others: others)
            MXLog.info("AgentSheet: \(mine.count) own + \(others.count) other agent(s) in room \(roomID)")
        case .failure(let error):
            MXLog.error("AgentSheet: failed to load room tools: \(error)")
            state.listState = .failed
            state.bindings.alertInfo = AlertInfo(id: .loadFailed,
                                                 title: L10n.commonError,
                                                 message: L10n.errorUnknown,
                                                 primaryButton: .init(title: L10n.actionRetry) { [weak self] in
                                                     Task { await self?.loadAgents() }
                                                 },
                                                 secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
        }
    }
}
