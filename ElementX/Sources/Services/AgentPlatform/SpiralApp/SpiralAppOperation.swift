//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 5.2): the six operations an
// Interactive Post's action may carry.
//
// Six, and no more, on purpose. Every app in the v1 queue — poll, shopping
// list, checklist, randomiser, split-the-bill — expresses itself in these,
// and each one is chosen so that concurrent use by two people converges:
// per-user paths never collide, appends never collide, and the two that can
// collide (`set` on one path, `incr`) have a defined winner.
//
// Plus ONE that carries the others: `batch`. Every action is a Matrix event
// in an E2EE room, and a clicker tapped a hundred times was a hundred
// events. The SDK coalesces a burst into one batch (§ 5.34 #2); the fold
// applies it as its members in order, and ownership is judged per member.
// A batch cannot contain a batch, and is bounded, so the wire stays flat.
//

import Foundation

enum SpiralAppOperation: Equatable {
    /// Overwrite whatever is at `path`.
    case set(path: [String], value: SpiralAppValue)
    /// Write only if nothing is there. The randomiser's "first spin wins"
    /// is exactly this, and it is why the app needs no lock.
    case setIfAbsent(path: [String], value: SpiralAppValue)
    /// Remove `path`. Idempotent.
    case delete(path: [String])
    /// Add to a number, creating it at zero when absent.
    case increment(path: [String], by: Double)
    /// Append to a list, creating it when absent.
    case listAppend(path: [String], item: SpiralAppValue)
    /// Remove the first list member whose `id` matches.
    case listRemove(path: [String], id: String)
    /// Several of the above, applied in order as one action.
    case batch([SpiralAppOperation])

    /// Most operations one batch may carry. A burst longer than this is
    /// two actions, which is still far fewer than it was.
    static let maxBatchSize = 64

    // MARK: - Decoding

    /// Parse the `op` object of a `com.spiral.app.action` event.
    ///
    /// Returns `nil` for anything unrecognised. A newer client emitting a
    /// seventh operation must not make an older one compute a *different*
    /// state — refusing the action outright is the only safe reading, and
    /// the caller reports it rather than guessing.
    init?(json: Any) {
        guard let object = json as? [String: Any],
              let (name, body) = object.first,
              let arguments = body as? [String: Any] else {
            return nil
        }

        let path = Self.path(from: arguments["path"])

        switch name {
        case "set":
            guard !path.isEmpty, let raw = arguments["value"],
                  let value = SpiralAppValue(json: raw) else { return nil }
            self = .set(path: path, value: value)

        case "setIfAbsent":
            guard !path.isEmpty, let raw = arguments["value"],
                  let value = SpiralAppValue(json: raw) else { return nil }
            self = .setIfAbsent(path: path, value: value)

        case "del":
            guard !path.isEmpty else { return nil }
            self = .delete(path: path)

        case "incr":
            guard !path.isEmpty, let by = arguments["by"] as? Double else { return nil }
            self = .increment(path: path, by: by)

        case "listAppend":
            guard !path.isEmpty, let raw = arguments["item"],
                  let item = SpiralAppValue(json: raw) else { return nil }
            self = .listAppend(path: path, item: item)

        case "listRemove":
            guard !path.isEmpty, let id = arguments["id"] as? String else { return nil }
            self = .listRemove(path: path, id: id)

        case "batch":
            // Every member must parse, or the whole batch is refused: a batch
            // half applied is a state no other client would compute.
            guard let raw = arguments["ops"] as? [Any],
                  !raw.isEmpty, raw.count <= Self.maxBatchSize else { return nil }
            var members: [SpiralAppOperation] = []
            for item in raw {
                guard let member = SpiralAppOperation(json: item) else { return nil }
                if case .batch = member { return nil }
                members.append(member)
            }
            self = .batch(members)

        default:
            return nil
        }
    }

    /// Path components, from either wire form. Empty when absent or
    /// malformed, which every case above rejects.
    ///
    /// An array is accepted because a dotted string cannot address a key
    /// containing a dot — and every Matrix user ID does (`@a:spiral.md`).
    /// Keying state by user is the first thing a poll or a checklist wants,
    /// so `"votes.@a:spiral.md"` would split into three components and write
    /// somewhere nobody meant.
    private static func path(from raw: Any?) -> [String] {
        if let components = raw as? [String] {
            // One empty component would address a key no writer can name,
            // so the whole path is refused rather than silently shortened.
            return components.isEmpty || components.contains(where: \.isEmpty) ? [] : components
        }

        guard let dotted = raw as? String, !dotted.isEmpty else { return [] }
        return dotted.split(separator: ".").map(String.init)
    }

    // MARK: - Encoding

