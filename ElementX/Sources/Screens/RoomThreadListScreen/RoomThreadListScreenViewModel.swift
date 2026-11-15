//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias RoomThreadListScreenViewModelType = StateStoreViewModelV2<RoomThreadListScreenViewState, RoomThreadListScreenViewAction>

class RoomThreadListScreenViewModel: RoomThreadListScreenViewModelType, RoomThreadListScreenViewModelProtocol {
    private let threadListServiceProxy: RoomThreadListServiceProxyProtocol
    
    private var isOldestItemVisible = false
    private var isReading = false // AGENT-PLATFORM (Brief 0083, decision 357)
    
    private let actionsSubject: PassthroughSubject<RoomThreadListScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<RoomThreadListScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(threadListServiceProxy: RoomThreadListServiceProxyProtocol, mediaProvider: MediaProviderProtocol) {
        self.threadListServiceProxy = threadListServiceProxy
        
        super.init(initialViewState: .init(paginationState: threadListServiceProxy.paginationStatePublisher.value, bindings: .init()),
                   mediaProvider: mediaProvider)
        
        updateItems(self.threadListServiceProxy.itemsPublisher.value)
        
        threadListServiceProxy.itemsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.updateItems(items)
            }
            .store(in: &cancellables)
        
        threadListServiceProxy.paginationStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paginationState in
                guard let self else { return }
                state.paginationState = paginationState
                Task { await self.paginateIfNecessary() }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public
    
    override func process(viewAction: RoomThreadListScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")
        
        switch viewAction {
        case .oldestItemDidAppear:
            isOldestItemVisible = true
            
            Task {
                await paginateIfNecessary()
            }
        case .oldestItemDidDisappear:
            isOldestItemVisible = false
        case .tappedThread(let threadRootEventID):
            actionsSubject.send(.presentThread(threadRootEventID: threadRootEventID))
        case .retry: // AGENT-PLATFORM (Brief 0083, decision 357)
            state.hasFailedToLoad = false
            
            Task {
                await paginateIfNecessary()
            }
        }
    }
    
    // MARK: - Private
    
    // AGENT-PLATFORM (Brief 0083, decision 357): an empty page has no oldest item to appear, so it reads its first
    // page itself. A failed read waits for Retry: the SDK's state goes back to idle, which used to read again at once.
    private func paginateIfNecessary() async {
        guard !state.hasFailedToLoad, !isReading,
              isOldestItemVisible || state.items.isEmpty,
              case .idle(endReached: false) = threadListServiceProxy.paginationStatePublisher.value else {
            return
        }
        
        isReading = true
        let result = await threadListServiceProxy.paginate()
        isReading = false
        
        switch result {
        case .success:
            await paginateIfNecessary() // The state's update may have come while this read was running.
        case .failure:
            state.hasFailedToLoad = true
        }
    }
    
    private func updateItems(_ items: [RoomThreadListItem]) {
        state.items = items
    }
}
