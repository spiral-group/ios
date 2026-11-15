//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreenCoordinator.swift`.

import Combine
import SwiftUI

struct PublicProfileScreenCoordinatorParameters {
    /// MXID of the user whose profile is being viewed (target
    /// of the `GET /api/v1/users/:mxid/profile` call).
    let targetMXID: String
    /// MXID of the caller. Used by the view model's
    /// self-lookup short-circuit so we don't re-render the
    /// owner's own dashboard as a stranger view.
    let currentUserMXID: String
    let store: AgentsStore
}

enum PublicProfileScreenCoordinatorAction {
    /// User tapped "Contact agent" on one of the rows. The
    /// flow coordinator decides what "Contact" means — current
    /// implementation pushes / creates a DM with the agent in
    /// the Chats tab.
    case contactAgent(matrixUserID: String)
    case dismiss
}

final class PublicProfileScreenCoordinator: CoordinatorProtocol {
    private let viewModel: PublicProfileScreenViewModelProtocol

    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<PublicProfileScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<PublicProfileScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: PublicProfileScreenCoordinatorParameters) {
        viewModel = PublicProfileScreenViewModel(targetMXID: parameters.targetMXID,
                                                 currentUserMXID: parameters.currentUserMXID,
                                                 store: parameters.store)
    }

    func start() {
        viewModel.actionsPublisher
            .sink { [weak self] action in
                MXLog.info("PublicProfileScreenCoordinator received view-model action: \(action)")
                guard let self else { return }
                switch action {
                case .contactAgent(let mxid):
                    actionsSubject.send(.contactAgent(matrixUserID: mxid))
                case .dismissed:
                    actionsSubject.send(.dismiss)
                }
            }
            .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(PublicProfileScreen(context: viewModel.context))
    }
}
