//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

#if DEBUG || SPIRAL_STAGING

import Foundation
@testable import Spiral
import Testing

/// The call-motion lab's voice must look like what a call delivers, or the operator judges motion against the wrong
/// signal: speech with pauses, reported by the SFU every 400 ms.
struct CallMotionLabVoiceTests {
    @Test
    func theSpeakerTalksInPhrasesWithPauses() {
        var speaker = CallMotionLabSpeaker(seed: 7)
        let samples = (0..<6000).map { _ in speaker.advance(by: 0.01) }
        let speaking = samples.filter { $0 > CallMotionLabSpeaker.silenceDecibels }
        let share = Double(speaking.count) / Double(samples.count)

        #expect(share > 0.4 && share < 0.9, "a minute of speech has pauses in it")
        #expect(speaking.allSatisfy { $0 > -50 && $0 < -5 }, "levels a microphone gives for speech")
        #expect((speaking.max() ?? 0) - (speaking.min() ?? 0) > 12, "syllables and phrases vary in loudness")
    }

    @Test
    func theSpeakerIsTheSameForASeed() {
        var first = CallMotionLabSpeaker(seed: 3)
        var second = CallMotionLabSpeaker(seed: 3)
        for _ in 0..<500 {
            #expect(first.advance(by: 0.01) == second.advance(by: 0.01))
        }
    }

    /// The Mac's microphone, raw, sits far below what a phone sends: its talk must still reach the SFU as speech,
    /// as a phone's gain control makes it, while the room's noise stays silent.
    @Test
    func theSenderLiftsAQuietMicrophoneAndGatesTheRoom() {
        var sender = CallMotionLabSender()
        var sfu = CallMotionLabSFU()
        var speaker = CallMotionLabSpeaker(seed: 11)
        // Two seconds of a room at -62 dBFS, then ten of ordinary talk 22 dB below what a phone sends.
        for _ in 0..<200 {
            sfu.advance(by: 0.01, decibels: sender.process(-62, by: 0.01))
        }
        #expect(sfu.reported == 0, "the room alone is silence")

        var reports: [Double] = []
        for step in 1...1000 {
            let talk = speaker.advance(by: 0.01) - 22
            sfu.advance(by: 0.01, decibels: sender.process(max(talk, -62), by: 0.01))
            if step.isMultiple(of: 40) {
                reports.append(sfu.reported)
            }
        }
        // A phone sends ordinary talk at -35…-15 dBov: 0.018…0.18.
        let spoken = reports.filter { $0 > 0.0178 }
        #expect(spoken.count >= 8, "the talk reaches the SFU as speech: \(reports)")
        #expect(reports.allSatisfy { $0 < 0.5 }, "and not above a phone's level")
    }

    @Test
    func theSFUReportsEvery400Milliseconds() {
        var sfu = CallMotionLabSFU()
        var changes = 0
        var previous = sfu.reported
        for step in 0..<400 {
            // A voice that keeps getting louder: every report differs from the last.
            sfu.advance(by: 0.01, decibels: step < 20 ? -20 : -30 + Double(step) * 0.02)
            if sfu.reported != previous {
                changes += 1
                previous = sfu.reported
            }
        }
        #expect(changes == 10, "four seconds hold ten reports")
    }

    @Test
    func theSFUReadsSilenceAndQuietVoicesAsZero() {
        var sfu = CallMotionLabSFU()
        for _ in 0..<80 {
            sfu.advance(by: 0.01, decibels: -20)
        }
        #expect(sfu.reported > 0.05 && sfu.reported < 0.15, "-20 dBov is 0.1 as a linear level")

        for _ in 0..<80 {
            sfu.advance(by: 0.01, decibels: -42)
        }
        #expect(sfu.reported == 0, "below -35 dBov the SFU does not count a voice as speaking")
    }

    @Test
    func theSFUAveragesTwoIntervals() {
        var sfu = CallMotionLabSFU()
        for _ in 0..<40 {
            sfu.advance(by: 0.01, decibels: -20)
        }
        for _ in 0..<40 {
            sfu.advance(by: 0.01, decibels: -30)
        }
        // The mean of -20 and -30 dBov, not the latest interval.
        #expect(abs(20 * log10(sfu.reported) - -25) < 0.5)
    }
}

#endif
