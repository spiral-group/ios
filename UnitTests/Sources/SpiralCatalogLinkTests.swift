//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: post catalogue links (decision 111). The grammar is § 2 of
// docs/DESIGNS/post-catalogue-links-2026-10-12.md, shared with the pages and
// the AASA.
//

import Foundation
@testable import Spiral
import Testing

struct SpiralCatalogLinkTests {
    private func parse(_ string: String) throws -> String? {
        try SpiralCatalogLink.parse(#require(URL(string: string)))?.templateID
    }

    @Test
    func buildsBothURLForms() throws {
        let link = try #require(SpiralCatalogLink(templateID: "poll"))
        #expect(link.webURL.absoluteString == "https://spiral.md/catalog/poll")
        #expect(link.schemeURL.absoluteString == "spiral:///catalog/poll")
        #expect(SpiralCatalogLink.parse(link.webURL) == link)
        #expect(SpiralCatalogLink.parse(link.schemeURL) == link)
    }

    @Test(arguments: ["https://spiral.md/catalog/poll",
                      "https://SPIRAL.md/catalog/poll",
                      "spiral:///catalog/poll",
                      "https://spiral.md/catalog/poll/",
                      "spiral:///catalog/poll/",
                      "https://spiral.md/catalog/poll?utm_source=notes",
                      "https://spiral.md/catalog/poll#top"])
    func parsesATemplatesLink(_ string: String) throws {
        #expect(try parse(string) == "poll")
    }

    @Test(arguments: ["countdown-2", "tic-tac-toe", "a", "x1y2"])
    func acceptsEveryIdOfTheGrammar(_ id: String) throws {
        #expect(try parse("https://spiral.md/catalog/\(id)") == id)
    }

    @Test(arguments: [
        "https://spiral.md/catalog", // no id
        "https://spiral.md/catalog/", // the index
        "https://spiral.md/catalog/index.json", // the catalogue's files
        "https://spiral.md/catalog/poll/app.jsx",
        "https://spiral.md/catalog/poll/manifest.json",
        "https://spiral.md/catalog//poll",
        "https://spiral.md/catalog/poll//",
        "https://spiral.md/catalogue/poll",
        "https://spiral.md/c/poll",
        "https://spiral.md/catalog/Poll", // uppercase
        "https://spiral.md/catalog/tic_tac_toe", // underscore
        "https://spiral.md/catalog/-poll",
        "https://spiral.md/catalog/poll-",
        "https://spiral.md/catalog/tic--tac",
        "https://spiral.md/catalog/p%20oll",
        "https://evil.example/catalog/poll", // another host
        "http://spiral.md/catalog/poll", // not https
        "spiral://catalog/poll", // two slashes: `catalog` is the host
        "spiral:catalog/poll"
    ])
    func refusesEverythingElse(_ string: String) throws {
        #expect(try parse(string) == nil)
    }

    @Test
    func anIdIsAtMostSixtyFourCharacters() throws {
        let longest = String(repeating: "a", count: 64)
        #expect(try parse("https://spiral.md/catalog/\(longest)") == longest)
        #expect(try parse("https://spiral.md/catalog/\(longest)a") == nil)
        #expect(SpiralCatalogLink(templateID: "") == nil)
    }
}
