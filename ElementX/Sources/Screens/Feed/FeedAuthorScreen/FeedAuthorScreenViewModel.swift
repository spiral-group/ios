//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Block is the messenger's ignore list,
// so it is global: the confirmation says so, and the feed, the chats and the
// person's agents all follow it (decision 98 syncs it to the platform). The
// posts are the session's `FeedStore`'s; while the sheet shows, the sync's
// changes read its first page again (decision 289).
//

import Combine
import SwiftUI

typealias FeedAuthorScreenViewModelType = StateStoreViewModelV2<FeedAuthorScreenViewState, FeedAuthorScreenViewAction>

protocol FeedAuthorScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<FeedAuthorScreenViewModelAction, Never> { get }
    var context: FeedAuthorScreenViewModelType.Context { get }
}

class FeedAuthorScreenViewModel: FeedAuthorScreenViewModelType, FeedAuthorScreenViewModelProtocol {
    static let pageSize = 20

    private let feedService: FeedServiceProtocol
    private let clientProxy: ClientProxyProtocol
    private let mediaProvider: MediaProviderProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    private let engagement: FeedEngagementController
    private var store: FeedStore {
        engagement.store
    }

    /// The person's own sheet holds their posts in every state.
    private let listID: FeedListID

    /// What the list is, apart from its posts, which are the store's.
    private enum Content: Equatable {
        case loading
        case loaded(LoadMoreState)
        case notAvailable
        case unavailable
        case failed
    }

    private var content: Content = .loading
    private var itemCache: [String: FeedItem] = [:]
    private var loadGeneration: UInt64 = 0

