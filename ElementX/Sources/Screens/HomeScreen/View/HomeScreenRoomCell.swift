//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import MatrixRustSDKMocks
import SwiftUI

struct HomeScreenRoomCell: View {
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.redactionReasons) private var redactionReasons
    // AGENT-PLATFORM (Brief 0083): the name's cap height, to centre the unread marker on its first line.
    @ScaledMetric(relativeTo: .body) private var nameCapHeight = 12.0
    
    let room: HomeScreenRoom
    let isSelected: Bool
    let mediaProvider: MediaProviderProtocol!
    let action: (HomeScreenViewAction) -> Void
    
    private let verticalInsets = 12.0
    private let horizontalInsets = 16.0
    
    var body: some View {
        Button {
            if let roomID = room.roomID {
                action(.selectRoom(roomIdentifier: roomID))
            }
        } label: {
            // AGENT-PLATFORM (Brief 0083): Spiral's row. The unread marker leads in its own column, centred on the
            // avatar, or on the name's first line when the avatar is hidden; the text keeps its column, so the
            // divider starts where it did.
            let markerOffset = nameCapHeight / 2
            HStack(alignment: isAvatarShown ? .center : .firstTextBaseline, spacing: 0) {
                HomeScreenRoomUnreadMarker(isShown: room.badges.isDotShown, isHighlighted: room.isHighlighted, notificationCount: unreadCount)
                    .alignmentGuide(.firstTextBaseline) { dimensions in
                        dimensions[VerticalAlignment.center] + markerOffset
                    }
                
                avatar
                
                content
                    .padding(.vertical, verticalInsets)
                    .padding(.trailing, horizontalInsets)
                    .rowDivider()
            }
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(HomeScreenRoomCellButtonStyle(isSelected: isSelected))
        .accessibilityIdentifier(A11yIdentifiers.homeScreen.roomName(room.name))
        .accessibilityHidden(redactionReasons.contains(.placeholder) ? true : false)
    }
    
    private var isAvatarShown: Bool {
        dynamicTypeSize < .accessibility3
    }
    
    @ViewBuilder
    private var avatar: some View {
        if isAvatarShown {
            RoomAvatarImage(avatar: room.avatar,
                            avatarSize: .room(on: .chats),
                            mediaProvider: mediaProvider)
                // AGENT-PLATFORM (Brief 0072, ADR-0083; Brief 0083, decision 357): the online dot on a DM, an agent's sparkle.
                .avatarBadges(userID: room.dmUserID, avatarURL: room.avatar.url, isOnline: room.isOnline, avatarSize: Avatars.Size.room(on: .chats).value)
                .dynamicTypeSize(dynamicTypeSize < .accessibility1 ? dynamicTypeSize : .accessibility1)
                .accessibilityHidden(true)
                .padding(.trailing, CompoundDesignTokens.space3X) // AGENT-PLATFORM (Brief 0083): 12 pt to the text, as iOS's own lists.
                // AGENT-PLATFORM (question 391): the sparkle never in this list: the name says what the agent is, and the dot keeps its corner.
                .environment(\.agentBadgeContext, .chatList)
        }
    }
    
    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            footer
        }
        // Hide the normal content for Skeletons and overlay centre aligned placeholders.
        .opacity(redactionReasons.contains(.placeholder) ? 0 : 1)
        .overlay {
            if redactionReasons.contains(.placeholder) {
                VStack(alignment: .leading, spacing: 2) {
                    header
                    lastMessage
                }
            }
        }
    }
    
    // AGENT-PLATFORM (Brief 0083): the name and its quiet state (a status, muted) lead; the time trails, in the
    // secondary colour at every state. At accessibility sizes the time moves under the name, so neither is cut.
    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: CompoundDesignTokens.space0_5X) {
                name
                timestampText
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: CompoundDesignTokens.space2X) {
                name
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                timestampText
            }
        }
    }
    
    private var name: some View {
        HStack(alignment: .firstTextBaseline, spacing: CompoundDesignTokens.space1X) {
            Text(room.name)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                // AGENT-PLATFORM (Brief 0083): at accessibility sizes the name wraps to its second line before it's cut.
                .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                // AGENT-PLATFORM (Brief 0072, ADR-0083; Brief 0083, decision 357): the dot and the sparkle are on the
                // avatar, which VoiceOver skips — say them with the name.
                .accessibilityLabel(nameAccessibilityLabel)
            
            if let statusEmoji = room.statusEmoji {
                Text(String(statusEmoji))
                    .fixedSize() // AGENT-PLATFORM (Brief 0083): the name gives way first.
            }
            
            if room.badges.isMuteShown {
                CompoundIcon(\.notificationsOffSolid, size: .xSmall, relativeTo: .compound.bodyMD)
                    .foregroundStyle(.compound.iconSecondary)
                    .accessibilityLabel(L10n.a11yNotificationsMuted)
            }
        }
        .font(.compound.bodyLGSemibold)
        .foregroundColor(.compound.textPrimary)
    }
    
    private var nameAccessibilityLabel: String {
        let isAgent = room.dmUserID.map(SpiralAppPostSession.isAgent) ?? false
        return [room.name,
                isAgent ? UntranslatedL10n.screenNativeCallAgentCenterForeignDetailTitle : nil,
                room.isOnline ? UntranslatedL10n.commonPresenceOnline : nil]
            .compactMap(\.self)
            .joined(separator: ", ")
    }
    
    @ViewBuilder
    private var timestampText: some View {
        if let timestamp = room.timestamp {
            Text(timestamp)
                .font(.compound.bodyMD)
                .foregroundColor(.compound.textSecondary)
                .lineLimit(1)
        }
    }
    
    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: CompoundDesignTokens.space2X) { // AGENT-PLATFORM (Brief 0083)
            ZStack(alignment: .topLeading) {
                // Hidden text with 2 lines to maintain consistent height, scaling with dynamic text.
                Text(" \n ")
                    .lastMessageFormatting(hasFailed: false)
                    .hidden()
                    .environment(\.redactionReasons, []) // Always maintain consistent height
                
                HStack(alignment: .top, spacing: 4.0) {
                    switch room.lastMessageState {
                    case .sending:
                        CompoundIcon(\.time, size: .small, relativeTo: .compound.bodyMD)
                            .foregroundStyle(.compound.iconSecondary) // AGENT-PLATFORM (Brief 0083): 3:1 and up.
                            .offset(y: -1)
                            .accessibilityLabel(L10n.commonSending)
                    case .failed:
                        CompoundIcon(\.errorSolid, size: .small, relativeTo: .compound.bodyMD)
                            .foregroundStyle(.compound.iconCriticalPrimary)
                            .offset(y: -1)
                            .accessibilityHidden(true) // The last message contains the error.
                    case .none:
                        EmptyView()
                    }
                    
                    lastMessage
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            activity
        }
    }
    
    // AGENT-PLATFORM (Brief 0083): a quieter trailing cluster. The unread dot moved to the leading column and
    // muted to the name, so only what is happening now stays here: a call in progress, in the green Spiral's call
    // controls use, and the unread count on a tinted badge that fills only for a mention.
    private var activity: some View {
        HStack(alignment: .firstTextBaseline, spacing: CompoundDesignTokens.space1_5X) {
            switch room.badges.callBadgeType {
            case .voice:
                CompoundIcon(\.voiceCallSolid, size: .xSmall, relativeTo: .compound.bodyMD)
                    .foregroundStyle(.compound.iconSuccessPrimary)
                    .accessibilityLabel(L10n.a11yNotificationsOngoingCall)
            case .video:
                CompoundIcon(\.videoCallSolid, size: .xSmall, relativeTo: .compound.bodyMD)
                    .foregroundStyle(.compound.iconSuccessPrimary)
                    .accessibilityLabel(L10n.a11yNotificationsOngoingCall)
            case .none:
                EmptyView()
            }
            
            if unreadCount > 0 || room.badges.isMentionShown {
                HomeScreenRoomUnreadBadge(count: unreadCount, isMention: room.badges.isMentionShown)
            }
        }
    }
    
    /// The count upstream showed on its badge: only for a room that notifies.
    private var unreadCount: UInt {
        room.badges.isDotShown && room.isHighlighted ? room.badges.notificationCount : 0
    }
    
    @ViewBuilder
    private var lastMessage: some View {
        if let displayedLastMessage = room.displayedLastMessage {
            Text(displayedLastMessage)
                .font(.compound.bodyMD)
                .lastMessageFormatting(hasFailed: room.lastMessageState == .failed)
        }
    }
}

