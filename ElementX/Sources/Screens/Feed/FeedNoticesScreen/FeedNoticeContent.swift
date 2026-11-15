//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). What a notice says, worded once for the
// notices screen and the post's banner (lane I3). To the author: what was
// restricted and until when, what set it off, whether automated means were
// used, the rule and its explanation (decision 271), the moderator's comment,
// the legal ground and where to appeal (DSA Art. 17(3)). To the reporter:
// the receipt and the outcome (Art. 16(4)–(6)). It never names who reported:
// the server does not send it. A kind newer than this build says to update.
// Decision 287: a plain headline and what happened show at once; the reasons
// (what set it off, automated means, the rule, the moderator's comment, the
// legal ground, the appeal) sit under "Why?", all of them still there.
//

import Foundation

struct FeedNoticeContent: Equatable {
    enum Line: Equatable, Hashable {
        case text(String)
        /// The rule's title with what it does not allow.
        case rule(title: String, explanation: String?)
        /// The moderator's own words, headed "Moderator's comment".
        case moderatorComment(String)
        /// Where to appeal: an email address, shown as a link.
        case appeal(String)
    }

    let title: String
    /// What happened, shown under the headline: until when, the new limits, a report's receipt or outcome.
    let summary: [Line]
    /// Why, under "Why?": the statement's other elements (Art. 17(3)), in full.
    let reasons: [Line]
    /// The notice is about a post the person can open from it.
    let postID: String?

    /// Every line, in the statement's order.
    var lines: [Line] {
        summary + reasons
    }

    init(notice: FeedNotice) {
        let statement = notice.statement
        let isComment = notice.commentID != nil

        switch notice.kind {
        case .other:
            title = UntranslatedL10n.screenFeedNoticeUnsupported
            summary = []
            reasons = []
            postID = nil
            return
        case .reportReceived, .reportDecided:
            title = notice.kind == .reportReceived ? UntranslatedL10n.screenFeedNoticeReportReceivedTitle : UntranslatedL10n.screenFeedNoticeReportDecidedTitle
            (summary, reasons) = Self.reporterLines(notice)
            postID = statement.targetKind == .author ? nil : notice.postID
            return
        case .held:
            title = isComment ? UntranslatedL10n.screenFeedNoticeHeldCommentTitle : UntranslatedL10n.screenFeedNoticeHeldPostTitle
        case .removed:
            title = isComment ? UntranslatedL10n.screenFeedNoticeRemovedCommentTitle : UntranslatedL10n.screenFeedNoticeRemovedPostTitle
        case .restored:
            title = isComment ? UntranslatedL10n.screenFeedNoticeRestoredCommentTitle : UntranslatedL10n.screenFeedNoticeRestoredPostTitle
        case .sensitive:
            title = isComment ? UntranslatedL10n.screenFeedNoticeSensitiveCommentTitle : UntranslatedL10n.screenFeedNoticeSensitivePostTitle
        case .suspended:
            title = UntranslatedL10n.screenFeedNoticeSuspendedTitle
        case .unsuspended:
            title = UntranslatedL10n.screenFeedNoticeUnsuspendedTitle
        case .limited:
            title = UntranslatedL10n.screenFeedNoticeLimitedTitle
        }
        (summary, reasons) = Self.authorLines(statement)
        postID = notice.postID
    }

    // MARK: - The author's statement (Art. 17(3))

    static func authorLines(_ statement: FeedNoticeStatement) -> (summary: [Line], reasons: [Line]) {
        var summary: [Line] = []

        if let until = statement.until {
            summary.append(.text(UntranslatedL10n.screenFeedNoticeUntil(until.formatted(date: .abbreviated, time: .shortened))))
        }
        if let tier = statement.tier {
            switch tier {
            case 0: summary.append(.text(UntranslatedL10n.screenFeedNoticeTierNew))
            case 1: summary.append(.text(UntranslatedL10n.screenFeedNoticeTierStandard))
            default: break
            }
        }
        var reasons: [Line] = []
        if let trigger = statement.trigger.flatMap(triggerText) {
            reasons.append(.text(trigger))
        }
        reasons += automatedMeansLines(statement)
        reasons += groundLines(statement)
        return (summary, reasons)
    }

