//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (question 390, operator 2026-11-09): an exception to decision 328 for agents. The Peek of an agent
// without a picture takes a colour of its own, from eight system hues, by a stable hash of the agent's Matrix ID.
// People and rooms keep 328's one monogram.
//
// The colours are literals here until they move into agent-brand-assets (tokens/colors.json, roles in
// tokens/spiral.json), whose iOS generator first needs a kind for a graphic that reads at 3:1 at every size: it only
// knows letters, which need 4.5:1 at 32 pt and under.
//

import SwiftUI

/// One agent colour: a gradient from top to bottom, with a value for each theme. The white Peek reads at least 3:1 on
/// either stop, the graphics threshold, from the smallest avatar (16 pt) up.
struct AgentAvatarGradient: Identifiable {
    /// A gradient's two stops, as sRGB hex.
    struct Stops: Equatable {
        let top: UInt32
        let bottom: UInt32

        /// The two stops' mean, channel by channel: the gradient as one solid colour.
        var midpoint: UInt32 {
            [16, 8, 0].reduce(UInt32(0)) { rgb, shift in
                rgb | ((((top >> shift) & 0xFF) + ((bottom >> shift) & 0xFF)) / 2) << shift
            }
        }
    }

    let name: String
    let light: Stops
    let dark: Stops
    let colors: [Color]
    /// The colour as one fill, for a mark too small to show the gradient: the agent badge (question 393).
    let solid: Color

    var id: String {
        name
    }

    init(_ name: String, light: Stops, dark: Stops) {
        self.name = name
        self.light = light
        self.dark = dark
        colors = [Color(light: light.top, dark: dark.top), Color(light: light.bottom, dark: dark.bottom)]
        solid = Color(light: light.midpoint, dark: dark.midpoint)
    }
}

/// System hues (the operator's pick, question 390): eight calm hues around the wheel at the lightness of iOS's
/// monogram, every two at least 15 apart (CIEDE2000, between the gradients' midpoints) in each theme.
enum AgentAvatarPalette {
    // OKLCH: light 0.63 → 0.53, dark 0.55 → 0.42, the hue turning 16° from top to bottom as iOS's monogram does.
    // Indigo is deeper (0.41 → 0.31) and Teal's and Rose's dark values moved, so that each parts from its neighbours.
    static let gradients: [AgentAvatarGradient] = [
        .init("Coral", light: .init(top: 0xBF6F6F, bottom: 0xA54F38), dark: .init(top: 0xA2595A, bottom: 0x7D331F)),
        .init("Amber", light: .init(top: 0xB57951, bottom: 0x945F0E), dark: .init(top: 0x99633E, bottom: 0x6C4300)),
        .init("Green", light: .init(top: 0x6D9664, bottom: 0x327D53), dark: .init(top: 0x587D50, bottom: 0x165B38)),
        .init("Teal", light: .init(top: 0x4F988D, bottom: 0x017B7F), dark: .init(top: 0x377E77, bottom: 0x05565C)),
        .init("Sky", light: .init(top: 0x4294B6, bottom: 0x2771A6), dark: .init(top: 0x2E7B9A, bottom: 0x09517F)),
        .init("Indigo", light: .init(top: 0x16488E, bottom: 0x1F1D7A), dark: .init(top: 0x134182, bottom: 0x151062)),
        .init("Violet", light: .init(top: 0x8E7DBB, bottom: 0x81589A), dark: .init(top: 0x76679F, bottom: 0x5F3B74)),
        .init("Rose", light: .init(top: 0xB37194, bottom: 0x9F4E66), dark: .init(top: 0xA55E85, bottom: 0x86334E))
    ]

    /// The colour of `agentID`'s Peek: the same on every screen, every launch and every device, as it comes from the
    /// full Matrix ID alone.
    static func gradient(for agentID: String) -> AgentAvatarGradient {
        gradients[stableIndex(of: agentID, count: gradients.count)]
    }

    /// FNV-1a over the ID's UTF-8, reduced by its high bits. `hashValue` is seeded on every launch, so it can't be used;
    /// and agents on one server share a long suffix, which a plain modulo of a weaker hash turns into few colours.
    nonisolated static func stableIndex(of agentID: String, count: Int) -> Int {
        let hash = agentID.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        return Int((UInt64(hash) &* UInt64(count)) >> 32)
    }
}

#if DEBUG || SPIRAL_STAGING
extension AgentAvatarGradient.Stops {
    /// The white Peek's WCAG contrast on the lighter of the two stops.
    var whiteContrast: Double {
        min(Self.whiteContrast(on: top), Self.whiteContrast(on: bottom))
    }

    static func whiteContrast(on rgb: UInt32) -> Double {
        let channels = [rgb >> 16, rgb >> 8, rgb].map { Double($0 & 0xFF) / 255 }
        let linear = channels.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        return 1.05 / (luminance + 0.05)
    }
}
#endif

private extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                           green: CGFloat((rgb >> 8) & 0xFF) / 255,
                           blue: CGFloat(rgb & 0xFF) / 255,
                           alpha: 1)
        })
    }
}
