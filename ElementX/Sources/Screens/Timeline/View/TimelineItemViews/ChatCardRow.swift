//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): the row every card in a chat shares: calls, an agent's notices, a post being
// generated and a blocked file. A disc with a white glyph, a title, and what the card has to say under it.
//

import Compound
import SpiralTokens
import SwiftUI

enum ChatCardLayout {
    /// What a card's row leaves above and below the card.
    static let rowPadding: CGFloat = 5
}

extension View {
    /// A card's surface: its side's bubble, with the room's shadow.
    func chatCardBubble(cornerRadius: CGFloat = SpiralRadius.callBubble) -> some View {
        modifier(ChatCardBubbleModifier(cornerRadius: cornerRadius))
    }
}

private struct ChatCardBubbleModifier: ViewModifier {
    @Environment(\.ownBubbleInk) private var ink
    @Environment(\.isChatBackgroundDrawn) private var isChatBackgroundDrawn
    
    let cornerRadius: CGFloat
    
    private var fill: Color {
        if let inkFill = ink?.fill {
            inkFill
        } else if isChatBackgroundDrawn {
            .spiral.chatBackgroundSurface
        } else {
            .compound._bgBubbleIncoming
        }
    }
    
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(fill, in: shape)
            .chatElevation(cornerRadius: cornerRadius, rowClearance: ChatCardLayout.rowPadding)
            .contentShape(shape)
    }
}

struct ChatCardRow<Content: View>: View {
    @Environment(\.ownBubbleInk) private var ink
    @Environment(\.colorScheme) private var colorScheme
    
    @ScaledMetric(relativeTo: .subheadline) private var titleSize = 15.5
    @ScaledMetric private var discSize = 38
    
    let icon: KeyPath<CompoundIcons, Image>
    /// An SF Symbol Compound has no key for (Apple's logo, 1.0.3), drawn instead of `icon` the way
    /// Spiral draws Compound's keys; `icon` stays the fallback.
    var systemSymbol: (name: String, label: String)?
    var isCritical = false
    /// In a group, who a card that isn't yours came from.
    var sender: TimelineItemSender?
    let title: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            disc
            
            VStack(alignment: .leading, spacing: 2) {
                if let sender {
                    Text(sender.displayName ?? sender.id)
                        .font(.compound.bodySMSemibold)
                        .foregroundStyle(SenderHue(userID: sender.id).color)
                        .lineLimit(1)
                }
                
                Text(title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(titleColor)
                
                content()
            }
        }
    }
    
    private var disc: some View {
        glyph
            .foregroundStyle(glyphColor)
            .frame(width: min(discSize, 57), height: min(discSize, 57)) // Unbounded, AX3 made it a third of the card.
            .background(discFill, in: .circle)
            .accessibilityHidden(true)
    }
    
    private var glyph: CompoundIcon {
        if let systemSymbol {
            CompoundIcon(systemName: systemSymbol.name, label: systemSymbol.label, size: .custom(19), relativeTo: .compound.bodyMD)
        } else {
            CompoundIcon(icon, size: .custom(19), relativeTo: .compound.bodyMD)
        }
    }
    
    private var titleColor: Color {
        if let ink {
            ink.text // Red reads about 1.1:1 on the own blue, so the disc says it there.
        } else if isCritical, colorScheme == .light {
            .compound.textCriticalPrimary
        } else {
            // Dark's red read 3.66:1 on the card (#E06060 on #323234) and no red token reaches 4.5:1: the disc says it.
            .compound.textPrimary
        }
    }
    
    private var discFill: Color {
        switch (isCritical, ink) {
        case (true, .some(let ink)): ink.criticalMarkDisc ?? .compound.bgCriticalPrimary
        case (true, .none): .compound.bgCriticalPrimary
        case (false, .some): .white.opacity(0.2)
        case (false, .none): OwnBubbleStyle.fill
        }
    }
    
    private var glyphColor: Color {
        isCritical && ink?.criticalMarkDisc != nil ? .compound.iconCriticalPrimary : .compound.iconOnSolidPrimary
    }
}
