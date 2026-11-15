//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082, decision 289). Latest page by page, its
// posts rendered from the session's `FeedStore`. Pull to refresh and the "N
// new posts" pill (which counts `feed.post_published` from the sync stream)
// read the first page afresh rather than prepending into the live list (arch
// § 5.4). Read again on its own (stale while shown), Latest keeps what the
// person sees: the posts shown get their new values, ones gone from it leave,
// and newer ones go to the pill. The person's posts on their way show on top.
//

import Combine
import SwiftUI

typealias FeedScreenViewModelType = StateStoreViewModelV2<FeedScreenViewState, FeedScreenViewAction>

protocol FeedScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<FeedScreenViewModelAction, Never> { get }
    var context: FeedScreenViewModelType.Context { get }
}

class FeedScreenViewModel: FeedScreenViewModelType, FeedScreenViewModelProtocol {
    static let pageSize = 20
    /// The pill counts at most this many ("99+").
    static let headCap = FeedStore.newPostsCap
    /// A page may come back empty with a cursor when every row it scanned was
    /// filtered; reading on is right, but not without end on one scroll.
    static let maxEmptyPagesInARow = 10

    private let feedService: FeedServiceProtocol
    private let mediaProvider: MediaProviderProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    private let engagement: FeedEngagementController
    private var store: FeedStore {
        engagement.store
    }

    /// What the list is, apart from its posts, which are the store's.
    private enum Content: Equatable {
        case loading
        case loaded(LoadMoreState)
        /// The first page could not be read; the one kept from the last read is shown.
        case offline
        case unavailable
        case failed
    }

    private var content: Content = .loading
    private var pinnedID: String?
    /// Cards are built once per version of a post.
    private var itemCache: [String: FeedItem] = [:]
    private var loadGeneration: UInt64 = 0

    private let actionsSubject: PassthroughSubject<FeedScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<FeedScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(feedService: FeedServiceProtocol,
         engagement: FeedEngagementController,
         clientProxy: ClientProxyProtocol,
         mediaProvider: MediaProviderProtocol,
         userIndicatorController: UserIndicatorControllerProtocol) {
        self.feedService = feedService
        self.mediaProvider = mediaProvider
        self.userIndicatorController = userIndicatorController
        self.engagement = engagement
        super.init(initialViewState: FeedScreenViewState(ownProfile: clientProxy.userProfilePublisher.value,
                                                         lastPinned: feedService.cachedFirstPage().map(FeedLastPinned.init) ?? .unknown),
                   mediaProvider: mediaProvider)

        clientProxy.userProfilePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                self?.state.ownProfile = profile
            }
            .store(in: &cancellables)

