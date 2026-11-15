//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082, decision 289). A post's flat comments
// (lane I3), oldest first, page by page, held by the session's `FeedStore`.
// A comment the person sends shows at once as sending, with a key of its own;
// the server's copy replaces it, and a refusal stays on it with Retry, which
// sends the same text with the same key, so the server answers the comment it
// may already have made. A delete removes one only once the server did.
// While the post shows, `feed.comment_added` / `_removed` read them again.
//

import Foundation

extension FeedPostScreenViewModel {
    /// A page may come back empty with a cursor; reading on is right, but not without end.
    static let maxEmptyCommentPagesInARow = 10
    /// A `429` waiting longer than this is the daily cap, which ends at midnight UTC.
    static let dailyCapRetryThreshold = FeedComposerScreenViewModel.dailyCapRetryThreshold

    // MARK: - The store

    func rebuildComments() {
        var cache: [String: FeedCommentItem] = [:]
        let items = store.comments(in: commentsListID).map { comment in
            let item = commentItemCache[comment.id].flatMap { $0.comment == comment ? $0 : nil } ?? FeedCommentItem(comment: comment)
            cache[comment.id] = item
            return item
        }
        commentItemCache = cache
        let commentsState: FeedCommentsState = switch commentsContent {
        case .loading: .loading
        case .loaded(let loadMore): .loaded(items, loadMore: loadMore)
        case .off: .off
        case .notAvailable: .notAvailable
        case .failed: .failed
        }
        if state.commentsState != commentsState {
            state.commentsState = commentsState
        }
        let pending = store.pendingComments(on: storeID).map(FeedCommentItem.init(pending:))
        if state.pendingComments != pending {
            state.pendingComments = pending
        }
    }

    func setCommentsContent(_ content: CommentsContent) {
        commentsContent = content
        rebuildComments()
    }

    // MARK: - Pages

    /// - Parameter isManual: Retry; over the read window it says "slow down" rather than wait.
    func loadFirstCommentsPage(isManual: Bool = false) async {
        guard let post = state.post, post.state == .visible else { return }
        guard post.commentsEnabled || post.viewer.isAuthor else {
            setCommentsContent(.off)
            return
        }
        commentsGeneration += 1
        let generation = commentsGeneration
        let previous = commentsContent
        if case .loaded = previous {
            // Read again (the switch turned on): the comments stay until the new ones are in.
        } else {
            setCommentsContent(.loading)
        }

        let result = await readComments(from: nil, after: [], isManual: isManual)
        guard generation == commentsGeneration else { return }
        if case .failure(let error) = result, error.isRateLimited {
            // Over the read window: what was on screen stays.
            if case .loaded = previous {
                setCommentsContent(previous)
            } else {
                setCommentsContent(.failed)
            }
            if isManual {
                FeedReadWindow.showSlowDown(userIndicatorController)
            }
            return
        }
        apply(result)
    }

    func loadMoreComments() {
        guard case .loaded(let loadMore) = commentsContent else { return }
        switch loadMore {
        case .idle(let cursor), .failed(let cursor):
            let generation = commentsGeneration
            // The failed row is a tap; the sentinel scrolling in is not.
            let isManual = loadMore == .failed(cursor: cursor)
            let shown = store.comments(in: commentsListID)
            setCommentsContent(.loaded(.loading))
            Task {
                let result = await readComments(from: cursor, after: shown, isManual: isManual)
                guard generation == commentsGeneration else { return }
                apply(result)
                if isManual, case .success(let page) = result, page.isOverTheWindow {
                    FeedReadWindow.showSlowDown(userIndicatorController)
                }
            }
        case .loading, .exhausted:
            return
        }
    }

    /// Stale while shown (`feed.comment_added`, `ready.fresh`, `limited`):
    /// read from the start as far as was shown, so a comment anywhere in it
    /// shows or leaves; a failure leaves what is shown.
    func readCommentsAgain() async -> Bool {
        guard case .loaded = commentsContent else {
            guard commentsContent != .off else { return true }
            await loadFirstCommentsPage()
            if case .loaded = commentsContent { return true } else { return false }
        }
        commentsGeneration += 1
        let generation = commentsGeneration
        let shownLast = store.list(commentsListID)?.ids.last
        var comments: [FeedComment] = []
        var cursor: String?
        for _ in 0..<Self.maxEmptyCommentPagesInARow {
            let result = await FeedReadWindow.retryingOnce { [feedService, postID = state.postID, cursor] in
                await feedService.comments(postID: postID, cursor: cursor, limit: Self.commentsPageSize)
            }
            guard generation == commentsGeneration else { return false }
            guard case .success(let page) = result else {
                MXLog.info("Could not read the comments of feed post \(state.postID) again")
                return false
            }
            comments += page.items
            cursor = page.nextCursor
            guard cursor != nil else { break }
            // As far as was shown: ids are UUIDv7, so they sort by time.
            if let last = page.items.last?.id, last >= shownLast ?? "" {
                break
            }
        }
        store.upsert(comments)
        store.setList(commentsListID, FeedStoreList(ids: Self.sortedIDs(comments), nextCursor: cursor))
        setCommentsContent(.loaded(cursor.map { .idle(cursor: $0) } ?? .exhausted))
        return true
    }

