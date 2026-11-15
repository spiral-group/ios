//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Foundation
@testable import Spiral
import Testing

/// The motion core behind the call's voice drawings: a spring that stays smooth between the SFU's 400 ms steps, a
/// loudness scale that moves for ordinary speech, and a rest state that lets a drawing stop in silence.
struct NativeCallVoiceMotionTests {
    // MARK: - The spring

    @Test
    func aStepIsFollowedSmoothlyWithoutOvershoot() {
        var spring = NativeCallVoiceSpring()
        var previous = spring.value
        for _ in 0..<60 {
            spring.advance(toward: 0.8, by: 1.0 / 60.0)
            #expect(spring.value >= previous, "a rise never dips back")
            #expect(spring.value <= 0.8, "critically damped: no overshoot from rest")
            previous = spring.value
        }
        #expect(spring.value > 0.79, "the rise arrives within a second")
    }

    /// One frame does not jump to the target: the rise is spread over several frames, which is what makes a 400 ms
    /// step look like motion rather than a cut.
    @Test
    func oneFrameDoesNotJumpToTheTarget() {
        var spring = NativeCallVoiceSpring()
        spring.advance(toward: 1, by: 1.0 / 60.0)
        #expect(spring.value > 0)
        #expect(spring.value < 0.25)
    }

    @Test
    func aRiseIsQuickerThanAFall() {
        var rising = NativeCallVoiceSpring()
        rising.advance(toward: 1, by: 0.1)

        var falling = NativeCallVoiceSpring()
        falling.advance(toward: 1, by: 5)
        falling.advance(toward: 0, by: 0.1)

        #expect(rising.value > 1 - falling.value, "speech starts sharply and trails off")
    }

    @Test
    func theResultDoesNotDependOnTheFrameRate() {
        var at30 = NativeCallVoiceSpring()
        var at60 = NativeCallVoiceSpring()
        var at120 = NativeCallVoiceSpring()
        for _ in 0..<30 {
            at30.advance(toward: 0.6, by: 1.0 / 30.0)
            for _ in 0..<2 {
                at60.advance(toward: 0.6, by: 1.0 / 60.0)
            }
            for _ in 0..<4 {
                at120.advance(toward: 0.6, by: 1.0 / 120.0)
            }
        }
        #expect(abs(at30.value - at60.value) < 1e-9)
        #expect(abs(at60.value - at120.value) < 1e-9)
    }

    @Test
    func aLongHitchLandsOnTheTarget() {
        var spring = NativeCallVoiceSpring()
        spring.advance(toward: 0.7, by: 0.05)
        spring.advance(toward: 0.7, by: 30)
        #expect(abs(spring.value - 0.7) < 1e-6)
        #expect(spring.isSettled(at: 0.7))
    }

    @Test
    func nonsenseInputChangesNothingOrReadsAsSilence() {
        var spring = NativeCallVoiceSpring()
        spring.advance(toward: 0.5, by: 0.2)
        let value = spring.value

        spring.advance(toward: 0.9, by: 0)
        spring.advance(toward: 0.9, by: -1)
        spring.advance(toward: 0.9, by: .nan)
        #expect(spring.value == value)

        spring.advance(toward: .nan, by: 10)
        #expect(spring.value.isFinite)
        #expect(abs(spring.value) < 1e-6, "a non-finite level is silence")
    }

    // MARK: - Loudness

    /// LiveKit's levels for ordinary talk (`10^(dBov/20)`, a report every 400 ms, 0 between phrases) must move the
    /// drawings clearly, not only a shout.
    @Test
    func normalSpeechReachesAVisibleLevel() {
        var loudness = NativeCallVoiceLoudness()
        let mapped = feed(&loudness, decibels: [-30, -26, -28, -24, -27, -29, -25, -26])
        #expect(mapped.allSatisfy { $0 > 0.45 }, "every report of ordinary talk is visible: \(mapped)")
        #expect((mapped.max() ?? 0) > 0.75, "and its louder words reach high")
    }