// AGENT-PLATFORM (Brief 0083): the leading unread marker of a Chats row, an invite and a knock, in a column
// 24 pt wide at the default text size. A room that notifies gets an accent dot; one with quiet unread messages
// (muted, or mentions only) a ring, so the two differ in shape as well as colour. Both are 3:1 and up. The
// column stays when there's nothing to mark, so the avatars and the text line up.
struct HomeScreenRoomUnreadMarker: View {
    @ScaledMetric(relativeTo: .subheadline) private var scaledSize = 10.0
    
    let isShown: Bool
    let isHighlighted: Bool
    /// How many notifications the row counts, read as "3 new messages"; zero reads as upstream's "New messages".
    var notificationCount: UInt = 0
    
    private var size: CGFloat {
        min(scaledSize, 14)
    }
    
    /// A room that notifies reads its count; one whose unread is quiet reads "Unread", the filter's own word.
    private var accessibilityText: String {
        if !isHighlighted {
            L10n.screenRoomlistFilterUnreads
        } else if notificationCount > 0 {
            L10n.notificationNewMessagesForRoom(Int(notificationCount))
        } else {
            L10n.a11yNotificationsNewMessages
        }
    }
    
    var body: some View {
        ZStack {
            if isShown {
                if isHighlighted {
                    Circle()
                        .fill(.compound.iconAccentPrimary)
                } else {
                    Circle()
                        .strokeBorder(.compound.iconSecondary, lineWidth: 1.5)
                }
            }
        }
        .frame(width: size, height: size)
        .padding(.leading, CompoundDesignTokens.space1_5X)
        .padding(.trailing, CompoundDesignTokens.space2X)
        .accessibilityElement()
        .accessibilityLabel(isShown ? accessibilityText : "")
        .accessibilityHidden(!isShown)
    }
}