    /// What a read of the comments found; `isOverTheWindow` when a later page stopped at the read window.
    typealias CommentsRead = (comments: [FeedComment], loadMore: LoadMoreState, isOverTheWindow: Bool)

    /// Reads from `cursor` until a page shows something, the cursor ends, a
    /// read fails, or `maxEmptyCommentPagesInARow` pages came back with nothing.
    /// - Parameter isManual: a tap; a read nobody asked for waits out the read window once.
    private func readComments(from cursor: String?, after shown: [FeedComment], isManual: Bool) async -> Result<CommentsRead, FeedError> {
        var comments = shown
        var cursor = cursor
        for _ in 0..<Self.maxEmptyCommentPagesInARow {
            let read = { [feedService, postID = state.postID, cursor] in
                await feedService.comments(postID: postID, cursor: cursor, limit: Self.commentsPageSize)
            }
            let result = isManual ? await read() : await FeedReadWindow.retryingOnce(read)
            switch result {
            case .success(let page):
                comments = Self.merging(page.items, into: comments)
                guard let next = page.nextCursor else { return .success((comments, .exhausted, false)) }
                if !page.items.isEmpty {
                    return .success((comments, .idle(cursor: next), false))
                }
                cursor = next
            case .failure(.invalidCursor) where cursor != nil:
                // An old cursor: the spec says to start from the first page.
                cursor = nil
                comments = []
            case .failure(let error):
                guard let cursor else { return .failure(error) }
                MXLog.error("Failed to read more comments of feed post \(state.postID): \(error)")
                return .success((comments, .failed(cursor: cursor), error.isRateLimited))
            }
        }
        // "Show more comments" reads on from here when tapped.
        return .success((comments, cursor.map { .idle(cursor: $0) } ?? .exhausted, false))
    }

    private func apply(_ result: Result<CommentsRead, FeedError>) {
        switch result {
        case .success(let page):
            store.upsert(page.comments)
            store.setList(commentsListID, FeedStoreList(ids: page.comments.map(\.id), nextCursor: page.loadMore.cursor))
            setCommentsContent(.loaded(page.loadMore))
        case .failure(.notFound):
            // The feed's own 404: the post is gone for the person, or its comments went off.
            setCommentsContent(.notAvailable)
        case .failure(let error):
            MXLog.error("Failed to read the comments of feed post \(state.postID): \(error)")
            setCommentsContent(.failed)
        }
    }

    /// Adds comments without repeating one, in time order: UUIDv7 ids sort by time.
    static func merging(_ comments: [FeedComment], into shown: [FeedComment]) -> [FeedComment] {
        var byID = Dictionary(shown.map { ($0.id, $0) }) { _, new in new }
        for comment in comments {
            byID[comment.id] = comment
        }
        return byID.values.sorted { $0.id < $1.id }
    }

    static func sortedIDs(_ comments: [FeedComment]) -> [String] {
        Array(Set(comments.map(\.id))).sorted()
    }

    // MARK: - Reply

    func reply(to commentID: String) {
        guard state.canComment, let item = state.visibleComments.first(where: { $0.id == commentID }), item.canReply else { return }
        state.replyingTo = item
        state.focusCommentFieldRequest += 1
    }

    // MARK: - Send

    /// The field clears at once: the comment shows under the others as sending.
    func sendComment() async {
        guard state.canSendComment else { return }
        let text = state.bindings.commentText
        let replyTo = state.replyingTo.map { FeedCommentReply(id: $0.id, author: $0.comment.author) }
        state.bindings.commentText = ""
        state.replyingTo = nil

        let key = UUID()
        // The store shows it as sending before it awaits the answer.
        let result = await store.sendComment(postID: storeID, text: text, replyTo: replyTo, author: currentAuthor, idempotencyKey: key)
        rebuild()
        if case .failure(let error) = result {
            await handleCommentRefusal(error, key: key)
        }
    }

    /// The same text, reply and key.
    func retryComment(_ key: UUID) async {
        let result = await store.retryComment(key)
        rebuild()
        guard let result, case .failure(let error) = result else { return }
        await handleCommentRefusal(error, key: key)
    }

