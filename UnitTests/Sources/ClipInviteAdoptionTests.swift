//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: Brief 0086 — the app adopts the App Clip's invitation.
//

import Foundation
@testable import Spiral
import Testing

struct ClipInviteAdoptionTests {
    /// A launch with no session asks again about whatever invitation it holds — adopted now or launches ago, from
    /// the Clip or a tapped link — so a bare token gets its inviter and a used-up one loses its banner. Signed in, never.
    @Test
    func everyLaunchWithNoSessionRechecksTheInvitation() {
        let bare = PendingInvite(token: "Qz8Hf72Kd91")
        #expect(ClipInviteAdoption.inviteToRecheck(bare, hasSession: false)?.token == "Qz8Hf72Kd91")
        let named = PendingInvite(token: "Qz8Hf72Kd91", inviterDisplayName: "Andrii", inviterUserID: "@andrii:spiral.md")
        #expect(ClipInviteAdoption.inviteToRecheck(named, hasSession: false)?.token == "Qz8Hf72Kd91")
        #expect(ClipInviteAdoption.inviteToRecheck(named, hasSession: true) == nil)
        #expect(ClipInviteAdoption.inviteToRecheck(nil, hasSession: false) == nil)
    }

    @Test
    func aLaunchWithNoSessionAdoptsTheClipsInvitationWithItsInviter() {
        let invite = ClipInviteAdoption.pendingInvite(from: Self.clipInvite, existing: nil, hasSession: false)
        #expect(invite == PendingInvite(token: "Qz8Hf72Kd91", inviterDisplayName: "Alice", inviterUserID: "@alice:spiral.md"))
    }

    @Test
    func aCampaignInvitationHasNoInviter() {
        let campaign = ClipInvite(token: "TESTFLIGHT", savedAt: .now)
        #expect(ClipInviteAdoption.pendingInvite(from: campaign, existing: nil, hasSession: false) == PendingInvite(token: "TESTFLIGHT"))
    }

    @Test
    func aPendingInviteTheAppAlreadyHoldsWins() {
        let existing = PendingInvite(token: "OtherToken1")
        #expect(ClipInviteAdoption.pendingInvite(from: Self.clipInvite, existing: existing, hasSession: false) == nil)
    }

    @Test
    func aLaunchWithASessionAdoptsNothing() {
        #expect(ClipInviteAdoption.pendingInvite(from: Self.clipInvite, existing: nil, hasSession: true) == nil)
    }

    @Test
    func anInvitationForTheOtherEnvironmentIsNotAdopted() {
        let prodInvite = ClipInvite(token: "Qz8Hf72Kd91", host: "spiral.md", savedAt: .now)
        let stagingInvite = ClipInvite(token: "Qz8Hf72Kd91", host: "staging.spiral.md", savedAt: .now)

        #expect(ClipInviteAdoption.pendingInvite(from: prodInvite, existing: nil, hasSession: false, serverName: "staging.spiral.md") == nil)
        #expect(ClipInviteAdoption.pendingInvite(from: stagingInvite, existing: nil, hasSession: false, serverName: "spiral.md") == nil)
        #expect(ClipInviteAdoption.pendingInvite(from: stagingInvite, existing: nil, hasSession: false, serverName: "staging.spiral.md")?.token == "Qz8Hf72Kd91")
        #expect(ClipInviteAdoption.pendingInvite(from: prodInvite, existing: nil, hasSession: false, serverName: "spiral.md")?.token == "Qz8Hf72Kd91")
    }

    @Test
    func noClipInvitationAdoptsNothing() {
        #expect(ClipInviteAdoption.pendingInvite(from: nil, existing: nil, hasSession: false) == nil)
    }

    @Test
    func theAdoptedInvitationReachesTheStartScreensSetting() throws {
        let appSettings = AppSettings.volatile()
        let pendingInvite = try #require(ClipInviteAdoption.pendingInvite(from: Self.clipInvite, existing: appSettings.pendingInvite, hasSession: false))
        appSettings.pendingInvite = pendingInvite
        #expect(appSettings.pendingInvite?.inviterDisplayName == "Alice")
        #expect(appSettings.pendingInvite?.link?.webURL.absoluteString == "https://spiral.md/join/Qz8Hf72Kd91")
    }

