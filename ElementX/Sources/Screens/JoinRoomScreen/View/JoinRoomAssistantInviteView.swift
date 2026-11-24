//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (1.0.3 A2, operator's concept A, 2026-11-20): the person's own assistant's chat before consent, in
// place of Element's invite («Invited by», Decline / Accept). Spark says what the assistant does; «Start conversation»,
// where the composer will be, accepts the invite: that tap is the consent (ADR-0017). Back leaves the invite as it was.
//

import Compound
import SpiralTokens
import SwiftUI

struct JoinRoomAssistantInviteView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var sparkHeight = 168
    @ScaledMetric(relativeTo: .body) private var tileSide = 40

    let context: JoinRoomScreenViewModel.Context

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content
                    .readableFrame()
                    .padding(.horizontal, CompoundDesignTokens.space6X)
                    .padding(.vertical, CompoundDesignTokens.space6X)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom) {
            startButton
                .readableFrame()
                .padding(.horizontal, CompoundDesignTokens.space4X)
                .padding(.top, CompoundDesignTokens.space3X)
                .padding(.bottom, UIConstants.actionButtonBottomPadding)
                .background(.compound.bgCanvasDefault)
        }
    }

    /// The assistant's own picture, its Peek without one: the person's own assistant is never hidden as a stranger.
    static func avatar(of viewState: JoinRoomScreenViewState) -> RoomAvatar {
        guard let inviter = viewState.roomDetails?.inviter else {
            return .room(id: viewState.roomID, name: nil, avatarURL: nil)
        }
        return .heroes([.init(userID: inviter.id, displayName: inviter.displayName, avatarURL: inviter.avatarURL)])
    }

    // MARK: - Private

    private var content: some View {
        VStack(spacing: CompoundDesignTokens.space6X) {
            Image(asset: Asset.Images.assistantSpark)
                .resizable()
                .scaledToFit()
                // Smaller at accessibility sizes, so the words come first.
                .frame(height: min(sparkHeight, dynamicTypeSize.isAccessibilitySize ? 112 : 220))
                .accessibilityHidden(true)

            Text(UntranslatedL10n.screenAssistantInviteTitle)
                .font(.compound.headingLGBold)
                .foregroundStyle(.compound.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: CompoundDesignTokens.space4X) {
                feature(UntranslatedL10n.screenAssistantInviteReminders, icon: \.time)
                feature(UntranslatedL10n.screenAssistantInviteContacts, icon: \.user)
                feature(UntranslatedL10n.screenAssistantInviteSummaries, icon: \.listBulleted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(UntranslatedL10n.screenAssistantInvitePrivacy)
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func feature(_ text: String, icon: KeyPath<CompoundIcons, Image>) -> some View {
        HStack(spacing: CompoundDesignTokens.space3X) {
            CompoundIcon(icon, size: .medium, relativeTo: .compound.bodyLG)
                .foregroundStyle(.compound.iconAccentPrimary)
                .frame(width: min(tileSide, 56), height: min(tileSide, 56))
                .background(.compound.iconAccentPrimary.opacity(0.12), in: .rect(cornerRadius: SpiralRadius.block))
                .dynamicTypeSize(dynamicTypeSize < .accessibility1 ? dynamicTypeSize : .accessibility1)
                .accessibilityHidden(true)

            Text(text)
                .font(.compound.bodyLG)
                .foregroundStyle(.compound.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var startButton: some View {
        Button {
            context.send(viewAction: .acceptInvite)
        } label: {
            Text(UntranslatedL10n.screenAssistantInviteStart)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.compound(.primary))
        .accessibilityHint(UntranslatedL10n.a11yAssistantInviteStartHint)
        .accessibilityIdentifier(A11yIdentifiers.joinRoomScreen.acceptInvite)
    }
}

// MARK: - Previews

struct JoinRoomAssistantInviteView_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let wrapper = JoinRoomScreenPreviewWrapper(mode: .invited(isDM: true), isOwnAssistant: true, customPreviewName: "Own assistant")
    
    static var previews: some View {
        wrapper.preview
    }
}
