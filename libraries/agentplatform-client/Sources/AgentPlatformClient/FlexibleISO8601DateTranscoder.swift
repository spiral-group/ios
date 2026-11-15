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
// This transcoder accepts any fractional precision on decode and keeps
// it to the microsecond, the backend's own precision:
//
//   * `2026-05-11T12:10:08Z`        (no fractional seconds)
//   * `2026-05-11T12:10:08.123Z`    (millisecond precision)
//   * `2026-05-11T12:10:08.866997Z` (microsecond precision)
//   * `2026-05-11T12:10:08.866997123Z` (nanosecond precision, cut to μs)
//
// On encode it emits microseconds (`.866997Z`), so a timestamp the
// client echoes back is the server's own instant. Millisecond output
// once put the feed's seen mark (`POST /feed/activity/seen` with the
// newest entry's `at`) just before that entry, which then stayed unread
// for ever (Brief 0082, FD10).
//
// Wire this into the generated client via
// `Configuration(dateTranscoder:)` in `AgentPlatformClient.init`;
// the generator routes every `format: date-time` field through
// `Configuration.dateTranscoder` automatically.

import Foundation
import OpenAPIRuntime

/// `DateTranscoder` that accepts ISO 8601 / RFC 3339 timestamps with
/// any fractional-second precision on decode, keeping microseconds,
/// and emits microsecond-precision UTC timestamps on encode.
///
/// A `Date` is a `Double` of seconds: around now its step is under a
/// quarter of a microsecond, so a microsecond survives the round trip
/// when it is rounded back on encode.
///
/// Thread-safe: every call constructs its own `ISO8601DateFormatter`.
/// The formatters are not `Sendable`, and `DateTranscoder` requires
/// `Sendable` conformance — keeping no stored properties sidesteps the
/// issue entirely. The allocation is cheap next to the network I/O of a
/// real REST call.
public struct FlexibleISO8601DateTranscoder: DateTranscoder {
    private static let microsecondsPerSecond: Int64 = 1_000_000

    public init() { }

    // MARK: - DateTranscoder

    public func encode(_ date: Date) throws -> String {
        let microseconds = Int64((date.timeIntervalSince1970 * Double(Self.microsecondsPerSecond)).rounded())
        let (seconds, fraction) = Self.floorDivision(microseconds, by: Self.microsecondsPerSecond)
        let whole = Self.plainFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
        // The plain formatter writes UTC as `…:08Z`; the fraction goes before the `Z`.
        return whole.dropLast() + "." + Self.sixDigits(fraction) + "Z"
    }

    public func decode(_ dateString: String) throws -> Date {
        guard let (whole, microseconds) = Self.splitFraction(dateString),
              let date = Self.plainFormatter().date(from: whole) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [],
                                                    debugDescription: "Expected RFC 3339 timestamp, got \(dateString)"))
        }
        let total = Int64(date.timeIntervalSince1970) * Self.microsecondsPerSecond + microseconds
        return Date(timeIntervalSince1970: Double(total) / Double(Self.microsecondsPerSecond))
    }

    // MARK: - Helpers

    private static func plainFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    /// The timestamp without its fractional seconds, and those seconds in
    /// whole microseconds (digits past the sixth dropped).
    ///
    /// Example: `2026-05-11T12:10:08.8669971+02:00` → (`2026-05-11T12:10:08+02:00`, 866997).
    /// `nil` for a `.` with no digit after it.
    static func splitFraction(_ input: String) -> (whole: String, microseconds: Int64)? {
        guard let dotIndex = input.firstIndex(of: ".") else {
            return (input, 0)
        }
        let fractionStart = input.index(after: dotIndex)
        let fractionEnd = input[fractionStart...].firstIndex { !$0.isASCII || !$0.isNumber } ?? input.endIndex
        let digits = input[fractionStart..<fractionEnd]
        guard !digits.isEmpty else { return nil }
        let micro = String(digits.prefix(6)).padding(toLength: 6, withPad: "0", startingAt: 0)
        guard let microseconds = Int64(micro) else { return nil }
        return (String(input[..<dotIndex]) + String(input[fractionEnd...]), microseconds)
    }

    private static func floorDivision(_ value: Int64, by divisor: Int64) -> (quotient: Int64, remainder: Int64) {
        let (quotient, remainder) = value.quotientAndRemainder(dividingBy: divisor)
        return remainder < 0 ? (quotient - 1, remainder + divisor) : (quotient, remainder)
    }

    private static func sixDigits(_ value: Int64) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, 6 - digits.count)) + digits
    }
}
