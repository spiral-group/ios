//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). One post, reached from a card or a
// `/feed/<id>` link: the author's delete (lane I2), and the like, the flat
// comments with "replying to", hide, share and the author's comment switch
// (lane I3).
//

import Foundation

enum FeedPostScreenViewModelAction {
    case openAuthor(FeedAuthor)
    /// The author deleted the post (lane I2); the screen closes.
    case deleted
    /// Lane I3: the chat picker for this post.
    case share(FeedPost)
    /// Lane I3 on B4: the report screen for the post or one of its comments.
    case report(FeedReportTarget)
    /// The person's notices, from the banner of their held or removed post.
    case openNotices
    /// Lane I5: who liked the post.
    case openLikers(postID: String)
}

enum FeedPostLoadState: Equatable {
    case loading
    case loaded(FeedItem)
    /// Not there for this person, whatever the reason (`404`, an unknown or
    /// author-hidden state, or an author they block): "This post isn't available".
    case notAvailable
    /// `FEED_MODE=off`.
    case unavailable
    /// The post could not be read: never shown as "not available".
    case failed
}

/// A comment with its text prepared once.
struct FeedCommentItem: Identifiable, Equatable {
    let comment: FeedComment
    let text: AttributedString?
    /// The http(s) links in the text, for VoiceOver.
    let links: [URL]
    /// The person's comment on its way (decision 289): the key it is sent with, and how it goes.
    let pendingKey: UUID?
    let delivery: FeedDelivery?

    init(comment: FeedComment) {
        self.init(comment: comment, pendingKey: nil, delivery: nil)
    }

    init(pending: FeedPendingComment) {
        self.init(comment: pending.comment, pendingKey: pending.key, delivery: pending.delivery)
    }

    private init(comment: FeedComment, pendingKey: UUID?, delivery: FeedDelivery?) {
        self.comment = comment
        self.pendingKey = pendingKey
        self.delivery = delivery
        text = comment.text.isEmpty ? nil : FeedTextBuilder.attributedString(from: comment.text)
        links = text.map(FeedTextBuilder.links(in:)) ?? []
    }

    var id: String {
        comment.id
    }

    var isPending: Bool {
        pendingKey != nil
    }

    /// A state newer than this build shows nothing of the comment (decision 96).
    var isAvailable: Bool {
        if case .other = comment.state { false } else { true }
    }

    /// Only its author sees a held or removed comment, with why.
    var authorLabel: String? {
        switch comment.state {
        case .held: UntranslatedL10n.screenFeedPostHeldLabel
        case .removed: UntranslatedL10n.screenFeedPostRemovedLabel
        case .visible, .other: nil
        }
    }

    /// A reply is offered to a visible comment the server has.
    var canReply: Bool {
        comment.state == .visible && !isPending
    }

    /// Someone else's visible comment (lane I3 on B4).
    var canReport: Bool {
        comment.state == .visible && !comment.isAuthor && !isPending
    }

    /// The row as one VoiceOver element, never the hidden text of a sensitive comment.
    func accessibilityLabel(isRevealed: Bool) -> String {
        guard isAvailable else { return UntranslatedL10n.screenFeedCommentNotAvailable }
        var parts = [comment.author.displayName]
        if comment.author.isOfficial {
            parts.append(UntranslatedL10n.screenFeedOfficialLabel)
        }
        if let reply = comment.replyTo {
            parts.append(UntranslatedL10n.a11yFeedReplyingTo(reply.author.displayName))
        }
        if !isPending {
            parts.append(comment.createdAt.formatted(.relative(presentation: .named, unitsStyle: .wide)))
        }
        if let authorLabel {
            parts.append(authorLabel)
        }
        if comment.isSensitive, !isRevealed {
            parts.append(UntranslatedL10n.screenFeedSensitiveTitle)
        } else if let text {
            parts.append(String(text.characters))
        }
        switch delivery {
        case .sending: parts.append(L10n.commonSending)
        case .failed: parts.append(UntranslatedL10n.screenFeedCommentSendFailed)
        case nil: break
        }
        return parts.joined(separator: ", ")
    }
}

