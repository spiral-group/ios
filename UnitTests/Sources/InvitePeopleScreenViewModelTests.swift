//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Brief 0073 / ADR-0008 — the invite screen.
//

@testable import ElementX
import Testing

@MainActor
struct InvitePeopleScreenViewModelTests {
    private let service = AgentPlatformServiceMock()
    private let clientProxy = ClientProxyMock(.init(userID: "@emmm:spiral.md"))
    
    private func makeViewModel() -> InvitePeopleScreenViewModel {
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
}