// AGENT-PLATFORM (Brief 0083): the unread count on Compound's tinted badge roles (`BadgeLabel`'s accent),
// capped at 99+. A mention adds "@" and fills it with the accent, the one loud thing a row can show. VoiceOver
// reads "New mentions"; the row's marker already reads the count.
private struct HomeScreenRoomUnreadBadge: View {
    @ScaledMetric(relativeTo: .footnote) private var minimumSide = CompoundDesignTokens.space5X
    
    let count: UInt
    let isMention: Bool
    
    var body: some View {
        HStack(spacing: CompoundDesignTokens.space0_5X) {
            if isMention {
                CompoundIcon(\.mention, size: .xSmall, relativeTo: .compound.bodySMSemibold)
                    .accessibilityLabel(L10n.a11yNotificationsNewMentions)
            }
            
            if count > 0 {
                Text(count > 99 ? "99+" : "\(count)")
                    .accessibilityHidden(true)
            }
        }
        .font(.compound.bodySMSemibold)
        .foregroundStyle(isMention ? Color.compound.textOnSolidPrimary : .compound.textBadgeAccent)
        .lineLimit(1)
        .padding(.horizontal, CompoundDesignTokens.space1_5X)
        .frame(minWidth: minimumSide, minHeight: minimumSide)
        .background(isMention ? Color.compound.bgAccentRest : .compound.bgBadgeAccent, in: .capsule)
    }
}

struct HomeScreenRoomCellButtonStyle: ButtonStyle {
    let isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isSelected ? Color.compound.bgSubtleSecondary : Color.compound.bgCanvasDefault)
            .contentShape(Rectangle())
            .animation(isSelected ? .none : .easeOut(duration: 0.1).disabledDuringTests(), value: isSelected)
    }
}

private extension View {
    func lastMessageFormatting(hasFailed: Bool) -> some View {
        foregroundColor(hasFailed ? .compound.textCriticalPrimary : .compound.textSecondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }
}

// MARK: - Previews

struct HomeScreenRoomCell_Previews: PreviewProvider, TestablePreview {
    static let summaryProviderGeneric = RoomSummaryProviderMock(.init(state: .loaded(.mockRooms)))
    static let genericRooms = summaryProviderGeneric.roomListPublisher.value.compactMap { mockRoom(summary: $0) }
    
    static let summaryProviderForNotificationsState = RoomSummaryProviderMock(.init(state: .loaded(.mockRoomsWithNotificationsState)))
    static let notificationsStateRooms = summaryProviderForNotificationsState.roomListPublisher.value.compactMap { mockRoom(summary: $0) }
    
