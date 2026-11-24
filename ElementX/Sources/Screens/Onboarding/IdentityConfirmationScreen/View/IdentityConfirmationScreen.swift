//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SpiralComponents // AGENT-PLATFORM (Brief 0083)
import SwiftUI

struct IdentityConfirmationScreen: View {
    @Bindable var context: IdentityConfirmationScreenViewModel.Context
    /// AGENT-PLATFORM (1.0.3): a device without a bottom safe area (iPhone SE, Touch ID iPads) gets the start screen's
    /// larger bottom margin, rather than the link 8 pt from the edge.
    @State private var hasBottomSafeArea = true
    
    var shouldShowSkipButton: Bool {
        #if DEBUG
        !ProcessInfo.isRunningTests
        #else
        false
        #endif
    }
    
    var body: some View {
        // AGENT-PLATFORM (Brief 0083, decision 308): the header leads, left aligned, near the top; the methods are
        // list rows at the bottom, then "Can't confirm?" as a link at the safe area.
        // AGENT-PLATFORM (Brief 0083, decision 323): the card at the screens' 24 pt margin, as on every later card.
        FullscreenDialog(topPadding: UIConstants.titleTopPaddingToNavigationBar,
                         horizontalPadding: CompoundDesignTokens.space6X,
                         bottomHorizontalPadding: CompoundDesignTokens.space6X,
                         bottomPadding: hasBottomSafeArea ? CompoundDesignTokens.space2X : CompoundDesignTokens.space4X) {
            screenHeader
        } bottomContent: {
            actions
        }
        .onGeometryChange(for: Bool.self) { $0.safeAreaInsets.bottom > 0 } action: { hasBottomSafeArea = $0 } // AGENT-PLATFORM (1.0.3)
        .toolbar { toolbar }
        .background()
        .backgroundStyle(.compound.bgCanvasDefault)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled()
        .alert(item: $context.alertInfo)
    }
    
    // MARK: - Private
    
    // AGENT-PLATFORM (Brief 0083, decisions 314 and 323): with no method to show, nothing is "below" to choose.
    private var subtitle: String {
        context.viewState.availableActions?.isEmpty == true ? UntranslatedL10n.screenIdentityConfirmationSubtitleNoMethodsSpiral : UntranslatedL10n.screenIdentityConfirmationSubtitleSpiral
    }
    
    // AGENT-PLATFORM (Brief 0083, decisions 308, 313 and 314): a small accent lock, a larger title and the link in the
    // accent; the header is shared with the screens after this one, and the copy is Spiral's.
    private var screenHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpiralDialogHeader(icon: \.lockSolid,
                               title: UntranslatedL10n.screenIdentityConfirmationTitleSpiral,
                               message: subtitle)
            
            Button(L10n.actionLearnMore) {
                UIApplication.shared.open(context.viewState.learnMoreURL)
            }
            .buttonStyle(.spiralLink)
            .padding(.top, CompoundDesignTokens.space1X)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 308): the methods as list rows, not filled buttons.
    private var actions: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space5X) {
            if let availableActions = context.viewState.availableActions {
                methods(availableActions)
                
                cannotConfirmLink
            } else {
                // AGENT-PLATFORM (Brief 0083, question 359): the methods and the link as placeholders until the methods
                // are known, in their own shape, so nothing moves when they come (decision 330). In neutral greys: redacted,
                // the real rows' icons would keep their accent blue.
                SpiralPreloader(label: L10n.commonLoading) {
                    VStack(alignment: .leading, spacing: CompoundDesignTokens.space5X) {
                        SpiralCard {
                            MethodRow(title: UntranslatedL10n.screenIdentityConfirmationUseAnotherDeviceSpiral,
                                      icon: \.mobile,
                                      iconColor: .compound.iconSecondary,
                                      showsSeparator: true) { }
                            MethodRow(title: UntranslatedL10n.screenIdentityConfirmationUseRecoveryKeySpiral,
                                      icon: \.key,
                                      iconColor: .compound.iconSecondary,
                                      showsSeparator: false) { }
                        }
                        
                        cannotConfirmLink
                    }
                }
            }
            
            if shouldShowSkipButton {
                Button("\(L10n.actionSkip) 🙉") {
                    context.send(viewAction: .skip)
                }
                .buttonStyle(.compound(.tertiary))
                .accessibilityIdentifier(A11yIdentifiers.identityConfirmationScreen.skip) // AGENT-PLATFORM (decision 146)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading) // AGENT-PLATFORM (Brief 0083, decision 323): leading with no card
    }
    
    private var cannotConfirmLink: some View {
        Button(UntranslatedL10n.screenIdentityConfirmationCannotConfirmSpiral) { // AGENT-PLATFORM (Brief 0083, decision 314)
            context.send(viewAction: .reset)
        }
        .buttonStyle(.spiralLink)
    }
    
    @ViewBuilder
    private func methods(_ availableActions: [IdentityConfirmationScreenViewState.AvailableActions]) -> some View {
        let showsOtherDevice = availableActions.contains(.interactiveVerification)
        let showsRecoveryKey = availableActions.contains(.recovery)
        
        if showsOtherDevice || showsRecoveryKey {
            SpiralCard { // AGENT-PLATFORM (Brief 0083, decision 313): the card the screens after this one share.
                if showsOtherDevice {
                    MethodRow(title: UntranslatedL10n.screenIdentityConfirmationUseAnotherDeviceSpiral, // AGENT-PLATFORM (Brief 0083, decision 314)
                              icon: \.mobile,
                              showsSeparator: showsRecoveryKey) {
                        context.send(viewAction: .otherDevice)
                    }
                }
                
                if showsRecoveryKey {
                    MethodRow(title: UntranslatedL10n.screenIdentityConfirmationUseRecoveryKeySpiral, // AGENT-PLATFORM (Brief 0083, decision 314)
                              icon: \.key,
                              showsSeparator: false) {
                        context.send(viewAction: .recoveryKey)
                    }
                }
            }
        }
    }
    
    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {
        ToolbarItem(placement: .destructiveAction) {
            Button(UntranslatedL10n.screenIdentityConfirmationSignOutSpiral) { // AGENT-PLATFORM (Brief 0083, decision 314): Spiral's "Sign out" (decision 187)
                context.send(viewAction: .logout)
            }
        }
    }
}

