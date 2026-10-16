//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: invite links (Brief 0073 / ADR-0008).
//

import Combine
import SwiftUI

struct InvitePeopleScreenCoordinatorParameters {
    let userSession: UserSessionProtocol
    let userIndicatorController: UserIndicatorControllerProtocol
}

enum InvitePeopleScreenCoordinatorAction {
    /// Open the profile of someone who joined through the link.
    case openUser(userID: String)
}

final class InvitePeopleScreenCoordinator: CoordinatorProtocol {
    private let viewModel: InvitePeopleScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<InvitePeopleScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<InvitePeopleScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: InvitePeopleScreenCoordinatorParameters) {
        viewModel = InvitePeopleScreenViewModel(userSession: parameters.userSession,
                                                userIndicatorController: parameters.userIndicatorController)
    }
    
    func start() {
        viewModel.actionsPublisher
            .sink { [weak self] action in
                switch action {
                case .openUser(let userID):
                    self?.actionsSubject.send(.openUser(userID: userID))
                }
            }
            .store(in: &cancellables)
    }
    
    func toPresentable() -> AnyView {
        AnyView(InvitePeopleScreen(context: viewModel.context))
    }
}
