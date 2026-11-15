//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082, decisions 255 and 284). The author's bio:
// the MSC4133 profile field `io.spiral.bio`, written from the profile editor
// and shown on the feed's author sheet. The backend reads it from Synapse and
// runs it through `normalise_bio` (`src/domain/feed/post.rs`) at every page;
// the editor applies the same rules before it saves, so what the person types
// is what others see.
//

import Foundation

enum FeedBio {
    /// The backend's `BIO_FIELD`.
    static let fieldName = "io.spiral.bio"
    /// The backend's `MAX_BIO_GRAPHEMES`: user-perceived characters, so an
    /// emoji sequence counts once.
    static let maxLength = 160

    /// The backend's `normalise_bio` without its cut at ``maxLength`` (the
    /// editor refuses a longer bio instead of cutting it): NFKC, every
    /// whitespace character (newlines included) a space, control and format
    /// characters dropped (but the emoji joiner and the tag characters), runs
    /// of spaces one space, trimmed. Empty when nothing is left.
    static func normalised(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.precomposedStringWithCompatibilityMapping.unicodeScalars {
            if scalar.properties.isWhitespace {
                scalars.append(" ")
            } else if !isDropped(scalar) {
                scalars.append(scalar)
            }
        }
        return String(scalars)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// The backend's `is_control() || is_dropped_format(c)`: bidi overrides
    /// and isolates, zero-width spaces and marks, the BOM. U+200D (👩‍💻) and
    /// U+E0020–U+E007F (subdivision flags) stay, because emoji are built from
    /// them.
    private static func isDropped(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control:
            true
        case .format:
            scalar.value != 0x200D && !(0xE0020...0xE007F).contains(scalar.value)
        default:
            false
        }
    }
}
