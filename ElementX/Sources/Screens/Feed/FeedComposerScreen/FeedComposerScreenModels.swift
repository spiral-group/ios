//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The text composer (lane I2): one
// idempotency key per composer session, the rules card on `409` (or "Update
// Spiral" when the server's rules are newer than the app's), the daily cap
// from `/feed/me/standing`, and a draft kept on the device until it is posted
// or discarded. Links are allowed from day one (decision 287).
//

import Foundation

enum FeedComposerScreenViewModelAction {
    /// The person posted: the sheet closes and the store sends it, showing it as sending (decision 289).
    case send(text: String, idempotencyKey: UUID)
    case dismiss
}

struct FeedComposerScreenViewState: BindableState {
    /// The person's own profile, above what they write (Brief 0083).
    var ownProfile: UserProfile?
    var isAcceptingRules = false
    /// The last accept of the rules failed; the sheet says so and stays.
    var rulesAcceptFailed = false
    /// `/feed/me/standing`, read when the composer opens; `nil` until then or when it could not be read.
    var standing: FeedStanding?
    /// Raised when the keyboard should come back: the rules have gone and the composer stayed.
    var focusEditorRequest = 0
    var bindings = FeedComposerScreenViewStateBindings()

    var length: Int {
        FeedPostText.length(of: bindings.text)
    }

    var canPost: Bool {
        FeedPostText.isPostable(bindings.text)
    }

    /// What the standing says about posting now: a suspension, or the daily cap reached.
    var standingNotice: String? {
        guard let standing else { return nil }
        if let until = standing.suspendedUntil, standing.isSuspended() {
            return UntranslatedL10n.screenFeedComposerSuspendedNotice(until.formatted(date: .abbreviated, time: .shortened))
        }
        if standing.hasReachedDailyCap, let cap = standing.postsPerDay {
            return UntranslatedL10n.screenFeedComposerDailyCapNotice(cap)
        }
        return nil
    }

    /// Shown near the limit and past it; `nil` well below it.
    var counter: Counter? {
        let length = length
        if length > FeedPostText.maximumLength {
            return .over(length - FeedPostText.maximumLength)
        }
        guard length >= FeedPostText.counterThreshold else { return nil }
        return .remaining(FeedPostText.maximumLength - length)
    }

    enum Counter: Equatable {
        case remaining(Int)
        case over(Int)

        var title: String {
            switch self {
            case .remaining(let count): UntranslatedL10n.screenFeedComposerCharactersLeft(count)
            case .over(let count): UntranslatedL10n.screenFeedComposerCharactersOver(count)
            }
        }
    }
}

struct FeedComposerScreenViewStateBindings {
    var text = ""
    var isPresentingRules = false
    var alertInfo: AlertInfo<FeedComposerScreenAlertType>?
}

enum FeedComposerScreenAlertType: Hashable {
    case confirmCancel
    /// The server's rules are newer than the ones this app shows.
    case updateRequired
    /// The server refused the rules this app shows without naming newer ones.
    case postingPaused
}

enum FeedComposerScreenViewAction {
    case post
    case cancel
    case acceptRules
    case declineRules
    /// The rules sheet has finished closing: an alert waiting on it can show.
    case rulesSheetDismissed
    case textChanged
}
