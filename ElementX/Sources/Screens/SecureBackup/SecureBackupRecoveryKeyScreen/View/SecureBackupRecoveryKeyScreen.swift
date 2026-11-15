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

struct SecureBackupRecoveryKeyScreen: View {
    @Bindable var context: SecureBackupRecoveryKeyScreenViewModel.Context
    @FocusState private var focused
    private let textFieldIdentifier = "textFieldIdentifier"
    
    var body: some View {
        // AGENT-PLATFORM (Brief 0083, decision 313): the identity path's margins, for the content and the buttons alike.
        FullscreenDialog(horizontalPadding: CompoundDesignTokens.space6X, bottomHorizontalPadding: CompoundDesignTokens.space6X) {
            ScrollViewReader { reader in
                mainContent
                    .onChange(of: focused) { _, newValue in
                        guard newValue == true else { return }
                        reader.scrollTo(textFieldIdentifier)
                    }
            }
        } bottomContent: {
            footer
        }
        .toolbar { toolbar }
        .toolbar(.visible, for: .navigationBar)
        .background()
        .backgroundStyle(.compound.bgCanvasDefault)
        .interactiveDismissDisabled()
        .alert(item: $context.alertInfo)
    }
    
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space8X) { // AGENT-PLATFORM (Brief 0083, decision 313)
            switch context.viewState.mode {
            case .setupRecovery, .changeRecovery:
                header
                generateRecoveryKeySection
            case .fixRecovery:
                header
                confirmRecoveryKeySection
            case .unknown:
                header
            }
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 313): the identity path's leading header in place of Element's centred icon tile.
    private var header: some View {
        SpiralDialogHeader(icon: \.keySolid, title: context.viewState.title, message: context.viewState.subtitle)
    }
    
    @ViewBuilder
    private var footer: some View {
        switch context.viewState.mode {
        case .setupRecovery, .changeRecovery:
            recoveryCreatedActionButtons
        case .fixRecovery:
            incompleteVerificationActionButtons
        case .unknown:
            // AGENT-PLATFORM (1.0.2): the state is read again rather than left unknown.
            Button(L10n.actionRetry) {
                context.send(viewAction: .retry)
            }
            .buttonStyle(.compound(.primary))
        }
    }
    
    private var incompleteVerificationActionButtons: some View {
        VStack(spacing: 16) {
            Button {
                context.send(viewAction: .confirmKey)
            } label: {
                Text(UntranslatedL10n.screenRecoveryKeyConfirmSubmitSpiral) // AGENT-PLATFORM (Brief 0083, decision 314)
            }
            .buttonStyle(.compound(.primary))
            .disabled(context.confirmationRecoveryKey.isEmpty)
            .accessibilityIdentifier(A11yIdentifiers.secureBackupRecoveryKeyScreen.confirm)
        }
    }
    
    private var recoveryCreatedActionButtons: some View {
        VStack(spacing: 16) {
            if let recoveryKey = context.viewState.recoveryKey {
                ShareLink(item: recoveryKey) {
                    Label(UntranslatedL10n.screenRecoveryKeySaveActionSpiral, icon: \.download) // AGENT-PLATFORM (Brief 0083, decision 314)
                }
                .buttonStyle(.compound(.secondary))
                .simultaneousGesture(TapGesture().onEnded { _ in
                    context.send(viewAction: .keySaved)
                })
            }
            
            // AGENT-PLATFORM (Brief 0083, decision 323): Done appears with the key, the only time it can turn on, so a
            // disabled button isn't the heaviest shape while the key is being created.
            if context.viewState.recoveryKey != nil {
                Button {
                    context.send(viewAction: .done)
                } label: {
                    Text(L10n.actionDone)
                }
                .buttonStyle(.compound(.primary))
                .disabled(context.viewState.doneButtonEnabled == false)
                .accessibilityIdentifier(A11yIdentifiers.secureBackupRecoveryKeyScreen.done)
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if context.viewState.isModallyPresented == true, context.viewState.recoveryKey == nil {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.actionCancel) {
                    context.send(viewAction: .cancel)
                }
            }
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 313): the key in the identity path's card, labelled like a field. Until there
    // is a key, the card holds "Create" as a row with an accent icon (accent text on the card's grey is 3.82:1 in dark);
    // the hidden key keeps the card one height in every state.
    private var generateRecoveryKeySection: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space2X) {
            Text(L10n.commonRecoveryKey)
                .foregroundColor(Compound.supportsGlass ? .compound.textSecondary : .compound.textPrimary)
                .font(Compound.supportsGlass ? .compound.bodyMDSemibold : .compound.bodySMSemibold)
                .padding(.horizontal, CompoundDesignTokens.space4X)
            
            SpiralCard {
                RecoveryKeyView(recoveryKey: "", isInvisibleForLayout: true) { }
                    .overlay {
                        if context.viewState.recoveryKey == nil {
                            if !context.viewState.isGeneratingKey {
                                Button {
                                    context.send(viewAction: .generateKey)
                                } label: {
                                    SpiralCardRow(icon: \.key) {
                                        Text(generateButtonTitle)
                                            .font(.compound.bodyLG)
                                            .foregroundStyle(.compound.textPrimary)
                                    }
                                    .frame(maxHeight: .infinity)
                                }
                                .buttonStyle(.spiralCardRow)
                                .accessibilityIdentifier(A11yIdentifiers.secureBackupRecoveryKeyScreen.generateRecoveryKey)
                            } else {
                                HStack(spacing: ListRowPadding.labelIconSpacing) {
                                    ProgressView()
                                    Text(UntranslatedL10n.screenRecoveryKeyGeneratingKeySpiral)
                                }
                                .font(.compound.bodyLG)
                                .foregroundStyle(.compound.textSecondary)
                                .padding(.horizontal, CompoundDesignTokens.space4X)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            }
                        } else {
                            RecoveryKeyView(recoveryKey: context.viewState.recoveryKey ?? "") {
                                context.send(viewAction: .copyKey)
                            }
                        }
                    }
            }
            
            if let subtitle = context.viewState.recoveryKeySubtitle {
                Text(subtitle)
                    .foregroundColor(.compound.textSecondary)
                    .font(.compound.bodySM)
                    .padding(.horizontal, CompoundDesignTokens.space4X)
            }
        }
    }
    
    private var generateButtonTitle: String {
        // AGENT-PLATFORM (Brief 0083, decision 314)
        context.viewState.mode == .setupRecovery ? UntranslatedL10n.screenRecoveryKeySetupGenerateKeySpiral : UntranslatedL10n.screenRecoveryKeyChangeGenerateKeySpiral
    }
    
    private var confirmRecoveryKeySection: some View {
        SecureField(UntranslatedL10n.screenRecoveryKeyConfirmKeyPlaceholderSpiral, text: $context.confirmationRecoveryKey) // AGENT-PLATFORM (Brief 0083, decision 314)
            .focused($focused)
            .textFieldStyle(.compound(.plain(.secure(hideLabel: L10n.a11yHidePassword, showLabel: L10n.a11yShowPassword)),
                                      labelText: L10n.commonRecoveryKey,
                                      footerText: context.viewState.recoveryKeySubtitle,
                                      accessibilityIdentifier: A11yIdentifiers.secureBackupRecoveryKeyScreen.recoveryKeyField))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit {
                context.send(viewAction: .confirmKey)
            }
            .id(textFieldIdentifier)
    }
}

