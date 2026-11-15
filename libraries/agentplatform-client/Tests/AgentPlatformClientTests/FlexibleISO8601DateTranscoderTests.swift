//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// Coverage for FlexibleISO8601DateTranscoder. The default
// `ISO8601DateTranscoder` baked into OpenAPIRuntime rejects
// any fractional-second precision in incoming timestamps,
// which breaks every endpoint that surfaces a chrono::DateTime
// from the Rust backend. These tests pin the wider precision
// matrix we accept (plain, ms, μs, ns), kept to the microsecond,
// and confirm the encoder gives the server back its own instant.

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
                       Self.expectedTimeIntervalSince1970(seconds: 8, fractional: 0.866997),
                       accuracy: 0.0000005)
    }

    func testDecodesNanosecondPrecisionToTheMicrosecond() throws {
        let date = try transcoder.decode("2026-05-11T12:10:08.866997123Z")
        XCTAssertEqual(date.timeIntervalSince1970,
                       Self.expectedTimeIntervalSince1970(seconds: 8, fractional: 0.866997),
                       accuracy: 0.0000005)
    }

    func testDecodesAnOffset() throws {
        let date = try transcoder.decode("2026-05-11T14:10:08.866997+02:00")
        XCTAssertEqual(try transcoder.encode(date), "2026-05-11T12:10:08.866997Z")
    }

    func testDecodeRejectsGarbage() {
        XCTAssertThrowsError(try transcoder.decode("not a date"))
        XCTAssertThrowsError(try transcoder.decode(""))
        XCTAssertThrowsError(try transcoder.decode("2026-05-11"))
        XCTAssertThrowsError(try transcoder.decode("2026-05-11T12:10:08.Z"))
    }

    // MARK: - Encode

    func testEncodeEmitsMicrosecondPrecisionUTC() throws {
        let encoded = try transcoder.encode(Date(timeIntervalSince1970: 1_778_581_808.123))
        XCTAssertEqual(encoded, "2026-05-12T10:30:08.123000Z")
    }

    /// The feed's seen mark (Brief 0082, FD10) echoes the newest activity entry's `at`: a
    /// millisecond echo fell just before the entry, which then stayed unread.
    func testAServerTimestampRoundTripsExactly() throws {
        for timestamp in ["2026-10-30T09:12:00.123456Z", "2026-10-30T09:12:00.999999Z", "2026-10-30T09:12:00.000001Z",
                          "2026-10-30T23:59:59.987654Z", "2026-10-30T09:12:00.000000Z", "1969-12-31T23:59:59.500001Z"] {
            XCTAssertEqual(try transcoder.encode(transcoder.decode(timestamp)), timestamp)
        }
        // Every microsecond of a second, around now.
        for microsecond in stride(from: 0, to: 1_000_000, by: 997) {
            let digits = String(microsecond)
            let timestamp = "2026-10-30T09:12:07." + String(repeating: "0", count: 6 - digits.count) + digits + "Z"
            XCTAssertEqual(try transcoder.encode(transcoder.decode(timestamp)), timestamp)
        }
    }

    func testAPlainTimestampGainsZeroMicroseconds() throws {
        XCTAssertEqual(try transcoder.encode(transcoder.decode("2026-05-11T12:10:08Z")), "2026-05-11T12:10:08.000000Z")
    }

    // MARK: - Fractional seconds

    func testSplitKeepsSixFractionalDigits() {
        let split = FlexibleISO8601DateTranscoder.splitFraction("2026-05-11T12:10:08.8669971+02:00")
        XCTAssertEqual(split?.whole, "2026-05-11T12:10:08+02:00")
        XCTAssertEqual(split?.microseconds, 866_997)
    }

    func testSplitPadsShortFractions() {
        XCTAssertEqual(FlexibleISO8601DateTranscoder.splitFraction("2026-05-11T12:10:08.12Z")?.microseconds, 120_000)
        XCTAssertEqual(FlexibleISO8601DateTranscoder.splitFraction("2026-05-11T12:10:08Z")?.microseconds, 0)
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