    /// A quiet talker or a far microphone: the scale follows their recent loudness, so they drive the motion too.
    @Test
    func aQuietTalkerIsLiftedWithinSeconds() {
        var loudness = NativeCallVoiceLoudness()
        let mapped = feed(&loudness, decibels: Array(repeating: [-36.0, -33, -35, -34], count: 4).flatMap(\.self))
        #expect(mapped.first ?? 1 < mapped.last ?? 0, "the scale adapts")
        #expect((mapped.suffix(4).max() ?? 0) > 0.75, "after a few seconds a quiet voice moves like a normal one")
    }

    /// A shout reaches the top at once, and its scale catches up so it doesn't sit flat at the maximum.
    @Test
    func shoutingReachesTheTopWithoutStickingThere() {
        var loudness = NativeCallVoiceLoudness()
        let mapped = feed(&loudness, decibels: Array(repeating: [-12.0, -16, -10, -15], count: 3).flatMap(\.self))
        #expect((mapped.first ?? 0) > 0.95, "the first shout is at the top")
        let settled = mapped.suffix(8)
        #expect((settled.max() ?? 0) - (settled.min() ?? 0) > 0.12, "a held shout still varies: \(settled)")
        #expect(settled.contains { $0 < 1 })
    }

    /// The scale has a floor: near-silence a client might pass on is never blown up into motion.
    @Test
    func faintNoiseStaysCalm() {
        var loudness = NativeCallVoiceLoudness()
        let mapped = feed(&loudness, decibels: Array(repeating: -58, count: 50))
        #expect((mapped.max() ?? 1) < 0.25, "faint input stays low however long it lasts: \(mapped.suffix(3))")
        #expect(feed(&loudness, decibels: [-75]).first == 0)
    }

    @Test
    func silenceIsZeroAndKeepsTheScale() {
        var loudness = NativeCallVoiceLoudness()
        _ = feed(&loudness, decibels: Array(repeating: -34, count: 12))
        let before = feed(&loudness, decibels: [-34]).first ?? 0
        for _ in 0..<50 {
            #expect(loudness.perceived(0, after: 0.4) == 0)
        }
        #expect(loudness.perceived(.nan, after: 0.4) == 0)
        #expect(loudness.perceived(-1, after: 0.4) == 0)
        let after = feed(&loudness, decibels: [-34]).first ?? 0
        #expect(abs(after - before) < 0.02, "the next phrase starts on the scale the last one ended on")
    }

    @Test
    func theScaleDoesNotDependOnHowOftenItIsRead() {
        var at10 = NativeCallVoiceLoudness()
        var at60 = NativeCallVoiceLoudness()
        let amplitude = pow(10, -34.0 / 20)
        for _ in 0..<30 {
            _ = at10.perceived(amplitude, after: 0.1)
            for _ in 0..<6 {
                _ = at60.perceived(amplitude, after: 1.0 / 60.0)
            }
        }
        #expect(abs(at10.perceived(amplitude, after: 0) - at60.perceived(amplitude, after: 0)) < 1e-9)
    }

    // MARK: - Flutter

    @Test
    func theFlutterStaysInRangeAndMoves() {
        let samples = stride(from: 0.0, to: 4.0, by: 1.0 / 60.0).map { NativeCallVoiceFlutter.value(at: $0) }
        #expect(samples.allSatisfy { $0 >= -1 && $0 <= 1 })
        #expect((samples.max() ?? 0) - (samples.min() ?? 0) > 1, "it visibly wobbles")
        #expect(NativeCallVoiceFlutter.value(at: 1.3, seed: 0) != NativeCallVoiceFlutter.value(at: 1.3, seed: 1))
    }

    // MARK: - The drawing's state

