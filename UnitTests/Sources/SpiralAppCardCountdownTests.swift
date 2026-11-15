//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, § 5.79): the countdown a post's card draws.
//

@testable import Spiral
import SwiftUI
import Testing

@MainActor
struct SpiralAppCardCountdownTests {
    /// Draws while its moment is ahead, and nothing once it has passed.
    ///
    /// It was a `TimelineView(.explicit([moment]))` gated on
    /// `context.date < moment`, and the first render of an explicit schedule
    /// is dated at its first entry — the moment itself — so on the phone the
    /// card said nothing with twelve days to go.
    @Test
    func aCountdownDrawsUntilItsMoment() {
        let ahead = ImageRenderer(content: SpiralAppCardCountdown(moment: .now.addingTimeInterval(12 * 24 * 3600)))
        #expect((ahead.uiImage?.size.width ?? 0) > 0)

        let past = ImageRenderer(content: SpiralAppCardCountdown(moment: .now.addingTimeInterval(-60)))
        #expect((past.uiImage?.size.width ?? 0) == 0)
    }
}
