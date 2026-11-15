//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import SwiftUI

typealias AgentChatsScreenViewModelType = StateStoreViewModelV2<AgentChatsScreenViewState, AgentChatsScreenViewAction>

class AgentChatsScreenViewModel: AgentChatsScreenViewModelType, AgentChatsScreenViewModelProtocol {
    private let agentID: String
    private let clientProxy: ClientProxyProtocol
    private let store: AgentsStore
    private var hasReportedGone = false
    
    private var resource: AgentsResource {
        .agent(agentID: agentID)
    }
    
    private let actionsSubject: PassthroughSubject<AgentChatsScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentChatsScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(agent: AgentSpaceAgentCard, clientProxy: ClientProxyProtocol, store: AgentsStore) {
        agentID = agent.agentID
        self.clientProxy = clientProxy
        self.store = store
        
        super.init(initialViewState: AgentChatsScreenViewState(agentName: agent.displayName,
                                                               expectedRoomCount: agent.roomCount,
                                                               ownerDMRoomID: AgentRoomLabel.ownerDMRoomID(agentMatrixUserID: agent.matrixUserID, clientProxy: clientProxy)))
        
        render()
        store.observe { [weak self] in
            guard let self else { return false }
            render()
            return true
        }
        store.show(resource, by: self)
    }
    
    isolated deinit {
        store.stopShowing(resource, by: self)
    }
    
    // MARK: - Public
    
    override func process(viewAction: AgentChatsScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")
        
        switch viewAction {
        case .selectRoom(let room):
            actionsSubject.send(.selectRoom(room))
        case .retry:
            Task { await reload() }
        }
    }
    
    func reload() async {
        await store.reread(resource)
    }
    
    // MARK: - Private
    
    private func render() {
        let loadState: AgentChatsScreenLoadState
        switch store.readState(resource, \.agent) {
        case .loading:
            loadState = .loading
        case .failed(.notFound):
            loadState = .failure
            if !hasReportedGone {
                hasReportedGone = true
                actionsSubject.send(.gone)
            }
        case .failed:
            loadState = .failure
        case .loaded(let detail):
            loadState = .loaded(detail.rooms)
            let deviceRoomNames = AgentRoomLabel.deviceRoomNames(of: detail.rooms, clientProxy: clientProxy)
            if state.deviceRoomNames != deviceRoomNames {
                state.deviceRoomNames = deviceRoomNames
            }
        }
        if state.loadState != loadState {
            state.loadState = loadState
        }
        if state.syncStatus != store.syncStatus {
            state.syncStatus = store.syncStatus
        }
    }
}
