//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 383): the motion core behind the voice-driven drawings of a call.
//
// The SFU reports a voice's loudness every 400 ms (LiveKit's `audio.update_interval`, averaged over two intervals), as a
// linear amplitude that sits between 0.02 and 0.2 while someone talks and is 0 between utterances. Drawn as it comes, a
// ring or a wave jumps two or three times a second and barely moves. So the level is first put on a perceived scale
// (decibels, adapted to the speaker's recent loudness), then followed at display rate by a critically damped spring:
// the motion stays continuous between the steps, never overshoots its target, and settles to rest in silence.

import Foundation
import Observation

/// A critically damped spring that follows a target with a quicker rise than fall.
///
/// It steps with the exact solution of the spring rather than a numerical integration, so the result does not depend on
/// the frame rate: one step of 1/30 s lands where two of 1/60 s do, and a long hitch lands on the target without
/// ringing.
nonisolated struct NativeCallVoiceSpring: Equatable {
    /// Seconds a rise takes to mostly arrive: speech starts sharply.
    let attack: Double
    /// Seconds a fall takes: a voice trails off, it does not cut.
    let release: Double

    private(set) var value = 0.0
    private(set) var velocity = 0.0

    init(attack: Double = 0.12, release: Double = 0.45) {
        self.attack = max(attack, 0.001)
        self.release = max(release, 0.001)
    }

    /// Moves the spring `seconds` toward `target`. A non-finite target is silence; a non-positive step changes nothing.
    mutating func advance(toward target: Double, by seconds: Double) {
        guard seconds > 0, seconds.isFinite else { return }
        let target = target.isFinite ? target : 0
        // Response in Apple's sense: the angular frequency of a spring with that period.
        let omega = 2 * Double.pi / (target > value ? attack : release)
        let offset = value - target
        let carried = velocity + omega * offset
        let decay = exp(-omega * seconds)
        value = target + (offset + carried * seconds) * decay
        velocity = (velocity - omega * carried * seconds) * decay
    }

    /// Close enough to `target` and slow enough that another frame would draw the same picture.
    func isSettled(at target: Double) -> Bool {
        abs(value - target) < 0.002 && abs(velocity) < 0.02
    }
}

/// The SFU's linear amplitude on the scale people hear, adapted to the speaker.
///
/// A fixed decibel range moved for a shout and barely for talk (operator, question 383): a voice reaches the SFU between
/// -35 and -15 dBov depending on the phone, the distance and the person. So the scale follows the voice's recent
/// loudness, a reference that rises at once with a louder word and settles back over seconds: ordinary talk maps to
/// the upper half, a quiet talker is lifted within a few seconds, and a shout reaches the top without sitting there,
/// because the reference catches up. Silence holds the reference, so the next phrase starts on the same scale.
nonisolated struct NativeCallVoiceLoudness: Equatable {
    /// The reference a call starts from: a phone's ordinary talk.
    static let startingReferenceDecibels = -26.0
    /// However quiet or loud the voice, the reference stays here, so faint input is never blown up into motion.
    static let referenceRange = -40.0 ... -12.0
    /// The scale spans this many decibels below the reference's top.
    static let spanDecibels = 24.0
    /// The reference's own level maps just under the top: louder words still show.
    static let headroomDecibels = 2.0
    /// Seconds for the reference to follow a louder word, and to settle back to a quieter voice.
    static let attack = 0.25
    static let release = 5.0
    /// Below this nothing a client passes on is speech.
    static let silenceDecibels = -60.0
    /// The same as an amplitude.
    static let silenceAmplitude = 0.001

    private(set) var referenceDecibels = startingReferenceDecibels

    /// The amplitude's place on the speaker's scale, 0...1, after `seconds` since the last sample.
    mutating func perceived(_ amplitude: Double, after seconds: Double) -> Double {
        guard amplitude.isFinite, amplitude > 0 else { return 0 }
        let decibels = 20 * log10(amplitude)
        guard decibels > Self.silenceDecibels else { return 0 }

        let time = decibels > referenceDecibels ? Self.attack : Self.release
        let step = seconds > 0 && seconds.isFinite ? 1 - exp(-seconds / time) : 0
        referenceDecibels += (decibels - referenceDecibels) * step
        referenceDecibels = min(Self.referenceRange.upperBound, max(Self.referenceRange.lowerBound, referenceDecibels))

        let top = referenceDecibels + Self.headroomDecibels
        return min(1, max(0, (decibels - (top - Self.spanDecibels)) / Self.spanDecibels))
    }
}

