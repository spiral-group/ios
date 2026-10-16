//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0066, § 5.56): the catalogue screen.
// The Spiral feature is built on Element's `TemplateScreenCoordinator.swift`.
//

import Combine
import SwiftUI

struct InteractivePostCatalogScreenCoordinatorParameters {
    let roomName: String
    let catalogURL: URL
    let dms: [JoinedRoomProxyProtocol]
    /// Who the preview runs as, and the people it shows (§ 5.60).
    let ownUserID: String
    /// The template a catalogue link named, to open on (decision 111).
    var initialTemplateID: String?
    /// Whether the viewer has an agent; without one, browse and Publish only (decision 129).
    var assistant = InteractivePostCatalogAssistant.available
    let loadMembers: @MainActor () async -> [String: Any]
}

enum InteractivePostCatalogScreenCoordinatorAction {
    case startNew
    case openThread(InteractivePostThreadItem)
    case publishTemplate(SpiralAppTemplate)
    case changeTemplate(SpiralAppTemplate)
    case showAllThreads
    case cancel
}

final class InteractivePostCatalogScreenCoordinator: CoordinatorProtocol {
    private let viewModel: InteractivePostCatalogScreenViewModelProtocol

    /// The full list of yours, for the stack the catalogue is on to push.
    var threadsCoordinator: InteractivePostThreadsScreenCoordinator {
        InteractivePostThreadsScreenCoordinator(viewModel: viewModel)
    }

    /// What the catalogue knows of the viewer's agents (decision 129).
    var assistant: InteractivePostCatalogAssistant {
        viewModel.context.viewState.assistant
    }

    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<InteractivePostCatalogScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<InteractivePostCatalogScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: InteractivePostCatalogScreenCoordinatorParameters) {
        viewModel = InteractivePostCatalogScreenViewModel(roomName: parameters.roomName,
                                                          catalogURL: parameters.catalogURL,
                                                          dms: parameters.dms,
                                                          ownUserID: parameters.ownUserID,
                                                          initialTemplateID: parameters.initialTemplateID,
                                                          assistant: parameters.assistant,
                                                          loadMembers: parameters.loadMembers)
    }

    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .startNew:
                actionsSubject.send(.startNew)
            case .openThread(let item):
                actionsSubject.send(.openThread(item))
            case .publishTemplate(let template):
                actionsSubject.send(.publishTemplate(template))
            case .changeTemplate(let template):
                actionsSubject.send(.changeTemplate(template))
            case .showAllThreads:
                actionsSubject.send(.showAllThreads)
            case .cancel:
                actionsSubject.send(.cancel)
            }
        }
        .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(InteractivePostCatalogScreen(context: viewModel.context))
    }
}

/// «Yours › All», over the catalogue on the same stack (§ 5.63): the same
/// view model, so the list is the one the main screen already holds.
final class InteractivePostThreadsScreenCoordinator: CoordinatorProtocol {
    private let viewModel: InteractivePostCatalogScreenViewModelProtocol

    init(viewModel: InteractivePostCatalogScreenViewModelProtocol) {
        self.viewModel = viewModel
    }

    func toPresentable() -> AnyView {
        AnyView(InteractivePostThreadsScreen(context: viewModel.context))
    }
}
