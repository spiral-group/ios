//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM (Brief 0078): the approval card printed the platform's raw
// `escalation_reason` tag. Each tag the platform writes now has its own line, and a tag
// this build does not know gets one generic line.

@testable import ElementX
import Foundation
import Testing

struct SpiralApprovalEscalationTests {
    /// Every tag the platform writes today (`worker/reply/consent.rs`, `worker/outreach_scheduler.rs`,
    /// `domain/escalation.rs` `describe_rule`, `domain/services/block_request.rs`,
    /// `worker/reply_dispatch_executor.rs`).
    @Test(arguments: [
        ("personal_agent_first_contact", ApprovalEscalation.firstContact),
        ("cold_outreach_first_contact", .coldOutreach),
        ("always", .everyReply),
        ("message_contains(invoice, contract)", .keywords("invoice, contract")),
        ("escalation_rule_match", .ruleMatch),
        ("any_of", .ruleMatch),
        ("all_of", .ruleMatch),
        ("message_contains()", .ruleMatch),
        ("block_sender", .blockSender),
        ("something_from_a_newer_platform", .unknown),
        ("", .unknown)
    ])
    func eachTagHasItsMeaning(tag: String, expected: ApprovalEscalation) {
        #expect(ApprovalEscalation(reason: tag, contextKind: nil, hasVisitor: false) == expected)
    }

    @Test
    func theContextDecidesWhenTheTagCannot() {
        #expect(ApprovalEscalation(reason: nil, contextKind: nil, hasVisitor: true) == .firstContact)
        #expect(ApprovalEscalation(reason: "newer_tag", contextKind: "cold_outreach", hasVisitor: false) == .coldOutreach)
        #expect(ApprovalEscalation(reason: nil, contextKind: "block_sender", hasVisitor: false) == .blockSender)
        #expect(ApprovalEscalation(reason: nil, contextKind: "a_newer_kind", hasVisitor: true) == .unknown)
        #expect(ApprovalEscalation(reason: nil, contextKind: nil, hasVisitor: false) == .unknown)
        // A known tag wins over the context.
        #expect(ApprovalEscalation(reason: "always", contextKind: nil, hasVisitor: true) == .everyReply)
    }

    @Test
    func anApprovalReadsItsEscalation() {
        #expect(Self.approval(reason: "personal_agent_first_contact", context: .personalAgentFirstContact(visitorMXID: "@bob:spiral.md")).escalation == .firstContact)
        #expect(Self.approval(reason: "cold_outreach_first_contact", context: .coldOutreach(targetMXID: "@bob:spiral.md", warnings: [])).escalation == .coldOutreach)
        #expect(Self.approval(reason: "escalation_rule_match", context: .generic(senderMXID: nil)).escalation == .ruleMatch)
        #expect(Self.approval(reason: "newer_tag", context: .personalAgentFirstContact(visitorMXID: "@bob:spiral.md")).escalation == .firstContact)
        #expect(Self.approval(reason: "newer_tag", context: .unknown(rawKind: "newer_kind")).escalation == .unknown)
        let blockRequest = ApprovalBlockRequest(targetMXID: "@spam:spiral.md", roomID: "!dm:spiral.md", isDirectMessage: true, reason: "Spam", userMessage: nil)
        #expect(Self.approval(reason: "block_sender", context: .blockSender(blockRequest)).escalation == .blockSender)
        #expect(Self.approval(reason: nil, context: .blockSender(blockRequest)).escalation == .blockSender)
    }

    @Test
    func theCardNeverShowsTheTag() {
        let tags = ["personal_agent_first_contact", "cold_outreach_first_contact", "always",
                    "escalation_rule_match", "any_of", "all_of", "block_sender", "something_from_a_newer_platform"]
        let lines = tags.map { ApprovalEscalation(reason: $0, contextKind: nil, hasVisitor: false).cardText }
        for (tag, line) in zip(tags, lines) {
            #expect(!line.isEmpty, "\(tag)")
            #expect(!line.contains(tag), "\(tag)")
            #expect(!line.contains("_"), "\(tag)")
        }
        // Eight tags, six lines: the three rule-match tags share one.
        #expect(Set(lines).count == 6)
        #expect(lines.last == UntranslatedL10n.screenApprovalDetailEscalationUnknown)
    }

    @Test
    func theWatchedWordsAreNamed() {
        let line = ApprovalEscalation(reason: "message_contains(invoice, contract)", contextKind: nil, hasVisitor: false).cardText
        #expect(line.contains("invoice, contract"))
        #expect(!line.contains("message_contains"))
    }

    // MARK: - Helpers

    private static func approval(reason: String?, context: ApprovalContext) -> ApprovalDetail {
        ApprovalDetail(id: "appr-1",
                       agentID: "agent-1",
                       ownerUserID: "@alice:spiral.md",
                       draftBody: "Hi",
                       targetRoomID: "!room:spiral.md",
                       state: .pending,
                       context: context,
                       createdAt: .now,
                       updatedAt: .now,
                       expiresAt: nil,
                       decidedAt: nil,
                       decidedBy: nil,
                       escalationReason: reason)
    }
}
