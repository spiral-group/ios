//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import SwiftUI

struct FeedScreenCoordinatorParameters {
    let feedService: FeedServiceProtocol
    /// The session's one controller, shared by every feed screen.
    let engagement: FeedEngagementController
    let clientProxy: ClientProxyProtocol
    let mediaProvider: MediaProviderProtocol
    let userIndicatorController: UserIndicatorControllerProtocol
}

enum FeedScreenCoordinatorAction {
    case openPost(FeedPost)
    case openAuthor(FeedAuthor)
    case compose
    case openOwnPosts
    case share(FeedPost)
    case report(FeedReportTarget)
    case openActivity
    case openLikers(postID: String)
    case published(FeedPost)
}

final class FeedScreenCoordinator: CoordinatorProtocol {
    let viewModel: FeedScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<FeedScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<FeedScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: FeedScreenCoordinatorParameters) {
        viewModel = FeedScreenViewModel(feedService: parameters.feedService,
                                        engagement: parameters.engagement,
                                        clientProxy: parameters.clientProxy,
                                        mediaProvider: parameters.mediaProvider,
                                        userIndicatorController: parameters.userIndicatorController)
    }

    func start() {
        viewModel.actionsPublisher
            .sink { [weak self] action in
                switch action {
                case .openPost(let post):
                    self?.actionsSubject.send(.openPost(post))
                case .openAuthor(let author):
                    self?.actionsSubject.send(.openAuthor(author))
                case .compose:
                    self?.actionsSubject.send(.compose)
                case .openOwnPosts:
                    self?.actionsSubject.send(.openOwnPosts)
                case .share(let post):
                    self?.actionsSubject.send(.share(post))
                case .report(let target):
                    self?.actionsSubject.send(.report(target))
                case .openActivity:
                    self?.actionsSubject.send(.openActivity)
                case .openLikers(let postID):
                    self?.actionsSubject.send(.openLikers(postID: postID))
                case .published(let post):
                    self?.actionsSubject.send(.published(post))
                }
            }
            .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(FeedScreen(context: viewModel.context))
    }
}
