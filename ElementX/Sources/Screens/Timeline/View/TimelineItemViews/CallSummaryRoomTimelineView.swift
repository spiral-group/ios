//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 371): a call's summary in the chat, in the call cards' language (question 359 items 3 and 4).
// A message all the same, so it sits in the styler: the sender's side, reactions, a reply, the menu.
//

import Compound
import SpiralTokens
import SwiftUI

struct CallSummaryRoomTimelineView: View {
    let timelineItem: CallSummaryRoomTimelineItem
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            CallSummaryCard(summary: timelineItem.summary, itemID: timelineItem.id)
        }
    }
}

/// A summary's card, on its surface in the chat and in a tool's example alike, so the example is what the chat shows.
struct CallSummaryCard: View {
    /// What the card leaves around its row, inside its surface.
    static let insets = EdgeInsets(top: CompoundDesignTokens.space2X,
                                   leading: CompoundDesignTokens.space2X,
                                   bottom: CompoundDesignTokens.space2X,
                                   trailing: CompoundDesignTokens.space4X)
    
    private enum Folded {
        static let textLineLimit = 6
        static let itemCount = 3
        static let itemLineLimit = 2
    }
    
    @Environment(\.timelineContext) private var context
    @Environment(\.timelineRowContext.isCallSummaryExpanded) private var isExpanded
    
    let summary: SpiralCallSummary
    /// The row's, in a timeline, where a long card opens. An ID and not a closure, which would rebuild the card on every
    /// update of the row around it.
    var itemID: TimelineItemIdentifier?
    
    private var isFolded: Bool {
        summary.isLong && !isExpanded
    }
    
    var body: some View {
        ChatCardRow(icon: AgentToolKind.callSummary.icon, title: summary.displayTitle) {
            VStack(alignment: .leading, spacing: CompoundDesignTokens.space1X) {
                Text(summary.text)
                    .lineLimit(isFolded ? Folded.textLineLimit : nil)
                
                section(title: summary.decisionsTitle, items: summary.decisions)
                section(title: summary.actionItemsTitle, items: summary.actionItems)
                
                if summary.isLong, let itemID {
                    // No animation: the table moves the row on a clock of its own (`CollapsibleRoomTimelineView`).
                    Button {
                        context?.expandedCallSummaries.formSymmetricDifference([itemID])
                    } label: {
                        Text(Self.foldTitle(isExpanded: isExpanded))
                            .font(.compound.bodySMSemibold)
                            .foregroundStyle(.compound.textLinkExternal)
                    }
                    .buttonStyle(.plain)
                    .contentShape(.interaction, Rectangle().inset(by: -CompoundDesignTokens.space2X))
                    .padding(.top, CompoundDesignTokens.space1X)
                    .accessibilityHidden(true) // The row's own action, as the row is one element.
                }
            }
            .font(.compound.bodySM)
            .foregroundStyle(.compound.textPrimary)
        }
    }
    
    static func foldTitle(isExpanded: Bool) -> String {
        isExpanded ? L10n.screenRoomTimelineReactionsShowLess : L10n.screenRoomTimelineReactionsShowMore
    }
    
    /// Nothing at all for an empty list.
    @ViewBuilder
    private func section(title: String?, items: [String]) -> some View {
        if let title, !items.isEmpty {
            Text(title)
                .font(.compound.bodySMSemibold)
                .padding(.top, CompoundDesignTokens.space1X)
        }
        
        ForEach(Array((isFolded ? items.prefix(Folded.itemCount) : items[...]).enumerated()), id: \.offset) { _, item in
            HStack(alignment: .firstTextBaseline, spacing: CompoundDesignTokens.space1X) {
                Text(verbatim: "•")
                    .accessibilityHidden(true)
                Text(item)
                    .lineLimit(isFolded ? Folded.itemLineLimit : nil)
            }
        }
    }
}

// MARK: - Previews

