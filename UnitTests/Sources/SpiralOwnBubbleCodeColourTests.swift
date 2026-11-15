//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, decision 300a): code on an own blue bubble keeps its dark text only where the code
// background is drawn under it. A `<pre>` inside a quote has none, and dark text read 3.5:1 on the blue.
//

@testable import Spiral
import Compound
import SwiftUI
import Testing

@MainActor
struct SpiralOwnBubbleCodeColourTests {
    private let builder = AttributedStringBuilder(cacheKey: "SpiralOwnBubbleCodeColourTests", mentionBuilder: MentionBuilder())

    @Test
    func codeOnItsOwnBackgroundTurnsDark() throws {
        var string = try #require(builder.fromHTML("<p>Run <code>make</code></p><pre>let total = 12</pre>"))
        string.keepCodeColours()

        #expect(colour(of: "make", in: string) == Self.textPrimary)
        #expect(colour(of: "let total = 12", in: string) == Self.textPrimary)
    }

    @Test
    func aPreInsideAQuoteOrDetailsKeepsTheTextColour() throws {
        var quoted = try #require(builder.fromHTML("<blockquote><pre>let total = 12</pre> and <code>make</code></blockquote>"))
        quoted.keepCodeColours()
        #expect(colour(of: "let total = 12", in: quoted) == nil)
        #expect(colour(of: "make", in: quoted) == Self.textPrimary)

        var details = try #require(builder.fromHTML("<details><summary>Log</summary><pre>exit 1</pre></details>"))
        details.keepCodeColours()
        #expect(colour(of: "exit 1", in: details) == nil)
    }

    private static let textPrimary = UIColor.compound.textPrimary.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))

    private func colour(of text: String, in string: AttributedString) -> UIColor? {
        guard let range = string.range(of: text) else {
            Issue.record("No \"\(text)\" in the message")
            return nil
        }
        return string[range].uiKit.foregroundColor?.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    }
}
