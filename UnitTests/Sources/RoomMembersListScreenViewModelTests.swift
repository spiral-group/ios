//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import Spiral
import Testing

@MainActor
struct RoomMembersListScreenViewModelTests {
    var viewModel: RoomMembersListScreenViewModel!
    var roomProxy: JoinedRoomProxyMock!
    var context: RoomMembersListScreenViewModel.Context {
        viewModel.context
    }
    
    @Test
    mutating func joinedMembers() async throws {
        setup(members: [.mockAlice, .mockBob])
        
        let deferred = deferFulfillment(context.$viewState) { state in
            state.visibleJoinedMembers.count == 2
        }
        try await deferred.fulfill()
        
        #expect(viewModel.state.joinedMembersCount == 2)
        #expect(viewModel.state.visibleJoinedMembers.count == 2)
    }
    
    @Test
    mutating func sortingMembers() async throws {
        setup(members: [.mockModerator, .mockDan, .mockAlice, .mockAdmin])
        
        let deferred = deferFulfillment(context.$viewState) { state in
            state.visibleJoinedMembers.count == 4
        }
        try await deferred.fulfill()
        
        let sortedMembers: [RoomMemberListScreenEntry] = [
            .init(member: .init(withProxy: RoomMemberProxyMock.mockAdmin),
                  verificationState: .notVerified),
            .init(member: .init(withProxy: RoomMemberProxyMock.mockModerator),
                  verificationState: .notVerified),
            .init(member: .init(withProxy: RoomMemberProxyMock.mockAlice),
                  verificationState: .notVerified),
            .init(member: .init(withProxy: RoomMemberProxyMock.mockDan),
                  verificationState: .notVerified)
        ]
        
        #expect(viewModel.state.visibleJoinedMembers == sortedMembers)
    }
    
    @Test
    mutating func sortingCallParticipants() async throws {
        setup(members: [.mockAdmin, .mockFrank, .mockAlice],
              activeRoomCallParticipants: [RoomMemberProxyMock.mockFrank.userID])
        
        let deferred = deferFulfillment(context.$viewState) { state in
            state.visibleJoinedMembers.count == 3
        }
        try await deferred.fulfill()
        
        // Frank is in the call, so he should be sorted to the top despite having the lowest power level.
        let sortedMembers: [RoomMemberListScreenEntry] = [
            .init(member: .init(withProxy: RoomMemberProxyMock.mockFrank),
                  verificationState: .notVerified,
                  isActiveRoomCallParticipant: true),
            .init(member: .init(withProxy: RoomMemberProxyMock.mockAdmin),
                  verificationState: .notVerified),
            .init(member: .init(withProxy: RoomMemberProxyMock.mockAlice),
                  verificationState: .notVerified)
        ]
        
        #expect(viewModel.state.visibleJoinedMembers == sortedMembers)
    }
    
    @Test
    mutating func search() async throws {
        setup(members: [.mockAlice, .mockBob])
        
        let deferred = deferFulfillment(context.$viewState) { state in
            state.visibleJoinedMembers.count == 1
        }
        context.searchQuery = "alice"
        try await deferred.fulfill()
        
        #expect(viewModel.state.joinedMembersCount == 2)
        #expect(viewModel.state.visibleJoinedMembers.count == 1)
    }
    
    @Test
    mutating func emptySearch() async throws {
        setup(members: [.mockAlice, .mockBob])
        
        context.searchQuery = "WWW"
        let deferred = deferFulfillment(context.$viewState) { state in
            state.joinedMembersCount == 2
        }
        try await deferred.fulfill()
        
        #expect(viewModel.state.joinedMembersCount == 2)
        #expect(viewModel.state.visibleJoinedMembers.isEmpty)
    }
    
    @Test
    mutating func joinedAndInvitedMembers() async throws {
        setup(members: [.mockInvited, .mockBob])
        
        let deferred = deferFulfillment(context.$viewState) { state in
            state.visibleInvitedMembers.count == 1
        }
        try await deferred.fulfill()
        
        #expect(viewModel.state.joinedMembersCount == 1)
        #expect(viewModel.state.visibleInvitedMembers.count == 1)
        #expect(viewModel.state.visibleJoinedMembers.count == 1)
    }
    
    @Test
    mutating func invitedMembers() async throws {
        setup(members: [.mockInvited])
        
        let deferred = deferFulfillment(context.$viewState) { state in
            state.visibleInvitedMembers.count == 1
        }
        try await deferred.fulfill()
        
        #expect(viewModel.state.joinedMembersCount == 0)
        #expect(viewModel.state.visibleInvitedMembers.count == 1)
        #expect(viewModel.state.visibleJoinedMembers.isEmpty)
    }
    
