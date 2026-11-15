//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import SpiralComponents // AGENT-PLATFORM (Brief 0083)
import SwiftUI

struct EncryptionResetPasswordScreen: View {
    @Bindable var context: EncryptionResetPasswordScreenViewModel.Context
    @FocusState private var textFieldFocus
    
    var body: some View {
        // AGENT-PLATFORM (Brief 0083, decisions 313 and 314): the identity path's leading header and margins, Compound's
        // field and Spiral's copy.
        FullscreenDialog(horizontalPadding: CompoundDesignTokens.space6X, bottomHorizontalPadding: CompoundDesignTokens.space6X) {
            VStack(alignment: .leading, spacing: CompoundDesignTokens.space8X) {
                SpiralDialogHeader(icon: \.lockSolid,
                                   tone: .critical,
                                   title: UntranslatedL10n.screenResetEncryptionPasswordTitleSpiral,
                                   message: UntranslatedL10n.screenResetEncryptionPasswordSubtitleSpiral)
                
                passwordSection
            }
        } bottomContent: {
            Button(UntranslatedL10n.screenResetEncryptionPasswordSubmitSpiral, role: .destructive) {
                context.send(viewAction: .submit)
            }
            .buttonStyle(.compound(.primary))
            .accessibilityIdentifier(A11yIdentifiers.encryptionResetPasswordScreen.submit)
        }
        .background()
        .backgroundStyle(.compound.bgCanvasDefault)
        .interactiveDismissDisabled()
        .onAppear { textFieldFocus = true }
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 313): Compound's field, as on sign-in, in place of a hand-drawn one.
    private var passwordSection: some View {
        SecureField(UntranslatedL10n.screenResetEncryptionPasswordPlaceholderSpiral, text: $context.password)
            .focused($textFieldFocus)
            .textFieldStyle(.compound(labelText: L10n.commonPassword,
                                      accessibilityIdentifier: A11yIdentifiers.encryptionResetPasswordScreen.passwordField))
            .submitLabel(.done)
            .onSubmit {
                context.send(viewAction: .submit)
            }
    }
}

// MARK: - Previews

struct EncryptionResetPasswordScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview { // AGENT-PLATFORM (Brief 0083)
    static let passwordPublisher = PassthroughSubject<String, Never>()
    static let viewModel = EncryptionResetPasswordScreenViewModel(passwordPublisher: passwordPublisher)
    static var previews: some View {
        ElementNavigationStack {
            EncryptionResetPasswordScreen(context: viewModel.context)
        }
    }
}
