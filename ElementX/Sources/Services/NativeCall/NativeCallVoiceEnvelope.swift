//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063): the smoothing behind every voice wave.
//
// The SFU refreshes a participant's loudness a few times a second, so the
// raw number arrives in steps. Drawn directly it reads as a stuttering
// meter. This is the usual audio-meter answer: follow a rise instantly
// (speech starts sharply) and let a fall decay, so the bars settle the way
// a voice actually does.

import Foundation

nonisolated struct NativeCallVoiceEnvelope: Equatable {
    /// How much of the previous level survives one step of decay. Tuned so
    /// a stop of speech fades over roughly a third of a second at 20-30fps
    /// rather than snapping to nothing between two server updates.
    static let decay = 0.82

    private(set) var level = 0.0

    /// Feeds one sample. A louder sample is taken immediately; a quieter
    /// one pulls the level down gradually.
    mutating func advance(to sample: Double) {
        let clamped = min(1, max(0, sample))
        level = clamped > level ? clamped : level * Self.decay + clamped * (1 - Self.decay)
    }

    /// The bar's length as a fraction of its design height.
    ///
    /// `resting` is what a bar shrinks to in silence — the mark stays
    /// visible as a shape, it just stops moving. Speech RMS sits low on the
    /// 0...1 scale, so the square root spreads the quiet half and ordinary
    /// talking visibly moves the bars. `phase` gives each bar its own
    /// breathing rhythm inside the shared amplitude.
    func scale(phase: Double, resting: Double = 0.35) -> Double {
        guard level > 0 else { return resting }
        let audible = level.squareRoot()
        let breath = 0.5 + 0.5 * sin(phase)
        return resting + (1 - resting) * audible * (0.35 + 0.65 * breath)
    }
}
