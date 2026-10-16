//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//


import Compound
import SwiftUI

struct InviteWelcomeScreen: View {
    @Bindable var context: InviteWelcomeScreenViewModelType.Context
    
    var body: some View {
        FullscreenDialog(topPadding: UIConstants.startScreenBreakerScreenTopPadding) {
            header
        } bottomContent: {
            buttons
        }
        .background()
        .backgroundStyle(.compound.bgCanvasDefault)
        .navigationBarHidden(true)
        .interactiveDismissDisabled()
        .alert(item: $context.alertInfo)
    }
    
    private var header: some View {
        VStack(spacing: 0) {
            LoadableAvatarImage(url: context.viewState.inviterProfile?.avatarURL,
                                name: context.viewState.inviterName,
                                contentID: context.viewState.inviterUserID,
                                avatarSize: .user(on: .memberDetails),
                                mediaProvider: context.mediaProvider)
                .accessibilityHidden(true)
                .padding(.bottom, 24)
            
            Text(UntranslatedL10n.screenInviteWelcomeTitle)
                .font(.compound.headingMDBold)
                .multilineTextAlignment(.center)
                .foregroundColor(.compound.textPrimary)
                .padding(.bottom, 8)
            
            Text(UntranslatedL10n.screenInviteWelcomeMessage(context.viewState.inviterName))
                .font(.compound.bodyMD)
                .multilineTextAlignment(.center)
                .foregroundColor(.compound.textSecondary)
                .accessibilityIdentifier(A11yIdentifiers.inviteWelcomeScreen.text) // AGENT-PLATFORM (decision 148)
        }
    }
    
    private var buttons: some View {
        VStack(spacing: 16) {
            Button {
                context.send(viewAction: .message)
            } label: {
                if context.viewState.isOpeningChat {
                    ProgressView()
                } else {
                    Text(UntranslatedL10n.screenInviteWelcomeMessageAction(context.viewState.inviterName))
                }
            }
            .buttonStyle(.compound(.primary))
            .disabled(context.viewState.isOpeningChat)
            .accessibilityIdentifier(A11yIdentifiers.inviteWelcomeScreen.message)
            
            Button(UntranslatedL10n.screenInviteWelcomeLater) {
                context.send(viewAction: .later)
            }
            .buttonStyle(.compound(.tertiary))
            .disabled(context.viewState.isOpeningChat)
            .accessibilityIdentifier(A11yIdentifiers.inviteWelcomeScreen.later)
        }
    }
}

// MARK: - Previews

struct InviteWelcomeScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel(displayName: "Emma")
    static let noNameViewModel = makeViewModel(displayName: nil)
    
    static var previews: some View {
        ElementNavigationStack {
            InviteWelcomeScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.inviterProfile).map { $0 != nil })
        .previewDisplayName("Named inviter")
        
        ElementNavigationStack {
            InviteWelcomeScreen(context: noNameViewModel.context)
        }
        .snapshotPreferences(expect: noNameViewModel.context.observe(\.viewState.inviterProfile).map { $0 != nil })
        .previewDisplayName("No display name")
    }
    
    static func makeViewModel(displayName: String?) -> InviteWelcomeScreenViewModel {
        let clientProxy = ClientProxyMock(.init(userID: "@newcomer:spiral.md"))
        clientProxy.profileForReturnValue = .success(.init(userID: "@emmm:spiral.md", displayName: displayName))
        return InviteWelcomeScreenViewModel(inviterUserID: "@emmm:spiral.md",
                                            clientProxy: clientProxy,
                                            mediaProvider: MediaProviderMock(.init()))
    }
}
