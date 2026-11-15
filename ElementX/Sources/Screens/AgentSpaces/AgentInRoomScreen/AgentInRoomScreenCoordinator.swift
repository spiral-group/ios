//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct AgentInRoomScreenCoordinatorParameters {
    let agent: AgentInRoomScreenAgent
    let room: AgentRoomEntry
    let agentPlatformService: AgentPlatformServiceProtocol
    let clientProxy: ClientProxyProtocol
    let mediaProvider: MediaProviderProtocol
}

enum AgentInRoomScreenCoordinatorAction {
    /// The chat itself was asked for.
    case openChat(roomID: String)
    /// The agent left the room — the flow pops and reloads upstream.
    case removed
    /// Hand off to the Brief 0036 arm flow for this room.
    case addTool
    case editTool(ActiveToolDetail)
}

final class AgentInRoomScreenCoordinator: CoordinatorProtocol {
    private let viewModel: AgentInRoomScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<AgentInRoomScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentInRoomScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: AgentInRoomScreenCoordinatorParameters) {
        viewModel = AgentInRoomScreenViewModel(agent: parameters.agent,
                                               room: parameters.room,
                                               agentPlatformService: parameters.agentPlatformService,
                                               clientProxy: parameters.clientProxy,
                                               mediaProvider: parameters.mediaProvider)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            switch action {
            case .openChat(let roomID):
                self?.actionsSubject.send(.openChat(roomID: roomID))
            case .removed:
                self?.actionsSubject.send(.removed)
            case .addTool:
                self?.actionsSubject.send(.addTool)
            case .editTool(let detail):
                self?.actionsSubject.send(.editTool(detail))
            }
        }
        .store(in: &cancellables)
    }
    
    /// Re-fetch the room's tools after the arm flow pops.
    func reload() {
        Task { await viewModel.reloadRoom() }
    }
    
    func toPresentable() -> AnyView {
        AnyView(AgentInRoomScreen(context: viewModel.context))
    }
}
