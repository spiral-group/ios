//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The words of an activity entry, shared by
// the Activity screen and the NSE's engagement pushes (lane I5), so a like
// group reads the same in both: "Taras and 3 others liked your post", a
// comment "Taras: so true". Target-portable (pulled into the NSE).
//

import Foundation

nonisolated enum FeedActivityText {
    /// A like group: the newest liker by name and how many more.
    static func likes(name: String, others: Int) -> String {
        others > 0 ? UntranslatedL10n.screenFeedActivityLikedMany(name, UntranslatedL10n.screenFeedActivityOthers(others)) : UntranslatedL10n.screenFeedActivityLikedOne(name)
    }

    /// A comment or reply: who, and what they wrote, on one line.
    static func quote(name: String, text: String) -> String {
        UntranslatedL10n.screenFeedActivityQuote(name, text)
    }

    /// What a comment is about, for the line under it and a push's subtitle.
    static func context(isReply: Bool) -> String {
        isReply ? UntranslatedL10n.screenFeedActivityReplyContext : UntranslatedL10n.screenFeedActivityCommentContext
    }

    /// A person's name as every feed list shows it: a withheld name is neutral, a missing one the localpart.
    static func name(userID: String, name: String?, isNameWithheld: Bool) -> String {
        if isNameWithheld {
            return UntranslatedL10n.screenFeedAuthorWithheldName
        }
        if let name, !name.isEmpty {
            return name
        }
        let withoutSigil = userID.hasPrefix("@") ? String(userID.dropFirst()) : userID
        return withoutSigil.split(separator: ":", maxSplits: 1).first.map(String.init) ?? userID
    }
}