/// The notice that says why the author's post is held, removed or marked sensitive (lane I3 on B4).
enum FeedPostStatementState: Equatable {
    /// Not the author's held, removed or sensitive post.
    case none
    case loading
    /// `nil`: no notice about it among the latest ones; the banner says only what happened.
    case loaded(FeedNoticeContent?)
    /// The notices could not be read: never shown as "no reasons".
    case failed
}

enum FeedCommentsState: Equatable {
    /// Not read yet, or being read.
    case loading
    case loaded([FeedCommentItem], loadMore: LoadMoreState)
    /// The author turned comments off: nobody but the author sees them.
    case off
    /// The feed's own `404` on the comments: the post is gone, or comments went off meanwhile.
    case notAvailable
    /// Could not be read: never shown as "no comments".
    case failed
}

struct FeedPostScreenViewState: BindableState {
    let postID: String
    var loadState: FeedPostLoadState = .loading
    var blockedUserIDs: Set<String> = []
    var isRevealed = false
    /// Hidden until the person's media setting is read.
    var hidesMedia = true

    // MARK: Comments (lane I3)

    var commentsState: FeedCommentsState = .loading
    /// The person's comments on their way, oldest first, under the others.
    var pendingComments: [FeedCommentItem] = []
    var revealedCommentIDs: Set<String> = []
    /// The comment the next one replies to.
    var replyingTo: FeedCommentItem?
    /// Read when a comment meets the daily cap, to name it.
    var standing: FeedStanding?
    var isAcceptingRules = false
    var rulesAcceptFailed = false
    /// Bumped to put the cursor in the comment field.
    var focusCommentFieldRequest = 0

    /// The statement of reasons behind the author's held or removed post, from their notices (lane I3 on B4).
    var authorStatement: FeedPostStatementState = .none

    /// Lane I5: the comment the screen opened at (from Activity), scrolled to and marked once it is read.
    var focusedCommentID: String?

    /// "Updating…" or "No connection" at the top, in place of pull to refresh (decision 289).
    var syncStatus: PlatformSyncStatus?

    var bindings = FeedPostScreenViewStateBindings()

    /// Nothing is being read: the post and, when they show, its comments.
    var isSettled: Bool {
        if case .loading = loadState { return false }
        if authorStatement == .loading { return false }
        guard showsComments else { return true }
        if case .loading = commentsState { return false }
        return true
    }

    /// The state the screen shows, after the person's blocks.
    var visibleLoadState: FeedPostLoadState {
        if case .loaded(let item) = loadState, blockedUserIDs.contains(item.post.author.userID) {
            return .notAvailable
        }
        return loadState
    }

    var post: FeedPost? {
        if case .loaded(let item) = visibleLoadState { item.post } else { nil }
    }

    /// Only the author deletes, in any state (lane I2).
    var canDelete: Bool {
        post?.viewer.isAuthor == true
    }

    /// Everyone but the author hides a visible post from their lists.
    var canHide: Bool {
        guard let post else { return false }
        return post.state == .visible && !post.viewer.isAuthor && !post.viewer.hidden
    }

    /// The author's comment switch, on a post others can see.
    var canToggleComments: Bool {
        guard let post else { return false }
        return post.viewer.isAuthor && post.state == .visible
    }

    /// Everyone but the author reports a visible post (lane I3 on B4).
    var canReport: Bool {
        guard let post else { return false }
        return post.state == .visible && !post.viewer.isAuthor
    }

    /// The person hid this post; it is still readable by id.
    var isHidden: Bool {
        post?.viewer.hidden == true
    }

