//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine // AGENT-PLATFORM (Brief 0083): the preview below.
import MatrixRustSDKMocks // AGENT-PLATFORM (Brief 0083): the preview below.
import SwiftUI

struct HomeScreenRoomList: View {
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    
    @ObservedObject var context: HomeScreenViewModel.Context
    
    var body: some View {
        // Hide the room list when the search bar is focused but the query is empty
        // This works hand in hand with the room list service layer filtering and
        // avoids glitches when focusing the search bar
        if !context.viewState.shouldHideRoomList {
            content
        }
    }
    
    private var content: some View {
        ForEach(context.viewState.visibleRooms) { room in
            switch room.type {
            case .placeholder:
                HomeScreenRoomCell(room: room, isSelected: false, mediaProvider: context.mediaProvider, action: context.send)
                    .redacted(reason: .placeholder)
            case .invite:
                HomeScreenInviteCell(room: room, context: context, hideInviteAvatars: context.viewState.hideInviteAvatars)
            case .knock:
                HomeScreenKnockedCell(room: room, context: context)
            case .room:
                let isSelected = context.viewState.selectedRoomID == room.id
                
                HomeScreenRoomCell(room: room,
                                   isSelected: isSelected,
                                   mediaProvider: context.mediaProvider,
                                   action: context.send)
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        context.send(viewAction: .detachRoom(roomIdentifier: room.id))
                    })
                    .contextMenu {
                        if room.badges.isDotShown {
                            Button {
                                context.send(viewAction: .markRoomAsRead(roomIdentifier: room.id))
                            } label: {
                                Label(L10n.screenRoomlistMarkAsRead, icon: \.markAsRead)
                            }
                        } else {
                            Button {
                                context.send(viewAction: .markRoomAsUnread(roomIdentifier: room.id))
                            } label: {
                                Label(L10n.screenRoomlistMarkAsUnread, icon: \.markAsUnread)
                            }
                        }
                        
                        if supportsMultipleWindows {
                            Button {
                                context.send(viewAction: .detachRoom(roomIdentifier: room.id))
                            } label: {
                                Label("Open in new window", icon: \.spotlight)
                            }
                        }
                        
                        if room.isFavourite {
                            Button {
                                context.send(viewAction: .markRoomAsFavourite(roomIdentifier: room.id, isFavourite: false))
                            } label: {
                                Label(L10n.commonFavourited, icon: \.favouriteSolid)
                            }
                        } else {
                            Button {
                                context.send(viewAction: .markRoomAsFavourite(roomIdentifier: room.id, isFavourite: true))
                            } label: {
                                Label(L10n.commonFavourite, icon: \.favourite)
                            }
                        }
                        
                        Button {
                            context.send(viewAction: .showRoomDetails(roomIdentifier: room.id))
                        } label: {
                            Label(L10n.commonSettings, icon: \.settings)
                        }
                        
                        if context.viewState.reportRoomEnabled {
                            Button(role: .destructive) {
                                context.send(viewAction: .reportRoom(roomIdentifier: room.id))
                            } label: {
                                Label(L10n.actionReportRoom, icon: \.chatProblem)
                            }
                        }
                        
                        Button(role: .destructive) {
                            context.send(viewAction: .leaveRoom(roomIdentifier: room.id))
                        } label: {
                            Label(L10n.actionLeaveRoom, icon: \.leave)
                        }
                    }
            }
        }
    }
}

// MARK: - Previews

