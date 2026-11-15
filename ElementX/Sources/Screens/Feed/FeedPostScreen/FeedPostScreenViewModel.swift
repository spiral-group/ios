//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082, decision 289). One post and its comments,
// rendered from the session's `FeedStore`: a count, a state or a like moved
// by the sync stream or another screen shows here at once, and while the
// screen shows, a changed post or new comments are read again on their own.
//

import Combine
import SwiftUI

typealias FeedPostScreenViewModelType = StateStoreViewModelV2<FeedPostScreenViewState, FeedPostScreenViewAction>

protocol FeedPostScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<FeedPostScreenViewModelAction, Never> { get }
    var context: FeedPostScreenViewModelType.Context { get }
}

class FeedPostScreenViewModel: FeedPostScreenViewModelType, FeedPostScreenViewModelProtocol {
    static let commentsPageSize = 20
    /// The latest notices searched for the one about this post (the server's largest page).
    static let statementSearchLimit = 50

    let feedService: FeedServiceProtocol
    let clientProxy: ClientProxyProtocol
    private let mediaProvider: MediaProviderProtocol
    let userIndicatorController: UserIndicatorControllerProtocol
    let engagement: FeedEngagementController
    var store: FeedStore {
        engagement.store
    }

    /// The app's language, for the rules' texts in a notice.
    private let language: String?

    /// What the screen is, apart from the post, which is the store's.
    enum Content: Equatable {
        case loading
        case loaded
        case notAvailable
        case unavailable
        case failed
    }

    private var content: Content = .loading
    /// The post as last rendered, to act when the store's copy changes.
    private var renderedPost: FeedPost?
    /// The id the store holds the post by: the server's (lower-case), once it answered.
    private(set) var storeID: String
    private var isShown = false

    // MARK: Comments (lane I3)

    /// What the comments are, apart from the comments, which are the store's.
    enum CommentsContent: Equatable {
        case loading
        case loaded(LoadMoreState)
        case off
        case notAvailable
        case failed
    }

    var commentsContent: CommentsContent = .loading
    var commentItemCache: [String: FeedCommentItem] = [:]
    var commentsGeneration: UInt64 = 0
    /// The comment the rules sheet holds back: sent again with its key once they are accepted.
    var commentAwaitingRules: UUID?
    /// From the sheet's presentation until its `onDismiss`, which runs after it has closed.
    var isRulesSheetOnScreen = false
    /// An alert raised while the rules sheet was on screen, shown once it has closed.
    var pendingAlert: AlertInfo<FeedPostScreenAlertType>?
    /// The rules were accepted here: a further `409` must not show them again.
    var hasAcceptedRules = false

    var commentsListID: FeedListID {
        .comments(postID: storeID)
    }

    let actionsSubject: PassthroughSubject<FeedPostScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<FeedPostScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    /// - Parameters:
    ///   - post: the post as a list showed it, rendered at once and then read
    ///     again by id; `nil` for a link, which reads it first.
    ///   - focusedCommentID: the comment to scroll to (an Activity entry's), once it is read.
    init(postID: String,
         post: FeedPost?,
         focusedCommentID: String? = nil,
         feedService: FeedServiceProtocol,
         engagement: FeedEngagementController,
         clientProxy: ClientProxyProtocol,
         mediaProvider: MediaProviderProtocol,
         userIndicatorController: UserIndicatorControllerProtocol,
         language: String? = FeedAppLanguage.current) {
        self.feedService = feedService
        self.clientProxy = clientProxy
        self.mediaProvider = mediaProvider
        self.userIndicatorController = userIndicatorController
        self.engagement = engagement
        self.language = language
        storeID = post?.id ?? postID.lowercased()

        var initialState = FeedPostScreenViewState(postID: postID)
        initialState.focusedCommentID = focusedCommentID
        super.init(initialViewState: initialState, mediaProvider: mediaProvider)
        if let post {
            // What a list showed renders at once; the store's copy wins when it has one.
            if store.post(post.id) == nil {
                store.upsert([post])
            }
            content = .loaded
        }

        clientProxy.ignoredUsersPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] userIDs in
                self?.state.blockedUserIDs = Set(userIDs ?? [])
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