    /// Only the author sees a held or removed post, with why; and their post
    /// marked sensitive (decision 278), which everyone else sees behind "Show".
    var authorNotice: String? {
        guard let post else { return nil }
        return switch FeedPostScreenViewModel.statementKind(for: post) {
        case .held: UntranslatedL10n.screenFeedPostHeldNotice
        case .removed: UntranslatedL10n.screenFeedPostRemovedNotice
        case .sensitive: UntranslatedL10n.screenFeedPostSensitiveNotice
        default: nil
        }
    }

    /// A held or removed post only its author sees; a sensitive one has Delete in the menu.
    var authorNoticeOffersDelete: Bool {
        post?.state == .held || post?.state == .removed
    }

    /// Comments belong to a post others can see.
    var showsComments: Bool {
        post?.state == .visible
    }

    /// The comment field: on a visible post whose comments are on.
    var canComment: Bool {
        guard let post else { return false }
        return post.state == .visible && post.commentsEnabled
    }

    /// A comment shows at once as sending: another can follow it straight away.
    var canSendComment: Bool {
        canComment && FeedCommentText.isPostable(bindings.commentText)
    }

    /// The comments to show, without anyone the person blocks.
    var visibleComments: [FeedCommentItem] {
        guard case .loaded(let items, _) = commentsState else { return [] }
        guard !blockedUserIDs.isEmpty else { return items }
        return items.filter { !blockedUserIDs.contains($0.comment.author.userID) }
    }

    var commentsSentinel: LoadMoreState? {
        guard case .loaded(_, let loadMore) = commentsState, loadMore != .exhausted else { return nil }
        return loadMore
    }

    /// Only a read that reached its end with nothing to show is "No comments yet".
    var hasNoComments: Bool {
        guard case .loaded(_, .exhausted) = commentsState else { return false }
        return visibleComments.isEmpty && pendingComments.isEmpty
    }

    /// The daily cap, once the standing that names it was read.
    var commentCapNotice: String? {
        guard let standing, standing.hasReachedCommentCap, let cap = standing.commentsPerDay else { return nil }
        return UntranslatedL10n.screenFeedCommentDailyCapNotice(cap)
    }

    /// Shown near the limit and past it; `nil` well below it.
    var commentCounter: String? {
        let length = FeedCommentText.length(of: bindings.commentText)
        if length > FeedCommentText.maximumLength {
            return UntranslatedL10n.screenFeedComposerCharactersOver(length - FeedCommentText.maximumLength)
        }
        guard length >= FeedCommentText.counterThreshold else { return nil }
        return UntranslatedL10n.screenFeedComposerCharactersLeft(FeedCommentText.maximumLength - length)
    }
}

struct FeedPostScreenViewStateBindings {
    var mediaPreviewItem: MediaPreviewItem?
    var alertInfo: AlertInfo<FeedPostScreenAlertType>?
    var commentText = ""
    var isPresentingRules = false
}

enum FeedPostScreenAlertType: Hashable {
    case confirmDelete
    case deleteFailed
    // Lane I3.
    case confirmDeleteComment(commentID: String)
    case deleteCommentFailed
    case commentRefused
    case updateRequired
    case postingPaused
    case actionFailed
}

enum FeedPostScreenViewAction {
    /// Shown: the post and its comments are read again when the sync says they changed.
    case appeared
    case disappeared
    case retry
    case card(FeedPostCardAction)
    /// Asks first; the post goes only when the server says it went.
    case delete
    // Lane I3.
    case loadMoreComments
    case retryComments
    case sendComment
    case reply(commentID: String)
    case cancelReply
    case deleteComment(commentID: String)
    case revealComment(commentID: String)
    /// The person's comment on its way that failed (decision 289).
    case retryComment(UUID)
    case discardComment(UUID)
    case openCommentAuthor(commentID: String)
    case setCommentsEnabled(Bool)
    case hide
    case unhide
    // Lane I3 on B4.
    case report
    case reportComment(commentID: String)
    case retryStatement
    case openNotices
    case acceptRules
    case declineRules
    /// The rules sheet has finished closing: an alert waiting on it can show.
    case rulesSheetDismissed
}
