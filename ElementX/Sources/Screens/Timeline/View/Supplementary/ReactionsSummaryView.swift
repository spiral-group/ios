//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SpiralComponents // AGENT-PLATFORM (Brief 0083)
import SpiralTokens // AGENT-PLATFORM (Brief 0083)
import SwiftUI

struct ReactionsSummaryView: View {
    let reactions: [AggregatedReaction]
    let members: [String: RoomMemberState]
    let mediaProvider: MediaProviderProtocol?
    
    @State var selectedReactionKey: String
    private var selectedReaction: AggregatedReaction? {
        reactions.first { $0.key == selectedReactionKey }
    }
    
    // AGENT-PLATFORM (Brief 0083): iOS's grouped sheet, as the message's menu: the reactions above, who reacted on a card.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            reactionButtons
            sendersList
        }
        .background(Color.compound.bgSubtleSecondaryLevel0.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationBackground(Color.compound.bgSubtleSecondaryLevel0)
        .presentationDragIndicator(.visible)
    }
    
    private var reactionButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { scrollView in
                HStack(spacing: 8) {
                    ForEach(reactions) { reaction in
                        ReactionSummaryButton(reaction: reaction, highlighted: selectedReactionKey == reaction.key) { key in
                            selectedReactionKey = key
                        }
                    }
                }
                .padding(.horizontal, CompoundDesignTokens.space4X) // AGENT-PLATFORM (Brief 0083): the cards' edge
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        scrollView.scrollTo(selectedReactionKey)
                    }
                }
                .onChange(of: selectedReactionKey) {
                    scrollView.scrollTo(selectedReactionKey)
                }
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 12)
    }
    
    // AGENT-PLATFORM (Brief 0083): the senders are rows of one card, each separator inset to the text.
    @ViewBuilder
    private var sendersList: some View {
        if let selectedReaction {
            ScrollView {
                SpiralCard(on: .groupedSheet) {
                    ForEach(selectedReaction.senders) { sender in
                        ReactionSummarySenderView(sender: sender, member: members[sender.id], mediaProvider: mediaProvider)
                            .overlay(alignment: .bottom) {
                                if sender.id != selectedReaction.senders.last?.id {
                                    SpiralCardSeparator(leadingInset: ReactionSummarySenderView.textInset)
                                }
                            }
                    }
                }
                .padding(.horizontal, CompoundDesignTokens.space4X)
                .padding(.bottom, CompoundDesignTokens.space4X)
            }
        }
    }
}

private struct ReactionSummaryButton: View {
    let reaction: AggregatedReaction
    let highlighted: Bool
    let action: (String) -> Void
    
    var body: some View {
        Button { action(reaction.key) } label: { label }
    }
    
    var label: some View {
        HStack(spacing: 4) {
            Text(reaction.displayKey)
                .font(.compound.headingSM)
                .foregroundColor(textColor)
            if reaction.count > 1 {
                Text(String(reaction.count))
                    .font(.compound.headingSM)
                    .foregroundColor(textColor)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(minHeight: CompoundDesignTokens.space11X) // AGENT-PLATFORM (Brief 0083): a 44 pt target
        .background(highlighted ? Color.compound.bgActionPrimaryRest : .clear, in: Capsule())
        .accessibilityElement(children: .combine)
    }
    
    var textColor: Color {
        highlighted ? Color.compound.textOnSolidPrimary : Color.compound.textSecondary
    }
}

private struct ReactionSummarySenderView: View {
    var sender: ReactionSender
    var member: RoomMemberState?
    let mediaProvider: MediaProviderProtocol?
    
    var displayName: String {
        member?.displayName ?? sender.id
    }
    
    /// Where the text starts: the separator under a row is inset to it.
    static let textInset = CompoundDesignTokens.space4X + SpiralAvatarSize.small + CompoundDesignTokens.space3X
    
    // AGENT-PLATFORM (Brief 0083): a row of the senders' card, as a list row: the name in body text, the time beside
    // it and the Matrix ID under it in secondary text.
    var body: some View {
        HStack(spacing: CompoundDesignTokens.space3X) {
            LoadableAvatarImage(url: member?.avatarURL,
                                name: displayName,
                                contentID: sender.id,
                                avatarSize: .user(on: .timeline),
                                mediaProvider: mediaProvider)
            
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: CompoundDesignTokens.space2X) {
                    Text(displayName)
                        .font(.compound.bodyLG)
                        .foregroundColor(.compound.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(sender.timestamp.formattedMinimal())
                        .font(.compound.bodySM)
                        .foregroundColor(.compound.textSecondary)
                }
                Text(sender.id)
                    .font(.compound.bodySM)
                    .foregroundColor(.compound.textSecondary)
            }
        }
        .padding(.horizontal, CompoundDesignTokens.space4X)
        .padding(.vertical, CompoundDesignTokens.space3X)
    }
}

struct ReactionsSummaryView_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview { // AGENT-PLATFORM (Brief 0083): Spiral's gates
    static var previews: some View {
        ReactionsSummaryView(reactions: AggregatedReaction.mockReactions,
                             members: [:],
                             mediaProvider: MediaProviderMock(.init()),
                             selectedReactionKey: AggregatedReaction.mockReactions[0].key)
    }
}