    @Test
    func theClipsInviterIsOnlyAFirstPaintAndIsChecked() {
        let invite = ClipInvite(token: "Qz8Hf72Kd91",
                                inviterDisplayName: "  " + String(repeating: "A", count: 200),
                                inviterUserID: "not an id",
                                savedAt: .now)
        let pendingInvite = ClipInviteAdoption.pendingInvite(from: invite, existing: nil, hasSession: false)
        #expect(pendingInvite?.inviterDisplayName == String(repeating: "A", count: ClipInviteAdoption.maximumDisplayNameLength))
        #expect(pendingInvite?.inviterUserID == nil)

        for userID in ["@alice", "@:spiral.md", "alice:spiral.md", "@al ice:spiral.md"] {
            let invite = ClipInvite(token: "Qz8Hf72Kd91", inviterUserID: userID, savedAt: .now)
            #expect(ClipInviteAdoption.pendingInvite(from: invite, existing: nil, hasSession: false)?.inviterUserID == nil, "\(userID)")
        }
    }

    // MARK: - The server's answer after the adoption

    @Test
    func aBareTokenGetsItsInviterFromTheServer() async throws {
        let appSettings = AppSettings.volatile()
        appSettings.pendingInvite = ClipInviteAdoption.pendingInvite(from: ClipInvite(token: "Qz8Hf72Kd91", savedAt: .now),
                                                                     existing: nil,
                                                                     hasSession: false)
        let resolver = InviteLinkResolverMock()
        resolver.resolveReturnValue = .success(.valid(inviter: InviteInviter(displayName: "Alice", avatarURL: nil, mxid: "@alice:spiral.md")))

        try await PendingInviteRefresh.refresh(#require(appSettings.pendingInvite?.link), resolver: resolver, appSettings: appSettings)

        #expect(appSettings.pendingInvite == PendingInvite(token: "Qz8Hf72Kd91", inviterDisplayName: "Alice", inviterUserID: "@alice:spiral.md"))
    }

    @Test
    func anInvitationUsedUpMeanwhileIsDropped() async throws {
        for state in [InviteLinkState.exhausted, .expired, .invalid] {
            let appSettings = AppSettings.volatile()
            appSettings.pendingInvite = ClipInviteAdoption.pendingInvite(from: Self.clipInvite, existing: nil, hasSession: false)
            let resolver = InviteLinkResolverMock()
            resolver.resolveReturnValue = .success(state)

            try await PendingInviteRefresh.refresh(#require(appSettings.pendingInvite?.link), resolver: resolver, appSettings: appSettings)

            #expect(appSettings.pendingInvite == nil, "\(state)")
        }
    }

    @Test
    func aFailedCheckKeepsTheClipsInvitation() async throws {
        let appSettings = AppSettings.volatile()
        appSettings.pendingInvite = ClipInviteAdoption.pendingInvite(from: Self.clipInvite, existing: nil, hasSession: false)
        let resolver = InviteLinkResolverMock()
        resolver.resolveReturnValue = .failure(.network)

        try await PendingInviteRefresh.refresh(#require(appSettings.pendingInvite?.link), resolver: resolver, appSettings: appSettings)

        #expect(appSettings.pendingInvite?.inviterDisplayName == "Alice")
    }

    @Test
    func anAnswerForAnInvitationReplacedMeanwhileChangesNothing() async throws {
        let appSettings = AppSettings.volatile()
        let link = try #require(SpiralInviteLink(token: "Qz8Hf72Kd91"))
        appSettings.pendingInvite = PendingInvite(token: "OtherToken1")
        let resolver = InviteLinkResolverMock()
        resolver.resolveReturnValue = .success(.invalid)

        await PendingInviteRefresh.refresh(link, resolver: resolver, appSettings: appSettings)

        #expect(appSettings.pendingInvite == PendingInvite(token: "OtherToken1"))
    }

    /// Why `AppCoordinator` takes the invitation before its migrations: a first launch resets the app's
    /// settings, which removes the whole App Group domain, the Clip's key with it.
    @Test
    func aSettingsResetRemovesTheClipsKey() throws {
        let suiteName = "ClipInviteAdoptionTests.\(UUID().uuidString)"
        let defaults = try #require(TrackedUserDefaults(suiteName: suiteName))
        ClipInviteHandOff(defaults: defaults).write(Self.clipInvite)
        #expect(ClipInviteHandOff(defaults: defaults).read() != nil)

        AppSettings(store: defaults).resetAllSettings()

        #expect(ClipInviteHandOff(defaults: defaults).read() == nil)
    }

    // MARK: - Helpers

    private static let clipInvite = ClipInvite(token: "Qz8Hf72Kd91",
                                               inviterDisplayName: "Alice",
                                               inviterUserID: "@alice:spiral.md",
                                               savedAt: .now)
}
