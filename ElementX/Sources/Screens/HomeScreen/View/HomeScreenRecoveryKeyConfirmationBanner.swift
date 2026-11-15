//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import SpiralTokens // AGENT-PLATFORM (Brief 0083)
import SwiftUI

struct HomeScreenRecoveryKeyConfirmationBanner: View {
    enum State { case setUpRecovery, recoveryOutOfSync }
    let state: State
    var context: HomeScreenViewModel.Context
    
    // AGENT-PLATFORM (Brief 0083, decision 314): Spiral's copy, through `Untranslated.strings`' `*_spiral` keys.
    var title: String {
        switch state {
        case .setUpRecovery: UntranslatedL10n.bannerSetUpRecoveryTitleSpiral
        case .recoveryOutOfSync: UntranslatedL10n.confirmRecoveryKeyBannerTitleSpiral
        }
    }
    
    var message: String {
        switch state {
        case .setUpRecovery: UntranslatedL10n.bannerSetUpRecoveryContentSpiral
        case .recoveryOutOfSync: UntranslatedL10n.confirmRecoveryKeyBannerMessageSpiral
        }
    }
    
    var actionTitle: String {
        switch state {
        case .setUpRecovery: UntranslatedL10n.bannerSetUpRecoverySubmitSpiral
        case .recoveryOutOfSync: UntranslatedL10n.confirmRecoveryKeyBannerPrimaryButtonTitleSpiral
        }
    }
    
    var primaryAction: HomeScreenViewAction {
        switch state {
        case .setUpRecovery: .setupRecovery
        case .recoveryOutOfSync: .confirmRecoveryKey
        }
    }
    
    var body: some View {
        // AGENT-PLATFORM (Brief 0083, decision 313): the identity path's look in a block: a small accent key before the
        // title, the sentence, then the new buttons.
        VStack(spacing: CompoundDesignTokens.space4X) {
            content
            buttons
        }
        .padding(CompoundDesignTokens.space4X)
        .background(.compound.bgSubtleSecondary, in: RoundedRectangle(cornerRadius: SpiralRadius.block, style: .continuous))
        .padding(.horizontal, CompoundDesignTokens.space4X)
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space1X) {
            HStack(alignment: .center, spacing: CompoundDesignTokens.space3X) {
                CompoundIcon(\.keySolid, size: .medium, relativeTo: .compound.bodyLGSemibold) // AGENT-PLATFORM (Brief 0083, decision 313)
                    .foregroundStyle(.compound.iconAccentPrimary)
                    .accessibilityHidden(true)
                
                Text(title)
                    .font(.compound.bodyLGSemibold)
                    .foregroundColor(.compound.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if state == .setUpRecovery {
                    Button {
                        context.send(viewAction: .skipRecoveryKeyConfirmation)
                    } label: {
                        CompoundIcon(\.close, size: .medium, relativeTo: .compound.bodyLGSemibold)
                            .foregroundColor(.compound.iconSecondary)
                    }
                }
            }
            
            Text(message)
                .font(.compound.bodyMD)
                .foregroundColor(.compound.textSecondary)
        }
    }
    
    var buttons: some View {
        VStack(spacing: CompoundDesignTokens.space3X) { // AGENT-PLATFORM (Brief 0083, decision 313)
            Button {
                context.send(viewAction: primaryAction)
            } label: {
                Text(actionTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.compound(.primary, size: .medium))
            .accessibilityIdentifier(A11yIdentifiers.homeScreen.recoveryKeyConfirmationBannerContinue)
            
            if state == .recoveryOutOfSync {
                Button {
                    context.send(viewAction: .resetEncryption)
                } label: {
                    Text(UntranslatedL10n.confirmRecoveryKeyBannerSecondaryButtonTitleSpiral) // AGENT-PLATFORM (Brief 0083, decision 314)
                        .frame(maxWidth: .infinity)
                }
                // AGENT-PLATFORM (Brief 0083, decision 313): a quiet secondary, raised above the block's grey (decision 329).
                .buttonStyle(.compound(.secondary, size: .medium, isRaised: true))
            }
        }
    }
}

struct HomeScreenRecoveryKeyConfirmationBanner_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview { // AGENT-PLATFORM (Brief 0083)
    static let viewModel = makeViewModel()
    static let chatsViewModel = makeViewModel(roomListState: .loaded(.mockRooms), recoveryState: .disabled) // AGENT-PLATFORM (Brief 0083)
    
    static var previews: some View {
        HomeScreenRecoveryKeyConfirmationBanner(state: .setUpRecovery,
                                                context: viewModel.context)
            .previewDisplayName("Set up recovery")
        HomeScreenRecoveryKeyConfirmationBanner(state: .recoveryOutOfSync,
                                                context: viewModel.context)
            .previewDisplayName("Out of sync")
        
        // AGENT-PLATFORM (Brief 0083, decision 313): the banner where an account without recovery sees it.
        ElementNavigationStack {
            HomeScreen(context: chatsViewModel.context)
        }
        .snapshotPreferences(expect: chatsViewModel.context.$viewState.map { state in
            state.roomListMode == .rooms && state.securityBannerMode == .show(.setUpRecovery)
        })
        .previewDisplayName("In Chats")
    }
    
    // AGENT-PLATFORM (Brief 0083): a room list and a recovery state, for the banner in Chats.
    static func makeViewModel(roomListState: RoomSummaryProviderMockConfigurationState = .loading,
                              recoveryState: SecureBackupRecoveryState = .enabled) -> HomeScreenViewModel {
        let clientProxy = ClientProxyMock(.init(userID: "@alice:example.com",
                                                roomSummaryProvider: RoomSummaryProviderMock(.init(state: roomListState))))
        
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        let securityState = SessionSecurityState(verificationState: .verified, recoveryState: recoveryState)
        userSession.sessionSecurityStatePublisher = CurrentValueSubject<SessionSecurityState, Never>(securityState).asCurrentValuePublisher()
        
        return HomeScreenViewModel(userSession: userSession,
                                   availableSessionsPublisher: .init([.init(userSession: userSession)]),
                                   selectedRoomPublisher: CurrentValueSubject<String?, Never>(nil).asCurrentValuePublisher(),
                                   analyticsService: AnalyticsServiceMock(.init()),
                                   bugReportService: BugReportServiceMock(.init()),
                                   userIndicatorController: UserIndicatorControllerMock())
    }
}