/// A smooth, never-repeating wobble in -1...1 at a syllable's rate (about 3-7 Hz).
///
/// The SFU's steps are too coarse to carry syllables, so a drawing adds this texture scaled by the voice's energy:
/// silent at rest, lively while someone talks. Three sines at incommensurate rates never line up into a visible loop.
nonisolated enum NativeCallVoiceFlutter {
    static func value(at time: Double, seed: Double = 0) -> Double {
        let first = sin(time * 2 * .pi * 4.3 + seed * 1.7)
        let second = sin(time * 2 * .pi * 6.7 + seed * 2.9)
        let third = sin(time * 2 * .pi * 2.9 + seed * 0.6)
        return 0.5 * first + 0.3 * second + 0.2 * third
    }
}

/// What one voice-driven drawing keeps between frames: the spring on the perceived level and how far its pattern has
/// travelled. Read from a `TimelineView`'s Canvas, once per frame.
///
/// Only `isAtRest` is observed. A drawing pauses its timeline once silence has settled, so a face nobody hears costs no
/// frame at all, and `pollWhileAtRest(_:)` wakes it when the voice comes back. Every other change stays out of
/// SwiftUI's invalidation.
@Observable
final class NativeCallVoiceMotion {
    struct Frame {
        /// The followed level, 0...1.
        let energy: Double
        /// Seconds, for textures that run on their own clock.
        let time: Double
        /// How far the pattern has moved: it moves faster as the voice gets louder and stops in silence.
        let travel: Double
    }

    /// True once silence has settled: nothing on screen would change until the voice comes back.
    private(set) var isAtRest = true

    @ObservationIgnored private var spring: NativeCallVoiceSpring
    @ObservationIgnored private var loudness = NativeCallVoiceLoudness()
    @ObservationIgnored private var lastTime: Double?
    @ObservationIgnored private var travel = 0.0
    @ObservationIgnored private var silentSince: Double?
    @ObservationIgnored private let speechSpeed: Double
    @ObservationIgnored private let restDelay: Double
    /// The rest flag a frame has asked for and not yet seen land: one hop to the main actor per change, not per frame.
    @ObservationIgnored private var pendingRest: Bool?

    /// - Parameters:
    ///   - speechSpeed: How fast the pattern travels at full voice, per second.
    ///   - restDelay: Seconds of settled silence before the drawing counts as at rest: the gaps between words keep the
    ///     display rate, and whatever is still fading out on screen has time to finish.
    init(attack: Double = 0.12, release: Double = 0.45, speechSpeed: Double = 2, restDelay: Double = 1) {
        spring = NativeCallVoiceSpring(attack: attack, release: release)
        self.speechSpeed = speechSpeed
        self.restDelay = restDelay
    }

    /// Advances to `time` toward the SFU's `amplitude`, or toward plain on/off with `speakingOnly` (Reduce Motion).
    func frame(at time: Double, amplitude: Double, speakingOnly: Bool = false) -> Frame {
        // A gap longer than a few frames (a hitch, the app coming back) moves the spring, never the pattern by a leap.
        let elapsed = lastTime.map { min(max(time - $0, 0), 0.5) } ?? 0
        lastTime = time

        let target = speakingOnly ? (amplitude > 0 ? 1 : 0) : loudness.perceived(amplitude, after: elapsed)
        spring.advance(toward: target, by: elapsed)
        let energy = min(1, max(0, spring.value))
        travel += min(elapsed, 1.0 / 15.0) * speechSpeed * energy

        silentSince = target == 0 ? (silentSince ?? time) : nil
        let atRest = spring.isSettled(at: 0) && silentSince.map { time - $0 >= restDelay } == true
        if atRest != (pendingRest ?? isAtRest) {
            // Not during the render that read it: the flag changes the drawing's own timeline.
            pendingRest = atRest
            Task { @MainActor [weak self] in
                guard let self, let pendingRest else { return }
                isAtRest = pendingRest
                self.pendingRest = nil
            }
        }
        return Frame(energy: energy, time: time, travel: travel)
    }

    /// While at rest, reads `level` ten times a second and wakes the drawing when a voice the scale would show is
    /// there (above its silence). Run from a view's `.task(id:)` while the scene is active: a level read per tick, no
    /// frame.
    func pollWhileAtRest(_ level: () -> Double) async {
        while isAtRest, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            if level() > NativeCallVoiceLoudness.silenceAmplitude {
                wake()
            }
        }
    }

    /// The voice is back: draw again. The spring carries on from where it rested.
    func wake() {
        pendingRest = nil
        silentSince = nil
        isAtRest = false
    }
}

/// Low Power Mode, observed: the voice drawings drop to 30 frames a second and fewer layers while it is on.
@Observable
final class NativeCallLowPowerMode {
    static let shared = NativeCallLowPowerMode()

    private(set) var isEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }
}
