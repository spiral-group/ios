//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenCoordinator.swift`.
//

import Combine
import SwiftUI

struct ToolMemberPickerScreenCoordinatorParameters {
    let roomProxy: JoinedRoomProxyProtocol
    /// The agent's Matrix user id — excluded from the candidate list.
    let agentMatrixUserID: String?
    /// Members already chosen, so re-opening the picker keeps them ticked.
    let preselectedMemberIDs: [String]
    let mediaProvider: MediaProviderProtocol?
}

enum ToolMemberPickerScreenCoordinatorAction {
    /// User confirmed — carries the chosen MXIDs back to the arm form.
    case confirm(members: [String])
}

final class ToolMemberPickerScreenCoordinator: CoordinatorProtocol {
    private let parameters: ToolMemberPickerScreenCoordinatorParameters
    private let viewModel: ToolMemberPickerScreenViewModel

    private let actionsSubject: PassthroughSubject<ToolMemberPickerScreenCoordinatorAction, Never> = .init()
    private var cancellables = Set<AnyCancellable>()

    var actionsPublisher: AnyPublisher<ToolMemberPickerScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: ToolMemberPickerScreenCoordinatorParameters) {
        self.parameters = parameters
        viewModel = ToolMemberPickerScreenViewModel(roomProxy: parameters.roomProxy,
                                                    agentMatrixUserID: parameters.agentMatrixUserID,
                                                    preselectedMemberIDs: parameters.preselectedMemberIDs)
    }

    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .confirm(let members):
                actionsSubject.send(.confirm(members: members))
            }
        }
        .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(ToolMemberPickerScreen(context: viewModel.context, mediaProvider: parameters.mediaProvider))
    }
}
