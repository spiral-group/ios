//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 383): the call bar's wave, the operator's pick from the call-motion lab. Three
// fine white lines span the bar and swell and travel outward from the call's name with the loudest voice. White text on
// the bar's green is 4.51:1 with nothing under it, so the lines keep out of the words' band and fade in beside it. Both
// sides are symmetric, so a right-to-left layout needs nothing.

import SwiftUI

struct NativeCallBarRibbon: View {
    /// The name and timer's width: the lines keep out of it.
    let textWidth: CGFloat

    @Environment(\.nativeCallVoiceLevels) private var levels
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var motion = NativeCallVoiceMotion(attack: 0.12, release: 0.5, speechSpeed: 1)
    @State private var lowPower = NativeCallLowPowerMode.shared

    /// The quiet margin each side of the words.
    private static let gapMargin: CGFloat = 12
    /// How far from that margin a line takes to reach its full swing and colour.
    private static let fadeLength: CGFloat = 36

    var body: some View {
        Group {
            if levels == nil {
                // Previews and snapshots: the lines at rest, deterministic.
                Canvas { context, size in
                    draw(.init(energy: 0, time: 0, travel: 0), in: &context, size: size, isLowPower: false)
                }
            } else {
                // 30 frames a second at most: the level changes every 400 ms and the band is 44 pt, while the timeline
                // under it is the app's first priority. In settled silence it pauses on the resting lines.
                SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: motion.isAtRest || scenePhase != .active)) { timeline in
                    Canvas { context, size in
                        let frame = motion.frame(at: timeline.date.timeIntervalSinceReferenceDate,
                                                 amplitude: levels?.loudestVoiceLevel ?? 0,
                                                 speakingOnly: reduceMotion)
                        draw(frame, in: &context, size: size, isLowPower: lowPower.isEnabled)
                    }
                }
                .task(id: motion.isAtRest && scenePhase == .active) {
                    guard scenePhase == .active else { return }
                    await motion.pollWhileAtRest { levels?.loudestVoiceLevel ?? 0 }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ frame: NativeCallVoiceMotion.Frame, in context: inout GraphicsContext, size: CGSize, isLowPower: Bool) {
        // Reduce Motion: one shape at a fixed swing, held still; only its strength follows speaking.
        let still = reduceMotion
        let energy = still ? 0.4 : frame.energy
        let travel = still ? 0 : frame.travel
        let opacityScale = still ? 0.45 + 0.55 * frame.energy : 1

        let midX = size.width / 2
        let midY = size.height / 2
        let gapHalf = min(textWidth / 2 + Self.gapMargin, midX - 24)
        let lines: [(opacity: Double, width: CGFloat)] = isLowPower ? [(0.9, 1.8)] : [(0.9, 1.8), (0.5, 1.3), (0.3, 1)]

        for (index, line) in lines.enumerated() {
            let seed = Double(index)
            let flutter = isLowPower || still ? 0 : NativeCallVoiceFlutter.value(at: frame.time, seed: seed)
            let amplitude = (2 + 12 * energy) * (1 + 0.25 * flutter * energy) * (1 - 0.2 * seed)
            for side in [-1.0, 1.0] {
                let start = midX + side * gapHalf
                let end: CGFloat = side < 0 ? 0 : size.width
                var path = Path()
                for (step, x) in stride(from: start, through: end, by: side * 3).enumerated() {
                    let distance = max(0, abs(x - midX) - gapHalf)
                    let swell = 0.65 * sin(0.075 * distance - travel * 3 + seed * 1.9)
                        + 0.35 * sin(0.16 * distance - travel * 4.4 + seed * 0.8)
                    let envelope = smoothstep(distance / Self.fadeLength) * smoothstep(min(x, size.width - x) / 24)
                    let point = CGPoint(x: x, y: midY + amplitude * envelope * swell)
                    step == 0 ? path.move(to: point) : path.addLine(to: point)
                }
                let fadeEnd = start + side * Self.fadeLength
                context.stroke(path,
                               with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(line.opacity * opacityScale)]),
                                                     startPoint: CGPoint(x: start, y: 0),
                                                     endPoint: CGPoint(x: fadeEnd, y: 0)),
                               lineWidth: line.width)
            }
        }
    }

    private func smoothstep(_ value: CGFloat) -> CGFloat {
        let clamped = min(1, max(0, value))
        return clamped * clamped * (3 - 2 * clamped)
    }
}
