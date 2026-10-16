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
        .compoundList()
        .navigationTitle(L10n.commonSecurity)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
    }
    
    private var signInSection: some View {
        Section {
            ListRow(label: .default(title: UntranslatedL10n.screenSettingsNewPhraseTitle,
                                    icon: \.devicePasskey),
                    kind: .button {
                        context.send(viewAction: .newPhrase)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.securitySettingsScreen.newPhrase)
            
            // The account page opens in a web session, so the row shows where it leads.
            if let url = context.viewState.accountProfileURL {
                ListRow(label: .default(title: UntranslatedL10n.screenSettingsDevicesTitle,
                                        icon: \.devices),
                        details: .icon(\.popOut),
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
    
    private var messagesSection: some View {
        Section {
            ListRow(label: .default(title: L10n.commonEncryption,
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

struct SecuritySettingsScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel(recoveryState: .enabled)
    static let recoveryDisabledViewModel = makeViewModel(recoveryState: .disabled)
    
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
    }
    
    static func makeViewModel(recoveryState: SecureBackupRecoveryState) -> SecuritySettingsScreenViewModel {
        let userSession = UserSessionMock(.init())
        userSession.sessionSecurityStatePublisher = CurrentValueSubject(.init(verificationState: .verified, recoveryState: recoveryState)).asCurrentValuePublisher()
        return SecuritySettingsScreenViewModel(userSession: userSession, appSettings: .volatile())
    }
}
