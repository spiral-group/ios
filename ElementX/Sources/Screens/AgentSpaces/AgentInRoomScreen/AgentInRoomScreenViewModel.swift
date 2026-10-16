//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias AgentInRoomScreenViewModelType = StateStoreViewModelV2<AgentInRoomScreenViewState, AgentInRoomScreenViewAction>

class AgentInRoomScreenViewModel: AgentInRoomScreenViewModelType, AgentInRoomScreenViewModelProtocol {
    private let agentPlatformService: AgentPlatformServiceProtocol
    private let clientProxy: ClientProxyProtocol
    
    private let actionsSubject: PassthroughSubject<AgentInRoomScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentInRoomScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(agent: AgentInRoomScreenAgent,
         room: AgentRoomEntry,
         agentPlatformService: AgentPlatformServiceProtocol,
         clientProxy: ClientProxyProtocol,
         mediaProvider: MediaProviderProtocol) {
        self.agentPlatformService = agentPlatformService
        self.clientProxy = clientProxy
        
        super.init(initialViewState: AgentInRoomScreenViewState(agent: agent,
                                                                room: room,
                                                                ownerDMRoomID: AgentRoomLabel.ownerDMRoomID(agentMatrixUserID: agent.matrixUserID,
                                                                                                            clientProxy: clientProxy)),
                   mediaProvider: mediaProvider)
        
        Task { await nameAudienceMembers() }
    }
    
    // MARK: - Public
    
    override func process(viewAction: AgentInRoomScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")
        
        switch viewAction {
        case .removeTapped:
            state.bindings.alertInfo = AlertInfo(id: .confirmRemove,
                                                 title: UntranslatedL10n.screenAgentInRoomRemoveAlertTitle,
                                                 message: UntranslatedL10n.screenAgentInRoomRemoveAlertMessage,
                                                 primaryButton: .init(title: L10n.actionRemove, role: .destructive) { [weak self] in
                                                     self?.context.send(viewAction: .confirmRemove)
                                                 },
                                                 secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
        case .confirmRemove:
            Task { await removeFromRoom() }
        case .addTool:
            actionsSubject.send(.addTool)
        case .selectTool(let id):
            guard state.openingToolID == nil else { return }
            Task { await openTool(id: id) }
        }
    }
    
    /// Re-fetch this room's tools (after arm/disable). Walks the
    /// agent-first room view and picks our room back out.
    func reloadRoom() async {
        if case .success(let rooms) = await agentPlatformService.fetchAgentRooms(agentID: state.agent.agentID),
           let fresh = rooms.first(where: { $0.roomID == state.room.roomID }) {
            state.room = fresh
            await nameAudienceMembers()
        }
    }
    
    /// The people a tool is for or not for, by name. Only this device's copy
    /// of the chat knows them, so a chat the owner isn't in keeps the general words.
    private func nameAudienceMembers() async {
        let wanted = Set(state.room.activeTools.flatMap { $0.audience?.members ?? [] }).subtracting(state.memberNames.keys)
        guard !wanted.isEmpty, case .joined(let roomProxy) = await clientProxy.roomForIdentifier(state.room.roomID) else { return }
        for userID in wanted {
            guard case .success(let member) = await roomProxy.getMember(userID: userID),
                  let name = member.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
            state.memberNames[userID] = name
        }
    }
    
    // MARK: - Private
    
    /// The form needs the tool's full settings, which the room's own read
    /// carries; this device can read it only when the owner is in the chat.
    private func openTool(id: String) async {
        state.openingToolID = id
        defer { state.openingToolID = nil }
        
        guard case .success(let roomTools) = await agentPlatformService.fetchRoomTools(roomID: state.room.roomID),
              let tool = AgentToolsListScreenViewModel.projectTools(from: roomTools, ownAgentID: state.agent.agentID).first(where: { $0.toolID == id }),
              tool.isEditable else {
            MXLog.error("Couldn't read tool \(id) in \(state.room.roomID) for its form")
            state.bindings.alertInfo = AlertInfo(id: .toolUnavailable,
                                                 title: UntranslatedL10n.screenAgentInRoomToolUnavailable,
                                                 message: UntranslatedL10n.screenAgentInRoomToolUnavailableMessage)
            return
        }
        actionsSubject.send(.editTool(tool))
    }
    
    private func removeFromRoom() async {
        state.isRemoving = true
        defer { state.isRemoving = false }
        
        switch await agentPlatformService.leaveRoom(agentID: state.agent.agentID, roomID: state.room.roomID) {
        case .success:
            actionsSubject.send(.removed)
        case .failure(let error):
            MXLog.error("Failed to remove agent from room: \(error)")
            state.bindings.alertInfo = AlertInfo(id: .removeFailed,
                                                 title: UntranslatedL10n.screenAgentInRoomRemoveFailure)
        }
    }
}
