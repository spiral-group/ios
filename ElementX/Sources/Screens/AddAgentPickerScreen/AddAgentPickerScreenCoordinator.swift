//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0035/0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenCoordinator.swift`.
//

import Combine
import SwiftUI

struct AddAgentPickerScreenCoordinatorParameters {
    let roomID: String
    let roomProxy: JoinedRoomProxyProtocol
    let agentPlatformService: any RoomToolsServiceProtocol
    let mediaProvider: MediaProviderProtocol?
}

enum AddAgentPickerScreenCoordinatorAction {
    /// An agent was invited — the flow opens its capabilities directly.
    case invited(AddAgentItem)
    case dismiss
}

final class AddAgentPickerScreenCoordinator: CoordinatorProtocol {
    private let viewModel: AddAgentPickerScreenViewModel
    private let mediaProvider: MediaProviderProtocol?

    private let actionsSubject: PassthroughSubject<AddAgentPickerScreenCoordinatorAction, Never> = .init()
    private var cancellables = Set<AnyCancellable>()

    var actionsPublisher: AnyPublisher<AddAgentPickerScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: AddAgentPickerScreenCoordinatorParameters) {
        viewModel = AddAgentPickerScreenViewModel(roomID: parameters.roomID,
                                                  roomProxy: parameters.roomProxy,
                                                  agentPlatformService: parameters.agentPlatformService)
        mediaProvider = parameters.mediaProvider
    }

    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .invited(let item):
                actionsSubject.send(.invited(item))
            case .dismiss:
                actionsSubject.send(.dismiss)
            }
        }
        .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(AddAgentPickerScreen(context: viewModel.context, mediaProvider: mediaProvider))
    }
}