    @Test
    mutating func searchInvitedMembers() async throws {
        setup(members: [.mockInvited])
        
        context.searchQuery = "invited"
        let deferred = deferFulfillment(context.$viewState) { state in
            state.visibleInvitedMembers.count == 1
        }
        try await deferred.fulfill()
        
        #expect(viewModel.state.joinedMembersCount == 0)
        #expect(viewModel.state.visibleInvitedMembers.count == 1)
        #expect(viewModel.state.visibleJoinedMembers.isEmpty)
    }
    
    @Test
    mutating func selectUserAsUser() async throws {
        setup(members: .allMembers)
        
        var deferred = deferFulfillment(context.$viewState) { !$0.visibleInvitedMembers.isEmpty }
        try await deferred.fulfill()
        
        deferred = deferFulfillment(context.$viewState) { $0.bindings.manageMemeberViewModel != nil }
        guard let user = viewModel.state.visibleJoinedMembers.first(where: { $0.member.role == .user && $0.member.id != RoomMemberProxyMock.mockMe.userID })?.member else {
            Issue.record("Expected to find a regular user.")
            return
        }
        
        context.send(viewAction: .selectMember(user))
        try await deferred.fulfill()
        
        #expect(context.manageMemeberViewModel != nil)
        #expect(context.manageMemeberViewModel?.state.memberDetails.id == user.id)
        #expect(context.manageMemeberViewModel?.state.permissions.canKick == false)
        #expect(context.manageMemeberViewModel?.state.permissions.canBan == false)
    }
    
    @Test
    mutating func selectUserAsAdmin() async throws {
        setup(members: .allMembersAsAdmin)
        
        var deferred = deferFulfillment(context.$viewState) { !$0.visibleInvitedMembers.isEmpty && $0.canKickUsers && $0.canBanUsers }
        try await deferred.fulfill()
        
        #expect(context.manageMemeberViewModel == nil)
        
        deferred = deferFulfillment(context.$viewState) { $0.bindings.manageMemeberViewModel != nil }
        guard let user = viewModel.state.visibleJoinedMembers.first(where: { $0.member.role == .user && $0.member.id != RoomMemberProxyMock.mockMe.userID })?.member else {
            Issue.record("Expected to find a regular user.")
            return
        }
        
        context.send(viewAction: .selectMember(user))
        try await deferred.fulfill()
        
        #expect(context.manageMemeberViewModel?.state.memberDetails.id == user.id)
        #expect(context.manageMemeberViewModel?.state.permissions.canKick == true)
        #expect(context.manageMemeberViewModel?.state.permissions.canBan == true)
        #expect(context.manageMemeberViewModel?.state.isKickDisabled == false)
        #expect(context.manageMemeberViewModel?.state.isBanUnbanDisabled == false)
        #expect(context.manageMemeberViewModel?.state.isMemberBanned == false)
    }
    
    @Test
    mutating func selectModeratorAsAdmin() async throws {
        setup(members: .allMembersAsAdmin)
        
        var deferred = deferFulfillment(context.$viewState) { !$0.visibleInvitedMembers.isEmpty && $0.canKickUsers && $0.canBanUsers }
        try await deferred.fulfill()
        
        #expect(context.manageMemeberViewModel == nil)
        
        deferred = deferFulfillment(context.$viewState) { $0.bindings.manageMemeberViewModel != nil }
        guard let moderator = viewModel.state.visibleJoinedMembers.first(where: { $0.member.role == .moderator })?.member else {
            Issue.record("Expected to find a moderator.")
            return
        }
        
        context.send(viewAction: .selectMember(moderator))
        try await deferred.fulfill()
        
        #expect(context.manageMemeberViewModel?.state.memberDetails.id == moderator.id)
        #expect(context.manageMemeberViewModel?.state.permissions.canKick == true)
        #expect(context.manageMemeberViewModel?.state.permissions.canBan == true)
        #expect(context.manageMemeberViewModel?.state.isMemberBanned == false)
        #expect(context.manageMemeberViewModel?.state.isKickDisabled == false)
        #expect(context.manageMemeberViewModel?.state.isBanUnbanDisabled == false)
    }
    
