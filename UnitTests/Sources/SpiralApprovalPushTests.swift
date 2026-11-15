//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM (Brief 0078): the approval push said "reply to a new contact" for every
// approval. The platform now names the approval's escalation tag in the payload
// (`spiral.reason`, backend `adapters/spiral_push.rs` `spiral_payload`), and the NSE words
// the banner from it with the approval card's mapping — no REST call from the extension.

import Foundation
@testable import Spiral
import Testing
import UserNotifications

struct SpiralApprovalPushTests {
    // MARK: - Wording

    @Test
    func eachEscalationHasItsPushLine() {
        #expect(ApprovalEscalation.firstContact.pushBody == UntranslatedL10n.notificationApprovalBodyFirstContact)
        #expect(ApprovalEscalation.coldOutreach.pushBody == UntranslatedL10n.notificationApprovalBodyColdOutreach)
        for rule in [ApprovalEscalation.everyReply, .keywords("invoice"), .ruleMatch] {
            #expect(rule.pushBody == UntranslatedL10n.notificationApprovalBodyRuleMatch, "\(rule)")
        }
        #expect(ApprovalEscalation.unknown.pushBody == UntranslatedL10n.notificationApprovalBody)

        let lines = [ApprovalEscalation.firstContact, .coldOutreach, .ruleMatch, .unknown].map(\.pushBody)
        #expect(Set(lines).count == 4)
    }

    @Test
    func theFallbackLineFitsEveryApproval() {
        // A cold outreach or a rule match is not "a new contact" writing in.
        #expect(!UntranslatedL10n.notificationApprovalBody.localizedCaseInsensitiveContains("new contact"))
    }

    // MARK: - From the payload

    /// Every tag the platform writes into `escalation_reason`, which is what `spiral.reason` carries.
    @Test(arguments: [
        ("personal_agent_first_contact", UntranslatedL10n.notificationApprovalBodyFirstContact),
        ("cold_outreach_first_contact", UntranslatedL10n.notificationApprovalBodyColdOutreach),
        ("always", UntranslatedL10n.notificationApprovalBodyRuleMatch),
        ("message_contains(invoice, contract)", UntranslatedL10n.notificationApprovalBodyRuleMatch),
        ("escalation_rule_match", UntranslatedL10n.notificationApprovalBodyRuleMatch),
        ("any_of", UntranslatedL10n.notificationApprovalBodyRuleMatch),
        ("all_of", UntranslatedL10n.notificationApprovalBodyRuleMatch),
        // Decision 38 — `adapters/spiral_push.rs` `wire_reason`.
        ("block_sender", UntranslatedL10n.notificationApprovalBodyBlockSender)
    ])
    func anApprovalIsWordedByTheTagItsPushNames(reason: String, body: String) throws {
        let content = try Self.content(for: Self.payload(kind: "approval", id: "appr-1", reason: reason))

        #expect(content.body == body)
        // A block request is tap-to-review only (operator question 88).
        let category = reason == "block_sender" ? NotificationConstants.Category.blockRequest : NotificationConstants.Category.approval
        #expect(content.categoryIdentifier == category)
        #expect(content.userInfo[NotificationConstants.UserInfoKey.agentApprovalIdentifier] as? String == "appr-1")
    }

    @Test
    func anApprovalWithoutATagGetsTheGenericLine() throws {
        let content = try Self.content(for: Self.payload(kind: "approval", id: "appr-1", reason: nil))
        #expect(content.body == UntranslatedL10n.notificationApprovalBody)
    }

    @Test(arguments: ["a_tag_from_a_newer_platform", ""])
    func anUnknownTagGetsTheGenericLine(reason: String) throws {
        let content = try Self.content(for: Self.payload(kind: "approval", id: "appr-1", reason: reason))
        #expect(content.body == UntranslatedL10n.notificationApprovalBody)
    }

    @Test
    func aTagThatIsNotAStringIsIgnored() throws {
        let userInfo: [AnyHashable: Any] = ["spiral": ["version": 1, "kind": "approval", "id": "appr-1", "reason": 42]]
        let subject = try #require(SpiralPushContentBuilder.extractSubject(from: userInfo))
        #expect(subject.reason == nil)
        #expect(try Self.content(for: userInfo).body == UntranslatedL10n.notificationApprovalBody)
    }

    @Test
    func aVerificationKeepsItsOwnLine() throws {
        let content = try Self.content(for: Self.payload(kind: "verification", id: "v-1", reason: nil))
        #expect(content.body == UntranslatedL10n.notificationVerificationBody)
        #expect(content.categoryIdentifier == NotificationConstants.Category.verification)
    }

    // MARK: - Helpers

    /// The shape sygnal delivers once it has merged the device's `default_payload`.
    private static func payload(kind: String, id: String, reason: String?) -> [AnyHashable: Any] {
        var spiral: [String: Any] = ["version": 1, "kind": kind, "id": id]
        spiral["reason"] = reason
        return ["spiral": spiral, "aps": ["mutable-content": 1]]
    }

    /// What the NSE does with a Spiral push: read the subject, build the banner.
    private static func content(for userInfo: [AnyHashable: Any]) throws -> UNNotificationContent {
        let base = UNMutableNotificationContent()
        base.userInfo = userInfo
        let subject = try #require(SpiralPushContentBuilder.extractSubject(from: userInfo))
        return try #require(SpiralPushContentBuilder.build(kind: subject.kind,
                                                           subjectID: subject.id,
                                                           baseContent: base,
                                                           reason: subject.reason))
    }
}