// AGENT-PLATFORM (Brief 0083, decision 308): a method as a list row, the icon in the accent and a chevron. Compound's
// `ListRow` lives in a `List`, which would put white rows on a grey screen and not at the bottom.
private struct MethodRow: View {
    let title: String
    let icon: KeyPath<CompoundIcons, Image>
    var iconColor: Color = .compound.iconAccentPrimary
    let showsSeparator: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            SpiralCardRow(icon: icon, iconColor: iconColor, showsSeparator: showsSeparator) {
                HStack(spacing: CompoundDesignTokens.space2X) {
                    Text(title)
                        .font(.compound.bodyLG)
                        .foregroundColor(.compound.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    ListRowAccessory.navigationLink
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.spiralCardRow)
    }
}

// MARK: - Previews

// AGENT-PLATFORM (Brief 0083): opted in to Spiral's gates. Without `@available(iOS 26.0, *)` it builds for the
// iOS 18 lane, and `observe(_:)` resolves to its AsyncStream fallback.
struct IdentityConfirmationScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static var viewModel = makeViewModel()
    static var loadingViewModel = makeViewModel(recoveryState: .unknown)
    static var noMethodsViewModel = makeViewModel(recoveryState: .disabled, hasOtherDevices: false) // AGENT-PLATFORM (Brief 0083)
    
    static var previews: some View {
        ElementNavigationStack {
            IdentityConfirmationScreen(context: viewModel.context)
        }
        .previewDisplayName("Actions")
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.availableActions).map { actions in
            actions?.contains([.interactiveVerification, .recovery]) == true
        })
        
        ElementNavigationStack {
            IdentityConfirmationScreen(context: loadingViewModel.context)
        }
        .environment(\.spiralPreloaderDelay, .zero) // AGENT-PLATFORM (Brief 0083): shows what a slow load shows.
        .previewDisplayName("Loading")
        
        // AGENT-PLATFORM (Brief 0083, decision 323): no other device and recovery off, a state people reach.
        ElementNavigationStack {
            IdentityConfirmationScreen(context: noMethodsViewModel.context)
        }
        .previewDisplayName("No methods")
        .snapshotPreferences(expect: noMethodsViewModel.context.observe(\.viewState.availableActions).map { $0?.isEmpty == true })
    }
    
    static func makeViewModel(recoveryState: SecureBackupRecoveryState = .enabled, hasOtherDevices: Bool = true) -> IdentityConfirmationScreenViewModel {
        let clientProxy = ClientProxyMock(.init())
        clientProxy.hasDevicesToVerifyAgainstReturnValue = .success(hasOtherDevices) // AGENT-PLATFORM (Brief 0083)
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        userSession.sessionSecurityStatePublisher = CurrentValuePublisher<SessionSecurityState, Never>(.init(verificationState: .unverified, recoveryState: recoveryState))
        
        return IdentityConfirmationScreenViewModel(userSession: userSession,
                                                   userSettings: .mock())
    }
}
