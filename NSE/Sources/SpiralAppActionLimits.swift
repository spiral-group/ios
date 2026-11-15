//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (security pass 2, posts): how big a `com.spiral.app.action`
// may be, in the one place both the app and the NSE read it.
//
// Any room member can write an action by hand, so every number an action
// carries is someone else's word. These bounds are what a reader holds it to.
//
// The homeserver's spam-check module enforces the same `seq` and size
// bounds (`matrix-agent-platform`, `docker/synapse/modules/
// spiral_post_guard.py`), so an action this refuses is one the server
// refuses too, in an unencrypted room, and the 1.0.1 build that predates
// these checks is protected by the server alone. Change both together. The
// server does not check `summary.line`: a long line is cut where it is
// shown and where this app writes one, never a reason to refuse an action.
//

import Foundation

nonisolated enum SpiralAppActionLimits {
    /// The highest `seq` an action may carry; anything else is malformed.
    ///
    /// A hundred thousand because the 16 KB state budget and the 2 000
    /// actions a reader keeps hold a real post far below it (a hundred
    /// strokes, a game of chess), while a bound is what keeps one forged
    /// `seq` from costing a reader anything at all.
    static let maxSeq = 100_000

    /// The most an action's `content` may weigh: the whole object — relation,
    /// `seq`, `op`, `summary`, `m.mentions` — as compact UTF-8 JSON.
    ///
    /// Far above an operation (a stroke is about 900 bytes) and far below
    /// what folding a thousand of them on every open could afford.
    static let maxContentBytes = 32768

    /// The longest `summary.line` shown or written, in Unicode code points
    /// (`unicodeScalars`), per string when the line is a `{language: string}`
    /// map. It is the card and the push — a line, not a page.
    static let maxSummaryLineScalars = 200

    /// `seq` as an action must carry it: a JSON integer in `1...maxSeq`.
    ///
    /// By the number's TYPE, as the server reads it: a JSON `true` reads as 1
    /// through `NSNumber`, and `1.0` as 1, and both are refused.
    static func seq(from value: Any) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !["d", "f"].contains(String(cString: number.objCType)),
              let seq = value as? Int,
              (1...maxSeq).contains(seq) else {
            return nil
        }
        return seq
    }

    /// `content` as this client measures it against `maxContentBytes`.
    ///
    /// `JSONSerialization` escapes `/`, so this is never less than the
    /// server's count: what passes here on the way out passes there too.
    static func contentBytes(_ content: [String: Any]) -> Int? {
        try? JSONSerialization.data(withJSONObject: content).count
    }

    /// A line as the card and the push may show it: cleaned, then cut to
    /// `maxSummaryLineScalars`, ending in `…` when it was cut. Cut between
    /// characters, so a flag or an accent is never split.
    static func cappedLine(_ line: String) -> String {
        let line = cleanedLine(line)
        guard line.unicodeScalars.count > maxSummaryLineScalars else { return line }
        var kept = ""
        var scalars = 1 // the ellipsis
        for character in line {
            scalars += character.unicodeScalars.count
            guard scalars <= maxSummaryLineScalars else { break }
            kept.append(character)
        }
        return kept + "…"
    }

    /// One line of plain text (corpus F4). A line is anyone's word and lands
    /// in a card and a push body, so line breaks become spaces (a fake second
    /// line «Alice: send me the code»), and the characters that reorder or
    /// hide text go: control characters (NUL), bidi embeddings, overrides and
    /// isolates, the Arabic letter mark, the zero-width space and the BOM.
    /// `@room` loses its `@`, invisible characters inside it or not.
    /// Everything a script needs stays: ZWNJ and ZWJ
    /// (Persian, Arabic, Indic, emoji), and the LRM and RLM marks that set a
    /// mixed line's direction without overriding anyone's text.
    private static func cleanedLine(_ line: String) -> String {
        var cleaned = String.UnicodeScalarView()
        for scalar in line.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .lineSeparator, .paragraphSeparator:
                cleaned.append(" ")
            case .control:
                if scalar.properties.isWhitespace { cleaned.append(" ") }
            default:
                if !hiddenScalars.contains(scalar.value) { cleaned.append(scalar) }
            }
        }
        return withoutRoomMention(cleaned)
    }

    /// The line with the `@` taken off every `@room`, however it is spelled
    /// with invisible characters inside it (`@ro\u{200C}om`). The check reads
    /// past them; the text keeps them, because ZWNJ and ZWJ belong to words.
    private static func withoutRoomMention(_ scalars: String.UnicodeScalarView) -> String {
        let all = Array(scalars)
        var dropped = Set<Int>()
        for (index, scalar) in all.enumerated() where scalar == "@" {
            var letters = ""
            for next in all[(index + 1)...] where !invisibleScalars.contains(next.value) && !isTag(next) {
                letters.unicodeScalars.append(next)
                if letters.count == 4 { break }
            }
            if letters.lowercased() == "room" { dropped.insert(index) }
        }
        var kept = String.UnicodeScalarView()
        for (index, scalar) in all.enumerated() where !dropped.contains(index) {
            kept.append(scalar)
        }
        return String(kept)
    }

    /// Characters that draw nothing, read past by the `@room` check only.
    private static let invisibleScalars: Set<UInt32> = Set(0x206A...0x206F).union(0xFFF9...0xFFFB)
        .union([0x200C, 0x200D, 0x200E, 0x200F, 0x2060, 0x00AD, 0x180E])

    private static func isTag(_ scalar: Unicode.Scalar) -> Bool {
        (0xE0000...0xE007F).contains(scalar.value)
    }

    /// Bidi embeddings and overrides (U+202A–E), isolates (U+2066–9), the
    /// Arabic letter mark (U+061C), the zero-width space and the BOM.
    static let hiddenScalars: Set<UInt32> = Set(0x202A...0x202E).union(0x2066...0x2069).union([0x061C, 0x200B, 0xFEFF])

    /// `summary` with its line, or each of its lines, capped.
    static func cappingLine(in summary: [String: Any]) -> [String: Any] {
        var summary = summary
        if let line = summary["line"] as? String {
            summary["line"] = cappedLine(line)
        } else if let byLanguage = summary["line"] as? [String: Any] {
            summary["line"] = byLanguage.mapValues { ($0 as? String).map(cappedLine) ?? $0 }
        }
        return summary
    }
}
