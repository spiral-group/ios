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
import SpiralComponents
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
            } else if context.viewState.isLoadingInvite {
                seatsLoadingSection
            }
            
            if !context.viewState.joined.isEmpty || context.viewState.joinedPlaceholderCount > 0 {
                joinedSection
            }
        }
        .spiralGroupedList() // AGENT-PLATFORM (Brief 0083): Spiral's grouped list, was `compoundList()`.
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
            } else if context.viewState.isLoadingInvite {
                // Brief 0083, question 359: the same two rows, which act once there is a link.
                ListRow(kind: .custom {
                    ListRowLabel.action(title: L10n.actionShareLink, icon: \.shareIos)
                })
                ListRow(kind: .custom {
                    ListRowLabel.action(title: L10n.actionCopyLink, icon: \.copy)
                })
            } else {
                ListRow(label: .plain(title: UntranslatedL10n.screenInvitePeopleTitle), kind: .label)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if let invite = context.viewState.invite {
                    Text(invite.link.webURL.absoluteString)
                        .accessibilityLabel(UntranslatedL10n.screenInvitePeopleTitle)
                        .accessibilityValue(invite.link.webURL.absoluteString)
                        .accessibilityIdentifier(A11yIdentifiers.invitePeopleScreen.link)
                } else if context.viewState.isLoadingInvite {
                    Text(verbatim: String(repeating: "0", count: 34))
                        .spiralLoadingSlot(true, label: L10n.commonLoading)
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
    
    /// The same section, with the numbers standing in their places. They are never shown.
    private var seatsLoadingSection: some View {
        Section {
            ListRow(label: .plain(title: UntranslatedL10n.screenInvitePeopleSeatsLabel),
                    details: .icon(Text(UntranslatedL10n.screenInvitePeopleSeatsValue(10, 10))
                        .spiralLoadingSlot(true, label: L10n.commonLoading)),
                    kind: .label)
        } footer: {
            Text(UntranslatedL10n.screenInvitePeopleSeatsFooter(10))
                .compoundListSectionFooter()
                .spiralLoadingSlot(true, label: L10n.commonLoading)
        }
    }
    
    private var joinedSection: some View {
        Section {
            // Their own row, with stand-in text: the link says how many.
            ForEach(0..<context.viewState.joinedPlaceholderCount, id: \.self) { _ in
                ListRow(kind: .custom {
                    SpiralPreloader(label: L10n.commonLoading) {
                        ListRowLabel.avatar(title: String(repeating: "0", count: 12),
                                            description: String(repeating: "0", count: 18),
                                            icon: LoadableAvatarImage(url: nil,
                                                                      name: nil,
                                                                      contentID: "",
                                                                      avatarSize: .user(on: .startChat),
                                                                      mediaProvider: context.mediaProvider))
                    }
                })
            }
            
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

// AGENT-PLATFORM (Brief 0083, lane settings): gated.
struct InvitePeopleScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = makeViewModel(used: 2)
    static let exhaustedViewModel = makeViewModel(used: 10)
    // Brief 0083, question 359
    static let loadingViewModel = makeViewModel(used: 2, invite: .neverAnswers)
    static let joinedLoadingViewModel = makeViewModel(used: 2, joined: .neverAnswers)
    
    /// How a read behaves in a preview.
    enum Read {
        case answers, neverAnswers
    }
    
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
        ElementNavigationStack {
            InvitePeopleScreen(context: loadingViewModel.context)
        }
        .environment(\.spiralPreloaderDelay, .zero)
        .previewDisplayName("Loading")
        ElementNavigationStack {
            InvitePeopleScreen(context: joinedLoadingViewModel.context)
        }
        .environment(\.spiralPreloaderDelay, .zero)
        .snapshotPreferences(expect: joinedLoadingViewModel.context.observe(\.viewState.invite).map { $0 != nil })
        .previewDisplayName("Who joined loading")
    }
    
    static func makeViewModel(used: Int, invite: Read = .answers, joined: Read = .answers) -> InvitePeopleScreenViewModel {
        let service = AgentPlatformServiceMock()
        let myInvite = MyInvite(link: SpiralInviteLink(token: "Qz8Hf72Kd91")!, maxUses: 10, used: used, expiresAt: nil)
        service.fetchMyInviteClosure = {
            await answer(invite, with: myInvite)
        }
        let joinedEntries = [InviteJoinedEntry(userID: "@alice:spiral.md", joinedAt: .now),
                             InviteJoinedEntry(userID: "@bob:spiral.md", joinedAt: .now)]
        service.fetchMyInviteJoinedClosure = {
            await answer(joined, with: joinedEntries)
        }
        let clientProxy = ClientProxyMock(.init(userID: "@emmm:spiral.md"))
        clientProxy.profileForClosure = { userID in .success(UserProfile(userID: userID, displayName: String(userID.dropFirst().prefix(while: { $0 != ":" })).capitalized)) }
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        userSession.agentPlatformService = service
        return InvitePeopleScreenViewModel(userSession: userSession, userIndicatorController: UserIndicatorControllerMock())
    }
    
    private nonisolated static func answer<Value>(_ read: Read, with value: Value) async -> Result<Value, AgentPlatformError> {
        if read == .neverAnswers {
            try? await Task.sleep(for: .seconds(3600))
        }
        return .success(value)
    }
}
