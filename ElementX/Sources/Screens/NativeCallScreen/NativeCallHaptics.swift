//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import UIKit

// AGENT-PLATFORM (Brief 0068 Slice 3)

/// The two taps a call gives the hand: connected, ended. A struct of
/// closures rather than a protocol so a test passes counters and a preview
/// passes nothing.
@MainActor
struct NativeCallHaptics {
    let connected: () -> Void
    let ended: () -> Void

    /// The Phone app's cues: a light tap on connect, a firmer one on end.
    static let system = NativeCallHaptics(connected: {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }, ended: {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    })

    static let none = NativeCallHaptics(connected: { }, ended: { })
}
