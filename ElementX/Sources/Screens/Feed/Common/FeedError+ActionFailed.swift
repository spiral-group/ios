//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). What an action the server refused tells
// the person (a post's unhide or comment switch, a report): what refused it,
// and the connection only when nothing answered.
//

extension FeedError {
    var actionFailedMessage: String {
        switch self {
        case .transport:
            UntranslatedL10n.screenFeedActionFailedMessage
        case .unavailable:
            UntranslatedL10n.screenFeedActionFailedUnavailableMessage
        case .rateLimited, .temporarilyUnavailable:
            UntranslatedL10n.screenFeedActionFailedTryShortlyMessage
        case .forbidden:
            // Synapse does not show the account (locked or suspended there).
            UntranslatedL10n.screenFeedActionFailedAccountRestrictedMessage
        default:
            UntranslatedL10n.screenFeedActionFailedServerMessage
        }
    }
}
