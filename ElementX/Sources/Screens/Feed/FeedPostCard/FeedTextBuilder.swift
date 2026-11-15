//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). A feed post's text with http(s) links
// and nothing else. The chat's `AttributedStringBuilder` turns "@room", MXIDs
// and matrix.to user links into pills, and a pill rendered without a room hits
// `MXLog.failure("Missing room context")` — an assertion in Debug (spike C2).
// Feed text has no room, so it never goes through that builder.
//

import Foundation

nonisolated enum FeedTextBuilder {
    static func attributedString(from text: String) -> AttributedString {
        let attributedString = NSMutableAttributedString(string: text)

        for match in MatrixEntityRegex.linkRegex.matches(in: text) {
            guard let range = Range(match.range, in: text),
                  let scheme = match.url?.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                continue // mailto:, tel: and friends stay plain text.
            }

            // The detector's own URL for "example.org" is http://; give it https as the chat does.
            guard let url = URL(string: String(text[range]).asSanitizedLink) else { continue }
            attributedString.addAttribute(.link, value: url, range: match.range)
        }

        return AttributedString(attributedString)
    }

    /// The links in `text`, in order, for the card's VoiceOver actions.
    static func links(in attributedString: AttributedString) -> [URL] {
        attributedString.runs.compactMap(\.link)
    }
}
