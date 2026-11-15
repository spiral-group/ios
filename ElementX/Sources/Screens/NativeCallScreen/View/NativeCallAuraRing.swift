//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 383): the Aura ring, the operator's pick from the call-motion lab. The ring
// round a speaker's avatar is a living edge: low harmonics bend it with the voice, a second faint stroke follows, and in
// silence it rests as a still, faint circle. One Canvas behind the avatar, redrawn by a TimelineView at display rate
// while a voice moves it; in settled silence and in the background the timeline pauses, and a ten-a-second level read
// wakes it.

import Compound
import SwiftUI

struct NativeCallAuraRing: View {
    /// Whose voice bends the ring.
    let userID: String
    /// The avatar's diameter: the ring is drawn outside it and never changes the layout.
    let diameter: CGFloat
    var tint: Color = .compound.iconAccentPrimary
    /// How far the ring reaches, as a multiple of the 120 pt stage's: the assistant's own page grows it.
    var magnitude: CGFloat = 1
    /// How much of the faint circle stays in silence: the stage's ring rests visible, the pill's halo fades away.
    var restingVisibility: Double = 1

    @Environment(\.nativeCallVoiceLevels) private var levels
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var motion = NativeCallVoiceMotion(attack: 0.12, release: 0.5, speechSpeed: 1.6)
    @State private var lowPower = NativeCallLowPowerMode.shared

    /// Room the ring takes outside a 120 pt avatar on each side.
    static let reach: CGFloat = 30

    var body: some View {
        Group {
            if levels == nil {
                // Previews and snapshots: the ring at rest, deterministic.
                Canvas { context, size in
                    draw(.init(energy: 0, time: 0, travel: 0), in: &context, size: size, isLowPower: false)
                }
            } else {
                // In settled silence the timeline pauses on the resting picture: a face nobody hears draws nothing.
                SwiftUI.TimelineView(.animation(minimumInterval: frameInterval, paused: motion.isAtRest || scenePhase != .active)) { timeline in
                    Canvas { context, size in
                        let frame = motion.frame(at: timeline.date.timeIntervalSinceReferenceDate,
                                                 amplitude: levels?.voiceLevel(forUserID: userID) ?? 0,
                                                 speakingOnly: reduceMotion)
                        draw(frame, in: &context, size: size, isLowPower: lowPower.isEnabled)
                    }
                }
                .task(id: motion.isAtRest && scenePhase == .active) {
                    guard scenePhase == .active else { return }
                    await motion.pollWhileAtRest { levels?.voiceLevel(forUserID: userID) ?? 0 }
                }
            }
        }
        .frame(width: diameter + 2 * reachHere, height: diameter + 2 * reachHere)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The reach scales with the avatar, so a group's small faces get a proportionate ring.
    private var reachHere: CGFloat {
        Self.reach * magnitude * min(1, diameter / 120)
    }

    private var frameInterval: Double {
        reduceMotion || lowPower.isEnabled ? 1.0 / 30.0 : 1.0 / 60.0
    }

    private func draw(_ frame: NativeCallVoiceMotion.Frame, in context: inout GraphicsContext, size: CGSize, isLowPower: Bool) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = diameter / 2
        let scale = reachHere / Self.reach
        let energy = frame.energy

        if reduceMotion {
            // No shape, no travel: the ring only brightens while the voice is on.
            var circle = Path()
            circle.addEllipse(in: CGRect(x: center.x - radius - 6 * scale, y: center.y - radius - 6 * scale,
                                         width: 2 * (radius + 6 * scale), height: 2 * (radius + 6 * scale)))
            context.stroke(circle, with: .color(tint.opacity(0.25 * restingVisibility + 0.6 * energy)), lineWidth: 2.5)
            return
        }

        let layers = isLowPower ? 1 : 2
        // A small avatar's ring is finer, as the lab's pill halo was.
        let line = max(0.75, min(1, scale))
        for layer in (0..<layers).reversed() {
            let seed = Double(layer) * 2.1
            let flutter = isLowPower ? 0 : NativeCallVoiceFlutter.value(at: frame.time, seed: seed)
            let bend = energy * (8 + 4 * flutter) * scale
            let base = radius + (7 + 5 * energy + CGFloat(layer) * 3 * energy) * scale
            var path = Path()
            let steps = 120
            for step in 0...steps {
                let angle = Double(step) / Double(steps) * 2 * .pi
                let shape = 0.55 * sin(3 * angle + frame.travel * 1.3 + seed)
                    + 0.3 * sin(5 * angle - frame.travel * 0.9 + seed * 0.5)
                    + 0.15 * sin(2 * angle + frame.travel * 0.5)
                let distance = base + bend * shape
                let point = CGPoint(x: center.x + distance * cos(angle), y: center.y + distance * sin(angle))
                step == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            path.closeSubpath()
            if layer == 0 {
                context.fill(path, with: .color(tint.opacity(0.14 * energy)))
                context.stroke(path, with: .color(tint.opacity(0.3 * restingVisibility + 0.6 * energy)), lineWidth: (2 + energy) * line)
            } else {
                context.stroke(path, with: .color(tint.opacity(0.35 * energy)), lineWidth: 4 * line)
            }
        }
    }
}
