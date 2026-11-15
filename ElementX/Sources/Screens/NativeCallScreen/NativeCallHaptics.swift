//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import UIKit

// AGENT-PLATFORM (Brief 0068 Slice 3)

/// The taps a call gives the hand: connected, ended, and a capsule event
/// with an action for you (operator, 2026-11-12). A struct of closures
/// rather than a protocol so a test passes counters and a preview passes
/// nothing.
@MainActor
struct NativeCallHaptics {
    let connected: () -> Void
    let ended: () -> Void
    /// An event with an action shows in the capsule: the same light tap as connect. Not while the call plays through
    /// the earpiece (`isAtEar`).
    var capsuleEvent: () -> Void = { }

    /// The Phone app's cues: a light tap on connect, a firmer one on end.
    static let system = NativeCallHaptics(connected: {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }, ended: {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }, capsuleEvent: {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    })

    /// The call plays through the earpiece: the phone is likely at the ear, next to the microphone, with nothing to
    /// look at — the capsule's tap stays off. The speaker, headphones or a car let it through. (The proximity sensor
    /// isn't watched by the call, so it can't say.)
    nonisolated static func isAtEar(_ routes: [NativeCallAudioRoute]) -> Bool {
        routes.contains { $0.kind == .receiver && $0.isActive }
    }

    static let none = NativeCallHaptics(connected: { }, ended: { })
}
