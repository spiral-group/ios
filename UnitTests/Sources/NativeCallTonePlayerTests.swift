//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Spiral
import Testing

// AGENT-PLATFORM (Brief 0063): call sessions in this target reach the real tone
// player, so the run itself must keep it silent.

@MainActor
struct NativeCallTonePlayerTests {
    /// Set by `UnitTestsAppCoordinator` before any test runs: without it a ringback loops out of the Mac.
    @Test
    func theTestRunTurnsTheToneOutputOff() {
        #expect(!NativeCallTonePlayer.isOutputEnabled)
    }

    /// Everything up to the hardware still runs: the tone is synthesised and loaded, only never played.
    @Test
    func aToneIsLoadedButNotHeard() {
        let player = NativeCallTonePlayer()

        for tone in [NativeCallTone.ringback, .busy, .connected, .ended, .reconnecting] {
            player.play(tone)
            #expect(player.tone == tone)
            #expect(!player.isAudible, "\(tone) started playing")
        }

        player.stop()
        #expect(player.tone == nil)
    }
}
