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
    
    /// AGENT-PLATFORM (1.0.3 onboarding): the invitation, the buttons and the version, measured, so the stories know
    /// how much of the screen is theirs.
    @State private var buttonsHeight: CGFloat = 0

    var body: some View {
        standardContent // AGENT-PLATFORM (Brief 0083 L1b): no Element Classic account view
    }

    // AGENT-PLATFORM (1.0.3 onboarding, board pick S3; was Brief 0083 decision 308's headline on the canvas): App Store
    // stories on the blue — the bars, the brand row, a slide about what Spiral does with Spark, then the invitation and
    // the buttons. The page fills the screen and scrolls once it's taller (a small phone, large text, a long language);
    // the buttons stay put while the slides change, as the slide's text keeps the tallest slide's height.
    var standardContent: some View {
        GeometryReader { geometry in
            ScrollView {
                page(in: geometry)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(.onboardingBlue)
        .lightStatusBar()
        .navigationBarHidden(true) // AGENT-PLATFORM (Brief 0083 L1b): the bar was only for Classic's other options
        .alert(item: $context.alertInfo)
        .introspect(.window, on: .supportedVersions) { window in
            context.send(viewAction: .updateWindow(window))
        }
    }
    
    private func page(in geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content(availableHeight: geometry.size.height - buttonsHeight)
                .accessibilityIdentifier(A11yIdentifiers.authenticationStartScreen.hidden)
            
            Spacer(minLength: 0)
            
            buttons
                .padding(.top, CompoundDesignTokens.space4X)
                .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? CompoundDesignTokens.space2X : CompoundDesignTokens.space4X)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { buttonsHeight = $0 }
        }
        .padding(.horizontal, CompoundDesignTokens.space5X)
        .frame(minHeight: geometry.size.height, alignment: .top)
        .readableFrame()
    }

    // AGENT-PLATFORM (1.0.3 onboarding): the stories; a white-label build keeps the logo alone.
    @ViewBuilder
    func content(availableHeight: CGFloat) -> some View {
        if context.viewState.hideBrandChrome {
            brand
                .padding(.top, CompoundDesignTokens.space5X)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            AuthenticationStartStories(availableHeight: availableHeight) {
                brand
            }
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 308; 1.0.3 onboarding): the app's tile at the size of the name, white over the
    // blue, without the shadow AuthenticationStartLogo gives the large tile.
    var brand: some View {
        HStack(spacing: CompoundDesignTokens.space3X) {
            Image(asset: Asset.Images.appLogo)
                .resizable()
                .scaledToFit()
                .scaledFrame(size: 32, relativeTo: .compound.headingMD)
                .appLogoEdge(hasShadow: false) // AGENT-PLATFORM (Brief 0083, decision 370)
                .accessibilityHidden(true)
            
            if !context.viewState.hideBrandChrome {
                Text(InfoPlistReader.main.productionAppName)
                    .font(.compound.headingMDBold)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                
                // AGENT-PLATFORM (Brief 0084): never in a prod build.
                if let screenMark = SpiralEnvironment.current.screenMark {
                    Text(verbatim: screenMark)
                        .font(.compound.bodySMSemibold)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
    }
    
    /// The main action buttons.
    var buttons: some View {
        // AGENT-PLATFORM (ADR-0005 auth v2): a public single-server
        // messenger leads with Sign in / Create account; QR (second-device
        // linking) drops to a quiet tertiary at the bottom. Three buttons,
        // as Element X has; without an invitation in hand, the web
        // registration's first step asks for one (1.0.3).
        // AGENT-PLATFORM (1.0.3 onboarding): the white capsule leads on the blue, the frosted one follows.
        VStack(spacing: CompoundDesignTokens.space3X) {
            // AGENT-PLATFORM (Brief 0073 / ADR-0008): who is inviting.
            if let pendingInvite = context.viewState.pendingInvite {
                invitedBanner(pendingInvite)
                    .padding(.bottom, CompoundDesignTokens.space1X)
            }
            
            // AGENT-PLATFORM (Brief 0073): an invitation leads with Create
            // account; without one Sign in stays first.
            if context.viewState.pendingInvite != nil, context.viewState.showCreateAccountButton {
                Button { context.send(viewAction: .register) } label: {
                    Text(L10n.screenCreateAccountTitle)
                }
                .buttonStyle(.onboarding(.white))
                .accessibilityIdentifier(A11yIdentifiers.authenticationStartScreen.createAccount) // AGENT-PLATFORM (decision 146)
                
                Button { context.send(viewAction: .login) } label: {
                    Text(context.viewState.loginButtonTitle)
                }
                .buttonStyle(.onboarding(.frosted))
                .accessibilityIdentifier(A11yIdentifiers.authenticationStartScreen.signIn)
            } else {
                Button { context.send(viewAction: .login) } label: {
                    Text(context.viewState.loginButtonTitle)
                }
                .buttonStyle(.onboarding(.white))
                .accessibilityIdentifier(A11yIdentifiers.authenticationStartScreen.signIn)
                
                if context.viewState.showCreateAccountButton {
                    Button { context.send(viewAction: .register) } label: {
                        Text(L10n.screenCreateAccountTitle)
                    }
                    .buttonStyle(.onboarding(.frosted))
                    .accessibilityIdentifier(A11yIdentifiers.authenticationStartScreen.createAccount) // AGENT-PLATFORM (decision 146)
                }
            }
            
            if context.viewState.showQRCodeLoginButton {
                Button { context.send(viewAction: .loginWithQR) } label: {
                    // AGENT-PLATFORM (1.0.3 onboarding): a quiet white action on the blue, where Compound's tertiary is dark.
                    Label(L10n.screenOnboardingSignInWithQrCode, icon: \.qrCode)
                        .font(.compound.bodyLGSemibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier(A11yIdentifiers.authenticationStartScreen.signInWithQr)
            }
            
            versionText
                .font(.compound.bodySM)
                .foregroundStyle(.white.opacity(0.9)) // AGENT-PLATFORM (1.0.3 onboarding): on the blue
                .onTapGesture(count: 7) {
                    context.send(viewAction: .reportProblem)
                }
                .accessibilityIdentifier(A11yIdentifiers.authenticationStartScreen.appVersion)
                .overlay(alignment: .trailing) {
                    developerOptionsButton
                        .scaledOffset(x: 32, y: -0.5, relativeTo: .compound.bodySM)
                }
                .frame(maxWidth: .infinity) // AGENT-PLATFORM (1.0.3 onboarding): centred in the leading-aligned page
                .padding(.top, CompoundDesignTokens.space1X)
        }
    }
    
    // AGENT-PLATFORM (Brief 0073 / ADR-0008; 1.0.3 onboarding): the inviter's monogram on frosted glass, who invites
    // you and that they'll know you came.
    private func invitedBanner(_ pendingInvite: PendingInvite) -> some View {
        HStack(spacing: CompoundDesignTokens.space3X) {
            inviterAvatar(pendingInvite)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(pendingInvite.inviterDisplayName.map { UntranslatedL10n.screenStartInvitedBy($0) } ?? UntranslatedL10n.screenStartInvited)
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(.white)
                Text(pendingInvite.inviterDisplayName.map { UntranslatedL10n.screenStartInvitedByHint($0) } ?? UntranslatedL10n.screenStartInvitedHint)
                    .font(.compound.bodySM)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CompoundDesignTokens.space4X)
        .padding(.vertical, CompoundDesignTokens.space3X)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: SpiralRadius.listCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SpiralRadius.listCard, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(A11yIdentifiers.authenticationStartScreen.invitedBanner)
    }
    
    /// The app's standard monogram for a named inviter; a campaign's invitation has no one, so a person-plus.
    @ViewBuilder
    private func inviterAvatar(_ pendingInvite: PendingInvite) -> some View {
        if let name = pendingInvite.inviterDisplayName {
            PlaceholderAvatarImage(name: name, contentID: pendingInvite.inviterUserID ?? name)
                .clipShape(Circle())
                .scaledFrame(size: 40, relativeTo: .compound.bodyMD)
                .accessibilityHidden(true)
        } else {
            CompoundIcon(\.userAdd, size: .medium, relativeTo: .compound.bodyMD)
                .foregroundStyle(.white)
                .scaledFrame(size: 40, relativeTo: .compound.bodyMD)
                .background(.white.opacity(0.2), in: Circle())
                .accessibilityHidden(true)
        }
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
                    .foregroundStyle(.white.opacity(0.9)) // AGENT-PLATFORM (1.0.3 onboarding): on the blue
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
                                                                     inviterDisplayName: "Alice",
                                                                     inviterUserID: "@alice:spiral.md"))
    // AGENT-PLATFORM (1.0.3 onboarding): a campaign's invitation names no one.
    static let campaignViewModel = makeViewModel(pendingInvite: .init(token: "TESTFLIGHT"))
    
    static var previews: some View {
        AuthenticationStartScreen(context: viewModel.context)
            .previewDisplayName("Default")
        AuthenticationStartScreen(context: invitedViewModel.context)
            .previewDisplayName("Invited")
        AuthenticationStartScreen(context: campaignViewModel.context)
            .previewDisplayName("Invited by a campaign")
        // AGENT-PLATFORM (Brief 0083 L1b): no "Provisioned" or "Classic App" preview.
    }
    
    static func makeViewModel(pendingInvite: PendingInvite? = nil) -> AuthenticationStartScreenViewModel {
        let appSettings = AppSettings.volatile()
        appSettings.pendingInvite = pendingInvite
        
        return AuthenticationStartScreenViewModel(authenticationService: AuthenticationService.mock,
                                                  isBugReportServiceEnabled: true,
                                                  appSettings: appSettings,
                                                  userIndicatorController: UserIndicatorControllerMock()) // AGENT-PLATFORM (Brief 0083 L1b)
    }
}
