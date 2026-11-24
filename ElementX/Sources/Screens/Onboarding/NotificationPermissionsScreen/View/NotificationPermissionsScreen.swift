//
// Copyright 2025 Element Creations Ltd.
// Copyright 2021-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// A prompt that asks the user whether they would like to enable notifications or not.
///
/// AGENT-PLATFORM (1.0.3 onboarding, board pick A): Spark listening under a soft bell halo and three general lines on
/// the canvas — no names, no message text, no Element gradient (operator, 2026-11-19 and 2026-11-20).
struct NotificationPermissionsScreen: View {
    @ObservedObject var context: NotificationPermissionsScreenViewModel.Context
    
    var body: some View {
        FullscreenDialog(topPadding: CompoundDesignTokens.space6X, horizontalPadding: CompoundDesignTokens.space6X, bottomHorizontalPadding: CompoundDesignTokens.space6X) {
            mainContent
        } bottomContent: {
            buttons
        }
        .background()
        .backgroundStyle(.compound.bgCanvasDefault)
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled()
    }
    
    /// The main content of the screen that is shown inside the scroll view.
    private var mainContent: some View {
        VStack(spacing: CompoundDesignTokens.space6X) {
            OnboardingSparkHalo(image: Asset.Images.sparkListen, badge: \.notificationsSolid)
            
            VStack(spacing: CompoundDesignTokens.space2X) {
                Text(UntranslatedL10n.screenNotificationOptinSpiralTitle)
                    .font(.compound.headingXLBold)
                    .foregroundStyle(.compound.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                
                Text(UntranslatedL10n.screenNotificationOptinSpiralSubtitle)
                    .font(.compound.bodyLG)
                    .foregroundStyle(.compound.textSecondary)
            }
            .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: CompoundDesignTokens.space4X) {
                benefit(icon: \.chat,
                        title: UntranslatedL10n.screenNotificationOptinMessagesTitle,
                        subtitle: UntranslatedL10n.screenNotificationOptinMessagesSubtitle)
                benefit(icon: \.voiceCall,
                        title: UntranslatedL10n.screenNotificationOptinCallsTitle,
                        subtitle: UntranslatedL10n.screenNotificationOptinCallsSubtitle)
                benefit(icon: \.host,
                        title: UntranslatedL10n.screenNotificationOptinAssistantTitle,
                        subtitle: UntranslatedL10n.screenNotificationOptinAssistantSubtitle)
            }
            .padding(.horizontal, CompoundDesignTokens.space2X)
        }
    }
    
    private func benefit(icon: KeyPath<CompoundIcons, Image>, title: String, subtitle: String) -> some View {
        HStack(spacing: CompoundDesignTokens.space4X) {
            OnboardingIconTile(symbol: .compound(icon))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(.compound.textPrimary)
                Text(subtitle)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
            }
            
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
    
    private var buttons: some View {
        VStack(spacing: CompoundDesignTokens.space2X) {
            Button { context.send(viewAction: .enable) } label: {
                Text(UntranslatedL10n.screenNotificationOptinAllow)
            }
            .buttonStyle(.compound(.primary))
            .accessibilityIdentifier(A11yIdentifiers.notificationPermissionsScreen.enable) // AGENT-PLATFORM (decision 146)
            
            Button { context.send(viewAction: .notNow) } label: {
                Text(L10n.actionNotNow)
            }
            .buttonStyle(.compound(.tertiary))
            .accessibilityIdentifier(A11yIdentifiers.notificationPermissionsScreen.notNow) // AGENT-PLATFORM (decision 146)
        }
    }
}

// MARK: - Previews

// AGENT-PLATFORM (1.0.3 onboarding): opted in to Spiral's gates.
struct NotificationPermissionsScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = NotificationPermissionsScreenViewModel(notificationService: NotificationServiceMock(.init()))
    static var previews: some View {
        NotificationPermissionsScreen(context: viewModel.context)
    }
}
