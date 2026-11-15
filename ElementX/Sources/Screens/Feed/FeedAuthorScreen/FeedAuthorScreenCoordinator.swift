//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import SwiftUI

struct FeedAuthorScreenCoordinatorParameters {
    let author: FeedAuthor
    let feedService: FeedServiceProtocol
    /// The session's one controller, shared by every feed screen.
    let engagement: FeedEngagementController
    let clientProxy: ClientProxyProtocol
    let mediaProvider: MediaProviderProtocol
    let userIndicatorController: UserIndicatorControllerProtocol
}

enum FeedAuthorScreenCoordinatorAction {
    case openRoom(roomID: String)
    case openPost(FeedPost)
    case report(FeedReportTarget)
    case dismiss
}

final class FeedAuthorScreenCoordinator: CoordinatorProtocol {
    let viewModel: FeedAuthorScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<FeedAuthorScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<FeedAuthorScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: FeedAuthorScreenCoordinatorParameters) {
        viewModel = FeedAuthorScreenViewModel(author: parameters.author,
                                              feedService: parameters.feedService,
                                              engagement: parameters.engagement,
                                              clientProxy: parameters.clientProxy,
                                              mediaProvider: parameters.mediaProvider,
                                              userIndicatorController: parameters.userIndicatorController)
    }

    func start() {
        viewModel.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .openRoom(let roomID):
                    actionsSubject.send(.openRoom(roomID: roomID))
                case .openPost(let post):
                    actionsSubject.send(.openPost(post))
                case .report(let target):
                    actionsSubject.send(.report(target))
                case .dismiss:
                    actionsSubject.send(.dismiss)
                }
            }
            .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(FeedAuthorScreen(context: viewModel.context))
    }
}
