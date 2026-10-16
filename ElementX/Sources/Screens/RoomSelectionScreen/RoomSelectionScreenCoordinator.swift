//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct RoomSelectionScreenCoordinatorParameters {
    let userSession: UserSessionProtocol
    let roomSummaryProvider: RoomSummaryProviderProtocol
    /// AGENT-PLATFORM (decision 111): a catalogue link continues, a share shares.
    var confirmTitle = L10n.actionShare
    /// AGENT-PLATFORM (Agents tab step B): «В чат» offers only the chats an agent can join.
    var roomFilter: (RoomSummary) -> Bool = { _ in true }
    /// AGENT-PLATFORM: why the filtered list can be empty.
    var emptyState: RoomSelectionScreenEmptyState?
}

enum RoomSelectionScreenCoordinatorAction {
    case dismiss
    case confirm(roomID: String)
}

final class RoomSelectionScreenCoordinator: CoordinatorProtocol {
    private var viewModel: RoomSelectionScreenViewModelProtocol
    private let actionsSubject: PassthroughSubject<RoomSelectionScreenCoordinatorAction, Never> = .init()
    private var cancellables = Set<AnyCancellable>()
    
    var actionsPublisher: AnyPublisher<RoomSelectionScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: RoomSelectionScreenCoordinatorParameters) {
        viewModel = RoomSelectionScreenViewModel(userSession: parameters.userSession,
                                                 roomSummaryProvider: parameters.roomSummaryProvider,
                                                 confirmTitle: parameters.confirmTitle,
                                                 roomFilter: parameters.roomFilter,
                                                 emptyState: parameters.emptyState)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            switch action {
            case .dismiss:
                self?.actionsSubject.send(.dismiss)
            case .confirm(let roomID):
                self?.actionsSubject.send(.confirm(roomID: roomID))
            }
        }
        .store(in: &cancellables)
    }
    
    func stop() {
        viewModel.stop()
    }
    
    func toPresentable() -> AnyView {
        AnyView(RoomSelectionScreen(context: viewModel.context))
    }
}
