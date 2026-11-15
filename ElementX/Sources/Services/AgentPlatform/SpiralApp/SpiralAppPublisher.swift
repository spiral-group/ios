//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, § 5.56): putting a post into a room, from
// whatever it came from — a draft the agent wrote, or a catalogue template.
//
// The bytes are encrypted with a fresh attachment key and uploaded; the post
// carries the `EncryptedFile`, which is what lets it be forwarded into any
// room — receivers decrypt with the key IN the event, not the room's. It goes
// out raw, for its event id: a generation thread is told which post it now
// edits, and a timeline send does not say.
//

import Foundation
import MatrixRustSDK
import Synchronization

/// How the post's content goes out, when the caller wants a say (§ 5.87:
/// asking the user when encryption refuses a verified user's devices). The
/// upload is done by then and is not repeated.
typealias RawSend = (String) async -> Result<String, RoomProxyError>

enum SpiralAppPublishError: Error {
    case upload
    case content
    case send(RoomProxyError)
}

enum SpiralAppPublisher {
    /// Publish packed bytes as a post in `room`; the new event's id.
    static func publish(packed: Data,
                        sha256: String,
                        appID: String,
                        runtime: String,
                        title: String,
                        aspect: String,
                        into room: JoinedRoomProxyProtocol,
                        clientProxy: ClientProxyProtocol,
                        send: RawSend? = nil) async -> Result<String, SpiralAppPublishError> {
        guard case .success(let upload) = await clientProxy.uploadEncryptedMedia(packed) else {
            return .failure(.upload)
        }
        let post = InteractivePostContent(body: title,
                                          appId: appID,
                                          runtime: runtime,
                                          title: title,
                                          aspect: aspect,
                                          stateChannel: "matrix",
                                          sha256: sha256,
                                          url: nil,
                                          fileJson: upload.fileJson)
        guard let raw = rawPostContent(post) else { return .failure(.content) }
        let send = send ?? { await room.sendSpiralRawEventReturningEventID(type: "m.room.message", content: $0) }
        switch await send(raw) {
        case .success(let eventID):
            return .success(eventID)
        case .failure(let error):
            return .failure(.send(error))
        }
    }

    /// Pack a template's manifest TEXT and source and publish them — the
    /// digest is the client's own here, as there is no agent to claim one.
    static func publish(template manifestJSON: String,
                        source: String,
                        title: String,
                        into room: JoinedRoomProxyProtocol,
                        clientProxy: ClientProxyProtocol,
                        send: RawSend? = nil) async -> Result<String, SpiralAppPublishError> {
        guard let manifest = SpiralAppManifest(json: Data(manifestJSON.utf8)) else { return .failure(.content) }
        let packed = SpiralAppContainer.pack(manifestJSON: manifestJSON, entry: manifest.entry, source: source)
        return await publish(packed: packed,
                             sha256: SpiralAppArtifact.digest(of: packed),
                             appID: manifest.appID,
                             runtime: manifest.runtime,
                             title: title,
                             aspect: manifest.aspect,
                             into: room,
                             clientProxy: clientProxy,
                             send: send)
    }

