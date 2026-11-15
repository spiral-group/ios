//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SpiralComponents // AGENT-PLATFORM (Brief 0083)
import SwiftUI

struct EncryptionResetScreen: View {
    @Bindable var context: EncryptionResetScreenViewModel.Context
    
    var body: some View {
        // AGENT-PLATFORM (Brief 0083, decision 313): the identity path's margins, for the content and the button alike.
        FullscreenDialog(horizontalPadding: CompoundDesignTokens.space6X, bottomHorizontalPadding: CompoundDesignTokens.space6X) {
            mainContent
        } bottomContent: {
            Button(UntranslatedL10n.screenEncryptionResetActionContinueResetSpiral, role: .destructive) { // AGENT-PLATFORM (Brief 0083, decision 314)
                context.send(viewAction: .reset)
            }
            .buttonStyle(.compound(.primary))
            .accessibilityIdentifier(A11yIdentifiers.encryptionResetScreen.continueReset)
        }
        .background()
        .backgroundStyle(.compound.bgCanvasDefault)
        .interactiveDismissDisabled()
        .toolbar { toolbar }
        .toolbar(.visible, for: .navigationBar)
        .alert(item: $context.alertInfo)
    }
    
    // AGENT-PLATFORM (Brief 0083, decisions 313, 314 and 323): the identity path's leading header, then what stays
    // and what goes as the rows of one card, the losses in red, then the "only if" warning as a semibold line.
    /// The main content of the screen that is shown inside the scroll view.
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space8X) {
            SpiralDialogHeader(icon: \.errorSolid, tone: .critical, title: UntranslatedL10n.screenEncryptionResetTitleSpiral)
            
            VStack(alignment: .leading, spacing: CompoundDesignTokens.space4X) {
                SpiralCard {
                    consequence(UntranslatedL10n.screenEncryptionResetBullet1Spiral, isKept: true, showsSeparator: true)
                    consequence(UntranslatedL10n.screenEncryptionResetBullet2Spiral, isKept: false, showsSeparator: true)
                    consequence(UntranslatedL10n.screenEncryptionResetBullet3Spiral, isKept: false, showsSeparator: false)
                }
                
                Text(UntranslatedL10n.screenEncryptionResetFooterSpiral)
                    .font(.compound.bodyMDSemibold)
                    .foregroundColor(.compound.textPrimary)
                    .padding(.horizontal, CompoundDesignTokens.space4X)
            }
        }
    }
    
    private func consequence(_ title: String, isKept: Bool, showsSeparator: Bool) -> some View {
        SpiralCardRow(icon: isKept ? \.check : \.info,
                      iconColor: isKept ? .compound.iconSuccessPrimary : .compound.iconCriticalPrimary,
                      showsSeparator: showsSeparator) {
            Text(title)
                .font(.compound.bodyLG)
                .foregroundColor(.compound.textPrimary)
        }
    }
    
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(L10n.actionCancel) {
                context.send(viewAction: .cancel)
            }
        }
    }
}

// MARK: - Previews

struct EncryptionResetScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview { // AGENT-PLATFORM (Brief 0083)
    static let viewModel = EncryptionResetScreenViewModel(clientProxy: ClientProxyMock(.init()),
                                                          userIndicatorController: UserIndicatorControllerMock())
    static var previews: some View {
        ElementNavigationStack {
            EncryptionResetScreen(context: viewModel.context)
        }
    }
}