private struct RecoveryKeyView: View {
    /// The recovery key to show. This can be blank if `isInvisibleForLayout` is `true.`
    let recoveryKey: String
    /// Hides the view, laying it out with the expected key size so that the superview can have a consistent size.
    var isInvisibleForLayout = false
    /// The action performed when tapping the copy button.
    let copyAction: () -> Void
    
    private let placeholderRecoveryKey = Array(repeating: "XXXX", count: 12).joined(separator: " ")
    
    var body: some View {
        // AGENT-PLATFORM (Brief 0083, decision 313): the key in the primary colour at a card row's padding; the copy
        // button in the accent, with a 44 pt target.
        HStack(spacing: CompoundDesignTokens.space2X) {
            Text(isInvisibleForLayout ? placeholderRecoveryKey : recoveryKey)
                .foregroundColor(.compound.textPrimary)
                .font(.compound.bodyLG.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button(action: copyAction) {
                CompoundIcon(\.copy)
                    .frame(minWidth: CompoundDesignTokens.space11X, minHeight: CompoundDesignTokens.space11X)
                    .contentShape(Rectangle())
            }
            .tint(.compound.iconAccentPrimary)
            .accessibilityLabel(L10n.actionCopy)
            .accessibilityIdentifier(A11yIdentifiers.secureBackupRecoveryKeyScreen.copyRecoveryKey)
        }
        .padding(.leading, CompoundDesignTokens.space4X)
        .padding(.trailing, CompoundDesignTokens.space1X)
        .padding(.vertical, CompoundDesignTokens.space3X)
        .opacity(isInvisibleForLayout ? 0 : 1)
        .accessibilityHidden(isInvisibleForLayout)
    }
}

// MARK: - Previews

// AGENT-PLATFORM (Brief 0083): opted in to Spiral's gates. Without `@available(iOS 26.0, *)` it builds for the
// iOS 18 lane, and `observe(_:)` resolves to its AsyncStream fallback.
struct SecureBackupRecoveryKeyScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let key = "EsTM njec uHYA yHmh dQdW Nj4o bNRU 9jMN XGMc KUNM UFr5 R8GY"
    static let notSetUpViewModel = viewModel(recoveryState: .disabled)
    static let generatingViewModel = viewModel(recoveryState: .disabled, generateKey: true, key: key)
    static let setupViewModel = viewModel(recoveryState: .enabled, generateKey: true, key: key)
    static let incompleteViewModel = viewModel(recoveryState: .incomplete)
    static let unknownViewModel = viewModel(recoveryState: .unknown)
    static let changeViewModel = viewModel(recoveryState: .enabled) // AGENT-PLATFORM (Brief 0083): a state without a preview
    
