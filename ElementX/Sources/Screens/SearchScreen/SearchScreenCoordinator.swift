//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct SearchScreenCoordinatorParameters {
    let roomSummaryProvider: RoomSummaryProviderProtocol
    let userSession: UserSessionProtocol
    let userIndicatorController: UserIndicatorControllerProtocol
}

enum SearchScreenCoordinatorAction {
    case presentRoom(roomID: String, eventID: String?)
}

// AGENT-PLATFORM (Brief 0083, question 343): not a coordinator of a screen any more; Chats draws the field and the results.
final class SearchScreenCoordinator {
    private let viewModel: SearchScreenViewModelProtocol
    
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<SearchScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<SearchScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: SearchScreenCoordinatorParameters) {
        viewModel = SearchScreenViewModel(roomSummaryProvider: parameters.roomSummaryProvider,
                                          userSession: parameters.userSession,
                                          userIndicatorController: parameters.userIndicatorController)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .presentRoom(let roomID, let eventID):
                viewModel.context.isSearchPresented = false // AGENT-PLATFORM (Brief 0083): back from the room lands on Chats.
                actionsSubject.send(.presentRoom(roomID: roomID, eventID: eventID))
            case .cancel:
                viewModel.context.isSearchPresented = false // AGENT-PLATFORM (Brief 0083, question 343)
            }
        }
        .store(in: &cancellables)
    }
    
    var context: SearchScreenViewModelType.Context {
        viewModel.context
    }
    
    func presentSearch() {
        viewModel.context.isFieldReturning = false // AGENT-PLATFORM (Brief 0083): this one is asked for, so the focus stays.
        viewModel.context.isSearchPresented = true
    }
}
