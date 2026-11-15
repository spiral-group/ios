//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct AIConsentPromptScreenCoordinatorParameters {
    let store: AgentsStore
    let privacyURL: URL
}

enum AIConsentPromptScreenCoordinatorAction {
    case done
}

final class AIConsentPromptScreenCoordinator: CoordinatorProtocol {
    private let viewModel: AIConsentPromptScreenViewModelProtocol
    private let actionsSubject: PassthroughSubject<AIConsentPromptScreenCoordinatorAction, Never> = .init()
    private var cancellables = Set<AnyCancellable>()
    
    var actionsPublisher: AnyPublisher<AIConsentPromptScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: AIConsentPromptScreenCoordinatorParameters) {
        viewModel = AIConsentPromptScreenViewModel(store: parameters.store,
                                                   privacyURL: parameters.privacyURL)
    }
    
    func start() {
        viewModel.actionsPublisher
            .sink { [weak self] action in
                switch action {
                case .done:
                    self?.actionsSubject.send(.done)
                }
            }
            .store(in: &cancellables)
    }
    
    func toPresentable() -> AnyView {
        AnyView(AIConsentPromptScreen(context: viewModel.context))
    }
}
