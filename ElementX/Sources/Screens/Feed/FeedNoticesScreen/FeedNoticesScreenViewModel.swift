//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The person's moderation notices, read
// again while they show on `feed.notice` (decision 289): no pull to refresh.
//

import Combine
import SwiftUI

typealias FeedNoticesScreenViewModelType = StateStoreViewModelV2<FeedNoticesScreenViewState, FeedNoticesScreenViewAction>

protocol FeedNoticesScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<FeedNoticesScreenViewModelAction, Never> { get }
    var context: FeedNoticesScreenViewModelType.Context { get }
}

class FeedNoticesScreenViewModel: FeedNoticesScreenViewModelType, FeedNoticesScreenViewModelProtocol {
    static let pageSize = 20

    private let feedService: FeedServiceProtocol
    private let store: FeedStore
    private let userIndicatorController: UserIndicatorControllerProtocol
    /// The app's language, for the rules' texts.
    private let language: String?
    /// Bumped by every first page, so an older page's answer is dropped.
    private var loadGeneration: UInt64 = 0
    /// Notices being marked read: one request each, whatever scrolls by.
    private var markingRead: Set<String> = []

    private let actionsSubject: PassthroughSubject<FeedNoticesScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<FeedNoticesScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(feedService: FeedServiceProtocol,
         store: FeedStore,
         userIndicatorController: UserIndicatorControllerProtocol,
         language: String? = FeedAppLanguage.current) {
        self.feedService = feedService
        self.store = store
        self.userIndicatorController = userIndicatorController
        self.language = language
        super.init(initialViewState: FeedNoticesScreenViewState(syncStatus: store.syncStatus))

        store.observe { [weak self] in
            guard let self else { return false }
            if state.syncStatus != store.syncStatus {
                state.syncStatus = store.syncStatus
            }
            return true
        }

        Task { await loadFirstPage() }
    }

    isolated deinit {
        store.stopShowing(.notices, by: self)
    }

    override func process(viewAction: FeedNoticesScreenViewAction) {
        switch viewAction {
        case .appeared:
            store.show(.notices, by: self) { [weak self] in
                await self?.loadFirstPage(isReadAgain: true) ?? false
            }
        case .disappeared:
            store.stopShowing(.notices, by: self)
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
        case .noticeAppeared(let noticeID):
            Task { await markRead(noticeID) }
        case .openPost(let postID):
            actionsSubject.send(.openPost(postID: postID))
        }
    }

    /// - Parameters:
    ///   - isManual: Retry; over the read window it says "slow down" rather than wait.
    ///   - isReadAgain: the sync said they changed; a failure leaves what is shown without a word.
    @discardableResult
    func loadFirstPage(isManual: Bool = false, isReadAgain: Bool = false) async -> Bool {
        loadGeneration += 1
        let generation = loadGeneration
        let read = { [feedService, language] in await feedService.notices(cursor: nil, limit: Self.pageSize, language: language) }
        let result = isManual ? await read() : await FeedReadWindow.retryingOnce(read)
        guard generation == loadGeneration else { return false }

        switch result {
        case .success(let page):
            state.listState = .loaded(page.items.map(FeedNoticeItem.init), loadMore: Self.loadMore(after: page))
            recordList(nextCursor: page.nextCursor)
            return true
        case .failure(.unavailable):
            state.listState = .unavailable
            return false
        case .failure(let error):
            MXLog.error("Failed to read the feed notices: \(error)")
            // What is shown stays; only a list never read becomes "couldn't load".
            if case .loaded = state.listState {
                if !error.isRateLimited, !isReadAgain {
                    userIndicatorController.submitIndicator(UserIndicator(type: .toast, title: UntranslatedL10n.screenFeedNoticesRefreshFailed, icon: \.close))
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

    private func loadNextPage(after items: [FeedNoticeItem], cursor: String, isManual: Bool) async {
        let generation = loadGeneration
        state.listState = .loaded(items, loadMore: .loading)
        let read = { [feedService, language] in await feedService.notices(cursor: cursor, limit: Self.pageSize, language: language) }
        let result = isManual ? await read() : await FeedReadWindow.retryingOnce(read)
        guard generation == loadGeneration, case .loaded(let current, _) = state.listState else { return }

        switch result {
        case .success(let page):
            let shown = Set(current.map(\.id))
            let added = page.items.filter { !shown.contains($0.id) }.map(FeedNoticeItem.init)
            state.listState = .loaded(current + added, loadMore: Self.loadMore(after: page))
            recordList(nextCursor: page.nextCursor)
        case .failure(.invalidCursor):
            await loadFirstPage()
        case .failure(let error):
            MXLog.error("Failed to read more feed notices: \(error)")
            state.listState = .loaded(current, loadMore: .failed(cursor: cursor))
            if isManual, error.isRateLimited {
                FeedReadWindow.showSlowDown(userIndicatorController)
            }
        }
    }

    /// Read once the server says so; a failure leaves it unread, to be tried on its next appearance.
    func markRead(_ noticeID: String) async {
        guard let item = state.items.first(where: { $0.id == noticeID }), !item.notice.isRead,
              markingRead.insert(noticeID).inserted else { return }
        defer { markingRead.remove(noticeID) }

        switch await feedService.markNoticeRead(id: noticeID) {
        case .success, .failure(.notFound):
            // A 404 is a notice that is not the person's any more (the account's notices went): nothing is unread there.
            guard case .loaded(var items, let loadMore) = state.listState,
                  let index = items.firstIndex(where: { $0.id == noticeID }) else { return }
            items[index].notice.isRead = true
            state.listState = .loaded(items, loadMore: loadMore)
        case .failure:
            break // Logged by the service.
        }
    }

    private static func loadMore(after page: FeedNoticePage) -> LoadMoreState {
        page.nextCursor.map { .idle(cursor: $0) } ?? .exhausted
    }

    /// The store holds the list's ids, so the sync marks it stale while this screen lives.
    private func recordList(nextCursor: String?) {
        store.setList(.notices, FeedStoreList(ids: state.items.map(\.id), nextCursor: nextCursor))
    }
}
