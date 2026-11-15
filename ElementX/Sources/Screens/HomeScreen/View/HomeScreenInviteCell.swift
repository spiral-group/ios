//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import MatrixRustSDKMocks
import SpiralTokens // AGENT-PLATFORM (Brief 0083)
import SwiftUI

struct HomeScreenInviteCell: View {
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var nameLineHeight = 22.0 // AGENT-PLATFORM (Brief 0083)
    
    let room: HomeScreenRoom
    let context: HomeScreenViewModel.Context
    let hideInviteAvatars: Bool
    
    private var avatar: RoomAvatar {
        // DM invites avatars are broken, this is a workaround
        // https://github.com/matrix-org/matrix-rust-sdk/issues/4825
        if room.isDirect, let inviter = room.inviter {
            .heroes([.init(userID: inviter.id, displayName: inviter.displayName, avatarURL: hideInviteAvatars ? nil : inviter.avatarURL)])
        } else {
            hideInviteAvatars ? room.avatar.removingAvatar : room.avatar
        }
    }
    
    var body: some View {
        // AGENT-PLATFORM (Brief 0083): a Chats row's columns. An unseen invite's dot leads, centred on the avatar
        // (on the name's first line when the avatar is hidden), where it was a badge after the name.
        HStack(alignment: .top, spacing: 0) {
            HomeScreenRoomUnreadMarker(isShown: room.badges.isDotShown, isHighlighted: true)
                .frame(height: isAvatarShown ? SpiralAvatarSize.medium : nameLineHeight)
                .accessibilityHidden(true) // As upstream's badge: the invite's buttons say what's new.
            
            if isAvatarShown {
                RoomAvatarImage(avatar: avatar,
                                avatarSize: .custom(SpiralAvatarSize.medium), // AGENT-PLATFORM (Brief 0083, decision 300b)
                                mediaProvider: context.mediaProvider)
                    .dynamicTypeSize(dynamicTypeSize < .accessibility1 ? dynamicTypeSize : .accessibility1)
                    .accessibilityHidden(true)
                    .padding(.trailing, CompoundDesignTokens.space3X)
            }
            
            mainContent
                // AGENT-PLATFORM (bug S6): the row takes its own height. Chats' lazy list measures it unbounded, then
                // places it at a concrete height; offered a hair less, the buttons switched to their stacked layout and
                // the row drew 60 pt taller than its slot: a gap above the name, the buttons under the next row.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 16)
                .padding(.trailing, 16)
                .multilineTextAlignment(.leading)
                .overlay(alignment: .bottom) {
                    separator
                }
        }
        .padding(.top, 12)
        .onTapGesture {
            if let roomID = room.roomID {
                context.send(viewAction: .selectRoom(roomIdentifier: roomID))
            }
        }
        .accessibilityIdentifier(A11yIdentifiers.homeScreen.roomName(room.name))
    }
    
    // MARK: - Private
    
    private var isAvatarShown: Bool {
        dynamicTypeSize < .accessibility3
    }
    
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                textualContent // AGENT-PLATFORM (Brief 0083): the dot leads the row now.
                