        Task { await load() }
    }

    /// A screen dropped without `disappeared` is no longer shown.
    isolated deinit {
        store.stopShowing(postID: storeID, by: self)
        store.stopShowing(.comments(postID: storeID), by: self)
    }

    override func process(viewAction: FeedPostScreenViewAction) {
        switch viewAction {
        case .appeared:
            isShown = true
            showInStore()
        case .disappeared:
            isShown = false
            store.stopShowing(postID: storeID, by: self)
            store.stopShowing(commentsListID, by: self)
        case .retry:
            setContent(.loading)
            Task { await load(isManual: true) }
        case .delete:
            confirmDelete()
        case .card(let action):
            handleCardAction(action)
        case .hide:
            Task { await hide() }
        case .unhide:
            Task { await unhide() }
        case .report:
            guard state.canReport else { return }
            actionsSubject.send(.report(.post(id: state.postID)))
        case .reportComment(let commentID):
            guard let item = state.visibleComments.first(where: { $0.id == commentID }), item.canReport else { return }
            actionsSubject.send(.report(.comment(id: commentID)))
        case .retryStatement:
            guard let post = state.post else { return }
            Task { await loadAuthorStatement(for: post, isManual: true) }
        case .openNotices:
            actionsSubject.send(.openNotices)
        case .setCommentsEnabled(let enabled):
            Task { await setCommentsEnabled(enabled) }
        case .loadMoreComments:
            loadMoreComments()
        case .retryComments:
            Task { await loadFirstCommentsPage(isManual: true) }
        case .sendComment:
            Task { await sendComment() }
        case .reply(let commentID):
            reply(to: commentID)
        case .cancelReply:
            state.replyingTo = nil
        case .deleteComment(let commentID):
            confirmDeleteComment(commentID)
        case .revealComment(let commentID):
            state.revealedCommentIDs.insert(commentID)
        case .retryComment(let key):
            Task { await retryComment(key) }
        case .discardComment(let key):
            store.discardComment(key)
            rebuild()
        case .openCommentAuthor(let commentID):
            guard let item = state.visibleComments.first(where: { $0.id == commentID }), item.isAvailable else { return }
            actionsSubject.send(.openAuthor(item.comment.author))
        case .acceptRules:
            Task { await acceptRules() }
        case .declineRules:
            state.bindings.isPresentingRules = false
            state.rulesAcceptFailed = false
        case .rulesSheetDismissed:
            isRulesSheetOnScreen = false
            if let pendingAlert {
                self.pendingAlert = nil
                state.bindings.alertInfo = pendingAlert
            }
        }
    }

    private func handleCardAction(_ action: FeedPostCardAction) {
        guard case .loaded(let item) = state.visibleLoadState else { return }
        switch action {
        case .openPost:
            break // Already open.
        case .openAuthor:
            actionsSubject.send(.openAuthor(item.post.author))
        case .reveal:
            state.isRevealed = true
        case .openMedia(let index):
            guard item.card.media.indices.contains(index) else { return }
            Task { await openMedia(item.card.media[index], title: item.card.authorName) }
        case .like:
            Task { await engagement.toggleLike(item.post) }
        case .comment:
            guard state.canComment else { return }
            state.focusCommentFieldRequest += 1
        case .share:
            guard item.card.canShare(isRevealed: state.isRevealed) else { return }
            actionsSubject.send(.share(item.post))
        case .hide:
            Task { await hide() }
        case .report:
            guard state.canReport else { return }
            actionsSubject.send(.report(.post(id: item.post.id)))
        case .openLikers:
            guard let engagement = item.card.engagement, engagement.likes > 0 else { return }
            actionsSubject.send(.openLikers(postID: item.post.id))
        }
    }

    // MARK: - The store

    private func showInStore() {
        store.show(postID: storeID, by: self)
        store.show(commentsListID, by: self) { [weak self] in
            await self?.readCommentsAgain() ?? false
        }
    }

    /// The server answered under another spelling of the id (a link's upper case).
    private func moveInStore(to id: String) {
        guard id != storeID else { return }
        store.stopShowing(postID: storeID, by: self)
        store.stopShowing(commentsListID, by: self)
        storeID = id
        if isShown {
            showInStore()
        }
    }

    /// The screen as the store holds it now; a changed post brings its banner and its comments along.
    func rebuild() {
        let post = store.post(storeID)
        let loadState: FeedPostLoadState = switch content {
        case .loading: post.map(Self.loadState(for:)) ?? .loading
        case .loaded: post.map(Self.loadState(for:)) ?? .notAvailable
        case .notAvailable: .notAvailable
        case .unavailable: .unavailable
        case .failed: .failed
        }
        if state.loadState != loadState {
            state.loadState = loadState
        }
        rebuildComments()
        if state.syncStatus != store.syncStatus {
            state.syncStatus = store.syncStatus
        }

        if case .loaded = loadState, let post, post != renderedPost {
            let previous = renderedPost
            renderedPost = post
            postChanged(from: previous, to: post)
        }
    }

    func setContent(_ content: Content) {
        self.content = content
        rebuild()
    }

    /// Its banner follows its state; comments the author turned off leave
    /// everyone else's screen, and turned on, they are read.
    private func postChanged(from previous: FeedPost?, to post: FeedPost) {
        let previousKind = previous.flatMap(Self.statementKind)
        if let kind = Self.statementKind(for: post) {
            // Read again when the state changes (held → removed): an answer for the old state is dropped.
            if state.authorStatement == .none || previousKind != kind {
                Task { await loadAuthorStatement(for: post) }
            }
        } else {
            state.authorStatement = .none
        }
        guard post.state == .visible else { return }
        if !post.commentsEnabled, !post.viewer.isAuthor {
            commentsGeneration += 1
            setCommentsContent(.off)
            state.replyingTo = nil
        } else if post.commentsEnabled, commentsContent == .off {
            Task { await loadFirstCommentsPage() }
        }
    }

    // MARK: - The statement of reasons (lane I3 on B4)

    /// The notice the author's banner shows: their held or removed post, or
    /// their visible one the filter or a moderator marked sensitive. `nil` for no banner.
    static func statementKind(for post: FeedPost) -> FeedNoticeKind? {
        guard post.viewer.isAuthor else { return nil }
        switch post.state {
        case .held: return .held
        case .removed: return .removed
        case .visible where post.content.isSensitive: return .sensitive
        case .visible, .hiddenAuthor, .other: return nil
        }
    }

    /// The newest notice about this post in its present state, among the latest notices.
    /// - Parameter isManual: the banner's Retry; over the read window it says "slow down".
    func loadAuthorStatement(for post: FeedPost, isManual: Bool = false) async {
        guard let kind = Self.statementKind(for: post) else { return }
        state.authorStatement = .loading
        let read = { [feedService, language] in await feedService.notices(cursor: nil, limit: Self.statementSearchLimit, language: language) }
        let result = isManual ? await read() : await FeedReadWindow.retryingOnce(read)
        // The post may have changed meanwhile (approved, deleted): its answer is for a banner no longer shown.
        guard state.post?.id == post.id, state.post.flatMap(Self.statementKind) == kind else { return }

        switch result {
        case .success(let page):
            let notice = page.items.first { $0.postID == post.id && $0.commentID == nil && $0.kind == kind }
            state.authorStatement = .loaded(notice.map(FeedNoticeContent.init))
        case .failure(let error):
            MXLog.error("Failed to read the notice of feed post \(post.id): \(error)")
            state.authorStatement = .failed
            if isManual, error.isRateLimited {
                FeedReadWindow.showSlowDown(userIndicatorController)
            }
        }
    }

    // MARK: - Delete (lane I2)

    private func confirmDelete() {
        guard state.canDelete else { return }
        state.bindings.alertInfo = .init(id: .confirmDelete,
                                         title: UntranslatedL10n.screenFeedPostDeleteTitle,
                                         message: UntranslatedL10n.screenFeedPostDeleteMessage,
                                         primaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil),
                                         secondaryButton: .init(title: L10n.actionDelete, role: .destructive) { [weak self] in
                                             Task { await self?.deletePost() }
                                         })
    }

    func deletePost() async {
        let indicatorID = UUID().uuidString
        userIndicatorController.submitIndicator(UserIndicator(id: indicatorID,
                                                              type: .modal(progress: .indeterminate, interactiveDismissDisabled: true, allowsInteraction: false),
                                                              title: UntranslatedL10n.screenFeedPostDeleting,
                                                              persistent: true))
        let result = await feedService.deletePost(id: state.postID)
        userIndicatorController.retractIndicatorWithId(indicatorID)

        switch result {
        case .success, .failure(.notFound):
            // A 404 is "no post of yours with this id": it is gone already.
            userIndicatorController.submitIndicator(UserIndicator(type: .toast, title: UntranslatedL10n.screenFeedPostDeleted, icon: \.checkCircle))
            actionsSubject.send(.deleted)
            store.removePost(storeID)
        case .failure(let error):
            MXLog.error("Failed to delete feed post \(state.postID): \(error)")
            state.bindings.alertInfo = .init(id: .deleteFailed,
                                             title: UntranslatedL10n.screenFeedPostDeleteFailed,
                                             message: Self.deleteFailedMessage(for: error))
        }
    }

    /// Why the post is still there; the connection only when there was no answer.
    /// A held post is not in the feed, so no message says it is.
    static func deleteFailedMessage(for error: FeedError) -> String {
        switch error {
        case .transport:
            UntranslatedL10n.screenFeedPostDeleteFailedMessage
        case .unavailable:
            UntranslatedL10n.screenFeedPostDeleteFailedUnavailableMessage
        case .rateLimited, .temporarilyUnavailable:
            UntranslatedL10n.screenFeedPostDeleteFailedTryShortlyMessage
        case .forbidden:
            UntranslatedL10n.screenFeedPostDeleteFailedAccountRestrictedMessage
        default:
            UntranslatedL10n.screenFeedPostDeleteFailedServerMessage
        }
    }

    // MARK: - Hide and the comment switch (lane I3)

    /// Still readable here once hidden, with "Show in my feed".
    func hide() async {
        guard state.canHide else { return }
        // The store marks it hidden once the server has.
        _ = await engagement.hide(postID: storeID)
        rebuild()
    }

    private func unhide() async {
        guard state.isHidden else { return }
        let result = await runWithIndicator { await self.feedService.setHidden(false, postID: self.state.postID) }
        switch result {
        case .success:
            store.setHidden(false, postID: storeID)
            rebuild()
        case .failure(let error):
            MXLog.error("Failed to show feed post \(state.postID) again: \(error)")
            showActionFailure(error, title: UntranslatedL10n.screenFeedUnhideFailed)
        }
    }

    private func setCommentsEnabled(_ enabled: Bool) async {
        guard state.canToggleComments, state.post?.commentsEnabled != enabled else { return }
        let result = await runWithIndicator { await self.feedService.setCommentsEnabled(enabled, postID: self.state.postID) }
        switch result {
        case .success(let post):
            // The comments are the author's either way.
            store.upsert([post])
            rebuild()
            userIndicatorController.submitIndicator(UserIndicator(type: .toast,
                                                                  title: enabled ? UntranslatedL10n.screenFeedCommentsTurnedOn : UntranslatedL10n.screenFeedCommentsTurnedOff,
                                                                  icon: \.checkCircle))
        case .failure(let error):
            MXLog.error("Failed to turn comments \(enabled ? "on" : "off") on feed post \(state.postID): \(error)")
            showActionFailure(error, title: UntranslatedL10n.screenFeedCommentsToggleFailed)
        }
    }

    /// A blocking indicator while the server answers; nothing changes on screen before it has.
    func runWithIndicator<Value>(_ operation: () async -> Result<Value, FeedError>) async -> Result<Value, FeedError> {
        let indicatorID = UUID().uuidString
        userIndicatorController.submitIndicator(UserIndicator(id: indicatorID,
                                                              type: .modal(progress: .indeterminate, interactiveDismissDisabled: true, allowsInteraction: false),
                                                              title: L10n.commonLoading,
                                                              persistent: true),
                                                delay: .milliseconds(200))
        defer { userIndicatorController.retractIndicatorWithId(indicatorID) }
        return await operation()
    }

    private func showActionFailure(_ error: FeedError, title: String) {
        let message = error == .notFound ? UntranslatedL10n.screenFeedPostNotAvailableMessage : error.actionFailedMessage
        state.bindings.alertInfo = .init(id: .actionFailed, title: title, message: message)
    }

    // MARK: - Load

    /// - Parameter isManual: Retry; over the read window it says "slow down" rather than wait.
    func load(isManual: Bool = false) async {
        let read = { [feedService, postID = state.postID] in await feedService.post(id: postID) }
        switch isManual ? await read() : await FeedReadWindow.retryingOnce(read) {
        case .success(let post):
            store.upsert([post])
            moveInStore(to: post.id)
            setContent(.loaded)
        case .failure(.notFound):
            setContent(.notAvailable)
        case .failure(.unavailable):
            setContent(.unavailable)
        case .failure(let error):
            MXLog.error("Failed to read feed post \(state.postID): \(error)")
            // What a list already showed stays; only a post never read becomes "couldn't load".
            if case .loaded = state.loadState {
                if !error.isRateLimited {
                    userIndicatorController.submitIndicator(UserIndicator(type: .toast, title: UntranslatedL10n.screenFeedRefreshFailed, icon: \.close))
                }
            } else {
                setContent(.failed)
            }
            if isManual, error.isRateLimited {
                FeedReadWindow.showSlowDown(userIndicatorController)
            }
        }

        if commentsContent == .loading {
            await loadFirstCommentsPage()
        }
    }

    /// The author as their own comments on their way show them.
    var currentAuthor: FeedAuthor {
        let profile = clientProxy.userProfilePublisher.value
        return FeedAuthor(userID: clientProxy.userID, name: profile.displayName, avatarURL: profile.avatarURL,
                          bio: nil, isOfficial: false, isNameWithheld: false)
    }

    static func loadState(for post: FeedPost) -> FeedPostLoadState {
        switch post.state {
        case .visible, .held, .removed:
            .loaded(FeedItem(post: post))
        case .hiddenAuthor, .other:
            // A newer state degrades to "not available" (decision 96).
            .notAvailable
        }
    }

    private func openMedia(_ media: FeedPostCardModel.Media, title: String) async {
        if let item = await FeedImageViewer.previewItem(for: media, title: title, mediaProvider: mediaProvider) {
            state.bindings.mediaPreviewItem = item
        } else {
            userIndicatorController.submitIndicator(UserIndicator(type: .toast, title: UntranslatedL10n.screenFeedImageLoadFailed, icon: \.close))
        }
    }
}

