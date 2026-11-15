//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 383): the voices the call-motion lab drives its drawings with — a simulated
// speaker, a fixed level or the Mac's microphone — fed through a copy of the SFU's reporting, so the lab shows what a
// real call delivers: a level every 400 ms, not a meter at display rate.
//
// Staging and Debug builds only: an App Store build has no lab compiled in.

#if DEBUG || SPIRAL_STAGING

import AVFAudio
import CallKit
import SwiftUI
import Synchronization

// MARK: - A simulated speaker

/// Speech-like loudness: syllables at 4-7 a second inside phrases of one to three seconds, pauses between them, and
/// phrases louder and quieter than each other. Deterministic for a seed, so a test can pin it.
nonisolated struct CallMotionLabSpeaker {
    /// Below anything the SFU counts as speech.
    static let silenceDecibels = -70.0

    private var random: CallMotionLabRandom
    private var isInPhrase = false
    private var segmentLeft = 0.0
    private var phraseDecibels = -24.0
    private var syllableElapsed = 0.0
    private var syllableLength = 0.2
    private var syllablePeak = -24.0

    init(seed: UInt64 = 0x5EED) {
        random = CallMotionLabRandom(seed: seed)
    }

    /// Moves `seconds` on and returns the level in dBov, `gain` decibels louder.
    mutating func advance(by seconds: Double, gain: Double = 0) -> Double {
        segmentLeft -= seconds
        if segmentLeft <= 0 {
            startSegment()
        }
        guard isInPhrase else { return Self.silenceDecibels }

        syllableElapsed += seconds
        if syllableElapsed >= syllableLength {
            startSyllable()
        }
        // A quick rise and a longer decay; the voice does not fall silent between syllables of one phrase.
        let progress = syllableElapsed / syllableLength
        let shape = progress < 0.2 ? sin(progress / 0.2 * .pi / 2) : exp(-(progress - 0.2) * 3)
        let trough = syllablePeak - 8
        return trough + (syllablePeak - trough) * shape + gain
    }

    private mutating func startSegment() {
        isInPhrase.toggle()
        if isInPhrase {
            segmentLeft = random.next(in: 0.8...3.2)
            // Phrases of a phone's ordinary talk: LiveKit reports them at -35...-15 dBov.
            phraseDecibels = random.next(in: -30 ... -16)
            startSyllable()
        } else {
            // Mostly the breath between phrases, now and then the other person's turn.
            segmentLeft = random.next(in: 0...1) < 0.15 ? random.next(in: 1.8...3.0) : random.next(in: 0.2...1.2)
        }
    }

    private mutating func startSyllable() {
        syllableElapsed = 0
        syllableLength = random.next(in: 0.14...0.28)
        let stress = random.next(in: 0...1) < 0.2 ? 4.0 : 0
        syllablePeak = phraseDecibels + random.next(in: -4...2) + stress
    }
}

/// SplitMix64: small, fast and the same on every run.
nonisolated struct CallMotionLabRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        mixed ^= mixed >> 31
        let unit = Double(mixed >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}

// MARK: - The phone's sending

/// What a phone does to its microphone before sending: gain control brings talk to a phone's level and noise
/// suppression keeps the room down. The Mac's microphone, raw, sits 15-25 dB below a phone's output, so without this the
/// SFU's -35 dBov gate drops ordinary talk and only a shout came through (operator, question 383).
nonisolated struct CallMotionLabSender {
    /// Where a phone puts the peaks of talk.
    static let targetPeakDecibels = -14.0
    static let gainRange = -10.0...30.0
    /// A sample this far above the room counts as voice; one under `suppressionMargin` is pushed down as noise.
    static let speechMargin = 12.0
    static let suppressionMargin = 6.0
    static let suppression = 20.0

    /// Nil until the first sample: the room starts as whatever the microphone hears first, so a quiet room's hum is
    /// never lifted into a voice while a fixed starting floor would still be catching up.
    private var noiseFloor: Double?
    private var speechPeak = -30.0

    /// The level to send for a microphone sample of `decibels` (dBFS), `seconds` after the last one.
    mutating func process(_ decibels: Double, by seconds: Double) -> Double {
        // The engine's first buffers are digital silence: they are no room.
        guard decibels > -85 || self.noiseFloor != nil else { return CallMotionLabSpeaker.silenceDecibels }
        // The room: follows a quieter sample fast, a louder one more slowly, so a phrase barely raises it.
        var noiseFloor = noiseFloor ?? decibels
        noiseFloor += (decibels - noiseFloor) * Self.step(seconds, decibels < noiseFloor ? 0.3 : 8)
        noiseFloor = min(-30, max(-90, noiseFloor))
        self.noiseFloor = noiseFloor

        if decibels > noiseFloor + Self.speechMargin {
            speechPeak += (decibels - speechPeak) * Self.step(seconds, decibels > speechPeak ? 0.2 : 3)
        }
        let gain = min(Self.gainRange.upperBound, max(Self.gainRange.lowerBound, Self.targetPeakDecibels - speechPeak))
        let suppressed = decibels < noiseFloor + Self.suppressionMargin ? Self.suppression : 0
        return min(-3, decibels + gain - suppressed)
    }

    private static func step(_ seconds: Double, _ time: Double) -> Double {
        1 - exp(-max(seconds, 0) / time)
    }
}

