//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM: Brief 0043 (ADR-0057) — pins the Spiral direct-push
// payload contract against backend `adapters/spiral_push.rs`.

import Foundation
@testable import Spiral
import Testing
import UserNotifications

struct SpiralPushContentBuilderTests {
    @Test
    func extractsSubjectFromBackendPayloadShape() {
        // Mirrors the `default_payload` merge sygnal performs.
        let userInfo: [AnyHashable: Any] = [
            "spiral": ["version": 1, "kind": "approval", "id": "abc-123"],
            "aps": ["mutable-content": 1]
        ]
        let subject = SpiralPushContentBuilder.extractSubject(from: userInfo)
        #expect(subject?.kind == "approval")
        #expect(subject?.id == "abc-123")
    }

    @Test
    func nonSpiralPayloadsAreIgnored() {
        #expect(SpiralPushContentBuilder.extractSubject(from: ["room_id": "!x:y"]) == nil)
        #expect(SpiralPushContentBuilder.extractSubject(from: ["spiral": ["kind": "approval", "id": ""]]) == nil)
    }

    @Test
    func buildsLocalizedContentPerKind() {
        let base = UNMutableNotificationContent()
        let cases: [(String, String, String)] = [
            ("approval", NotificationConstants.Category.approval, NotificationConstants.UserInfoKey.agentApprovalIdentifier),
            ("verification", NotificationConstants.Category.verification, NotificationConstants.UserInfoKey.agentVerificationIdentifier)
        ]
        for (kind, category, userInfoKey) in cases {
            let content = SpiralPushContentBuilder.build(kind: kind, subjectID: "id-1", baseContent: base)
            #expect(content?.categoryIdentifier == category, "kind \(kind)")
            #expect(content?.userInfo[userInfoKey] as? String == "id-1", "kind \(kind)")
            #expect(content?.body.isEmpty == false, "kind \(kind)")
        }
    }

    /// Brief 0082 (decision 266): the feed's kinds carry ids only; the text
    /// is the device's, and every push of one post groups under it.
    @Test
    func feedPushesAreWordedOnTheDeviceAndGroupedByPost() throws {
        let base = UNMutableNotificationContent()
        let subject = try #require(SpiralPushContentBuilder.extractSubject(from: ["spiral": ["version": 1, "kind": "feed_comment", "id": "c1", "post": "p1"]]))
        #expect(subject.post == "p1")

        let comment = try #require(SpiralPushContentBuilder.build(kind: subject.kind, subjectID: subject.id, baseContent: base, post: subject.post))
        #expect(comment.body == UntranslatedL10n.notificationFeedCommentBody)
        #expect(comment.categoryIdentifier == NotificationConstants.Category.feedPost)
        #expect(comment.threadIdentifier == "feed:p1")
        #expect(comment.userInfo[NotificationConstants.UserInfoKey.feedPostIdentifier] as? String == "p1")

        // Lane I5: a like names its post as its id and its day as the group; a reply its post.
        let likeSubject = try #require(SpiralPushContentBuilder.extractSubject(from: ["spiral": ["version": 1, "kind": "feed_like", "id": "p1", "group": "2026-10-30"]]))
        #expect(likeSubject.group == "2026-10-30")
        let like = try #require(SpiralPushContentBuilder.build(kind: likeSubject.kind, subjectID: likeSubject.id, baseContent: base))
        #expect(like.body == UntranslatedL10n.notificationFeedLikeBody)
        #expect(like.categoryIdentifier == NotificationConstants.Category.feedPost)
        #expect(like.threadIdentifier == "feed:p1")
        #expect(like.userInfo[NotificationConstants.UserInfoKey.feedPostIdentifier] as? String == "p1")

        let reply = try #require(SpiralPushContentBuilder.build(kind: "feed_reply", subjectID: "c2", baseContent: base, post: "p1"))
        #expect(reply.body == UntranslatedL10n.notificationFeedReplyBody)
        #expect(reply.threadIdentifier == "feed:p1")
        #expect(reply.userInfo[NotificationConstants.UserInfoKey.feedPostIdentifier] as? String == "p1")

        // A reply without its post opens nothing and says to update.
        let lostReply = try #require(SpiralPushContentBuilder.build(kind: "feed_reply", subjectID: "c2", baseContent: base))
        #expect(lostReply.body == UntranslatedL10n.notificationSpiralNeedsUpdateBody)
        #expect(lostReply.categoryIdentifier.isEmpty)

        let notice = try #require(SpiralPushContentBuilder.build(kind: "feed_notice", subjectID: "n1", baseContent: base))
        #expect(notice.body == UntranslatedL10n.notificationFeedNoticeBody)
        #expect(notice.categoryIdentifier == NotificationConstants.Category.feedNotice)
        #expect(notice.threadIdentifier == "feed:notices")
        #expect(notice.userInfo[NotificationConstants.UserInfoKey.feedNoticeIdentifier] as? String == "n1")
    }

    /// Decision 96: a kind this build does not know (a newer platform's)
    /// still says something, and says to update the app. It showed the
    /// push's bare "Spiral" title. No category and no deep link: there is
    /// nothing here to act on or open.
    @Test
    func anUnknownKindSaysToUpdateTheApp() throws {
        let base = UNMutableNotificationContent()

        let content = try #require(SpiralPushContentBuilder.build(kind: "future-kind", subjectID: "x", baseContent: base))

        #expect(content.body == UntranslatedL10n.notificationSpiralNeedsUpdateBody)
        #expect(content.title == InfoPlistReader.main.bundleDisplayName)
        #expect(content.categoryIdentifier.isEmpty)
        #expect(content.userInfo[NotificationConstants.UserInfoKey.agentApprovalIdentifier] == nil)
        #expect(content.userInfo[NotificationConstants.UserInfoKey.agentVerificationIdentifier] == nil)
    }

    /// Operator question 88: a block request's push is tap-to-review only. It
    /// carried the approval category, so the lock screen offered Approve for
    /// a block the owner had not seen.
    @Test
    func aBlockRequestPushIsTapOnly() {
        let base = UNMutableNotificationContent()

        let block = SpiralPushContentBuilder.build(kind: "approval", subjectID: "id-1", baseContent: base, reason: "block_sender")
        let other = SpiralPushContentBuilder.build(kind: "approval", subjectID: "id-2", baseContent: base, reason: "personal_agent_first_contact")

        #expect(block?.categoryIdentifier == NotificationConstants.Category.blockRequest)
        #expect(block?.userInfo[NotificationConstants.UserInfoKey.agentApprovalIdentifier] as? String == "id-1")
        #expect(other?.categoryIdentifier == NotificationConstants.Category.approval)
    }
}
