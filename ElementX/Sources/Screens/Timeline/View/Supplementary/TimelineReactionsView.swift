//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// AGENT-PLATFORM (Brief 0083, question 359): one for all the rows, as each row making its own showed in the cost of a new row.
private let feedbackGenerator = UIImpactFeedbackGenerator(style: .heavy)

struct TimelineReactionsView: View {
    @Environment(\.layoutDirection) private var layoutDirection: LayoutDirection
    @Environment(\.timelineRowContext.areReactionsCollapsed) private var isCollapsed // AGENT-PLATFORM (Brief 0083, question 359)
    
    let context: TimelineViewModel.Context?
    let itemID: TimelineItemIdentifier
    let reactions: [AggregatedReaction]
    var isLayoutRTL = false
    
    var reactionsLayoutDirection: LayoutDirection {
        guard isLayoutRTL else { return layoutDirection }
        return layoutDirection == .leftToRight ? .rightToLeft : .leftToRight
    }
    
    var body: some View {
        layout {
            ForEach(reactions) { reaction in
                TimelineReactionButton(reaction: reaction) { key in
                    feedbackGenerator.impactOccurred()
                    context?.send(viewAction: .toggleReaction(key: key, itemID: itemID))
                } showReactionSummary: { key in
                    context?.send(viewAction: .displayReactionSummary(itemID: itemID, key: key))
                }
                .reactionLayoutItem(.reaction)
                .environment(\.layoutDirection, layoutDirection)
            }
            
            if isCollapsible {
                Button {
                    context?.reactionsCollapsed[itemID] = !isCollapsed
                } label: {
                    TimelineCollapseButtonLabel(collapsed: isCollapsed)
                        .transaction { $0.animation = nil }
                }
                .reactionLayoutItem(.expandCollapse)
                .environment(\.layoutDirection, layoutDirection)
            }
            
            Button {
                context?.send(viewAction: .displayEmojiPicker(itemID: itemID))
            } label: {
                TimelineReactionAddMoreButtonLabel()
            }
            .reactionLayoutItem(.addMore)
        }
        .environment(\.layoutDirection, reactionsLayoutDirection)
        .animation(.easeInOut(duration: 0.1).disabledDuringTests(), value: reactions)
        .padding(.leading, 4)
    }
    
    // MARK: - Private
    
    private var isCollapsible: Bool {
        reactions.count > 5
    }
    
    private var layout: AnyLayout {
        if isCollapsible {
            return AnyLayout(CollapsibleReactionLayout(itemSpacing: 4,
                                                       rowSpacing: 4,
                                                       collapsed: isCollapsed,
                                                       rowsBeforeCollapsible: 2))
        }
        
        return AnyLayout(HStackLayout(spacing: 4.0))
    }
}

// AGENT-PLATFORM (Brief 0083, the room's timeline): a capsule under the bubble, filled with the accent's tint when
// it's your reaction, as Chats' counts are. Element drew a rounded square with a ring of the canvas's colour, over
// the bubble's edge, and outlined your reactions.
/// The pill shape for the label that surrounds both the reaction and collapse buttons.
struct TimelineReactionButtonLabel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme // AGENT-PLATFORM (Brief 0083)
    
    var isHighlighted = false
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        content()
            .background(isHighlighted ? Color.compound.bgBadgeAccent : .compound.bgSubtleSecondary, in: .capsule)
            // AGENT-PLATFORM (Brief 0083): in dark the accent's tint sits close to the grey of the others, so yours
            // also takes a 1 pt accent outline.
            .overlay {
                if isHighlighted, colorScheme == .dark {
                    Capsule().strokeBorder(Color.compound.iconAccentPrimary, lineWidth: 1)
                }
            }
            .accessibilityElement(children: .combine)
    }
}

struct TimelineCollapseButtonLabel: View {
    var collapsed: Bool
    @ScaledMetric(relativeTo: .subheadline) private var lineHeight = 20
    
    var body: some View {
        TimelineReactionButtonLabel {
            Text(collapsed ? L10n.screenRoomTimelineReactionsShowMore : L10n.screenRoomTimelineReactionsShowLess)
                .frame(height: lineHeight, alignment: .center)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .font(.compound.bodyMD)
                .foregroundColor(.compound.textPrimary)
        }
    }
}

