//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (question 412): the catalogue as a room opens it — in a sheet,
// on its own stack — from the preview fixture. A card pushes the post page and
// «Yours» pushes Yours on the same view model; nothing runs.
//

import Combine
import SwiftUI

final class InteractivePostCatalogHarness {
    let stack = NavigationStackCoordinator()

    private let viewModel: InteractivePostCatalogScreenViewModel
    private var cancellable: AnyCancellable?

    init(hasSeenIntroduction: Bool, cancel: @escaping () -> Void) {
        viewModel = InteractivePostCatalogPreviewFixture.viewModel(hasSeenIntroduction: hasSeenIntroduction, peopleInRoom: 5,
                                                                   newIDs: InteractivePostCatalogPreviewFixture.severalNewIDs)
        stack.setRootCoordinator(InteractivePostCatalogHarnessScreenCoordinator(viewModel: viewModel))
        cancellable = viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .showPost:
                stack.push(InteractivePostCatalogPostScreenCoordinator(viewModel: viewModel))
            case .showYours:
                stack.push(InteractivePostCatalogYoursScreenCoordinator(viewModel: viewModel))
            case .changeTemplate, .startNew:
                // A thread in place of the real one.
                stack.push(BlankFormCoordinator())
            case .cancel:
                cancel()
            case .openThread, .publishTemplate, .showAgents, .retryAgents:
                break
            }
        }
    }
}

private final class InteractivePostCatalogHarnessScreenCoordinator: CoordinatorProtocol {
    private let viewModel: InteractivePostCatalogScreenViewModel

    init(viewModel: InteractivePostCatalogScreenViewModel) {
        self.viewModel = viewModel
    }

    func toPresentable() -> AnyView {
        AnyView(InteractivePostCatalogScreen(context: viewModel.context))
    }
}
