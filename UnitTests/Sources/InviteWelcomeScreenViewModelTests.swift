//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

@testable import Spiral
import Testing

// AGENT-PLATFORM (Brief 0073): the screen after an invited registration.
@MainActor
struct InviteWelcomeScreenViewModelTests {
    private let inviter = "@emmm:spiral.md"
    
    private func makeViewModel(displayName: String? = "Emma") -> (InviteWelcomeScreenViewModel, ClientProxyMock) {
        let clientProxy = ClientProxyMock(.init(userID: "@newcomer:spiral.md"))
        clientProxy.profileForReturnValue = .success(.init(userID: inviter, displayName: displayName))
        clientProxy.directRoomOrPendingInviteForUserIDClosure = nil
        let viewModel = InviteWelcomeScreenViewModel(inviterUserID: inviter, clientProxy: clientProxy, mediaProvider: nil)
        return (viewModel, clientProxy)
    }
    
    @Test
    func namesTheInviterFromTheirProfile() async throws {
        let (viewModel, _) = makeViewModel()
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.inviterProfile)) { $0 != nil }
        try await loaded.fulfill()
        #expect(viewModel.context.viewState.inviterName == "Emma")
    }
    
    @Test
    func fallsBackToTheLocalpartNotTheMXID() async throws {
        let (viewModel, _) = makeViewModel(displayName: " ")
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.inviterProfile)) { $0 != nil }
        try await loaded.fulfill()
        #expect(viewModel.context.viewState.inviterName == "emmm")
    }
    
    @Test
    func messageOpensTheExistingDirectChat() async throws {
        let (viewModel, clientProxy) = makeViewModel()
        clientProxy.directRoomOrPendingInviteForUserIDReturnValue = .success("!dm:spiral.md")
        
        let opened = deferFulfillment(viewModel.actionsPublisher) { $0 == .openDirectChat(roomID: "!dm:spiral.md") }
        viewModel.context.send(viewAction: .message)
        try await opened.fulfill()
        #expect(!clientProxy.createDirectRoomWithExpectedRoomNameCalled)
    }
    
    @Test
    func messageCreatesTheDirectChatWithoutAskingAgain() async throws {
        let (viewModel, clientProxy) = makeViewModel()
        clientProxy.directRoomOrPendingInviteForUserIDReturnValue = .success(nil)
        clientProxy.createDirectRoomWithExpectedRoomNameReturnValue = .success("!new:spiral.md")
        
        let opened = deferFulfillment(viewModel.actionsPublisher) { $0 == .openDirectChat(roomID: "!new:spiral.md") }
        viewModel.context.send(viewAction: .message)
        try await opened.fulfill()
        #expect(clientProxy.createDirectRoomWithExpectedRoomNameReceivedArguments?.userID == inviter)
    }
    
    @Test
    func aFailedChatShowsAnAlertAndStays() async throws {
        let (viewModel, clientProxy) = makeViewModel()
        clientProxy.directRoomOrPendingInviteForUserIDReturnValue = .success(nil)
        clientProxy.createDirectRoomWithExpectedRoomNameReturnValue = .failure(.sdkError(ClientProxyMockError.generic))
        
        let alert = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0 != nil }
        viewModel.context.send(viewAction: .message)
        try await alert.fulfill()
        #expect(!viewModel.context.viewState.isOpeningChat)
    }
    
    @Test
    func laterDismisses() async throws {
        let (viewModel, _) = makeViewModel()
        let dismissed = deferFulfillment(viewModel.actionsPublisher) { $0 == .dismiss }
        viewModel.context.send(viewAction: .later)
        try await dismissed.fulfill()
    }
}
