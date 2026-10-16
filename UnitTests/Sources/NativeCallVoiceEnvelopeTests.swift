//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import ElementX
import Testing

/// The smoothing behind every voice wave. The SFU reports loudness a few
/// times a second; drawn raw it stutters, so a rise is taken at once and a
/// fall decays.
struct NativeCallVoiceEnvelopeTests {
    @Test
    func aRiseIsTakenImmediatelyAndAFallDecays() {
        var envelope = NativeCallVoiceEnvelope()
        #expect(envelope.level == 0)

        envelope.advance(to: 0.8)
        #expect(envelope.level == 0.8, "speech starts sharply — no lag on the way up")

        // Silence: the level slides down rather than snapping to nothing
        // between two server updates.
        envelope.advance(to: 0)
        #expect(envelope.level < 0.8)
        #expect(envelope.level > 0.5)

        var previous = envelope.level
        for _ in 0..<20 {
            envelope.advance(to: 0)
            #expect(envelope.level < previous)
            previous = envelope.level
        }
        #expect(previous < 0.05, "the tail settles rather than lingering")
    }

    @Test
    func samplesAreClampedToTheUnitRange() {
        var envelope = NativeCallVoiceEnvelope()
        envelope.advance(to: 4)
        #expect(envelope.level == 1)

        envelope.advance(to: -3)
        #expect(envelope.level <= 1)
        #expect(envelope.level >= 0)
    }

    /// Silence keeps the mark visible as a shape: the bars rest, they do
    /// not vanish. Sound lifts them above that floor.
    @Test
    func silenceRestsAndSoundLiftsTheBars() {
        var envelope = NativeCallVoiceEnvelope()
        #expect(envelope.scale(phase: 0) == 0.35)
        #expect(envelope.scale(phase: 3) == 0.35)

        envelope.advance(to: 1)
        let loudest = (0..<8).map { envelope.scale(phase: Double($0)) }.max() ?? 0
        #expect(loudest > 0.35)
        #expect(loudest <= 1)
    }

    /// A louder voice draws longer bars than a quiet one, at the same
    /// point in the breathing cycle.
    @Test
    func aLouderVoiceDrawsLongerBars() {
        var quiet = NativeCallVoiceEnvelope()
        quiet.advance(to: 0.2)
        var loud = NativeCallVoiceEnvelope()
        loud.advance(to: 0.9)

        let phase = Double.pi / 2
        #expect(loud.scale(phase: phase) > quiet.scale(phase: phase))
    }
}
