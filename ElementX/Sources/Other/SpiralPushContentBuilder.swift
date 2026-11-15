//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0043, ADR-0057): builder for Spiral DIRECT
// pushes — the orchestrator POSTs sygnal itself with
// `{spiral: {kind, id}}` and NO Matrix event exists behind the
// notification. The NSE intercepts these before any SDK work and
// builds the visible content locally, in the DEVICE locale
// (multilingual contract: the wire never carries display text).
//
// Target-portable (ElementX/Other + pulled into NSE via target.yml)
// so UnitTests can pin the payload contract.

import Foundation
import UserNotifications

// `nonisolated`: the NSE calls this off the main actor; upstream's Swift 6.2
// default-MainActor isolation would otherwise capture the whole enum.
nonisolated enum SpiralPushContentBuilder {
    /// Top-level payload key sygnal merges from the per-device
    /// `default_payload` (see backend `adapters/spiral_push.rs`).
    static let payloadKey = "spiral"
    static let kindKey = "kind"
    static let idKey = "id"
    /// An approval's escalation tag (Brief 0078) — metadata, never display text.
    static let reasonKey = "reason"
    /// AGENT-PLATFORM: feed (Brief 0082): a `feed_comment`'s or `feed_reply`'s post, the thread it groups under.
    static let postKey = "post"
    /// AGENT-PLATFORM: feed (Brief 0082): a `feed_like`'s UTC day, naming its activity entry `like:<post>:<group>`.
    static let groupKey = "group"

    /// What a Spiral push points at.
    struct Subject {
        let kind: String
        let id: String
        /// Absent for verifications and for approvals the platform escalated without a tag.
        let reason: String?
        /// A `feed_comment`'s or `feed_reply`'s post (Brief 0082); absent for every other kind.
        var post: String?
        /// A `feed_like`'s day (Brief 0082); absent for every other kind.
        var group: String?

        /// The post a feed engagement push is about: a like names it as its id.
        var feedPostID: String? {
            switch kind {
            case "feed_like": id
            case "feed_comment", "feed_reply": post?.isEmpty == false ? post : nil
            default: nil
            }
        }
    }

    /// Extract the subject from an APNs payload, or nil when this
    /// isn't a Spiral direct push.
    static func extractSubject(from userInfo: [AnyHashable: Any]) -> Subject? {
        guard let spiral = userInfo[payloadKey] as? [String: Any],
              let kind = spiral[kindKey] as? String,
              let id = spiral[idKey] as? String,
              !id.isEmpty else {
            return nil
        }
        return Subject(kind: kind, id: id, reason: spiral[reasonKey] as? String, post: spiral[postKey] as? String, group: spiral[groupKey] as? String)
    }

    /// Build the localized notification for a Spiral push. Sets the
    /// category and the deep-link userInfo key that tap and inline-action
    /// routing read. A kind this build does not know says to update the
    /// app (decision 96). nil only when the base content cannot be copied.
    ///
    /// `reason` words an approval by why it escalated, through the same mapping
    /// as the approval card (Brief 0078); without one, or with a tag this build
    /// does not know, the banner keeps a line true for any approval.
    static func build(kind: String,
                      subjectID: String,
                      baseContent: UNNotificationContent,
                      reason: String? = nil,
                      post: String? = nil) -> UNNotificationContent? {
        guard let content = baseContent.mutableCopy() as? UNMutableNotificationContent else {
            return nil
        }
        let feedPostID = Subject(kind: kind, id: subjectID, reason: nil, post: post).feedPostID
        switch kind {
        case "approval":
            let escalation = ApprovalEscalation(reason: reason, contextKind: nil, hasVisitor: false)
            content.body = escalation.pushBody
            // A block request is tap-to-review only (operator question 88).
            content.categoryIdentifier = escalation == .blockSender ? NotificationConstants.Category.blockRequest : NotificationConstants.Category.approval
            content.userInfo[NotificationConstants.UserInfoKey.agentApprovalIdentifier] = subjectID
        case "verification":
            content.body = UntranslatedL10n.notificationVerificationBody
            content.categoryIdentifier = NotificationConstants.Category.verification
            content.userInfo[NotificationConstants.UserInfoKey.agentVerificationIdentifier] = subjectID
        // AGENT-PLATFORM: feed (Brief 0082, decision 266): ids only on the wire; the text is the device's.
        case "feed_notice":
            content.body = UntranslatedL10n.notificationFeedNoticeBody
            content.categoryIdentifier = NotificationConstants.Category.feedNotice
            content.threadIdentifier = "feed:notices"
            content.userInfo[NotificationConstants.UserInfoKey.feedNoticeIdentifier] = subjectID
        // The generic words; the NSE puts the name and the text in when it can read them (`FeedPushActivityReader`).
        case "feed_like" where feedPostID != nil, "feed_comment" where feedPostID != nil, "feed_reply" where feedPostID != nil:
            let postID = feedPostID ?? subjectID
            content.body = switch kind {
            case "feed_like": UntranslatedL10n.notificationFeedLikeBody
            case "feed_reply": UntranslatedL10n.notificationFeedReplyBody
            default: UntranslatedL10n.notificationFeedCommentBody
            }
            content.categoryIdentifier = NotificationConstants.Category.feedPost
            content.threadIdentifier = "feed:\(postID)"
            content.userInfo[NotificationConstants.UserInfoKey.feedPostIdentifier] = postID
        default:
            // A newer platform's kind (or a comment push without its post): nothing to act on or open here.
            content.body = UntranslatedL10n.notificationSpiralNeedsUpdateBody
        }
        content.title = InfoPlistReader.main.bundleDisplayName
        content.sound = .default
        return content
    }
}