    @Test
    mutating func selectAdminAsAdmin() async throws {
        setup(members: .allMembersAsAdmin)
        
        var deferred = deferFulfillment(context.$viewState) { !$0.visibleInvitedMembers.isEmpty && $0.canKickUsers && $0.canBanUsers }
        try await deferred.fulfill()
        
        deferred = deferFulfillment(context.$viewState) { $0.bindings.manageMemeberViewModel != nil }
        guard let admin = viewModel.state.visibleJoinedMembers.first(where: { $0.member.role.isAdminOrHigher && $0.member.id != RoomMemberProxyMock.mockMe.userID })?.member else {
            Issue.record("Expected to find another admin.")
            return
        }
        
        context.send(viewAction: .selectMember(admin))
        try await deferred.fulfill()
        
        #expect(context.manageMemeberViewModel?.state.memberDetails.id == admin.id)
        #expect(context.manageMemeberViewModel?.state.permissions.canKick == true)
        #expect(context.manageMemeberViewModel?.state.permissions.canBan == true)
        #expect(context.manageMemeberViewModel?.state.isKickDisabled == true)
        #expect(context.manageMemeberViewModel?.state.isBanUnbanDisabled == true)
        #expect(context.manageMemeberViewModel?.state.isMemberBanned == false)
    }
    
    @Test
    mutating func selectOwnMemberAsAdmin() async throws {
        setup(members: .allMembersAsAdmin)
        
        let deferred = deferFulfillment(context.$viewState) { !$0.visibleInvitedMembers.isEmpty }
        try await deferred.fulfill()
        
        let memberDetailsAction = deferFulfillment(viewModel.actions) { $0.isSelectMember }
        guard let ownMember = viewModel.state.visibleJoinedMembers.first(where: { $0.member.id == RoomMemberProxyMock.mockMe.userID })?.member else {
            Issue.record("Expected to find own user admin.")
            return
        }
        
        context.send(viewAction: .selectMember(ownMember))
        try await memberDetailsAction.fulfill()
        
        #expect(context.manageMemeberViewModel == nil)
    }
    
    @Test
    mutating func selectBannedMember() async throws {
        setup(members: .allMembersAsAdmin + RoomMemberProxyMock.mockBanned)
        
        var deferred = deferFulfillment(context.$viewState) { !$0.visibleInvitedMembers.isEmpty && $0.canKickUsers && $0.canBanUsers }
        try await deferred.fulfill()
        
        #expect(context.alertInfo == nil)
        
        deferred = deferFulfillment(context.$viewState) { $0.bindings.manageMemeberViewModel != nil }
        guard let bannedMember = viewModel.state.visibleBannedMembers.first?.member else {
            Issue.record("Expected to find a banned user.")
            return
        }
        
        context.send(viewAction: .selectMember(bannedMember))
        try await deferred.fulfill()
        
        #expect(context.manageMemeberViewModel?.state.memberDetails.id == bannedMember.id)
        #expect(context.manageMemeberViewModel?.state.permissions.canKick == true)
        #expect(context.manageMemeberViewModel?.state.permissions.canBan == true)
        #expect(context.manageMemeberViewModel?.state.isKickDisabled == true)
        #expect(context.manageMemeberViewModel?.state.isBanUnbanDisabled == false)
        #expect(context.manageMemeberViewModel?.state.isMemberBanned == true)
    }
    
    @Test
    mutating func switchesToMembersModeWhenThereAreNoBannedMembers() async throws {
        roomProxy = JoinedRoomProxyMock(.init(name: "test"))
        
        let subject = CurrentValueSubject<[RoomMemberProxyProtocol], Never>([RoomMemberProxyMock].allMembersAsAdmin + RoomMemberProxyMock.mockBanned)
        roomProxy.membersPublisher = subject.asCurrentValuePublisher()
        
        viewModel = RoomMembersListScreenViewModel(userSession: UserSessionMock(.init()),
                                                   roomProxy: roomProxy,
                                                   userIndicatorController: UserIndicatorControllerMock(),
                                                   analytics: AnalyticsServiceMock(.init()))
        
        let context = viewModel.context
        
        var deferred = deferFulfillment(context.$viewState) { $0.visibleBannedMembers.count == 4 && $0.bindings.mode == .banned }
        context.mode = .banned
        try await deferred.fulfill()
        
        deferred = deferFulfillment(context.$viewState) { $0.visibleBannedMembers.isEmpty && $0.bindings.mode == .members }
        subject.value = [RoomMemberProxyMock].allMembersAsAdmin
        try await deferred.fulfill()
    }
    
