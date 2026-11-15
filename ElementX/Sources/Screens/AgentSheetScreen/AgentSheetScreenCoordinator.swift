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

struct AgentSheetScreenCoordinatorParameters {
    let roomID: String
    let roomProxy: JoinedRoomProxyProtocol
    let store: AgentsStore
    let agentPlatformService: any AgentPlatformServiceProtocol
    let clientProxy: any ClientProxyProtocol
    /// Loads agent avatars for the rows.
    let mediaProvider: MediaProviderProtocol?
}

final class AgentSheetScreenCoordinator: CoordinatorProtocol {
    private let viewModel: AgentSheetScreenViewModel
    private let mediaProvider: MediaProviderProtocol?

    var actionsPublisher: AnyPublisher<AgentSheetScreenViewModelAction, Never> {
        viewModel.actionsPublisher
    }

    init(parameters: AgentSheetScreenCoordinatorParameters) {
        viewModel = AgentSheetScreenViewModel(roomID: parameters.roomID,
                                              roomProxy: parameters.roomProxy,
                                              store: parameters.store,
                                              agentPlatformService: parameters.agentPlatformService,
                                              clientProxy: parameters.clientProxy)
        mediaProvider = parameters.mediaProvider
    }

    /// Re-pull the agents (after an add-agent invite or an arm/disable).
    func reload() {
        viewModel.reload()
    }

    func toPresentable() -> AnyView {
        AnyView(AgentSheetScreen(context: viewModel.context, mediaProvider: mediaProvider))
    }
}