// AGENT-PLATFORM (Brief 0083): every state a Chats row shows, in one list, so the gates and the
// sheets see them all: unread with a count, a mention, marked unread, quiet unread, muted, ongoing
// calls, presence and a status, sending, failed, upgraded, a favourite, no messages, invites and a knock.
struct HomeScreenRoomList_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = makeViewModel()
    
    static var previews: some View {
        VStack(spacing: 0) {
            HomeScreenRoomList(context: viewModel.context)
        }
        .snapshotPreferences(expect: viewModel.context.$viewState.map { state in
            state.roomListMode == .rooms
        })
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Every state")
    }
    
    static func makeViewModel() -> HomeScreenViewModel {
        let clientProxy = ClientProxyMock(.init(userID: "@alice:example.com",
                                                roomSummaryProvider: RoomSummaryProviderMock(.init(state: .loaded(rooms)))))
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        
        let presence = UserPresence(userID: avaID, state: .online, lastActiveAgo: 2, currentlyActive: true, receivedAt: .now)
        let presenceObserverService = PresenceObserverServiceMock()
        presenceObserverService.underlyingPresencePublisher = CurrentValueSubject([avaID: presence]).asCurrentValuePublisher()
        userSession.presenceObserverService = presenceObserverService
        
        return HomeScreenViewModel(userSession: userSession,
                                   availableSessionsPublisher: .init([.init(userSession: userSession)]),
                                   selectedRoomPublisher: CurrentValueSubject<String?, Never>(nil).asCurrentValuePublisher(),
                                   analyticsService: AnalyticsServiceMock(.init()),
                                   bugReportService: BugReportServiceMock(.init()),
                                   userIndicatorController: UserIndicatorControllerMock())
    }
    
    private static let avaID = "@ava:example.com"
    
    private static var rooms: [RoomSummary] {
        let ava = UserProfile(userID: avaID, displayName: "Ava Thompson", avatarURL: nil)
        let sam = RoomMemberProxyMock(with: .init(userID: "@sam:example.com", displayName: "Sam Rivera", membership: .join))
        
        return [
            summary(id: "!unread", name: "Ava Thompson", isDirect: true, heroes: [ava],
                    lastMessage: "Are we still on for ten? I booked the room by the window.",
                    unreadMessages: 3, unreadNotifications: 3),
            summary(id: "!mention", name: "Design team",
                    lastMessage: "Mila: @alice can you check the new icons before lunch?",
                    unreadMessages: 5, unreadMentions: 1, unreadNotifications: 2),
            summary(id: "!voice", name: "Marcus Webb", isDirect: true, heroes: [.init(userID: "@marcus:example.com", displayName: "Marcus Webb", avatarURL: nil)],
                    lastMessage: "Calling you now", unreadMessages: 1, unreadNotifications: 1, callIntent: .audio),
            summary(id: "!video", name: "Weekend hike 🏔️", lastMessage: "Jonas: Join the call, we're planning the route",
                    callIntent: .video),
            summary(id: "!marked", name: "Erin", isDirect: true, heroes: [.mockErin],
                    lastMessage: "Sent a photo", isMarkedUnread: true),
            summary(id: "!quiet", name: "Book club", lastMessage: "Priya: Chapter nine was something else",
                    unreadMessages: 4, notificationMode: .mentionsAndKeywordsOnly),
            summary(id: "!muted-unread", name: "Neighbourhood", lastMessage: "Tom: The street party moved to Sunday",
                    unreadMessages: 12, unreadNotifications: 12, notificationMode: .mute),
            summary(id: "!muted", name: "Release notes", lastMessage: "Version 1.0.2 is out", notificationMode: .mute),
            summary(id: "!failed", name: "Lina Park", isDirect: true, heroes: [.init(userID: "@lina:example.com", displayName: "Lina Park", avatarURL: nil)],
                    lastMessage: "See you there", lastMessageState: .failed),
            summary(id: "!sending", name: "Project Atlas", lastMessage: "Uploading the final draft", lastMessageState: .sending),
            summary(id: "!favourite", name: "Mum", isDirect: true, heroes: [.init(userID: "@mum:example.com", displayName: "Mum", avatarURL: nil)],
                    lastMessage: "Call me when you land", isFavourite: true),
            summary(id: "!upgraded", name: "Old project room", unreadMessages: 1, unreadNotifications: 1, isTombstoned: true),
            summary(id: "!new", name: "Tessa Moreau", isDirect: true, heroes: [.init(userID: "@tessa:example.com", displayName: "Tessa Moreau", avatarURL: nil)],
                    lastMessage: nil),
            summary(id: "!invite", name: "Climbing club", joinRequestType: .invite(inviter: RoomMemberProxyMock.mockCharlie),
                    canonicalAlias: "#climbing:example.com"),
            summary(id: "!dm-invite", name: "Sam Rivera", isDirect: true, joinRequestType: .invite(inviter: sam)),
            summary(id: "!knock", name: "Product guild", joinRequestType: .knock, canonicalAlias: "#product-guild:example.com")
        ]
    }
    
    private static func summary(id: String,
                                name: String,
                                isDirect: Bool = false,
                                heroes: [UserProfile] = [],
                                joinRequestType: RoomSummary.JoinRequestType? = nil,
                                lastMessage: String? = nil,
                                lastMessageState: RoomSummary.LastMessageState? = nil,
                                unreadMessages: UInt = 0,
                                unreadMentions: UInt = 0,
                                unreadNotifications: UInt = 0,
                                notificationMode: RoomNotificationModeProxy = .allMessages,
                                canonicalAlias: String? = nil,
                                callIntent: CallIntent? = nil,
                                isMarkedUnread: Bool = false,
                                isFavourite: Bool = false,
                                isTombstoned: Bool = false) -> RoomSummary {
        RoomSummary(room: RoomSDKMock(),
                    id: id,
                    joinRequestType: joinRequestType,
                    isJoined: joinRequestType == nil,
                    name: name,
                    isDirect: isDirect,
                    isSpace: false,
                    avatarURL: nil,
                    heroes: heroes,
                    activeMembersCount: 0,
                    lastMessage: lastMessage.map { AttributedString($0) },
                    lastMessageDate: joinRequestType == nil ? .mock : nil,
                    lastMessageState: lastMessageState,
                    unreadMessagesCount: unreadMessages,
                    unreadMentionsCount: unreadMentions,
                    unreadNotificationsCount: unreadNotifications,
                    notificationMode: joinRequestType == nil ? notificationMode : nil,
                    canonicalAlias: canonicalAlias,
                    alternativeAliases: [],
                    hasOngoingCall: callIntent != nil,
                    activeCallIntent: callIntent,
                    isMarkedUnread: isMarkedUnread,
                    isFavourite: isFavourite,
                    isTombstoned: isTombstoned)
    }
}