    private let actionsSubject: PassthroughSubject<FeedAuthorScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<FeedAuthorScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(author: FeedAuthor,
         feedService: FeedServiceProtocol,
         engagement: FeedEngagementController,
         clientProxy: ClientProxyProtocol,
         mediaProvider: MediaProviderProtocol,
         userIndicatorController: UserIndicatorControllerProtocol) {
        self.feedService = feedService
        self.clientProxy = clientProxy
        self.mediaProvider = mediaProvider
        self.userIndicatorController = userIndicatorController
        self.engagement = engagement
        let isOwnProfile = author.userID == clientProxy.userID
        listID = isOwnProfile ? .ownPosts : .author(userID: author.userID)
        super.init(initialViewState: FeedAuthorScreenViewState(author: author, isOwnProfile: isOwnProfile),
                   mediaProvider: mediaProvider)

        clientProxy.ignoredUsersPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] userIDs in
                self?.state.isBlocked = userIDs?.contains(author.userID) ?? false
            }
            .store(in: &cancellables)

        clientProxy.timelineMediaVisibilityPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visibility in
                self?.state.hidesMedia = visibility != .always
            }
            .store(in: &cancellables)

        store.observe { [weak self] in
            self?.rebuild()
            return self != nil
        }
        rebuild()

        Task { await loadFirstPage() }
    }

    isolated deinit {
        store.stopShowing(listID, by: self)
    }

    override func process(viewAction: FeedAuthorScreenViewAction) {
        switch viewAction {
        case .appeared:
            store.show(listID, by: self) { [weak self] in
                await self?.readAgain() ?? false
            }
        case .disappeared:
            store.stopShowing(listID, by: self)
        case .retry:
            Task { await loadFirstPage(isManual: true) }
        case .loadMore:
            guard case .loaded(let loadMore) = content else { return }
            switch loadMore {
            case .idle where state.isReadOnPaused:
                state.isReadOnPaused = false
                Task { await readOnIfNothingNew(shownBefore: shownCount) }
            case .idle(let cursor):
                Task { await loadNextPage(cursor: cursor, isManual: false) }
            case .failed(let cursor):
                // The failed row is a tap.
                Task { await loadNextPage(cursor: cursor, isManual: true) }
            case .loading, .exhausted:
                return
            }
        case .message:
            guard state.canMessage else { return }
            openDirectChat()
        case .block:
            guard state.canBlock else { return }
            confirmBlock()
        case .report:
            guard !state.isOwnProfile else { return }
            actionsSubject.send(.report(.author(userID: state.author.userID)))
        case .dismiss:
            actionsSubject.send(.dismiss)
        case .card(let postID, let action):
            handleCardAction(action, postID: postID)
        }
    }

    // MARK: - The store

    private func rebuild() {
        var cache: [String: FeedItem] = [:]
        let items = store.posts(in: listID).map { post in
            let item = itemCache[post.id].flatMap { $0.post == post ? $0 : nil } ?? FeedItem(post: post)
            cache[post.id] = item
            return item
        }
        itemCache = cache
        let postsState: FeedAuthorPostsState = switch content {
        case .loading: .loading
        case .loaded(let loadMore): .loaded(items, loadMore: loadMore)
        case .notAvailable: .notAvailable
        case .unavailable: .unavailable
        case .failed: .failed
        }
        if state.postsState != postsState {
            state.postsState = postsState
        }
        if state.syncStatus != store.syncStatus {
            state.syncStatus = store.syncStatus
        }
    }

    private func setContent(_ content: Content) {
        self.content = content
        rebuild()
    }

    private var shownCount: Int {
        store.list(listID)?.ids.count ?? 0
    }

    // MARK: - Posts

    /// - Parameter isManual: Retry; over the read window it says "slow down" rather than wait.
    @discardableResult
    func loadFirstPage(isManual: Bool = false) async -> Bool {
        loadGeneration += 1
        let generation = loadGeneration
        let previous = content
        if case .loaded = previous {
            // Stays until the new page is in.
        } else {
            setContent(.loading)
        }

        let result = isManual ? await page(cursor: nil) : await FeedReadWindow.retryingOnce { await page(cursor: nil) }
        guard generation == loadGeneration else { return false }

        switch result {
        case .success(let page):
            store.upsert(page.items)
            store.setList(listID, FeedStoreList(ids: FeedScreenViewModel.ids(of: page.items, excluding: nil), nextCursor: page.nextCursor))
            state.isReadOnPaused = false
            setContent(.loaded(FeedScreenViewModel.loadMore(after: page)))
            await readOnIfNothingNew(shownBefore: 0)
            return true
        case .failure(.notFound):
            setContent(.notAvailable)
        case .failure(.unavailable):
            setContent(.unavailable)
        case .failure(let error):
            MXLog.error("Failed to read an author's feed posts: \(error)")
            // Only the feed's own answers above change what is shown; a failed read again leaves the posts.
            if case .loaded = previous {
                setContent(previous)
            } else {
                setContent(.failed)
            }
            if isManual, error.isRateLimited {
                FeedReadWindow.showSlowDown(userIndicatorController)
            }
        }
        return false
    }

    /// Stale while shown: the first page read again goes on top, and what it no
    /// longer holds within its span leaves; older pages stay as they were read.
    private func readAgain() async -> Bool {
        guard case .loaded = content else { return await loadFirstPage() }
        loadGeneration += 1
        let generation = loadGeneration
        let result = await FeedReadWindow.retryingOnce { await page(cursor: nil) }
        guard generation == loadGeneration else { return false }
        switch result {
        case .success(let page):
            store.upsert(page.items)
            let current = store.list(listID) ?? FeedStoreList(ids: [], nextCursor: page.nextCursor)
            let pageIDs = FeedScreenViewModel.ids(of: page.items, excluding: nil)
            let oldestRead = page.items.map(\.createdAt).min()
            let older = current.ids.filter { id in
                guard !pageIDs.contains(id), page.nextCursor != nil, let post = store.post(id) else { return false }
                return oldestRead.map { post.createdAt < $0 } ?? true
            }
            store.setList(listID, FeedStoreList(ids: pageIDs + older, nextCursor: older.isEmpty ? page.nextCursor : current.nextCursor))
            if older.isEmpty {
                setContent(.loaded(FeedScreenViewModel.loadMore(after: page)))
            } else {
                rebuild()
            }
            return true
        case .failure(let error):
            MXLog.info("Could not read an author's feed posts again: \(error)")
            return false
        }
    }

    private func loadNextPage(cursor: String, isManual: Bool) async {
        let generation = loadGeneration
        state.isReadOnPaused = false
        setContent(.loaded(.loading))

        let result = isManual ? await page(cursor: cursor) : await FeedReadWindow.retryingOnce { await page(cursor: cursor) }
        guard generation == loadGeneration else { return }

        switch result {
        case .success(let page):
            let shownBefore = shownCount
            append(page.items, nextCursor: page.nextCursor)
            setContent(.loaded(FeedScreenViewModel.loadMore(after: page)))
            await readOnIfNothingNew(shownBefore: shownBefore)
        case .failure(.invalidCursor):
            await loadFirstPage()
        case .failure(let error):
            MXLog.error("Failed to read more of an author's feed posts: \(error)")
            setContent(.loaded(.failed(cursor: cursor)))
            if isManual, error.isRateLimited {
                FeedReadWindow.showSlowDown(userIndicatorController)
            }
        }
    }

    private func append(_ posts: [FeedPost], nextCursor: String?) {
        store.upsert(posts)
        let current = store.list(listID)?.ids ?? []
        var seen = Set(current)
        let added = posts.map(\.id).filter { seen.insert($0).inserted }
        store.setList(listID, FeedStoreList(ids: current + added, nextCursor: nextCursor))
    }

    /// The person's own sheet reads `/feed/me/posts`, so a held or removed post
    /// stays findable with its notice and its Delete (lane I2).
    private func page(cursor: String?) async -> Result<FeedPage, FeedError> {
        if state.isOwnProfile {
            await feedService.ownPosts(cursor: cursor, limit: Self.pageSize)
        } else {
            await feedService.authorPosts(userID: state.author.userID, cursor: cursor, limit: Self.pageSize)
        }
    }

    /// An empty page with a cursor is not "No posts yet": read on as Latest does.
    private func readOnIfNothingNew(shownBefore: Int) async {
        guard case .loaded(.idle(let cursor)) = content, shownCount <= shownBefore else { return }
        let generation = loadGeneration
        setContent(.loaded(.loading))

        let readOn = await FeedScreenViewModel.readOn(from: cursor) { _ in
            true
        } read: { cursor in
            await FeedReadWindow.retryingOnce { await self.page(cursor: cursor) }
        } isCurrent: { [weak self] in
            self?.loadGeneration == generation
        }
        guard let readOn, case .loaded = content else { return }
        append(readOn.posts, nextCursor: readOn.loadMore.cursor)
        state.isReadOnPaused = readOn.isPaused
        setContent(.loaded(readOn.loadMore))
    }

    // MARK: - Block

    private func confirmBlock() {
        let name = state.author.displayName
        state.bindings.alertInfo = .init(id: .confirmBlock,
                                         title: UntranslatedL10n.screenFeedAuthorBlockTitle(name),
                                         message: UntranslatedL10n.screenFeedAuthorBlockMessage,
                                         primaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil),
                                         secondaryButton: .init(title: UntranslatedL10n.screenFeedAuthorBlock, role: .destructive) { [weak self] in
                                             Task { await self?.block() }
                                         })
    }

    private func block() async {
        switch await clientProxy.ignoreUser(state.author.userID) {
        case .success:
            // The ignore list's publisher hides their posts everywhere at once.
            actionsSubject.send(.dismiss)
        case .failure(let error):
            MXLog.error("Failed to block a feed author: \(error)")
            state.bindings.alertInfo = .init(id: .blockFailed, title: UntranslatedL10n.screenFeedAuthorBlockFailed)
        }
    }

    // MARK: - Message

    private func openDirectChat() {
        switch clientProxy.directRoomOrPendingInviteForUserID(state.author.userID) {
        case .success(.some(let roomID)):
            actionsSubject.send(.openRoom(roomID: roomID))
        case .success(.none):
            state.bindings.alertInfo = .init(id: .confirmStartChat,
                                             title: UntranslatedL10n.screenFeedAuthorStartChatTitle(state.author.displayName),
                                             primaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil),
                                             secondaryButton: .init(title: L10n.actionStartChat, role: nil) { [weak self] in
                                                 Task { await self?.createDirectChat() }
                                             })
        case .failure(let error):
            MXLog.error("Failed to find a chat with a feed author: \(error)")
            state.bindings.alertInfo = .init(id: .chatFailed, title: UntranslatedL10n.screenFeedAuthorChatFailed)
        }
    }

    private func createDirectChat() async {
        switch await clientProxy.createDirectRoom(with: state.author.userID, expectedRoomName: state.author.name) {
        case .success(let roomID):
            actionsSubject.send(.openRoom(roomID: roomID))
        case .failure(let error):
            MXLog.error("Failed to start a chat with a feed author: \(error)")
            state.bindings.alertInfo = .init(id: .chatFailed, title: UntranslatedL10n.screenFeedAuthorChatFailed)
        }
    }

    // MARK: - Cards

    private func handleCardAction(_ action: FeedPostCardAction, postID: String) {
        guard case .loaded(let items, _) = state.postsState, let item = items.first(where: { $0.id == postID }), item.card.isAvailable else { return }
        switch action {
        case .openPost, .comment, .share:
            // The chat picker is a sheet of its own: this one gives way to the post, which has Share.
            actionsSubject.send(.openPost(item.post))
        case .like:
            Task { await engagement.toggleLike(item.post) }
        case .hide:
            guard item.card.engagement?.canHide == true else { return }
            Task { await engagement.hide(postID: postID) }
        case .report:
            guard item.card.engagement?.canReport == true else { return }
            actionsSubject.send(.report(.post(id: postID)))
        case .openAuthor:
            break // This sheet is theirs.
        case .openLikers:
            break // The count is not a tap on this sheet: the post opens it.
        case .reveal:
            state.revealedPostIDs.insert(postID)
        case .openMedia(let index):
            guard item.card.media.indices.contains(index) else { return }
            Task {
                if let preview = await FeedImageViewer.previewItem(for: item.card.media[index], title: item.card.authorName, mediaProvider: mediaProvider) {
                    state.bindings.mediaPreviewItem = preview
                } else {
                    userIndicatorController.submitIndicator(UserIndicator(type: .toast, title: UntranslatedL10n.screenFeedImageLoadFailed, icon: \.close))
                }
            }
        }
    }
}
