//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

@testable import Spiral
import Foundation
import Testing

// AGENT-PLATFORM (Brief 0073): the screen after an invited registration.
@MainActor
struct InviteWelcomeScreenViewModelTests {
    private let inviter = "@emmm:spiral.md"
    
    private func makeViewModel(displayName: String? = "Emma") -> (InviteWelcomeScreenViewModel, ClientProxyMock) {
        let clientProxy = ClientProxyMock(.init(userID: "@newcomer:spiral.md", displayName: "Nora"))
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
    
    // AGENT-PLATFORM (1.0.3 onboarding): the welcome pairs the inviter's avatar with the newcomer's own.
    @Test
    func pairsTheInviterWithTheNewcomersOwnProfile() {
        let (viewModel, _) = makeViewModel()
        #expect(viewModel.context.viewState.ownProfile.id == "@newcomer:spiral.md")
        #expect(viewModel.context.viewState.ownProfile.displayName == "Nora")
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

// MARK: - 1.0.3: the welcome comes from the platform

/// AGENT-PLATFORM (1.0.3, operator 2026-11-21): the welcome after sign-up follows `GET /me/invited-by`, not the
/// link this client carried, and is shown once: the platform records it (`POST`), a failed request is asked again at
/// the next session start, and an answer for an account no longer signed in is dropped.
@MainActor
struct InviteWelcomeOfferTests {
    private let service = AgentPlatformServiceMock()
    private let account = UserSettings.mock(userID: "@newcomer:spiral.md").account
    private let me = "@newcomer:spiral.md"

    init() {
        service.markInviteWelcomedReturnValue = .success(())
    }

    /// One session start; a welcome handed over is displayed at once unless `displays` is false.
    private func run(isStillCurrent: Bool = true, displays: Bool = true) async -> [String] {
        var handedOver: [String] = []
        await InviteWelcomeOffer.run(service: service, account: account, ownUserID: me,
                                     isStillCurrent: { isStillCurrent }, present: { inviter, _ in handedOver.append(inviter) })
        if displays, !handedOver.isEmpty {
            await InviteWelcomeOffer.shown(service: service, account: account)
        }
        return handedOver
    }

    @Test
    func anOwedWelcomeIsShownOnceAndRecorded() async {
        service.fetchInvitedByReturnValue = .success(InvitedBy(inviterUserID: "@alice:spiral.md", isWelcomeOwed: true))

        #expect(await run() == ["@alice:spiral.md"])
        #expect(service.markInviteWelcomedCallsCount == 1)
        #expect(account.hasSettledInviteWelcome)

        // The next session start asks nothing.
        #expect(await run().isEmpty)
        #expect(service.fetchInvitedByCallsCount == 1)
    }

    /// An inviter whose welcome isn't owed (already shown elsewhere, or registered long ago) settles it unseen.
    @Test
    func anInviterWithoutAnOwedWelcomeSettlesIt() async {
        service.fetchInvitedByReturnValue = .success(InvitedBy(inviterUserID: "@alice:spiral.md", isWelcomeOwed: false))

        #expect(await run().isEmpty)
        #expect(account.hasSettledInviteWelcome)
        #expect(service.markInviteWelcomedCallsCount == 0)
    }

    @Test
    func nothingOwedSettlesIt() async {
        service.fetchInvitedByReturnValue = .success(nil)

        #expect(await run().isEmpty)
        #expect(account.hasSettledInviteWelcome)
        #expect(service.markInviteWelcomedCallsCount == 0)
    }

    @Test
    func aFailedAskIsAskedAgainNextTime() async {
        service.fetchInvitedByReturnValue = .failure(.serverError(status: 503))
        #expect(await run().isEmpty)
        #expect(!account.hasSettledInviteWelcome)

        service.fetchInvitedByReturnValue = .success(InvitedBy(inviterUserID: "@alice:spiral.md", isWelcomeOwed: true))
        #expect(await run() == ["@alice:spiral.md"])
    }

    @Test
    func aFailedRecordIsRetriedWithoutShowingItAgain() async {
        service.fetchInvitedByReturnValue = .success(InvitedBy(inviterUserID: "@alice:spiral.md", isWelcomeOwed: true))
        service.markInviteWelcomedReturnValue = .failure(.serverError(status: 503))
        #expect(await run() == ["@alice:spiral.md"])
        #expect(!account.hasSettledInviteWelcome)

        service.markInviteWelcomedReturnValue = .success(())
        #expect(await run().isEmpty)
        #expect(service.fetchInvitedByCallsCount == 1)
        #expect(account.hasSettledInviteWelcome)
    }

    @Test
    func anAnswerForAnAccountNoLongerSignedInIsDropped() async {
        service.fetchInvitedByReturnValue = .success(InvitedBy(inviterUserID: "@alice:spiral.md", isWelcomeOwed: true))

        #expect(await run(isStillCurrent: false).isEmpty)
        #expect(!account.hasShownInviteWelcome)
        #expect(service.markInviteWelcomedCallsCount == 0)
    }

    /// Review finding: queued (onboarding still up) but never displayed — the app quit — leaves it owed.
    @Test
    func aWelcomeQueuedButNeverDisplayedStaysOwed() async {
        service.fetchInvitedByReturnValue = .success(InvitedBy(inviterUserID: "@alice:spiral.md", isWelcomeOwed: true))

        #expect(await run(displays: false) == ["@alice:spiral.md"])
        #expect(service.markInviteWelcomedCallsCount == 0)
        #expect(!account.hasShownInviteWelcome)
        #expect(!account.hasSettledInviteWelcome)

        // The next start asks again and shows it.
        #expect(await run() == ["@alice:spiral.md"])
        #expect(service.markInviteWelcomedCallsCount == 1)
        #expect(account.hasSettledInviteWelcome)
    }

    @Test
    func nobodyIsGreetedByThemselves() async {
        service.fetchInvitedByReturnValue = .success(InvitedBy(inviterUserID: me, isWelcomeOwed: true))

        #expect(await run().isEmpty)
        #expect(account.hasSettledInviteWelcome)
    }
}
