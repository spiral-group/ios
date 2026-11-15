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
    /// Whether the viewer has an agent; without one, browse and Send only (decision 129).
    var assistant = InteractivePostCatalogAssistant.available
    /// Whether the one-time introduction has been shown (question 412).
    var hasSeenIntroduction = true
    var introductionSeen: () -> Void = { }
    /// How many people are in the room, nil if unknown: it orders the shelves.
    let countPeople: @MainActor () async -> Int?
    let loadMembers: @MainActor () async -> [String: Any]
}

enum InteractivePostCatalogScreenCoordinatorAction {
    case startNew(description: String?)
    case openThread(InteractivePostThreadItem)
    case publishTemplate(SpiralAppTemplate)
    case changeTemplate(SpiralAppTemplate)
    /// Close the catalogue for the Agents tab.
    case showAgents
    /// Read the agents again and open the catalogue on this post.
    case retryAgents(templateID: String)
    /// Push `postCoordinator()` onto the catalogue's stack.
    case showPost
    /// Push `yoursCoordinator()` onto the catalogue's stack.
    case showYours
    case cancel
}

final class InteractivePostCatalogScreenCoordinator: CoordinatorProtocol {
    /// Internal so a flow's tests can press the screen's buttons.
    let viewModel: InteractivePostCatalogScreenViewModelProtocol

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
                                                          hasSeenIntroduction: parameters.hasSeenIntroduction,
                                                          introductionSeen: parameters.introductionSeen,
                                                          countPeople: parameters.countPeople,
                                                          loadMembers: parameters.loadMembers)
    }

    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .startNew(let description):
                actionsSubject.send(.startNew(description: description))
            case .openThread(let item):
                actionsSubject.send(.openThread(item))
            case .publishTemplate(let template):
                actionsSubject.send(.publishTemplate(template))
            case .changeTemplate(let template):
                actionsSubject.send(.changeTemplate(template))
            case .showAgents:
                actionsSubject.send(.showAgents)
            case .retryAgents(let templateID):
                actionsSubject.send(.retryAgents(templateID: templateID))
            case .showPost:
                actionsSubject.send(.showPost)
            case .showYours:
                actionsSubject.send(.showYours)
            case .cancel:
                actionsSubject.send(.cancel)
            }
        }
        .store(in: &cancellables)
    }

    func stop() {
        viewModel.stop()
    }

    /// The post page, for the stack the catalogue is on to push.
    func postCoordinator() -> InteractivePostCatalogPostScreenCoordinator {
        InteractivePostCatalogPostScreenCoordinator(viewModel: viewModel)
    }

    /// Yours, for the stack the catalogue is on to push.
    func yoursCoordinator() -> InteractivePostCatalogYoursScreenCoordinator {
        InteractivePostCatalogYoursScreenCoordinator(viewModel: viewModel)
    }

    func toPresentable() -> AnyView {
        AnyView(InteractivePostCatalogScreen(context: viewModel.context))
    }
}

/// The post page over the catalogue, on the same view model: the catalogue
/// below keeps its place for the way back.
final class InteractivePostCatalogPostScreenCoordinator: CoordinatorProtocol {
    private let viewModel: InteractivePostCatalogScreenViewModelProtocol

    init(viewModel: InteractivePostCatalogScreenViewModelProtocol) {
        self.viewModel = viewModel
    }

    func toPresentable() -> AnyView {
        AnyView(InteractivePostCatalogPostScreen(context: viewModel.context))
    }
}

/// Yours, over the catalogue on the same stack.
final class InteractivePostCatalogYoursScreenCoordinator: CoordinatorProtocol {
    private let viewModel: InteractivePostCatalogScreenViewModelProtocol

    init(viewModel: InteractivePostCatalogScreenViewModelProtocol) {
        self.viewModel = viewModel
    }

    func toPresentable() -> AnyView {
        AnyView(InteractivePostCatalogYoursScreen(context: viewModel.context))
    }
}