    // MARK: - Failed reads (AGENT-PLATFORM, 1.0.3 B14)
    
    @Test
    mutating func failedReadOffersRetry() async throws {
        setup(members: []) { .failure(.eventNotFound) }
        
        try await waitUntil { context.viewState.hasFailedToLoad }
        
        #expect(context.viewState.hasFailedToLoad)
        #expect(context.viewState.shouldShowEmptyState)
    }
    
    @Test
    mutating func retryReadsAgainAndSuccessClearsTheFailure() async throws {
        let members = CurrentValueSubject<[RoomMemberProxyProtocol], Never>([])
        setup(members: [], membersSubject: members) { .failure(.eventNotFound) }
        try await waitUntil { context.viewState.hasFailedToLoad }
        // Let the screen's other first reads (the power levels' sink) finish failing too.
        try await Task.sleep(for: .milliseconds(100))
        let readsBeforeRetry = roomProxy.updateMembersCallsCount
        
        roomProxy.updateMembersClosure = {
            members.send([RoomMemberProxyMock.mockAlice, RoomMemberProxyMock.mockBob])
            return .success(())
        }
        context.send(viewAction: .retry)
        
        try await waitUntil { context.viewState.visibleJoinedMembers.count == 2 }
        #expect(roomProxy.updateMembersCallsCount == readsBeforeRetry + 1)
        #expect(!context.viewState.hasFailedToLoad)
        #expect(!context.viewState.shouldShowEmptyState)
    }
    
    @Test
    mutating func retryThatFailsAgainStaysFailed() async throws {
        setup(members: []) { .failure(.eventNotFound) }
        try await waitUntil { context.viewState.hasFailedToLoad }
        try await Task.sleep(for: .milliseconds(100))
        let readsBeforeRetry = roomProxy.updateMembersCallsCount
        
        context.send(viewAction: .retry)
        // Retry shows the preloader again until the read answers.
        #expect(!context.viewState.hasFailedToLoad)
        
        try await waitUntil { context.viewState.hasFailedToLoad }
        #expect(roomProxy.updateMembersCallsCount == readsBeforeRetry + 1)
    }
    
    @Test
    mutating func failedReadWithCachedMembersShowsThemNotTheFailure() async throws {
        // Offline: the disk read has the members, the server read fails before their rows are built.
        setup(members: [.mockAlice, .mockBob]) { .failure(.eventNotFound) }
        var sawFailure = context.viewState.hasFailedToLoad
        let cancellable = context.$viewState.sink { if $0.hasFailedToLoad { sawFailure = true } }
        
        try await waitUntil { context.viewState.visibleJoinedMembers.count == 2 }
        try await Task.sleep(for: .milliseconds(100))
        
        #expect(!sawFailure)
        #expect(!context.viewState.hasFailedToLoad)
        cancellable.cancel()
    }
    
    @Test
    mutating func membersArrivingAfterAFailureKeepItForTheEmptySearch() async throws {
        let members = CurrentValueSubject<[RoomMemberProxyProtocol], Never>([])
        setup(members: [], membersSubject: members) { .failure(.eventNotFound) }
        try await waitUntil { context.viewState.hasFailedToLoad }
        
        members.send([RoomMemberProxyMock.mockAlice])
        
        try await waitUntil { context.viewState.visibleJoinedMembers.count == 1 }
        #expect(context.viewState.hasFailedToLoad)
    }
    
    @Test
    mutating func anOlderReadDoesNotOverrideANewerOne() async throws {
        setup(members: [])
        try await Task.sleep(for: .milliseconds(100))
        #expect(!context.viewState.hasFailedToLoad)
        
        let readsBefore = roomProxy.updateMembersCallsCount
        let reads = ReadCounter()
        roomProxy.updateMembersClosure = {
            // The first read is slow and fails; the next one answers at once.
            if await reads.next() == 1 {
                try? await Task.sleep(for: .milliseconds(300))
                return .failure(.eventNotFound)
            }
            return .success(())
        }
        context.send(viewAction: .retry)
        try await waitUntil { roomProxy.updateMembersCallsCount == readsBefore + 1 }
        context.send(viewAction: .retry)
        
        try await Task.sleep(for: .milliseconds(500))
        #expect(await reads.count == 2)
        #expect(!context.viewState.hasFailedToLoad)
    }
    
    // MARK: - Helpers
    
    private actor ReadCounter {
        private(set) var count = 0
        
        func next() -> Int {
            count += 1
            return count
        }
    }
    
