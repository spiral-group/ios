//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: Brief 0086 — the App Clip's invitation hand-off.
//

import Foundation
@testable import Spiral
import Testing

struct ClipInviteHandOffTests {
    @Test
    func roundTripsThroughTheAppGroupDefaults() throws {
        let (handOff, defaults) = try makeHandOff()
        let invite = ClipInvite(token: "Qz8Hf72Kd91", inviterDisplayName: "Alice", inviterUserID: "@alice:spiral.md", savedAt: Self.savedAt)

        handOff.write(invite)

        #expect(handOff.read() == invite)
        let json = try #require(defaults.data(forKey: "spiral.clipInvite.v1").flatMap { String(data: $0, encoding: .utf8) })
        #expect(json.contains("\"savedAt\":\"2026-11-19T10:00:00Z\""), "savedAt is ISO-8601, as the contract says")
        #expect(json.contains("\"inviterUserID\":\"@alice:spiral.md\""))
        #expect(json.contains("\"host\":\"spiral.md\""), "the build's own server")
    }

    @Test
    func anInvitationWithoutItsServerReadsAsNothing() throws {
        let (handOff, defaults) = try makeHandOff()
        defaults.set(Data(#"{"token":"Qz8Hf72Kd91","savedAt":"2026-11-19T10:00:00Z"}"#.utf8), forKey: "spiral.clipInvite.v1")
        #expect(handOff.read() == nil)

        handOff.write(ClipInvite(token: "Qz8Hf72Kd91", host: "", savedAt: Self.savedAt))
        #expect(handOff.read() == nil)
    }

    @Test
    func readsTheContractsJSONAsTheClipWritesIt() throws {
        let (handOff, defaults) = try makeHandOff()
        defaults.set(Data(#"{"token":"TESTFLIGHT","host":"staging.spiral.md","savedAt":"2026-11-19T10:00:00Z"}"#.utf8), forKey: "spiral.clipInvite.v1")

        let invite = try #require(handOff.read())
        #expect(invite.token == "TESTFLIGHT")
        #expect(invite.host == "staging.spiral.md")
        #expect(invite.inviterDisplayName == nil)
        #expect(invite.inviterUserID == nil)
        #expect(invite.savedAt == Self.savedAt)
    }

    @Test
    func takeReturnsAFreshInvitationAndRemovesIt() throws {
        let (handOff, _) = try makeHandOff()
        handOff.write(ClipInvite(token: "Qz8Hf72Kd91", savedAt: Self.savedAt))

        #expect(handOff.take(now: Self.savedAt.addingTimeInterval(ClipInviteHandOff.lifetime - 1))?.token == "Qz8Hf72Kd91")
        #expect(handOff.read() == nil)
        #expect(handOff.take(now: Self.savedAt) == nil, "taken once")
    }

    @Test
    func takeDropsAnInvitationSevenDaysOldButStillRemovesIt() throws {
        let (handOff, _) = try makeHandOff()
        handOff.write(ClipInvite(token: "Qz8Hf72Kd91", savedAt: Self.savedAt))

        #expect(handOff.take(now: Self.savedAt.addingTimeInterval(7 * 24 * 60 * 60)) == nil)
        #expect(handOff.read() == nil)
    }

    @Test
    func expiryBoundary() {
        let invite = ClipInvite(token: "Qz8Hf72Kd91", savedAt: Self.savedAt)
        #expect(ClipInviteHandOff.isFresh(invite, now: Self.savedAt))
        #expect(ClipInviteHandOff.isFresh(invite, now: Self.savedAt.addingTimeInterval(-60)), "a clock change backwards")
        #expect(ClipInviteHandOff.isFresh(invite, now: Self.savedAt.addingTimeInterval(7 * 24 * 60 * 60 - 1)))
        #expect(!ClipInviteHandOff.isFresh(invite, now: Self.savedAt.addingTimeInterval(7 * 24 * 60 * 60)))
    }

    @Test
    func malformedJSONReadsAsNothingAndIsStillRemoved() throws {
        let (handOff, defaults) = try makeHandOff()
        defaults.set(Data(#"{"token":"Qz8Hf72Kd91","savedAt":"yesterday"}"#.utf8), forKey: "spiral.clipInvite.v1")
        #expect(handOff.read() == nil)

        defaults.set(Data("not json".utf8), forKey: "spiral.clipInvite.v1")
        #expect(handOff.read() == nil)

        defaults.set("a string, not data", forKey: "spiral.clipInvite.v1")
        #expect(handOff.take(now: Self.savedAt) == nil)
        #expect(defaults.object(forKey: "spiral.clipInvite.v1") == nil)
    }

    @Test
    func anInvalidTokenReadsAsNothing() throws {
        let (handOff, _) = try makeHandOff()
        handOff.write(ClipInvite(token: "abc", savedAt: Self.savedAt))
        #expect(handOff.read() == nil, "too short")

        handOff.write(ClipInvite(token: "has space", savedAt: Self.savedAt))
        #expect(handOff.read() == nil)
    }

    @Test
    func clearRemovesTheKey() throws {
        let (handOff, defaults) = try makeHandOff()
        handOff.write(ClipInvite(token: "Qz8Hf72Kd91", savedAt: Self.savedAt))
        handOff.clear()
        #expect(defaults.object(forKey: "spiral.clipInvite.v1") == nil)
    }

    @Test
    func theAppReadsTheAppGroupAndServerFromItsInfoPlist() {
        #expect(ClipInviteLink.host == SpiralLink.serverName, "the app's environment, as the Clip's")
        #expect(ClipInviteHandOff(bundle: .main) != nil)
        #expect(Bundle.main.object(forInfoDictionaryKey: ClipInviteHandOff.appGroupInfoPlistKey) as? String == InfoPlistReader.main.appGroupIdentifier)
    }

    // MARK: - The token parser, a copy of SpiralInviteLink's

    @Test
    func parsesTheSameLinksAsSpiralInviteLink() throws {
        let links = ["https://spiral.md/join/Qz8Hf72Kd91",
                     "https://SPIRAL.md/join/TESTFLIGHT",
                     "spiral://join/Qz8Hf72Kd91",
                     "spiral:///join/Qz8Hf72Kd91",
                     "https://spiral.md/@alice",
                     "https://spiral.md/join",
                     "https://spiral.md/join/a/b",
                     "https://evil.example/join/Qz8Hf72Kd91",
                     "https://spiral.md/join/abc",
                     "https://spiral.md/join/has%20space",
                     "https://spiral.md/join/\(String(repeating: "a", count: 65))",
                     "http://spiral.md/join/Qz8Hf72Kd91"]

        for link in links {
            let url = try #require(URL(string: link))
            #expect(ClipInviteLink.token(from: url) == SpiralInviteLink.parse(url)?.token, "\(link)")
        }
        #expect(try ClipInviteLink.token(from: #require(URL(string: "https://spiral.md/join/Qz8Hf72Kd91"))) == "Qz8Hf72Kd91")
        #expect(try ClipInviteLink.token(from: #require(URL(string: "https://spiral.md/join/abc"))) == nil)
    }

    @Test
    func aStagingBuildParsesStagingLinksOnly() throws {
        let staging = try #require(URL(string: "https://staging.spiral.md/join/Qz8Hf72Kd91"))
        let prod = try #require(URL(string: "https://spiral.md/join/Qz8Hf72Kd91"))
        #expect(ClipInviteLink.token(from: staging, host: "staging.spiral.md") == "Qz8Hf72Kd91")
        #expect(ClipInviteLink.token(from: prod, host: "staging.spiral.md") == nil)
        #expect(ClipInviteLink.webURL(token: "Qz8Hf72Kd91", host: "staging.spiral.md") == staging)
    }

    @Test
    func buildsBothURLForms() {
        #expect(ClipInviteLink.webURL(token: "Qz8Hf72Kd91")?.absoluteString == "https://spiral.md/join/Qz8Hf72Kd91")
        #expect(ClipInviteLink.schemeURL(token: "Qz8Hf72Kd91")?.absoluteString == "spiral://join/Qz8Hf72Kd91")
    }

    // MARK: - Helpers

    private static let savedAt = Date(timeIntervalSince1970: 1_795_082_400) // 2026-11-19T10:00:00Z

    private func makeHandOff() throws -> (ClipInviteHandOff, UserDefaults) {
        let suiteName = "ClipInviteHandOffTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (ClipInviteHandOff(defaults: defaults), defaults)
    }
}
