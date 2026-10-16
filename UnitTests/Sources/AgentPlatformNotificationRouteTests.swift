//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM: where a tap on a Spiral push goes, from the payload the
// orchestrator sends (`adapters/spiral_push.rs`) to the app route.

@testable import ElementX
import Foundation
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

    /// What the NSE hands the system for this payload.
    private static func builtContent(kind: String, id: String) throws -> UNNotificationContent {
        let base = UNMutableNotificationContent()
        base.userInfo = ["spiral": ["version": 1, "kind": kind, "id": id], "aps": ["mutable-content": 1]]
        let subject = try #require(SpiralPushContentBuilder.extractSubject(from: base.userInfo))
        return try #require(SpiralPushContentBuilder.build(kind: subject.kind, subjectID: subject.id, baseContent: base))
    }
}
