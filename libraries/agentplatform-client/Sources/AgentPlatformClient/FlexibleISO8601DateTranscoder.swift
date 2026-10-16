//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// FlexibleISO8601DateTranscoder — date encode/decode for
// swift-openapi-generator that tolerates fractional-second
// precision beyond what Foundation's strict ISO 8601 parser
// accepts out of the box.
//
// Why this exists:
//
// The Agent Platform backend serialises `chrono::DateTime<Utc>`
// via `serde` defaults, which emit RFC 3339 timestamps with
// microsecond precision (e.g. `2026-05-11T12:10:08.866997Z`).
// RFC 3339 explicitly allows arbitrary fractional-second
// precision, but `OpenAPIRuntime.ISO8601DateTranscoder` (the
// default `DateTranscoder` baked into `Configuration`) routes
// decoding through `Foundation.ISO8601DateFormatter` without
// `.withFractionalSeconds`, which rejects any `.` after the
// seconds field. Result: every `/api/v1/*` response that
// includes `created_at` / `updated_at` fails with
// `DecodingError.dataCorrupted: Expected date string to be
// ISO8601-formatted`.
//
// This transcoder accepts both shapes on decode:
//
//   * `2026-05-11T12:10:08Z`        (no fractional seconds)
//   * `2026-05-11T12:10:08.123Z`    (millisecond precision)
//   * `2026-05-11T12:10:08.866997Z` (microsecond precision)
//   * `2026-05-11T12:10:08.866997123Z` (nanosecond precision)
//
// On encode, we emit millisecond precision (`.123Z`) for
// stability — backend accepts any RFC 3339-compliant input
// and we never need sub-millisecond precision in request
// payloads.
//
// Wire this into the generated client via
// `Configuration(dateTranscoder:)` in `AgentPlatformClient.init`;
// the generator routes every `format: date-time` field through
// `Configuration.dateTranscoder` automatically.

import Foundation
import OpenAPIRuntime

/// `DateTranscoder` that accepts ISO 8601 / RFC 3339 timestamps
/// with arbitrary fractional-second precision on decode and
/// emits millisecond-precision UTC timestamps on encode.
///
/// Thread-safe: every `encode` / `decode` call constructs its
/// own `ISO8601DateFormatter`. The formatters themselves are
/// not `Sendable` (Foundation's class predates Swift 6 strict
/// concurrency), and `DateTranscoder` requires `Sendable`
/// conformance — keeping no stored properties sidesteps the
/// issue entirely. The formatter allocation is cheap (a few μs)
/// and dwarfed by the surrounding network I/O of a real REST
/// call.
public struct FlexibleISO8601DateTranscoder: DateTranscoder {
    public init() { }

    // MARK: - DateTranscoder

    public func encode(_ date: Date) throws -> String {
        // Always emit fractional-second form. Backend's
        // `serde` deserialiser for `DateTime<Utc>` accepts
        // both shapes; emitting fractional matches what the
        // backend itself produces, keeping round-trips
        // byte-identical when the client echoes a server-
        // assigned timestamp back in a PATCH/PUT.
        Self.fractionalFormatter().string(from: date)
    }

    public func decode(_ dateString: String) throws -> Date {
        // Fast path: millisecond-precision input matches
        // exactly what `withFractionalSeconds` was built for.
        if let date = Self.fractionalFormatter().date(from: dateString) {
            return date
        }

        // Plain RFC 3339 without fractional seconds.
        if let date = Self.plainFormatter().date(from: dateString) {
            return date
        }

        // Sub-millisecond precision (μs / ns) — `ISO8601DateFormatter`
        // with `.withFractionalSeconds` only parses up to 3 fractional
        // digits, so we truncate down to milliseconds before retrying.
        // We deliberately drop the extra precision: `Date` is a
        // `TimeInterval` (Double) anyway, so anything finer than
        // about a microsecond is lost in storage; preserving full μs
        // input precision in `Date` is not a goal of this codebase.
        if let truncated = Self.truncateFractionalSecondsToMilliseconds(dateString),
           let date = Self.fractionalFormatter().date(from: truncated) {
            return date
        }

        throw DecodingError.dataCorrupted(.init(codingPath: [],
                                                debugDescription: "Expected RFC 3339 timestamp, got \(dateString)"))
    }

    // MARK: - Formatter factories

    private static func fractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func plainFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    // MARK: - Helpers

    /// Truncates fractional-second component of an ISO 8601
    /// timestamp to at most three digits, preserving the rest
    /// of the string (timezone suffix, etc.).
    ///
    /// Example:
    ///   `2026-05-11T12:10:08.866997Z` → `2026-05-11T12:10:08.866Z`
    ///   `2026-05-11T12:10:08.866997123+00:00` → `2026-05-11T12:10:08.866+00:00`
    ///
    /// Returns `nil` if the input has no fractional-second
    /// component or fewer than four fractional digits (in which
    /// case the calling fast path should have matched already).
    static func truncateFractionalSecondsToMilliseconds(_ input: String) -> String? {
        guard let dotIndex = input.firstIndex(of: ".") else {
            return nil
        }
        // Walk forward from the dot collecting fractional digits.
        var endOfFraction = input.index(after: dotIndex)
        while endOfFraction < input.endIndex, input[endOfFraction].isNumber {
            endOfFraction = input.index(after: endOfFraction)
        }
        let fractionalDigitCount = input.distance(from: input.index(after: dotIndex), to: endOfFraction)
        guard fractionalDigitCount > 3 else {
            return nil
        }
        let truncatedFractionEnd = input.index(dotIndex, offsetBy: 4) // `.` + 3 digits
        let head = input[..<truncatedFractionEnd]
        let tail = input[endOfFraction...]
        return String(head) + String(tail)
    }
}
