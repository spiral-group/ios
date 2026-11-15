//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Foundation
@testable import Spiral
import Testing

/// Question 390: an agent's Peek takes one of eight system hues, the same on every launch and device; every
/// colour carries the white Peek at 3:1, and every two of them are told apart (CIEDE2000 ≥ 15); people and rooms keep
/// the one monogram.
struct AgentAvatarPaletteTests {
    private let agents = ["@assistant-alex:spiral.example", "@assistant-mira:spiral.example", "@agent-research:spiral.example",
                          "@agent-notes:spiral.example", "@assistant-sam:spiral.example", "@agent-support:spiral.example"]

    /// Fixed values: a launch-seeded hash (`hashValue`) would fail this on the next run.
    @Test
    func theColourComesFromTheFullIDAloneAndNeverChanges() {
        #expect(agents.map { AgentAvatarPalette.stableIndex(of: $0, count: 8) } == [7, 6, 4, 6, 3, 1])
        // The server is part of the ID: the same localpart elsewhere is another agent.
        #expect(["@assistant-alex:example.org", "@assistant-alex:matrix.example"].map { AgentAvatarPalette.stableIndex(of: $0, count: 6) } == [4, 2])
        #expect(AgentAvatarPalette.gradient(for: agents[0]).name == "Rose")
    }

    @Test
    func everyAgentOnOneServerCanTakeEveryColour() {
        let indices = (0..<200).map { AgentAvatarPalette.stableIndex(of: "@assistant-person-\($0):spiral.example", count: 8) }
        #expect(Set(indices) == Set(AgentAvatarPalette.gradients.indices))
        #expect(AgentAvatarPalette.gradients.count == 8)
    }

    @Test
    func theWhitePeekReadsAtLeast3To1OnEveryColour() {
        for gradient in AgentAvatarPalette.gradients {
            #expect(gradient.light.whiteContrast >= 3, "\(gradient.name) light")
            #expect(gradient.dark.whiteContrast >= 3, "\(gradient.name) dark")
        }
    }

    /// Question 393: the agent badge fills with the colour's midpoint and carries the white Peek on it.
    @Test
    func theWhitePeekReadsAtLeast3To1OnEverySolidColour() {
        #expect(AgentAvatarGradient.Stops(top: 0x204060, bottom: 0x406080).midpoint == 0x305070)
        for gradient in AgentAvatarPalette.gradients {
            #expect(AgentAvatarGradient.Stops.whiteContrast(on: gradient.light.midpoint) >= 3, "\(gradient.name) light")
            #expect(AgentAvatarGradient.Stops.whiteContrast(on: gradient.dark.midpoint) >= 3, "\(gradient.name) dark")
        }
    }

    /// The operator's measure: no two colours closer than ΔE 15 (CIEDE2000) between their gradients' midpoints.
    @Test
    func everyTwoColoursAreToldApart() {
        for (first, second) in pairs(AgentAvatarPalette.gradients) {
            #expect(deltaE2000(midpoint(first.light), midpoint(second.light)) >= 15, "\(first.name) and \(second.name) in light")
            #expect(deltaE2000(midpoint(first.dark), midpoint(second.dark)) >= 15, "\(first.name) and \(second.name) in dark")
        }
    }

    @Test
    func peopleAndRoomsKeepTheMonogram() {
        #expect(AgentAvatar.fallback(contentID: "@lena:spiral.example") == .letter)
        #expect(AgentAvatar.fallback(contentID: "!agent-research:spiral.example") == .letter)
        #expect(AgentAvatar.fallback(contentID: "#assistant-alex:spiral.example") == .letter)
    }

    // MARK: - Helpers

    private typealias Lab = (l: Double, a: Double, b: Double)

    private func pairs<T>(_ items: [T]) -> [(T, T)] {
        items.indices.flatMap { i in items.indices.filter { $0 > i }.map { (items[i], items[$0]) } }
    }

    /// The mean of the two stops in CIELAB (D65).
    private func midpoint(_ stops: AgentAvatarGradient.Stops) -> Lab {
        let top = lab(stops.top), bottom = lab(stops.bottom)
        return ((top.l + bottom.l) / 2, (top.a + bottom.a) / 2, (top.b + bottom.b) / 2)
    }

    private func lab(_ rgb: UInt32) -> Lab {
        let channel = { (shift: UInt32) -> Double in
            let value = Double((rgb >> shift) & 0xFF) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let (r, g, b) = (channel(16), channel(8), channel(0))
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
        let f = { (t: Double) -> Double in t > 216 / 24389 ? cbrt(t) : (24389 / 27 * t + 16) / 116 }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }

    /// CIEDE2000 (Sharma, Wu and Dalal, 2005), with kL = kC = kH = 1.
    private func deltaE2000(_ first: Lab, _ second: Lab) -> Double {
        let radians = { (degrees: Double) in degrees * .pi / 180 }
        let pow25To7 = pow(25.0, 7.0)
        let meanC = (hypot(first.a, first.b) + hypot(second.a, second.b)) / 2
        let g = 0.5 * (1 - sqrt(pow(meanC, 7.0) / (pow(meanC, 7.0) + pow25To7)))
        let a1 = (1 + g) * first.a, a2 = (1 + g) * second.a
        let c1 = hypot(a1, first.b), c2 = hypot(a2, second.b)
        let hue = { (a: Double, b: Double) -> Double in
            let degrees = atan2(b, a) * 180 / .pi
            return degrees < 0 ? degrees + 360 : degrees
        }
        let h1 = hue(a1, first.b), h2 = hue(a2, second.b)
        var deltaH = h2 - h1
        if c1 * c2 == 0 { deltaH = 0 } else if deltaH > 180 { deltaH -= 360 } else if deltaH < -180 { deltaH += 360 }
        let deltaL = second.l - first.l
        let deltaC = c2 - c1
        let deltaBigH = 2 * sqrt(c1 * c2) * sin(radians(deltaH / 2))
        let meanL = (first.l + second.l) / 2
        let meanCPrime = (c1 + c2) / 2
        var meanH = h1 + h2
        if c1 * c2 != 0 {
            meanH = abs(h1 - h2) <= 180 ? (h1 + h2) / 2 : (h1 + h2 < 360 ? (h1 + h2 + 360) / 2 : (h1 + h2 - 360) / 2)
        }
        let t = 1 - 0.17 * cos(radians(meanH - 30)) + 0.24 * cos(radians(2 * meanH))
            + 0.32 * cos(radians(3 * meanH + 6)) - 0.20 * cos(radians(4 * meanH - 63))
        let deltaTheta = 30 * exp(-pow((meanH - 275) / 25, 2.0))
        let rC = 2 * sqrt(pow(meanCPrime, 7.0) / (pow(meanCPrime, 7.0) + pow25To7))
        let sL = 1 + 0.015 * pow(meanL - 50, 2.0) / sqrt(20 + pow(meanL - 50, 2.0))
        let sC = 1 + 0.045 * meanCPrime
        let sH = 1 + 0.015 * meanCPrime * t
        let rT = -sin(radians(2 * deltaTheta)) * rC
        let l = deltaL / sL, c = deltaC / sC, h = deltaBigH / sH
        return sqrt(l * l + c * c + h * h + rT * c * h)
    }
}
