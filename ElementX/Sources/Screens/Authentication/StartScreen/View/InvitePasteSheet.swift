//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: invite links (Brief 0073 / ADR-0008).
//

import Compound
import SwiftUI

/// «Have an invitation?» — behind Create account when the person did not
/// arrive through a link (an in-app browser such as Telegram's swallows
/// universal links, so the landing page says to paste it here). Laid out as
/// the stock `ServerSelectionScreen`: icon, title, one Compound field whose
/// footer carries the error, Continue; «Continue without an invitation»
/// only while registration is open (`registrationRequiresInvite`, the
/// client's twin of the platform's `REGISTRATION_MODE`, ADR-0008).
struct InvitePasteSheet: View {
    @Bindable var context: AuthenticationStartScreenViewModel.Context
    @FocusState private var isFieldFocused: Bool
    
    private var canContinue: Bool {
        !context.pastedInviteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !context.viewState.isCheckingPastedInvite
    }
    
    var body: some View {
        ElementNavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.top, UIConstants.iconTopPaddingToNavigationBar)
                        .padding(.bottom, 36)
                    
                    form
                }
                .readableFrame()
                .padding(.horizontal, 16)
            }
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.actionCancel) { context.showInvitePasteSheet = false }
                        .accessibilityIdentifier(A11yIdentifiers.invitePasteSheet.cancel)
                }
            }
            .onAppear { isFieldFocused = true }
        }
    }
    
    private var header: some View {
        VStack(spacing: 8) {
            BigIcon(icon: \.userAdd)
                .padding(.bottom, 8)
            
            Text(UntranslatedL10n.screenInvitePasteTitle)
                .font(.compound.headingMDBold)
                .multilineTextAlignment(.center)
                .foregroundColor(.compound.textPrimary)
            
            Text(UntranslatedL10n.screenInvitePasteMessage)
                .font(.compound.bodyMD)
                .multilineTextAlignment(.center)
                .foregroundColor(.compound.textSecondary)
        }
        .padding(.horizontal, 16)
    }
    
    private var form: some View {
        VStack(alignment: .leading, spacing: 24) {
            TextField(UntranslatedL10n.screenInvitePastePlaceholder, text: $context.pastedInviteText)
                .textFieldStyle(.compound(labelText: UntranslatedL10n.screenInvitePasteLabel,
                                          footerText: context.viewState.pastedInviteError,
                                          state: context.viewState.pastedInviteError == nil ? .default : .error,
                                          accessibilityIdentifier: A11yIdentifiers.invitePasteSheet.field))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($isFieldFocused)
                .onSubmit { if canContinue { context.send(viewAction: .usePastedInvite) } }
            
            VStack(spacing: 16) {
                Button { context.send(viewAction: .usePastedInvite) } label: {
                    Text(L10n.actionContinue)
                }
                .buttonStyle(.compound(.primary))
                .disabled(!canContinue)
                .accessibilityIdentifier(A11yIdentifiers.invitePasteSheet.use)
                
                if !context.viewState.registrationRequiresInvite {
                    Button { context.send(viewAction: .registerWithoutInvite) } label: {
                        Text(UntranslatedL10n.screenInvitePasteWithout)
                    }
                    .buttonStyle(.compound(.tertiary))
                    .accessibilityIdentifier(A11yIdentifiers.invitePasteSheet.withoutInvite)
                }
            }
        }
    }
}

// MARK: - Previews

struct InvitePasteSheet_Previews: PreviewProvider, TestablePreview {
    static let viewModel = AuthenticationStartScreen_Previews.makeViewModel()
    static let errorViewModel = {
        let viewModel = AuthenticationStartScreen_Previews.makeViewModel()
        viewModel.context.pastedInviteText = "hello"
        viewModel.context.send(viewAction: .usePastedInvite)
        return viewModel
    }()
    
    static let openRegistrationViewModel = AuthenticationStartScreen_Previews.makeViewModel(registrationRequiresInvite: false)
    
    static var previews: some View {
        InvitePasteSheet(context: viewModel.context)
            .previewDisplayName("Empty")
        InvitePasteSheet(context: openRegistrationViewModel.context)
            .previewDisplayName("Open registration")
        InvitePasteSheet(context: errorViewModel.context)
            .snapshotPreferences(expect: errorViewModel.context.observe(\.viewState.pastedInviteError).map { $0 != nil })
            .previewDisplayName("Error")
    }
}
