//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import SwiftUI

struct FeedLikersScreenCoordinatorParameters {
    let postID: String
    let feedService: FeedServiceProtocol
    /// The session's store: the list is read again when the post's likes move.
    let store: FeedStore
    let clientProxy: ClientProxyProtocol
    let mediaProvider: MediaProviderProtocol
    let userIndicatorController: UserIndicatorControllerProtocol
}

enum FeedLikersScreenCoordinatorAction {
    case openAuthor(FeedAuthor)
    case dismiss
}

final class FeedLikersScreenCoordinator: CoordinatorProtocol {
    let viewModel: FeedLikersScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<FeedLikersScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<FeedLikersScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: FeedLikersScreenCoordinatorParameters) {
        viewModel = FeedLikersScreenViewModel(postID: parameters.postID,
                                              feedService: parameters.feedService,
                                              store: parameters.store,
                                              clientProxy: parameters.clientProxy,
                                              mediaProvider: parameters.mediaProvider,
                                              userIndicatorController: parameters.userIndicatorController)
    }

    func start() {
        viewModel.actionsPublisher
            .sink { [weak self] action in
                switch action {
                case .openAuthor(let author):
                    self?.actionsSubject.send(.openAuthor(author))
                }
            }
            .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(FeedLikersScreen(context: viewModel.context) { [weak self] in
            self?.actionsSubject.send(.dismiss)
        })
    }
}
