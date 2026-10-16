//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 5.12): reading an artifact's bytes.
//
// An artifact is a manifest and one module, packed in a container whose whole
// purpose is that three independent implementations — the TypeScript packer,
// the Rust one the agent will use, and this — produce and read the same bytes
// from the same contents, for ever. Its SHA-256 is the post's identity.
//
//     SPIRALv1\n
//     manifest.json\n<decimal byte count>\n<bytes>
//     app.jsx\n<decimal byte count>\n<bytes>
//
// Not tar and not zip: both carry timestamps, permissions and compression
// choices, none of which may change an identity and all of which differ
// between writers.
//
// Byte counts are what makes this safe to parse. A reader that scanned for
// entry names would be fooled by a generated app containing the string
// `app.jsx\n999\n`, which a model could write by accident or on purpose.
//

import Foundation

/// Where a generated post was made: a thread in the owner's DM with the agent.
nonisolated struct SpiralAppOrigin: Equatable {
    let roomID: String
    let threadRootEventID: String
}

/// The post a generation thread now edits — written into the thread by the
/// client as `com.spiral.live_post` when it publishes, replaces or reopens
/// one (§ 5.55). Its drafts then offer to update THAT post in place.
nonisolated struct SpiralLivePost: Equatable {
    let roomID: String
    let eventID: String
    let roomName: String

    static let contentKey = "com.spiral.live_post"
    /// A marker's body starts with this, so a timeline only asks for the raw
    /// JSON of messages that can be one.
    static let bodyPrefix = "📌 "

    /// The marker in a raw event, if it is one.
    init?(eventJSON: String) {
        guard let data = eventJSON.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = event["content"] as? [String: Any],
              let marker = content[Self.contentKey] as? [String: Any],
              let roomID = marker["room_id"] as? String, !roomID.isEmpty,
              let eventID = marker["event_id"] as? String, !eventID.isEmpty else {
            return nil
        }
        self.init(roomID: roomID, eventID: eventID, roomName: marker["room_name"] as? String ?? "")
    }

    init(roomID: String, eventID: String, roomName: String) {
        self.roomID = roomID
        self.eventID = eventID
        self.roomName = roomName
    }

    /// The `m.text` that says so, in the thread `threadRootEventID`.
    func markerContent(action: String, body: String, threadRootEventID: String) -> String? {
        let content: [String: Any] = [
            "msgtype": "m.text",
            "body": Self.bodyPrefix + body,
            "m.relates_to": ["rel_type": "m.thread",
                             "event_id": threadRootEventID,
                             "is_falling_back": true,
                             "m.in_reply_to": ["event_id": threadRootEventID]],
            Self.contentKey: ["room_id": roomID, "event_id": eventID, "room_name": roomName, "action": action]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: content) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Where a thread opened from the catalogue publishes: the room «+» was
/// pressed in, which need not be the room the thread was made for (§ 5.56).
nonisolated struct SpiralPublishRoom: Equatable {
    let id: String
    let name: String
}

/// What an artifact declares about itself.
nonisolated struct SpiralAppManifest: Equatable {
    let appID: String
    /// Runtime major version the artifact was written against.
    let runtime: String
    /// The module to load. `app.jsx` in v1, named so the format outlives it.
    let entry: String
    /// `w:h`. The row is sized from this before a byte of the app loads.
    let aspect: String
    let stateChannel: String
    /// What the artifact ASKS for. Granting is the host's business.
    let capabilities: [String]
    let maxStateBytes: Int
    /// The generation thread the post came from, when the agent says: the
    /// DM with it and the thread's root, so «Change» on a published post
    /// opens the conversation it was made in (§ 5.55). Inside the digest.
    let origin: SpiralAppOrigin?

    init?(json: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let appID = root["app_id"] as? String, !appID.isEmpty,
              let runtime = root["runtime"] as? String,
              let entry = root["entry"] as? String, !entry.isEmpty,
              let capabilities = root["capabilities"] as? [String] else {
            return nil
        }

        self.appID = appID
        self.runtime = runtime
        self.entry = entry
        self.capabilities = capabilities
        // Absent rather than wrong is survivable for these three: a missing
        // aspect is a square row, a missing channel is the shared one, and a
        // missing limit is the documented default. A missing `entry` is not,
        // which is why it is above.
        aspect = root["aspect"] as? String ?? "1:1"
        stateChannel = root["state_channel"] as? String ?? "matrix"
        maxStateBytes = (root["limits"] as? [String: Any])?["max_state_bytes"] as? Int ?? 16 * 1024
        if let origin = root["origin"] as? [String: Any],
           let roomID = origin["room_id"] as? String, !roomID.isEmpty,
           let threadRoot = origin["thread_root"] as? String, !threadRoot.isEmpty {
            self.origin = SpiralAppOrigin(roomID: roomID, threadRootEventID: threadRoot)
        } else {
            origin = nil
        }
    }

    /// `aspect` as a width/height ratio, or `nil` when it says nothing usable.
    ///
    /// Refuses zero and negative values rather than clamping them: a row sized
    /// from a nonsense ratio is a layout bug that surfaces far from its cause.
    var aspectRatio: CGFloat? {
        let parts = aspect.split(separator: ":")
        guard parts.count == 2,
              let width = Double(parts[0]), let height = Double(parts[1]),
              width > 0, height > 0 else {
            return nil
        }
        return CGFloat(width / height)
    }
}

/// An artifact's contents, read from its container.
nonisolated struct SpiralAppContainer: Equatable {
    let manifest: SpiralAppManifest
    /// The entry module's bytes, UTF-8.
    let source: Data

    private static let magic = "SPIRALv1"

    /// Write packed bytes.
    ///
    /// Takes the manifest as the JSON TEXT it was given, not as a parsed
    /// value: the digest is of the bytes, and the bytes of a manifest are
    /// whatever its writer serialised — key order included. A client that
    /// re-serialised would hash something the agent never wrote and could
    /// never verify against the agent's `sha256`. So the agent's manifest
    /// text travels in the draft and is packed here as is; the three
    /// packers agree because none of them has an opinion about it.
    static func pack(manifestJSON: String, entry: String, source: String) -> Data {
        var out = Data()
        out.append(Data("\(magic)\n".utf8))
        for (name, body) in [("manifest.json", Data(manifestJSON.utf8)), (entry, Data(source.utf8))] {
            out.append(Data("\(name)\n\(body.count)\n".utf8))
            out.append(body)
        }
        return out
    }

    /// Read packed bytes.
    ///
    /// Returns `nil` for anything that is not exactly this format. The caller
    /// must treat that as "refuse to run": an artifact we cannot read is one
    /// whose digest told us nothing about what we would have run.
    static func unpack(_ bytes: Data) -> SpiralAppContainer? {
        var cursor = bytes.startIndex

        // Checked before anything is parsed, so something that is not a
        // container at all says so — rather than failing later with whatever
        // the first mis-parse happens to be.
        guard let header = "\(magic)\n".data(using: .utf8),
              bytes.count >= header.count,
              bytes.prefix(header.count) == header else {
            MXLog.error("[SpiralApp] artifact is not a \(magic) container")
            return nil
        }
        cursor += header.count

        func readLine() -> String? {
            guard let newline = bytes[cursor...].firstIndex(of: 0x0A) else { return nil }
            defer { cursor = bytes.index(after: newline) }
            return String(data: bytes[cursor..<newline], encoding: .utf8)
        }

        func readEntry() -> (name: String, body: Data)? {
            guard let name = readLine(),
                  let countText = readLine(),
                  let count = Int(countText), count >= 0,
                  bytes.index(cursor, offsetBy: count, limitedBy: bytes.endIndex) != nil else {
                return nil
            }
            let end = bytes.index(cursor, offsetBy: count)
            defer { cursor = end }
            return (name, bytes[cursor..<end])
        }

        guard let first = readEntry(), first.name == "manifest.json",
              let manifest = SpiralAppManifest(json: first.body) else {
            MXLog.error("[SpiralApp] artifact has no readable manifest.json")
            return nil
        }

        guard let second = readEntry(), second.name == manifest.entry else {
            MXLog.error("[SpiralApp] artifact does not carry the entry its manifest names")
            return nil
        }

        // Trailing bytes mean the writer and this reader disagree about the
        // format — which is exactly the disagreement a digest cannot detect,
        // since both sides would agree on the hash of the whole thing.
        guard cursor == bytes.endIndex else {
            MXLog.error("[SpiralApp] artifact has \(bytes.endIndex - cursor) bytes after the last entry")
            return nil
        }

        return SpiralAppContainer(manifest: manifest, source: Data(second.body))
    }
}
