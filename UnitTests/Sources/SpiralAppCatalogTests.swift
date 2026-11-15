//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: what a catalogue link's template id is to this build
// (decisions 96, 111).
//

import Foundation
@testable import Spiral
import Testing
import UIKit

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

    /// A template compiled at `catalog:pack` is previewed and published as
    /// the compiled module, and a thread with the agent starts from its source
    /// (question 374). One packed before has only its source, for both.
    @Test
    func aCompiledTemplateIsPublishedCompiledAndEditedAsSource() async throws {
        let base = try catalogue(index: """
        {"version":1,"runtime":"1","sections":[{"id":"s","title":"S","items":["new","old"]}],
         "items":[{"id":"new","title":"N","description":"","aspect":"1:1","source":"new/app.jsx","module":"new/app.js","manifest":"new/manifest.json","stills":{"uk":"new/still.uk.jpg","ru":"new/still.ru.jpg","en":"new/still.en.jpg"}},
                  {"id":"old","title":"O","description":"","aspect":"1:1","source":"old/app.jsx","manifest":"old/manifest.json"}]}
        """)
        let files = [
            "new/app.jsx": "export default () => <p>new</p>;",
            "new/app.js": #"import { jsx as _jsx } from "react/jsx-runtime"; export default () => _jsx("p", { children: "new" });"#,
            "new/manifest.json": #"{"app_id":"tpl-new","runtime":"1","entry":"app.js","aspect":"1:1","state_channel":"matrix","capabilities":[]}"#,
            "old/app.jsx": "export default () => <p>old</p>;",
            "old/manifest.json": #"{"app_id":"tpl-old","runtime":"1","entry":"app.jsx","aspect":"1:1","state_channel":"matrix","capabilities":[]}"#
        ]
        for (path, text) in files {
            try FileManager.default.createDirectory(at: base.appending(path: path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: base.appending(path: path), atomically: true, encoding: .utf8)
        }
        let catalog = try #require(await SpiralAppCatalog.load(from: base))
        let new = try #require(catalog.template("new"))
        let old = try #require(catalog.template("old"))
        #expect(new.stills == ["uk": "new/still.uk.jpg", "ru": "new/still.ru.jpg", "en": "new/still.en.jpg"])
        #expect(old.stills == nil)

        let compiled = try #require(await SpiralAppCatalog.artifact(of: new, from: base))
        #expect(compiled.manifest.isCompiled)
        #expect(String(decoding: compiled.source, as: UTF8.self) == files["new/app.js"])
        #expect(await SpiralAppCatalog.source(of: new, from: base) == files["new/app.jsx"], "the agent is handed source")

        let source = try #require(await SpiralAppCatalog.artifact(of: old, from: base))
        #expect(!source.manifest.isCompiled)
        #expect(String(decoding: source.source, as: UTF8.self) == files["old/app.jsx"])
    }

    /// `index.json` describes each module and each language's still by its
    /// SHA-256: the one it describes is published and shown, a stale one is not.
    @Test
    func aModuleOrStillTheIndexDoesNotDescribeIsRefused() async throws {
        let module = #"import { jsx as _jsx } from "react/jsx-runtime"; export default () => _jsx("p", { children: "new" });"#
        let still = Self.picture(.white)
        let moduleDigest = SpiralAppArtifact.digest(of: Data(module.utf8))
        let stillDigest = SpiralAppArtifact.digest(of: still)
        let stills = { (id: String) in #"{"uk":"\#(id)/still.uk.jpg","ru":"\#(id)/still.ru.jpg","en":"\#(id)/still.en.jpg"}"# }
        let digests = #"{"module":"\#(moduleDigest)","stills":{"uk":"\#(stillDigest)","ru":"\#(stillDigest)","en":"\#(stillDigest)"}}"#
        let base = try catalogue(index: """
        {"version":1,"runtime":"1","sections":[{"id":"s","title":"S","items":["good","stale"]}],
         "items":[{"id":"good","title":"G","description":"","aspect":"1:1","source":"good/app.jsx","module":"good/app.js","manifest":"m.json","stills":\(stills("good")),"sha256":\(digests)},
                  {"id":"stale","title":"S","description":"","aspect":"1:1","source":"stale/app.jsx","module":"stale/app.js","manifest":"m.json","stills":\(stills("stale")),"sha256":\(digests)}]}
        """)
        try Self.write([
            "good/app.js": Data(module.utf8),
            "good/still.uk.jpg": still,
            "good/still.ru.jpg": still,
            // Only the English reader's file is stale here: each language is checked against its own digest.
            "good/still.en.jpg": Self.picture(.black),
            "stale/app.js": Data(module.replacingOccurrences(of: "new", with: "old").utf8),
            "stale/still.uk.jpg": Self.picture(.black),
            "stale/still.ru.jpg": Self.picture(.black),
            "stale/still.en.jpg": Self.picture(.black),
            "m.json": Data(#"{"app_id":"tpl-x","runtime":"1","entry":"app.js","aspect":"1:1","state_channel":"matrix","capabilities":[]}"#.utf8)
        ], to: base)
        let catalog = try #require(await SpiralAppCatalog.load(from: base))
        let good = try #require(catalog.template("good"))
        let stale = try #require(catalog.template("stale"))
        #expect(good.sha256 == .init(module: moduleDigest, stills: ["uk": stillDigest, "ru": stillDigest, "en": stillDigest]))

        #expect(await SpiralAppCatalog.artifact(of: good, from: base) != nil)
        #expect(await SpiralAppCatalog.artifact(of: stale, from: base) == nil, "a stale module is never published")
        #expect(await InteractivePostCatalogScreenViewModel.still(of: good, from: base, languages: ["uk"]) != nil)
        #expect(await InteractivePostCatalogScreenViewModel.still(of: good, from: base, languages: ["ru"]) != nil)
        #expect(await InteractivePostCatalogScreenViewModel.still(of: good, from: base, languages: ["en"]) == nil,
                "the chosen language's stale still is not shown")
        #expect(await InteractivePostCatalogScreenViewModel.still(of: stale, from: base, languages: ["uk"]) == nil, "a stale still is not shown")
    }

    /// A still in the app's language (question 412): uk for uk, ru for ru,
    /// English for every other language, as the titles are chosen.
    @Test
    func theStillSpeaksTheAppsLanguage() throws {
        let template = try Self.template(stills: #"{"uk":"t/still.uk.jpg","ru":"t/still.ru.jpg","en":"t/still.en.jpg"}"#,
                                         digests: #"{"stills":{"uk":"aa","ru":"bb","en":"cc"}}"#)

        #expect(template.still(for: ["uk"]) == .init(path: "t/still.uk.jpg", sha256: "aa"))
        #expect(template.still(for: ["uk-UA"]) == .init(path: "t/still.uk.jpg", sha256: "aa"))
        #expect(template.still(for: ["ru"]) == .init(path: "t/still.ru.jpg", sha256: "bb"))
        #expect(template.still(for: ["en"]) == .init(path: "t/still.en.jpg", sha256: "cc"))
        #expect(template.still(for: ["de"]) == .init(path: "t/still.en.jpg", sha256: "cc"), "any other language is English")
        #expect(template.still(for: []) == .init(path: "t/still.en.jpg", sha256: "cc"))
        #expect(template.still(for: ["de", "ru"]) == .init(path: "t/still.ru.jpg", sha256: "bb"), "as a title: the first the catalogue draws")

        defer { Bundle.overrideLocalizations = nil }
        Bundle.overrideLocalizations = ["ru"]
        #expect(template.still() == .init(path: "t/still.ru.jpg", sha256: "bb"), "the app's language by default")
    }

    /// A still missing in the wanted language is the English one, and without
    /// English whichever there is; no stills at all is a card without a
    /// picture, and a language without a digest is fetched unchecked, as a
    /// still was before digests (decision 96).
    @Test
    func aMissingStillFallsBackToEnglishThenAnyOther() async throws {
        let noRussian = try Self.template(stills: #"{"uk":"t/still.uk.jpg","en":"t/still.en.jpg"}"#, digests: #"{"stills":{"en":"cc"}}"#)
        #expect(noRussian.still(for: ["ru"]) == .init(path: "t/still.en.jpg", sha256: "cc"))
        #expect(noRussian.still(for: ["uk"]) == .init(path: "t/still.uk.jpg", sha256: nil))

        let ukrainianOnly = try Self.template(stills: #"{"uk":"t/still.uk.jpg"}"#)
        #expect(ukrainianOnly.still(for: ["ru"]) == .init(path: "t/still.uk.jpg", sha256: nil))
        #expect(ukrainianOnly.still(for: ["de"]) == .init(path: "t/still.uk.jpg", sha256: nil))

        let futureOnly = try Self.template(stills: #"{"ru":"t/still.ru.jpg","pl":"t/still.pl.jpg"}"#)
        #expect(futureOnly.still(for: ["de"]) == .init(path: "t/still.pl.jpg", sha256: nil), "without English, the first by code")

        #expect(try Self.template(stills: nil).still(for: ["uk"]) == nil, "no stills, no picture")
        #expect(try Self.template(stills: "{}").still(for: ["uk"]) == nil)

        let base = try catalogue(index: nil)
        let none = try Self.template(stills: nil)
        #expect(await InteractivePostCatalogScreenViewModel.still(of: none, from: base, languages: ["uk"]) == nil)
        try Self.write(["t/still.uk.jpg": Self.picture(.white)], to: base)
        #expect(await InteractivePostCatalogScreenViewModel.still(of: ukrainianOnly, from: base, languages: ["en"]) != nil,
                "a fallback still is fetched and shown")
    }

    /// The single `still` of a catalogue before question 412 is not read (decision 95).
    @Test
    func theSingleStillIsNotRead() throws {
        let template = try Self.template(stills: nil, extra: #","still":"t/still.jpg""#, digests: #"{"still":"aa"}"#)
        #expect(template.stills == nil)
        #expect(template.sha256?.stills == nil)
        #expect(template.still(for: ["en"]) == nil)
    }

    private static func template(stills: String?, extra: String = "", digests: String? = nil) throws -> SpiralAppTemplate {
        let json = #"{"id":"t","title":"T","description":"","aspect":"1:1","source":"t/app.jsx","manifest":"t/manifest.json""#
            + (stills.map { #","stills":"# + $0 } ?? "") + extra + (digests.map { #","sha256":"# + $0 } ?? "") + "}"
        return try JSONDecoder().decode(SpiralAppTemplate.self, from: Data(json.utf8))
    }

    private static func picture(_ colour: UIColor) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            colour.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    private static func write(_ files: [String: Data], to base: URL) throws {
        for (path, data) in files {
            try FileManager.default.createDirectory(at: base.appending(path: path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: base.appending(path: path))
        }
    }

    /// A catalogue file the server answers with an error is not the file:
    /// a 404 page is never published as a template's module.
    @Test
    func anHTTPErrorIsNotTheFile() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogueURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let base = try #require(URL(string: "https://catalogue.test/catalog"))

        #expect(await SpiralAppCatalog.data(at: "dice/app.js", from: base, session: session) == nil)
        #expect(await SpiralAppCatalog.data(at: "dice/manifest.json", from: base, session: session) == Data("{}".utf8))

        let url = base.appending(path: "dice/app.js")
        let page = Data("<h1>Not Found</h1>".utf8)
        for status in [404, 500, 301] {
            let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil))
            #expect(SpiralAppCatalog.body(page, response, path: "dice/app.js") == nil, "HTTP \(status)")
        }
        let ok = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil))
        #expect(SpiralAppCatalog.body(page, ok, path: "dice/app.js") == page)
        let file = URLResponse(url: URL(filePath: "/tmp/app.js"), mimeType: nil, expectedContentLength: 4, textEncodingName: nil)
        #expect(SpiralAppCatalog.body(page, file, path: "dice/app.js") == page, "a file has no status")
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

    // MARK: Question 412: what is new, who a template is for, how it plays

    private static func decode(_ json: String) throws -> SpiralAppCatalog {
        try JSONDecoder().decode(SpiralAppCatalog.self, from: Data(json.utf8))
    }

    private static func item(_ id: String, _ extra: String = "") -> String {
        #"{"id":"\#(id)","title":"\#(id)","description":"","aspect":"1:1","source":"\#(id)/app.jsx","manifest":"\#(id)/manifest.json"\#(extra)}"#
    }

    private static func index(new: String? = nil, items: [String]) -> String {
        #"{"version":1,"runtime":"1","sections":[{"id":"two","title":"Вдвох","items":["rps","dice"]}],"items":[\#(items.joined(separator: ","))]\#(new.map { #","new":\#($0)"# } ?? "")}"#
    }

    @Test
    func theFactsAndWhatIsNewDecode() throws {
        let catalog = try Self.decode(Self.index(new: #"["rps","dice"]"#,
                                                 items: [Self.item("rps", #","players":"2","traits":["sealed","score"]"#),
                                                         Self.item("dice", #","players":"2+","traits":["sameForAll"]"#)]))
        #expect(catalog.newIDs == ["rps", "dice"], "in the catalogue's order: the first is the «New» card")
        #expect(catalog.template("rps")?.players == .two)
        #expect(catalog.template("rps")?.traits == [.sealed, .score])
        #expect(catalog.template("dice")?.players == .group)
        #expect(catalog.runnable.newIDs == ["rps", "dice"])
    }

    /// The catalogue on staging and prod today: none of the three keys.
    @Test
    func aCatalogueWithoutTheFactsDecodesAsBefore() throws {
        let catalog = try Self.decode(Self.index(items: [Self.item("rps"), Self.item("dice")]))
        #expect(catalog.items.count == 2)
        #expect(catalog.newIDs.isEmpty)
        #expect(catalog.template("rps")?.players == nil)
        #expect(catalog.template("rps")?.traits == [])
    }

    /// Decision 96: a value from a newer catalogue is skipped, never a broken catalogue.
    @Test
    func anUnknownTraitOrPlayersValueIsSkipped() throws {
        let catalog = try Self.decode(Self.index(items: [Self.item("rps", #","players":"3+","traits":["teleport","sealed",7,{"x":1},"score"]"#),
                                                         Self.item("dice", #","players":2,"traits":"sealed""#)]))
        #expect(catalog.items.count == 2, "a strange fact never drops a template")
        #expect(catalog.template("rps")?.players == nil)
        #expect(catalog.template("rps")?.traits == [.sealed, .score], "the ones this build knows, in order")
        #expect(catalog.template("dice")?.players == nil)
        #expect(catalog.template("dice")?.traits == [])
    }

    @Test
    func aNewIDWithNoTemplateIsLeftOut() throws {
        let catalog = try Self.decode(Self.index(new: #"["gone","dice","dice",3]"#, items: [Self.item("rps"), Self.item("dice")]))
        #expect(catalog.newIDs == ["dice"], "an id that is no template, a repeat and a non-string go")
        #expect(try Self.decode(Self.index(new: #""dice""#, items: [Self.item("dice")])).newIDs.isEmpty, "not a list: nothing new")
        #expect(try Self.decode(Self.index(new: "null", items: [Self.item("dice")])).newIDs.isEmpty)
    }

    /// A new template this build can't run leaves the list with it.
    @Test
    func aNewTemplateForANewerRuntimeIsNotNew() throws {
        let catalog = try Self.decode(Self.index(new: #"["rps","dice"]"#, items: [Self.item("rps", #","runtime":"9""#), Self.item("dice")])).runnable
        #expect(catalog.newIDs == ["dice"])
    }

    /// The values `catalog-facts.mjs` (spiral-app-shell) packs, by hand: a
    /// value the pack gains and this build lacks would be skipped silently.
    @Test
    func theAppKnowsEveryValueThePackWrites() {
        #expect(Set(SpiralAppTemplate.Players.allCases.map(\.rawValue)) == ["1", "2", "2+"])
        #expect(Set(SpiralAppTemplate.Trait.allCases.map(\.rawValue)) == ["sealed", "secret", "turns", "live", "sameForAll",
                                                                          "score", "names", "agentFills", "shown", "together"])
    }
}

/// A catalogue server that has `manifest.json` files and nothing else.
private nonisolated final class CatalogueURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let found = url.lastPathComponent == "manifest.json"
        guard let response = HTTPURLResponse(url: url, statusCode: found ? 200 : 404, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((found ? "{}" : "<h1>Not Found</h1>").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }
}

// AGENT-PLATFORM (412): a catalogue template's post is titled in the reader's language.
extension SpiralAppCatalogTests {
    /// A uk phone publishes the tug of war: the post stores «Перетягування каната». An en reader whose app has read the
    /// catalogue sees the template's en title; a post the catalogue doesn't know keeps the title it stored.
    @Test
    func aTemplatesPostIsTitledInTheReadersLanguage() throws {
        let suite = "SpiralAppTemplateTitlesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let index = """
        {"runtime":"1","sections":[{"id":"play","title":"Грати","items":["tug-of-war"]}],
         "items":[{"id":"tug-of-war","title":"Перетягування каната","titles":{"en":"Tug of war","ru":"Перетягивание каната"},
                   "description":"","aspect":"1:1","source":"tug-of-war/app.jsx","manifest":"tug-of-war/manifest.json"}]}
        """
        let catalog = try JSONDecoder().decode(SpiralAppCatalog.self, from: Data(index.utf8))
        let titles = SpiralAppTemplateTitles(defaults: defaults)
        #expect(titles.title(forAppID: "tpl-tug-of-war", languages: ["en"]) == nil, "nothing kept yet: the stored title stands")

        titles.store(catalog)

        #expect(titles.title(forAppID: "tpl-tug-of-war", languages: ["en-US"]) == "Tug of war")
        #expect(titles.title(forAppID: "tpl-tug-of-war", languages: ["uk"]) == "Перетягування каната")
        #expect(titles.title(forAppID: "tpl-tug-of-war", languages: ["de"]) == "Tug of war", "another language reads English, as the catalogue does")
        #expect(titles.title(forAppID: "tpl-nosuch", languages: ["en"]) == nil, "a template the catalogue doesn't list keeps its stored title")
        #expect(titles.title(forAppID: "a1b2c3", languages: ["en"]) == nil, "an agent's own post isn't a template")

        let relaunched = SpiralAppTemplateTitles(defaults: defaults)
        #expect(relaunched.title(forAppID: "tpl-tug-of-war", languages: ["en"]) == "Tug of war", "kept across launches")
    }
}
