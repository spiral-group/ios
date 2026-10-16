//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import SFSafeSymbols
import SwiftUI

struct SettingsScreen: View {
    @Bindable var context: SettingsScreenViewModel.Context
    
    var body: some View {
        Form {
            userSection
            
            if context.viewState.showUserStatus {
                userStatusSection
            }
            
            // AGENT-PLATFORM (decisions 187, 188): one row per domain, no
            // section headers. The account and security rows are in the
            // Security hub, the consent and visibility rows in Privacy, and
            // Labs has no row (threads are always on).
            
            // AGENT-PLATFORM (Brief 0073 / ADR-0008): registration is by
            // invitation, so the link is a first-class setting.
            invitePeopleSection
            
            accountSection
            
            appSection
            
            signOutSection
        }
        .compoundList()
        .navigationTitle(L10n.commonSettings)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(context.viewState.navigationBarVisibility, for: .navigationBar)
        .toolbar { toolbar }
    }
    
    private var userSection: some View {
        Section {
            ListRow(kind: .custom {
                Button {
                    context.send(viewAction: .userDetails)
                } label: {
                    HStack(spacing: 12) {
                        LoadableAvatarImage(url: context.viewState.userProfile.avatarURL,
                                            name: context.viewState.userProfile.displayName,
                                            contentID: context.viewState.userProfile.id,
                                            avatarSize: .user(on: .settings),
                                            mediaProvider: context.mediaProvider)
                            .accessibilityHidden(true)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(context.viewState.userProfile.displayName ?? "")
                                
                                if let statusEmoji = context.viewState.userProfile.status.displayed?.emoji {
                                    Text(String(statusEmoji))
                                }
                            }
                            .font(.compound.headingMD)
                            .foregroundColor(.compound.textPrimary)
                            
                            Text(context.viewState.userProfile.id)
                                .font(.compound.bodySM)
                                .foregroundColor(.compound.textSecondary)
                        }
                        
                        Spacer()
                        
                        ListRowAccessory.navigationLink
                    }
                    .padding(.horizontal, ListRowPadding.horizontal)
                    .padding(.vertical, 8)
                }
            })
        }
    }
    
    private var userStatusSection: some View {
        Section {
            SettingsScreenUserStatusRow(mode: context.viewState.userStatusRowMode) { action in
                context.send(viewAction: .userStatus(action))
            }
            .sheet(isPresented: $context.isPresentingStatusPicker) {
                SettingsScreenUserStatusPickerView { action in
                    context.send(viewAction: .userStatus(action))
                }
                .presentationDetents([.medium]) // Stop using a List and calculate the exact height?
                .presentationBackground(.compound.bgCanvasDefault)
            }
        }
    }
    
    // AGENT-PLATFORM (Brief 0073 / ADR-0008).
    private var invitePeopleSection: some View {
        Section {
            ListRow(label: .default(title: UntranslatedL10n.screenInvitePeopleTitle,
                                    icon: \.userAdd),
                    kind: .navigationLink {
                        context.send(viewAction: .invitePeople)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.invitePeople)
        }
    }
    
    // AGENT-PLATFORM (decision 187).
    private var accountSection: some View {
        Section {
            ListRow(label: .default(title: L10n.commonSecurity,
                                    icon: \.shield),
                    details: context.viewState.showSecuritySectionBadge ? .icon(securitySectionBadge) : nil,
                    kind: .navigationLink {
                        context.send(viewAction: .security)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.security)
            
            ListRow(label: .default(title: UntranslatedL10n.screenSettingsPrivacyTitle,
                                    icon: \.visibilityOn),
                    kind: .navigationLink {
                        context.send(viewAction: .privacy)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.privacy)
            
            ListRow(label: .default(title: L10n.screenNotificationSettingsTitle,
                                    icon: \.notifications),
                    kind: .navigationLink {
                        context.send(viewAction: .notifications)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.notifications)
            
            // AGENT-PLATFORM (Brief 0078): the account export and one call's export.
            if context.viewState.showYourData {
                ListRow(label: .default(title: UntranslatedL10n.screenYourDataTitle,
                                        icon: \.exportArchive),
                        kind: .navigationLink {
                            context.send(viewAction: .yourData)
                        })
                        .accessibilityIdentifier(A11yIdentifiers.settingsScreen.yourData) // AGENT-PLATFORM (decision 146)
            }
        }
    }
    
    // AGENT-PLATFORM (decision 187).
    private var appSection: some View {
        Section {
            ListRow(label: .default(title: UntranslatedL10n.screenSettingsAppearanceMediaTitle,
                                    icon: \.theme),
                    kind: .navigationLink {
                        context.send(viewAction: .appearanceAndMedia)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.appearanceAndMedia)
            
            ListRow(label: .default(title: L10n.commonAbout,
                                    icon: \.info),
                    kind: .navigationLink {
                        context.send(viewAction: .about)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.about)
            
            if context.viewState.isBugReportServiceEnabled {
                ListRow(label: .default(title: L10n.commonReportAProblem,
                                        icon: \.chatProblem),
                        kind: .navigationLink {
                            context.send(viewAction: .reportBug)
                        })
                        .accessibilityIdentifier(A11yIdentifiers.settingsScreen.reportBug)
            }
            
            if context.viewState.showAnalyticsSettings {
                ListRow(label: .default(title: L10n.commonAnalytics,
                                        icon: \.chart),
                        kind: .navigationLink {
                            context.send(viewAction: .analytics)
                        })
                        .accessibilityIdentifier(A11yIdentifiers.settingsScreen.analytics)
            }
            
            if context.viewState.showDeveloperOptions {
                ListRow(label: .default(title: L10n.commonDeveloperOptions,
                                        icon: \.code),
                        kind: .navigationLink {
                            context.send(viewAction: .developerOptions)
                        })
                        .accessibilityIdentifier(A11yIdentifiers.settingsScreen.developerOptions)
            }
        }
    }
    
    private var signOutSection: some View {
        Section {
            // AGENT-PLATFORM (decision 187): «Sign out», not upstream's «Remove this device».
            ListRow(label: .action(title: UntranslatedL10n.screenSignoutPreferenceItemSpiral,
                                   icon: \.signOut,
                                   role: .destructive),
                    kind: .button {
                        context.send(viewAction: .logout)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.logout)
            
            if context.viewState.showAccountDeactivation {
                ListRow(label: .action(title: L10n.actionDeleteAccount,
                                       icon: \.delete,
                                       role: .destructive),
                        kind: .navigationLink {
                            context.send(viewAction: .deactivateAccount)
                        })
                        .accessibilityIdentifier(A11yIdentifiers.settingsScreen.deleteAccount) // AGENT-PLATFORM (decision 146)
            }
        } footer: {
            versionSection
        }
    }
    
    private var versionSection: some View {
        VStack(spacing: 0) {
            versionText
                .frame(maxWidth: .infinity)
            
            if let deviceID = context.viewState.deviceID {
                Text(deviceID)
            }
        }
        .compoundListSectionFooter()
        .textSelection(.enabled)
        .padding(.top, 24)
        .onTapGesture(count: 7) {
            context.send(viewAction: .enableDeveloperOptions)
        }
    }
    
    private var versionText: Text {
        Text(L10n.settingsVersionNumber(InfoPlistReader.main.bundleShortVersionString, InfoPlistReader.main.bundleVersion))
    }
    
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ToolbarButton(role: .close) { context.send(viewAction: .close) }
                .accessibilityIdentifier(A11yIdentifiers.settingsScreen.done)
        }
    }
    
    @ViewBuilder
    private var securitySectionBadge: some View {
        if context.viewState.showSecuritySectionBadge {
            BadgeView(size: 10)
        }
    }
}

// MARK: - Previews

@available(iOS 26.0, *)
struct SettingsScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel()
    static let recoveryDisabledViewModel = makeViewModel(recoveryState: .disabled)
    
    static var previews: some View {
        ElementNavigationStack {
            SettingsScreen(context: viewModel.context)
        }
        .previewDisplayName("Default")
        
        // AGENT-PLATFORM (decision 187): Element's recovery nudge, on the Security row.
        ElementNavigationStack {
            SettingsScreen(context: recoveryDisabledViewModel.context)
        }
        .snapshotPreferences(expect: recoveryDisabledViewModel.context.observe(\.viewState.showSecuritySectionBadge))
        .previewDisplayName("Recovery not set up")
    }
    
    static func makeViewModel(recoveryState: SecureBackupRecoveryState = .enabled) -> SettingsScreenViewModel {
        let userSession = UserSessionMock(.init(clientProxy: ClientProxyMock(.init(userID: "@alice:example.com",
                                                                                   deviceID: "AAAAAAAAAAA",
                                                                                   displayName: "Alice Liddell",
                                                                                   status: .mockFocussing))))
        // AGENT-PLATFORM (decision 187): a Spiral account, which shows Your data and Delete account.
        userSession.agentPlatformService = AgentPlatformServiceMock()
        userSession.sessionSecurityStatePublisher = CurrentValueSubject(.init(verificationState: .verified, recoveryState: recoveryState)).asCurrentValuePublisher()
        return SettingsScreenViewModel(userSession: userSession,
                                       appSettings: .volatile(),
                                       isBugReportServiceEnabled: false,
                                       isInSecondaryWindow: false,
                                       userIndicatorController: UserIndicatorControllerMock())
    }
}