    /// A post's content as JSON — the same fields, in the same shape, as
    /// `InteractivePostContent` becomes in the SDK (`ruma.rs`), plus
    /// `msgtype` and `body`.
    nonisolated static func rawPostContent(_ post: InteractivePostContent) -> String? {
        var content: [String: Any] = ["msgtype": SpiralAppPost.msgtype,
                                      "body": post.body,
                                      "app_id": post.appId,
                                      "runtime": post.runtime,
                                      "title": post.title,
                                      "aspect": post.aspect,
                                      "state_channel": post.stateChannel,
                                      "sha256": post.sha256]
        if let url = post.url {
            content["url"] = url
        }
        if let fileJSON = post.fileJson {
            guard let file = try? JSONSerialization.jsonObject(with: Data(fileJSON.utf8)) else { return nil }
            content["file"] = file
        }
        guard let data = try? JSONSerialization.data(withJSONObject: content) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// A catalogue template, as `/catalog/index.json` lists it (§ 5.56).
///
/// `title` and `description` are the base text (Ukrainian); `titles` and
/// `descriptions` carry the other languages the app ships, keyed by language
/// code, and the app's own is shown (§ 5.59). A catalogue written before
/// them decodes the same.
nonisolated struct SpiralAppTemplate: Identifiable, Equatable, Decodable {
    let id: String
    let title: String
    let titles: [String: String]?
    let description: String
    let descriptions: [String: String]?
    let aspect: String
    /// The template's source: what a thread with the agent starts from.
    let source: String
    /// The same template compiled at `catalog:pack` (question 374): what is
    /// published and run, so its frame never loads the compiler. A catalogue
    /// packed before it has none, and `source` is published instead.
    var module: String?
    let manifest: String
    /// A picture of the row, from before the catalogue ran the template
    /// itself (§ 5.61). Not read; a catalogue may still carry it.
    let row: String?
    /// The card at rest (question 376): the template drawn once at
    /// `catalog:pack`, light, with sample names, once per language the
    /// catalogue is written in (question 412), keyed by language code. A touch
    /// runs the template. `still(for:)` picks the one a card shows.
    var stills: [String: String]?
    /// Hex SHA-256 of `module` and of each of `stills` as packed. What is
    /// fetched is checked against it, so a stale file is never published or
    /// shown as the template's. A catalogue packed before them has none.
    var sha256: Digests?
    /// What the agent asks first, by language — for a template that is only
    /// a shape until someone fills it (a poll's question and options, a
    /// card's recipient). Such a template is never published as is: it opens
    /// with the agent, who asks this beside Draft v1 (§ 5.60).
    let asks: [String: String]?
    /// The runtime the template needs — `1.1` for one importing a name the
    /// runtime gained later (§ 5.75). Absent is `1`.
    let runtime: String?
    /// Who the template is for (question 412): the post page's first fact.
    /// Absent in a catalogue packed before it, or a value this build doesn't know.
    var players: Players?
    /// How it plays, most telling first (question 412): the post page's
    /// other facts. Only the values this build knows; any other is skipped (decision 96).
    var traits: [Trait] = []

    /// Whether this build carries what the template imports.
    var isRuntimeSupported: Bool {
        SpiralAppPost.supportedRuntimes.contains(runtime ?? "1")
    }

    var localizedTitle: String {
        SpiralAppCatalog.localized(title, titles)
    }

    /// The question in the app's language, nil for a template that needs none.
    var localizedAsk: String? {
        guard let asks, let base = asks[SpiralAppCatalog.baseLanguage] ?? asks["en"] ?? asks.values.first else {
            return nil
        }
        return SpiralAppCatalog.localized(base, asks)
    }

    var localizedDescription: String {
        SpiralAppCatalog.localized(description, descriptions)
    }

    /// A still to fetch: its path in the catalogue, and the digest it must have when the index gives one.
    struct Still: Equatable {
        let path: String
        let sha256: String?
    }

    /// The languages a still is drawn in (question 412). A reader of any other sees the English one.
    static let stillLanguages = ["uk", "ru", "en"]

    /// The still a card shows to a reader of `languages` (the app's, best first): the first of them the
    /// catalogue draws stills in, as `localized` picks a title, else English. A template without that
    /// one shows the English still, and without English whichever it has (decision 96); one with no
    /// stills at all, nil, and its card has no picture.
    func still(for languages: [String] = SpiralAppCatalog.appLanguages) -> Still? {
        guard let stills else { return nil }
        let wanted = SpiralAppCatalog.firstLanguage(of: languages, among: Self.stillLanguages) ?? "en"
        guard let language = [wanted, "en"].first(where: { stills[$0] != nil }) ?? stills.keys.sorted().first,
              let path = stills[language] else {
            return nil
        }
        return Still(path: path, sha256: sha256?.stills?[language])
    }

    struct Digests: Equatable, Decodable {
        var module: String?
        /// By language, as `stills`.
        var stills: [String: String]?
    }

    /// `players` in `index.json` (`catalog-facts.mjs` in spiral-app-shell).
    enum Players: String, Equatable, CaseIterable {
        /// Each plays alone; the chat keeps the table.
        case solo = "1"
        /// Two take the seats, anyone in the chat can watch.
        case two = "2"
        /// The whole chat takes part.
        case group = "2+"
    }

    /// `traits` in `index.json`: a closed set the app phrases itself, so no
    /// template carries words to translate (`catalog-facts.mjs`).
    enum Trait: String, Equatable, CaseIterable {
        /// A move or an answer stays hidden until everyone has chosen.
        case sealed
        /// Something only one person sees: a fleet, a secret word, your guesses.
        case secret
        case turns
        /// It changes on every phone at once as people act.
        case live
        /// One result, the same on every phone.
        case sameForAll
        /// A score, a tally or a leaderboard that stays in the chat.
        case score
        /// The chat's people are the content: a wheel of names, a rota.
        case names
        /// The agent fills it in first (the template `asks`).
        case agentFills
        /// Everyone sees who chose what.
        case shown
        /// Everyone adds their own to one shared thing.
        case together
    }
}

nonisolated extension SpiralAppTemplate {
    private enum CodingKeys: String, CodingKey {
        case id, title, titles, description, descriptions, aspect, source, module, manifest, row, stills, sha256, asks, runtime, players, traits
    }

    /// As the synthesised decoder read it, plus the facts, which never fail a
    /// template: a value from a newer catalogue is skipped, not an error (decision 96).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        titles = try container.decodeIfPresent([String: String].self, forKey: .titles)
        description = try container.decode(String.self, forKey: .description)
        descriptions = try container.decodeIfPresent([String: String].self, forKey: .descriptions)
        aspect = try container.decode(String.self, forKey: .aspect)
        source = try container.decode(String.self, forKey: .source)
        module = try container.decodeIfPresent(String.self, forKey: .module)
        manifest = try container.decode(String.self, forKey: .manifest)
        row = try container.decodeIfPresent(String.self, forKey: .row)
        stills = try container.decodeIfPresent([String: String].self, forKey: .stills)
        sha256 = try container.decodeIfPresent(Digests.self, forKey: .sha256)
        asks = try container.decodeIfPresent([String: String].self, forKey: .asks)
        runtime = try container.decodeIfPresent(String.self, forKey: .runtime)
        players = (try? container.decodeIfPresent(String.self, forKey: .players)).flatMap { $0 }.flatMap(Players.init(rawValue:))
        traits = (try? container.decodeIfPresent([LenientString].self, forKey: .traits)).flatMap { $0 }?
            .compactMap { $0.value.flatMap(Trait.init(rawValue:)) } ?? []
    }
}

/// A string in a list that may hold something else: anything else reads as nil
/// instead of failing the list.
private nonisolated struct LenientString: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(String.self)
    }
}

