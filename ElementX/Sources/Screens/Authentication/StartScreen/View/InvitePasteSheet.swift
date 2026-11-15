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
/// the storyboard's sheet (Brief 0083, decision 308): title and sentence left
/// aligned, one Compound field whose footer carries the error, Continue;
/// «Continue without an invitation», a link, only while registration is open
/// (`registrationRequiresInvite`, the client's twin of the platform's
/// `REGISTRATION_MODE`, ADR-0008).
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
                // AGENT-PLATFORM (Brief 0083, decision 308): the title and its sentence lead, left aligned, without the
                // icon; the field and Continue follow.
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.top, CompoundDesignTokens.space4X)
                        .padding(.bottom, CompoundDesignTokens.space7X)
                    
                    form
                }
                .readableFrame()
                .padding(.horizontal, CompoundDesignTokens.space6X)
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
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space2X) {
            Text(UntranslatedL10n.screenInvitePasteTitle)
                .font(.compound.headingLGBold)
                .foregroundColor(.compound.textPrimary)
                .accessibilityAddTraits(.isHeader)
            
            Text(UntranslatedL10n.screenInvitePasteMessage)
                .font(.compound.bodyLG)
                .foregroundColor(.compound.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var form: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space4X) {
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
            
            Button { context.send(viewAction: .usePastedInvite) } label: {
                Text(L10n.actionContinue)
            }
            .buttonStyle(.compound(.primary))
            .disabled(!canContinue)
            .accessibilityIdentifier(A11yIdentifiers.invitePasteSheet.use)
            
            // AGENT-PLATFORM (Brief 0083): the other way on is a link, as on the identity screen.
            if !context.viewState.registrationRequiresInvite {
                Button { context.send(viewAction: .registerWithoutInvite) } label: {
                    Text(UntranslatedL10n.screenInvitePasteWithout)
                }
                .buttonStyle(.spiralLink)
                .accessibilityIdentifier(A11yIdentifiers.invitePasteSheet.withoutInvite)
            }
        }
    }
}

// MARK: - Previews

// AGENT-PLATFORM (Brief 0083): opted in to Spiral's gates.
struct InvitePasteSheet_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
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
