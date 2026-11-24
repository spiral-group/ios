//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (1.0.3 A3, operator's concept A, 2026-11-20): the assistant's welcome, drawn by the app from the
// server's fact. A short hello on the incoming side; under it, until the person writes, three starters that send their
// request as the person's own message, or, without the person's AI consent, the way to allow AI.
//

import Compound
import SpiralTokens
import SwiftUI

struct SpiralWelcomeNoticeView: View {
    // Nil outside a timeline (previews).
    @Environment(\.timelineContext) private var context
    @Environment(\.timelineRowContext) private var rowContext

    let timelineItem: SpiralNoticeRoomTimelineItem

    var body: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space2X) {
            hello
            extras
        }
        .padding(.trailing, 48) // As a message's.
        .padding(.horizontal, 16)
        .padding(.vertical, ChatCardLayout.rowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Private

    private var hello: some View {
        VStack(alignment: .trailing, spacing: 2) {
            VStack(alignment: .leading, spacing: CompoundDesignTokens.space1X) {
                Text(title)
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(.compound.textPrimary)
                Text(UntranslatedL10n.noticeWelcomeBody)
                    .font(.compound.bodyLG)
                    .foregroundStyle(.compound.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(timelineItem.timestamp.formattedTime())
                .font(.compound.bodyXS)
                .foregroundStyle(.compound.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .padding(.horizontal, 14)
        .chatCardBubble()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(A11yIdentifiers.roomScreen.spiralNotice(timelineItem.notice.kind.wireName))
        .frame(maxWidth: 340, alignment: .leading)
    }

    @ViewBuilder
    private var extras: some View {
        switch rowContext.spiralWelcomeExtras {
        case .none:
            EmptyView()
        case .starters:
            VStack(alignment: .leading, spacing: CompoundDesignTokens.space1X) {
                ForEach(SpiralWelcomeStarter.allCases, id: \.self) { starter in
                    action(starter.title, icon: \.host) {
                        context?.send(viewAction: .sendWelcomeStarter(starter))
                    }
                }
            }
        case .allowAI:
            VStack(alignment: .leading, spacing: CompoundDesignTokens.space1X) {
                Text(UntranslatedL10n.noticeWelcomeAllowAiReason)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
                    .padding(.vertical, CompoundDesignTokens.space1X)
                    .chatBackgroundChip()

                action(UntranslatedL10n.noticeWelcomeAllowAiAction, icon: \.lock) {
                    context?.send(viewAction: .openAIConsentSettings)
                }
            }
        }
    }

    /// A chip under the hello, in the link colour on the surface the room's picture gives what sits on it: on the
    /// picture itself the link colour read under 4.5:1 (#2455B5 on #FFFFFF reads 7.4:1, #6CB2FF on #171C2B 7.6:1).
    private func action(_ title: String, icon: KeyPath<CompoundIcons, Image>, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label {
                Text(title)
                    .font(.compound.bodyLGSemibold)
            } icon: {
                CompoundIcon(icon, size: .small, relativeTo: .compound.bodyLGSemibold)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.compound.textLinkExternal)
            .padding(.vertical, CompoundDesignTokens.space1_5X)
            .chatBackgroundChip()
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
    
    private var title: String {
        guard case .welcome(let ownerDisplayName, _, _) = timelineItem.notice.kind else { return "" }
        return UntranslatedL10n.noticeWelcomeTitle(SpiralNotice.firstName(of: ownerDisplayName))
    }
}

// MARK: - Previews

struct SpiralWelcomeNoticeView_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static var previews: some View {
        welcome(extras: .starters)
            .previewDisplayName("Starters")
        welcome(extras: .allowAI)
            .previewDisplayName("Allow AI")
        welcome(extras: .none)
            .previewDisplayName("After the first message")
    }

    private static func welcome(extras: SpiralWelcomeExtras) -> some View {
        SpiralWelcomeNoticeView(timelineItem: .init(id: .randomEvent,
                                                    timestamp: .mock,
                                                    sender: .init(id: "@assistant-alice:spiral.md", displayName: "Alice Smith · assistant"),
                                                    notice: SpiralNotice(msgtype: SpiralNotice.msgtype,
                                                                         data: #"{"com.spiral.notice":{"kind":"welcome","owner_display_name":"Alice Smith","agent_display_name":"Alice Smith · assistant","behavior":"personal_assistant"}}"#)!))
            .environment(\.timelineRowContext, TimelineRowContext(spiralWelcomeExtras: extras))
            .chatBackground() // Where the timeline draws it: the starters sit on the room's picture.
            .previewLayout(.sizeThatFits)
    }
}