nonisolated struct SpiralAppCatalog: Equatable, Decodable {
    struct Section: Equatable, Decodable, Identifiable {
        let id: String
        let title: String
        let titles: [String: String]?
        let items: [String]

        var localizedTitle: String {
            SpiralAppCatalog.localized(title, titles)
        }
    }

    /// The text in the first of the app's languages the catalogue carries,
    /// then English, then the base text — the order `UntranslatedL10n`
    /// resolves in, so a German reader sees the English the rest of the app
    /// shows them rather than the Ukrainian the catalogue is written in.
    static func localized(_ base: String, _ translations: [String: String]?, languages: [String] = appLanguages) -> String {
        guard let translations, !translations.isEmpty else { return base }
        let all = translations.merging([baseLanguage: base]) { translated, _ in translated }
        if let language = firstLanguage(of: languages, among: all.keys) {
            return all[language] ?? base
        }
        return all["en"] ?? base
    }

    /// The app's languages, best first.
    static var appLanguages: [String] {
        Bundle.overrideLocalizations ?? Bundle.app.preferredLocalizations
    }

    /// The first of `languages` that `available` holds, by its full code or its first two letters
    /// (`uk-UA` reads as `uk`): the code `available` holds it under, or nil when it holds none.
    static func firstLanguage(of languages: [String], among available: some Collection<String>) -> String? {
        for language in languages {
            for code in [language, String(language.prefix(2))] where available.contains(code) {
                return code
            }
        }
        return nil
    }

    /// The language a catalogue's base `title`/`description` is written in.
    static let baseLanguage = "uk"

    let runtime: String
    let sections: [Section]
    let items: [SpiralAppTemplate]
    /// What is new, in order (question 412): the catalogue's «New» slider
    /// shows them in this order, each wears a «New» badge. `new` in `index.json`; only ids
    /// of templates this catalogue holds.
    let newIDs: [String]
    /// The templates `runnable` dropped because this build predates their
    /// runtime: a link to one asks for an update rather than saying the
    /// template is gone (decisions 96, 111).
    private(set) var needsNewerBuild: Set<String> = []

    private enum CodingKeys: String, CodingKey {
        case runtime, sections, items
        case newIDs = "new"
    }

    init(runtime: String, sections: [Section], items: [SpiralAppTemplate], newIDs: [String] = [], needsNewerBuild: Set<String> = []) {
        self.runtime = runtime
        self.sections = sections
        self.items = items
        let ids = Set(items.map(\.id))
        var seen = Set<String>()
        self.newIDs = newIDs.filter { ids.contains($0) && seen.insert($0).inserted }
        self.needsNewerBuild = needsNewerBuild
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // What is new never fails a catalogue: absent, or not a list, is nothing new (decision 96).
        let newIDs = (try? container.decodeIfPresent([LenientString].self, forKey: .newIDs)).flatMap { $0 }?.compactMap(\.value) ?? []
        try self.init(runtime: container.decode(String.self, forKey: .runtime),
                      sections: container.decode([Section].self, forKey: .sections),
                      items: container.decode([SpiralAppTemplate].self, forKey: .items),
                      newIDs: newIDs)
    }

    func template(_ id: String) -> SpiralAppTemplate? {
        items.first { $0.id == id }
    }

    /// The catalogue format this build reads (`index.json`'s own `runtime`).
    static let supportedRuntime = "1"

    /// What reading `index.json` gave.
    enum Fetched {
        case catalog(SpiralAppCatalog)
        /// A catalogue format newer than this build: update, not an error (decision 96).
        case newerFormat
        case unavailable
    }

    /// Only the format version, read before the rest: a newer catalogue may
    /// not decode as this build's, and must not read as a broken one.
    private struct Format: Decodable {
        let runtime: String
    }

    /// The catalogue, from the homeserver host (Caddy, like /brand/). Only
    /// templates for the runtime this build carries.
    static func fetch(from base: URL) async -> Fetched {
        guard let index = await data(at: "index.json", from: base),
              let format = try? JSONDecoder().decode(Format.self, from: index) else {
            return .unavailable
        }
        guard format.runtime == supportedRuntime else { return .newerFormat }
        guard let catalog = try? JSONDecoder().decode(SpiralAppCatalog.self, from: index) else { return .unavailable }
        SpiralAppTemplateTitles.standard.store(catalog)
        return .catalog(catalog.runnable)
    }

    static func load(from base: URL) async -> SpiralAppCatalog? {
        guard case .catalog(let catalog) = await fetch(from: base) else { return nil }
        return catalog
    }

    /// Only the templates this build can run — a newer catalogue may carry
    /// games this build predates (§ 5.75) — and sections left with none go.
    var runnable: SpiralAppCatalog {
        let kept = items.filter(\.isRuntimeSupported)
        let ids = Set(kept.map(\.id))
        let sections = sections.map { Section(id: $0.id, title: $0.title, titles: $0.titles, items: $0.items.filter(ids.contains)) }
            .filter { !$0.items.isEmpty }
        let dropped = Set(items.map(\.id)).subtracting(ids)
        return SpiralAppCatalog(runtime: runtime, sections: sections, items: kept, newIDs: newIDs, needsNewerBuild: needsNewerBuild.union(dropped))
    }

    /// What a catalogue link's template id is to this build (decision 111).
    enum Resolution: Equatable {
        case template(SpiralAppTemplate)
        /// In the catalogue, for a runtime this build doesn't carry.
        case needsNewerApp
        /// Not in the catalogue (any more).
        case unknown
        /// The catalogue couldn't be read. A newer catalogue format is
        /// `needsNewerApp`, whatever the id.
        case unavailable
    }

    func resolve(_ id: String) -> Resolution {
        if let template = template(id) {
            return .template(template)
        }
        return needsNewerBuild.contains(id) ? .needsNewerApp : .unknown
    }

    static func resolve(_ id: String, from base: URL) async -> Resolution {
        switch await fetch(from: base) {
        case .catalog(let catalog): catalog.resolve(id)
        case .newerFormat: .needsNewerApp
        case .unavailable: .unavailable
        }
    }

    /// A template packed exactly as `publish(template:)` will pack it, for a
    /// preview that is the post the room would get (§ 5.60).
    static func artifact(of template: SpiralAppTemplate, from base: URL) async -> SpiralAppArtifact? {
        guard let files = await files(of: template, from: base),
              let manifest = SpiralAppManifest(json: Data(files.manifestJSON.utf8)) else {
            return nil
        }
        let packed = SpiralAppContainer.pack(manifestJSON: files.manifestJSON, entry: manifest.entry, source: files.module)
        return SpiralAppArtifact.verified(packed: packed, claimedDigest: SpiralAppArtifact.digest(of: packed))
    }

    /// A template's module and manifest text, as they are published: the
    /// compiled module when the catalogue has one (question 374).
    /// A module that is not the one the catalogue describes is nil.
    static func files(of template: SpiralAppTemplate, from base: URL) async -> (module: String, manifestJSON: String)? {
        let path = template.module ?? template.source
        guard let module = await data(at: path, from: base),
              let manifest = await data(at: template.manifest, from: base) else {
            return nil
        }
        if template.module != nil, let expected = template.sha256?.module, SpiralAppArtifact.digest(of: module) != expected {
            MXLog.error("[SpiralApp] catalogue \(path) is not the module its index describes")
            return nil
        }
        return (String(decoding: module, as: UTF8.self), String(decoding: manifest, as: UTF8.self))
    }

    /// A template's source, for a thread with the agent: the agent edits
    /// source, never the compiled module.
    static func source(of template: SpiralAppTemplate, from base: URL) async -> String? {
        await text(at: template.source, from: base)
    }

    private static func text(at path: String, from base: URL) async -> String? {
        await data(at: path, from: base).map { String(decoding: $0, as: UTF8.self) }
    }

    /// A catalogue file's bytes, or nil when it couldn't be read.
    static func data(at path: String, from base: URL, session: URLSession = .shared) async -> Data? {
        guard let (data, response) = try? await session.data(from: base.appending(path: path)) else {
            MXLog.error("[SpiralApp] catalogue \(path) could not be read")
            return nil
        }
        return body(data, response, path: path)
    }

    /// The bytes of a response that is the file: an HTTP status other than
    /// 2xx is the server's error page, never a module or a still. A file URL
    /// (tests, a catalogue on disk) has no status.
    static func body(_ data: Data, _ response: URLResponse, path: String) -> Data? {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            MXLog.error("[SpiralApp] catalogue \(path) answered HTTP \(http.statusCode)")
            return nil
        }
        return data
    }
}

