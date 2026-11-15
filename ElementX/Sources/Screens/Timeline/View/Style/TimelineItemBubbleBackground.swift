//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SpiralTokens // AGENT-PLATFORM (Brief 0083)
import SwiftUI

extension View {
    /// - Parameters:
    ///   - insets: defaults to what we use for file timeline items, text uses custom values
    ///   - color: self explanatory, defaults to subtle secondary
    ///   - borderColor: an optional colour for a border around the bubble
    ///   - cornerRadius: the bubble's, unless it's one of the chat's cards
    ///   - shadowClearance: how far above the bubble its row ends, if the bubble casts the room background's shadow
    func bubbleBackground(insets: EdgeInsets = .init(top: 8, leading: 12, bottom: 8, trailing: 12),
                          color: @autoclosure @MainActor () -> Color? = .compound.bgSubtleSecondary,
                          borderColor: @autoclosure @MainActor () -> Color? = nil,
                          cornerRadius: CGFloat = SpiralRadius.bubble,
                          shadowClearance: CGFloat? = nil) -> some View {
        modifier(TimelineItemBubbleBackgroundModifier(insets: insets,
                                                      color: color(),
                                                      borderColor: borderColor(),
                                                      cornerRadius: cornerRadius,
                                                      shadowClearance: shadowClearance))
    }
}

// AGENT-PLATFORM (Brief 0083, the room's timeline): every corner keeps the bubble's continuous radius, grouped or
// not, as Messages draws it. Element squared the corners on the sender's side within a group.
private struct TimelineItemBubbleBackgroundModifier: ViewModifier {
    let insets: EdgeInsets
    var color: Color?
    var borderColor: Color?
    var cornerRadius: CGFloat
    var shadowClearance: CGFloat?
    
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
    
    @ViewBuilder
    func body(content: Content) -> some View {
        let bubble = content
            .padding(insets)
            .background(color)
            .clipShape(shape)
            .overlay {
                if let borderColor {
                    shape.stroke(borderColor)
                }
            }
        
        if let shadowClearance {
            bubble.chatElevation(cornerRadius: cornerRadius, rowClearance: shadowClearance)
        } else {
            bubble
        }
    }
}
