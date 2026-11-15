//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): a call in the timeline is a part of the conversation, so it's a bubble on the
// side of whoever called, with a disc for the call's glyph. A call isn't an event item, so it lays out its own row.
//

import Compound
import SpiralTokens
import SwiftUI

struct TimelineCallBubble<Details: View, Accessory: View>: View {
    @Environment(\.timelineContext) private var context
    
    let sender: TimelineItemSender
    let isDM: Bool
    let isOutgoing: Bool
    var isMissed = false
    let icon: KeyPath<CompoundIcons, Image>
    let title: String
    /// The line under the title, such as the call's length and its time.
    @ViewBuilder let details: () -> Details
    /// What can be pressed, under the line.
    @ViewBuilder let accessory: () -> Accessory
    
    private var ink: OwnBubbleInk? {
        isOutgoing ? .solid : nil
    }
    
    /// In a group the bubble's side says it was someone else, and only this says who.
    private var showsSender: Bool {
        !isDM && !isOutgoing
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if showsSender {
                TimelineSenderAvatarView(sender: sender)
                    .accessibilityHidden(true)
                    .onTapGesture {
                        context?.send(viewAction: .tappedOnSenderDetails(sender: sender))
                    }
            }
            
            bubble
        }
        .padding(isOutgoing ? .leading : .trailing, 48) // As a message's: differentiates the sides.
        .padding(.horizontal, 16)
        .padding(.vertical, ChatCardLayout.rowPadding)
        .frame(maxWidth: .infinity, alignment: isOutgoing ? .trailing : .leading)
    }
    
    private var bubble: some View {
        ChatCardRow(icon: icon, isCritical: isMissed, sender: showsSender ? sender : nil, title: title) {
            HStack(spacing: 6) {
                details()
            }
            .font(.compound.bodyXS)
            .foregroundStyle(ink?.secondaryText ?? .compound.textSecondary)
            
            accessory()
                .padding(.top, 6)
        }
        .padding(.vertical, 8)
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .chatCardBubble()
        .environment(\.ownBubbleInk, ink)
        .frame(maxWidth: 340, alignment: isOutgoing ? .trailing : .leading)
    }
}