    private func handleCommentRefusal(_ error: FeedError, key: UUID) async {
        switch error {
        case .rulesNotAccepted(let currentVersion):
            if FeedRules.isOutdated(serverVersion: currentVersion) {
                presentCommentAlert(.updateRequired, title: UntranslatedL10n.screenFeedComposerUpdateRequiredTitle,
                                    message: UntranslatedL10n.screenFeedCommentUpdateRequiredMessage)
            } else if hasAcceptedRules {
                // Accepted and refused again: the sheet a second time would be a loop.
                presentCommentAlert(.postingPaused, title: UntranslatedL10n.screenFeedComposerErrorReadOnlyTitle,
                                    message: UntranslatedL10n.screenFeedCommentReadOnlyMessage)
            } else {
                commentAwaitingRules = key
                state.rulesAcceptFailed = false
                isRulesSheetOnScreen = true
                state.bindings.isPresentingRules = true
            }
            return
        case .notFound:
            Task { await load() }
        case .rateLimited(let seconds?) where seconds > Self.dailyCapRetryThreshold:
            await loadStanding()
        case _ where Self.isConnectionFailure(error):
            // "Couldn't send" with Retry on the comment says it all.
            return
        default:
            break
        }

        let message = Self.commentMessage(for: error, dailyCap: state.standing?.commentsPerDay)
        presentCommentAlert(.commentRefused, title: message.title, message: message.message)
    }

    /// No answer, or one that says nothing of the comment: Retry is the way on.
    static func isConnectionFailure(_ error: FeedError) -> Bool {
        switch error {
        case .transport, .temporarilyUnavailable: true
        case .server(let status): status >= 500
        default: false
        }
    }

    func loadStanding() async {
        switch await FeedReadWindow.retryingOnce({ [feedService] in await feedService.standing() }) {
        case .success(let standing):
            state.standing = standing
        case .failure(let error):
            MXLog.info("Could not read the feed standing: \(error)")
        }
    }

    /// What the person is told for each refusal; anything the app does not know is the generic one.
    static func commentMessage(for error: FeedError, dailyCap: Int? = nil) -> (title: String, message: String) {
        switch error {
        case .linkRefused:
            (UntranslatedL10n.screenFeedComposerErrorLinkRefusedTitle, UntranslatedL10n.screenFeedCommentErrorLinkRefusedMessage)
        case .suspended:
            (UntranslatedL10n.screenFeedCommentErrorSuspendedTitle, UntranslatedL10n.screenFeedCommentErrorSuspendedMessage)
        case .rateLimited(let seconds?) where seconds > dailyCapRetryThreshold:
            (UntranslatedL10n.screenFeedCommentErrorRateLimitedTitle,
             dailyCap.map(UntranslatedL10n.screenFeedCommentDailyCapNotice) ?? UntranslatedL10n.screenFeedCommentErrorRateLimitedLater)
        case .rateLimited(let seconds):
            (UntranslatedL10n.screenFeedCommentErrorRateLimitedTitle,
             seconds.map { UntranslatedL10n.screenFeedCommentErrorRateLimitedMinutes(FeedComposerScreenViewModel.minutes(fromSeconds: $0)) }
                 ?? UntranslatedL10n.screenFeedCommentErrorRateLimitedLater)
        case .readOnly:
            (UntranslatedL10n.screenFeedComposerErrorReadOnlyTitle, UntranslatedL10n.screenFeedCommentReadOnlyMessage)
        case .unavailable:
            (UntranslatedL10n.screenFeedUnavailableTitle, UntranslatedL10n.screenFeedCommentErrorUnavailableMessage)
        case .idempotencyKeyReused:
            (UntranslatedL10n.screenFeedCommentErrorKeyReusedTitle, UntranslatedL10n.screenFeedCommentErrorKeyReusedMessage)
        case .notFound:
            (UntranslatedL10n.screenFeedCommentsNotAvailable, UntranslatedL10n.screenFeedCommentErrorNotFoundMessage)
        case .unprocessable:
            (UntranslatedL10n.screenFeedCommentErrorReplyGoneTitle, UntranslatedL10n.screenFeedCommentErrorReplyGoneMessage)
        case .temporarilyUnavailable:
            (UntranslatedL10n.screenFeedCommentErrorGenericTitle, UntranslatedL10n.screenFeedCommentErrorTryShortlyMessage)
        case .forbidden:
            // Synapse does not show the account (locked or suspended there).
            (UntranslatedL10n.screenFeedCommentErrorSuspendedTitle, UntranslatedL10n.screenFeedCommentErrorAccountRestrictedMessage)
        case .transport:
            (UntranslatedL10n.screenFeedCommentErrorGenericTitle, UntranslatedL10n.screenFeedCommentErrorGenericMessage)
        default:
            // The server answered: the connection is not to blame.
            (UntranslatedL10n.screenFeedCommentErrorGenericTitle, UntranslatedL10n.screenFeedCommentErrorServerMessage)
        }
    }

