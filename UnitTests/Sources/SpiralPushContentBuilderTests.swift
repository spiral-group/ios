//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM: Brief 0043 (ADR-0057) — pins the Spiral direct-push
// payload contract against backend `adapters/spiral_push.rs`.

@testable import ElementX
import Foundation
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
