//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SpiralTokens // AGENT-PLATFORM (Brief 0083)
import SwiftUI

/// The screen shown at the beginning of the onboarding flow.
struct AuthenticationStartScreen: View {
    @Bindable var context: AuthenticationStartScreenViewModel.Context
    
    var body: some View {
        standardContent // AGENT-PLATFORM (Brief 0083 L1b): no Element Classic account view
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 308): Spiral's start. A small logo and the name sit top left, the
    // sentence is the headline under them and the buttons are at the bottom. Nothing depends on the size class,
    // so the snapshots show the phone's layout and a phone in landscape keeps the logo.
    var standardContent: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                        .frame(height: UIConstants.spacerHeight(in: geometry))
                    
                    content
                        .accessibilityIdentifier(A11yIdentifiers.authenticationStartScreen.hidden)
                    
                    Spacer(minLength: CompoundDesignTokens.space8X)
                    
                    buttons
                        .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 0 : CompoundDesignTokens.space4X)
                    
                    Spacer()
                        .frame(height: UIConstants.spacerHeight(in: geometry))
                }
                .padding(.horizontal, CompoundDesignTokens.space6X)
                .frame(minHeight: geometry.size.height)
                .readableFrame()
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background {
            AuthenticationStartScreenBackgroundImage()
        }
        .navigationBarHidden(true) // AGENT-PLATFORM (Brief 0083 L1b): the bar was only for Classic's other options
        .alert(item: $context.alertInfo)
        .sheet(isPresented: $context.showInvitePasteSheet) {
            // AGENT-PLATFORM (Brief 0073 / ADR-0008).
            InvitePasteSheet(context: context)
        }
        .introspect(.window, on: .supportedVersions) { window in
            context.send(viewAction: .updateWindow(window))
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 308): the brand row, then the welcome sentence as the headline.
    var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.top, CompoundDesignTokens.space4X)
            
            if !context.viewState.hideBrandChrome {
                // AGENT-PLATFORM: Spiral welcome subtitle (fork-local copy).
                Text(UntranslatedL10n.screenStartWelcomeSubtitle)
                    .font(.compound.headingXLBold)
                    .foregroundStyle(.compound.textPrimary)
                    .padding(.top, CompoundDesignTokens.space20X)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 308): the app's tile at the size of the name, without the shadow
    // AuthenticationStartLogo gives the large tile.
    var brand: some View {
        HStack(spacing: CompoundDesignTokens.space3X) {
            Image(asset: Asset.Images.appLogo)
                .resizable()
                .scaledToFit()
                .scaledFrame(size: 40, relativeTo: .compound.headingMD)
                .appLogoEdge() // AGENT-PLATFORM (Brief 0083, decision 370)
                .accessibilityHidden(true)
            
            if !context.viewState.hideBrandChrome {
                Text(InfoPlistReader.main.productionAppName)
                    .font(.compound.headingMDBold)
                    .foregroundStyle(.compound.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                
                // AGENT-PLATFORM (Brief 0084): never in a prod build.
                if let screenMark = SpiralEnvironment.current.screenMark {
                    Text(verbatim: screenMark)
                        .font(.compound.bodySMSemibold)
                        .foregroundStyle(.compound.textSecondary)
                }
            }
        }
    }
    
    /// The main action buttons.
    var buttons: some View {
        // AGENT-PLATFORM (ADR-0005 auth v2): a public single-server
        // messenger leads with Sign in / Create account; QR (second-device
        // linking) drops to a quiet tertiary at the bottom. Three buttons,
        // as Element X has; the invitation is asked for behind Create
        // account (Brief 0073).
        // AGENT-PLATFORM (Brief 0083, decisions 308 and 293): the second button is Compound's secondary, a quiet grey fill.
        VStack(spacing: CompoundDesignTokens.space3X) {
            // AGENT-PLATFORM (Brief 0073 / ADR-0008): who is inviting.
            if let pendingInvite = context.viewState.pendingInvite {
                invitedBanner(pendingInvite)
            }
            
            // AGENT-PLATFORM (Brief 0073): an invitation leads with Create
            // account; without one Sign in stays first.
            if context.viewState.pendingInvite != nil, context.viewState.showCreateAccountButton {
                Button { context.send(viewAction: .register) } label: {
                    Text(L10n.screenCreateAccountTitle)
                }
                .buttonStyle(.compound(.primary))
                .accessibilityIdentifier(A11yIdentifiers.authenticationStartScreen.createAccount) // AGENT-PLATFORM (decision 146)
                
                Button { context.send(viewAction: .login) } label: {
                    Text(context.viewState.loginButtonTitle)
                }
                .buttonStyle(.compound(.secondary))
                .accessibilityIdentifier(A11yIdentifiers.authenticationStartScreen.signIn)
            } else {
                Button { context.send(viewAction: .login) } label: {
                    Text(context.viewState.loginButtonTitle)
                }
                .buttonStyle(.compound(.primary))
                .accessibilityIdentifier(A11yIdentifiers.authenticationStartScreen.signIn)
                
                if context.viewState.showCreateAccountButton {
                    Button { context.send(viewAction: .register) } label: {
                        Text(L10n.screenCreateAccountTitle)
                    }
                    .buttonStyle(.compound(.secondary))
                    .accessibilityIdentifier(A11yIdentifiers.authenticationStartScreen.createAccount) // AGENT-PLATFORM (decision 146)
                }
            }
            
            if context.viewState.showQRCodeLoginButton {
                Button { context.send(viewAction: .loginWithQR) } label: {
                    Label(L10n.screenOnboardingSignInWithQrCode, icon: \.qrCode)
                }
                .buttonStyle(.compound(.tertiary))
                .accessibilityIdentifier(A11yIdentifiers.authenticationStartScreen.signInWithQr)
            }
            
            versionText
                .font(.compound.bodySM)
                .foregroundColor(.compound.textSecondary)
                .onTapGesture(count: 7) {
                    context.send(viewAction: .reportProblem)
                }
                .accessibilityIdentifier(A11yIdentifiers.authenticationStartScreen.appVersion)
                .overlay(alignment: .trailing) {
                    developerOptionsButton
                        .scaledOffset(x: 32, y: -0.5, relativeTo: .compound.bodySM)
                }
                .padding(.top, CompoundDesignTokens.space2X)
        }
    }
    
    // AGENT-PLATFORM (Brief 0073 / ADR-0008).
    private func invitedBanner(_ pendingInvite: PendingInvite) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CompoundIcon(\.userAdd, size: .medium, relativeTo: .compound.bodyLG)
                .foregroundStyle(.compound.iconAccentPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(pendingInvite.inviterDisplayName.map { UntranslatedL10n.screenStartInvitedBy($0) } ?? UntranslatedL10n.screenStartInvited)
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(.compound.textPrimary)
                Text(UntranslatedL10n.screenStartInvitedHint)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        // AGENT-PLATFORM (Brief 0083): a list card's radius, as the identity screen's methods.
        .background(.compound.bgSubtleSecondary, in: RoundedRectangle(cornerRadius: SpiralRadius.listCard, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(A11yIdentifiers.authenticationStartScreen.invitedBanner)
    }
    
    var versionText: Text {
        // Let's not deal with snapshotting a changing version string.
        let shortVersionString = ProcessInfo.isRunningTests ? "0.0.0" : InfoPlistReader.main.bundleShortVersionString
        return Text(L10n.screenOnboardingAppVersion(shortVersionString))
    }
    
    @ViewBuilder
    var developerOptionsButton: some View {
        if AppSettings.appBuildType != .release, !ProcessInfo.isRunningTests {
            Button { context.send(viewAction: .developerOptions) } label: {
                CompoundIcon(\.code)
                    .foregroundStyle(.compound.iconSecondary)
            }
            .accessibilityLabel(L10n.commonDeveloperOptions)
        }
    }
}

// MARK: - Previews

// AGENT-PLATFORM (Brief 0083): opted in to Spiral's gates.
struct AuthenticationStartScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = makeViewModel()
    static let invitedViewModel = makeViewModel(pendingInvite: .init(token: "Qz8Hf72Kd91",
                                                                      inviterDisplayName: "Andrii",
                                                                      inviterUserID: "@alice:spiral.md"))
    
    static var previews: some View {
        AuthenticationStartScreen(context: viewModel.context)
            .previewDisplayName("Default")
        AuthenticationStartScreen(context: invitedViewModel.context)
            .previewDisplayName("Invited")
        // AGENT-PLATFORM (Brief 0083 L1b): no "Provisioned" or "Classic App" preview.
    }
    
    static func makeViewModel(pendingInvite: PendingInvite? = nil,
                              registrationRequiresInvite: Bool = true) -> AuthenticationStartScreenViewModel {
        let appSettings = AppSettings.volatile()
        appSettings.pendingInvite = pendingInvite
        appSettings.registrationRequiresInvite = registrationRequiresInvite
        
        return AuthenticationStartScreenViewModel(authenticationService: AuthenticationService.mock,
                                                  isBugReportServiceEnabled: true,
                                                  appSettings: appSettings,
                                                  userIndicatorController: UserIndicatorControllerMock()) // AGENT-PLATFORM (Brief 0083 L1b)
    }
}
