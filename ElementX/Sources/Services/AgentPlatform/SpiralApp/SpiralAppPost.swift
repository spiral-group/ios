//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 5.1): the post event, parsed.
//
// A `com.spiral.app` event says where the artifact is and what it looks like
// before any of it loads. That matters twice over: the timeline row is sized
// from `aspect` before a byte arrives, and the room list needs a line to show
// without running anything at all.
//
// Read from `debugInfo.originalJSON` rather than typed FFI content, because
// the SDK models a custom message-like event as nothing but its type string
// (`MsgLikeKind.other(eventType:)`). That escape hatch is the documented one
// — ADR-0058, and the same route `SpiralToolsStateReader` uses.
//

import Foundation
import MatrixRustSDK

/// The reference to an artifact's bytes in Matrix media.
///
/// One of two shapes: `file` in an encrypted room, `url` otherwise. Both are
/// carried so the client can fetch either without a second decision.
nonisolated enum SpiralAppSource: Equatable {
    /// `mxc://` in an unencrypted room.
    case plain(String)
    /// An `EncryptedFile` (v2), carried as its JSON.
    ///
    /// Bytes rather than a dictionary because it is opaque to us until we
    /// decrypt — and because `[String: Any]` is neither `Equatable` nor
    /// `Sendable`, which a timeline item must be: items are built off the
    /// main actor and diffed on the main one.
    case encrypted(Data)

    /// The `EncryptedFile` wrapped the way `MediaSource.fromJson` reads it.
    ///
    /// Ruma's `MediaSource` is `{"url": …}` OR `{"file": {…}}`, and an
    /// `EncryptedFile` on its own has a `url` in it — so handed over bare it
    /// reads as a PLAIN source at the ciphertext's address, downloads the
    /// ciphertext, and the digest check refuses it (2026-09-17: the first
    /// published draft, `claimed 3f25…, got 79d4…`). Wrapped under `file`,
    /// the SDK decrypts on the way in, as it does for every photo.
    var mediaSourceJSON: String? {
        switch self {
        case .plain(let url):
            return "{\"url\": \(url.jsonEscaped)}"
        case .encrypted(let json):
            guard let file = String(data: json, encoding: .utf8) else { return nil }
            return "{\"file\": \(file)}"
        }
    }

    /// Where the bytes are, whichever shape this is.
    var mxcURL: String? {
        switch self {
        case .plain(let url):
            url
        case .encrypted(let json):
            (try? JSONSerialization.jsonObject(with: json) as? [String: Any])?["url"] as? String
        }
    }
}

/// One Interactive Post, as its event describes it.
///
/// `nonisolated` because timeline items are built on a detached task
/// (`TimelineController` runs the factory off the main actor) and diffed on
/// the main one.
nonisolated struct SpiralAppPost: Equatable {
    /// A `msgtype`, not an event type.
    ///
    /// An Interactive Post is a MESSAGE — the same kind of thing as a photo —
    /// so it travels as `m.room.message` and every path that already carries
    /// messages carries it: the room list, push rules, and the fallback
    /// rendering of every other Matrix client, which shows `body`.
    static let msgtype = "com.spiral.app"

    let appID: String
    /// Runtime major version the artifact was written against.
    let runtime: String
    /// Shown on the card and in the room list when nothing is running.
    let title: String
    /// `w:h`. Sizes the row before the artifact loads, so it never reflows.
    let aspect: String
    let stateChannel: String
    /// Lowercase hex SHA-256 of the packed container.
    let digest: String
    let source: SpiralAppSource

    /// The runtime majors this build carries. A post written against another
    /// is shown as its card with «update the app» and never mounted (§ 7 #25,
    /// § 5.70): the runtime is served by the app, so the day there is a `2`
    /// an older app would have booted its `1` into a module that imports
    /// what `1` does not have, and shown a blank row.
    ///
    /// `1.<level>` is the same runtime with names added later — `1.1`
    /// brought the games (`useSeats`, `useLeaderboard`, `<Leaderboard>`,
    /// § 5.75). A post says the level its imports need, so a build that
    /// predates them shows the card rather than failing to link.
    static let supportedRuntimes: Set = ["1", "1.1"]

    /// Whether this build can run the post at all.
    var isRuntimeSupported: Bool {
        Self.supportedRuntimes.contains(runtime)
    }

    /// `aspect` as a width/height ratio, or `nil` when it says nothing usable.
    var aspectRatio: CGFloat? {
        let parts = aspect.split(separator: ":")
        guard parts.count == 2,
              let width = Double(parts[0]), let height = Double(parts[1]),
              width > 0, height > 0 else {
            return nil
        }
        return CGFloat(width / height)
    }

    /// The shape the ROW will actually take.
    ///
    /// A manifest asks; the host decides — the same rule as capabilities. What
    /// it may not do is ask for a shape nobody can use: `16:1` is a 22pt strip
    /// across a phone, with controls too small to hit and text that cannot fit.
    ///
    /// Clamped rather than floored, so the app always fills its row exactly. A
    /// minimum HEIGHT would have left an app sitting in a band of empty space,
    /// which looks like a bug rather than a decision.
    var displayAspectRatio: CGFloat {
        min(max(aspectRatio ?? 1, Self.narrowestAspectRatio), Self.widestAspectRatio)
    }

    /// Taller than wide, to a point: a portrait app still has to be a message
    /// in a conversation rather than a page.
    static let narrowestAspectRatio: CGFloat = 0.5
    /// Wider than tall, to a point. Past this a row is a strip.
    static let widestAspectRatio: CGFloat = 4

    /// Whether this raw event is an Interactive Post.
    ///
    /// The ONE place raw JSON is still read, and only because the event-cache
    /// observer hands out events as text — it sits below the typed layer on
    /// purpose, so that actions can be seen at all. Anything with typed content
    /// uses `init(_:)` instead.
    static func isPost(rawEventJSON: String) -> Bool {
        guard let data = rawEventJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["type"] as? String == "m.room.message",
              let content = root["content"] as? [String: Any] else {
            return false
        }

        return content["msgtype"] as? String == msgtype
    }

    /// Adopt what the SDK already read.
    ///
    /// No parsing here, and none anywhere else in the app: an Interactive Post
    /// is a message type, so its claims arrive typed the way an image's
    /// dimensions do. This exists only to keep the app's own vocabulary —
    /// `source` says where the bytes are without the caller minding whether
    /// the room was encrypted.
    init(_ content: InteractivePostContent) {
        appID = content.appId
        runtime = content.runtime
        title = content.title
        aspect = content.aspect
        stateChannel = content.stateChannel
        digest = content.sha256

        // `file` first: in an encrypted room both may be present, and the
        // encrypted one is the only one that can be decrypted.
        if let fileJSON = content.fileJson, let data = fileJSON.data(using: .utf8) {
            source = .encrypted(data)
        } else {
            source = .plain(content.url ?? "")
        }
    }
}

private nonisolated extension String {
    /// `self` as a JSON string literal, quotes included.
    var jsonEscaped: String {
        guard let data = try? JSONSerialization.data(withJSONObject: [self]),
              let array = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(array.dropFirst().dropLast())
    }
}