    /// The `op` object to write into a `com.spiral.app.action` event.
    ///
    /// Must round-trip through ``init(json:)``: a client that cannot read back
    /// what it wrote would fold a different state from its own action.
    var jsonObject: [String: Any] {
        let encoded = Self.encode(path: path)

        return switch self {
        case .set(_, let value):
            ["set": ["path": encoded, "value": value.jsonObject]]
        case .setIfAbsent(_, let value):
            ["setIfAbsent": ["path": encoded, "value": value.jsonObject]]
        case .delete:
            ["del": ["path": encoded]]
        case .increment(_, let by):
            ["incr": ["path": encoded, "by": by]]
        case .listAppend(_, let item):
            ["listAppend": ["path": encoded, "item": item.jsonObject]]
        case .listRemove(_, let id):
            ["listRemove": ["path": encoded, "id": id]]
        case .batch(let members):
            ["batch": ["ops": members.map(\.jsonObject)]]
        }
    }

    /// Dotted while that is unambiguous, an array once it is not.
    ///
    /// Keeps the common event readable — `"path": "count"` — without letting
    /// a component that contains a dot be written in a form that cannot be
    /// read back. Both forms parse, so this only decides what we emit.
    private static func encode(path: [String]) -> Any {
        path.contains { $0.contains(".") } ? path : path.joined(separator: ".")
    }

    /// The path this operation touches, for collision detection. Empty for
    /// a batch, which touches its members' paths.
    var path: [String] {
        switch self {
        case .set(let path, _), .setIfAbsent(let path, _), .delete(let path),
             .increment(let path, _), .listAppend(let path, _), .listRemove(let path, _):
            path
        case .batch:
            []
        }
    }

    /// This operation as the list of simple operations it performs: itself,
    /// or a batch's members. What the fold and the ownership check walk, so
    /// neither has a second opinion about what a batch means.
    var members: [SpiralAppOperation] {
        if case .batch(let members) = self { return members }
        return [self]
    }

    // MARK: - Ownership

    /// The top-level key under which each user has a namespace of their own.
    ///
    /// `by.<userId>.*` is writable only by `<userId>` and is folded only from
    /// that user's actions — never taken from another sender's `state` blob.
    /// It is what makes "who voted", "who confirmed", "who scored" honest:
    /// the same property MSC3381 polls get because a vote is the voter's
    /// event. An app keys per-person data here and gets it for free; one
    /// that keys it anywhere else gets shared, rewritable data, which is
    /// also sometimes what it wants.
    static let ownedNamespace = "by"

    /// Whose namespace this operation writes into, or nil for shared state.
    /// A batch has no single owner; ask its `members`.
    ///
    /// The bare `by` is everybody's namespaces at once, so it belongs to
    /// nobody: its owner is "", which no sender is. A write there is refused
    /// before it is sent and skipped by every reader's owned pass; as shared
    /// state it forged other members' votes (corpus F2).
    var owner: String? {
        let path = path
        guard path.first == Self.ownedNamespace else { return nil }
        return path.count >= 2 ? path[1] : ""
    }

    // MARK: - Application

    /// Apply to a state document, returning the result.
    func applied(to state: SpiralAppValue) -> SpiralAppValue {
        switch self {
        case .set(let path, let value):
            return state.setting(path, to: value)

        case .setIfAbsent(let path, let value):
            // `.null` counts as absent: an app that clears a slot by writing
            // null should not then be unable to claim it again.
            let existing = state.value(at: path)
            if existing == nil || existing == .null {
                return state.setting(path, to: value)
            }
            return state

        case .delete(let path):
            return state.removing(path)

        case .increment(let path, let amount):
            let current: Double
            if case .number(let value) = state.value(at: path) ?? .null {
                current = value
            } else {
                current = 0
            }
            return state.setting(path, to: .number(current + amount))

        case .listAppend(let path, let item):
            var items: [SpiralAppValue]
            if case .array(let existing) = state.value(at: path) ?? .null {
                items = existing
            } else {
                items = []
            }
            items.append(item)
            return state.setting(path, to: .array(items))

        case .listRemove(let path, let id):
            guard case .array(let items) = state.value(at: path) ?? .null else { return state }
            let remaining = items.filter { item in
                guard case .object(let members) = item,
                      case .string(let itemID)? = members["id"] else { return true }
                return itemID != id
            }
            return state.setting(path, to: .array(remaining))

        case .batch(let members):
            return members.reduce(state) { $1.applied(to: $0) }
        }
    }
}

extension SpiralAppOperation {
    /// One line for a log: the kind and the path, never the value.
    var shortDescription: String {
        switch self {
        case .set(let path, _): "set \(path.joined(separator: "."))"
        case .setIfAbsent(let path, _): "setIfAbsent \(path.joined(separator: "."))"
        case .delete(let path): "del \(path.joined(separator: "."))"
        case .increment(let path, let by): "incr \(path.joined(separator: ".")) by \(by)"
        case .listAppend(let path, _): "listAppend \(path.joined(separator: "."))"
        case .listRemove(let path, let id): "listRemove \(path.joined(separator: ".")) \(id)"
        case .batch(let ops): "batch[\(ops.map(\.shortDescription).joined(separator: ", "))]"
        }
    }
}