    static var previews: some View {
        ElementNavigationStack {
            SecureBackupRecoveryKeyScreen(context: notSetUpViewModel.context)
        }
        .previewDisplayName("Not set up")
        
        ElementNavigationStack {
            SecureBackupRecoveryKeyScreen(context: generatingViewModel.context)
        }
        .previewDisplayName("Generating")
        
        ElementNavigationStack {
            SecureBackupRecoveryKeyScreen(context: setupViewModel.context)
        }
        .snapshotPreferences(expect: setupViewModel.context.observe(\.viewState.recoveryKey).map { $0 != nil })
        .previewDisplayName("Set up")
        
        ElementNavigationStack {
            SecureBackupRecoveryKeyScreen(context: incompleteViewModel.context)
        }
        .previewDisplayName("Incomplete")
        
        ElementNavigationStack {
            SecureBackupRecoveryKeyScreen(context: unknownViewModel.context)
        }
        .previewDisplayName("Unknown")
        
        // AGENT-PLATFORM (Brief 0083): a new key for someone who has one.
        ElementNavigationStack {
            SecureBackupRecoveryKeyScreen(context: changeViewModel.context)
        }
        .previewDisplayName("Change")
    }
    
    static func viewModel(recoveryState: SecureBackupRecoveryState, generateKey: Bool = false, key: String? = nil) -> SecureBackupRecoveryKeyScreenViewModelType {
        let backupController = SecureBackupControllerMock()
        backupController.recoveryState = CurrentValueSubject<SecureBackupRecoveryState, Never>(recoveryState).asCurrentValuePublisher()
        
        if let key {
            backupController.generateRecoveryKeyWithPassphraseReturnValue = .success(key)
        } else {
            backupController.generateRecoveryKeyWithPassphraseClosure = { _ in
                try? await Task.sleep(for: .seconds(1000))
                return .success("youshouldntseeme")
            }
        }
        
        let viewModel = SecureBackupRecoveryKeyScreenViewModel(secureBackupController: backupController,
                                                               userIndicatorController: UserIndicatorControllerMock(),
                                                               isModallyPresented: true)
        
        if generateKey {
            viewModel.context.send(viewAction: .generateKey)
        }
        
        return viewModel
    }
}
