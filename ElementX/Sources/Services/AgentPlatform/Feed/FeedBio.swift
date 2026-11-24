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
    /// editor stops at it, ``limited(_:editing:)``): NFKC, every
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

    /// What an edit from `old` to `new` keeps within ``maxLength`` (1.0.3 B11,
    /// operator 2026-11-18): what was typed or pasted is cut on a character
    /// boundary, so typing at the limit adds nothing and a paste keeps what
    /// fits, wherever the caret was. Should the rest be over the limit already
    /// (a stored bio longer than it), the whole is cut from its end.
    static func limited(_ new: String, editing old: String) -> String {
        guard !fits(new) else { return new }
        
        let oldCharacters = Array(old)
        let newCharacters = Array(new)
        let shared = min(oldCharacters.count, newCharacters.count)
        var headCount = 0
        while headCount < shared, oldCharacters[headCount] == newCharacters[headCount] {
            headCount += 1
        }
        var tailCount = 0
        while tailCount < shared - headCount,
              oldCharacters[oldCharacters.count - 1 - tailCount] == newCharacters[newCharacters.count - 1 - tailCount] {
            tailCount += 1
        }
        
        let head = String(newCharacters[..<headCount])
        let tail = String(newCharacters[(newCharacters.count - tailCount)...])
        let inserted = longestPrefix(of: newCharacters[headCount..<(newCharacters.count - tailCount)]) { head + String($0) + tail }
        let edited = head + String(inserted) + tail
        return fits(edited) ? edited : String(longestPrefix(of: newCharacters[...]) { String($0) })
    }
    
    private static func fits(_ raw: String) -> Bool {
        normalised(raw).count <= maxLength
    }
    
    /// By bisection: a longer prefix never counts fewer characters once normalised.
    private static func longestPrefix(of characters: ArraySlice<Character>,
                                      fittingAs text: (ArraySlice<Character>) -> String) -> ArraySlice<Character> {
        var low = 0
        var high = characters.count
        while low < high {
            let middle = (low + high + 1) / 2
            if fits(text(characters.prefix(middle))) {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return characters.prefix(low)
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
