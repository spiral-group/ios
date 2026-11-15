//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Lane I3 on B4's contract: reports with
// their receipt, the person's notices (the statement of reasons, DSA Art.
// 16–17), as the app owns them. Wire
// strings keep an `.other` case, so a newer value degrades (decision 96).
//

import Foundation

/// What a report is about.
nonisolated enum FeedReportTarget: Equatable, CustomStringConvertible {
    case post(id: String)
    case comment(id: String)
    /// A person: their name, bio or conduct.
    case author(userID: String)

    /// For logs: the kind and a post's or comment's id; never a person's MXID or name.
    var description: String {
        switch self {
        case .post(let id): "post \(id)"
        case .comment(let id): "comment \(id)"
        case .author: "author"
        }
    }
}

/// The rule a report says is broken (Terms § 6), as the server names it.
nonisolated enum FeedReportReason: String, CaseIterable, Identifiable {
    case childSafety = "child_safety"
    case threatToLife = "threat_to_life"
    case privateInformation = "private_information"
    case illegal
    case regulatedGoods = "regulated_goods"
    case sexualContent = "sexual_content"
    case harassment
    case hate
    case violence
    case impersonation
    case spam
    case malware
    case other

    var id: String {
        rawValue
    }

    /// A severe report holds a post or comment at once (D-P11); a person is never held by reports (269).
    var isSevere: Bool {
        switch self {
        case .childSafety, .threatToLife, .privateInformation: true
        default: false
        }
    }
}

/// A report's receipt (Art. 16(4)).
nonisolated struct FeedReportReceipt: Equatable {
    let reportID: String
    /// A moderator decides by then; past it the content is held until they do.
    let deadline: Date
    /// The person had already reported it and that report is still open: this is its receipt.
    let isExisting: Bool
}

/// The rules of a report's free text, as the server measures them.
nonisolated enum FeedReportText {
    static let maximumLength = 1000
    static let counterThreshold = 900

    static func length(of text: String) -> Int {
        FeedPostText.length(of: text)
    }
}

/// A notice: a statement of reasons about the person's content or account,
/// or the receipt and decision of a report they filed.
nonisolated struct FeedNotice: Identifiable, Equatable {
    let id: String
    let kind: FeedNoticeKind
    let createdAt: Date
    var isRead: Bool
    /// The post it is about (or the post a comment is under).
    let postID: String?
    let commentID: String?
    /// The person's own report (reporter notices only).
    let reportID: String?
    let statement: FeedNoticeStatement
}

/// A notice's kind, and a statement's restriction: the same strings.
nonisolated enum FeedNoticeKind: Equatable {
    case held
    case removed
    case restored
    case sensitive
    case suspended
    case unsuspended
    case limited
    case reportReceived
    case reportDecided
    /// A kind newer than this build: a generic "Update Spiral" notice.
    case other(String)

    init(wireValue: String) {
        switch wireValue {
        case "held": self = .held
        case "removed": self = .removed
        case "restored": self = .restored
        case "sensitive": self = .sensitive
        case "suspended": self = .suspended
        case "unsuspended": self = .unsuspended
        case "limited": self = .limited
        case "report_received": self = .reportReceived
        case "report_decided": self = .reportDecided
        default: self = .other(wireValue)
        }
    }

    /// About a report the person filed, not about their content.
    var isAboutAReport: Bool {
        self == .reportReceived || self == .reportDecided
    }
}

/// The statement: for the author the six elements of Art. 17(3), for the
/// reporter the receipt and the outcome (Art. 16(4)–(6)). Never who reported.
/// Every field but `isAutomated` may be absent.
nonisolated struct FeedNoticeStatement: Equatable {
    let restriction: FeedNoticeKind?
    /// A suspension's end.
    let until: Date?
    /// A limiting's new feed tier (decision 270).
    let tier: Int?
    let trigger: FeedNoticeTrigger?
    /// The decision was taken by automated means (Art. 17(3)(c)).
    let isAutomated: Bool
    /// Automated means detected the content (the keyword filter), whoever then
    /// decided (Art. 17(3)(c)). The wire's absent is `false`.
    var isDetectedByAutomatedMeans = false
    /// The rule's stable code, a report reason; its texts come in the person's language.
    let rule: String?
    let ruleTitle: String?
    let ruleExplanation: String?
    /// The moderator's own words, shown after the rule's texts (decision 271).
    let moderatorComment: String?
    let legalGround: String?
    /// Where to appeal: an email address.
    let appealContact: String?
    /// What the person reported (`report_received`).
    let targetKind: FeedNoticeTargetKind?
    let deadline: Date?
    /// What came of the person's report (`report_decided`).
    let outcome: FeedReportOutcome?
}

nonisolated enum FeedNoticeTrigger: Equatable {
    /// Someone's report.
    case report
    /// Several people's reports.
    case reports
    case filter
    case moderator
    /// A report stayed open 24 h: held pending review.
    case sla
    case other(String)

    init(wireValue: String) {
        switch wireValue {
        case "report": self = .report
        case "reports": self = .reports
        case "filter": self = .filter
        case "moderator": self = .moderator
        case "sla": self = .sla
        default: self = .other(wireValue)
        }
    }
}

nonisolated enum FeedNoticeTargetKind: Equatable {
    case post
    case comment
    case author
    case other(String)

    init(wireValue: String) {
        switch wireValue {
        case "post": self = .post
        case "comment": self = .comment
        case "author": self = .author
        default: self = .other(wireValue)
        }
    }
}

nonisolated enum FeedReportOutcome: Equatable {
    case actionTaken
    case noAction
    case targetDeleted
    case other(String)

    init(wireValue: String) {
        switch wireValue {
        case "action_taken": self = .actionTaken
        case "no_action": self = .noAction
        case "target_deleted": self = .targetDeleted
        default: self = .other(wireValue)
        }
    }
}

nonisolated struct FeedNoticePage: Equatable {
    /// Newest first.
    let items: [FeedNotice]
    /// The next (older) page; `nil` at the end.
    let nextCursor: String?
    /// Unread notices in all: the badge.
    let unread: Int
}

/// The app's language, for the texts the server words (`en`, `uk` or `ru`; English otherwise).
nonisolated enum FeedAppLanguage {
    static var current: String? {
        Bundle.main.preferredLocalizations.first
    }
}