        clientProxy.ignoredUsersPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] userIDs in
                // `nil` is "not read yet": the server already filters, so nothing extra is hidden.
                self?.state.blockedUserIDs = Set(userIDs ?? [])
            }
            .store(in: &cancellables)

        clientProxy.timelineMediaVisibilityPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visibility in
                self?.state.hidesMedia = visibility != .always
            }
            .store(in: &cancellables)

        // Every read of the notices and every one marked read moves the badge; a failed read sends nothing.
        feedService.noticesUnreadPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] unread in
                self?.state.unreadNotices = unread
            }
            .store(in: &cancellables)

        // Lane I5: a page of activity and its seen mark move it.
        feedService.activityUnreadPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] unread in
                self?.state.unreadActivity = unread
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self, store.isShown(.latest) else { return }
                readAgainIfNotLoaded()
            }
            .store(in: &cancellables)

        store.observe { [weak self] in
            self?.rebuild()
            return self != nil
        }
        rebuild()

        Task { await loadFirstPage() }
    }

    /// A screen dropped without `disappeared` is no longer shown.
    isolated deinit {
        store.stopShowing(.latest, by: self)
    }

    override func process(viewAction: FeedScreenViewAction) {
        switch viewAction {
        case .appeared:
            readAgainIfNotLoaded()
            store.show(.latest, by: self) { [weak self] in
                await self?.readAgain() ?? false
            }
        case .disappeared:
            store.stopShowing(.latest, by: self)
        case .refresh:
            Task { await loadFirstPage(isManual: true) }
        case .loadMore:
            guard case .loaded(let loadMore) = content else { return }
            switch loadMore {
            case .idle where state.isReadOnPaused:
                state.isReadOnPaused = false
                Task { await readOnIfNothingNew(visibleBefore: visibleCount) }
            case .idle(let cursor):
                Task { await loadNextPage(cursor: cursor, isManual: false) }
            case .failed(let cursor):
                // The failed row is a tap.
                Task { await loadNextPage(cursor: cursor, isManual: true) }
            case .loading, .exhausted:
                return
            }
        case .showNewPosts:
            store.clearNewPosts()
            state.scrollToTopRequest += 1
            Task { await loadFirstPage(isManual: true) }
        case .card(let postID, let action):
            handleCardAction(action, postID: postID)
        case .compose:
            actionsSubject.send(.compose)
        case .openOwnPosts:
            actionsSubject.send(.openOwnPosts)
        case .openActivity:
            actionsSubject.send(.openActivity)
        case .retryPost(let key):
            retryPost(key)
        case .discardPost(let key):
            store.discardPost(key)
            rebuild()
        }
    }

    // MARK: - The store

    /// The screen as the store holds it now.
    private func rebuild() {
        var cache: [String: FeedItem] = [:]
        func item(for post: FeedPost) -> FeedItem {
            let item = itemCache[post.id].flatMap { $0.post == post ? $0 : nil } ?? FeedItem(post: post)
            cache[post.id] = item
            return item
        }

        let items = store.posts(in: .latest).map(item(for:))
        let listState: FeedListState = switch content {
        case .loading: .loading
        case .loaded(let loadMore): .loaded(items, loadMore: loadMore)
        case .offline: .offline(items)
        case .unavailable: .unavailable
        case .failed: .failed
        }
        let pinned = pinnedID.flatMap(store.post).map(item(for:))
        itemCache = cache

        if state.listState != listState {
            state.listState = listState
        }
        if state.pinned != pinned {
            state.pinned = pinned
        }
        if state.newPostsCount != store.newPostsCount {
            state.newPostsCount = store.newPostsCount
        }
        if state.pendingPosts != store.pendingPosts {
            state.pendingPosts = store.pendingPosts
        }
        if state.syncStatus != store.syncStatus {
            state.syncStatus = store.syncStatus
        }
    }

    private func setContent(_ content: Content) {
        self.content = content
        rebuild()
    }

    // MARK: - Posts on their way

    /// A refusal over the rules is answered in the composer (its draft has the
    /// same key); any other is sent again.
    private func retryPost(_ key: UUID) {
        guard let pending = store.pendingPosts.first(where: { $0.key == key }) else { return }
        if case .failed(.rulesNotAccepted) = pending.delivery {
            actionsSubject.send(.compose)
            return
        }
        Task {
            let result = await store.retryPost(key)
            rebuild()
            if case .success(let post) = result {
                actionsSubject.send(.published(post))
            }
        }
    }

    // MARK: - Pages

    /// - Parameters:
    ///   - keepsWhatIsShown: a read the person did not ask for leaves the
    ///     screen as it is until its answer is in.
    ///   - isManual: the person asked for it (pull to refresh, Retry, the
    ///     pill): over the read window it says "slow down" rather than wait.
    @discardableResult
    func loadFirstPage(keepsWhatIsShown: Bool = false, isManual: Bool = false) async -> Bool {
        loadGeneration += 1
        let generation = loadGeneration
        let previous = content
        if case .loaded = previous {
            // A refresh keeps the list in place until the new page is in.
        } else if !keepsWhatIsShown {
            setContent(.loading)
        }

        let result = await readFirstPage(isManual: isManual, generation: generation)
        guard generation == loadGeneration, let result else { return false }

        switch result {
        case .success(let page):
            store.upsert(page.items + [page.pinned].compactMap(\.self))
            pinnedID = page.pinned?.id
            state.lastPinned = FeedLastPinned(page)
            store.setList(.latest, FeedStoreList(ids: Self.ids(of: page.items, excluding: pinnedID), nextCursor: page.nextCursor))
            store.clearNewPosts()
            state.isReadOnPaused = false
            setContent(.loaded(Self.loadMore(after: page)))
            await readOnIfNothingNew(visibleBefore: 0)
            return true
        case .failure(let error):
            MXLog.error("Failed to read the first page of the feed: \(error)")
            if error.isRateLimited, previous != .loading {
                // Over the read window: what was on screen stays, whatever it was.
                setContent(previous)
            } else {
                applyFirstPageFailure(error, previous: previous)
            }
            if isManual, error.isRateLimited {
                FeedReadWindow.showSlowDown(userIndicatorController)
            }
            return false
        }
    }

    /// The first page with one retry when the server says, or `nil` when a newer read replaced this one.
    private func readFirstPage(isManual: Bool, generation: UInt64) async -> Result<FeedPage, FeedError>? {
        var result = await feedService.latest(cursor: nil, limit: Self.pageSize)
        switch result {
        case .failure(.temporarilyUnavailable(let retryAfterSeconds)), .failure(.rateLimited(let retryAfterSeconds)):
            // The page's authors could not be read, or the read window is full: one
            // retry, when the server says; a read the person asked for is not kept waiting.
            guard !(isManual && result.isRateLimited) else { break }
            try? await Task.sleep(for: Self.retryDelay(retryAfterSeconds: retryAfterSeconds))
            guard generation == loadGeneration else { return nil }
            result = await feedService.latest(cursor: nil, limit: Self.pageSize)
        default:
            break
        }
        return result
    }

    /// Stale while shown (a sync change, `ready.fresh`, `limited`): a list read
    /// before keeps its place, anything else is read as it would be on opening.
    private func readAgain() async -> Bool {
        guard case .loaded = content else {
            return await loadFirstPage(keepsWhatIsShown: true)
        }
        loadGeneration += 1
        let generation = loadGeneration
        guard let result = await readFirstPage(isManual: false, generation: generation), generation == loadGeneration else { return false }
        switch result {
        case .success(let page):
            reconcile(with: page)
            return true
        case .failure(let error):
            // What is shown stays; the next time it shows it is read again.
            MXLog.info("Could not read the feed's first page again: \(error)")
            return false
        }
    }

    /// The first page read again under what is shown: the posts it holds get
    /// their new values; within its span, a shown post it no longer has is gone
    /// (removed, hidden, held); one newer than the top goes to the pill.
    private func reconcile(with page: FeedPage) {
        store.upsert(page.items + [page.pinned].compactMap(\.self))
        pinnedID = page.pinned?.id
        state.lastPinned = FeedLastPinned(page)
        let current = store.list(.latest) ?? FeedStoreList(ids: [], nextCursor: page.nextCursor)
        let pageIDs = Self.ids(of: page.items, excluding: pinnedID)
        let pageSet = Set(pageIDs)
        let newestShown = current.ids.compactMap(store.post).map(\.createdAt).max()
        let oldestRead = page.items.map(\.createdAt).min()

        let newer = page.items.filter { post in pageSet.contains(post.id) && !current.ids.contains(post.id) && newestShown.map { post.createdAt > $0 } ?? false }
        store.addNewPosts(newer.map(\.id))

        let kept = current.ids.filter { id in
            guard !pageSet.contains(id), let post = store.post(id) else { return true }
            // The whole list was read: what it lacks is gone.
            guard page.nextCursor != nil else { return false }
            // Below the page the list was not read again; within it, the page is the truth.
            guard let oldestRead else { return true }
            return post.createdAt < oldestRead
        }
        let newerIDs = Set(newer.map(\.id))
        let ids = (kept + pageIDs.filter { !kept.contains($0) && !newerIDs.contains($0) })
            .compactMap(store.post)
            .sorted { $0.createdAt > $1.createdAt }
            .map(\.id)
        store.setList(.latest, FeedStoreList(ids: ids, nextCursor: current.nextCursor))
        rebuild()
    }

    /// A first page that did not load (failed, offline, the feed off) is read
    /// again when the tab shows or the app returns: release day turns
    /// `FEED_MODE` from off to open under running apps.
    private func readAgainIfNotLoaded() {
        switch content {
        case .loaded, .loading:
            return
        case .offline, .unavailable, .failed:
            Task { await loadFirstPage(keepsWhatIsShown: true) }
        }
    }

    private func applyFirstPageFailure(_ error: FeedError, previous: Content) {
        if error == .unavailable {
            pinnedID = nil
            setContent(.unavailable)
            return
        }

        if case .loaded = previous {
            // A failed refresh leaves what was read; it says so instead of emptying the list.
            setContent(previous)
            showRefreshFailure()
            return
        }

        if let cached = feedService.cachedFirstPage() {
            store.upsert(cached.items + [cached.pinned].compactMap(\.self))
            pinnedID = cached.pinned?.id
            store.setList(.latest, FeedStoreList(ids: Self.ids(of: cached.items, excluding: pinnedID), nextCursor: nil))
            setContent(.offline)
        } else {
            setContent(.failed)
        }
    }

    /// - Parameter isManual: a tap on the failed row; the sentinel scrolling in is not.
    func loadNextPage(cursor: String, isManual: Bool) async {
        let generation = loadGeneration
        setContent(.loaded(.loading))

        let read = { [feedService] in await feedService.latest(cursor: cursor, limit: Self.pageSize) }
        let result = isManual ? await read() : await FeedReadWindow.retryingOnce(read)
        guard generation == loadGeneration, case .loaded = content else { return }

        switch result {
        case .success(let page):
            let visibleBefore = visibleCount
            append(page.items, nextCursor: page.nextCursor)
            setContent(.loaded(Self.loadMore(after: page)))
            await readOnIfNothingNew(visibleBefore: visibleBefore)
        case .failure(.invalidCursor):
            // An old or malformed cursor: the spec says to start from the first page.
            await loadFirstPage()
        case .failure(let error):
            MXLog.error("Failed to read the next page of the feed: \(error)")
            setContent(.loaded(.failed(cursor: cursor)))
            if isManual, error.isRateLimited {
                FeedReadWindow.showSlowDown(userIndicatorController)
            }
        }
    }

    /// Appends a page, dropping posts already shown (cursors overlap) and the pinned one.
    private func append(_ posts: [FeedPost], nextCursor: String?) {
        store.upsert(posts)
        let current = store.list(.latest)?.ids ?? []
        var seen = Set(current)
        if let pinnedID {
            seen.insert(pinnedID)
        }
        let added = posts.map(\.id).filter { seen.insert($0).inserted }
        store.setList(.latest, FeedStoreList(ids: current + added, nextCursor: nextCursor))
    }

    /// An empty page with a cursor is not the end (the server filtered every
    /// row it scanned): read on until something new shows or the cursor ends.
    private func readOnIfNothingNew(visibleBefore: Int) async {
        guard case .loaded(.idle(let cursor)) = content, visibleCount <= visibleBefore else { return }
        let generation = loadGeneration
        // Shown as loading, so the sentinel's own load-more does not read the same page again.
        setContent(.loaded(.loading))

        let readOn = await Self.readOn(from: cursor) { [weak self] post in
            self?.state.blockedUserIDs.contains(post.author.userID) == false
        } read: { [feedService] cursor in
            await FeedReadWindow.retryingOnce { await feedService.latest(cursor: cursor, limit: Self.pageSize) }
        } isCurrent: { [weak self] in
            self?.loadGeneration == generation
        }
        guard let readOn, case .loaded = content else { return }
        append(readOn.posts, nextCursor: readOn.loadMore.cursor)
        state.isReadOnPaused = readOn.isPaused
        setContent(.loaded(readOn.loadMore))
    }

    /// What reading on past empty pages found.
    struct ReadOn {
        let posts: [FeedPost]
        let loadMore: LoadMoreState
        /// `maxEmptyPagesInARow` pages showed nothing: the next read waits for a tap.
        let isPaused: Bool
    }

    /// Reads pages from `cursor` until one has a post that `shows`, the cursor
    /// ends, a read fails, or `maxEmptyPagesInARow` came back with nothing.
    /// `nil` when a newer read replaced this one (`isCurrent` is false).
    static func readOn(from cursor: String,
                       shows: (FeedPost) -> Bool,
                       read: (String) async -> Result<FeedPage, FeedError>,
                       isCurrent: () -> Bool) async -> ReadOn? {
        var posts: [FeedPost] = []
        var cursor = cursor
        for _ in 0..<maxEmptyPagesInARow {
            let result = await read(cursor)
            guard isCurrent() else { return nil }
            switch result {
            case .success(let page):
                posts += page.items
                guard let next = page.nextCursor else { return ReadOn(posts: posts, loadMore: .exhausted, isPaused: false) }
                if page.items.contains(where: shows) {
                    return ReadOn(posts: posts, loadMore: .idle(cursor: next), isPaused: false)
                }
                cursor = next
            case .failure(let error):
                MXLog.error("Failed to read on past an empty feed page: \(error)")
                return ReadOn(posts: posts, loadMore: .failed(cursor: cursor), isPaused: false)
            }
        }
        return ReadOn(posts: posts, loadMore: .idle(cursor: cursor), isPaused: true)
    }

    // MARK: - Cards

    private func handleCardAction(_ action: FeedPostCardAction, postID: String) {
        guard let item = item(withID: postID), item.card.isAvailable else { return }
        switch action {
        case .openPost:
            actionsSubject.send(.openPost(item.post))
        case .openAuthor:
            actionsSubject.send(.openAuthor(item.post.author))
        case .reveal:
            state.revealedPostIDs.insert(postID)
        case .openMedia(let index):
            guard item.card.media.indices.contains(index) else { return }
            Task { await openMedia(item.card.media[index], title: item.card.authorName) }
        case .like:
            Task { await engagement.toggleLike(item.post) }
        case .comment:
            actionsSubject.send(.openPost(item.post))
        case .share:
            guard item.card.canShare(isRevealed: state.revealedPostIDs.contains(postID)) else { return }
            actionsSubject.send(.share(item.post))
        case .hide:
            guard item.card.engagement?.canHide == true else { return }
            // The store takes it out of the list once the server has hidden it.
            Task { await engagement.hide(postID: postID) }
        case .report:
            guard item.card.engagement?.canReport == true else { return }
            actionsSubject.send(.report(.post(id: postID)))
        case .openLikers:
            guard let engagement = item.card.engagement, engagement.likes > 0 else { return }
            actionsSubject.send(.openLikers(postID: postID))
        }
    }

    private func item(withID id: String) -> FeedItem? {
        if state.pinned?.id == id { return state.pinned }
        return state.visibleItems.first { $0.id == id }
    }

    private func openMedia(_ media: FeedPostCardModel.Media, title: String) async {
        let indicatorID = UUID().uuidString
        userIndicatorController.submitIndicator(UserIndicator(id: indicatorID,
                                                              type: .modal(progress: .indeterminate, interactiveDismissDisabled: false, allowsInteraction: true),
                                                              title: L10n.commonLoading,
                                                              persistent: true),
                                                delay: .milliseconds(200))
        defer { userIndicatorController.retractIndicatorWithId(indicatorID) }

        if let item = await FeedImageViewer.previewItem(for: media, title: title, mediaProvider: mediaProvider) {
            state.bindings.mediaPreviewItem = item
        } else {
            userIndicatorController.submitIndicator(UserIndicator(type: .toast, title: UntranslatedL10n.screenFeedImageLoadFailed, icon: \.close))
        }
    }

    private func showRefreshFailure() {
        userIndicatorController.submitIndicator(UserIndicator(type: .toast, title: UntranslatedL10n.screenFeedRefreshFailed, icon: \.close))
    }

    // MARK: - Helpers

    private var visibleCount: Int {
        state.visibleItems.count
    }

    /// The server's `Retry-After`, within the read window's bounds.
    static func retryDelay(retryAfterSeconds: Int?) -> Duration {
        FeedReadWindow.delay(retryAfterSeconds: retryAfterSeconds)
    }

    /// A page's ids once each, without the pinned one.
    static func ids(of posts: [FeedPost], excluding pinnedID: String?) -> [String] {
        var seen = Set<String>()
        if let pinnedID {
            seen.insert(pinnedID)
        }
        return posts.map(\.id).filter { seen.insert($0).inserted }
    }

    static func loadMore(after page: FeedPage) -> LoadMoreState {
        page.nextCursor.map { .idle(cursor: $0) } ?? .exhausted
    }
}

extension LoadMoreState {
    /// Where the next page starts, while there is one.
    var cursor: String? {
        switch self {
        case .idle(let cursor), .failed(let cursor): cursor
        case .loading, .exhausted: nil
        }
    }
}
