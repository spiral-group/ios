//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The public feed: the read side (lane
// I1), text posting (lane I2), engagement, reports and notices (lane I3),
// activity and who liked (lane I5). What changed comes over the platform
// sync stream (`PlatformSyncService`, decision 289).
// Reached as `agentPlatformService.feed`; ViewModels see the app-owned types
// in `FeedModels.swift`, `FeedPostingModels.swift`,
// `FeedEngagementModels.swift` and `FeedModerationModels.swift`, never the
// generated ones.
//

import Combine
import Foundation

// sourcery: AutoMockable
protocol FeedServiceProtocol {
    /// `GET /feed/latest`: newest first. `cursor == nil` is the first page,
    /// which is also kept for `cachedFirstPage`.
    func latest(cursor: String?, limit: Int) async -> Result<FeedPage, FeedError>

    /// `GET /feed/posts/{id}`.
    func post(id: String) async -> Result<FeedPost, FeedError>

    /// `GET /feed/authors/{mxid}/posts`: one author's visible posts.
    func authorPosts(userID: String, cursor: String?, limit: Int) async -> Result<FeedPage, FeedError>

    /// The last first page of Latest that was read, for the offline state.
    /// `nil` when none was read on this device for this account.
    func cachedFirstPage() -> FeedPage?

    // MARK: - Posting (lane I2)

    /// `GET /feed/me/posts`: the person's own posts in every state, so a held
    /// ("Under review") or removed one stays findable.
    func ownPosts(cursor: String?, limit: Int) async -> Result<FeedPage, FeedError>

    /// `POST /feed/posts` with the composer session's key: a retry with the
    /// same key and text answers the post it already made.
    func createPost(text: String, idempotencyKey: UUID) async -> Result<FeedPost, FeedError>

    /// `DELETE /feed/posts/{id}`, the author's own post.
    func deletePost(id: String) async -> Result<Void, FeedError>

    /// `GET /feed/me/standing`: rules, the daily caps and a suspension.
    func standing() async -> Result<FeedStanding, FeedError>

    /// `POST /feed/rules/accept` with the version the person read; a `409`
    /// says the app's rules are not the server's current ones.
    func acceptRules(version: String) async -> Result<FeedStanding, FeedError>

    /// The draft kept on this device for this account, if any.
    func draft() -> FeedDraft?
    func saveDraft(_ draft: FeedDraft)
    func deleteDraft()

    // MARK: - Engagement (lane I3)

    /// `PUT` / `DELETE /feed/posts/{id}/like`: the server's count after it.
    func setLiked(_ liked: Bool, postID: String) async -> Result<FeedLikes, FeedError>

    /// `PUT` / `DELETE /feed/posts/{id}/hide`.
    func setHidden(_ hidden: Bool, postID: String) async -> Result<Void, FeedError>

    /// `GET /feed/posts/{id}/comments`: oldest first; the person's own in any state.
    func comments(postID: String, cursor: String?, limit: Int) async -> Result<FeedCommentPage, FeedError>

    /// `POST /feed/posts/{id}/comments`: one key per comment sent; a retry of
    /// the same text with the same key answers the comment it already made.
    func createComment(postID: String, text: String, replyTo: String?, idempotencyKey: UUID) async -> Result<FeedComment, FeedError>

    /// `DELETE /feed/comments/{id}`: their own, or one under their post.
    func deleteComment(id: String) async -> Result<Void, FeedError>

    /// `PATCH /feed/posts/{id}` by the author: the post as the server answered it.
    func setCommentsEnabled(_ enabled: Bool, postID: String) async -> Result<FeedPost, FeedError>

    /// `POST /feed/posts/{id}/share`: the message the server built for `roomID`,
    /// in `language` (`en`, `uk` or `ru`; English otherwise).
    func share(postID: String, roomID: String, language: String?) async -> Result<FeedShareMessage, FeedError>

    // MARK: - Reports and notices (lane I3, B4's contract)

    /// `POST …/report`: the receipt. A second report of the same thing while
    /// the first is open answers that receipt (`isExisting`), not a failure.
    func report(_ target: FeedReportTarget, reason: FeedReportReason, detail: String?) async -> Result<FeedReportReceipt, FeedError>

    /// `GET /feed/notices`, newest first; the rules' texts in `language`.
    /// A page read sets `noticesUnreadPublisher`; a failed one leaves it.
    func notices(cursor: String?, limit: Int, language: String?) async -> Result<FeedNoticePage, FeedError>

    /// `POST /feed/notices/{id}/read`, for an unread notice: once the server answers, the count is read again from it (a failed re-read leaves the last one).
    func markNoticeRead(id: String) async -> Result<Void, FeedError>

    /// The unread notices as the server last counted them; nothing until it has.
    var noticesUnreadPublisher: AnyPublisher<Int, Never> { get }

    // MARK: - Activity, who liked and push settings (lane I5, B6's contract)

    /// `GET /feed/activity`, newest first, kinds this build knows only. A page read sets `activityUnreadPublisher`.
    func activity(cursor: String?, limit: Int) async -> Result<FeedActivityPage, FeedError>

    /// `POST /feed/activity/seen` up to `date` (the newest entry shown; `nil` is now): the unread count after it.
    func markActivitySeen(upTo date: Date?) async -> Result<Int, FeedError>

    /// The unread activity as the server last counted it (a page, the seen mark); nothing until it has.
    var activityUnreadPublisher: AnyPublisher<Int, Never> { get }

    /// `GET /feed/posts/{id}/likes`: who liked the post, newest first.
    func likers(postID: String, cursor: String?, limit: Int) async -> Result<FeedLikersPage, FeedError>

    /// `GET /feed/me/notification-settings`.
    func notificationSettings() async -> Result<FeedNotificationSettings, FeedError>

    /// `PUT /feed/me/notification-settings` with all three kinds: the settings as the server stored them.
    func setNotificationSettings(_ settings: FeedNotificationSettings) async -> Result<FeedNotificationSettings, FeedError>
}
