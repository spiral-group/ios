//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: the SDK's room info subscription reports only changes made
// after it starts. A sync between `JoinedRoomProxy.init` reading the info and
// the subscription (a DM joined a moment ago) must still reach the proxy.
//

import Foundation
import MatrixRustSDK
import MatrixRustSDKMocks
@testable import Spiral
import Testing

struct JoinedRoomProxyRoomInfoTests {
    @Test
    func aChangeBeforeTheSubscriptionIsCaughtUp() async throws {
        let room = makeRoom()
        var current = roomInfo(isDirect: false, joinedMembersCount: 0)
        room.roomInfoClosure = { current }
        let proxy = try await makeProxy(room: room)
        #expect(proxy.infoPublisher.value.joinedMembersCount == 0)
        
        // The join's sync lands before anyone subscribed.
        current = roomInfo(isDirect: true, joinedMembersCount: 2)
        let caughtUp = deferFulfillment(proxy.infoPublisher) { $0.joinedMembersCount == 2 }
        proxy.subscribeToRoomInfoUpdates()
        try await caughtUp.fulfill()
        
        #expect(proxy.infoPublisher.value.isDirect)
    }
    
    @Test
    func aSubscriptionUpdateDuringTheCatchUpWins() async throws {
        let room = makeRoom()
        var listener: RoomInfoListener?
        room.subscribeToRoomInfoUpdatesListenerClosure = { newListener in
            listener = newListener
            return TaskHandleSDKMock()
        }
        var reads = 0
        room.roomInfoClosure = {
            reads += 1
            guard reads > 1 else { return roomInfo(isDirect: false, joinedMembersCount: 1) }
            // The catch-up read: a newer update arrives while it is in flight.
            listener?.call(roomInfo: roomInfo(isDirect: true, joinedMembersCount: 3))
            try await Task.sleep(for: .milliseconds(100))
            return roomInfo(isDirect: true, joinedMembersCount: 2)
        }
        let proxy = try await makeProxy(room: room)
        
        let updated = deferFulfillment(proxy.infoPublisher) { $0.joinedMembersCount == 3 }
        proxy.subscribeToRoomInfoUpdates()
        try await updated.fulfill()
        try await Task.sleep(for: .milliseconds(300))
        
        #expect(reads == 2)
        #expect(proxy.infoPublisher.value.joinedMembersCount == 3)
    }
    
    // MARK: - Adding an agent (357 item 4)
    
    /// The agent joins at once and writes its hint a single time: the grant has to be there by then.
    @Test
    func anAgentIsGrantedItsStateRowsBeforeItIsInvited() async throws {
        let room = makeRoom()
        var calls: [String] = []
        room.allowStateTypesAtDefaultLevelEventTypesClosure = { eventTypes in
            #expect(eventTypes == SpiralAgentRoomGrants.stateTypes)
            calls.append("grant")
            return true
        }
        room.inviteUserByIdUserIdClosure = { _ in calls.append("invite") }
        let proxy = try await makeProxy(room: room)
        
        let result = await proxy.invite(userID: "@assistant-me:spiral.md")
        
        #expect(throws: Never.self) { try result.get() }
        #expect(calls == ["grant", "invite"])
    }
    
    @Test
    func aFailedGrantStopsTheInvite() async throws {
        let room = makeRoom()
        room.allowStateTypesAtDefaultLevelEventTypesThrowableError = MockError.unused
        room.inviteUserByIdUserIdClosure = { _ in }
        let proxy = try await makeProxy(room: room)
        
        let result = await proxy.invite(userID: "@assistant-me:spiral.md")
        
        #expect(throws: RoomProxyError.self) { try result.get() }
        #expect(room.inviteUserByIdUserIdCallsCount == 0)
    }
    
    @Test
    func noRightsToGrantStillInvitesTheAgent() async throws {
        let room = makeRoom()
        room.allowStateTypesAtDefaultLevelEventTypesReturnValue = false
        room.inviteUserByIdUserIdClosure = { _ in }
        let proxy = try await makeProxy(room: room)
        
        let result = await proxy.invite(userID: "@assistant-me:spiral.md")
        
        #expect(throws: Never.self) { try result.get() }
        #expect(room.inviteUserByIdUserIdCallsCount == 1)
    }
    
