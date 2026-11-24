//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SpiralTokens
import SwiftUI

/// AGENT-PLATFORM (1.0.3 onboarding, board pick W2): you and the inviter together on the pearl, and three next steps.
/// Saying hello is the screen's one action; meeting the assistant and the games tell what waits in Chats.
struct InviteWelcomeScreen: View {
    @Bindable var context: InviteWelcomeScreenViewModelType.Context
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                header
                    .padding(.horizontal, CompoundDesignTokens.space5X)
                    .padding(.bottom, CompoundDesignTokens.space4X)
                    .readableFrame()
            }
            .scrollBounceBehavior(.basedOnSize)
            
            buttons
                .padding(.horizontal, CompoundDesignTokens.space5X)
                .padding(.top, CompoundDesignTokens.space3X)
                .padding(.bottom, CompoundDesignTokens.space2X)
                .readableFrame()
        }
        .background(.onboardingPearl)
        .navigationBarHidden(true)
        .interactiveDismissDisabled()
        .alert(item: $context.alertInfo)
    }
    
    private var header: some View {
        VStack(spacing: CompoundDesignTokens.space6X) {
            InviteWelcomeAvatarPair(context: context)
                .padding(.top, CompoundDesignTokens.space12X)
            
            Text(UntranslatedL10n.screenInviteWelcomeTogetherTitle(context.viewState.inviterName))
                .font(.compound.headingXLBold)
                .multilineTextAlignment(.center)
                .foregroundStyle(.compound.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(A11yIdentifiers.inviteWelcomeScreen.text) // AGENT-PLATFORM (decision 148)
            
            VStack(spacing: CompoundDesignTokens.space2X) {
                Button { context.send(viewAction: .message) } label: {
                    InviteWelcomeStepRow(symbol: .compound(\.chat),
                                         title: UntranslatedL10n.screenInviteWelcomeStepSayHelloTitle(context.viewState.inviterName),
                                         subtitle: UntranslatedL10n.screenInviteWelcomeStepSayHelloSubtitle(context.viewState.inviterName),
                                         showsChevron: true)
                }
                .buttonStyle(InviteWelcomeRowButtonStyle())
                .disabled(context.viewState.isOpeningChat)
                
                // The assistant's invitation and the games live in Chats: these two tell, they don't open anything.
                InviteWelcomeStepRow(symbol: .compound(\.host),
                                     title: UntranslatedL10n.screenInviteWelcomeStepAssistantTitle,
                                     subtitle: UntranslatedL10n.screenInviteWelcomeStepAssistantSubtitle,
                                     showsChevron: false)
                InviteWelcomeStepRow(symbol: .system("gamecontroller"),
                                     title: UntranslatedL10n.screenInviteWelcomeStepPlayTitle,
                                     subtitle: UntranslatedL10n.screenInviteWelcomeStepPlaySubtitle,
                                     showsChevron: false)
            }
        }
    }
    
    private var buttons: some View {
        VStack(spacing: CompoundDesignTokens.space3X) {
            Button {
                context.send(viewAction: .message)
            } label: {
                if context.viewState.isOpeningChat {
                    ProgressView()
                } else {
                    Text(UntranslatedL10n.screenInviteWelcomeMessageAction(context.viewState.inviterName))
                }
            }
            .buttonStyle(.compound(.primary))
            .disabled(context.viewState.isOpeningChat)
            .accessibilityIdentifier(A11yIdentifiers.inviteWelcomeScreen.message)
            
            Button(UntranslatedL10n.screenInviteWelcomeLater) {
                context.send(viewAction: .later)
            }
            .buttonStyle(.onboarding(.pearl))
            .disabled(context.viewState.isOpeningChat)
            .accessibilityIdentifier(A11yIdentifiers.inviteWelcomeScreen.later)
        }
    }
}

/// The inviter and you, overlapping: the inviter first, you in front, ringed in the field's colour.
private struct InviteWelcomeAvatarPair: View {
    let context: InviteWelcomeScreenViewModelType.Context
    
    @ScaledMetric(relativeTo: .largeTitle) private var overlap = SpiralAvatarSize.large * 0.22
    
    var body: some View {
        HStack(spacing: -overlap) {
            LoadableAvatarImage(url: context.viewState.inviterProfile?.avatarURL,
                                name: context.viewState.inviterName,
                                contentID: context.viewState.inviterUserID,
                                avatarSize: .user(on: .memberDetails),
                                mediaProvider: context.mediaProvider)
            
            LoadableAvatarImage(url: context.viewState.ownProfile.avatarURL,
                                name: context.viewState.ownProfile.displayName,
                                contentID: context.viewState.ownProfile.id,
                                avatarSize: .user(on: .memberDetails),
                                mediaProvider: context.mediaProvider)
                .padding(CompoundDesignTokens.space1X)
                .background(Asset.Colors.onboardingPearlRing.swiftUIColor, in: Circle())
                .padding(-CompoundDesignTokens.space1X)
        }
        .accessibilityElement()
        .accessibilityLabel(UntranslatedL10n.a11yInviteWelcomeAvatars(context.viewState.inviterName))
    }
}

/// A next step on a card: a tinted icon, what to do and why.
private struct InviteWelcomeStepRow: View {
    let symbol: OnboardingIconTile.Symbol
    let title: String
    let subtitle: String
    let showsChevron: Bool
    
    var body: some View {
        HStack(spacing: CompoundDesignTokens.space3X) {
            OnboardingIconTile(symbol: symbol)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(.compound.textPrimary)
                Text(subtitle)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
            }
            .multilineTextAlignment(.leading)
            
            Spacer(minLength: 0)
            
            if showsChevron {
                CompoundIcon(\.chevronRight, size: .small, relativeTo: .compound.bodyMD)
                    .foregroundStyle(.compound.iconTertiary)
                    .flipsForRightToLeftLayoutDirection(true)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, CompoundDesignTokens.space4X)
        .padding(.vertical, CompoundDesignTokens.space3X)
        .background(Asset.Colors.onboardingPearlCard.swiftUIColor, in: RoundedRectangle(cornerRadius: SpiralRadius.listCard, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: SpiralRadius.listCard, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A row's press: a small give, as iOS's own cards.
private struct InviteWelcomeRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.2, bounce: 0), value: configuration.isPressed)
    }
}

// MARK: - Previews

// AGENT-PLATFORM (1.0.3 onboarding): opted in to Spiral's gates.
struct InviteWelcomeScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = makeViewModel(displayName: "Emma")
    static let noNameViewModel = makeViewModel(displayName: nil)
    
    static var previews: some View {
        ElementNavigationStack {
            InviteWelcomeScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.inviterProfile).map { $0 != nil })
        .previewDisplayName("Named inviter")
        
        ElementNavigationStack {
            InviteWelcomeScreen(context: noNameViewModel.context)
        }
        .snapshotPreferences(expect: noNameViewModel.context.observe(\.viewState.inviterProfile).map { $0 != nil })
        .previewDisplayName("No display name")
    }
    
    static func makeViewModel(displayName: String?) -> InviteWelcomeScreenViewModel {
        let clientProxy = ClientProxyMock(.init(userID: "@newcomer:spiral.md", displayName: "Nora"))
        clientProxy.profileForReturnValue = .success(.init(userID: "@emmm:spiral.md", displayName: displayName))
        return InviteWelcomeScreenViewModel(inviterUserID: "@emmm:spiral.md",
                                            clientProxy: clientProxy,
                                            mediaProvider: MediaProviderMock(.init()))
    }
}
