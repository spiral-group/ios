//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063): THE voice wave (`21 · REF · Voice wave`).
//
// One mark, one meaning: this voice is airing right now, and the bars move
// with it, beside an avatar where identity is already shown (the Agent
// Center's agent head). The pill's slot became an Aura round the avatar
// (question 383).
//
// The bars are centred on one midline and lengthen symmetrically; a
// baseline meter reads as a chart, not as a voice. Under Reduce Motion, and
// without a level source (previews, snapshot tests), they hold their design
// heights, so the snapshots stay deterministic.

import Compound
import SwiftUI

struct NativeCallVoiceWave: View {
    enum Scale {
        /// The Agent Center head.
        case sheet

        var heights: [CGFloat] {
            switch self {
            case .sheet: [7, 13, 10, 15]
            }
        }

        var barWidth: CGFloat {
            3
        }

        var spacing: CGFloat {
            2.5
        }
    }

    /// Whose voice to follow; nil means "the loudest voice in the call".
    let userID: String?
    let scale: Scale
    var color: Color = .compound.iconAccentPrimary

    @Environment(\.nativeCallVoiceLevels) private var levels
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var motion = NativeCallVoiceMotion(attack: 0.12, release: 0.5, speechSpeed: 1.4)
    @State private var lowPower = NativeCallLowPowerMode.shared

    var body: some View {
        bars(color: color)
    }

    @ViewBuilder
    private func bars(color: Color) -> some View {
        if levels == nil || reduceMotion {
            // The design heights: still, and stable for snapshots.
            row(color: color, scales: scale.heights.map { _ in 1 })
        } else {
            // Qualified: the app's room timeline also declares a `TimelineView`. The same calibrated core as the ring and
            // the bar (question 383): display rate while the voice moves, paused in settled silence and when hidden.
            SwiftUI.TimelineView(.animation(minimumInterval: frameInterval, paused: motion.isAtRest || scenePhase != .active)) { timeline in
                let frame = motion.frame(at: timeline.date.timeIntervalSinceReferenceDate, amplitude: sampleLevel())
                row(color: color, scales: barScales(frame))
            }
            .task(id: motion.isAtRest && scenePhase == .active) {
                guard scenePhase == .active else { return }
                await motion.pollWhileAtRest { sampleLevel() }
            }
        }
    }

    private func row(color: Color, scales: [CGFloat]) -> some View {
        HStack(spacing: scale.spacing) {
            ForEach(Array(scale.heights.enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: scale.barWidth / 2)
                    .fill(color)
                    .frame(width: scale.barWidth, height: max(2, height * scales[index]))
            }
        }
        // Centred on one midline: the level lengthens each bar up AND down.
        .frame(height: scale.heights.max() ?? 0)
        .accessibilityHidden(true)
    }

    private func sampleLevel() -> Double {
        guard let levels else { return 0 }
        guard let userID else { return levels.loudestVoiceLevel }
        return levels.voiceLevel(forUserID: userID)
    }

    private var frameInterval: Double {
        lowPower.isEnabled ? 1.0 / 30.0 : 1.0 / 60.0
    }

    /// Each bar swings at its own phase inside the shared energy, with the syllable-rate flutter, so the group reads as
    /// a voice rather than a single pulsing block. In silence the bars rest at a third of their height: still a shape.
    private func barScales(_ frame: NativeCallVoiceMotion.Frame) -> [CGFloat] {
        let resting = 0.35
        return scale.heights.indices.map { index in
            let swing = 0.55 + 0.45 * sin(frame.travel * 3 + Double(index) * 1.7)
            let flutter = NativeCallVoiceFlutter.value(at: frame.time, seed: Double(index))
            let level = frame.energy * swing * (1 + 0.25 * flutter)
            return CGFloat(min(1, resting + (1 - resting) * level))
        }
    }
}

extension EnvironmentValues {
    /// The call's live voice levels, published once at the call screen's
    /// root so every wave — sheet, pill, bar — can
    /// follow the speaker without threading a reader through every view.
    @Entry var nativeCallVoiceLevels: NativeCallVoiceLevelReading?
}

// MARK: - Previews

struct NativeCallVoiceWave_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        NativeCallVoiceWave(userID: nil, scale: .sheet)
            .padding()
            .previewDisplayName("Voice wave")
    }
}
