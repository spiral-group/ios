//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import SwiftUI

struct FeedReportScreenCoordinatorParameters {
    let target: FeedReportTarget
    let feedService: FeedServiceProtocol
}

enum FeedReportScreenCoordinatorAction {
    case dismiss
}

final class FeedReportScreenCoordinator: CoordinatorProtocol {
    let viewModel: FeedReportScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<FeedReportScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<FeedReportScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: FeedReportScreenCoordinatorParameters) {
        viewModel = FeedReportScreenViewModel(target: parameters.target, feedService: parameters.feedService)
    }

    func start() {
        viewModel.actionsPublisher
            .sink { [weak self] action in
                switch action {
                case .dismiss:
                    self?.actionsSubject.send(.dismiss)
                }
            }
            .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(FeedReportScreen(context: viewModel.context))
    }
}
