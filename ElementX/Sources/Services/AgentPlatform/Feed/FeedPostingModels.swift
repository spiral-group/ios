//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The write side of the public feed (lane
// I2): what the composer keeps between sessions, the rules and the text limits.
//

import Foundation

/// A post being written, kept on the device until it is posted or discarded.
nonisolated struct FeedDraft: Equatable, Codable {
    var text: String
    /// One per composer session (`POST /feed/posts`): a retry, and a draft
    /// restored after the app was closed mid-post, replay the same create.
    let idempotencyKey: UUID
}

/// The feed rules built into this app (the rules sheet's text). Lane L sets
/// the real date with the legal text; it must equal the server's
/// `FEED_RULES_VERSION`, which `POST /feed/rules/accept` checks.
nonisolated enum FeedRules {
    static let version = "2026-10-27"

    /// The server's current rules are newer than the ones this app shows:
    /// accepting ours would be refused, so the person is asked to update.
    /// Versions are ISO dates, so they compare as strings.
    static func isOutdated(serverVersion: String?) -> Bool {
        guard let serverVersion else { return false }
        return version < serverVersion
    }
}

/// What the composer may offer this person now (`GET /feed/me/standing`).
nonisolated struct FeedStanding: Equatable {
    let rulesVersion: String
    let rulesAccepted: Bool
    /// The daily cap (UTC); `nil` when there is none.
    let postsPerDay: Int?
    let postsToday: Int
    let suspendedUntil: Date?
    /// The comments' daily cap (UTC, lane B3); `nil` when there is none or the server did not say.
    var commentsPerDay: Int?
    /// `nil` when the server did not say (an additive field, lane B3).
    var commentsToday: Int?

    var hasReachedDailyCap: Bool {
        postsPerDay.map { postsToday >= $0 } ?? false
    }

    var hasReachedCommentCap: Bool {
        guard let commentsPerDay, let commentsToday else { return false }
        return commentsToday >= commentsPerDay
    }

    func isSuspended(at now: Date = .now) -> Bool {
        suspendedUntil.map { $0 > now } ?? false
    }
}

/// The text rules of `POST /feed/posts`, measured as the server does.
nonisolated enum FeedPostText {
    /// The server's `MAX_TEXT_CHARS`, counted in Unicode scalars after NFKC.
    static let maximumLength = 5000
    /// The counter shows from here on.
    static let counterThreshold = 4500

    /// The length the server will count: NFKC, line ends unified, trimmed.
    static func length(of text: String) -> Int {
        normalised(text).unicodeScalars.count
    }

    /// Whether the text can be sent: something left after trimming, and not too long.
    static func isPostable(_ text: String) -> Bool {
        let length = length(of: text)
        return length > 0 && length <= maximumLength
    }

    private static func normalised(_ text: String) -> String {
        text.replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")
            .precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
