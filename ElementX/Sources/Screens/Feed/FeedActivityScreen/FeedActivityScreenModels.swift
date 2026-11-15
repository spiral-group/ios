//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Behind the feed's bell (lane I5,
// decision 287): what others did with the person's posts and comments —
// likes grouped per post and day, comments, replies — newest first, and a
// "From Spiral" row that opens the moderation notices, shown only when there
// is one (decision 288: always there, it reads as a warning). Opening it marks the
// activity seen; a tap opens the post, at the comment.
//

import Foundation

enum FeedActivityScreenViewModelAction {
    case openPost(postID: String, commentID: String?)
    case openNotices
}

/// An entry with its words prepared once.
struct FeedActivityItem: Identifiable, Equatable {
    let entry: FeedActivityEntry
    /// "Taras and 3 others liked your post", or "Taras: so true".
    let title: String
    /// A comment's or reply's "Comment on your post"; `nil` for a like.
    let context: String?

    init(entry: FeedActivityEntry) {
        self.entry = entry
        let name = entry.actors.first?.displayName ?? ""
        switch entry.kind {
        case .like:
            title = FeedActivityText.likes(name: name, others: entry.othersCount)
            context = nil
        case .comment, .reply:
            title = entry.preview.map { FeedActivityText.quote(name: name, text: $0) } ?? name
            context = FeedActivityText.context(isReply: entry.kind == .reply)
        }
    }

    var id: String {
        entry.id
    }

    /// A sensitive comment's text stays behind "Show"; a like has none to hide but its post's.
    var hiddenTitle: String {
        let name = entry.actors.first?.displayName ?? ""
        return entry.kind == .like ? title : name
    }

    /// The row as one VoiceOver element, never a hidden preview.
    func accessibilityLabel(isRevealed: Bool) -> String {
        let shows = !entry.isSensitive || isRevealed
        var parts = [shows ? title : hiddenTitle]
        if let context {
            parts.append(context)
        }
        if shows {
            parts.append(entry.postPreview)
        } else {
            parts.append(UntranslatedL10n.screenFeedSensitiveTitle)
        }
        parts.append(entry.at.formatted(.relative(presentation: .named, unitsStyle: .wide)))
        if entry.isUnread {
            parts.append(UntranslatedL10n.a11yFeedNoticeUnread)
        }
        return parts.joined(separator: ", ")
    }
}

enum FeedActivityListState: Equatable {
    case loading
    case loaded([FeedActivityItem], loadMore: LoadMoreState)
    /// `FEED_MODE=off`.
    case unavailable
    /// The first page could not be read: never shown as "no activity".
    case failed
}

struct FeedActivityScreenViewState: BindableState {
    var listState: FeedActivityListState = .loading
    /// The unread notices as the server last counted them; `nil` until it has.
    var unreadNotices: Int?
    /// Whether the person has any notice, read or not; `nil` until the server has said.
    var hasNotices: Bool?
    /// Sensitive entries the person chose to see.
    var revealedEntryIDs: Set<String> = []
    /// "Updating…" or "No connection" at the top, in place of pull to refresh (decision 289).
    var syncStatus: PlatformSyncStatus?

    var items: [FeedActivityItem] {
        if case .loaded(let items, _) = listState { items } else { [] }
    }

    var sentinel: LoadMoreState? {
        guard case .loaded(_, let loadMore) = listState, loadMore != .exhausted else { return nil }
        return loadMore
    }

    /// A row that is always there reads as a warning; a failed read keeps the way to the notices.
    var showsFromSpiral: Bool {
        hasNotices == true || (unreadNotices ?? 0) > 0
    }

    /// Only a read that reached its end with nothing in it is "No activity yet".
    var isEmpty: Bool {
        guard case .loaded(let items, .exhausted) = listState else { return false }
        return items.isEmpty
    }
}

enum FeedActivityScreenViewAction {
    /// Shown: read again when the sync says Activity changed.
    case appeared
    case disappeared
    /// The failed state's Retry.
    case retry
    case loadMore
    case open(entryID: String)
    case reveal(entryID: String)
    case openNotices
}
