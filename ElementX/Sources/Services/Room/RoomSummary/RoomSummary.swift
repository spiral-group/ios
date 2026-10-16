//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRustSDK

/// A quick summary of a Room, useful to describe and give quick informations for the room list
nonisolated struct RoomSummary {
    enum JoinRequestType {
        case invite(inviter: RoomMemberProxyProtocol?)
        case knock
        
        var isInvite: Bool {
            switch self {
            case .invite: true
            default: false
            }
        }
    }
    
    enum LastMessageState { case sending, failed }
    
    let room: Room
    
    let id: String
    
    let joinRequestType: JoinRequestType?
    
    let name: String
    let isDirect: Bool
    let isSpace: Bool
    let avatarURL: URL?
    
    let heroes: [UserProfile]
    let activeMembersCount: UInt
    
    let lastMessage: AttributedString?
    let lastMessageDate: Date?
    let lastMessageState: LastMessageState?
    let unreadMessagesCount: UInt
    let unreadMentionsCount: UInt
    let unreadNotificationsCount: UInt
    let notificationMode: RoomNotificationModeProxy?
    let canonicalAlias: String?
    let alternativeAliases: Set<String>
    
    let hasOngoingCall: Bool
    let activeCallIntent: CallIntent?
    
    let isMarkedUnread: Bool
    let isFavourite: Bool
    let isTombstoned: Bool
    
    var hasUnreadMessages: Bool {
        unreadMessagesCount > 0
    }
    
    var hasUnreadMentions: Bool {
        unreadMentionsCount > 0
    }
    
    var hasUnreadNotifications: Bool {
        unreadNotificationsCount > 0
    }
    
    var isMuted: Bool {
        notificationMode == .mute
    }
    
    /// Whether this room is asking for the user's attention — the single
    /// definition behind BOTH the room-list dot and the app icon badge.
    ///
    /// AGENT-PLATFORM: the two used to be computed from different sources
    /// entirely. The dot came from the SDK's client-side unread counters
    /// (decrypted, and deliberately blind to the event types we hide); the
    /// badge came from the homeserver's push count, which in an encrypted
    /// room can only apply the "all encrypted events" rule and therefore
    /// counts everything — call notices, agent control flips, reactions.
    /// Sharing one predicate is what makes "badge says 2, nothing is
    /// unread" structurally impossible rather than merely fixed once.
    func needsAttention(activityVisibility: RoomListActivityVisibility,
                        seenInvites: Set<String>) -> Bool {
        let isUnseenInvite = joinRequestType?.isInvite == true && !seenInvites.contains(id)
        
        return switch activityVisibility {
        case .current:
            hasUnreadMessages || hasUnreadMentions || hasUnreadNotifications || isMarkedUnread || isUnseenInvite
        case .hide, .show:
            (!isMuted && (hasUnreadNotifications || hasUnreadMentions)) || isMarkedUnread || isUnseenInvite
        }
    }
}

nonisolated extension RoomSummary: CustomStringConvertible {
    var description: String {
        """
        RoomSummary: - id: \(id) \
        - isDirect: \(isDirect) \
        - unreadMessagesCount: \(unreadMessagesCount) \
        - unreadMentionsCount: \(unreadMentionsCount) \
        - unreadNotificationsCount: \(unreadNotificationsCount) \
        - notificationMode: \(notificationMode?.rawValue ?? "nil")
        """
    }
    
    /// Used where summaries are shown in a list e.g. message forwarding,
    /// global search, share destination list etc.
    var roomListDescription: String {
        if isDirect {
            return canonicalAlias ?? ""
        }
        
        if let alias = canonicalAlias {
            return alias
        }
        
        guard !heroes.isEmpty else {
            return ""
        }
        
        var heroComponents = heroes.compactMap(\.displayName)
        
        let othersCount = Int(activeMembersCount) - heroes.count
        if othersCount > 0 {
            heroComponents.append(L10n.commonManyMembers(othersCount))
        }
        
        return heroComponents.formatted(.list(type: .and))
    }
}

nonisolated extension RoomSummary {
    /// An empty summary used when the room info is momentarily unavailable (e.g. while the client tears
    /// down on logout). Keeps the diff indices aligned with the SDK instead of crashing.
    nonisolated static func placeholder(room: Room) -> RoomSummary {
        RoomSummary(room: room,
                    id: room.id(),
                    joinRequestType: nil,
                    name: room.id(),
                    isDirect: false,
                    isSpace: false,
                    avatarURL: nil,
                    heroes: [],
                    activeMembersCount: 0,
                    lastMessage: nil,
                    lastMessageDate: nil,
                    lastMessageState: nil,
                    unreadMessagesCount: 0,
                    unreadMentionsCount: 0,
                    unreadNotificationsCount: 0,
                    notificationMode: nil,
                    canonicalAlias: nil,
                    alternativeAliases: [],
                    hasOngoingCall: false,
                    activeCallIntent: nil,
                    isMarkedUnread: false,
                    isFavourite: false,
                    isTombstoned: false)
    }
    
    init(room: Room, id: String, settingsMode: RoomNotificationModeProxy, hasUnreadMessages: Bool, hasUnreadMentions: Bool, hasUnreadNotifications: Bool) {
        self.room = room
        self.id = id
        let string = "\(settingsMode) - messages: \(hasUnreadMessages) - mentions: \(hasUnreadMentions) - notifications: \(hasUnreadNotifications)"
        name = string
        isDirect = true
        isSpace = false
        avatarURL = nil
        
        heroes = []
        activeMembersCount = 0
        
        lastMessage = AttributedString(string)
        lastMessageDate = .mock
        lastMessageState = nil
        unreadMessagesCount = hasUnreadMessages ? 1 : 0
        unreadMentionsCount = hasUnreadMentions ? 1 : 0
        unreadNotificationsCount = hasUnreadNotifications ? 1 : 0
        notificationMode = settingsMode
        canonicalAlias = nil
        alternativeAliases = []
        hasOngoingCall = false
        activeCallIntent = nil
        
        joinRequestType = nil
        isMarkedUnread = false
        isFavourite = false
        isTombstoned = false
    }
    
    /// This doesn't have to work properly for DM invites, the heroes are always empty
    var avatar: RoomAvatar {
        guard !isTombstoned else {
            return .tombstoned
        }
        
        if isSpace {
            return .space(id: id, name: name, avatarURL: avatarURL)
        } else if isDirect, avatarURL == nil, heroes.count == 1 {
            return .heroes(heroes)
        } else {
            return .room(id: id, name: name, avatarURL: avatarURL)
        }
    }
    
    var statusEmoji: Character? {
        guard case let .heroes(heroes) = avatar else { return nil }
        return heroes.first?.status.displayed?.emoji
    }
    
    // AGENT-PLATFORM (Brief 0072, ADR-0083): the DM's other person, by the
    // same rule as `statusEmoji`.
    var dmUserID: String? {
        guard case let .heroes(heroes) = avatar, heroes.count == 1 else { return nil }
        return heroes[0].id
    }
}
