//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import AVFoundation
import Foundation

// AGENT-PLATFORM (Brief 0063): the in-call signalling tones (ringback, busy,
// connect, end). They are synthesised so no audio assets need shipping.
//
// Telephony ordering rule: a tone may only start on an audio session that the
// system has already activated — anything started earlier is nullified when
// CallKit activates the call session. `NativeCallAudio` owns that ordering;
// nothing else should talk to this player directly.

/// The classic telephony cues, with ETSI cadences where one exists.
enum NativeCallTone {
    /// 425 Hz, 1 s on / 4 s off, looped — outgoing call is ringing.
    case ringback
    /// 425 Hz, 0.5 s on / 0.5 s off, looped — peer is busy.
    case busy
    /// A short two-note blip — the call connected.
    case connected
    /// A short double beep — the call ended or was not picked up.
    case ended
    /// A quiet periodic tick, looped — the transport is reconnecting.
    case reconnecting
    
    var loops: Bool {
        switch self {
        case .ringback, .busy, .reconnecting: true
        case .connected, .ended: false
        }
    }
    
    /// `frequency == nil` is silence.
    var segments: [(frequency: Double?, duration: Double)] {
        switch self {
        case .ringback: [(425, 1), (nil, 4)]
        case .busy: [(425, 0.5), (nil, 0.5)]
        case .connected: [(500, 0.09), (nil, 0.04), (700, 0.12)]
        case .ended: [(425, 0.22), (nil, 0.14), (425, 0.22)]
        case .reconnecting: [(425, 0.15), (nil, 2.85)]
        }
    }
}

@MainActor
final class NativeCallTonePlayer {
    /// Off for the unit-test run (`UnitTestsAppCoordinator`): sessions there reach real tones, and a looping
    /// ringback from the test host plays out of the Mac's speakers. Everything up to `AVAudioPlayer.play()` still runs.
    static var isOutputEnabled = true
    
    /// The tone last asked for and not stopped since, whether or not it is audible.
    private(set) var tone: NativeCallTone?
    private var player: AVAudioPlayer?
    
    var isAudible: Bool {
        player?.isPlaying ?? false
    }
    
    func play(_ tone: NativeCallTone) {
        stop()
        
        guard let data = NativeCallToneSynthesizer.wavData(for: tone) else { return }
        
        do {
            let player = try AVAudioPlayer(data: data)
            player.numberOfLoops = tone.loops ? -1 : 0
            player.volume = 0.4
            if Self.isOutputEnabled {
                player.play()
            }
            self.player = player
            self.tone = tone
        } catch {
            MXLog.error("Failed playing a call tone: \(error)")
        }
    }
    
    func stop() {
        player?.stop()
        player = nil
        tone = nil
    }
}

enum NativeCallToneSynthesizer {
    private static let sampleRate: Double = 8000
    
    static func wavData(for tone: NativeCallTone) -> Data? {
        makeWAVData(segments: tone.segments)
    }
    
    static func makeWAVData(segments: [(frequency: Double?, duration: Double)]) -> Data? {
        var samples = [Int16]()
        let amplitude = 0.5 * Double(Int16.max)
        // A short fade at the tone edges avoids clicks.
        let fadeSampleCount = Int(0.01 * sampleRate)
        
        for segment in segments {
            let segmentSampleCount = Int(segment.duration * sampleRate)
            
            guard let frequency = segment.frequency else {
                samples.append(contentsOf: [Int16](repeating: 0, count: segmentSampleCount))
                continue
            }
            
            for index in 0..<segmentSampleCount {
                let envelope = min(1, min(Double(index), Double(segmentSampleCount - index)) / Double(fadeSampleCount))
                samples.append(Int16(amplitude * envelope * sin(2 * .pi * frequency * Double(index) / sampleRate)))
            }
        }
        
        guard !samples.isEmpty else { return nil }
        
        let dataChunkSize = samples.count * MemoryLayout<Int16>.size
        
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLittleEndian(UInt32(36 + dataChunkSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.appendLittleEndian(UInt32(16)) // PCM format chunk size
        data.appendLittleEndian(UInt16(1)) // PCM
        data.appendLittleEndian(UInt16(1)) // mono
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate) * 2) // byte rate
        data.appendLittleEndian(UInt16(2)) // block align
        data.appendLittleEndian(UInt16(16)) // bits per sample
        data.append(contentsOf: Array("data".utf8))
        data.appendLittleEndian(UInt32(dataChunkSize))
        samples.forEach { data.appendLittleEndian(UInt16(bitPattern: $0)) }
        
        return data
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
    
    mutating func appendLittleEndian(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
