//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct ResolveVerifiedUserSendFailureScreenCoordinatorParameters {
    let failure: TimelineItemSendFailure.VerifiedUser
    // AGENT-PLATFORM (Brief 0066 § 5.87): was `sendHandle` + `roomProxy`; the
    // resolver carries the room, and also resolves a raw send.
    let resolver: VerifiedUserSendFailureResolver
    let userIndicatorController: UserIndicatorControllerProtocol
}

enum ResolveVerifiedUserSendFailureScreenCoordinatorAction {
    case dismiss
}

final class ResolveVerifiedUserSendFailureScreenCoordinator: CoordinatorProtocol {
    private let viewModel: ResolveVerifiedUserSendFailureScreenViewModelProtocol
    
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<ResolveVerifiedUserSendFailureScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<ResolveVerifiedUserSendFailureScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: ResolveVerifiedUserSendFailureScreenCoordinatorParameters) {
        viewModel = ResolveVerifiedUserSendFailureScreenViewModel(failure: parameters.failure,
                                                                  resolver: parameters.resolver,
                                                                  userIndicatorController: parameters.userIndicatorController)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            MXLog.info("Coordinator: received view model action: \(action)")
            
            guard let self else { return }
            switch action {
            case .dismiss:
                actionsSubject.send(.dismiss)
            }
        }
        .store(in: &cancellables)
    }
    
    func toPresentable() -> AnyView {
        AnyView(ResolveVerifiedUserSendFailureScreen(context: viewModel.context))
    }
}
