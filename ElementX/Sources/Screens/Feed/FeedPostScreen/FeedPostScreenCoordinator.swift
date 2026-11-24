//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import SwiftUI

struct FeedPostScreenCoordinatorParameters {
    let postID: String
    /// The post as a list showed it; `nil` when opened from a link.
    let post: FeedPost?
    /// Lane I5: the comment an Activity entry opens at.
    var focusedCommentID: String?
    let feedService: FeedServiceProtocol
    /// The session's one controller, shared by every feed screen.
    let engagement: FeedEngagementController
    let clientProxy: ClientProxyProtocol
    let mediaProvider: MediaProviderProtocol
    let userIndicatorController: UserIndicatorControllerProtocol
}

enum FeedPostScreenCoordinatorAction {
    case openAuthor(FeedAuthor)
    case deleted
    case share(FeedPost)
    case report(FeedReportTarget)
    case openNotices
    case openLikers(postID: String)
}

final class FeedPostScreenCoordinator: CoordinatorProtocol {
    let viewModel: FeedPostScreenViewModelProtocol
    /// The post shown: a second ask for it while it is on top is dropped.
    let postID: String
    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<FeedPostScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<FeedPostScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: FeedPostScreenCoordinatorParameters) {
        postID = parameters.postID
        viewModel = FeedPostScreenViewModel(postID: parameters.postID,
                                            post: parameters.post,
                                            focusedCommentID: parameters.focusedCommentID,
                                            feedService: parameters.feedService,
                                            engagement: parameters.engagement,
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
                case .deleted:
                    self?.actionsSubject.send(.deleted)
                case .share(let post):
                    self?.actionsSubject.send(.share(post))
                case .report(let target):
                    self?.actionsSubject.send(.report(target))
                case .openNotices:
                    self?.actionsSubject.send(.openNotices)
                case .openLikers(let postID):
                    self?.actionsSubject.send(.openLikers(postID: postID))
                }
            }
            .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(FeedPostScreen(context: viewModel.context))
    }
}
