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
    let source: String
    let manifest: String
    /// A picture of the row, from before the catalogue ran the template
    /// itself (§ 5.61). Not read; a catalogue may still carry it.
    let row: String?
    /// What the agent asks first, by language — for a template that is only
    /// a shape until someone fills it (a poll's question and options, a
    /// card's recipient). Such a template is never published as is: it opens
    /// with the agent, who asks this beside Draft v1 (§ 5.60).
    let asks: [String: String]?
    /// The runtime the template needs — `1.1` for one importing a name the
    /// runtime gained later (§ 5.75). Absent is `1`.
    let runtime: String?

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
    static func localized(_ base: String, _ translations: [String: String]?) -> String {
        guard let translations, !translations.isEmpty else { return base }
        let all = translations.merging([baseLanguage: base]) { translated, _ in translated }
        for language in Bundle.overrideLocalizations ?? Bundle.app.preferredLocalizations {
            if let text = all[language] ?? all[String(language.prefix(2))] {
                return text
            }
        }
        return all["en"] ?? base
    }

    /// The language a catalogue's base `title`/`description` is written in.
    static let baseLanguage = "uk"

    let runtime: String
    let sections: [Section]
    let items: [SpiralAppTemplate]
    /// The templates `runnable` dropped because this build predates their
    /// runtime: a link to one asks for an update rather than saying the
    /// template is gone (decisions 96, 111).
    private(set) var needsNewerBuild: Set<String> = []

    private enum CodingKeys: String, CodingKey {
        case runtime, sections, items
    }

    init(runtime: String, sections: [Section], items: [SpiralAppTemplate], needsNewerBuild: Set<String> = []) {
        self.runtime = runtime
        self.sections = sections
        self.items = items
        self.needsNewerBuild = needsNewerBuild
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
        guard let (data, _) = try? await URLSession.shared.data(from: base.appending(path: "index.json")),
              let format = try? JSONDecoder().decode(Format.self, from: data) else {
            return .unavailable
        }
        guard format.runtime == supportedRuntime else { return .newerFormat }
        guard let catalog = try? JSONDecoder().decode(SpiralAppCatalog.self, from: data) else { return .unavailable }
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
        return SpiralAppCatalog(runtime: runtime, sections: sections, items: kept, needsNewerBuild: needsNewerBuild.union(dropped))
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
        let packed = SpiralAppContainer.pack(manifestJSON: files.manifestJSON, entry: manifest.entry, source: files.source)
        return SpiralAppArtifact.verified(packed: packed, claimedDigest: SpiralAppArtifact.digest(of: packed))
    }

    /// A template's source and manifest text.
    static func files(of template: SpiralAppTemplate, from base: URL) async -> (source: String, manifestJSON: String)? {
        guard let (source, _) = try? await URLSession.shared.data(from: base.appending(path: template.source)),
              let (manifest, _) = try? await URLSession.shared.data(from: base.appending(path: template.manifest)) else {
            return nil
        }
        return (String(decoding: source, as: UTF8.self), String(decoding: manifest, as: UTF8.self))
    }
}
