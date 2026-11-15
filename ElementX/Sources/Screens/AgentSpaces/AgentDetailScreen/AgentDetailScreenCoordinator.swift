//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct AgentDetailScreenCoordinatorParameters {
    let selection: AgentSelection
    let agentPlatformService: AgentPlatformServiceProtocol
    let clientProxy: ClientProxyProtocol
    let mediaProvider: MediaProviderProtocol
    let userIndicatorController: UserIndicatorControllerProtocol
    let store: AgentsStore
}

enum AgentDetailScreenCoordinatorAction {
    case selectRoom(AgentRoomEntry)
    case showEdit
    case showVerification(id: String)
    case showActivity
    case showUsage
    case showQueue
    case message
    case addToChat(agentRoomIDs: Set<String>)
    case addedToChat
    case showSettings(AgentSettingsSection)
    case showPendingApprovals
    case showBlocked
    case changed
    case archived
    /// The agent no longer exists (deleted elsewhere).
    case gone
}

final class AgentDetailScreenCoordinator: CoordinatorProtocol {
    private let viewModel: AgentDetailScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<AgentDetailScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentDetailScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: AgentDetailScreenCoordinatorParameters) {
        viewModel = AgentDetailScreenViewModel(selection: parameters.selection,
                                               agentPlatformService: parameters.agentPlatformService,
                                               clientProxy: parameters.clientProxy,
                                               mediaProvider: parameters.mediaProvider,
                                               userIndicatorController: parameters.userIndicatorController,
                                               store: parameters.store)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            switch action {
            case .selectRoom(let room):
                self?.actionsSubject.send(.selectRoom(room))
            case .showEdit:
                self?.actionsSubject.send(.showEdit)
            case .showVerification(let id):
                self?.actionsSubject.send(.showVerification(id: id))
            case .showActivity:
                self?.actionsSubject.send(.showActivity)
            case .showUsage:
                self?.actionsSubject.send(.showUsage)
            case .showQueue:
                self?.actionsSubject.send(.showQueue)
            case .message:
                self?.actionsSubject.send(.message)
            case .addToChat(let agentRoomIDs):
                self?.actionsSubject.send(.addToChat(agentRoomIDs: agentRoomIDs))
            case .addedToChat:
                self?.actionsSubject.send(.addedToChat)
            case .showSettings(let section):
                self?.actionsSubject.send(.showSettings(section))
            case .showPendingApprovals:
                self?.actionsSubject.send(.showPendingApprovals)
            case .showBlocked:
                self?.actionsSubject.send(.showBlocked)
            case .changed:
                self?.actionsSubject.send(.changed)
            case .archived:
                self?.actionsSubject.send(.archived)
            case .gone:
                self?.actionsSubject.send(.gone)
            }
        }
        .store(in: &cancellables)
    }
    
    /// Re-fetch after a mutation deeper in the flow.
    func reload() {
        Task { await viewModel.reload() }
    }
    
    /// The chat picked for «В чат».
    func addToChat(roomID: String) {
        Task { await viewModel.addToChat(roomID: roomID) }
    }
    
    func toPresentable() -> AnyView {
        AnyView(AgentDetailScreen(context: viewModel.context))
    }
}