    /// Art. 17(3)(c): whether automated means detected the content, and whether
    /// they decided, both as the server says them (`detected_by_automated_means`, `automated`).
    private static func automatedMeansLines(_ statement: FeedNoticeStatement) -> [Line] {
        let isDetected = statement.isDetectedByAutomatedMeans
        guard isDetected || statement.isAutomated else { return [.text(UntranslatedL10n.screenFeedNoticeByModerator)] }
        return (isDetected ? [.text(UntranslatedL10n.screenFeedNoticeAutomatedDetected)] : [])
            + [.text(statement.isAutomated ? UntranslatedL10n.screenFeedNoticeDecidedAutomatically : UntranslatedL10n.screenFeedNoticeModeratorDecided)]
    }

    private static func triggerText(_ trigger: FeedNoticeTrigger) -> String? {
        switch trigger {
        case .report: UntranslatedL10n.screenFeedNoticeTriggerReport
        case .reports: UntranslatedL10n.screenFeedNoticeTriggerReports
        case .filter: UntranslatedL10n.screenFeedNoticeTriggerFilter
        case .moderator: UntranslatedL10n.screenFeedNoticeTriggerModerator
        case .sla: UntranslatedL10n.screenFeedNoticeTriggerSla
        case .other: nil
        }
    }

    /// The rule, the moderator's comment after it, the legal ground and the appeal.
    private static func groundLines(_ statement: FeedNoticeStatement) -> [Line] {
        var lines: [Line] = []
        if let title = statement.ruleTitle?.nonEmpty {
            lines.append(.rule(title: title, explanation: statement.ruleExplanation?.nonEmpty))
        }
        if let comment = statement.moderatorComment?.nonEmpty {
            lines.append(.moderatorComment(comment))
        }
        if let legalGround = statement.legalGround?.nonEmpty {
            lines.append(.text(UntranslatedL10n.screenFeedNoticeLegalGround(legalGround)))
        }
        if let contact = statement.appealContact?.nonEmpty {
            lines.append(.appeal(contact))
        }
        return lines
    }

    // MARK: - The reporter's notices (Art. 16(4)–(6))

    static func reporterLines(_ notice: FeedNotice) -> (summary: [Line], reasons: [Line]) {
        let statement = notice.statement
        var lines: [Line] = []

        if notice.kind == .reportReceived {
            switch statement.targetKind {
            case .post: lines.append(.text(UntranslatedL10n.screenFeedNoticeReportedPost))
            case .comment: lines.append(.text(UntranslatedL10n.screenFeedNoticeReportedComment))
            case .author: lines.append(.text(UntranslatedL10n.screenFeedNoticeReportedAuthor))
            case .other, .none: break
            }
            if let deadline = statement.deadline {
                lines.append(.text(UntranslatedL10n.screenFeedNoticeDeadline(deadline.formatted(date: .abbreviated, time: .shortened))))
            }
            return (lines, [])
        }

        switch statement.outcome {
        case .actionTaken: lines.append(.text(UntranslatedL10n.screenFeedNoticeOutcomeActionTaken))
        case .noAction: lines.append(.text(UntranslatedL10n.screenFeedNoticeOutcomeNoAction))
        case .targetDeleted: lines.append(.text(UntranslatedL10n.screenFeedNoticeOutcomeTargetDeleted))
        case .other, .none: break
        }
        var reasons: [Line] = []
        if statement.isAutomated {
            reasons.append(.text(UntranslatedL10n.screenFeedNoticeAutomated))
        }
        reasons += groundLines(statement)
        return (lines, reasons)
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
