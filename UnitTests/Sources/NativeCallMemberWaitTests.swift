//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import Foundation
import MatrixRustSDK
@testable import Spiral
import Testing

/// A call configured on a room proxy fresh from `roomForIdentifier` reads
/// members that proxy is still loading; the wait in front of it is bounded
/// and only for a DM that has none yet.
@MainActor
struct NativeCallMemberWaitTests {
    /// Review follow-up 2026-10-11: answering a call or calling from a
    /// profile builds a room proxy whose members are still loading. A DM
    /// waits for them, briefly, so a renamed assistant DM still calls its
    /// assistant.
    @Test
    func aFreshDMWaitsForItsMembersBeforeTheCallIsConfigured() async {
        let roomInfo = Self.dm()
        roomInfo.rawName = "My assistant"
        let members = CurrentValueSubject<[RoomMemberProxyProtocol], Never>([])
        let roomProxy = Self.roomProxy(roomInfo, members: members)
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            members.send([Self.member(Self.me), Self.member(Self.assistant)])
        }

        let started = ContinuousClock.now
        await NativeCallConfiguration.awaitFirstMembers(of: roomProxy, timeout: .seconds(5))

        #expect(ContinuousClock.now - started < .seconds(5), "the members arrived inside the bound")
        #expect(NativeCallConfiguration(media: .audio, roomInfo: roomInfo, members: members.value, ownUserID: Self.me).scope == .assistant)
    }

    /// Nothing arrives: the wait ends at its bound and the heroes decide.
    @Test
    func aFreshDMWhoseMembersNeverArriveFallsBackToTheHeroes() async {
        let roomInfo = Self.dm()
        roomInfo.heroes = [Self.hero(Self.assistant)]
        let members = CurrentValueSubject<[RoomMemberProxyProtocol], Never>([])

        let started = ContinuousClock.now
        await NativeCallConfiguration.awaitFirstMembers(of: Self.roomProxy(roomInfo, members: members), timeout: .milliseconds(200))

        #expect(ContinuousClock.now - started >= .milliseconds(200))
        #expect(NativeCallConfiguration(media: .audio, roomInfo: roomInfo, members: members.value, ownUserID: Self.me).scope == .assistant)
        roomInfo.heroes = []
        #expect(NativeCallConfiguration(media: .audio, roomInfo: roomInfo, members: members.value, ownUserID: Self.me).scope == .direct)
    }

    /// The room screen's call button stays instant: a room whose members are
    /// loaded never waits, and neither does a group.
    @Test
    func aLoadedRoomOrAGroupNeverWaitsForMembers() async {
        let loaded = CurrentValueSubject<[RoomMemberProxyProtocol], Never>([Self.member(Self.me), Self.member(Self.assistant)])
        let group = Self.dm()
        group.isDM = false
        let started = ContinuousClock.now

        await NativeCallConfiguration.awaitFirstMembers(of: Self.roomProxy(Self.dm(), members: loaded), timeout: .seconds(5))
        await NativeCallConfiguration.awaitFirstMembers(of: Self.roomProxy(group, members: .init([])), timeout: .seconds(5))

        #expect(ContinuousClock.now - started < .seconds(1))
    }

    /// Re-review 2026-10-11: `updateMembers()` publishes the store's members
    /// first (`membersNoSync`), which under lazy member loading can be just
    /// me, then the full list. The wait must hold out for the whole room —
    /// on the partial list the renamed assistant DM routed `.direct`.
    @Test
    func aPartialFirstLoadKeepsTheWaitGoingUntilTheWholeRoomIsThere() async {
        let roomInfo = Self.dm()
        roomInfo.rawName = "My assistant"
        let members = CurrentValueSubject<[RoomMemberProxyProtocol], Never>([Self.member(Self.me)])
        let roomProxy = Self.roomProxy(roomInfo, members: members)
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            members.send([Self.member(Self.me), Self.member(Self.assistant)])
        }

        await NativeCallConfiguration.awaitFirstMembers(of: roomProxy, timeout: .seconds(5))

        #expect(NativeCallConfiguration(media: .audio, roomInfo: roomInfo, members: members.value, ownUserID: Self.me).scope == .assistant)
    }

    /// A member list with fewer joined members than the room counts is not
    /// the room's members: the heroes decide, as with no list at all.
    @Test
    func aPartialMemberListFallsBackToTheHeroes() {
        let roomInfo = Self.dm()
        roomInfo.heroes = [Self.hero(Self.assistant)]
        let partial = [Self.member(Self.me)]

        #expect(NativeCallConfiguration(media: .audio, roomInfo: roomInfo, members: partial, ownUserID: Self.me).scope == .assistant)
        roomInfo.heroes = []
        #expect(NativeCallConfiguration(media: .audio, roomInfo: roomInfo, members: partial, ownUserID: Self.me).scope == .direct)
    }

    private static func roomProxy(_ roomInfo: RoomInfoProxyMock,
                                  members: CurrentValueSubject<[RoomMemberProxyProtocol], Never>) -> JoinedRoomProxyMock {
        let roomProxy = JoinedRoomProxyMock(.init(id: "!dm:localhost"))
        roomProxy.infoPublisher = CurrentValuePublisher(CurrentValueSubject<RoomInfoProxyProtocol, Never>(roomInfo))
        roomProxy.membersPublisher = CurrentValuePublisher(members)
        return roomProxy
    }

    private nonisolated static let me = "@walkb:localhost"
    private nonisolated static let assistant = "@assistant-walkb:localhost"

    private static func hero(_ userID: String) -> RoomHero {
        RoomHero(userId: userID, displayName: nil, avatarUrl: nil, status: nil, call: nil)
    }

    private static func member(_ userID: String) -> RoomMemberProxyMock {
        RoomMemberProxyMock(with: .init(userID: userID, membership: .join))
    }

    /// A DM of two joined members without member hints.
    private static func dm() -> RoomInfoProxyMock {
        let roomInfo = RoomInfoProxyMock()
        roomInfo.isDirect = true
        roomInfo.isDM = true
        roomInfo.isSpace = false
        roomInfo.joinedMembersCount = 2
        roomInfo.activeServiceMembersCount = 0
        roomInfo.joinRule = .invite
        return roomInfo
    }
}
