//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// AGENT-PLATFORM (1.0.3 onboarding, operator 2026-11-20): the third-party AI consent in the onboarding's look, a sibling
/// of the notifications prompt — Spark with the shield under a halo on the canvas, the title, the disclosure with the
/// privacy policy, who receives what, and Allow as an explicit tap. The words and the choice are unchanged.
struct AIConsentPromptScreen: View {
    @Bindable var context: AIConsentPromptScreenViewModel.Context
    
    var body: some View {
        // The buttons come after the disclosure: where it overflows (a small phone, large text, a long language) Allow
        // is reached only by scrolling past who receives what (1.0.3).
        FullscreenDialog(topPadding: CompoundDesignTokens.space4X,
                         horizontalPadding: CompoundDesignTokens.space6X,
                         bottomHorizontalPadding: CompoundDesignTokens.space6X,
                         scrollsBottomContentWithContent: true) {
            mainContent
        } bottomContent: {
            buttons
        }
        .background()
        .backgroundStyle(.compound.bgCanvasDefault)
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled()
        .alert(item: $context.alertInfo)
    }
    
    private var mainContent: some View {
        // Smaller art and a tighter rhythm than the notifications prompt: here every line is part of the consent.
        VStack(spacing: CompoundDesignTokens.space4X) {
            OnboardingSparkHalo(image: Asset.Images.sparkShield, scale: 0.55)
            header
            disclosureList
        }
    }
    
    private var header: some View {
        VStack(spacing: CompoundDesignTokens.space2X) {
            Text(UntranslatedL10n.screenAiConsentPromptTitle)
                .font(.compound.headingXLBold)
                .foregroundStyle(.compound.textPrimary)
                .accessibilityAddTraits(.isHeader)
            
            Text(context.viewState.content)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textSecondary)
        }
        .multilineTextAlignment(.center)
    }
    
    /// Who receives what, and what declining means.
    private var disclosureList: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space4X) {
            disclosure(UntranslatedL10n.screenAiConsentPromptOpenai, icon: \.chat)
            disclosure(UntranslatedL10n.screenAiConsentPromptGoogle, icon: \.translate)
            disclosure(UntranslatedL10n.screenAiConsentPromptDecline, icon: \.lock)
        }
        .padding(.horizontal, CompoundDesignTokens.space2X)
    }
    
    private func disclosure(_ text: String, icon: KeyPath<CompoundIcons, Image>) -> some View {
        HStack(spacing: CompoundDesignTokens.space4X) {
            OnboardingIconTile(symbol: .compound(icon))
            
            Text(text)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
    
    private var buttons: some View {
        VStack(spacing: CompoundDesignTokens.space2X) {
            Button { context.send(viewAction: .allow) } label: {
                Text(UntranslatedL10n.screenAiConsentPromptAllow)
            }
            .buttonStyle(.compound(.primary))
            .accessibilityIdentifier(A11yIdentifiers.aiConsentPromptScreen.allow)
            
            Button { context.send(viewAction: .notNow) } label: {
                Text(L10n.actionNotNow)
            }
            .buttonStyle(.compound(.tertiary))
            .accessibilityIdentifier(A11yIdentifiers.aiConsentPromptScreen.notNow)
        }
        .disabled(context.viewState.isSaving)
    }
}

// MARK: - Previews

// AGENT-PLATFORM (1.0.3 onboarding): opted in to Spiral's gates.
struct AIConsentPromptScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = AIConsentPromptScreenViewModel(store: AgentsStore(service: AgentPlatformServiceMock()),
                                                          privacyURL: AppSettings.volatile().privacyURL)
    
    static var previews: some View {
        AIConsentPromptScreen(context: viewModel.context)
    }
}