// MARK: - The SFU's reporting

/// What LiveKit's server does with a voice before a client sees it (`audio` config defaults): one report every 400 ms,
/// the average of the last two intervals, sent only while the voice was above -35 dBov for more than 40 % of the
/// interval; a voice not speaking reads 0. Levels go out as linear amplitude, `10^(dBov/20)`.
nonisolated struct CallMotionLabSFU {
    static let interval = 0.4
    static let activeDecibels = -35.0
    static let activeShare = 0.4

    /// The amplitude a client reads right now.
    private(set) var reported = 0.0

    private var elapsed = 0.0
    private var decibelSum = 0.0
    private var sampleCount = 0
    private var activeCount = 0
    private var previousInterval: Double?

    /// Takes the voice's level over the last `seconds`.
    mutating func advance(by seconds: Double, decibels: Double) {
        elapsed += seconds
        decibelSum += decibels
        sampleCount += 1
        if decibels > Self.activeDecibels {
            activeCount += 1
        }
        // The tolerance keeps forty 10 ms steps one interval despite floating-point sums.
        guard elapsed >= Self.interval - 1e-9, sampleCount > 0 else { return }

        let mean = decibelSum / Double(sampleCount)
        let smoothed = previousInterval.map { ($0 + mean) / 2 } ?? mean
        let isActive = Double(activeCount) / Double(sampleCount) > Self.activeShare
        reported = isActive ? pow(10, smoothed / 20) : 0

        previousInterval = mean
        elapsed -= Self.interval
        decibelSum = 0
        sampleCount = 0
        activeCount = 0
    }
}

// MARK: - The lab's level source

/// Feeds the call's real level environment (`nativeCallVoiceLevels`), so the drawings read the lab exactly as they read
/// a call. The simulation advances lazily, to the moment a drawing asks: no timer of its own runs.
@Observable
final class CallMotionLabLevels: NativeCallVoiceLevelReading {
    enum Source: String, CaseIterable, Identifiable {
        case speech = "Speech"
        case manual = "Manual"
        case microphone = "Mic"

        var id: Self {
            self
        }
    }

    var source = Source.speech {
        didSet { microphone.isRunning = source == .microphone && isPlaying }
    }

    /// Through the SFU's 400 ms reporting, as in a call; off, the raw level at display rate (a local meter).
    var isThroughSFU = true
    var isPlaying = true {
        didSet { microphone.isRunning = source == .microphone && isPlaying }
    }

    /// Speech: the speaker's gain in dB. Manual: the level itself, in dBov.
    var slider = 0.0

    var microphoneStatus: String {
        microphone.status
    }

    /// The Mac microphone's raw level, dBFS, for the meter.
    @ObservationIgnored private(set) var microphoneDecibels = -90.0
    /// The drawings' scale, fed what they are fed, for the meter.
    @ObservationIgnored private(set) var mappedLevel = 0.0

    @ObservationIgnored private var speaker = CallMotionLabSpeaker()
    @ObservationIgnored private var sender = CallMotionLabSender()
    @ObservationIgnored private var scale = NativeCallVoiceLoudness()
    @ObservationIgnored private var sfu = CallMotionLabSFU()
    @ObservationIgnored private var raw = 0.0
    @ObservationIgnored private var lastTime: Double?
    @ObservationIgnored private let microphone = CallMotionLabMicrophone()

