//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// Coverage for FlexibleISO8601DateTranscoder. The default
// `ISO8601DateTranscoder` baked into OpenAPIRuntime rejects
// any fractional-second precision in incoming timestamps,
// which breaks every endpoint that surfaces a chrono::DateTime
// from the Rust backend. These tests pin the wider precision
// matrix we accept (plain, ms, μs, ns) and confirm the encoder
// emits a stable, RFC 3339-compliant millisecond form.

@testable import AgentPlatformClient
import XCTest

final class FlexibleISO8601DateTranscoderTests: XCTestCase {
    private let transcoder = FlexibleISO8601DateTranscoder()

    // MARK: - Decode

    func testDecodesPlainSecondsPrecision() throws {
        let date = try transcoder.decode("2026-05-11T12:10:08Z")
        let components = Self.components(from: date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 5)
        XCTAssertEqual(components.day, 11)
        XCTAssertEqual(components.hour, 12)
        XCTAssertEqual(components.minute, 10)
        XCTAssertEqual(components.second, 8)
    }

    func testDecodesMillisecondPrecision() throws {
        let date = try transcoder.decode("2026-05-11T12:10:08.123Z")
        XCTAssertEqual(date.timeIntervalSince1970,
                       Self.expectedTimeIntervalSince1970(seconds: 8, fractional: 0.123),
                       accuracy: 0.0005)
    }

    func testDecodesMicrosecondPrecisionFromBackend() throws {
        // Exact shape observed from the Rust backend in the
        // smoke run that motivated this transcoder.
        let date = try transcoder.decode("2026-05-11T12:10:08.866997Z")
        XCTAssertEqual(date.timeIntervalSince1970,
                       Self.expectedTimeIntervalSince1970(seconds: 8, fractional: 0.866),
                       accuracy: 0.001)
    }

    func testDecodesNanosecondPrecision() throws {
        let date = try transcoder.decode("2026-05-11T12:10:08.866997123Z")
        XCTAssertEqual(date.timeIntervalSince1970,
                       Self.expectedTimeIntervalSince1970(seconds: 8, fractional: 0.866),
                       accuracy: 0.001)
    }

    func testDecodeRejectsGarbage() {
        XCTAssertThrowsError(try transcoder.decode("not a date"))
        XCTAssertThrowsError(try transcoder.decode(""))
        XCTAssertThrowsError(try transcoder.decode("2026-05-11"))
    }

    // MARK: - Encode

    func testEncodeEmitsMillisecondPrecisionUTC() throws {
        // Pick a date with a precisely representable fractional
        // component so encode is deterministic.
        let date = Date(timeIntervalSince1970: 1_778_581_808.123)
        let encoded = try transcoder.encode(date)
        // Foundation's ISO 8601 formatter renders in UTC when
        // `.withInternetDateTime` is set and never localises;
        // assert the full RFC 3339 shape so a future regression
        // to non-UTC output (or a missing fractional component)
        // fails loudly.
        let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$"#
        XCTAssertNotNil(encoded.range(of: pattern, options: .regularExpression),
                        "Encoded value '\(encoded)' did not match RFC 3339 UTC millisecond shape")
    }

    func testRoundTripPreservesMillisecondPrecision() throws {
        let original = Date(timeIntervalSince1970: 1_778_581_808.123)
        let encoded = try transcoder.encode(original)
        let decoded = try transcoder.decode(encoded)
        XCTAssertEqual(decoded.timeIntervalSince1970,
                       original.timeIntervalSince1970,
                       accuracy: 0.001)
    }

    // MARK: - Fractional-second truncation helper

    func testTruncateRetainsThreeFractionalDigits() {
        let input = "2026-05-11T12:10:08.866997Z"
        let truncated = FlexibleISO8601DateTranscoder.truncateFractionalSecondsToMilliseconds(input)
        XCTAssertEqual(truncated, "2026-05-11T12:10:08.866Z")
    }

    func testTruncateHandlesOffsetTimezone() {
        let input = "2026-05-11T12:10:08.866997123+02:00"
        let truncated = FlexibleISO8601DateTranscoder.truncateFractionalSecondsToMilliseconds(input)
        XCTAssertEqual(truncated, "2026-05-11T12:10:08.866+02:00")
    }

    func testTruncateReturnsNilWhenAlreadyMillisecondOrCoarser() {
        XCTAssertNil(FlexibleISO8601DateTranscoder.truncateFractionalSecondsToMilliseconds("2026-05-11T12:10:08.866Z"))
        XCTAssertNil(FlexibleISO8601DateTranscoder.truncateFractionalSecondsToMilliseconds("2026-05-11T12:10:08Z"))
    }

    // MARK: - Helpers

    private static func components(from date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                       from: date)
    }

    /// Computes the expected `timeIntervalSince1970` for
    /// `2026-05-11T12:10:08.<fractional>Z`, given the integer
    /// seconds component and a fractional offset. Keeps the
    /// fixture readable while still anchoring on a deterministic
    /// epoch value.
    private static func expectedTimeIntervalSince1970(seconds: Int, fractional: Double) -> TimeInterval {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 11
        components.hour = 12
        components.minute = 10
        components.second = seconds
        components.timeZone = TimeZone(identifier: "UTC")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let base = calendar.date(from: components) else {
            return 0
        }
        return base.timeIntervalSince1970 + fractional
    }
}