    static let lastMessageStateRooms = [makeRoom(lastMessageState: .sending), makeRoom(lastMessageState: .failed)]
    
    static let roomHeroRooms = [makeRoom(heroes: [.mockDan]), makeRoom(heroes: [.mockErin])]

    // AGENT-PLATFORM (Brief 0083, decision 357): who is who at a glance.
    static let kindsRooms = {
        var person = makeRoom(heroes: [.init(userID: "@erin:matrix.org", displayName: "Erin", avatarURL: .mockMXCUserAvatar)])
        person.isOnline = true
        var agent = makeRoom(heroes: [.init(userID: "@assistant-alice:matrix.org", displayName: "Alice's assistant")])
        agent.isOnline = true
        // An agent's own picture: no sparkle here either (question 391), and the dot stays on its corner.
        var agentWithPicture = makeRoom(heroes: [.init(userID: "@agent-support-2:matrix.org", displayName: "Support agent", avatarURL: .mockMXCAvatar)])
        agentWithPicture.isOnline = true
        return [person,
                agent,
                agentWithPicture,
                makeRoom(),
                makeRoom(heroes: [.mockDan]),
                makeRoom(heroes: [], name: "Design team", avatarURL: nil)]
    }()
    
    static var previews: some View {
        VStack(spacing: 0) {
            ForEach(genericRooms) { room in
                HomeScreenRoomCell(room: room, isSelected: false, mediaProvider: MediaProviderMock(.init())) { _ in }
            }
            
            HomeScreenRoomCell(room: .placeholder(), isSelected: false, mediaProvider: MediaProviderMock(.init())) { _ in }
                .redacted(reason: .placeholder)
        }
        .previewDisplayName("Generic")
        
        VStack(spacing: 0) {
            ForEach(notificationsStateRooms) { room in
                HomeScreenRoomCell(room: room, isSelected: false, mediaProvider: MediaProviderMock(.init())) { _ in }
            }
        }
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Notifications State")
        
        VStack(spacing: 0) {
            ForEach(lastMessageStateRooms) { room in
                HomeScreenRoomCell(room: room, isSelected: false, mediaProvider: MediaProviderMock(.init())) { _ in }
            }
        }
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Last Message State")
        
        VStack(spacing: 0) {
            ForEach(roomHeroRooms) { room in
                HomeScreenRoomCell(room: room, isSelected: false, mediaProvider: MediaProviderMock(.init())) { _ in }
            }
        }
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Room Heroes")
        
        VStack(spacing: 0) {
            ForEach(kindsRooms) { room in
                HomeScreenRoomCell(room: room, isSelected: false, mediaProvider: MediaProviderMock(.init())) { _ in }
            }
        }
        .previewLayout(.sizeThatFits)
        .previewDisplayName("People, groups and agents")
    }
    
    static func mockRoom(summary: RoomSummary) -> HomeScreenRoom? {
        HomeScreenRoom(summary: summary)
    }
    
    static func makeRoom(lastMessageState: RoomSummary.LastMessageState? = nil,
                         heroes: [UserProfile] = [],
                         name groupName: String = "Foundation and Empire",
                         avatarURL: URL? = .mockMXCAvatar) -> HomeScreenRoom {
        let name = if heroes.count == 1 {
            heroes[0].displayName ?? heroes[0].id
        } else {
            groupName
        }
        let summary = RoomSummary(room: RoomSDKMock(),
                                  id: UUID().uuidString,
                                  joinRequestType: nil,
                                  isJoined: true,
                                  name: name,
                                  isDirect: heroes.count == 1,
                                  isSpace: false,
                                  avatarURL: heroes.count == 1 ? nil : avatarURL,
                                  heroes: heroes,
                                  activeMembersCount: 0,
                                  lastMessage: AttributedString("How do you see the Emperor then? You think he keeps office hours?"),
                                  lastMessageDate: .mock,
                                  lastMessageState: lastMessageState,
                                  unreadMessagesCount: 2,
                                  unreadMentionsCount: 0,
                                  unreadNotificationsCount: 2,
                                  notificationMode: .mute,
                                  canonicalAlias: "#foundation-and-empire:matrix.org",
                                  alternativeAliases: [],
                                  hasOngoingCall: false,
                                  activeCallIntent: nil,
                                  isMarkedUnread: false,
                                  isFavourite: false,
                                  isTombstoned: false)
        
        return .init(summary: summary)
    }
}
