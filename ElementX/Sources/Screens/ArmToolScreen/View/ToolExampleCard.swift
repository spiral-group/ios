//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SFSafeSymbols
import SpiralTokens
import SwiftUI

/// The top of a tool's form: what a person gets when the tool fires, on a tinted card. What lands in the chat wears the
/// chat's own bubbles and cards; what only happens in a call doesn't.
struct ToolExampleCard: View {
    /// Nothing plays it: the example's voice message is only its look.
    private static let recording = AudioPlayerState(id: .recorderPreview,
                                                    title: L10n.commonVoiceMessage,
                                                    duration: 754,
                                                    waveform: .mockWaveform)
    
    let example: ToolExample
    
    var body: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space2X) {
            sample
            
            if let hint = example.hint {
                Text(hint)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textPrimary) // The secondary grey reads 4.4:1 on the card's light end, and a blue reads as a link.
            }
        }
        .padding(CompoundDesignTokens.space4X)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.compound.bgInfoSubtle, .compound.bgBadgeInfo], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: SpiralRadius.listCard, style: .continuous))
        .onChatBackground()
        .accessibilityElement(children: .combine)
    }
    
    @ViewBuilder
    private var sample: some View {
        switch example.sample {
        case .chat(let message, let reply):
            bubble {
                Text(message)
            }
            if let reply {
                bubble {
                    HStack(alignment: .firstTextBaseline, spacing: CompoundDesignTokens.space1X) {
                        Image(systemSymbol: .sparkles)
                            .foregroundStyle(.compound.iconAccentPrimary)
                            .accessibilityHidden(true)
                        Text(reply)
                    }
                }
            }
        case .callSummary(let summary):
            CallSummaryCard(summary: summary)
                .padding(CallSummaryCard.insets)
                .chatCardBubble()
        case .callRecording:
            callRecording
        }
    }
    
    private var callRecording: some View {
        VoiceMessageRoomPlaybackView(playerState: Self.recording,
                                     onPlayPause: { },
                                     onSeek: { _ in },
                                     onScrubbing: { _ in },
                                     onPlaybackSpeedChange: { })
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 340)
            .padding(CompoundDesignTokens.space2X)
            .chatCardBubble(cornerRadius: SpiralRadius.bubble)
            .allowsHitTesting(false)
            // Hit testing off leaves VoiceOver its Play action, which plays nothing: the sample is named instead.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(L10n.commonVoiceMessage))
            .accessibilityValue(Text(Duration.seconds(Self.recording.duration).formatted(.units(allowed: [.minutes, .seconds], width: .wide))))
    }
    
    private func bubble(@ViewBuilder content: () -> some View) -> some View {
        content()
            .font(.compound.bodyMD)
            .foregroundStyle(.compound.textPrimary)
            .padding(.horizontal, CompoundDesignTokens.space3X)
            .padding(.vertical, CompoundDesignTokens.space2X)
            .chatCardBubble(cornerRadius: SpiralRadius.bubble)
    }
}

// MARK: - Previews

struct ToolExampleCard_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static var previews: some View {
        card(.translate, language: "es").previewDisplayName("Translate")
        card(.translate).previewDisplayName("Translate without a language")
        card(.translate, language: "sw").previewDisplayName("Translate without a sample")
        card(.simplify).previewDisplayName("Simplify")
        card(.correct).previewDisplayName("Correct")
        card(.rephrase).previewDisplayName("Rephrase")
        card(.summarize).previewDisplayName("Summarise")
        card(.custom).previewDisplayName("Custom")
        card(.callSummary).previewDisplayName("Call summary")
        card(.callRecording).previewDisplayName("Call recording")
    }
    
    private static func card(_ kind: AgentToolKind, language: String = "") -> some View {
        ToolExampleCard(example: ToolExample(kind: kind, language: language))
            .padding(CompoundDesignTokens.space4X)
            .frame(width: 375)
            .background(.compound.bgSubtleSecondary)
            .previewLayout(.sizeThatFits)
    }
}