struct TimelineReactionButton: View {
    let reaction: AggregatedReaction
    let toggleReaction: (String) -> Void
    let showReactionSummary: (String) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var lineHeight = 20
    
    private var accessibilityLabel: String {
        if reaction.isHighlighted {
            return reaction.count > 1 ? L10n.tr("Localizable", "screen_room_timeline_reaction_including_you_a11y", reaction.count - 1, reaction.displayKey) : L10n.screenRoomTimelineReactionYouA11y(reaction.displayKey)
        }
        return L10n.tr("Localizable", "screen_room_timeline_reaction_a11y", reaction.count, reaction.displayKey)
    }
    
    private var toggleReactionAccessibilityActionName: String {
        reaction.isHighlighted ? L10n.a11yRemoveReaction(reaction.displayKey) : L10n.a11yAddReaction(reaction.displayKey)
    }
    
    var body: some View {
        label
            .onTapGesture {
                toggleReaction(reaction.key)
            }
            .longPressWithFeedback {
                showReactionSummary(reaction.key)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(toggleReactionAccessibilityActionName)
            .accessibilityAction(named: L10n.screenRoomTimelineReactionsShowReactionsSummary) {
                showReactionSummary(reaction.key)
            }
    }
    
    var label: some View {
        TimelineReactionButtonLabel(isHighlighted: reaction.isHighlighted) {
            HStack(spacing: 4) {
                // Designs have bodyMD for the key but practically this makes
                // emojis too big. bodySM gives a more appropriate size when compared
                // to the count text and the lineHeight/padding in the designs.
                Text(reaction.displayKey)
                    .font(.compound.bodySM)
                if reaction.count > 1 {
                    Text(String(reaction.count))
                        .font(.compound.bodySMSemibold) // AGENT-PLATFORM (Brief 0083)
                        .foregroundColor(textColor)
                }
            }
            .frame(height: lineHeight, alignment: .center)
            .padding(.vertical, 6)
            .padding(.horizontal, 10) // AGENT-PLATFORM (Brief 0083)
        }
    }
    
    // AGENT-PLATFORM (Brief 0083): your reaction's count in the accent, on its tint.
    var textColor: Color {
        reaction.isHighlighted ? Color.compound.textBadgeAccent : .compound.textSecondary
    }
}

// AGENT-PLATFORM (Brief 0083): the glyph alone, at a reaction's height, so it reads as an action beside them.
struct TimelineReactionAddMoreButtonLabel: View {
    var body: some View {
        CompoundIcon(\.reactionAdd, size: .small, relativeTo: .compound.bodySM)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .foregroundColor(.compound.iconSecondary)
            // A 44 pt target around the 32 pt glyph, without moving the pills.
            .padding(6)
            .contentShape(.rect)
            .padding(-6)
            .accessibilityLabel(L10n.actionReact)
    }
}

struct TimelineReactionViewPreviewsContainer: View {
    var body: some View {
        VStack(spacing: 8) {
            TimelineReactionsView(context: TimelineViewModel.mock.context,
                                  itemID: .randomEvent,
                                  reactions: [AggregatedReaction.mockReactionWithLongText,
                                              AggregatedReaction.mockReactionWithLongTextRTL])
            Divider()
            TimelineReactionsView(context: TimelineViewModel.mock.context,
                                  itemID: .randomEvent,
                                  reactions: Array(AggregatedReaction.mockReactions.prefix(3)))
            Divider()
            TimelineReactionsView(context: TimelineViewModel.mock.context,
                                  itemID: .randomEvent,
                                  reactions: AggregatedReaction.mockReactions)
            Divider()
            TimelineReactionsView(context: TimelineViewModel.mock.context,
                                  itemID: .randomEvent,
                                  reactions: AggregatedReaction.mockReactions,
                                  isLayoutRTL: true)
        }
        .background(Color.red)
        .frame(maxWidth: 250, alignment: .leading)
    }
}

struct TimelineReactionView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        TimelineReactionViewPreviewsContainer()
    }
}