    @Test
    func theDrawingFollowsTheVoiceAndComesToRestInSilence() async {
        let motion = NativeCallVoiceMotion()
        var time = 100.0
        var frame = motion.frame(at: time, amplitude: 0)
        #expect(frame.energy == 0)

        for _ in 0..<30 {
            time += 1.0 / 60.0
            frame = motion.frame(at: time, amplitude: 0.06)
        }
        #expect(frame.energy > 0.5)
        #expect(frame.travel > 0, "the pattern moves while someone speaks")
        await yieldToMainActor()
        #expect(!motion.isAtRest)

        for _ in 0..<180 {
            time += 1.0 / 60.0
            frame = motion.frame(at: time, amplitude: 0)
        }
        let travelAtRest = frame.travel
        #expect(frame.energy < 0.002)
        await yieldToMainActor()
        #expect(motion.isAtRest)

        time += 1
        frame = motion.frame(at: time, amplitude: 0)
        #expect(frame.travel == travelAtRest, "silence holds the pattern still")
    }

    /// The gaps between words keep the drawing at display rate: switching rates on every pause would stutter.
    @Test
    func aPauseBetweenWordsDoesNotPutTheDrawingToRest() async {
        let motion = NativeCallVoiceMotion(restDelay: 1)
        var time = 0.0
        for _ in 0..<30 {
            time += 1.0 / 60.0
            _ = motion.frame(at: time, amplitude: 0.06)
        }
        // Six tenths of a second of silence: the spring settles, the drawing keeps its pace.
        for _ in 0..<36 {
            time += 1.0 / 60.0
            _ = motion.frame(at: time, amplitude: 0)
        }
        await yieldToMainActor()
        #expect(!motion.isAtRest)

        for _ in 0..<60 {
            time += 1.0 / 60.0
            _ = motion.frame(at: time, amplitude: 0)
        }
        await yieldToMainActor()
        #expect(motion.isAtRest)
    }

    /// At rest a drawing pauses; the ten-a-second poll wakes it when a voice comes back, and only then.
    @Test
    func thePollWakesARestingDrawingWhenAVoiceComesBack() async {
        let motion = NativeCallVoiceMotion(restDelay: 0)
        #expect(motion.isAtRest, "a new drawing starts at rest, paused")

        var reads = 0
        await motion.pollWhileAtRest {
            reads += 1
            return reads < 3 ? 0 : 0.05
        }
        #expect(!motion.isAtRest, "the voice woke it")
        #expect(reads == 3, "silence kept it asleep until then")
    }

    /// Reduce Motion: the drawing follows speaking or not, never the loudness, so nothing pulses with syllables.
    @Test
    func speakingOnlyIgnoresTheLoudness() {
        let quiet = NativeCallVoiceMotion()
        let loud = NativeCallVoiceMotion()
        var time = 0.0
        var quietFrame = quiet.frame(at: time, amplitude: 0.02, speakingOnly: true)
        var loudFrame = loud.frame(at: time, amplitude: 0.3, speakingOnly: true)
        for _ in 0..<20 {
            time += 1.0 / 30.0
            quietFrame = quiet.frame(at: time, amplitude: 0.02, speakingOnly: true)
            loudFrame = loud.frame(at: time, amplitude: 0.3, speakingOnly: true)
        }
        #expect(quietFrame.energy == loudFrame.energy)
        #expect(quietFrame.energy > 0.9)
    }

    @Test
    func aGapInFramesDoesNotLeapThePattern() {
        let motion = NativeCallVoiceMotion(speechSpeed: 2)
        _ = motion.frame(at: 0, amplitude: 0.2)
        for step in 1...60 {
            _ = motion.frame(at: Double(step) / 60.0, amplitude: 0.2)
        }
        let before = motion.frame(at: 1, amplitude: 0.2).travel
        let after = motion.frame(at: 11, amplitude: 0.2).travel
        #expect(after - before <= 2.0 / 15.0 + 1e-9, "a ten-second gap moves the pattern one short step")
    }

    // MARK: - Helpers

    /// Feeds SFU reports, one every 400 ms, as amplitudes, and reads the mapped level each time.
    private func feed(_ loudness: inout NativeCallVoiceLoudness, decibels: [Double]) -> [Double] {
        decibels.map { loudness.perceived(pow(10, $0 / 20), after: 0.4) }
    }

    /// The rest flag changes in a task after the frame that saw it; let it land.
    private func yieldToMainActor() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }
}
