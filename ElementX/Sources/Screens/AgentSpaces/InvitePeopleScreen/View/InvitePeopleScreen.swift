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
import SpiralTokens
import SwiftUI

/// «Invite to Spiral» as a chain (1.0.3, concept C, operator 2026-11-21): who invited the caller, the caller, and the
/// link's seats — who came through it and the free ones. The link and its share sit at the bottom, under the thumb.
/// Reached from Settings and from Start chat.
struct InvitePeopleScreen: View {
    @Bindable var context: InvitePeopleScreenViewModel.Context
    
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// A seat's disc, grown with the text as the avatars in it grow.
    @ScaledMetric private var seatSize = Self.seatBaseSize
    
    private var state: InvitePeopleScreenViewState {
        context.viewState
    }
    
    var body: some View {
        Form {
            Section {
                ListRow(kind: .custom { chain })
            } footer: {
                Text(footer)
                    .compoundListSectionFooter()
                    .spiralLoadingSlot(state.isLoadingInvite, label: L10n.commonLoading)
            }
        }
        .spiralGroupedList() // AGENT-PLATFORM (Brief 0083): Spiral's grouped list, was `compoundList()`.
        .navigationTitle(UntranslatedL10n.screenInvitePeopleTitle)
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) { dock }
        .alert(item: $context.alertInfo)
    }
    
    private var footer: String {
        if let invite = state.invite {
            invite.isExhausted
                ? UntranslatedL10n.screenInvitePeopleExhausted(invite.maxUses)
                : UntranslatedL10n.screenInvitePeopleChainFooter(invite.maxUses)
        } else if state.isLoadingInvite {
            UntranslatedL10n.screenInvitePeopleChainFooter(InvitePeopleScreenViewState.seatsWhileLoading)
        } else {
            // The link's read failed: say so above Retry.
            L10n.errorUnknown
        }
    }
    
    // MARK: - The chain
    
    private var chain: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let invitedBy = state.invitedBy {
                inviterNode(invitedBy)
                connector
            }
            ownNode
            if !state.seats.isEmpty {
                connector
                seatsGrid
            }
        }
        .padding(18)
    }
    
    /// The line from one node to the next, under the middle of the caller's avatar.
    private var connector: some View {
        Rectangle()
            .fill(Color.compound.borderDisabled)
            .frame(width: 2, height: 20)
            .padding(.leading, Self.ownAvatarSize / 2 - 1)
            .accessibilityHidden(true)
    }
    
    /// 1.0.3: the other side — whose link the caller registered with; a tap opens their profile, as a seat does.
    private func inviterNode(_ user: UserProfile) -> some View {
        Button { context.send(viewAction: .openUser(user)) } label: {
            HStack(spacing: 12) {
                LoadableAvatarImage(url: user.avatarURL,
                                    name: user.displayName,
                                    contentID: user.id,
                                    avatarSize: .custom(SpiralAvatarSize.small),
                                    mediaProvider: context.mediaProvider)
                    // Its middle on the caller's, so one line joins them.
                    .padding(.leading, (Self.ownAvatarSize - SpiralAvatarSize.small) / 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(user.displayName ?? Self.localpart(user.id))
                        .font(.compound.bodyLGSemibold)
                        .foregroundStyle(.compound.textPrimary)
                        .lineLimit(1)
                    Text(UntranslatedL10n.screenInvitePeopleInvitedYou)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                }
                Spacer(minLength: 0)
                CompoundIcon(\.chevronRight, size: .small, relativeTo: .compound.bodyLG)
                    .foregroundStyle(.compound.iconTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(A11yIdentifiers.invitePeopleScreen.invitedBy)
    }
    
    private var ownNode: some View {
        HStack(spacing: 12) {
            LoadableAvatarImage(url: state.ownProfile.avatarURL,
                                name: state.ownProfile.displayName,
                                contentID: state.ownProfile.id,
                                avatarSize: .custom(Self.ownAvatarSize - 6),
                                mediaProvider: context.mediaProvider)
                .padding(3)
                .overlay { Circle().strokeBorder(Color.compound.iconAccentPrimary, lineWidth: 3) }
            VStack(alignment: .leading, spacing: 1) {
                Text(UntranslatedL10n.screenInvitePeopleYou)
                    .font(.compound.headingSMSemibold)
                    .foregroundStyle(.compound.textPrimary)
                if let invite = state.invite {
                    Text(UntranslatedL10n.screenInvitePeopleInvitedCount(invite.used, invite.maxUses))
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                } else if state.isLoadingInvite {
                    Text(UntranslatedL10n.screenInvitePeopleInvitedCount(0, InvitePeopleScreenViewState.seatsWhileLoading))
                        .font(.compound.bodySM)
                        .spiralLoadingSlot(true, label: L10n.commonLoading)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        // AGENT-PLATFORM (decision 148): «Invited N of M» — only once the link is read, so the E2E walk waits for it.
        .accessibilityIdentifier(state.invite == nil ? "" : A11yIdentifiers.invitePeopleScreen.seats)
    }
    
    private var seatsGrid: some View {
        // Five to a row as the board drew it; three at the accessibility sizes, where five discs no longer fit. On a wide
        // screen the row keeps a phone's width instead of spreading the seats apart.
        let columns = dynamicTypeSize.isAccessibilitySize ? 3 : 5
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: columns), spacing: 14) {
            ForEach(state.seats) { seat in
                seatView(seat)
            }
        }
        .frame(maxWidth: Self.seatsMaxWidth, alignment: .leading)
    }
    
    @ViewBuilder
    private func seatView(_ seat: InviteSeat) -> some View {
        switch seat {
        case .joined(let user):
            Button { context.send(viewAction: .openUser(user)) } label: {
                seatCell(name: user.displayName.map(Self.firstName) ?? Self.localpart(user.id)) {
                    LoadableAvatarImage(url: user.avatarURL,
                                        name: user.displayName,
                                        contentID: user.id,
                                        avatarSize: .custom(Self.seatBaseSize),
                                        mediaProvider: context.mediaProvider)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(user.displayName ?? user.id)
            .accessibilityIdentifier(A11yIdentifiers.invitePeopleScreen.joinedUser(user.id)) // AGENT-PLATFORM (decision 148)
        case .loading:
            SpiralPreloader(label: L10n.commonLoading) {
                seatCell(name: String(repeating: "0", count: 6)) {
                    Circle().fill(Color.compound.bgSubtleSecondary)
                }
            }
        case .taken:
            seatCell(name: UntranslatedL10n.screenInvitePeopleSeatTaken, nameStyle: .compound.textSecondary) {
                Circle()
                    .fill(Color.compound.bgSubtleSecondary)
                    .overlay { CompoundIcon(\.user, size: .small, relativeTo: .compound.bodyMD).foregroundStyle(.compound.iconSecondary) }
            }
            .accessibilityElement(children: .combine)
        case .invite:
            shareLink {
                seatCell(name: UntranslatedL10n.screenInvitePeopleSeatInvite, nameStyle: .compound.textActionAccent, isBold: true) {
                    Circle()
                        .fill(Color.compound.bgBadgeAccent)
                        .overlay { CompoundIcon(\.plus, size: .medium, relativeTo: .compound.bodyLG).foregroundStyle(.compound.iconAccentPrimary) }
                }
            }
        case .free:
            shareLink {
                seatCell(name: nil) {
                    Circle()
                        .strokeBorder(Color.compound.borderDisabled, lineWidth: 1.5)
                        .overlay { CompoundIcon(\.plus, size: .small, relativeTo: .compound.bodyMD).foregroundStyle(.compound.iconTertiary) }
                }
            }
            // One way to invite is enough for VoiceOver: the first free seat.
            .accessibilityHidden(true)
        }
    }
    
    private func seatCell(name: String?,
                          nameStyle: Color = .compound.textPrimary,
                          isBold: Bool = false,
                          @ViewBuilder disc: () -> some View) -> some View {
        VStack(spacing: 6) {
            disc()
                .frame(width: seatSize, height: seatSize)
            Text(name ?? " ")
                .font(isBold ? .compound.bodyXSSemibold : .compound.bodyXS)
                .foregroundStyle(nameStyle)
                .lineLimit(1)
                // AGENT-PLATFORM (1.0.3): a seat's column is ~60 pt, and «Запросити»
                // under the invite seat read «Запрос…» (operator, 2026-11-24, option 1:
                // shrink only where the word doesn't fit; words that fit keep their size).
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private func shareLink(@ViewBuilder label: () -> some View) -> some View {
        if let shareText = state.shareText {
            ShareLink(item: shareText, label: label)
                .buttonStyle(.plain)
        } else {
            label()
        }
    }
    
    // MARK: - The dock
    
    @ViewBuilder
    private var dock: some View {
        Group {
            if state.invite != nil || state.isLoadingInvite {
                VStack(spacing: 10) {
                    if let invite = state.invite, !invite.isExhausted, !dynamicTypeSize.isAccessibilitySize {
                        Image(asset: Asset.Images.sparkPoint)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 84, height: 84)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                    linkCapsule
                    shareButton
                }
            } else {
                // The link's read failed and its alert was dismissed: the way back stays on the page.
                Button(L10n.actionRetry) { context.send(viewAction: .retry) }
                    .buttonStyle(.compound(.primary))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        // The chain scrolls under the dock, not through it.
        .background(Color.compound.bgSubtleSecondaryLevel0)
    }
    
    private var linkCapsule: some View {
        let isUsable = !(state.invite?.isExhausted ?? true)
        return HStack(spacing: 8) {
            CompoundIcon(\.link, size: .small, relativeTo: .compound.bodyMD)
                .foregroundStyle(.compound.iconSecondary)
            if let invite = state.invite {
                Text(Self.shortLink(invite.link.webURL))
                    .font(.compound.bodyMD.monospaced())
                    .foregroundStyle(isUsable ? .compound.textPrimary : .compound.textDisabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel(invite.link.webURL.absoluteString)
                    .accessibilityIdentifier(A11yIdentifiers.invitePeopleScreen.link)
            } else {
                Text(verbatim: String(repeating: "0", count: 26))
                    .font(.compound.bodyMD.monospaced())
                    .spiralLoadingSlot(true, label: L10n.commonLoading)
            }
            Spacer(minLength: 0)
            Button { context.send(viewAction: .copyLink) } label: {
                CompoundIcon(\.copy, size: .small, relativeTo: .compound.bodyMD)
                    .foregroundStyle(isUsable ? .compound.iconAccentPrimary : .compound.iconDisabled)
                    .frame(width: 36, height: 36)
                    .background(Color.compound.bgSubtleSecondary, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isUsable)
            .accessibilityLabel(L10n.actionCopyLink)
            .accessibilityIdentifier(A11yIdentifiers.invitePeopleScreen.copy)
        }
        .padding(.leading, 16)
        .padding(.trailing, 5)
        .frame(minHeight: 46)
        .background(Color.compound.bgSubtlePrimary, in: Capsule())
    }
    
    @ViewBuilder
    private var shareButton: some View {
        if let invite = state.invite, invite.isExhausted {
            Button(UntranslatedL10n.screenInvitePeopleAllUsed) { }
                .buttonStyle(.compound(.primary))
                .disabled(true)
        } else if let shareText = state.shareText {
            ShareLink(item: shareText) {
                Label(L10n.actionShareLink, icon: \.shareIos)
            }
            .buttonStyle(.compound(.primary))
            .accessibilityIdentifier(A11yIdentifiers.invitePeopleScreen.share)
        } else {
            Button(L10n.actionShareLink) { }
                .buttonStyle(.compound(.primary))
                .disabled(true)
        }
    }
    
    // MARK: - Helpers
    
    private static let ownAvatarSize = SpiralAvatarSize.medium
    private static let seatBaseSize: CGFloat = 48
    private static let seatsMaxWidth: CGFloat = 360
    
    /// `@alice:spiral.md` → `alice`, for a person whose name hasn't landed.
    private static func localpart(_ userID: String) -> String {
        String(userID.dropFirst().prefix { $0 != ":" })
    }
    
    private static func firstName(_ displayName: String) -> String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }
    
    /// The link without its scheme, as people say it.
    private static func shortLink(_ url: URL) -> String {
        url.absoluteString.replacingOccurrences(of: "https://", with: "")
    }
}

// MARK: - Previews

// AGENT-PLATFORM (Brief 0083, lane settings): gated.
struct InvitePeopleScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = makeViewModel(used: 3, joined: 2)
    static let exhaustedViewModel = makeViewModel(used: 10, joined: 10)
    static let nobodyYetViewModel = makeViewModel(used: 0, joined: 0)
    static let noInviterViewModel = makeViewModel(used: 2, joined: 2, invitedBy: false)
    // Brief 0083, question 359
    static let loadingViewModel = makeViewModel(used: 2, joined: 2, inviteRead: .neverAnswers)
    static let joinedLoadingViewModel = makeViewModel(used: 2, joined: 2, joinedRead: .neverAnswers)
    static let failedViewModel = makeViewModel(used: 2, joined: 2, inviteRead: .fails)
    
    /// How a read behaves in a preview.
    enum Read {
        case answers, neverAnswers, fails
    }
    
    static let names = ["alice", "bohdan", "daryna", "ihor", "kateryna", "lev", "nina", "roman", "sofia", "viktor"]
    
    static var previews: some View {
        // Wait until the names landed — the MXIDs alone show first.
        preview(viewModel, joined: 2, "Seats left")
        preview(exhaustedViewModel, joined: 10, "Exhausted")
        preview(nobodyYetViewModel, joined: 0, "Nobody yet")
        preview(noInviterViewModel, joined: 2, invitedBy: false, "Nobody invited you")
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
        ElementNavigationStack {
            InvitePeopleScreen(context: failedViewModel.context)
        }
        .snapshotPreferences(expect: failedViewModel.context.observe(\.viewState).map { !$0.isLoading && $0.invitedBy?.displayName != nil })
        .previewDisplayName("Failed")
    }
    
    static func preview(_ model: InvitePeopleScreenViewModel, joined: Int, invitedBy: Bool = true, _ name: String) -> some View {
        ElementNavigationStack {
            InvitePeopleScreen(context: model.context)
        }
        .snapshotPreferences(expect: model.context.observe(\.viewState).map { state in
            state.invite != nil && state.ownProfile.displayName != nil
                && state.joined.count == joined && state.joined.allSatisfy { $0.displayName != nil }
                && (state.invitedBy?.displayName != nil) == invitedBy
        })
        .previewDisplayName(name)
    }
    
    static func makeViewModel(used: Int, joined: Int, invitedBy: Bool = true,
                              inviteRead: Read = .answers, joinedRead: Read = .answers) -> InvitePeopleScreenViewModel {
        let service = AgentPlatformServiceMock()
        let myInvite = MyInvite(link: SpiralInviteLink(token: "Qz8Hf72Kd91")!, maxUses: 10, used: used, expiresAt: nil)
        service.fetchMyInviteClosure = {
            await answer(inviteRead, with: myInvite)
        }
        let joinedEntries = names.prefix(joined).map { InviteJoinedEntry(userID: "@\($0):spiral.md", joinedAt: .now) }
        service.fetchMyInviteJoinedClosure = {
            await answer(joinedRead, with: Array(joinedEntries))
        }
        service.fetchInvitedByReturnValue = .success(invitedBy ? InvitedBy(inviterUserID: "@maria:spiral.md", isWelcomeOwed: false) : nil)
        let clientProxy = ClientProxyMock(.init(userID: "@oleksandr:spiral.md"))
        clientProxy.profileForClosure = { userID in .success(UserProfile(userID: userID, displayName: String(userID.dropFirst().prefix(while: { $0 != ":" })).capitalized)) }
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        userSession.agentPlatformService = service
        return InvitePeopleScreenViewModel(userSession: userSession, userIndicatorController: UserIndicatorControllerMock())
    }
    
    private nonisolated static func answer<Value>(_ read: Read, with value: Value) async -> Result<Value, AgentPlatformError> {
        switch read {
        case .answers: break
        case .neverAnswers: try? await Task.sleep(for: .seconds(3600))
        case .fails: return .failure(.serverError(status: 500))
        }
        return .success(value)
    }
}
