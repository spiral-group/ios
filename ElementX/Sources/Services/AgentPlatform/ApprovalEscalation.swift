//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM (Brief 0078): why an approval reached its owner, read from the
// platform's `escalation_reason` tag, and the words the card and the push use for it.
// The card used to print the raw tag (`personal_agent_first_contact`); the push said
// "reply to a new contact" for every approval. Shared with the NSE (NSE/target.yml).

import Foundation

nonisolated enum ApprovalEscalation: Equatable {
    /// Someone wrote to the owner's agent for the first time (`personal_agent_first_contact`).
    case firstContact
    /// The agent wants to write to someone first (`cold_outreach_first_contact`).
    case coldOutreach
    /// The agent's rules ask the owner about every reply (`always`).
    case everyReply
    /// The incoming message contains words a rule watches for (`message_contains(a, b)`).
    case keywords(String)
    /// Some other escalation rule matched (`escalation_rule_match`, `any_of`, `all_of`).
    case ruleMatch
    /// The agent asks to block the sender of a message it was answering (`block_sender`, decision 38).
    case blockSender
    /// A tag this build does not know.
    case unknown

    /// - Parameters:
    ///   - reason: `escalation_reason` as the platform writes it — `worker/reply/consent.rs`,
    ///     `worker/outreach_scheduler.rs`, `domain/escalation.rs` (`describe_rule`),
    ///     `domain/services/block_request.rs` and `worker/reply_dispatch_executor.rs`.
    ///   - contextKind: `context_snapshot.kind`, consulted only when the tag is missing or new.
    ///   - hasVisitor: whether `context_snapshot` names a `visitor_mxid` (a first contact has no kind).
    init(reason: String?, contextKind: String?, hasVisitor: Bool) {
        switch reason {
        case "personal_agent_first_contact":
            self = .firstContact
        case "cold_outreach_first_contact":
            self = .coldOutreach
        case "always":
            self = .everyReply
        case "escalation_rule_match", "any_of", "all_of":
            self = .ruleMatch
        case "block_sender":
            self = .blockSender
        case let reason? where reason.hasPrefix(Self.keywordsPrefix) && reason.hasSuffix(")"):
            let words = reason.dropFirst(Self.keywordsPrefix.count).dropLast().trimmingCharacters(in: .whitespaces)
            self = words.isEmpty ? .ruleMatch : .keywords(words)
        default:
            if contextKind == "cold_outreach" {
                self = .coldOutreach
            } else if contextKind == "block_sender" {
                self = .blockSender
            } else if contextKind == nil, hasVisitor {
                self = .firstContact
            } else {
                self = .unknown
            }
        }
    }

    /// The line under "Escalation reason" on the approval card.
    var cardText: String {
        switch self {
        case .firstContact:
            UntranslatedL10n.screenApprovalDetailEscalationFirstContact
        case .coldOutreach:
            UntranslatedL10n.screenApprovalDetailEscalationColdOutreach
        case .everyReply:
            UntranslatedL10n.screenApprovalDetailEscalationEveryReply
        case .keywords(let words):
            UntranslatedL10n.screenApprovalDetailEscalationKeywords(words)
        case .ruleMatch:
            UntranslatedL10n.screenApprovalDetailEscalationRuleMatch
        case .blockSender:
            UntranslatedL10n.screenApprovalDetailEscalationBlockSender
        case .unknown:
            UntranslatedL10n.screenApprovalDetailEscalationUnknown
        }
    }

    /// The approval push's body. A rule match of any kind reads the same on the lock screen.
    var pushBody: String {
        switch self {
        case .firstContact:
            UntranslatedL10n.notificationApprovalBodyFirstContact
        case .coldOutreach:
            UntranslatedL10n.notificationApprovalBodyColdOutreach
        case .everyReply, .keywords, .ruleMatch:
            UntranslatedL10n.notificationApprovalBodyRuleMatch
        case .blockSender:
            UntranslatedL10n.notificationApprovalBodyBlockSender
        case .unknown:
            UntranslatedL10n.notificationApprovalBody
        }
    }

    private static let keywordsPrefix = "message_contains("
}
