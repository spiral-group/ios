//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 4.7): the value type an
// Interactive Post's shared state is made of.
//
// State arrives as JSON in a Matrix event and goes back out as JSON, so this
// is a JSON tree and nothing more. It is spelled out as an enum rather than
// passed around as `Any` because the fold has to compare values for equality
// and walk them by path, and both are miserable to do safely on `Any`.
//

import Foundation

indirect enum SpiralAppValue: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([SpiralAppValue])
    case object([String: SpiralAppValue])
}

// MARK: - JSON

extension SpiralAppValue {
    /// Build from `JSONSerialization` output.
    ///
    /// Returns `nil` for anything JSON cannot contain, so a malformed event
    /// is refused rather than silently folded into a half-state.
    init?(json: Any) {
        switch json {
        case is NSNull:
            self = .null
        case let value as NSNumber:
            // `NSNumber` does not distinguish Bool from 0/1 by type, only by
            // its ObjC encoding. Getting this wrong turns `true` into `1`
            // and back, which breaks equality for a checklist's toggles.
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as String:
            self = .string(value)
        case let value as [Any]:
            var items: [SpiralAppValue] = []
            items.reserveCapacity(value.count)
            for item in value {
                guard let converted = SpiralAppValue(json: item) else { return nil }
                items.append(converted)
            }
            self = .array(items)
        case let value as [String: Any]:
            var members: [String: SpiralAppValue] = [:]
            members.reserveCapacity(value.count)
            for (key, item) in value {
                guard let converted = SpiralAppValue(json: item) else { return nil }
                members[key] = converted
            }
            self = .object(members)
        default:
            return nil
        }
    }

    /// Convert back to something `JSONSerialization` accepts.
    var jsonObject: Any {
        switch self {
        case .null: NSNull()
        case .bool(let value): value
        case .number(let value): value
        case .string(let value): value
        case .array(let items): items.map(\.jsonObject)
        case .object(let members): members.mapValues(\.jsonObject)
        }
    }

    /// Parse a complete state document.
    static func decode(from data: Data) -> SpiralAppValue? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return SpiralAppValue(json: json)
    }

    func encoded() -> Data? {
        try? JSONSerialization.data(withJSONObject: jsonObject, options: [.fragmentsAllowed, .sortedKeys])
    }
}

// MARK: - Paths

extension SpiralAppValue {
    /// Read the value at a dotted path, or `nil` when the path does not exist.
    func value(at path: [String]) -> SpiralAppValue? {
        guard let head = path.first else { return self }
        guard case .object(let members) = self, let child = members[head] else { return nil }
        return child.value(at: Array(path.dropFirst()))
    }

    /// Return a copy with `newValue` written at `path`, creating any missing
    /// objects along the way.
    ///
    /// Intermediate values that are not objects are **replaced**. An app that
    /// writes `a.b` after setting `a` to a number has contradicted itself, and
    /// refusing the write would leave two clients disagreeing about the state
    /// — the one thing the fold exists to prevent.
    func setting(_ path: [String], to newValue: SpiralAppValue) -> SpiralAppValue {
        guard let head = path.first else { return newValue }

        var members: [String: SpiralAppValue]
        if case .object(let existing) = self {
            members = existing
        } else {
            members = [:]
        }

        let child = members[head] ?? .object([:])
        members[head] = child.setting(Array(path.dropFirst()), to: newValue)
        return .object(members)
    }

    /// Return a copy with `path` removed. A path that does not exist is not
    /// an error: deleting twice must be idempotent, because two clients can
    /// both delete the same item before either sees the other.
    func removing(_ path: [String]) -> SpiralAppValue {
        guard let head = path.first else { return self }
        guard case .object(let existing) = self else { return self }

        var members = existing
        if path.count == 1 {
            members.removeValue(forKey: head)
        } else if let child = members[head] {
            members[head] = child.removing(Array(path.dropFirst()))
        }
        return .object(members)
    }

    /// Approximate size, used against the 16 KiB per-instance ceiling.
    var encodedByteCount: Int {
        encoded()?.count ?? 0
    }
}
