//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). `FeedBio.normalised` against the
// backend's `normalise_bio` tests (`src/domain/feed/post.rs`), so the editor
// saves what the feed shows.
//

@testable import Spiral
import Testing

struct FeedBioTests {
    @Test
    func aBioIsOnePlainLine() {
        #expect(FeedBio.normalised("  Hi,\n\nI am <b>Ann</b>\u{0007} — https://x.y  ") == "Hi, I am <b>Ann</b> — https://x.y")
        #expect(FeedBio.normalised(" \n\t ").isEmpty)
    }

    @Test
    func aBioIsCompatibilityNormalised() {
        // U+FB01 (ﬁ) and fullwidth A fold under NFKC.
        #expect(FeedBio.normalised("\u{FB01}ne \u{FF21}") == "fine A")
    }

    @Test
    func aBioDropsBidiOverridesAndZeroWidthCharacters() {
        // U+202E would show "Ann" + "gpj.exe" as "Ann exe.jpg".
        #expect(FeedBio.normalised("Ann \u{202E}gpj.exe\u{202C} \u{2066}x\u{2069}\u{200B}y\u{FEFF}") == "Ann gpj.exe xy")
        #expect(FeedBio.normalised("\u{202E}\u{200B}").isEmpty)
    }

    @Test
    func emojiSequencesKeepTheirJoinerAndTags() {
        let coder = "\u{1F469}\u{200D}\u{1F4BB}"
        #expect(FeedBio.normalised(coder) == coder)
        #expect(FeedBio.normalised(coder).count == 1)
        let england = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
        #expect(FeedBio.normalised(england) == england)
    }
}
