//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import Spiral
import Testing

@MainActor
struct UserProfileScreenViewModelTests {
    @Test
    func initialState() async throws {
        let userIndicatorController = UserIndicatorControllerMock()
        
        // AGENT-PLATFORM (Brief 0060): Spiral links are minted for our own homeserver.
        let profile = UserProfile(userID: "@alice:spiral.md", displayName: "Alice", avatarURL: .mockMXCAvatar)
        let clientProxy = ClientProxyMock(.init())
        clientProxy.profileForReturnValue = .success(profile)
        
        let viewModel = UserProfileScreenViewModel(userID: profile.id,
                                                   isPresentedModally: false,
                                                   userSession: UserSessionMock(.init(clientProxy: clientProxy)),
                                                   analytics: AnalyticsServiceMock(.init()),
                                                   userIndicatorController: userIndicatorController)
        let context = viewModel.context
        
        let waitForMemberToLoad = deferFulfillment(context.observe(\.viewState.userProfile)) { $0 != nil }
        try await waitForMemberToLoad.fulfill()
        
        #expect(!context.viewState.isOwnUser)
        #expect(context.viewState.userProfile == profile)
        #expect(context.viewState.permalink != nil)
    }
    
    @Test
    func initialStateAccountOwner() async throws {
        let userIndicatorController = UserIndicatorControllerMock()
        
        // AGENT-PLATFORM (Brief 0060): links are only minted for our own
        // homeserver, so the account owner has to live on it too.
        let profile = UserProfile(userID: "@me:spiral.md", displayName: "Me", avatarURL: .mockMXCAvatar)
        let clientProxy = ClientProxyMock(.init(userID: profile.id))
        clientProxy.profileForReturnValue = .success(profile)
        
        let viewModel = UserProfileScreenViewModel(userID: profile.id,
                                                   isPresentedModally: false,
                                                   userSession: UserSessionMock(.init(clientProxy: clientProxy)),
                                                   analytics: AnalyticsServiceMock(.init()),
                                                   userIndicatorController: userIndicatorController)
        let context = viewModel.context
        
        let waitForMemberToLoad = deferFulfillment(context.observe(\.viewState.userProfile)) { $0 != nil }
        try await waitForMemberToLoad.fulfill()
        
        #expect(context.viewState.isOwnUser)
        #expect(context.viewState.userProfile == profile)
        #expect(context.viewState.permalink != nil)
    }
    
    @Test
    func startingDmWithUnknownUserFetchesIdentity() async throws {
        let userIndicatorController = UserIndicatorControllerMock()
        
        let profile = UserProfile.mockAlice
        
        let clientProxy = ClientProxyMock(.init())
        clientProxy.directRoomForUserIDReturnValue = .success(nil)
        clientProxy.userIdentityForFallBackToServerReturnValue = .success(nil)
        
        let viewModel = UserProfileScreenViewModel(userID: profile.id,
                                                   isPresentedModally: false,
                                                   userSession: UserSessionMock(.init(clientProxy: clientProxy)),
                                                   analytics: AnalyticsServiceMock(.init()),
                                                   userIndicatorController: userIndicatorController)
        
        let context = viewModel.context
        
        let waitForMemberToLoad = deferFulfillment(context.observe(\.viewState.userProfile)) { $0 != nil }
        try await waitForMemberToLoad.fulfill()
        
        let deferred = deferFulfillment(context.observe(\.viewState.bindings.inviteConfirmationUser), timeout: .seconds(5)) { $0?.isUnknown == true }
        
        context.send(viewAction: .openDirectChat)
        try await deferred.fulfill()
    }
    
    // AGENT-PLATFORM (Brief 0073): a pending DM invite from this person is what
    // «Message» opens, but it is no room to call into — no call buttons.
    @Test
    func aPendingInviteIsWhereMessageGoesButNotACall() async throws {
        let profile = UserProfile.mockAlice
        let clientProxy = ClientProxyMock(.init())
        clientProxy.directRoomForUserIDReturnValue = .success(nil)
        clientProxy.directRoomOrPendingInviteForUserIDClosure = { _ in .success("!invite:spiral.md") }
        
        let viewModel = UserProfileScreenViewModel(userID: profile.id,
                                                   isPresentedModally: false,
                                                   userSession: UserSessionMock(.init(clientProxy: clientProxy)),
                                                   analytics: AnalyticsServiceMock(.init()),
                                                   userIndicatorController: UserIndicatorControllerMock())
        let context = viewModel.context
        
        let loaded = deferFulfillment(context.observe(\.viewState.userProfile)) { $0 != nil }
        try await loaded.fulfill()
        #expect(context.viewState.dmRoomID == nil)
        
        let opened = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .openDirectChat(let roomID) = action { roomID == "!invite:spiral.md" } else { false }
        }
        context.send(viewAction: .openDirectChat)
        try await opened.fulfill()
    }
}
