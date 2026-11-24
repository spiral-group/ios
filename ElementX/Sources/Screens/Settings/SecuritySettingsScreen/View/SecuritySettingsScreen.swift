//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (decision 187): the Security hub. The footers tell the
// sign-in phrase (the account) apart from the recovery key (the history).
// The Spiral feature is built on Element's `SettingsScreen.swift`.
//

import Combine
import Compound
import SwiftUI

struct SecuritySettingsScreen: View {
    @Bindable var context: SecuritySettingsScreenViewModel.Context
    
    var body: some View {
        Form {
            signInSection
            
            if context.viewState.showEncryption {
                messagesSection
            }
            
            thisDeviceSection
        }
        .spiralGroupedList() // AGENT-PLATFORM (Brief 0083): Spiral's grouped list, was `compoundList()`.
        .navigationTitle(L10n.commonSecurity)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
    }
    
    private var signInSection: some View {
        Section {
            // 1.0.3: «Add sign-in phrase» for an account made with Apple. Same row, so nothing moves.
            ListRow(label: .default(title: context.viewState.phraseRowTitle,
                                    icon: \.devicePasskey),
                    kind: .button {
                        context.send(viewAction: .newPhrase)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.securitySettingsScreen.newPhrase)
            
            // 1.0.3: shown only once the server has answered — never a placeholder.
            switch context.viewState.signInMethods.appleRow {
            case .linked:
                ListRow(label: .default(title: UntranslatedL10n.screenSettingsAppleTitle,
                                        icon: Self.appleIcon),
                        details: .title(UntranslatedL10n.screenSettingsAppleConnected),
                        kind: .label)
                    .accessibilityIdentifier(A11yIdentifiers.securitySettingsScreen.apple)
            case .add:
                ListRow(label: .default(title: UntranslatedL10n.screenSettingsAppleAddTitle,
                                        icon: Self.appleIcon),
                        kind: .button {
                            context.send(viewAction: .addApple)
                        })
                        .accessibilityIdentifier(A11yIdentifiers.securitySettingsScreen.apple)
            case nil:
                EmptyView()
            }
            
            // The account page opens in a web session, so the row shows where it leads.
            if let url = context.viewState.accountProfileURL {
                ListRow(label: .default(title: UntranslatedL10n.screenSettingsDevicesTitle,
                                        icon: \.devices),
                        details: .icon(CompoundIcon(\.popOut).foregroundStyle(.compound.iconTertiaryAlpha)), // Grey as the chevron (Brief 0083).
                        kind: .button {
                            context.send(viewAction: .manageAccount(url: url))
                        })
                        .accessibilityIdentifier(A11yIdentifiers.securitySettingsScreen.devices)
            }
            
            if context.viewState.showLinkNewDeviceButton {
                ListRow(label: .default(title: L10n.commonLinkNewDevice,
                                        icon: \.qrCode),
                        kind: .navigationLink {
                            context.send(viewAction: .linkNewDevice)
                        })
            }
        } header: {
            Text(UntranslatedL10n.screenSecuritySignInSection)
                .compoundListSectionHeader()
        } footer: {
            Text(UntranslatedL10n.screenSecuritySignInFooter)
                .compoundListSectionFooter()
        }
    }
    
    /// Compound has no Apple glyph; the SF Symbol drawn like its neighbours (decision 320).
    private static var appleIcon: CompoundIcon {
        CompoundIcon(systemName: "apple.logo", label: "Apple")
    }
    
    private var messagesSection: some View {
        Section {
            ListRow(label: .default(title: UntranslatedL10n.commonEncryptionSpiral, // AGENT-PLATFORM (Brief 0083): five locales leave upstream's key English.
                                    icon: \.key),
                    details: context.viewState.showEncryptionBadge ? .icon(BadgeView(size: 10)) : nil,
                    kind: .navigationLink {
                        context.send(viewAction: .secureBackup)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.securitySettingsScreen.encryption)
        } header: {
            Text(UntranslatedL10n.screenSecurityMessagesSection)
                .compoundListSectionHeader()
        } footer: {
            Text(UntranslatedL10n.screenSecurityMessagesFooter)
                .compoundListSectionFooter()
        }
    }
    
    private var thisDeviceSection: some View {
        Section {
            ListRow(label: .default(title: L10n.commonScreenLock,
                                    icon: \.lock),
                    kind: .navigationLink {
                        context.send(viewAction: .appLock)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.securitySettingsScreen.screenLock)
        } header: {
            Text(UntranslatedL10n.screenSecurityThisDeviceSection)
                .compoundListSectionHeader()
        }
    }
}

// MARK: - Previews

// AGENT-PLATFORM (Brief 0083, lane settings): gated.
struct SecuritySettingsScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = makeViewModel(recoveryState: .enabled)
    static let recoveryDisabledViewModel = makeViewModel(recoveryState: .disabled)
    // 1.0.3: an account made with Apple, and a phrase account the server can add Apple to.
    static let appleAccountViewModel = makeViewModel(recoveryState: .enabled,
                                                     signInMethods: .init(phrase: false, apple: true, appleAvailable: true))
    static let phraseAccountViewModel = makeViewModel(recoveryState: .enabled,
                                                      signInMethods: .init(phrase: true, apple: false, appleAvailable: true))
    
    static var previews: some View {
        ElementNavigationStack {
            SecuritySettingsScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.accountProfileURL).map { $0 != nil })
        .previewDisplayName("Default")
        
        ElementNavigationStack {
            SecuritySettingsScreen(context: recoveryDisabledViewModel.context)
        }
        .snapshotPreferences(expect: recoveryDisabledViewModel.context.observe(\.viewState.accountProfileURL).map { $0 != nil })
        .previewDisplayName("Recovery not set up")
        
        ElementNavigationStack {
            SecuritySettingsScreen(context: appleAccountViewModel.context)
        }
        .snapshotPreferences(expect: appleAccountViewModel.context.observe(\.viewState).map { $0.accountProfileURL != nil && $0.signInMethods.phrase != nil })
        .previewDisplayName("Add sign-in phrase")
        
        ElementNavigationStack {
            SecuritySettingsScreen(context: phraseAccountViewModel.context)
        }
        .snapshotPreferences(expect: phraseAccountViewModel.context.observe(\.viewState).map { $0.accountProfileURL != nil && $0.signInMethods.phrase != nil })
        .previewDisplayName("Add Sign in with Apple")
    }
    
    static func makeViewModel(recoveryState: SecureBackupRecoveryState, signInMethods: SignInMethods? = nil) -> SecuritySettingsScreenViewModel {
        let userSession = UserSessionMock(.init())
        userSession.sessionSecurityStatePublisher = CurrentValueSubject(.init(verificationState: .verified, recoveryState: recoveryState)).asCurrentValuePublisher()
        if let signInMethods {
            let service = AgentPlatformServiceMock()
            service.fetchSignInMethodsReturnValue = .success(signInMethods)
            userSession.agentPlatformService = service
        }
        return SecuritySettingsScreenViewModel(userSession: userSession, appSettings: .volatile())
    }
}