    // MARK: - Rules

    func acceptRules() async {
        guard !state.isAcceptingRules else { return }
        state.isAcceptingRules = true
        state.rulesAcceptFailed = false

        let result = await feedService.acceptRules(version: FeedRules.version)
        state.isAcceptingRules = false

        switch result {
        case .success(let standing):
            hasAcceptedRules = true
            state.standing = standing
            state.bindings.isPresentingRules = false
            // The same text and reply: the same key.
            if let key = commentAwaitingRules {
                commentAwaitingRules = nil
                await retryComment(key)
            }
        case .failure(.rulesNotAccepted(let currentVersion)):
            state.bindings.isPresentingRules = false
            if FeedRules.isOutdated(serverVersion: currentVersion) {
                presentCommentAlert(.updateRequired, title: UntranslatedL10n.screenFeedComposerUpdateRequiredTitle,
                                    message: UntranslatedL10n.screenFeedCommentUpdateRequiredMessage)
            } else {
                presentCommentAlert(.postingPaused, title: UntranslatedL10n.screenFeedComposerErrorReadOnlyTitle,
                                    message: UntranslatedL10n.screenFeedCommentReadOnlyMessage)
            }
        case .failure(let error):
            MXLog.error("Failed to accept the feed rules: \(error)")
            state.rulesAcceptFailed = true
        }
    }

    /// An alert set while the rules sheet is still closing is dropped by
    /// SwiftUI, so it waits for the sheet's `onDismiss`.
    private func presentCommentAlert(_ id: FeedPostScreenAlertType, title: String, message: String) {
        let alert = AlertInfo(id: id, title: title, message: message)
        if isRulesSheetOnScreen {
            pendingAlert = alert
        } else {
            state.bindings.alertInfo = alert
        }
    }

    // MARK: - Delete

    func confirmDeleteComment(_ commentID: String) {
        guard let item = state.visibleComments.first(where: { $0.id == commentID }), item.comment.canDelete else { return }
        state.bindings.alertInfo = .init(id: .confirmDeleteComment(commentID: commentID),
                                         title: UntranslatedL10n.screenFeedCommentDeleteTitle,
                                         message: UntranslatedL10n.screenFeedCommentDeleteMessage,
                                         primaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil),
                                         secondaryButton: .init(title: L10n.actionDelete, role: .destructive) { [weak self] in
                                             Task { await self?.deleteComment(commentID) }
                                         })
    }

    func deleteComment(_ commentID: String) async {
        let result = await runWithIndicator { await self.feedService.deleteComment(id: commentID) }

        switch result {
        case .success, .failure(.notFound):
            // The feed's own 404 is "no comment you may delete with this id": it is gone either way.
            removeComment(commentID)
            userIndicatorController.submitIndicator(UserIndicator(type: .toast, title: UntranslatedL10n.screenFeedCommentDeleted, icon: \.checkCircle))
        case .failure(let error):
            MXLog.error("Failed to delete feed comment \(commentID): \(error)")
            state.bindings.alertInfo = .init(id: .deleteCommentFailed,
                                             title: UntranslatedL10n.screenFeedCommentDeleteFailed,
                                             message: Self.deleteCommentFailedMessage(for: error))
        }
    }

    /// Why the comment is still there; the connection only when there was no answer.
    static func deleteCommentFailedMessage(for error: FeedError) -> String {
        switch error {
        case .transport:
            UntranslatedL10n.screenFeedCommentDeleteFailedMessage
        case .unavailable:
            UntranslatedL10n.screenFeedCommentDeleteFailedUnavailableMessage
        case .rateLimited, .temporarilyUnavailable:
            UntranslatedL10n.screenFeedCommentDeleteFailedTryShortlyMessage
        case .forbidden:
            UntranslatedL10n.screenFeedCommentDeleteFailedAccountRestrictedMessage
        default:
            UntranslatedL10n.screenFeedCommentDeleteFailedServerMessage
        }
    }

    private func removeComment(_ commentID: String) {
        store.removeComment(commentID, postID: storeID)
        rebuild()
        if state.replyingTo?.id == commentID {
            state.replyingTo = nil
        }
    }
}

extension FeedComment {
    var withoutReply: FeedComment {
        FeedComment(id: id, postID: postID, author: author, text: text, replyTo: nil, createdAt: createdAt,
                    state: state, heldReason: heldReason, isAuthor: isAuthor, canDelete: canDelete, isSensitive: isSensitive)
    }
}
