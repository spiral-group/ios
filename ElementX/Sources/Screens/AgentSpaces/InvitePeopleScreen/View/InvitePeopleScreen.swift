//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: invite links (Brief 0073 / ADR-0008).
//

import Compound
import SwiftUI

/// «Invite people»: the personal link, the seats left, a new link when
/// they are gone, and who came through it. Reached from Settings and
/// from Start chat.
struct InvitePeopleScreen: View {
    @Bindable var context: InvitePeopleScreenViewModel.Context
    
    var body: some View {
        Form {
            linkSection
            
            if let invite = context.viewState.invite {
                seatsSection(invite)
            }
            
            if !context.viewState.joined.isEmpty {
                joinedSection
            }
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenInvitePeopleTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
    }
    
    /// The two actions on the link, the link itself in the footer — the
    /// shape every action list in Settings has.
    private var linkSection: some View {
        Section {
            if let shareText = context.viewState.shareText {
                ListRow(kind: .custom {
                    ShareLink(item: shareText) {
                        ListRowLabel.action(title: L10n.actionShareLink, icon: \.shareIos)
                    }
                })
                .accessibilityIdentifier(A11yIdentifiers.invitePeopleScreen.share)
                
                ListRow(label: .action(title: L10n.actionCopyLink, icon: \.copy),
                        kind: .button { context.send(viewAction: .copyLink) })
                    .accessibilityIdentifier(A11yIdentifiers.invitePeopleScreen.copy)
            } else {
                ListRow(label: .plain(title: UntranslatedL10n.screenInvitePeopleTitle),
                        details: .isWaiting(context.viewState.isLoading),
                        kind: .label)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if let invite = context.viewState.invite {
                    Text(invite.link.webURL.absoluteString)
                        .accessibilityIdentifier(A11yIdentifiers.invitePeopleScreen.link)
                }
                Text(UntranslatedL10n.screenInvitePeopleBody)
            }
            .compoundListSectionFooter()
        }
    }
    
    private func seatsSection(_ invite: MyInvite) -> some View {
        Section {
            ListRow(label: .plain(title: UntranslatedL10n.screenInvitePeopleSeatsLabel),
                    details: .title(UntranslatedL10n.screenInvitePeopleSeatsValue(invite.seatsLeft, invite.maxUses)),
                    kind: .label)
                .accessibilityIdentifier(A11yIdentifiers.invitePeopleScreen.seats) // AGENT-PLATFORM (decision 148)
        } footer: {
            Text(invite.isExhausted
                ? UntranslatedL10n.screenInvitePeopleExhausted(invite.maxUses)
                : UntranslatedL10n.screenInvitePeopleSeatsFooter(invite.maxUses))
                .compoundListSectionFooter()
        }
    }
    
    private var joinedSection: some View {
        Section {
            ForEach(context.viewState.joined, id: \.id) { user in
                UserProfileListRow(user: user,
                                   membership: nil,
                                   mediaProvider: context.mediaProvider,
                                   kind: .button { context.send(viewAction: .openUser(user)) })
                    .accessibilityIdentifier(A11yIdentifiers.invitePeopleScreen.joinedUser(user.id)) // AGENT-PLATFORM (decision 148)
            }
        } header: {
            Text(UntranslatedL10n.screenInvitePeopleJoinedTitle)
                .compoundListSectionHeader()
        } footer: {
            Text(UntranslatedL10n.screenInvitePeopleJoinedFooter)
                .compoundListSectionFooter()
        }
    }
}

// MARK: - Previews

struct InvitePeopleScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel(used: 2)
    static let exhaustedViewModel = makeViewModel(used: 10)
    
    static var previews: some View {
        // Wait until the names landed — the MXIDs alone show first.
        ElementNavigationStack {
            InvitePeopleScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.joined).map { $0.count == 2 && $0.allSatisfy { $0.displayName != nil } })
        .previewDisplayName("Seats left")
        ElementNavigationStack {
            InvitePeopleScreen(context: exhaustedViewModel.context)
        }
        .snapshotPreferences(expect: exhaustedViewModel.context.observe(\.viewState.joined).map { $0.count == 2 && $0.allSatisfy { $0.displayName != nil } })
        .previewDisplayName("Exhausted")
    }
    
    static func makeViewModel(used: Int) -> InvitePeopleScreenViewModel {
        let service = AgentPlatformServiceMock()
        service.fetchMyInviteReturnValue = .success(MyInvite(link: SpiralInviteLink(token: "Qz8Hf72Kd91")!,
                                                             maxUses: 10, used: used, expiresAt: nil))
        service.fetchMyInviteJoinedReturnValue = .success([InviteJoinedEntry(userID: "@alice:spiral.md", joinedAt: .now),
                                                           InviteJoinedEntry(userID: "@bob:spiral.md", joinedAt: .now)])
        let clientProxy = ClientProxyMock(.init(userID: "@emmm:spiral.md"))
        clientProxy.profileForClosure = { userID in .success(UserProfile(userID: userID, displayName: String(userID.dropFirst().prefix(while: { $0 != ":" })).capitalized)) }
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        userSession.agentPlatformService = service
        return InvitePeopleScreenViewModel(userSession: userSession, userIndicatorController: UserIndicatorControllerMock())
    }
}
