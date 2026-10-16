//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct RoomMembersListScreenMemberCell: View {
    let listEntry: RoomMemberListScreenEntry
    let isLast: Bool
    let context: RoomMembersListScreenViewModel.Context
    // AGENT-PLATFORM (Brief 0072, ADR-0083): nil when unknown or not asked for.
    var presence: UserPresence?
    
    var body: some View {
        Button {
            context.send(viewAction: .selectMember(listEntry.member))
        } label: {
            HStack(spacing: 16) {
                LoadableAvatarImage(url: avatarURL,
                                    name: avatarName,
                                    contentID: listEntry.member.id,
                                    avatarSize: .user(on: .roomMembersList),
                                    mediaProvider: context.mediaProvider)
                    // AGENT-PLATFORM (Brief 0072, ADR-0083): the status line says it to VoiceOver.
                    .presenceBadge(isOnline: presence?.isOnline ?? false,
                                   avatarSize: Avatars.Size.user(on: .roomMembersList).value,
                                   ringColor: .compound.bgCanvasDefaultLevel1,
                                   announced: false)
                    .accessibilityHidden(true)
                
                HStack(alignment: .center, spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(title)
                                .lineLimit(1)
                            
                            if let statusEmoji {
                                Text(String(statusEmoji))
                            }
                        }
                        .font(.compound.bodyLG)
                        .foregroundColor(.compound.textPrimary)
                        
                        subtitleLine
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VerificationBadge(verificationState: listEntry.verificationState)
                    
                    if let role {
                        Text(role)
                            .font(.compound.bodyLG)
                            .foregroundStyle(.compound.textSecondary)
                    }
                    
                    if listEntry.isActiveRoomCallParticipant {
                        CompoundIcon(\.videoCallSolid, size: .small, relativeTo: .compound.bodyLG)
                            .foregroundStyle(.compound.iconAccentPrimary)
                            .accessibilityLabel(L10n.commonOnACall)
                    }
                }
                .overlay(alignment: .bottom) {
                    if !isLast {
                        ListRowColor.separatorTint
                            .frame(height: 1)
                            .offset(x: 0, y: ListRowPadding.vertical)
                    }
                }
            }
            .padding(ListRowPadding.insets)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
    
    // AGENT-PLATFORM (Brief 0072, ADR-0083): as Telegram has it, the line
    // under a member is their presence; the user ID when there is none
    // (agents, bridges, not asked for yet). The minutes move on their own.
    @ViewBuilder
    private var subtitleLine: some View {
        if let presence, !listEntry.member.isBanned {
            SwiftUI.TimelineView(.everyMinute) { timeline in
                if let status = presence.statusText(now: timeline.date) {
                    subtitleText(status, isOnline: presence.isOnline)
                } else if let subtitle {
                    subtitleText(subtitle, isOnline: false)
                }
            }
        } else if let subtitle {
            subtitleText(subtitle, isOnline: false)
        }
    }
    
    private func subtitleText(_ text: String, isOnline: Bool) -> some View {
        Text(text)
            .font(.compound.bodySM)
            .foregroundColor(isOnline ? .compound.textActionAccent : .compound.textSecondary)
            .lineLimit(1)
    }
    
    var role: String? {
        switch listEntry.member.role {
        case .creator, .owner:
            L10n.screenRoomMemberListRoleOwner
        case .administrator:
            L10n.screenRoomMemberListRoleAdministrator
        case .moderator:
            L10n.screenRoomMemberListRoleModerator
        case .user:
            nil
        }
    }
    
    // Computed properties to hide the user's profile when banned.
    
    var title: String {
        guard !listEntry.member.isBanned else { return listEntry.member.id }
        return listEntry.member.name ?? listEntry.member.id
    }
    
    var statusEmoji: Character? {
        listEntry.member.isBanned ? nil : listEntry.member.status.displayed?.emoji
    }
    
    var subtitle: String? {
        listEntry.member.isBanned ? nil : listEntry.member.id
    }
    
    var avatarName: String? {
        listEntry.member.isBanned ? nil : listEntry.member.name
    }
    
    var avatarURL: URL? {
        listEntry.member.isBanned ? nil : listEntry.member.avatarURL
    }
}

