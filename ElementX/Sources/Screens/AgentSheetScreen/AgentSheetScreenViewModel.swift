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

/// Drives `AgentSheetScreen`: the room's tools, grouped by agent, and what the
/// catalogue says of the person's own agents here.
///
/// AGENT-PLATFORM: platform sync (decision 289). The room's tools are the
/// session store's and are read again on `agent.tools` / `agent.rooms` for the
/// owner's own agents. Other people's agents in the room are no change for this
/// owner: they are read when the sheet shows (contract § 5).
class AgentSheetScreenViewModel: AgentSheetScreenViewModelType, AgentSheetScreenViewModelProtocol {
    private let roomID: String
    private let roomProxy: JoinedRoomProxyProtocol
    private let store: AgentsStore
    private let agentPlatformService: any AgentPlatformServiceProtocol
    private let clientProxy: any ClientProxyProtocol
    /// The own agents whose catalogue this screen shows.
    private var shownCatalogAgentIDs: Set<String> = []
    
    private let actionsSubject: PassthroughSubject<AgentSheetScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentSheetScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    private var resource: AgentsResource {
        .roomTools(roomID: roomID)
    }
    
    init(roomID: String,
         roomProxy: JoinedRoomProxyProtocol,
         store: AgentsStore,
         agentPlatformService: any AgentPlatformServiceProtocol,
         clientProxy: any ClientProxyProtocol) {
        self.roomID = roomID
        self.roomProxy = roomProxy
        self.store = store
        self.agentPlatformService = agentPlatformService
        self.clientProxy = clientProxy
        super.init(initialViewState: AgentSheetScreenViewState(roomName: roomProxy.infoPublisher.value.displayName))
        
        render()
        store.observe { [weak self] in
            guard let self else { return false }
            render()
            return true
        }
        store.show(resource, by: self)
        // The room's tools carry no avatars or owners' names: the card has an own agent's, the room's member anyone's.
        roomProxy.membersPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)
        Task { await roomProxy.updateMembers() }
        // Others' agents never come on this owner's stream: what is shown is read again as the sheet opens.
        if store.value(resource) != nil, !store.isStale(resource) {
            Task { await store.reread(resource) }
        }
    }
    
    isolated deinit {
        store.stopShowing(resource, by: self)
        for agentID in shownCatalogAgentIDs {
            store.stopShowing(catalogResource(agentID), by: self)
        }
    }
    
    // MARK: - Public
    
    override func process(viewAction: AgentSheetScreenViewAction) {
        MXLog.info("AgentSheetScreenViewModel received view action: \(viewAction)")
        
        switch viewAction {
        case .retry:
            Task { await store.reread(resource) }
        case .retryCatalog(let agentID):
            store.refresh(catalogResource(agentID))
            render()
        case .selectTool(let agentID, let toolID):
            selectTool(id: toolID, agentID: agentID)
        case .addTool(let agentID):
            guard let agent = ownAgent(id: agentID) else { return }
            actionsSubject.send(.addTool(summary(of: agent)))
        case .addToolOfKind(let kind, let agentID):
            guard let agent = ownAgent(id: agentID) else { return }
            actionsSubject.send(.addToolOfKind(kind, summary(of: agent)))
        case .viewProfile(let agentID):
            guard let agent = ownAgent(id: agentID) else { return }
            actionsSubject.send(.viewProfile(userID: agent.matrixUserID))
        case .removeAgent(let agentID):
            confirmRemove(agentID: agentID)
        case .addAgent:
            actionsSubject.send(.addAgent)
        case .done:
            actionsSubject.send(.dismiss)
        }
    }
    
    /// Read the room's tools now, after the person's own add-agent invite or arm/disable.
    func reload() {
        Task { await store.reread(resource) }
    }
    
    // MARK: - Tools
    
    /// `isMine` decides what opens: only the person's own tool with an id reaches the form.
    private func selectTool(id: String, agentID: String) {
        guard let agent = store.value(resource)?.roomTools?.agents.first(where: { $0.agentID == agentID }),
              let tool = agent.tools.first(where: { $0.id == id }) else { return }
        guard agent.isMine, var detail = ActiveToolDetail(tool) else {
            actionsSubject.send(.viewTool(ToolDetail(tool: tool,
                                                     agent: agent,
                                                     agentAvatarURL: avatarURL(for: agent),
                                                     ownerName: ownerName(of: agent))))
            return
        }
        detail.canFire = canFire(kind: tool.toolKind, agentID: agentID)
        guard detail.canFire else {
            // Editing would arm it again, which the server refuses: only off.
            offerTurnOff(of: detail, agentID: agentID, id: .unavailable,
                         title: UntranslatedL10n.screenAgentCapabilitiesUnavailable,
                         message: UntranslatedL10n.screenAgentToolsListUnavailableMessage)
            return
        }
        guard detail.isEditable else {
            // Turning it off removes the whole tool, knowingly.
            offerTurnOff(of: detail, agentID: agentID, id: .needsUpdate,
                         title: UntranslatedL10n.screenAgentToolsListNeedsUpdateTitle,
                         message: UntranslatedL10n.screenAgentToolsListNeedsUpdateMessage)
            return
        }
        actionsSubject.send(.editTool(detail, summary(of: agent)))
    }
    
    private func offerTurnOff(of tool: ActiveToolDetail, agentID: String, id: AgentSheetScreenAlertType, title: String, message: String) {
        state.bindings.alertInfo = AlertInfo(id: id,
                                             title: title,
                                             message: message,
                                             primaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil),
                                             secondaryButton: .init(title: UntranslatedL10n.screenArmToolTurnOff, role: .destructive) { [weak self] in
                                                 Task { await self?.turnOff(toolID: tool.toolID, agentID: agentID) }
                                             })
    }
    
    private func turnOff(toolID: String, agentID: String) async {
        switch await agentPlatformService.disableTool(agentID: agentID, roomID: roomID, toolID: toolID) {
        case .success:
            MXLog.info("Turned off tool \(toolID)")
            await store.reread(resource)
        case .failure(let error):
            MXLog.error("Failed to turn off tool \(toolID): \(error)")
            state.bindings.alertInfo = AlertInfo(id: .turnOffFailed, title: L10n.commonError, message: error.roomToolMessage)
        }
    }
    
    // MARK: - Removing an agent
    
    private func confirmRemove(agentID: String) {
        guard state.removingAgentID == nil, let agent = ownAgent(id: agentID), canRemoveFromChat(agent) else { return }
        state.bindings.alertInfo = AlertInfo(id: .confirmRemove,
                                             title: UntranslatedL10n.screenAgentInRoomRemoveAlertTitle,
                                             message: UntranslatedL10n.screenAgentInRoomRemoveAlertMessage,
                                             primaryButton: .init(title: L10n.actionRemove, role: .destructive) { [weak self] in
                                                 Task { await self?.remove(agentID: agentID) }
                                             },
                                             secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
    }
    
    private func remove(agentID: String) async {
        state.removingAgentID = agentID
        defer { state.removingAgentID = nil }
        
        switch await agentPlatformService.leaveRoom(agentID: agentID, roomID: roomID) {
        case .success:
            await store.reread(resource)
        case .failure(let error):
            MXLog.error("Failed to remove agent \(agentID) from room \(roomID): \(error)")
            state.bindings.alertInfo = AlertInfo(id: .removeFailed, title: UntranslatedL10n.screenAgentInRoomRemoveFailure)
        }
    }
    
    // MARK: - Rendering
    
    private func render() {
        let listState: AgentSheetListState
        switch store.readState(resource, \.roomTools) {
        case .loading:
            listState = .loading
        case .failed:
            listState = .failed
        case .loaded(let roomTools):
            showCatalogs(of: roomTools.agents.filter(\.isMine))
            listState = .loaded(mine: roomTools.agents.filter(\.isMine).map(ownGroup),
                                others: roomTools.agents.filter { !$0.isMine && !$0.tools.isEmpty }.map(otherGroup))
        }
        if state.listState != listState {
            state.listState = listState
        }
        if state.syncStatus != store.syncStatus {
            state.syncStatus = store.syncStatus
        }
    }
    
    private func showCatalogs(of agents: [RoomToolAgentEntry]) {
        let agentIDs = Set(agents.map(\.agentID))
        for agentID in shownCatalogAgentIDs.subtracting(agentIDs) {
            store.stopShowing(catalogResource(agentID), by: self)
        }
        for agentID in agentIDs.subtracting(shownCatalogAgentIDs) {
            store.show(catalogResource(agentID), by: self)
        }
        shownCatalogAgentIDs = agentIDs
    }
    
    private func ownGroup(_ agent: RoomToolAgentEntry) -> AgentSheetGroup {
        let tools = agent.tools.map { tool -> AgentSheetTool in
            guard let detail = ActiveToolDetail(tool) else { return otherTool(tool) }
            let isUnavailable = !canFire(kind: tool.toolKind, agentID: agent.agentID)
            return AgentSheetTool(id: tool.id,
                                  title: detail.title,
                                  subtitle: isUnavailable ? UntranslatedL10n.screenAgentCapabilitiesUnavailableSubtitle : detail.subtitle,
                                  icon: ToolDisplayName.icon(forKind: tool.toolKind),
                                  isUnavailable: isUnavailable)
        }
        return AgentSheetGroup(agent: summary(of: agent),
                               tools: tools,
                               quickAdd: tools.isEmpty ? quickAdd(agentID: agent.agentID) : .none,
                               canRemoveFromChat: canRemoveFromChat(agent))
    }
    
    private func otherGroup(_ agent: RoomToolAgentEntry) -> AgentSheetGroup {
        AgentSheetGroup(agent: summary(of: agent),
                        ownerLine: ownerName(of: agent).map(UntranslatedL10n.screenChatToolsOtherAgentOwner),
                        tools: agent.tools.map(otherTool))
    }
    
    /// A tool as the safe slice has it.
    private func otherTool(_ tool: RoomToolView) -> AgentSheetTool {
        AgentSheetTool(id: tool.id,
                       title: ToolDisplayName.title(forKind: tool.toolKind, language: tool.targetLanguage),
                       subtitle: AgentToolTrigger.when(firing: AgentToolFiring(rawValue: tool.triggerKind)),
                       icon: ToolDisplayName.icon(forKind: tool.toolKind))
    }
    
    /// Two kinds lead: translation, the reason most people come, and a call's summary. The rest follow by order.
    private func quickAdd(agentID: String) -> AgentSheetQuickAdd {
        switch store.readState(catalogResource(agentID), \.toolsCatalog) {
        case .loading:
            return .loading
        case .failed:
            return .failed
        case .loaded(let catalog):
            let offered = AgentToolKind.offered(availableToolKinds: catalog.availableToolKinds)
            let leading = [AgentToolKind.translate, .callSummary].filter(offered.contains)
            let kinds = Array((leading + offered.filter { !leading.contains($0) }).prefix(2))
            return .kinds(kinds, hasMore: offered.count > kinds.count)
        }
    }
    
    // MARK: - Reading the room's read
    
    private func catalogResource(_ agentID: String) -> AgentsResource {
        .toolsCatalog(agentID: agentID, roomID: roomID)
    }
    
    /// A catalogue not read says nothing, so the row stays a working one; the server refuses what can't fire.
    private func canFire(kind: String, agentID: String) -> Bool {
        guard let catalog = store.value(catalogResource(agentID))?.toolsCatalog else { return true }
        return catalog.availableToolKinds.contains(kind)
    }
    
    private func ownAgent(id: String) -> RoomToolAgentEntry? {
        store.value(resource)?.roomTools?.agents.first { $0.agentID == id && $0.isMine }
    }
    
    private func summary(of agent: RoomToolAgentEntry) -> AgentSummary {
        AgentSummary(entry: agent, avatarURL: avatarURL(for: agent))
    }
    
    private func canRemoveFromChat(_ agent: RoomToolAgentEntry) -> Bool {
        AgentRoomLabel.ownerDMRoomID(agentMatrixUserID: agent.matrixUserID, clientProxy: clientProxy) != roomID
    }
    
    private func avatarURL(for agent: RoomToolAgentEntry) -> URL? {
        if let card = store.card(agentID: agent.agentID) {
            return card.avatarMXC.flatMap(URL.init(string:))
        }
        return roomProxy.membersPublisher.value.first { $0.userID == agent.matrixUserID }?.avatarURL
    }
    
    private func ownerName(of agent: RoomToolAgentEntry) -> String? {
        guard let ownerUserID = agent.ownerUserID else { return nil }
        return roomProxy.membersPublisher.value.first { $0.userID == ownerUserID }?.displayName
            ?? AgentSummary.displayName(fromMatrixUserID: ownerUserID)
    }
}
