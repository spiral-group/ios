//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Lane I5: who liked a post, read again
// while it shows when the post's likes move (decision 289).
//

import Combine
import SwiftUI

typealias FeedLikersScreenViewModelType = StateStoreViewModelV2<FeedLikersScreenViewState, FeedLikersScreenViewAction>

protocol FeedLikersScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<FeedLikersScreenViewModelAction, Never> { get }
    var context: FeedLikersScreenViewModelType.Context { get }
}

class FeedLikersScreenViewModel: FeedLikersScreenViewModelType, FeedLikersScreenViewModelProtocol {
    static let pageSize = 30

    private let postID: String
    private let feedService: FeedServiceProtocol
    private let store: FeedStore
    private let userIndicatorController: UserIndicatorControllerProtocol
    private var loadGeneration: UInt64 = 0

    private let actionsSubject: PassthroughSubject<FeedLikersScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<FeedLikersScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(postID: String,
         feedService: FeedServiceProtocol,
         store: FeedStore,
         clientProxy: ClientProxyProtocol,
         mediaProvider: MediaProviderProtocol,
         userIndicatorController: UserIndicatorControllerProtocol) {
        self.postID = postID
        self.feedService = feedService
        self.store = store
        self.userIndicatorController = userIndicatorController
        super.init(initialViewState: FeedLikersScreenViewState(syncStatus: store.syncStatus), mediaProvider: mediaProvider)

        store.observe { [weak self] in
            guard let self else { return false }
            if state.syncStatus != store.syncStatus {
                state.syncStatus = store.syncStatus
            }
            return true
        }

        clientProxy.ignoredUsersPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] userIDs in
                self?.state.blockedUserIDs = Set(userIDs ?? [])
            }
            .store(in: &cancellables)

        Task { await loadFirstPage() }
    }

    isolated deinit {
        store.stopShowing(.likers(postID: postID), by: self)
    }

    override func process(viewAction: FeedLikersScreenViewAction) {
        switch viewAction {
        case .appeared:
            store.show(.likers(postID: postID), by: self) { [weak self] in
                await self?.loadFirstPage() ?? false
            }
        case .disappeared:
            store.stopShowing(.likers(postID: postID), by: self)
        case .retry:
            state.listState = .loading
            Task { await loadFirstPage(isManual: true) }
        case .loadMore:
            guard case .loaded(let likers, let loadMore) = state.listState else { return }
            switch loadMore {
            case .idle(let cursor):
                Task { await loadNextPage(after: likers, cursor: cursor, isManual: false) }
            case .failed(let cursor):
                Task { await loadNextPage(after: likers, cursor: cursor, isManual: true) }
            case .loading, .exhausted:
                return
            }
        case .openAuthor(let userID):
            guard let liker = state.likers.first(where: { $0.author.userID == userID }) else { return }
            actionsSubject.send(.openAuthor(liker.author))
        }
    }

    /// A failed read again leaves who was shown.
    /// - Parameter isManual: Retry; over the read window it says "slow down" rather than wait.
    @discardableResult
    func loadFirstPage(isManual: Bool = false) async -> Bool {
        loadGeneration += 1
        let generation = loadGeneration
        let read = { [feedService, postID] in await feedService.likers(postID: postID, cursor: nil, limit: Self.pageSize) }
        let result = isManual ? await read() : await FeedReadWindow.retryingOnce(read)
        guard generation == loadGeneration else { return false }

        switch result {
        case .success(let page):
            state.listState = .loaded(page.items, loadMore: Self.loadMore(after: page))
            recordList(nextCursor: page.nextCursor)
            return true
        case .failure(.notFound):
            state.listState = .notAvailable
        case .failure(.unavailable):
            state.listState = .unavailable
        case .failure(let error):
            MXLog.error("Failed to read who liked feed post \(postID): \(error)")
            if case .loaded = state.listState {
                // What is shown stays.
            } else {
                state.listState = .failed
            }
            if isManual, error.isRateLimited {
                FeedReadWindow.showSlowDown(userIndicatorController)
            }
        }
        return false
    }

    private func loadNextPage(after likers: [FeedLiker], cursor: String, isManual: Bool) async {
        let generation = loadGeneration
        state.listState = .loaded(likers, loadMore: .loading)
        let read = { [feedService, postID] in await feedService.likers(postID: postID, cursor: cursor, limit: Self.pageSize) }
        let result = isManual ? await read() : await FeedReadWindow.retryingOnce(read)
        guard generation == loadGeneration, case .loaded(let current, _) = state.listState else { return }

        switch result {
        case .success(let page):
            let shown = Set(current.map(\.id))
            state.listState = .loaded(current + page.items.filter { !shown.contains($0.id) }, loadMore: Self.loadMore(after: page))
            recordList(nextCursor: page.nextCursor)
        case .failure(.invalidCursor):
            await loadFirstPage()
        case .failure(let error):
            MXLog.error("Failed to read more of who liked feed post \(postID): \(error)")
            state.listState = .loaded(current, loadMore: .failed(cursor: cursor))
            if isManual, error.isRateLimited {
                FeedReadWindow.showSlowDown(userIndicatorController)
            }
        }
    }

    private static func loadMore(after page: FeedLikersPage) -> LoadMoreState {
        page.nextCursor.map { .idle(cursor: $0) } ?? .exhausted
    }

    /// The store holds the list's ids, so the sync marks it stale while this screen lives.
    private func recordList(nextCursor: String?) {
        store.setList(.likers(postID: postID), FeedStoreList(ids: state.likers.map(\.id), nextCursor: nextCursor))
    }
}
