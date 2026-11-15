//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The feed's accessibility identifiers, in
// our own file so `AccessibilityIdentifiers.swift` stays untouched; the E2E
// scenarios FD1–FD8 drive them.
//

extension A11yIdentifiers {
    static let feedScreen = FeedScreen()
    static let feedAuthorScreen = FeedAuthorScreen()
    static let feedReportScreen = FeedReportScreen()
    static let feedNoticesScreen = FeedNoticesScreen()
    static let feedActivityScreen = FeedActivityScreen()
    static let feedLikersScreen = FeedLikersScreen()
    static let feedNotificationSettings = FeedNotificationSettings()
    static let feedBioEditor = FeedBioEditor()

    struct FeedScreen {
        let tab = "home_tabs-feed"
        let postCard = "feed-post_card"
        let pinnedPost = "feed-pinned_post"
        let newPostsPill = "feed-new_posts_pill"
        let empty = "feed-empty"
        let unavailable = "feed-unavailable"
        let error = "feed-error"
        let offlineBanner = "feed-offline_banner"
        let postNotAvailable = "feed-post_not_available"
        // Lane I3, for the E2E scenarios FD3 (counts) and FD7 (share).
        let like = "feed-like"
        let comment = "feed-comment"
        let share = "feed-share"
        let postMenu = "feed-post_menu"
        let commentRow = "feed-comment_row"
        let commentField = "feed-comment_field"
        let sendComment = "feed-send_comment"
        let commentsOff = "feed-comments_off"
        let hiddenNotice = "feed-hidden_notice"
        // Lane I3 on B4, for FD5 (report → remove → notices).
        let report = "feed-report"
        let reportComment = "feed-report_comment"
        let postStatement = "feed-post_statement"
        // The card's author button (FD6) and text (FD3, FD5, FD7 open the post by it).
        let postAuthor = "feed-post_author"
        let postText = "feed-post_text"
        // Lane I5: the count that opens who liked (the likers and live-count scenarios).
        let likesCount = "feed-likes_count"
        let noticeWhy = "feed-notice_why"
        // Decision 289: the sync's state and what is on its way.
        let syncStatus = "feed-sync_status"
        let pendingPost = "feed-pending_post"
        let pendingComment = "feed-pending_comment"
    }

    struct FeedAuthorScreen {
        let message = "feed_author-message"
        let more = "feed_author-more"
        let block = "feed_author-block"
        let report = "feed_author-report"
        let bio = "feed_author-bio"
    }

    /// The bio in the profile editor (`UserDetailsEditScreen`).
    struct FeedBioEditor {
        let field = "edit_profile-bio"
        let loadFailed = "edit_profile-bio_load_failed"
        let count = "edit_profile-bio_count"
    }

    struct FeedReportScreen {
        let detail = "feed_report-detail"
        let send = "feed_report-send"
        let done = "feed_report-done"
        let receipt = "feed_report-receipt"

        /// By the wire code, so the E2E target needs no app types.
        func reason(_ code: String) -> String {
            "feed_report-reason_\(code)"
        }
    }

    /// Lane I5: behind the bell.
    struct FeedActivityScreen {
        let entry = "feed_activity-entry"
        let fromSpiral = "feed_activity-from_spiral"
        let empty = "feed_activity-empty"
        let error = "feed_activity-error"
    }

    struct FeedLikersScreen {
        let liker = "feed_likers-liker"
        let empty = "feed_likers-empty"
        let error = "feed_likers-error"
    }

    struct FeedNoticesScreen {
        let toolbarButton = "feed_notices-toolbar_button"
        let notice = "feed_notices-notice"
        let empty = "feed_notices-empty"
        let error = "feed_notices-error"
    }

    struct FeedNotificationSettings {
        let likes = "feed_notification_settings-likes"
        let comments = "feed_notification_settings-comments"
        let replies = "feed_notification_settings-replies"
    }
}
