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
    // AGENT-PLATFORM (Brief 0083, decision 349)
    private static let maxContentWidth: CGFloat = 640
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass // AGENT-PLATFORM (Brief 0083, decision 349)
    
    @Bindable var context: SettingsScreenViewModel.Context
    
    @State private var width: CGFloat = 0 // AGENT-PLATFORM (Brief 0083, decision 349)
    
    var body: some View {
        // AGENT-PLATFORM (Brief 0083, decision 357): the person's field, as on a profile. The title stays in the bar.
        SpiralProfilePage(picture: .user(context.viewState.userProfile), mediaProvider: context.mediaProvider) {
            userSection
            
            if context.viewState.showUserStatusInput {
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
            
            if context.viewState.showAccountDeactivation {
                deleteAccountSection
            }
        }
        .navigationTitle(L10n.commonSettings)
        .toolbarVisibility(context.viewState.navigationBarVisibility, for: .navigationBar)
        .toolbar { toolbar } // AGENT-PLATFORM (1.0.3): share my profile.
        // AGENT-PLATFORM (Brief 0083, decision 349): a tab's root, so there is nothing to close, and full width on iPad.
        .contentMargins(.horizontal, sideMargin, for: .scrollContent)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }
    
    // AGENT-PLATFORM (1.0.3, operator 2026-11-19): the owner's own spiral.md link, as a profile's Share shares it.
    // The bar's only item: the tab's root has no Done button.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let shareLink = context.viewState.shareLink {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: shareLink) {
                    CompoundIcon(\.shareIos)
                        .accessibilityHidden(true)
                }
                .accessibilityLabel(UntranslatedL10n.a11ySettingsShareProfile) // AGENT-PLATFORM (1.0.3): not a bare «Share».
                .accessibilityIdentifier(A11yIdentifiers.settingsScreen.shareProfile)
            }
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 349): iPad's cards stay a readable width; `nil` keeps the system's margins on iPhone.
    private var sideMargin: CGFloat? {
        horizontalSizeClass == .regular ? max((width - Self.maxContentWidth) / 2, CompoundDesignTokens.space4X) : nil
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 357): the avatar centred over the name, the Matrix ID and Edit, on the page's
    // field. It was a white card, and before that Element's row of a 52 pt avatar, the name and a chevron. Only the ink
    // stands on the field (340): the grey and the accent drop under 4.5:1 there.
    private var userSection: some View {
        Section {
            Button {
                context.send(viewAction: .userDetails)
            } label: {
                VStack(spacing: CompoundDesignTokens.space1X) {
                    LoadableAvatarImage(url: context.viewState.userProfile.avatarURL,
                                        name: context.viewState.userProfile.displayName,
                                        contentID: context.viewState.userProfile.id,
                                        avatarSize: .user(on: .settings),
                                        mediaProvider: context.mediaProvider)
                        .accessibilityHidden(true)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1) // At AX3 it filled the screen.
                        .padding(.bottom, CompoundDesignTokens.space2X)
                    
                    HStack(spacing: CompoundDesignTokens.space1_5X) {
                        Text(context.viewState.userProfile.displayName ?? "")
                        
                        if let statusEmoji = context.viewState.userProfile.status.displayed?.emoji {
                            Text(String(statusEmoji))
                        }
                    }
                    .font(.compound.headingMDBold)
                    .foregroundColor(.compound.textPrimary)
                    
                    Text(Self.lineBreakable(context.viewState.userProfile.id))
                        .font(.compound.bodyMD)
                        .foregroundColor(.compound.textPrimary)
                        .accessibilityLabel(context.viewState.userProfile.id) // The raw ID, without U+200B.
                    
                    Text(L10n.actionEdit)
                        .font(.compound.bodyMDSemibold)
                        .foregroundColor(.compound.textPrimary)
                        .padding(.horizontal, CompoundDesignTokens.space4X)
                        .padding(.vertical, CompoundDesignTokens.space1_5X)
                        .spiralGlass(in: Capsule(), snapshotBackground: .compound.bgCanvasDefault.opacity(0.72)) // Decision 346
                        .padding(.top, CompoundDesignTokens.space2X)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, ListRowPadding.horizontal)
                .padding(.top, CompoundDesignTokens.space4X)
                .padding(.bottom, CompoundDesignTokens.space3X)
                .contentShape(Rectangle())
                .spiralProfileFieldEdge()
            }
            .buttonStyle(.spiralProfileAction)
            .accessibilityIdentifier(A11yIdentifiers.settingsScreen.account)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
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
                .compoundListRowStyle() // AGENT-PLATFORM (Brief 0083): the picker keeps upstream's rows.
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
            // AGENT-PLATFORM (Brief 0083, lane settings): red titles centred without a glyph, as iOS's account
            // page signs out. Both confirmations are unchanged.
            ListRow(label: .centeredAction(title: UntranslatedL10n.screenSignoutPreferenceItemSpiral,
                                           icon: EmptyView(),
                                           role: .destructive),
                    kind: .button {
                        context.send(viewAction: .logout)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.logout)
        } footer: {
            if !context.viewState.showAccountDeactivation {
                versionSection
            }
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, lane settings): its own card under Sign out, with the version under it.
    private var deleteAccountSection: some View {
        Section {
            ListRow(label: .centeredAction(title: L10n.actionDeleteAccount,
                                           icon: EmptyView(),
                                           role: .destructive),
                    kind: .button {
                        context.send(viewAction: .deactivateAccount)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.deleteAccount) // AGENT-PLATFORM (decision 146)
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
        // AGENT-PLATFORM (Brief 0084): a Staging build says so here.
        Text(SpiralEnvironment.current.markedVersionLine(L10n.settingsVersionNumber(InfoPlistReader.main.bundleShortVersionString, InfoPlistReader.main.bundleVersion)))
    }
    
    @ViewBuilder
    private var securitySectionBadge: some View {
        if context.viewState.showSecuritySectionBadge {
            BadgeView(size: 10)
        }
    }
    
    /// AGENT-PLATFORM (Brief 0083, lane settings): a Matrix ID breaks only after ":" and ".", never with a hyphen
    /// inside a word (at AX3 it read "example.-com").
    private static func lineBreakable(_ id: String) -> String {
        id.replacingOccurrences(of: ":", with: ":\u{200B}")
            .replacingOccurrences(of: ".", with: ".\u{200B}")
    }
}

// MARK: - Previews

// AGENT-PLATFORM (Brief 0083, lane settings): gated, and built for iOS 18's lane too.
struct SettingsScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = makeViewModel()
    static let recoveryDisabledViewModel = makeViewModel(recoveryState: .disabled)
    static let photoViewModel = makeViewModel(avatarURL: .mockMXCUserAvatar)
    
    static var previews: some View {
        ElementNavigationStack {
            SettingsScreen(context: viewModel.context)
        }
        .previewDisplayName("Default")
        
        // AGENT-PLATFORM (Brief 0083, decision 357): the field from a photo; "Default" has the monogram's.
        ElementNavigationStack {
            SettingsScreen(context: photoViewModel.context)
        }
        .previewDisplayName("With a photo")
        
        // AGENT-PLATFORM (decision 187): Element's recovery nudge, on the Security row.
        ElementNavigationStack {
            SettingsScreen(context: recoveryDisabledViewModel.context)
        }
        .snapshotPreferences(expect: recoveryDisabledViewModel.context.observe(\.viewState.showSecuritySectionBadge))
        .previewDisplayName("Recovery not set up")
    }
    
    static func makeViewModel(recoveryState: SecureBackupRecoveryState = .enabled, avatarURL: URL? = nil) -> SettingsScreenViewModel {
        // AGENT-PLATFORM (1.0.3): an ID on Spiral's homeserver, so the bar shows the share button.
        let userSession = UserSessionMock(.init(clientProxy: ClientProxyMock(.init(userID: "@alice:\(SpiralLink.serverName)",
                                                                                   deviceID: "AAAAAAAAAAA",
                                                                                   displayName: "Alice Liddell",
                                                                                   avatarURL: avatarURL,
                                                                                   status: .mockFocussing))))
        // AGENT-PLATFORM (decision 187): a Spiral account, which shows Your data and Delete account.
        userSession.agentPlatformService = AgentPlatformServiceMock()
        userSession.sessionSecurityStatePublisher = CurrentValueSubject(.init(verificationState: .verified, recoveryState: recoveryState)).asCurrentValuePublisher()
        return SettingsScreenViewModel(userSession: userSession,
                                       isBugReportServiceEnabled: false,
                                       isInSecondaryWindow: false,
                                       userIndicatorController: UserIndicatorControllerMock())
    }
}
