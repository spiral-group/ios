//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import SwiftUI

struct FeedNoticesScreenCoordinatorParameters {
    let feedService: FeedServiceProtocol
    /// The session's store: the notices are read again on `feed.notice`.
    let store: FeedStore
    let userIndicatorController: UserIndicatorControllerProtocol
}

enum FeedNoticesScreenCoordinatorAction {
    case openPost(postID: String)
}

final class FeedNoticesScreenCoordinator: CoordinatorProtocol {
    private let viewModel: FeedNoticesScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<FeedNoticesScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<FeedNoticesScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: FeedNoticesScreenCoordinatorParameters) {
        viewModel = FeedNoticesScreenViewModel(feedService: parameters.feedService,
                                               store: parameters.store,
                                               userIndicatorController: parameters.userIndicatorController)
    }

    func start() {
        viewModel.actionsPublisher
            .sink { [weak self] action in
                switch action {
                case .openPost(let postID):
                    self?.actionsSubject.send(.openPost(postID: postID))
                }
            }
            .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(FeedNoticesScreen(context: viewModel.context))
    }
}
