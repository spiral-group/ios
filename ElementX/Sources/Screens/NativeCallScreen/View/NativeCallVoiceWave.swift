//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063): THE voice wave (`21 · REF · Voice wave`).
//
// One mark, one meaning: this voice is airing right now, and the bars move
// with it. Two forms, per the design:
//
//   BARE — beside an avatar, where identity is already shown (roster row,
//          the Agent Center's agent head).
//   SLOT — inside a tinted circle, where the wave IS the identity (the
//          agent block, the capsule over video, the minimized call bar).
//
// The bars are centred on one midline and lengthen symmetrically; a
// baseline meter reads as a chart, not as a voice. Without a level source
// (previews, snapshot tests) they render at their design heights, so the
// snapshots stay deterministic.

import Compound
import SwiftUI

struct NativeCallVoiceWave: View {
    enum Scale {
        /// `C/Participant`'s airing mark, and the Agent Center head.
        case row
        case sheet
        /// The agent block and the capsule over video.
        case block
        /// The minimized call bar: three bars, tighter.
        case badge

        var heights: [CGFloat] {
            switch self {
            case .row: [6, 11, 8, 12]
            case .sheet: [7, 13, 10, 15]
            case .block: [7, 14, 10, 16]
            case .badge: [5, 9, 7]
            }
        }

        var barWidth: CGFloat {
            self == .badge ? 2.5 : 3
        }

        var spacing: CGFloat {
            switch self {
            case .row: 2
            case .badge: 2
            case .sheet, .block: 2.5
            }
        }

        /// The block leads the screen, so it gets the smoothest tick; the
        /// rest run slower because a roster can hold eight of them.
        var refreshInterval: Double {
            self == .block ? 1.0 / 30.0 : 1.0 / 20.0
        }
    }

    /// The circle a wave wears when it stands for the speaker itself.
    struct Slot {
        let diameter: CGFloat
        let background: Color
        let foreground: Color

        static let agent = Slot(diameter: 30,
                                background: Color.compound.iconAccentPrimary.opacity(0.15),
                                foreground: .compound.iconAccentPrimary)
        static let overVideo = Slot(diameter: 26,
                                    background: Color.compound.iconAccentPrimary.opacity(0.35),
                                    foreground: .white)
        static let onGreen = Slot(diameter: 24,
                                  background: .white.opacity(0.16),
                                  foreground: .white)
    }

    /// Whose voice to follow; nil means "the loudest voice in the call",
    /// which is what the minimized bar shows.
    let userID: String?
    let scale: Scale
    var slot: Slot?
    /// Only used by the bare form — the slotted form takes its colour from
    /// the slot so the pair always agrees.
    var color: Color = .compound.iconAccentPrimary

    @Environment(\.nativeCallVoiceLevels) private var levels
    @State private var envelope = NativeCallVoiceEnvelope()

    var body: some View {
        if let slot {
            bars(color: slot.foreground)
                .frame(width: slot.diameter, height: slot.diameter)
                .background(slot.background, in: Circle())
        } else {
            bars(color: color)
        }
    }

    @ViewBuilder
    private func bars(color: Color) -> some View {
        if levels == nil {
            // No level source: the design heights, stable for snapshots.
            row(color: color, scales: scale.heights.map { _ in 1 })
        } else {
            // Qualified: the app's room timeline also declares a `TimelineView`.
            SwiftUI.TimelineView(.animation(minimumInterval: scale.refreshInterval)) { timeline in
                row(color: color, scales: barScales(at: timeline.date))
                    .onChange(of: timeline.date) {
                        envelope.advance(to: sampleLevel())
                    }
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

    /// Each bar breathes at its own rate inside the shared amplitude, so
    /// the group reads as a voice rather than a single pulsing block.
    private func barScales(at date: Date) -> [CGFloat] {
        let frequencies: [Double] = [2.6, 3.4, 2.2, 3.0]
        let time = date.timeIntervalSinceReferenceDate
        return scale.heights.indices.map { index in
            let frequency = frequencies[index % frequencies.count]
            let phase = time * frequency * 2 * .pi + Double(index) * 1.7
            return CGFloat(envelope.scale(phase: phase))
        }
    }
}

extension EnvironmentValues {
    /// The call's live voice levels, published once at the call screen's
    /// root so every wave — roster row, sheet, block, capsule, bar — can
    /// follow the speaker without threading a reader through every view.
    @Entry var nativeCallVoiceLevels: NativeCallVoiceLevelReading?
}

// MARK: - Previews

struct NativeCallVoiceWave_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 28) {
                NativeCallVoiceWave(userID: nil, scale: .row)
                NativeCallVoiceWave(userID: nil, scale: .sheet)
            }

            HStack(spacing: 28) {
                NativeCallVoiceWave(userID: nil, scale: .block, slot: .agent)

                NativeCallVoiceWave(userID: nil, scale: .block, slot: .overVideo)
                    .padding(6)
                    .background(.black, in: RoundedRectangle(cornerRadius: 12))

                NativeCallVoiceWave(userID: nil, scale: .badge, slot: .onGreen)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.compound.iconSuccessPrimary, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .previewDisplayName("Voice wave")
    }
}
