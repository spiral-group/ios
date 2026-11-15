//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 383): the speaking mark on a group's video tiles, the operator's pick (the Aura
// edge): the tile's own edge bends with the speaker's voice through the calibrated core, as the ring does round a face.
// Nothing shows in silence, and the timeline pauses there, so a quiet tile costs no frame.

import Compound
import SwiftUI

struct NativeCallTileAuraEdge: View {
    let userID: String
    let cornerRadius: CGFloat

    /// How far the edge's outer layer reaches past the tile at its loudest, for whoever lays tiles out.
    static let reach: CGFloat = 6

    private static let steps = 200

    @Environment(\.nativeCallVoiceLevels) private var levels
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var motion = NativeCallVoiceMotion(attack: 0.12, release: 0.5, speechSpeed: 1.4)
    @State private var lowPower = NativeCallLowPowerMode.shared
    @State private var outline = OutlineSamples()

    var body: some View {
        Group {
            if levels != nil {
                SwiftUI.TimelineView(.animation(minimumInterval: reduceMotion || lowPower.isEnabled ? 1.0 / 30.0 : 1.0 / 60.0,
                                                paused: motion.isAtRest || scenePhase != .active)) { timeline in
                    Canvas { context, size in
                        let frame = motion.frame(at: timeline.date.timeIntervalSinceReferenceDate,
                                                 amplitude: levels?.voiceLevel(forUserID: userID) ?? 0,
                                                 speakingOnly: reduceMotion)
                        draw(frame, in: &context, size: size)
                    }
                }
                .task(id: motion.isAtRest && scenePhase == .active) {
                    guard scenePhase == .active else { return }
                    await motion.pollWhileAtRest { levels?.voiceLevel(forUserID: userID) ?? 0 }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ frame: NativeCallVoiceMotion.Frame, in context: inout GraphicsContext, size: CGSize) {
        let energy = frame.energy
        guard energy > 0.01 else { return }
        let accent = Color.compound.iconAccentPrimary

        if reduceMotion {
            // Still: only the edge's strength follows speaking.
            let edge = RoundedRectangle(cornerRadius: max(0, cornerRadius - 1.5), style: .continuous)
                .path(in: CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5))
            context.stroke(edge, with: .color(accent.opacity(0.4 + 0.55 * energy)), lineWidth: 2.5)
            return
        }

        // The outline is walked once per size; a frame only bends it.
        let samples = outline.samples(size: size, cornerRadius: cornerRadius, count: Self.steps)
        let layers = lowPower.isEnabled ? [0] : [1, 0]
        for layer in layers {
            let seed = Double(layer) * 2.1
            var path = Path()
            for (step, sample) in samples.enumerated() {
                let phase = Double(step) / Double(Self.steps) * 2 * .pi
                let shape = 0.55 * sin(7 * phase + frame.travel * 1.3 + seed) + 0.3 * sin(11 * phase - frame.travel * 0.9 + seed)
                let offset = 1 + energy * (3 + 2 * shape) + Double(layer) * 2 * energy
                let moved = CGPoint(x: sample.point.x + sample.normal.dx * offset, y: sample.point.y + sample.normal.dy * offset)
                step == 0 ? path.move(to: moved) : path.addLine(to: moved)
            }
            path.closeSubpath()
            context.stroke(path, with: .color(layer == 0 ? accent.opacity(0.4 + 0.55 * energy) : accent.opacity(0.3 * energy)),
                           lineWidth: layer == 0 ? 2 + energy : 4)
        }
    }
}

/// The tile's outline sampled at even steps, kept until the tile's size changes.
private final class OutlineSamples {
    private var key: (size: CGSize, cornerRadius: CGFloat)?
    private var samples: [NativeCallRoundedPerimeter.Sample] = []

    func samples(size: CGSize, cornerRadius: CGFloat, count: Int) -> [NativeCallRoundedPerimeter.Sample] {
        if let key, key.size == size, key.cornerRadius == cornerRadius {
            return samples
        }
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 5.5, dy: 5.5)
        samples = NativeCallRoundedPerimeter(rect: rect, radius: max(0, cornerRadius - 5)).samples(count: count)
        key = (size, cornerRadius)
        return samples
    }
}

/// A rounded rectangle's outline walked by arc length, with the outward normal at each point.
struct NativeCallRoundedPerimeter {
    struct Sample {
        let point: CGPoint
        let normal: CGVector
    }

    let rect: CGRect
    let radius: CGFloat
    let length: CGFloat

    init(rect: CGRect, radius: CGFloat) {
        self.rect = rect
        self.radius = min(radius, min(rect.width, rect.height) / 2)
        length = 2 * (rect.width - 2 * self.radius) + 2 * (rect.height - 2 * self.radius) + 2 * .pi * self.radius
    }

    /// `count + 1` points at even steps, clockwise from the top edge's left end back to it.
    func samples(count: Int) -> [Sample] {
        (0...count).map { step in
            let (point, normal) = point(at: CGFloat(step) / CGFloat(count) * length)
            return Sample(point: point, normal: normal)
        }
    }

    /// Clockwise from the top edge's left end.
    func point(at distance: CGFloat) -> (CGPoint, CGVector) {
        let width = rect.width - 2 * radius
        let height = rect.height - 2 * radius
        let arc = .pi / 2 * radius
        var remaining = distance.truncatingRemainder(dividingBy: max(length, 0.001))

        if remaining <= width {
            return (CGPoint(x: rect.minX + radius + remaining, y: rect.minY), CGVector(dx: 0, dy: -1))
        }
        remaining -= width
        if remaining <= arc {
            return corner(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), start: -.pi / 2, along: remaining)
        }
        remaining -= arc
        if remaining <= height {
            return (CGPoint(x: rect.maxX, y: rect.minY + radius + remaining), CGVector(dx: 1, dy: 0))
        }
        remaining -= height
        if remaining <= arc {
            return corner(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), start: 0, along: remaining)
        }
        remaining -= arc
        if remaining <= width {
            return (CGPoint(x: rect.maxX - radius - remaining, y: rect.maxY), CGVector(dx: 0, dy: 1))
        }
        remaining -= width
        if remaining <= arc {
            return corner(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), start: .pi / 2, along: remaining)
        }
        remaining -= arc
        if remaining <= height {
            return (CGPoint(x: rect.minX, y: rect.maxY - radius - remaining), CGVector(dx: -1, dy: 0))
        }
        remaining -= height
        return corner(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius), start: .pi, along: min(remaining, arc))
    }

    private func corner(center: CGPoint, start: Double, along: CGFloat) -> (CGPoint, CGVector) {
        let angle = start + Double(radius > 0 ? along / radius : 0)
        return (CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)), CGVector(dx: cos(angle), dy: sin(angle)))
    }
}