/// The catalogue templates' titles in every language, kept from the last
/// catalogue read, so a template's post shows its title in the READER'S
/// language. A post stores its title in the publisher's language («Перетягування
/// каната» from a uk phone); until the post writes its first summary line,
/// that is all an en reader would see on its card.
///
/// Read synchronously, where a post's row is built. Every successful catalogue
/// read refreshes it (`SpiralAppCatalog.fetch`), and the session's start reads
/// the catalogue once in the background (`ChatsTabFlowCoordinator.start`), so a
/// reader who never opened the catalogue gets the titles too. Nothing kept, or
/// a template the catalogue no longer lists: the post's stored title.
nonisolated final class SpiralAppTemplateTitles: Sendable {
    /// Thread-safe, as Foundation documents; not marked `Sendable`.
    nonisolated(unsafe) let defaults: UserDefaults
    /// The decoded titles: a row's build reads them, and a plist read per row
    /// would cost more than the lookup it serves. Nil until first read.
    private let memo = Mutex<[String: [String: String]]?>(nil)

    static let standard = SpiralAppTemplateTitles(defaults: .standard)

    private static let key = "spiralCatalogTemplateTitles"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Keeps every template's base title (under `SpiralAppCatalog.baseLanguage`)
    /// and its translations, keyed by template id. Templates this build can't
    /// run are kept too: their posts are still titled.
    func store(_ catalog: SpiralAppCatalog) {
        var all = [String: [String: String]]()
        for template in catalog.items {
            all[template.id] = (template.titles ?? [:]).merging([SpiralAppCatalog.baseLanguage: template.title]) { translated, _ in translated }
        }
        defaults.set(all, forKey: Self.key)
        memo.withLock { $0 = all }
    }

    /// The card's title for a post: a catalogue template's (`app_id` `tpl-<id>`)
    /// in the first of `languages` the catalogue carries, else nil and the post's
    /// own title stands.
    func title(forAppID appID: String, languages: [String] = SpiralAppCatalog.appLanguages) -> String? {
        guard appID.hasPrefix("tpl-"), let titles = kept[String(appID.dropFirst(4))],
              let base = titles[SpiralAppCatalog.baseLanguage] else {
            return nil
        }
        return SpiralAppCatalog.localized(base, titles, languages: languages)
    }

    private var kept: [String: [String: String]] {
        memo.withLock { memo in
            if let memo { return memo }
            let kept = defaults.dictionary(forKey: Self.key) as? [String: [String: String]] ?? [:]
            memo = kept
            return kept
        }
    }
}
