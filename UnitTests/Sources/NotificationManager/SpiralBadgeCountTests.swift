//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063, § 5.83; decision 256): the Chats-tab and app-icon
// badges count ROOMS that matter, by `RoomSummary.countsTowardsBadge`, from the
// room list's own counters. Upstream 26.10 publishes the SDK's
// `totalUnreadNotifications` in `NotificationService`; Spiral's
// `NotificationService.attentionCount(in:)` replaces that number.
//

@testable import Spiral
import Testing

@MainActor
struct SpiralBadgeCountTests {
    /// element-x-ios#2066: "the number of rooms with unread push notifs", the
    /// MSC4076 model — the E2EE client computes it, the server can't.
    @Test
    func badgeCountsRoomsNotMessages() {
        let badge = badgeCount(for: [.mock(id: "!a:hs", name: "A", unreadNotificationsCount: 7),
                                     .mock(id: "!b:hs", name: "B", isMarkedUnread: true),
                                     .mock(id: "!c:hs", name: "C")])
        
        #expect(badge == 2, "seven notifications in one room are still ONE room")
    }
    
    @Test
    func plainUnreadMessagesWithoutANotificationDontCount() {
        #expect(badgeCount(for: [.mock(id: "!plain:hs", name: "Plain", unreadMessagesCount: 3)]) == 0)
    }
    
    @Test
    func aMutedRoomWithUnreadNotificationsDoesntCount() {
        #expect(badgeCount(for: [.mock(id: "!muted:hs", name: "Muted", unreadNotificationsCount: 5, notificationMode: .mute)]) == 0)
    }
    
    /// Decided by `notificationMode`: muting means "stop counting this at me", mentions
    /// included; a mentions-only room asked for exactly its mentions.
    @Test
    func aMentionCountsUnlessTheRoomIsMuted() {
        #expect(badgeCount(for: [.mock(id: "!muted:hs", name: "Muted", unreadMentionsCount: 1, notificationMode: .mute)]) == 0)
        #expect(badgeCount(for: [.mock(id: "!mentions:hs", name: "Mentions", unreadMentionsCount: 1, notificationMode: .mentionsAndKeywordsOnly)]) == 1)
    }
    
    @Test
    func aRoomMarkedUnreadCounts() {
        #expect(badgeCount(for: [.mock(id: "!marked:hs", name: "Marked", isMarkedUnread: true)]) == 1)
    }
    
    @Test
    func anUnseenInviteCountsAndASeenOneDoesnt() {
        let invites: [RoomSummary] = [.mock(id: "!new:hs", name: "New", joinRequestType: .invite(inviter: nil)),
                                      .mock(id: "!seen:hs", name: "Seen", joinRequestType: .invite(inviter: nil))]
        
        #expect(badgeCount(for: invites, seenInvites: ["!seen:hs"]) == 1)
    }
    
    /// The setting is the room list's: the badge counts the same rooms either way.
    @Test
    func showAllActivityDoesntChangeTheBadge() {
        let rooms: [RoomSummary] = [.mock(id: "!plain:hs", name: "Plain", unreadMessagesCount: 3),
                                    .mock(id: "!muted:hs", name: "Muted", unreadNotificationsCount: 2, notificationMode: .mute),
                                    .mock(id: "!notifying:hs", name: "Notifying", unreadNotificationsCount: 1)]
        
        #expect(badgeCount(for: rooms, showAllActivity: true) == 1)
        #expect(badgeCount(for: rooms, showAllActivity: false) == 1)
    }
    
    /// Everything read → zero: the badge once said 2 while nothing was unread.
    @Test
    func badgeClearsWhenEverythingIsRead() {
        #expect(badgeCount(for: [.mock(id: "!a:hs", name: "A"), .mock(id: "!b:hs", name: "B")]) == 0)
    }
    
    /// Opening an invite marks it seen without the room list changing.
    @Test
    func openingAnInviteDropsItFromTheBadge() {
        let clientProxy = ClientProxyMock(.init(userID: "@alice:example.com"))
        clientProxy.staticRoomSummaryProvider = RoomSummaryProviderMock(.init(state: .loaded([.mock(id: "!new:hs", name: "New", joinRequestType: .invite(inviter: nil)),
                                                                                              .mock(id: "!other:hs", name: "Other", joinRequestType: .invite(inviter: nil))])))
        let userSettings = AppSettings.volatile().userSettings(for: "@alice:example.com")
        let service = NotificationService(clientProxy: clientProxy, userSettings: userSettings)
        #expect(service.badgeCountPublisher.value == 2)
        
        userSettings.account.seenInvites.insert("!new:hs")
        
        #expect(service.badgeCountPublisher.value == 1)
    }
    
    // MARK: - Helpers
    
    private func badgeCount(for rooms: [RoomSummary], showAllActivity: Bool = true, seenInvites: Set<String> = []) -> Int {
        let clientProxy = ClientProxyMock(.init(userID: "@alice:example.com"))
        clientProxy.staticRoomSummaryProvider = RoomSummaryProviderMock(.init(state: .loaded(rooms)))
        let userSettings = AppSettings.volatile().userSettings(for: "@alice:example.com")
        userSettings.account.showAllRoomListActivity = showAllActivity
        userSettings.account.seenInvites = seenInvites
        
        return NotificationService(clientProxy: clientProxy, userSettings: userSettings).badgeCountPublisher.value
    }
}
