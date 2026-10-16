//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct AIConsentPromptScreen: View {
    @Bindable var context: AIConsentPromptScreenViewModel.Context
    
    var body: some View {
        FullscreenDialog(topPadding: UIConstants.startScreenBreakerScreenTopPadding, background: .gradient) {
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
        VStack(spacing: 40) {
            header
            disclosureList
        }
    }
    
    private var header: some View {
        VStack(spacing: 8) {
            BigIcon(icon: \.shield)
                .padding(.bottom, 8)
            
            Text(UntranslatedL10n.screenAiConsentPromptTitle)
                .font(.compound.headingMDBold)
                .multilineTextAlignment(.center)
                .foregroundColor(.compound.textPrimary)
            
            Text(context.viewState.content)
                .font(.compound.bodyMD)
                .multilineTextAlignment(.center)
                .foregroundColor(.compound.textSecondary)
        }
    }
    
    /// Who receives what, and what declining means.
    private var disclosureList: some View {
        VStack(alignment: .leading, spacing: 4) {
            listItem(title: UntranslatedL10n.screenAiConsentPromptOpenai, icon: \.chat, position: .top)
            listItem(title: UntranslatedL10n.screenAiConsentPromptGoogle, icon: \.translate, position: .middle)
            listItem(title: UntranslatedL10n.screenAiConsentPromptDecline, icon: \.lock, position: .bottom)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .environment(\.backgroundStyle, AnyShapeStyle(.compound.bgSubtleSecondary))
    }
    
    private func listItem(title: String, icon: KeyPath<CompoundIcons, Image>, position: ListPosition) -> some View {
        VisualListItem(title: title, position: position) {
            CompoundIcon(icon, size: .small, relativeTo: .body)
                .foregroundColor(.compound.iconSecondary)
        }
    }
    
    private var buttons: some View {
        VStack(spacing: 16) {
            Button(UntranslatedL10n.screenAiConsentPromptAllow) { context.send(viewAction: .allow) }
                .buttonStyle(.compound(.primary))
                .accessibilityIdentifier(A11yIdentifiers.aiConsentPromptScreen.allow)
            
            Button { context.send(viewAction: .notNow) } label: {
                Text(L10n.actionNotNow)
                    .font(.compound.bodyLGSemibold)
                    .padding(14)
            }
            .accessibilityIdentifier(A11yIdentifiers.aiConsentPromptScreen.notNow)
        }
        .disabled(context.viewState.isSaving)
    }
}

// MARK: - Previews

struct AIConsentPromptScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = AIConsentPromptScreenViewModel(agentPlatformService: AgentPlatformServiceMock(),
                                                          privacyURL: AppSettings.volatile().privacyURL)
    
    static var previews: some View {
        AIConsentPromptScreen(context: viewModel.context)
    }
}