    @Test
    func aFailedInviteIsAFailureAfterTheGrant() async throws {
        let room = makeRoom()
        room.allowStateTypesAtDefaultLevelEventTypesReturnValue = true
        room.inviteUserByIdUserIdThrowableError = MockError.unused
        let proxy = try await makeProxy(room: room)
        
        let result = await proxy.invite(userID: "@assistant-me:spiral.md")
        
        #expect(throws: RoomProxyError.self) { try result.get() }
    }
    
    @Test
    func aPersonGetsNoGrant() async throws {
        let room = makeRoom()
        room.inviteUserByIdUserIdClosure = { _ in }
        let proxy = try await makeProxy(room: room)
        
        _ = await proxy.invite(userID: "@alice:spiral.md")
        
        #expect(room.allowStateTypesAtDefaultLevelEventTypesCallsCount == 0)
        #expect(room.inviteUserByIdUserIdCallsCount == 1)
    }
    
    // MARK: - Helpers
    
    private func makeRoom() -> RoomSDKMock {
        let room = RoomSDKMock()
        room.idReturnValue = "!room:spiral.md"
        room.ownUserIdReturnValue = "@me:spiral.md"
        room.roomInfoReturnValue = roomInfo(isDirect: false, joinedMembersCount: 2)
        room.timelineWithConfigurationConfigurationReturnValue = TimelineSDKMock()
        room.subscribeToRoomInfoUpdatesListenerReturnValue = TaskHandleSDKMock()
        room.membersNoSyncThrowableError = MockError.unused
        room.membersThrowableError = MockError.unused
        room.encryptionStateReturnValue = .notEncrypted
        return room
    }
    
    private func makeProxy(room: RoomSDKMock) async throws -> JoinedRoomProxy {
        let stateEventStringBuilder = RoomStateEventStringBuilder(userID: "@me:spiral.md")
        let attributedStringBuilder = AttributedStringBuilder(mentionBuilder: MentionBuilder())
        let eventStringBuilder = RoomEventStringBuilder(stateEventStringBuilder: stateEventStringBuilder,
                                                        messageEventStringBuilder: RoomMessageEventStringBuilder(attributedStringBuilder: attributedStringBuilder,
                                                                                                                 style: .senderPrefixed),
                                                        shouldPrefixSenderName: true)
        return try await JoinedRoomProxy(roomListService: RoomListServiceSDKMock(),
                                         room: room,
                                         userSettings: UserSettings.mock(),
                                         analyticsService: AnalyticsService(client: DisabledAnalyticsClient(), appSettings: AppSettings.volatile()),
                                         eventStringBuilder: eventStringBuilder)
    }
    
    private enum MockError: Error { case unused }
}

private func roomInfo(isDirect: Bool, joinedMembersCount: UInt64) -> RoomInfo {
    RoomInfo(id: "!room:spiral.md", encryptionState: .notEncrypted, creators: nil, displayName: "Peer", rawName: nil, topic: nil,
             avatarUrl: nil, isDirect: isDirect, isDm: isDirect, isPublic: false, isSpace: false, successorRoom: nil,
             isFavourite: false, isLowPriority: false, canonicalAlias: nil, alternativeAliases: [], membership: .joined,
             inviter: nil, heroes: [], activeMembersCount: joinedMembersCount, invitedMembersCount: 0,
             joinedMembersCount: joinedMembersCount, activeServiceMembersCount: 0, serviceMembers: [], highlightCount: 0,
             notificationCount: 0, cachedUserDefinedNotificationMode: nil, hasRoomCall: false, activeRoomCallParticipants: [],
             activeRoomCallConsensusIntent: .none, isMarkedUnread: false, numUnreadMessages: 0, numUnreadNotifications: 0,
             numUnreadMentions: 0, fullyReadEventId: nil, pinnedEventIds: [], joinRule: nil, historyVisibility: .shared,
             powerLevels: nil, roomVersion: nil, privilegedCreatorsRole: false)
}