    // MARK: NativeCallVoiceLevelReading

    func voiceLevel(forUserID userID: String) -> Double {
        current
    }

    var loudestVoiceLevel: Double {
        current
    }

    // MARK: Simulation

    private var current: Double {
        advanceToNow()
        guard isPlaying else { return 0 }
        return isThroughSFU ? sfu.reported : raw
    }

    private func advanceToNow() {
        let now = CACurrentMediaTime()
        defer { lastTime = now }
        guard let lastTime, isPlaying else { return }

        // Ten-millisecond steps, as the server sees the packets; a long gap (backgrounded) restarts quietly.
        var remaining = min(now - lastTime, 1)
        while remaining > 0 {
            let step = min(remaining, 0.01)
            let decibels = decibelsNow(advancingBy: step)
            sfu.advance(by: step, decibels: decibels)
            raw = decibels <= CallMotionLabSpeaker.silenceDecibels ? 0 : pow(10, decibels / 20)
            mappedLevel = scale.perceived(isThroughSFU ? sfu.reported : raw, after: step)
            remaining -= step
        }
    }

    private func decibelsNow(advancingBy seconds: Double) -> Double {
        switch source {
        case .speech:
            return speaker.advance(by: seconds, gain: slider)
        case .manual:
            return slider <= -60 ? CallMotionLabSpeaker.silenceDecibels : slider
        case .microphone:
            let amplitude = microphone.amplitude
            let raw = amplitude > 0 ? max(-90, 20 * log10(amplitude)) : -90
            microphoneDecibels = raw
            return sender.process(raw, by: seconds)
        }
    }
}

// MARK: - The Mac's microphone

/// In the simulator the Mac's microphone is the device's: the operator can talk to the lab. The tap runs on the audio
/// thread and only stores the buffer's RMS; the drawings read it at display rate.
///
/// The lab never takes the audio session from a call: while one is active the Mic source refuses. A stop that lands
/// while a start still waits for the permission cancels it, and a stop always stops the engine.
@Observable
final class CallMotionLabMicrophone {
    private(set) var status = "Off"

    var isRunning = false {
        didSet {
            guard isRunning != oldValue else { return }
            isRunning ? start() : stop()
        }
    }

    var amplitude: Double {
        meter.amplitude.withLock { $0 }
    }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let meter = CallMotionLabMicrophoneMeter()
    @ObservationIgnored private let callObserver = CXCallObserver()
    @ObservationIgnored private var starting: Task<Void, Never>?
    @ObservationIgnored private var hasSession = false

    private func start() {
        guard !callObserver.calls.contains(where: { !$0.hasEnded }) else {
            status = "Not during a call: the call has the microphone"
            return
        }
        starting = Task {
            let isAllowed = await AVAudioApplication.requestRecordPermission()
            guard !Task.isCancelled, isRunning else { return }
            guard isAllowed else {
                status = "No microphone permission"
                return
            }
            guard !callObserver.calls.contains(where: { !$0.hasEnded }) else {
                status = "Not during a call: the call has the microphone"
                return
            }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
                try session.setActive(true)
                hasSession = true
                let input = engine.inputNode
                input.removeTap(onBus: 0)
                input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0),
                                 block: CallMotionLabMicrophoneMeter.tapBlock(for: meter))
                try engine.start()
                status = "Listening"
            } catch {
                stop()
                status = "Microphone failed: \(error.localizedDescription)"
            }
        }
    }

    private func stop() {
        starting?.cancel()
        starting = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        meter.amplitude.withLock { $0 = 0 }
        if hasSession {
            hasSession = false
            // A call that started meanwhile owns the session now: leave it alone.
            if !callObserver.calls.contains(where: { !$0.hasEnded }) {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
        status = "Off"
    }
}

/// The one value shared with the audio thread.
final nonisolated class CallMotionLabMicrophoneMeter: Sendable {
    let amplitude = Mutex(0.0)

    /// Built outside the main actor: a closure made inside it would assert the main queue on the audio thread.
    static func tapBlock(for meter: CallMotionLabMicrophoneMeter) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for index in 0..<count {
                sum += samples[index] * samples[index]
            }
            let rms = Double((sum / Float(count)).squareRoot())
            meter.amplitude.withLock { $0 = rms }
        }
    }
}

#endif
