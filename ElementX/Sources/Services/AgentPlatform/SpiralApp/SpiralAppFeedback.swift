//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066 step 6.12): the tap answered in the hand.
//
// A generated post is a web document in a sandboxed frame; nothing it can do
// reaches the Taptic engine. This is the whole of `ui.haptic` on the native
// side — a switch over five strengths, generators kept alive between taps so
// a game does not pay the warm-up on every hit.
//

import UIKit

@MainActor
enum SpiralAppFeedback {
    private static let impacts: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [
        .light: UIImpactFeedbackGenerator(style: .light),
        .medium: UIImpactFeedbackGenerator(style: .medium),
        .heavy: UIImpactFeedbackGenerator(style: .heavy)
    ]

    private static let notice = UINotificationFeedbackGenerator()

    /// Play one, named as the SDK names it. An unknown name is a light tap
    /// rather than nothing: a post from a newer runtime still feels alive.
    static func play(_ strength: String) {
        switch strength {
        case "medium":
            impacts[.medium]?.impactOccurred()
        case "heavy":
            impacts[.heavy]?.impactOccurred()
        case "success":
            notice.notificationOccurred(.success)
        case "warning":
            notice.notificationOccurred(.warning)
        default:
            impacts[.light]?.impactOccurred()
        }
    }

    /// Warm the generators so the first tap of a game is not the slow one.
    static func prepare() {
        for generator in impacts.values {
            generator.prepare()
        }
        notice.prepare()
    }
}
