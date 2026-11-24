//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Brief 0073 / ADR-0008 — the invite screen.
//

@testable import Spiral
import Testing
import UIKit

@MainActor
struct InvitePeopleScreenViewModelTests {
    private let service = AgentPlatformServiceMock()
    private let clientProxy = ClientProxyMock(.init(userID: "@emmm:spiral.md"))
    
    private func makeViewModel() -> InvitePeopleScreenViewModel {
        if service.fetchInvitedByReturnValue == nil, service.fetchInvitedByClosure == nil {
            service.fetchInvitedByReturnValue = .success(nil)
        }
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        userSession.agentPlatformService = service
        return InvitePeopleScreenViewModel(userSession: userSession, userIndicatorController: UserIndicatorControllerMock())
    }
    
    private func invite(used: Int) -> MyInvite {
        MyInvite(link: SpiralInviteLink(token: "Qz8Hf72Kd91")!, maxUses: 10, used: used, expiresAt: nil)
    }
    
    @Test
    func loadsTheLinkAndWhoJoined() async throws {
        service.fetchMyInviteReturnValue = .success(invite(used: 3))
        service.fetchMyInviteJoinedReturnValue = .success([.init(userID: "@alice:spiral.md", joinedAt: .now),
                                                           .init(userID: "@bob:spiral.md", joinedAt: .now)])
        clientProxy.profileForClosure = { userID in
            userID == "@alice:spiral.md" ? .success(UserProfile(userID: userID, displayName: "Alice")) : .failure(.sdkError(ClientProxyMockError.generic))
        }
        
        let viewModel = makeViewModel()
        // The MXIDs show at once; the names follow when the profiles land.
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.joined)) { $0.count == 2 && $0[0].displayName != nil }
        try await deferred.fulfill()
        
        #expect(viewModel.context.viewState.invite?.seatsLeft == 7)
        #expect(viewModel.context.viewState.shareText?.contains("https://spiral.md/join/Qz8Hf72Kd91") == true)
        #expect(viewModel.context.viewState.joined[0].displayName == "Alice")
        // A profile lookup that fails still lists the person by MXID.
        #expect(viewModel.context.viewState.joined[1].id == "@bob:spiral.md")
        #expect(viewModel.context.viewState.joined[1].displayName == nil)
    }
    
    /// 1.0.3 (operator: «щоб бачили і другу сторону»): whose link the caller came with shows, named.
    @Test
    func whoInvitedTheCallerShowsWithTheirName() async throws {
        service.fetchMyInviteReturnValue = .success(invite(used: 0))
        service.fetchMyInviteJoinedReturnValue = .success([])
        service.fetchInvitedByReturnValue = .success(InvitedBy(inviterUserID: "@maria:spiral.md", isWelcomeOwed: false))
        clientProxy.profileForClosure = { userID in .success(UserProfile(userID: userID, displayName: "Maria")) }

        let viewModel = makeViewModel()
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.invitedBy)) { $0?.displayName == "Maria" }
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.invitedBy?.id == "@maria:spiral.md")
    }

    @Test
    func nobodyShowsWithoutAnInviter() async throws {
        service.fetchMyInviteReturnValue = .success(invite(used: 0))
        service.fetchMyInviteJoinedReturnValue = .success([])
        service.fetchInvitedByReturnValue = .success(nil)

        let viewModel = makeViewModel()
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.isLoading)) { !$0 }
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.invitedBy == nil)
    }

    /// Copy link puts exactly the shown link on the pasteboard (the E2E walk checked it through the invitation sheet,
    /// gone in 1.0.3).
    @Test
    func copyLinkPutsTheShownLinkOnThePasteboard() async throws {
        service.fetchMyInviteReturnValue = .success(invite(used: 0))
        service.fetchMyInviteJoinedReturnValue = .success([])
        let viewModel = makeViewModel()
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.invite)) { $0 != nil }
        try await deferred.fulfill()

        viewModel.context.send(viewAction: .copyLink)

        #expect(UIPasteboard.general.url == URL(string: "https://spiral.md/join/Qz8Hf72Kd91"))
    }

        /// Brief 0083, question 359: the page has its shape before the link arrives.
    @Test
    func theLinksPlaceStandsWhileItLoads() async throws {
        let read = HeldRead<MyInvite>(answer: .success(invite(used: 0)))
        service.fetchMyInviteClosure = { await read.answer() }
        service.fetchMyInviteJoinedReturnValue = .success([])
        
        let viewModel = makeViewModel()
        #expect(viewModel.context.viewState.isLoadingInvite)
        
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.invite)) { $0 != nil }
        read.release()
        try await loaded.fulfill()
        #expect(!viewModel.context.viewState.isLoadingInvite)
    }
    
    /// A failed read is never a page still loading: the alert says so.
    @Test
    func aFailedLinkReadStopsLoading() async throws {
        service.fetchMyInviteReturnValue = .failure(.serverError(status: 500))
        
        let viewModel = makeViewModel()
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.isLoading)) { !$0 }
        try await failed.fulfill()
        
        #expect(!viewModel.context.viewState.isLoadingInvite)
        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .loadFailed)
    }
    
    /// Brief 0083, question 359: the link counts who came through it, so their rows stand in that number.
    @Test
    func whoJoinedTakesItsCountFromTheLink() async throws {
        let read = HeldRead<[InviteJoinedEntry]>(answer: .success([.init(userID: "@alice:spiral.md", joinedAt: .now)]))
        service.fetchMyInviteReturnValue = .success(invite(used: 3))
        service.fetchMyInviteJoinedClosure = { await read.answer() }
        clientProxy.profileForClosure = { .success(UserProfile(userID: $0)) }
        
        let viewModel = makeViewModel()
        let linked = deferFulfillment(viewModel.context.observe(\.viewState.invite)) { $0 != nil }
        try await linked.fulfill()
        #expect(viewModel.context.viewState.joinedPlaceholderCount == 3)
        
        let joined = deferFulfillment(viewModel.context.observe(\.viewState.joined)) { !$0.isEmpty }
        read.release()
        try await joined.fulfill()
        #expect(viewModel.context.viewState.joinedPlaceholderCount == 0)
    }
    
    @Test
    func exhaustedLinkIsShownAsSuch() async throws {
        service.fetchMyInviteReturnValue = .success(invite(used: 10))
        service.fetchMyInviteJoinedReturnValue = .success([])
        
        let viewModel = makeViewModel()
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.invite)) { $0 != nil }
        try await loaded.fulfill()
        
        #expect(viewModel.context.viewState.invite?.isExhausted == true)
        #expect(viewModel.context.viewState.invite?.seatsLeft == 0)
        // Still shareable text — the link exists; the footer says it is used up.
        #expect(viewModel.context.viewState.shareText != nil)
    }
    
    @Test
    func tappingSomeoneWhoJoinedOpensThem() async throws {
        service.fetchMyInviteReturnValue = .success(invite(used: 1))
        service.fetchMyInviteJoinedReturnValue = .success([.init(userID: "@alice:spiral.md", joinedAt: .now)])
        clientProxy.profileForClosure = { .success(UserProfile(userID: $0)) }
        
        let viewModel = makeViewModel()
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.joined)) { $0.count == 1 }
        try await loaded.fulfill()
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .openUser(userID: "@alice:spiral.md") }
        viewModel.context.send(viewAction: .openUser(viewModel.context.viewState.joined[0]))
        try await deferred.fulfill()
    }

    // MARK: - The chain's seats (1.0.3, concept C)
    
    /// Who came, then the seats the link counts but the list doesn't name, then the free seats — the first of them the
    /// way to invite. Ten in all, one per seat.
    @Test
    func seatsReadJoinedThenTakenThenFree() {
        var state = InvitePeopleScreenViewState(ownProfile: UserProfile(userID: "@emmm:spiral.md"))
        state.isLoading = false
        state.invite = invite(used: 3)
        state.joined = [UserProfile(userID: "@alice:spiral.md"), UserProfile(userID: "@bob:spiral.md")]
        
        #expect(state.seats == [.joined(UserProfile(userID: "@alice:spiral.md")), .joined(UserProfile(userID: "@bob:spiral.md")),
                                .taken(0), .invite] + (1..<7).map { .free($0) })
    }
    
    @Test
    func aFullLinkHasNoWayToInvite() {
        var state = InvitePeopleScreenViewState(ownProfile: UserProfile(userID: "@emmm:spiral.md"))
        state.isLoading = false
        state.invite = invite(used: 10)
        state.joined = (0..<10).map { UserProfile(userID: "@p\($0):spiral.md") }
        
        #expect(state.seats.count == 10)
        #expect(!state.seats.contains(.invite))
    }
    
    /// While who came is still being read, the people the link counts wait in their seats — never shown as signing up.
    @Test
    func countedPeopleWaitWhileTheirReadIsOut() {
        var state = InvitePeopleScreenViewState(ownProfile: UserProfile(userID: "@emmm:spiral.md"))
        state.isLoading = true
        state.invite = invite(used: 2)
        
        #expect(state.seats == [.loading(0), .loading(1), .invite] + (1..<8).map { .free($0) })
    }
    
    /// Before the link arrives its ten seats stand, waiting; a failed read leaves none.
    @Test
    func theSeatsStandWhileTheLinkLoads() {
        var state = InvitePeopleScreenViewState(ownProfile: UserProfile(userID: "@emmm:spiral.md"))
        #expect(state.seats == (0..<10).map { .loading($0) })
        state.isLoading = false
        #expect(state.seats.isEmpty)
    }
    
    /// The caller's own name and avatar come with the page: the middle of the chain.
    @Test
    func theCallersProfileLoads() async throws {
        service.fetchMyInviteReturnValue = .success(invite(used: 0))
        service.fetchMyInviteJoinedReturnValue = .success([])
        clientProxy.profileForClosure = { userID in .success(UserProfile(userID: userID, displayName: "Emmm")) }
        
        let viewModel = makeViewModel()
        #expect(viewModel.context.viewState.ownProfile.id == "@emmm:spiral.md")
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.ownProfile)) { $0.displayName == "Emmm" }
        try await loaded.fulfill()
    }

    /// A deleted account keeps its seat counted but nameless (Fable review): it reads «Taken», never «signing up»
    /// for good. So does every counted seat when the list of who came failed to load.
    @Test
    func uncountedSeatsAreJustTaken() {
        var state = InvitePeopleScreenViewState(ownProfile: UserProfile(userID: "@emmm:spiral.md"))
        state.isLoading = false
        state.invite = invite(used: 3)
        #expect(state.seats.prefix(4) == [.taken(0), .taken(1), .taken(2), .invite])
    }
    
    /// While the names are still being looked up, the people already listed and the rest of the count hold their
    /// seats: no free seat turns into a taken one when the read ends.
    @Test
    func takenSeatsDontFlipWhileNamesLoad() {
        var state = InvitePeopleScreenViewState(ownProfile: UserProfile(userID: "@emmm:spiral.md"))
        state.invite = invite(used: 3)
        state.joined = [UserProfile(userID: "@alice:spiral.md")]
        let whileLoading = state.seats
        state.isLoading = false
        #expect(whileLoading == state.seats)
    }
    
    /// A failed link read still shows who invited the caller; the page keeps a way to try again.
    @Test
    func theInviterStaysWhenTheLinkFails() async throws {
        service.fetchMyInviteReturnValue = .failure(.serverError(status: 500))
        service.fetchInvitedByReturnValue = .success(InvitedBy(inviterUserID: "@maria:spiral.md", isWelcomeOwed: false))
        clientProxy.profileForClosure = { userID in .success(UserProfile(userID: userID, displayName: "Maria")) }
        
        let viewModel = makeViewModel()
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.isLoading)) { !$0 }
        try await failed.fulfill()
        
        #expect(viewModel.context.viewState.invitedBy?.displayName == "Maria")
        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .loadFailed)
        #expect(viewModel.context.viewState.seats.isEmpty)
    }

    /// Retry keeps the inviter's name on screen while their profile is read again (no jump to the MXID).
    @Test
    func retryKeepsTheInvitersName() async throws {
        service.fetchMyInviteReturnValue = .failure(.serverError(status: 500))
        service.fetchInvitedByReturnValue = .success(InvitedBy(inviterUserID: "@maria:spiral.md", isWelcomeOwed: false))
        clientProxy.profileForClosure = { userID in .success(UserProfile(userID: userID, displayName: "Maria")) }
        let viewModel = makeViewModel()
        let named = deferFulfillment(viewModel.context.observe(\.viewState.invitedBy)) { $0?.displayName == "Maria" }
        try await named.fulfill()
        
        let bare = deferFailure(viewModel.context.observe(\.viewState.invitedBy), timeout: .seconds(1)) { $0?.displayName == nil }
        viewModel.context.send(viewAction: .retry)
        try await bare.fulfill()
    }
}
