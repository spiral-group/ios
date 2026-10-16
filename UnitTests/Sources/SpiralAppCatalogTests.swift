//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: what a catalogue link's template id is to this build
// (decisions 96, 111).
//

@testable import ElementX
import Foundation
import Testing

// The suite itself is in SpiralLivePostTests.swift.
extension SpiralAppCatalogTests {
    /// One template this build runs, one for a runtime it predates.
    static let index = """
    {"version":1,"runtime":"1",
     "sections":[{"id":"decide","title":"Вирішити","items":["poll","later"]}],
     "items":[{"id":"poll","title":"Голосування","description":"","aspect":"4:3","source":"poll/app.jsx","manifest":"poll/manifest.json","runtime":"1.1"},
              {"id":"later","title":"Потім","description":"","aspect":"1:1","source":"later/app.jsx","manifest":"later/manifest.json","runtime":"9"}]}
    """

    private func catalogue(index: String? = Self.index) throws -> URL {
        try AppSettings.catalogueFixture(index: index)
    }

    @Test
    func aLinkResolvesAgainstTheCatalogue() async throws {
        let base = try catalogue()

        guard case .template(let poll) = await SpiralAppCatalog.resolve("poll", from: base) else {
            Issue.record("a runnable template resolves to itself")
            return
        }
        #expect(poll.id == "poll")
        #expect(await SpiralAppCatalog.resolve("later", from: base) == .needsNewerApp, "decision 96: update, not gone")
        #expect(await SpiralAppCatalog.resolve("nosuch", from: base) == .unknown)
    }

    @Test
    func anUnreadableCatalogueIsUnavailable() async throws {
        #expect(try await SpiralAppCatalog.resolve("poll", from: catalogue(index: nil)) == .unavailable)
        #expect(try await SpiralAppCatalog.resolve("poll", from: catalogue(index: "{")) == .unavailable)
    }

    /// A catalogue format newer than this build is "update the app", even
    /// when the rest of it no longer decodes as this build's (decision 96).
    @Test
    func aNewerCatalogueFormatAsksForAnUpdate() async throws {
        let newer = #"{"runtime":"2","templates":{"poll":{}}}"#
        #expect(try await SpiralAppCatalog.resolve("poll", from: catalogue(index: newer)) == .needsNewerApp)
        #expect(try await SpiralAppCatalog.load(from: catalogue(index: newer)) == nil, "the carousel shows nothing it can't read")
        #expect(try await SpiralAppCatalog.resolve("poll", from: catalogue(index: #"{"sections":[]}"#)) == .unavailable,
                "no format at all is broken, not newer")
    }

    /// The carousel still lists only what this build runs; what it dropped
    /// is remembered, not shown.
    @Test
    func theRunnableCatalogueRemembersWhatItDropped() throws {
        let catalog = try JSONDecoder().decode(SpiralAppCatalog.self, from: Data(Self.index.utf8)).runnable
        #expect(catalog.items.map(\.id) == ["poll"])
        #expect(catalog.sections.first?.items == ["poll"])
        #expect(catalog.needsNewerBuild == ["later"])
        #expect(catalog.runnable == catalog, "filtering twice keeps what the first pass dropped")
    }
}
