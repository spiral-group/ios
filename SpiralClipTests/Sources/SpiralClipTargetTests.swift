//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: Brief 0086 — the App Clip target.
//

import Foundation
@testable import SpiralClip
import Testing

struct SpiralClipTargetTests {
    @Test
    func theClipReadsTheAppGroupFromItsInfoPlist() {
        #expect(Bundle.main.object(forInfoDictionaryKey: ClipInviteHandOff.appGroupInfoPlistKey) as? String == "group.com.veruslogistics.messenger")
        #expect(ClipInviteHandOff(bundle: .main) != nil)
    }
    
    @Test
    func theClipTalksToItsBuildsServer() {
        #expect(ClipInviteLink.host == Self.buildServer)
        #expect(ClipInviteResolver.avatarURL("https://staging.spiral.md/og/u/alice", host: "staging.spiral.md") != nil)
        #expect(ClipInviteResolver.avatarURL("https://spiral.md/og/u/alice", host: "staging.spiral.md") == nil)
    }

    @Test
    func theClipIsTheAppsClip() {
        #expect(Bundle.main.bundleIdentifier == "com.veruslogistics.messenger.Clip")
    }

    /// SPIRAL_ASSOCIATED_DOMAIN, as `app.yml` sets it per configuration.
    private static var buildServer: String {
        #if SPIRAL_STAGING
        "staging.spiral.md"
        #else
        "spiral.md"
        #endif
    }
}
