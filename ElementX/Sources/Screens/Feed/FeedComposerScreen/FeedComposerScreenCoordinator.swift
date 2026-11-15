//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import SwiftUI

struct FeedComposerScreenCoordinatorParameters {
    let feedService: FeedServiceProtocol
    let clientProxy: ClientProxyProtocol
    let mediaProvider: MediaProviderProtocol
}

enum FeedComposerScreenCoordinatorAction {
    /// The sheet closes; the store sends the post with the composer's key.
    case send(text: String, idempotencyKey: UUID)
    case dismiss
}

final class FeedComposerScreenCoordinator: CoordinatorProtocol {
    let viewModel: FeedComposerScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<FeedComposerScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<FeedComposerScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: FeedComposerScreenCoordinatorParameters) {
        viewModel = FeedComposerScreenViewModel(feedService: parameters.feedService,
                                                clientProxy: parameters.clientProxy,
                                                mediaProvider: parameters.mediaProvider)
    }

    func start() {
        viewModel.actionsPublisher
            .sink { [weak self] action in
                switch action {
                case .send(let text, let idempotencyKey):
                    self?.actionsSubject.send(.send(text: text, idempotencyKey: idempotencyKey))
                case .dismiss:
                    self?.actionsSubject.send(.dismiss)
                }
            }
            .store(in: &cancellables)
    }

    func stop() {
        viewModel.stop()
    }

    func toPresentable() -> AnyView {
        AnyView(FeedComposerScreen(context: viewModel.context))
    }
}
