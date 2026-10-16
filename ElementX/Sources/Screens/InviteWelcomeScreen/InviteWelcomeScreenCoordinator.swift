//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//


import Combine
import SwiftUI

struct InviteWelcomeScreenCoordinatorParameters {
    let inviterUserID: String
    let clientProxy: ClientProxyProtocol
    let mediaProvider: MediaProviderProtocol?
}

enum InviteWelcomeScreenCoordinatorAction {
    case openDirectChat(roomID: String)
    case dismiss
}

final class InviteWelcomeScreenCoordinator: CoordinatorProtocol {
    private let viewModel: InviteWelcomeScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<InviteWelcomeScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<InviteWelcomeScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: InviteWelcomeScreenCoordinatorParameters) {
        viewModel = InviteWelcomeScreenViewModel(inviterUserID: parameters.inviterUserID,
                                                 clientProxy: parameters.clientProxy,
                                                 mediaProvider: parameters.mediaProvider)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            MXLog.info("Coordinator: received view model action: \(action)")
            guard let self else { return }
            switch action {
            case .openDirectChat(let roomID):
                actionsSubject.send(.openDirectChat(roomID: roomID))
            case .dismiss:
                actionsSubject.send(.dismiss)
            }
        }
        .store(in: &cancellables)
    }
    
    func toPresentable() -> AnyView {
        AnyView(InviteWelcomeScreen(context: viewModel.context))
    }
}
