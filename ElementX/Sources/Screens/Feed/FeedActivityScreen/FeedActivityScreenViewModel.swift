//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Lane I5: the person's activity page by
// page. The first page read marks what it shows seen (`POST
// /feed/activity/seen` up to its newest entry), which clears the badge on the
// bell and the Feed tab; the dots stay on screen until the next read. While it
// shows, `feed.activity` from the sync stream reads it again (decision 289):
// there is no pull to refresh.
//

import Combine
import SwiftUI

typealias FeedActivityScreenViewModelType = StateStoreViewModelV2<FeedActivityScreenViewState, FeedActivityScreenViewAction>

protocol FeedActivityScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<FeedActivityScreenViewModelAction, Never> { get }
    var context: FeedActivityScreenViewModelType.Context { get }
}

class FeedActivityScreenViewModel: FeedActivityScreenViewModelType, FeedActivityScreenViewModelProtocol {
    static let pageSize = 20

    private let feedService: FeedServiceProtocol
    private let store: FeedStore
    private let userIndicatorController: UserIndicatorControllerProtocol
    /// Bumped by every first page, so an older page's answer is dropped.
    private var loadGeneration: UInt64 = 0

    private let actionsSubject: PassthroughSubject<FeedActivityScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<FeedActivityScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(feedService: FeedServiceProtocol, store: FeedStore, mediaProvider: MediaProviderProtocol, userIndicatorController: UserIndicatorControllerProtocol) {
        self.feedService = feedService
        self.store = store
        self.userIndicatorController = userIndicatorController
        super.init(initialViewState: FeedActivityScreenViewState(syncStatus: store.syncStatus), mediaProvider: mediaProvider)

        store.observe { [weak self] in
            guard let self else { return false }
            if state.syncStatus != store.syncStatus {
                state.syncStatus = store.syncStatus
            }
            return true
        }

        feedService.noticesUnreadPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] unread in
                self?.state.unreadNotices = unread
                // A notice read on its own screen is still a notice: the row stays.
                if unread > 0 {
                    self?.state.hasNotices = true
                }
            }
            .store(in: &cancellables)

        Task { await loadFirstPage() }
        Task { await refreshUnreadNotices() }
    }

    isolated deinit {
        store.stopShowing(.activity, by: self)
    }

    override func process(viewAction: FeedActivityScreenViewAction) {
        switch viewAction {
        case .appeared:
            store.show(.activity, by: self) { [weak self] in
                await self?.loadFirstPage(isReadAgain: true) ?? false
            }
        case .disappeared:
            store.stopShowing(.activity, by: self)
        case .retry:
            Task { await loadFirstPage(isManual: true) }
        case .loadMore:
            guard case .loaded(let items, let loadMore) = state.listState else { return }
            switch loadMore {
            case .idle(let cursor):
                Task { await loadNextPage(after: items, cursor: cursor, isManual: false) }
            case .failed(let cursor):
                // The failed row is a tap.
                Task { await loadNextPage(after: items, cursor: cursor, isManual: true) }
            case .loading, .exhausted:
                return
            }
        case .open(let entryID):
            guard let item = state.items.first(where: { $0.id == entryID }) else { return }
            actionsSubject.send(.openPost(postID: item.entry.postID, commentID: item.entry.commentID))
        case .reveal(let entryID):
            state.revealedEntryIDs.insert(entryID)
        case .openNotices:
            actionsSubject.send(.openNotices)
        }
    }

    /// - Parameters:
    ///   - isManual: Retry; over the read window it says "slow down" rather than wait.
    ///   - isReadAgain: the sync said it changed; a failure leaves what is shown without a word.
    @discardableResult
    func loadFirstPage(isManual: Bool = false, isReadAgain: Bool = false) async -> Bool {
        loadGeneration += 1
        let generation = loadGeneration
        let read = { [feedService] in await feedService.activity(cursor: nil, limit: Self.pageSize) }
        let result = isManual ? await read() : await FeedReadWindow.retryingOnce(read)
        guard generation == loadGeneration else { return false }

        switch result {
        case .success(let page):
            state.listState = .loaded(page.items.map(FeedActivityItem.init), loadMore: Self.loadMore(after: page))
            recordList(nextCursor: page.nextCursor)
            if page.unread > 0 {
                await markSeen(page)
            }
            return true
        case .failure(.unavailable):
            state.listState = .unavailable
            return false
        case .failure(let error):
            MXLog.error("Failed to read the feed activity: \(error)")
            // What is shown stays; only a list never read becomes "couldn't load".
            if case .loaded = state.listState {
                if !error.isRateLimited, !isReadAgain {
                    userIndicatorController.submitIndicator(UserIndicator(type: .toast, title: UntranslatedL10n.screenFeedActivityRefreshFailed, icon: \.close))
                }
            } else {
                state.listState = .failed
            }
            if isManual, error.isRateLimited {
                FeedReadWindow.showSlowDown(userIndicatorController)
            }
            return false
        }
    }

    private func loadNextPage(after items: [FeedActivityItem], cursor: String, isManual: Bool) async {
        let generation = loadGeneration
        state.listState = .loaded(items, loadMore: .loading)
        let read = { [feedService] in await feedService.activity(cursor: cursor, limit: Self.pageSize) }
        let result = isManual ? await read() : await FeedReadWindow.retryingOnce(read)
        guard generation == loadGeneration, case .loaded(let current, _) = state.listState else { return }

        switch result {
        case .success(let page):
            // A like group that gained a like moved to the top with the same id: the one shown wins.
            let shown = Set(current.map(\.id))
            let added = page.items.filter { !shown.contains($0.id) }.map(FeedActivityItem.init)
            state.listState = .loaded(current + added, loadMore: Self.loadMore(after: page))
            recordList(nextCursor: page.nextCursor)
        case .failure(.invalidCursor):
            await loadFirstPage()
        case .failure(let error):
            MXLog.error("Failed to read more feed activity: \(error)")
            state.listState = .loaded(current, loadMore: .failed(cursor: cursor))
            if isManual, error.isRateLimited {
                FeedReadWindow.showSlowDown(userIndicatorController)
            }
        }
    }

    /// Up to the newest entry the server sent, one of a kind this build skips
    /// included, so it is not unread for ever (now, for an empty page): the
    /// server's answer is the badge. A failure leaves the badge as it was.
    private func markSeen(_ page: FeedActivityPage) async {
        _ = await feedService.markActivitySeen(upTo: page.newestAt)
    }

    /// One notice is enough: it says whether there are any, and the page carries
    /// the unread count, which the service publishes. A failed read shows the row.
    private func refreshUnreadNotices() async {
        switch await FeedReadWindow.retryingOnce({ [feedService] in await feedService.notices(cursor: nil, limit: 1, language: nil) }) {
        case .success(let page):
            state.hasNotices = !page.items.isEmpty
        case .failure(let error):
            MXLog.info("Could not read the feed notices' unread count: \(error)")
            state.hasNotices = true
        }
    }

    private static func loadMore(after page: FeedActivityPage) -> LoadMoreState {
        page.nextCursor.map { .idle(cursor: $0) } ?? .exhausted
    }

    /// The store holds the list's ids, so the sync marks it stale while this screen lives.
    private func recordList(nextCursor: String?) {
        store.setList(.activity, FeedStoreList(ids: state.items.map(\.id), nextCursor: nextCursor))
    }
}