                inviterView
                    .padding(.top, 6)
                    .padding(.trailing, 16)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            
            ViewThatFits {
                HStack(spacing: 12) { buttons }
                VStack(spacing: 16) { Group(subviews: buttons) { ForEach($0.reversed()) { $0 } } }
            }
            .padding(.trailing, 22)
        }
    }
    
    @ViewBuilder
    private var inviterView: some View {
        if let inviter = room.inviter,
           !room.isDirect {
            RoomInviterLabel(inviter: inviter,
                             shouldHideAvatar: hideInviteAvatars,
                             mediaProvider: context.mediaProvider)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textSecondary)
        }
    }
    
    private var textualContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.compound.bodyLGSemibold)
                .foregroundColor(.compound.textPrimary)
                .lineLimit(2)
            
            if let subtitle {
                Text(subtitle)
                    .font(.compound.bodyMD)
                    .foregroundColor(.compound.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private var buttons: some View {
        Button {
            context.send(viewAction: .declineInvite(roomIdentifier: room.id))
        } label: {
            Text(L10n.actionDecline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.compound(.secondary, size: .medium))
        
        Button {
            context.send(viewAction: .acceptInvite(roomIdentifier: room.id))
        } label: {
            Text(L10n.actionAccept)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.compound(.primary, size: .medium))
    }
    
    private var separator: some View {
        Rectangle()
            .fill(Color.compound.borderDisabled)
            .frame(height: 1 / UIScreen.main.scale)
    }
    
    private var title: String {
        room.name
    }
    
    private var subtitle: String? {
        room.isDirect ? room.inviter?.id : nil
    }
}

// MARK: - Previews

struct HomeScreenInviteCell_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        VStack(spacing: 0) {
            HomeScreenInviteCell(room: .dmInvite,
                                 context: makeViewModel().context,
                                 hideInviteAvatars: false)
            
            HomeScreenInviteCell(room: .invite(),
                                 context: makeViewModel().context,
                                 hideInviteAvatars: false)
            
            HomeScreenInviteCell(room: .invite(alias: "#footest:somewhere.org",
                                               avatarURL: .mockMXCAvatar),
                                 context: makeViewModel().context,
                                 hideInviteAvatars: false)
            
            // Not the final design, may get its own cell type entirely.
            HomeScreenInviteCell(room: .invite(name: "Awesome Space",
                                               isSpace: true,
                                               alias: "#footest:somewhere.org",
                                               avatarURL: .mockMXCAvatar),
                                 context: makeViewModel().context,
                                 hideInviteAvatars: false)
            
            HomeScreenInviteCell(room: .invite(name: "Hidden Avatars",
                                               avatarURL: .mockMXCAvatar),
                                 context: makeViewModel().context,
                                 hideInviteAvatars: true)
            
            HomeScreenInviteCell(room: .invite(alias: "#footest:somewhere.org"),
                                 context: makeViewModel().context,
                                 hideInviteAvatars: false)
                .dynamicTypeSize(.accessibility1)
                .previewDisplayName("Aliased room (AX1)")
        }
        .previewLayout(.sizeThatFits)
    }
    
    static func makeViewModel() -> HomeScreenViewModel {
        let clientProxy = ClientProxyMock(.init())
        
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        
        return HomeScreenViewModel(userSession: userSession,
                                   availableSessionsPublisher: .init([.init(userSession: userSession)]),
                                   selectedRoomPublisher: CurrentValueSubject<String?, Never>(nil).asCurrentValuePublisher(),
                                   analyticsService: AnalyticsServiceMock(.init()),
                                   bugReportService: BugReportServiceMock(.init()),
                                   userIndicatorController: UserIndicatorControllerMock())
    }
}

private extension HomeScreenRoom {
    static var dmInvite: HomeScreenRoom {
        let inviter = RoomMemberProxyMock()
        inviter.displayName = "Some Guy"
        inviter.userID = "@someone:somewhere.com"
        
        let summary = RoomSummary(room: RoomSDKMock(),
                                  id: "@someone:somewhere.com",
                                  joinRequestType: .invite(inviter: inviter),
                                  isJoined: false,
                                  name: "Some Guy",
                                  isDirect: true,
                                  isSpace: false,
                                  avatarURL: nil,
                                  heroes: [.init(userID: "@someone:somewhere.com")],
                                  activeMembersCount: 0,
                                  lastMessage: nil,
                                  lastMessageDate: nil,
                                  lastMessageState: nil,
                                  unreadMessagesCount: 0,
                                  unreadMentionsCount: 0,
                                  unreadNotificationsCount: 0,
                                  notificationMode: nil,
                                  canonicalAlias: "#footest:somewhere.org",
                                  alternativeAliases: [],
                                  hasOngoingCall: false,
                                  activeCallIntent: nil,
                                  isMarkedUnread: false,
                                  isFavourite: false,
                                  isTombstoned: false)
        
        return .init(summary: summary)
    }
    
    static func invite(name: String = "Awesome Room",
                       isSpace: Bool = false,
                       alias: String? = nil,
                       avatarURL: URL? = nil) -> HomeScreenRoom {
        let inviter = RoomMemberProxyMock()
        inviter.displayName = "Luca"
        inviter.userID = "@jack:somewhi.nl"
        inviter.avatarURL = avatarURL.map { _ in .mockMXCUserAvatar }
        
        let summary = RoomSummary(room: RoomSDKMock(),
                                  id: "@someone:somewhere.com",
                                  joinRequestType: .invite(inviter: inviter),
                                  isJoined: false,
                                  name: name,
                                  isDirect: false,
                                  isSpace: isSpace,
                                  avatarURL: avatarURL,
                                  heroes: [.init(userID: "@someone:somewhere.com")],
                                  activeMembersCount: 0,
                                  lastMessage: nil,
                                  lastMessageDate: nil,
                                  lastMessageState: nil,
                                  unreadMessagesCount: 0,
                                  unreadMentionsCount: 0,
                                  unreadNotificationsCount: 0,
                                  notificationMode: nil,
                                  canonicalAlias: alias,
                                  alternativeAliases: [],
                                  hasOngoingCall: false,
                                  activeCallIntent: nil,
                                  isMarkedUnread: false,
                                  isFavourite: false,
                                  isTombstoned: false)
        
        return .init(summary: summary)
    }
}
