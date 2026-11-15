//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Reporting a post, a comment or a
// person (lane I3, arch § 5.5): a rule from Terms § 6, an optional note for
// the moderator, and the receipt with the date a moderator decides by
// (DSA Art. 16(4)). The author never learns who reported, and never sees
// the note.
//

import Foundation

enum FeedReportScreenViewModelAction {
    case dismiss
}

struct FeedReportScreenViewState: BindableState {
    let target: FeedReportTarget
    var reason: FeedReportReason?
    /// From the tap on Send until the server answers.
    var isSending = false
    /// The server's receipt: the form is done.
    var receipt: FeedReportReceipt?
    var bindings = FeedReportScreenViewStateBindings()

    var title: String {
        switch target {
        case .post: UntranslatedL10n.screenFeedReportPostTitle
        case .comment: UntranslatedL10n.screenFeedReportCommentTitle
        case .author: UntranslatedL10n.screenFeedReportAuthorTitle
        }
    }

    /// The severe rules hold a post or a comment at once; a person is never held by reports (decision 269).
    var severeFooter: String? {
        switch target {
        case .post, .comment: UntranslatedL10n.screenFeedReportSevereFooter
        case .author: nil
        }
    }

    var detailLength: Int {
        FeedReportText.length(of: bindings.detail)
    }

    var canSend: Bool {
        reason != nil && !isSending && receipt == nil && detailLength <= FeedReportText.maximumLength
    }

    /// Shown near the limit and past it.
    var detailCounter: String? {
        let length = detailLength
        if length > FeedReportText.maximumLength {
            return UntranslatedL10n.screenFeedComposerCharactersOver(length - FeedReportText.maximumLength)
        }
        guard length >= FeedReportText.counterThreshold else { return nil }
        return UntranslatedL10n.screenFeedComposerCharactersLeft(FeedReportText.maximumLength - length)
    }
}

struct FeedReportScreenViewStateBindings {
    var detail = ""
    var alertInfo: AlertInfo<FeedReportScreenAlertType>?
}

enum FeedReportScreenAlertType: Hashable {
    /// 10 reports a day: nothing was filed.
    case rateLimited
    /// What was reported is not there for the person any more.
    case notAvailable
    /// Decision 276: suspended from the feed, the person cannot report; nothing was filed.
    case suspended
    case failed
}

enum FeedReportScreenViewAction {
    case selectReason(FeedReportReason)
    case send
    case dismiss
}

extension FeedReportReason {
    var title: String {
        switch self {
        case .childSafety: UntranslatedL10n.screenFeedReportReasonChildSafety
        case .threatToLife: UntranslatedL10n.screenFeedReportReasonThreatToLife
        case .privateInformation: UntranslatedL10n.screenFeedReportReasonPrivateInformation
        case .illegal: UntranslatedL10n.screenFeedReportReasonIllegal
        case .regulatedGoods: UntranslatedL10n.screenFeedReportReasonRegulatedGoods
        case .sexualContent: UntranslatedL10n.screenFeedReportReasonSexualContent
        case .harassment: UntranslatedL10n.screenFeedReportReasonHarassment
        case .hate: UntranslatedL10n.screenFeedReportReasonHate
        case .violence: UntranslatedL10n.screenFeedReportReasonViolence
        case .impersonation: UntranslatedL10n.screenFeedReportReasonImpersonation
        case .spam: UntranslatedL10n.screenFeedReportReasonSpam
        case .malware: UntranslatedL10n.screenFeedReportReasonMalware
        case .other: UntranslatedL10n.screenFeedReportReasonOther
        }
    }

    /// One line under the title where the title alone is not enough.
    var subtitle: String? {
        switch self {
        case .childSafety: UntranslatedL10n.screenFeedReportReasonChildSafetyDescription
        case .threatToLife: UntranslatedL10n.screenFeedReportReasonThreatToLifeDescription
        case .privateInformation: UntranslatedL10n.screenFeedReportReasonPrivateInformationDescription
        default: nil
        }
    }

    static var severe: [FeedReportReason] {
        allCases.filter(\.isSevere)
    }

    static var others: [FeedReportReason] {
        allCases.filter { !$0.isSevere }
    }
}
