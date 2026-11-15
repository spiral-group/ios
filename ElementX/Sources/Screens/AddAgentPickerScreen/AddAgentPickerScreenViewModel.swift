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
/// caller may act for — their Personal space and each company they own —
/// one section per space, from the session's store, so a person who has
/// opened anything sees the list at once. Crosses them with the room's
/// agents: those already in the room are non-addable (badge). Tapping an
/// addable agent invites it via `roomProxy.invite`; the backend auto-accepts
/// the invite of an agent the inviter acts for (ADR-0017 — invite, never a
/// client force-join), so it joins almost immediately.
class AddAgentPickerScreenViewModel: AddAgentPickerScreenViewModelType, AddAgentPickerScreenViewModelProtocol {
    private let roomID: String
    private let roomProxy: JoinedRoomProxyProtocol
    private let store: AgentsStore
    private var hasReadMembers = false

    private var roomTools: AgentsResource {
        .roomTools(roomID: roomID)
    }

    private let actionsSubject: PassthroughSubject<AddAgentPickerScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AddAgentPickerScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(roomID: String,
         roomProxy: JoinedRoomProxyProtocol,
         store: AgentsStore) {
        self.roomID = roomID
        self.roomProxy = roomProxy
        self.store = store
        super.init(initialViewState: AddAgentPickerScreenViewState())

        render()
        store.observe { [weak self] in
            guard let self else { return false }
            render()
            return true
        }
        store.show(.spaces, by: self)
        store.show(roomTools, by: self)
        // Others' agents never come on this owner's stream: what is shown is read again as the picker opens.
        store.refresh(roomTools)
        roomProxy.membersPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)
        Task { await readMembers() }
    }

    isolated deinit {
        store.stopShowing(.spaces, by: self)
        store.stopShowing(roomTools, by: self)
    }

    // MARK: - Public

    override func process(viewAction: AddAgentPickerScreenViewAction) {
        MXLog.info("AddAgentPickerScreenViewModel received view action: \(viewAction)")

        switch viewAction {
        case .retry:
            retry()
        case .invite(let id):
            Task { await invite(agentID: id) }
        case .done:
            actionsSubject.send(.dismiss)
        }
    }

    // MARK: - Private

    private func readMembers() async {
        await roomProxy.updateMembers()
        hasReadMembers = true
        render()
    }

    private func retry() {
        Task { await store.reread(.spaces) }
        Task { await store.reread(roomTools) }
        Task { await readMembers() }
    }

    private func render() {
        let listState = listState()
        if state.listState != listState {
            state.listState = listState
        }
        let isRoomRead = if case .loading = store.readState(roomTools, \.roomTools) { false } else { hasReadMembers }
        if state.isRoomRead != isRoomRead {
            state.isRoomRead = isRoomRead
        }
    }

    private func listState() -> AddAgentPickerListState {
        switch store.readState(.spaces, \.spaces) {
        case .loading:
            return .loading
        case .failed:
            return .failed
        case .loaded(let spaces):
            // A space that couldn't be read is not a space without agents.
            let listed = spaces.directory.spaces.filter { $0.agentCount > 0 }
            let details = listed.compactMap { spaces.details[$0.orgID] }
            guard details.count == listed.count, let inRoomMXIDs = inRoomMXIDs() else { return .failed }
            return .loaded(sections: details.compactMap { space in
                let agents = space.agents
                    .filter { $0.lifecycleState != "archived" }
                    .map { Self.item(for: $0, isInRoom: inRoomMXIDs.contains($0.matrixUserID)) }
                return agents.isEmpty ? nil : AddAgentSection(id: space.orgID, title: space.displayName, agents: agents)
            })
        }
    }

    /// Who is in the chat: the room's own members, joined or invited, and the agents the server lists, which
    /// are joined ones only. A failed server read leaves the room's list; `nil` when there is no list at all.
    private func inRoomMXIDs() -> Set<String>? {
        let members = Set(roomProxy.membersPublisher.value.filter { $0.membership == .join || $0.membership == .invite }.map(\.userID))
        switch store.readState(roomTools, \.roomTools) {
        case .loaded(let room):
            return members.union(room.agents.map(\.matrixUserID))
        case .failed:
            return members.isEmpty && hasReadMembers ? nil : members
        case .loading:
            return members
        }
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
        // What may already be in the chat is not offered: an invite waits for this opening's read of the room.
        guard state.isRoomRead, let agent = state.agents.first(where: { $0.id == agentID }), !agent.isInRoom else { return }
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
