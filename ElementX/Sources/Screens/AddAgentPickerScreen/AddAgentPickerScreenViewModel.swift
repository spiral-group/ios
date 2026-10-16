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

typealias AddAgentPickerScreenViewModelType = StateStoreViewModelV2<AddAgentPickerScreenViewState, AddAgentPickerScreenViewAction>

/// Drives `AddAgentPickerScreen`. Lists the agents of every space the
/// caller may act for — their Personal space and each company they own
/// (`GET /me/agent-spaces`, then `GET /agent-spaces/:id`) — one section per
/// space, and crosses them with the room's agents (`GET /rooms/:id/tools`):
/// those already in the room are non-addable (badge). Tapping an addable
/// agent invites it via `roomProxy.invite`; the backend auto-accepts the
/// invite of an agent the inviter acts for (ADR-0017 — invite, never a
/// client force-join), so it joins almost immediately.
class AddAgentPickerScreenViewModel: AddAgentPickerScreenViewModelType, AddAgentPickerScreenViewModelProtocol {
    private let roomID: String
    private let roomProxy: JoinedRoomProxyProtocol
    private let agentPlatformService: any RoomToolsServiceProtocol

    private let actionsSubject: PassthroughSubject<AddAgentPickerScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AddAgentPickerScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(roomID: String,
         roomProxy: JoinedRoomProxyProtocol,
         agentPlatformService: any RoomToolsServiceProtocol) {
        self.roomID = roomID
        self.roomProxy = roomProxy
        self.agentPlatformService = agentPlatformService
        super.init(initialViewState: AddAgentPickerScreenViewState())
    }

    // MARK: - Public

    override func process(viewAction: AddAgentPickerScreenViewAction) {
        MXLog.info("AddAgentPickerScreenViewModel received view action: \(viewAction)")

        switch viewAction {
        case .appeared:
            if case .loaded = state.listState { return }
            Task { await loadAgents() }
        case .retry:
            Task { await loadAgents() }
        case .invite(let id):
            Task { await invite(agentID: id) }
        case .done:
            actionsSubject.send(.dismiss)
        }
    }

    // MARK: - Private

    private func loadAgents() async {
        state.listState = .loading

        // Sequential: Swift 6.2 strict checking forbids `async let` child
        // tasks capturing the non-Sendable service existential, and a person
        // has a handful of spaces at most.
        guard let spaces = await loadSpaces() else {
            state.listState = .failed
            return
        }

        // In-room MXIDs — a failed room fetch degrades to "none in room"
        // (the invite is idempotent, so worst case is a redundant invite).
        let inRoomMXIDs: Set<String>
        if case .success(let room) = await agentPlatformService.fetchRoomTools(roomID: roomID) {
            inRoomMXIDs = Set(room.agents.map(\.matrixUserID))
        } else {
            inRoomMXIDs = []
        }

        let sections = spaces.compactMap { space -> AddAgentSection? in
            let agents = space.agents
                .filter { $0.lifecycleState != "archived" }
                .map { Self.item(for: $0, isInRoom: inRoomMXIDs.contains($0.matrixUserID)) }
            guard !agents.isEmpty else { return nil }
            return AddAgentSection(id: space.orgID,
                                   title: space.displayName,
                                   agents: agents)
        }
        state.listState = .loaded(sections: sections)
        MXLog.info("AddAgentPicker: \(sections.map(\.agents.count).reduce(0, +)) agent(s) in \(sections.count) space(s), \(inRoomMXIDs.count) already in room")
    }

    /// Every space with agents, in the directory's order (Personal first).
    /// `nil` when any read fails: a space that couldn't be read is not a
    /// space without agents.
    private func loadSpaces() async -> [AgentSpaceDetail]? {
        guard case .success(let directory) = await agentPlatformService.listMyAgentSpaces() else {
            MXLog.error("AddAgentPicker: failed to list my agent spaces")
            return nil
        }
        var spaces: [AgentSpaceDetail] = []
        for space in directory.spaces where space.agentCount > 0 {
            guard case .success(let detail) = await agentPlatformService.fetchAgentSpace(orgID: space.orgID) else {
                MXLog.error("AddAgentPicker: failed to read space \(space.orgID)")
                return nil
            }
            spaces.append(detail)
        }
        return spaces
    }

    private static func item(for card: AgentSpaceAgentCard, isInRoom: Bool) -> AddAgentItem {
        // The agent's own name, not its login title-cased: deriving one from
        // the MXID made this picker disagree with every other surface about
        // what the same agent is called.
        let name = card.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return AddAgentItem(agentID: card.agentID,
                            matrixUserID: card.matrixUserID,
                            displayName: name.isEmpty ? AgentSummary.displayName(fromMatrixUserID: card.matrixUserID) : name,
                            avatarURL: card.avatarMXC.flatMap(URL.init(string:)),
                            isInRoom: isInRoom)
    }

    private func invite(agentID: String) async {
        guard let agent = state.agents.first(where: { $0.id == agentID }), !agent.isInRoom else { return }
        state.invitingAgentID = agentID
        defer { state.invitingAgentID = nil }

        switch await roomProxy.invite(userID: agent.matrixUserID) {
        case .success:
            MXLog.info("AddAgentPicker: invited \(agent.matrixUserID) — the backend auto-joins it")
            actionsSubject.send(.invited(agent))
        case .failure(let error):
            MXLog.error("AddAgentPicker: failed to invite \(agent.matrixUserID): \(error)")
            state.bindings.alertInfo = AlertInfo(id: .inviteFailed,
                                                 title: L10n.commonError,
                                                 message: L10n.errorUnknown)
        }
    }
}
