//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SwiftUI

// AGENT-PLATFORM (Brief 0083, decision 308): the reviewer path's text links ("Learn more", "Can't confirm?").
// Compound's `.textLink` draws them in the primary text colour; the storyboard draws them in the accent.
// Phase 3 moves this into Spiral's design-system target.

extension ButtonStyle where Self == SpiralLinkButtonStyle {
    /// A text link in the accent colour, at least 44 pt tall.
    static var spiralLink: SpiralLinkButtonStyle {
        SpiralLinkButtonStyle()
    }
}

struct SpiralLinkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityShowButtonShapes) private var accessibilityShowButtonShapes
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.compound.bodyLGSemibold)
            .underline(accessibilityShowButtonShapes)
            .multilineTextAlignment(.leading)
            .foregroundStyle(isEnabled ? .compound.textActionAccent : .compound.textDisabled)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .frame(minHeight: CompoundDesignTokens.space11X)
            .contentShape(Rectangle())
    }
    
    /// The same as Compound's buttons.
    private var pressedOpacity: Double {
        colorScheme == .light ? 0.3 : 0.6
    }
}
