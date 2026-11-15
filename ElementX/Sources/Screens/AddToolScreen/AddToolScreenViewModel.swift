//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import SwiftUI

typealias AddToolScreenViewModelType = StateStoreViewModelV2<AddToolScreenViewState, AddToolScreenViewAction>

class AddToolScreenViewModel: AddToolScreenViewModelType, AddToolScreenViewModelProtocol {
    private let resource: AgentsResource
    private let store: AgentsStore
    
    private let actionsSubject: PassthroughSubject<AddToolScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AddToolScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(roomID: String, agentID: String, agentDisplayName: String, store: AgentsStore) {
        resource = .toolsCatalog(agentID: agentID, roomID: roomID)
        self.store = store
        super.init(initialViewState: AddToolScreenViewState(agentDisplayName: agentDisplayName))
        
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
    
    override func process(viewAction: AddToolScreenViewAction) {
        switch viewAction {
        case .retry:
            store.refresh(resource)
            render()
        case .selectKind(let kind):
            actionsSubject.send(.selectKind(kind))
        }
    }
    
    // MARK: - Private
    
    private func render() {
        let listState: AddToolListState = switch store.readState(resource, \.toolsCatalog) {
        case .loading: .loading
        case .failed: .failed
        case .loaded(let catalog):
            .loaded(text: AgentToolKind.offered(availableToolKinds: catalog.availableToolKinds).filter { !$0.firesOnCalls },
                    calls: AgentToolKind.offered(availableToolKinds: catalog.availableToolKinds).filter(\.firesOnCalls))
        }
        if state.listState != listState {
            state.listState = listState
        }
    }
}