struct CallSummaryRoomTimelineView_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = TimelineViewModel.mock
    
    private static let short = SpiralCallSummary(title: "Call summary",
                                                 text: "We agreed to ship the new onboarding on Friday and to keep the old one behind a flag for a week.",
                                                 decisionsTitle: "Decisions",
                                                 decisions: ["Ship on Friday", "Keep the old flow for a week"],
                                                 actionItemsTitle: "Action items",
                                                 actionItems: ["Anna sends the release notes", "Marcus checks the flag on staging"])
    
    private static let long = SpiralCallSummary(title: "Call summary",
                                                text: Array(repeating: "We went through the launch plan step by step, who owns each part of it and what could still go wrong before Friday.",
                                                            count: 5).joined(separator: "\n\n"),
                                                decisionsTitle: "Decisions",
                                                decisions: ["Ship on Friday", "Keep the old flow for a week", "Review the numbers on Monday", "Hire no one this month"],
                                                actionItemsTitle: "Action items",
                                                actionItems: ["Anna sends the release notes to everyone in the team by Thursday noon",
                                                              "Marcus checks the flag on staging",
                                                              "Dana books the room for the review",
                                                              "Lee updates the store listing",
                                                              "Sam writes the post for the website"])
    
    static var previews: some View {
        row(short)
            .previewDisplayName("Summary")
        row(SpiralCallSummary(title: "Call summary", text: "No summary — no speech was heard in the call."))
            .previewDisplayName("Without action items")
        row(SpiralCallSummary(title: "Call summary", text: short.text, actionItemsTitle: "Action items", actionItems: short.actionItems))
            .previewDisplayName("Without decisions")
        row(SpiralCallSummary(text: short.text, decisions: short.decisions, actionItems: short.actionItems))
            .previewDisplayName("Without titles")
        row(long)
            .previewDisplayName("Long, folded")
        row(long, rowContext: TimelineRowContext(isDM: true, isCallSummaryExpanded: true))
            .previewDisplayName("Long, open")
        row(short, rowContext: TimelineRowContext(isDM: false))
            .previewDisplayName("In a group")
        row(short, properties: RoomTimelineItemProperties(reactions: [AggregatedReaction(accountOwnerID: "@me:spiral.md",
                                                                                         key: "👍",
                                                                                         senders: [ReactionSender(id: "@me:spiral.md", timestamp: .mock)])]))
            .previewDisplayName("With a reaction")
        row(short, properties: RoomTimelineItemProperties(replyDetails: .loaded(sender: .init(id: "@anna:spiral.md", displayName: "Anna"),
                                                                                eventID: "$reply",
                                                                                eventContent: .message(.text(.init(body: "Can we have the notes?"))))))
            .previewDisplayName("In reply")
        TextRoomTimelineView(timelineItem: plainBubble)
            .environment(\.timelineContext, viewModel.context)
            .padding(.vertical, CompoundDesignTokens.space2X)
            .previewDisplayName("Plain bubble")
            .previewLayout(.sizeThatFits)
        ToolExampleCard(example: ToolExample(kind: .callSummary, language: ""))
            .padding(CompoundDesignTokens.space4X)
            .frame(width: 375)
            .previewDisplayName("The tool's example")
            .previewLayout(.sizeThatFits)
    }
    
    private static func row(_ summary: SpiralCallSummary,
                            rowContext: TimelineRowContext = TimelineRowContext(isDM: true),
                            properties: RoomTimelineItemProperties = .init()) -> some View {
        CallSummaryRoomTimelineView(timelineItem: item(summary, properties: properties))
            .environment(\.timelineContext, viewModel.context)
            .environment(\.timelineRowContext, rowContext)
            .padding(.vertical, CompoundDesignTokens.space2X)
            .frame(width: 375)
            .previewLayout(.sizeThatFits)
    }
    
    private static func item(_ summary: SpiralCallSummary, properties: RoomTimelineItemProperties) -> CallSummaryRoomTimelineItem {
        CallSummaryRoomTimelineItem(id: .randomEvent,
                                    timestamp: .mock,
                                    isOutgoing: false,
                                    isEditable: false,
                                    canBeRepliedTo: true,
                                    sender: .init(id: "@assistant-alice:spiral.md", displayName: "Alice's Assistant"),
                                    content: .init(body: summary.text),
                                    summary: summary,
                                    properties: properties)
    }
    
    private static var plainBubble: TextRoomTimelineItem {
        let body = "\(short.text)\n\nDecisions:\n• \(short.decisions.joined(separator: "\n• "))\n\nAction items:\n• \(short.actionItems.joined(separator: "\n• "))"
        return TextRoomTimelineItem(id: .randomEvent,
                                    timestamp: .mock,
                                    isOutgoing: false,
                                    isEditable: false,
                                    canBeRepliedTo: true,
                                    sender: .init(id: "@assistant-alice:spiral.md", displayName: "Alice's Assistant"),
                                    content: .init(body: body))
    }
}
