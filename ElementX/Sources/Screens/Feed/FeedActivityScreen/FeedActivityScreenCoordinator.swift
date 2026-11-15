//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import SwiftUI

struct FeedActivityScreenCoordinatorParameters {
    let feedService: FeedServiceProtocol
    /// The session's store: Activity is read again when the sync says it changed.
    let store: FeedStore
    let mediaProvider: MediaProviderProtocol
    let userIndicatorController: UserIndicatorControllerProtocol
}

enum FeedActivityScreenCoordinatorAction {
    case openPost(postID: String, commentID: String?)
    case openNotices
}

final class FeedActivityScreenCoordinator: CoordinatorProtocol {
    let viewModel: FeedActivityScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<FeedActivityScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<FeedActivityScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: FeedActivityScreenCoordinatorParameters) {
        viewModel = FeedActivityScreenViewModel(feedService: parameters.feedService,
                                                store: parameters.store,
                                                mediaProvider: parameters.mediaProvider,
                                                userIndicatorController: parameters.userIndicatorController)
    }

    func start() {
        viewModel.actionsPublisher
            .sink { [weak self] action in
                switch action {
                case .openPost(let postID, let commentID):
                    self?.actionsSubject.send(.openPost(postID: postID, commentID: commentID))
                case .openNotices:
                    self?.actionsSubject.send(.openNotices)
                }
            }
            .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(FeedActivityScreen(context: viewModel.context))
    }
}
