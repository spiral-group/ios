//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM: where a tap on a Spiral push goes, from the payload the
// orchestrator sends (`adapters/spiral_push.rs`) to the app route.

import Foundation
@testable import Spiral
import Testing
import UserNotifications

struct AgentPlatformNotificationRouteTests {
    /// A personal agent's first contact escalates to an approval, and the
    /// push names that approval (ADR-0087): the tap opens its card.
    @Test
    func aFirstContactApprovalPushOpensTheApprovalCard() throws {
        let content = try Self.builtContent(kind: "approval", id: "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b")

        #expect(content.agentPlatformRoute == .approvalDetail(approvalID: "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b"))
    }

    /// A block request's tap-only push opens its card (operator question 88).
    @Test
    func aBlockRequestPushOpensItsCard() {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = NotificationConstants.Category.blockRequest
        content.agentApprovalID = "appr-block"

        #expect(content.agentPlatformRoute == .approvalDetail(approvalID: "appr-block"))
    }

    @Test
    func aVerificationPushOpensTheVerificationScreen() throws {
        let content = try Self.builtContent(kind: "verification", id: "verification-1")

        #expect(content.agentPlatformRoute == .verificationDetail(verificationID: "verification-1"))
    }

    @Test
    func aMessageKeepsItsOwnRoad() {
        let message = UNMutableNotificationContent()
        message.categoryIdentifier = NotificationConstants.Category.message
        message.roomID = "!room:spiral.md"
        message.agentApprovalID = "stray"

        #expect(message.agentPlatformRoute == nil)
    }

    // MARK: - Feed (Brief 0082, decision 266)

    /// A notice push carries the notice id only: the tap opens the notices.
    @Test
    func aFeedNoticePushOpensTheNotices() throws {
        let content = try Self.builtContent(kind: "feed_notice", id: "0199d0a1-0000-7000-8000-00000000a001")

        #expect(content.agentPlatformRoute == .feedNotices)
    }

    /// A comment push opens its post; a removed one then reads "This post isn't available".
    @Test
    func aFeedCommentPushOpensItsPost() throws {
        let content = try Self.builtContent(kind: "feed_comment", id: "0199d0a1-0000-7000-8000-00000000c001",
                                            post: "0199D0A1-0000-7000-8000-00000000B001")

        #expect(content.agentPlatformRoute == .feedPost(postID: "0199d0a1-0000-7000-8000-00000000b001"))
    }

    /// Lane I5: a like push names the post as its id, a reply its post: both open it.
    @Test(arguments: [("feed_like", "0199D0A1-0000-7000-8000-00000000B001", nil as String?),
                      ("feed_reply", "0199d0a1-0000-7000-8000-00000000c002", "0199D0A1-0000-7000-8000-00000000B001")])
    func aLikeOrReplyPushOpensItsPost(kind: String, id: String, post: String?) throws {
        let content = try Self.builtContent(kind: kind, id: id, post: post)

        #expect(content.agentPlatformRoute == .feedPost(postID: "0199d0a1-0000-7000-8000-00000000b001"))
    }

    /// A comment push without its post opens nothing, and says to update.
    @Test
    func aFeedCommentPushWithoutAPostOpensNothing() throws {
        let content = try Self.builtContent(kind: "feed_comment", id: "0199d0a1-0000-7000-8000-00000000c001")

        #expect(content.agentPlatformRoute == nil)
        #expect(content.body == UntranslatedL10n.notificationSpiralNeedsUpdateBody)
    }

    /// What the NSE hands the system for this payload.
    private static func builtContent(kind: String, id: String, post: String? = nil) throws -> UNNotificationContent {
        let base = UNMutableNotificationContent()
        var spiral: [String: Any] = ["version": 1, "kind": kind, "id": id]
        spiral["post"] = post
        base.userInfo = ["spiral": spiral, "aps": ["mutable-content": 1]]
        let subject = try #require(SpiralPushContentBuilder.extractSubject(from: base.userInfo))
        return try #require(SpiralPushContentBuilder.build(kind: subject.kind, subjectID: subject.id, baseContent: base, post: subject.post))
    }
}