    // MARK: - Presence (AGENT-PLATFORM, Brief 0072, ADR-0083)
    
    @Test
    mutating func theJoinedMembersOnScreenAreAskedForAsOneList() async throws {
        let presenceService = makePresenceService()
        setup(members: [.mockAlice, .mockBob, .mockCharlie], presenceObserverService: presenceService)
        try await deferFulfillment(context.$viewState) { $0.visibleJoinedMembers.count == 3 }.fulfill()
        let alice = RoomMemberProxyMock.mockAlice.userID
        let bob = RoomMemberProxyMock.mockBob.userID
        let charlie = RoomMemberProxyMock.mockCharlie.userID
        
        for userID in [alice, bob, charlie] {
            context.send(viewAction: .memberAppeared(userID: userID))
        }
        try await waitUntil { presenceService.setObservedScopeReceivedArguments?.userIDs == [alice, bob, charlie] }
        try await Task.sleep(for: .milliseconds(400))
        #expect(presenceService.setObservedScopeCallsCount == 1, "a scroll settles before the set is sent")
        
        context.send(viewAction: .memberDisappeared(userID: bob))
        try await waitUntil { presenceService.setObservedScopeReceivedArguments?.userIDs == [alice, charlie] }
        
        viewModel.stop()
        #expect(presenceService.setObservedScopeReceivedArguments?.userIDs == [], "leaving the screen clears the scope")
        #expect(Set(presenceService.setObservedScopeReceivedInvocations.map(\.scope)).count == 1)
    }
    
    @Test
    mutating func onlyThisRoomsMembersReachTheState() async throws {
        let presences = CurrentValueSubject<[String: UserPresence], Never>([:])
        setup(members: [.mockAlice, .mockBob], presenceObserverService: makePresenceService(presences))
        try await deferFulfillment(context.$viewState) { $0.visibleJoinedMembers.count == 2 }.fulfill()
        let alice = RoomMemberProxyMock.mockAlice.userID
        let stranger = "@stranger:matrix.org"
        
        let deferred = deferFulfillment(context.$viewState) { $0.presences[alice]?.isOnline == true }
        presences.send([alice: Self.online(alice), stranger: Self.online(stranger)])
        try await deferred.fulfill()
        #expect(context.viewState.presences.keys.sorted() == [alice])
    }
    
    @Test
    mutating func presenceKnownBeforeTheMembersSurvivesTheirArrival() async throws {
        let alice = RoomMemberProxyMock.mockAlice.userID
        let presences = CurrentValueSubject<[String: UserPresence], Never>([alice: Self.online(alice)])
        setup(members: [.mockAlice, .mockBob], presenceObserverService: makePresenceService(presences))
        
        try await deferFulfillment(context.$viewState) { state in
            state.visibleJoinedMembers.count == 2 && state.presences[alice]?.isOnline == true
        }.fulfill()
    }
    
    private static func online(_ userID: String) -> UserPresence {
        UserPresence(userID: userID, state: .online, lastActiveAgo: 1, currentlyActive: true, receivedAt: .now)
    }
    
    private func makePresenceService(_ presences: CurrentValueSubject<[String: UserPresence], Never> = .init([:])) -> PresenceObserverServiceMock {
        let service = PresenceObserverServiceMock()
        service.presencePublisher = presences.asCurrentValuePublisher()
        return service
    }
    
    private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(5)) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    
    private mutating func setup(members: [RoomMemberProxyMock],
                                activeRoomCallParticipants: [String] = [],
                                presenceObserverService: PresenceObserverServiceProtocol? = nil,
                                membersSubject: CurrentValueSubject<[RoomMemberProxyProtocol], Never>? = nil,
                                updateMembers: (() async -> Result<Void, RoomProxyError>)? = nil) {
        roomProxy = JoinedRoomProxyMock(.init(name: "test", activeRoomCallParticipants: activeRoomCallParticipants, members: members))
        if let membersSubject {
            roomProxy.membersPublisher = membersSubject.asCurrentValuePublisher()
        }
        if let updateMembers {
            roomProxy.updateMembersClosure = updateMembers
        }
        let userSession = UserSessionMock(.init())
        userSession.presenceObserverService = presenceObserverService
        viewModel = RoomMembersListScreenViewModel(userSession: userSession,
                                                   roomProxy: roomProxy,
                                                   userIndicatorController: UserIndicatorControllerMock(),
                                                   analytics: AnalyticsServiceMock(.init()))
    }
}