struct RoomMembersListMemberCell_Previews: PreviewProvider, TestablePreview {
    static let members: [RoomMemberListScreenEntry] = [
        .init(member: .init(withProxy: RoomMemberProxyMock.mockAlice),
              verificationState: .notVerified),
        .init(member: .init(withProxy: RoomMemberProxyMock.mockErin),
              verificationState: .notVerified),
        .init(member: .init(withProxy: RoomMemberProxyMock.mockAdmin),
              verificationState: .verified),
        .init(member: .init(withProxy: RoomMemberProxyMock.mockModerator),
              verificationState: .verificationViolation),
        .init(member: .init(withProxy: RoomMemberProxyMock.mockFrank),
              verificationState: .notVerified,
              isActiveRoomCallParticipant: true),
        .init(member: .init(withProxy: RoomMemberProxyMock(with: .init(userID: "@nodisplayname:matrix.org",
                                                                       membership: .join))),
        verificationState: .notVerified),
        .init(member: .init(withProxy: RoomMemberProxyMock(with: .init(userID: "@avatar:matrix.org",
                                                                       displayName: "Avatar",
                                                                       avatarURL: .mockMXCUserAvatar,
                                                                       membership: .join))),
        verificationState: .notVerified)
    ]
    
    static let bannedMembers: [RoomMemberListScreenEntry] = [
        .init(member: .init(withProxy: RoomMemberProxyMock(with: .init(userID: "@nodisplayname:matrix.org",
                                                                       membership: .ban))),
        verificationState: .notVerified),
        .init(member: .init(withProxy: RoomMemberProxyMock(with: .init(userID: "@fake:matrix.org",
                                                                       displayName: "President",
                                                                       membership: .ban))),
        verificationState: .verified),
        .init(member: .init(withProxy: RoomMemberProxyMock(with: .init(userID: "@badavatar:matrix.org",
                                                                       avatarURL: .mockMXCUserAvatar,
                                                                       membership: .ban))),
        verificationState: .verificationViolation)
    ]
    
    static let viewModel = RoomMembersListScreenViewModel(userSession: UserSessionMock(.init()),
                                                          roomProxy: JoinedRoomProxyMock(.init(name: "Some room", members: [])),
                                                          userIndicatorController: UserIndicatorControllerMock(),
                                                          analytics: AnalyticsServiceMock(.init()))
    static var previews: some View {
        VStack(spacing: 0) {
            Section("Invited/Joined") {
                ForEach(members, id: \.member.id) { entry in
                    RoomMembersListScreenMemberCell(listEntry: entry, isLast: members.last == entry, context: viewModel.context)
                }
            }
            
            // Banned members should have their profiles hidden and the avatar should use the first letter from their user ID.
            Section("Banned") {
                ForEach(bannedMembers, id: \.member.id) { entry in
                    RoomMembersListScreenMemberCell(listEntry: entry, isLast: bannedMembers.last == entry, context: viewModel.context)
                }
            }
        }
        
        // AGENT-PLATFORM (Brief 0072, ADR-0083, ADR-0084): online, last seen
        // exactly, last seen coarsely, and no presence (the user ID stays).
        // Only texts that do not depend on the clock the snapshot runs at.
        VStack(spacing: 0) {
            ForEach(presenceMembers, id: \.member.id) { entry in
                RoomMembersListScreenMemberCell(listEntry: entry,
                                                isLast: presenceMembers.last == entry,
                                                context: viewModel.context,
                                                presence: presences[entry.member.id])
            }
        }
        .previewDisplayName("Presence")
    }
    
    static let presenceMembers: [RoomMemberListScreenEntry] = [
        .init(member: .init(withProxy: RoomMemberProxyMock.mockAlice), verificationState: .notVerified),
        .init(member: .init(withProxy: RoomMemberProxyMock.mockBob), verificationState: .notVerified),
        .init(member: .init(withProxy: RoomMemberProxyMock.mockAdmin), verificationState: .verified),
        .init(member: .init(withProxy: RoomMemberProxyMock.mockCharlie), verificationState: .notVerified)
    ]
    
    static let presences: [String: UserPresence] = [
        RoomMemberProxyMock.mockAlice.userID: .init(userID: RoomMemberProxyMock.mockAlice.userID, state: .online,
                                                    lastActiveAgo: 2, currentlyActive: true, receivedAt: .now),
        RoomMemberProxyMock.mockBob.userID: .init(userID: RoomMemberProxyMock.mockBob.userID, state: .unavailable,
                                                  lastActiveAgo: 10, currentlyActive: false, receivedAt: .now),
        RoomMemberProxyMock.mockAdmin.userID: .init(userID: RoomMemberProxyMock.mockAdmin.userID, state: .offline,
                                                    lastActiveAgo: nil, currentlyActive: false,
                                                    lastSeenBucket: .withinWeek, receivedAt: .now)
    ]
}
