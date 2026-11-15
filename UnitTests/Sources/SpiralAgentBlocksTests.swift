//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (decision 87): undoing an agent's block of a person from their
// profile — confirmed first, then `DELETE /agents/{id}/blocks`, then a toast.
//

import Combine
import Foundation
import MatrixRustSDK
@testable import Spiral
import Testing

@MainActor
struct SpiralAgentBlocksTests {
    let service = AgentPlatformServiceMock()
    let userIndicatorController = UserIndicatorControllerMock()

    init() {
        service.listAgentBlocksOfContactReturnValue = .success([Self.ariaBlock])
        service.unblockContactForAgentReturnValue = .success(())
    }

    // MARK: - The helper

    @Test
    func theBlocksAreReadOrNothingIsShown() async {
        let agentBlocks = AgentBlocks(agentPlatformService: service, userIndicatorController: userIndicatorController)
        #expect(await agentBlocks.blocks(ofContact: "@bob:spiral.md") == [Self.ariaBlock])
        #expect(service.listAgentBlocksOfContactReceivedContactMXID == "@bob:spiral.md")

        service.listAgentBlocksOfContactReturnValue = .failure(.serverError(status: 500))
        #expect(await agentBlocks.blocks(ofContact: "@bob:spiral.md") == nil)
    }

    @Test
    func theConfirmationNamesThePersonAndTheAgent() throws {
        let agentBlocks = AgentBlocks(agentPlatformService: service, userIndicatorController: userIndicatorController)
        let alert = agentBlocks.confirmation(id: "unblock", block: Self.ariaBlock, contactName: "Bob") { }

        #expect(alert.title == UntranslatedL10n.screenRoomMemberDetailsAgentUnblockAlertTitle("Bob", "Aria"))
        #expect(alert.message == UntranslatedL10n.screenRoomMemberDetailsAgentUnblockAlertMessage("Aria"))
        #expect(alert.primaryButton.title == UntranslatedL10n.screenRoomMemberDetailsAgentUnblockAction)
        #expect(try #require(alert.secondaryButton).role == .cancel)
    }

    @Test(arguments: [true, false])
    func anUnblockSaysSoEitherWay(succeeds: Bool) async {
        service.unblockContactForAgentReturnValue = succeeds ? .success(()) : .failure(.forbidden)
        let agentBlocks = AgentBlocks(agentPlatformService: service, userIndicatorController: userIndicatorController)

        let unblocked = await agentBlocks.unblock(Self.ariaBlock, contactMXID: "@bob:spiral.md")

        #expect(unblocked == succeeds)
        #expect(service.unblockContactForAgentReceivedArguments?.contactMXID == "@bob:spiral.md")
        #expect(service.unblockContactForAgentReceivedArguments?.agentID == Self.ariaBlock.agentID)
        let toast = userIndicatorController.submitIndicatorDelayReceivedArguments?.indicator.title
        #expect(toast == (succeeds ? UntranslatedL10n.screenRoomMemberDetailsAgentUnblockDone("Aria") : UntranslatedL10n.screenRoomMemberDetailsAgentUnblockFailed))
    }

    // MARK: - Room member details

    @Test
    func memberDetailsShowsTheBlocksOnAPersonsProfile() async throws {
        let viewModel = makeMemberDetails(member: .mockAlice)

        let shown = deferFulfillment(viewModel.context.$viewState) { $0.showAgentBlocksSection }
        try await shown.fulfill()

        #expect(viewModel.context.viewState.agentBlocks == [Self.ariaBlock])
        #expect(service.listAgentBlocksOfContactReceivedContactMXID == RoomMemberProxyMock.mockAlice.userID)
    }

    @Test
    func memberDetailsReadsNoBlocksOnYourOwnProfile() async throws {
        let viewModel = makeMemberDetails(member: .mockMe)

        // The rule has decided before the identity is read, and a read it lets through is state at once.
        let identified = deferFulfillment(viewModel.context.$viewState) { $0.verificationState != nil }
        try await identified.fulfill()
        viewModel.context.send(viewAction: .appeared)

        #expect(viewModel.context.viewState.agentBlocksRead == .notRead)
        #expect(!service.listAgentBlocksOfContactCalled)
        #expect(!viewModel.context.viewState.showAgentBlocksSection)
    }

    @Test(arguments: SpiralAgentBlocksTests.ownAgents)
    func memberDetailsReadsNoBlocksOnYourOwnAgent(agentID: String) async throws {
        stubOwnAgents()
        let viewModel = makeMemberDetails(member: agentMember(agentID))

        // Both of the rule's inputs are known, and the identity is read after the member's.
        let known = deferFulfillment(viewModel.context.$viewState) { $0.agentProfile?.ownCard != nil && $0.verificationState != nil }
        try await known.fulfill()
        viewModel.context.send(viewAction: .appeared)

        #expect(viewModel.context.viewState.agentBlocksRead == .notRead)
        #expect(!service.listAgentBlocksOfContactCalled)
    }

    @Test
    func memberDetailsShowsTheBlocksOnAStrangersAgent() async throws {
        stubOwnAgents()
        let viewModel = makeMemberDetails(member: agentMember(Self.strangersAgent))

        let shown = deferFulfillment(viewModel.context.$viewState) { $0.showAgentBlocksSection }
        try await shown.fulfill()
        #expect(service.listAgentBlocksOfContactCallsCount == 1)
    }

    /// Confirmed first; on success the row goes, a toast says so, and the
    /// screen reads the blocks again.
    @Test
    func memberDetailsUnblocksAfterTheConfirmationAndReadsAgain() async throws {
        service.listAgentBlocksOfContactClosure = { [service] _ in service.unblockContactForAgentCalled ? .success([]) : .success([Self.ariaBlock]) }
        let viewModel = makeMemberDetails(member: .mockAlice)
        let shown = deferFulfillment(viewModel.context.$viewState) { $0.showAgentBlocksSection }
        try await shown.fulfill()

        viewModel.context.send(viewAction: .unblockAgent(agentID: Self.ariaBlock.agentID))
        let alert = try #require(viewModel.context.alertInfo)
        #expect(alert.id == .unblockAgent)
        #expect(alert.title == UntranslatedL10n.screenRoomMemberDetailsAgentUnblockAlertTitle("Alice", "Aria"))
        #expect(!service.unblockContactForAgentCalled)

        let gone = deferFulfillment(viewModel.context.$viewState) { $0.agentBlocks.isEmpty && $0.unblockingAgentID == nil }
        alert.primaryButton.action?()
        try await gone.fulfill()

        #expect(service.unblockContactForAgentReceivedArguments?.agentID == Self.ariaBlock.agentID)
        #expect(service.unblockContactForAgentReceivedArguments?.contactMXID == RoomMemberProxyMock.mockAlice.userID)
        #expect(service.listAgentBlocksOfContactCallsCount == 2, "read again")
        #expect(!viewModel.context.viewState.showAgentBlocksSection)
        let done = UntranslatedL10n.screenRoomMemberDetailsAgentUnblockDone("Aria")
        #expect(await eventually { userIndicatorController.submitIndicatorDelayReceivedInvocations.contains { $0.indicator.title == done } })
    }

    @Test
    func memberDetailsKeepsTheRowWhenTheUnblockFails() async throws {
        service.unblockContactForAgentReturnValue = .failure(.serverError(status: 500))
        let viewModel = makeMemberDetails(member: .mockAlice)
        let shown = deferFulfillment(viewModel.context.$viewState) { $0.showAgentBlocksSection }
        try await shown.fulfill()

        viewModel.context.send(viewAction: .unblockAgent(agentID: Self.ariaBlock.agentID))
        let finished = deferFulfillment(viewModel.context.$viewState.dropFirst()) { [service] in $0.unblockingAgentID == nil && service.unblockContactForAgentCalled }
        try #require(viewModel.context.alertInfo).primaryButton.action?()
        try await finished.fulfill()

        #expect(viewModel.context.viewState.agentBlocks == [Self.ariaBlock])
        let failed = UntranslatedL10n.screenRoomMemberDetailsAgentUnblockFailed
        #expect(await eventually { userIndicatorController.submitIndicatorDelayReceivedInvocations.contains { $0.indicator.title == failed } })
    }

    /// The button is disabled while the request is in flight, and a second
    /// tap asks nothing.
    @Test
    func memberDetailsTakesNoSecondUnblockWhileOneIsInFlight() async throws {
        let (release, releaser) = AsyncStream<Void>.makeStream()
        service.unblockContactForAgentClosure = { _, _ in
            for await _ in release {
                break
            }
            return .success(())
        }
        let viewModel = makeMemberDetails(member: .mockAlice)
        let shown = deferFulfillment(viewModel.context.$viewState) { $0.showAgentBlocksSection }
        try await shown.fulfill()

        viewModel.context.send(viewAction: .unblockAgent(agentID: Self.ariaBlock.agentID))
        let inFlight = deferFulfillment(viewModel.context.$viewState) { $0.unblockingAgentID == Self.ariaBlock.agentID }
        try #require(viewModel.context.alertInfo).primaryButton.action?()
        try await inFlight.fulfill()
        viewModel.context.alertInfo = nil

        viewModel.context.send(viewAction: .unblockAgent(agentID: Self.ariaBlock.agentID))

        #expect(viewModel.context.alertInfo == nil, "no second confirmation")
        #expect(service.unblockContactForAgentCallsCount == 1)
        let finished = deferFulfillment(viewModel.context.$viewState) { $0.unblockingAgentID == nil }
        releaser.yield()
        releaser.finish()
        try await finished.fulfill()
    }

    /// An agent's block is not Element's Block user (the Matrix ignore list):
    /// undoing it leaves an ignored person ignored.
    @Test
    func memberDetailsLeavesElementsBlockUserAlone() async throws {
        let clientProxy = ClientProxyMock(.init())
        let viewModel = makeMemberDetails(member: .mockIgnored, clientProxy: clientProxy)
        let shown = deferFulfillment(viewModel.context.$viewState) { $0.showAgentBlocksSection }
        try await shown.fulfill()

        viewModel.context.send(viewAction: .unblockAgent(agentID: Self.ariaBlock.agentID))
        let finished = deferFulfillment(viewModel.context.$viewState.dropFirst()) { [service] in $0.unblockingAgentID == nil && service.unblockContactForAgentCalled }
        try #require(viewModel.context.alertInfo).primaryButton.action?()
        try await finished.fulfill()

        #expect(viewModel.context.viewState.memberDetails?.isIgnored == true)
        #expect(!clientProxy.unignoreUserCalled)
        #expect(!clientProxy.ignoreUserCalled)
    }

    // MARK: - User profile

    @Test
    func userProfileShowsTheBlocksOnAPersonsProfile() async throws {
        let viewModel = makeUserProfile(userID: RoomMemberProxyMock.mockAlice.userID)

        let shown = deferFulfillment(viewModel.context.observe(\.viewState.showAgentBlocksSection)) { $0 }
        try await shown.fulfill()

        #expect(viewModel.context.viewState.agentBlocks == [Self.ariaBlock])
        #expect(service.listAgentBlocksOfContactReceivedContactMXID == RoomMemberProxyMock.mockAlice.userID)
    }

    @Test
    func userProfileReadsNoBlocksOnYourOwnProfile() async throws {
        let viewModel = makeUserProfile(userID: RoomMemberProxyMock.mockMe.userID)

        // The rule has decided before the identity is read, and a read it lets through is state at once.
        let identified = deferFulfillment(viewModel.context.observe(\.viewState.isVerified)) { $0 != nil }
        try await identified.fulfill()
        viewModel.context.send(viewAction: .appeared)

        #expect(viewModel.context.viewState.agentBlocksRead == .notRead)
        #expect(!service.listAgentBlocksOfContactCalled)
    }

    @Test(arguments: SpiralAgentBlocksTests.ownAgents)
    func userProfileReadsNoBlocksOnYourOwnAgent(agentID: String) async throws {
        stubOwnAgents()
        let viewModel = makeUserProfile(userID: agentID)

        let known = deferFulfillment(viewModel.context.observe(\.viewState.agentProfile?.ownCard)) { $0 != nil }
        try await known.fulfill()
        let identified = deferFulfillment(viewModel.context.observe(\.viewState.isVerified)) { $0 != nil }
        try await identified.fulfill()
        viewModel.context.send(viewAction: .appeared)

        #expect(viewModel.context.viewState.agentBlocksRead == .notRead)
        #expect(!service.listAgentBlocksOfContactCalled)
    }

    @Test
    func userProfileUnblocksAfterTheConfirmationAndReadsAgain() async throws {
        service.listAgentBlocksOfContactClosure = { [service] _ in service.unblockContactForAgentCalled ? .success([]) : .success([Self.ariaBlock]) }
        let viewModel = makeUserProfile(userID: RoomMemberProxyMock.mockAlice.userID)
        let shown = deferFulfillment(viewModel.context.observe(\.viewState.showAgentBlocksSection)) { $0 }
        try await shown.fulfill()

        viewModel.context.send(viewAction: .unblockAgent(agentID: Self.ariaBlock.agentID))
        let alert = try #require(viewModel.context.alertInfo)
        #expect(alert.id == .unblockAgent)
        #expect(alert.title == UntranslatedL10n.screenRoomMemberDetailsAgentUnblockAlertTitle("Alice", "Aria"))
        #expect(!service.unblockContactForAgentCalled)

        let gone = deferFulfillment(viewModel.context.observe(\.viewState.showAgentBlocksSection)) { !$0 }
        alert.primaryButton.action?()
        try await gone.fulfill()

        #expect(service.unblockContactForAgentReceivedArguments?.agentID == Self.ariaBlock.agentID)
        #expect(await eventually { service.listAgentBlocksOfContactCallsCount == 2 }, "read again")
        let done = UntranslatedL10n.screenRoomMemberDetailsAgentUnblockDone("Aria")
        #expect(await eventually { userIndicatorController.submitIndicatorDelayReceivedInvocations.contains { $0.indicator.title == done } })
    }

    @Test
    func userProfileKeepsTheRowWhenTheUnblockFails() async throws {
        service.unblockContactForAgentReturnValue = .failure(.notFound)
        let viewModel = makeUserProfile(userID: RoomMemberProxyMock.mockAlice.userID)
        let shown = deferFulfillment(viewModel.context.observe(\.viewState.showAgentBlocksSection)) { $0 }
        try await shown.fulfill()

        viewModel.context.send(viewAction: .unblockAgent(agentID: Self.ariaBlock.agentID))
        let finished = deferFulfillment(viewModel.context.observe(\.viewState.unblockingAgentID)) { [service] in $0 == nil && service.unblockContactForAgentCalled }
        try #require(viewModel.context.alertInfo).primaryButton.action?()
        try await finished.fulfill()

        #expect(viewModel.context.viewState.agentBlocks == [Self.ariaBlock])
        let failed = UntranslatedL10n.screenRoomMemberDetailsAgentUnblockFailed
        #expect(await eventually { userIndicatorController.submitIndicatorDelayReceivedInvocations.contains { $0.indicator.title == failed } })
    }

    @Test
    func userProfileTakesNoSecondUnblockWhileOneIsInFlight() async throws {
        let (release, releaser) = AsyncStream<Void>.makeStream()
        service.unblockContactForAgentClosure = { _, _ in
            for await _ in release {
                break
            }
            return .success(())
        }
        let viewModel = makeUserProfile(userID: RoomMemberProxyMock.mockAlice.userID)
        let shown = deferFulfillment(viewModel.context.observe(\.viewState.showAgentBlocksSection)) { $0 }
        try await shown.fulfill()

        viewModel.context.send(viewAction: .unblockAgent(agentID: Self.ariaBlock.agentID))
        let inFlight = deferFulfillment(viewModel.context.observe(\.viewState.unblockingAgentID)) { $0 == Self.ariaBlock.agentID }
        try #require(viewModel.context.alertInfo).primaryButton.action?()
        try await inFlight.fulfill()
        viewModel.context.alertInfo = nil

        viewModel.context.send(viewAction: .unblockAgent(agentID: Self.ariaBlock.agentID))

        #expect(viewModel.context.alertInfo == nil, "no second confirmation")
        #expect(service.unblockContactForAgentCallsCount == 1)
        let finished = deferFulfillment(viewModel.context.observe(\.viewState.unblockingAgentID)) { $0 == nil }
        releaser.yield()
        releaser.finish()
        try await finished.fulfill()
    }

    // MARK: - Reading again

    /// A failed read is never taken for "not blocked": the member's next load reads again.
    @Test
    func memberDetailsRetriesAFailedReadWhenTheMemberReloads() async throws {
        failTheFirstRead()
        let identityChanges = CurrentValueSubject<[IdentityStatusChange], Never>([])
        let viewModel = makeMemberDetails(member: .mockAlice, identityChanges: identityChanges)
        let failed = deferFulfillment(viewModel.context.$viewState) { $0.agentBlocksRead == .failed }
        try await failed.fulfill()
        #expect(!viewModel.context.viewState.showAgentBlocksSection)

        let shown = deferFulfillment(viewModel.context.$viewState) { $0.showAgentBlocksSection }
        identityChanges.send([IdentityStatusChange(userId: RoomMemberProxyMock.mockAlice.userID, changedTo: .pinned)])
        try await shown.fulfill()

        #expect(service.listAgentBlocksOfContactCallsCount == 2)
        #expect(viewModel.context.viewState.agentBlocksRead == .read)
    }

    @Test
    func memberDetailsRetriesAFailedReadWhenTheScreenReappears() async throws {
        failTheFirstRead()
        let viewModel = makeMemberDetails(member: .mockAlice)
        let failed = deferFulfillment(viewModel.context.$viewState) { $0.agentBlocksRead == .failed }
        try await failed.fulfill()

        let shown = deferFulfillment(viewModel.context.$viewState) { $0.showAgentBlocksSection }
        viewModel.context.send(viewAction: .appeared)
        try await shown.fulfill()

        #expect(service.listAgentBlocksOfContactCallsCount == 2)
    }

    /// A block set or lifted while the screen was covered shows when it comes back.
    @Test
    func memberDetailsReadsAgainWhenTheScreenReappears() async throws {
        service.listAgentBlocksOfContactClosure = { [service] _ in service.listAgentBlocksOfContactCallsCount == 1 ? .success([]) : .success([Self.ariaBlock]) }
        let viewModel = makeMemberDetails(member: .mockAlice)
        let read = deferFulfillment(viewModel.context.$viewState) { $0.agentBlocksRead == .read }
        try await read.fulfill()
        #expect(!viewModel.context.viewState.showAgentBlocksSection)

        let shown = deferFulfillment(viewModel.context.$viewState) { $0.showAgentBlocksSection }
        viewModel.context.send(viewAction: .appeared)
        try await shown.fulfill()
    }

    /// A read again that fails keeps what the last good read showed.
    @Test
    func memberDetailsKeepsTheRowsWhenAReadAgainFails() async throws {
        service.listAgentBlocksOfContactClosure = { [service] _ in
            service.listAgentBlocksOfContactCallsCount == 1 ? .success([Self.ariaBlock]) : .failure(.serverError(status: 500))
        }
        let viewModel = makeMemberDetails(member: .mockAlice)
        let read = deferFulfillment(viewModel.context.$viewState) { $0.agentBlocksRead == .read }
        try await read.fulfill()

        let failed = deferFulfillment(viewModel.context.$viewState) { $0.agentBlocksRead == .failed }
        viewModel.context.send(viewAction: .appeared)
        try await failed.fulfill()

        #expect(viewModel.context.viewState.agentBlocks == [Self.ariaBlock])
        #expect(viewModel.context.viewState.showAgentBlocksSection)
    }

    @Test
    func userProfileRetriesAFailedReadWhenTheScreenReappears() async throws {
        failTheFirstRead()
        let viewModel = makeUserProfile(userID: RoomMemberProxyMock.mockAlice.userID)
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.agentBlocksRead)) { $0 == .failed }
        try await failed.fulfill()
        #expect(!viewModel.context.viewState.showAgentBlocksSection)

        let shown = deferFulfillment(viewModel.context.observe(\.viewState.showAgentBlocksSection)) { $0 }
        viewModel.context.send(viewAction: .appeared)
        try await shown.fulfill()

        #expect(service.listAgentBlocksOfContactCallsCount == 2)
    }

    @Test
    func userProfileReadsAgainWhenTheScreenReappears() async throws {
        service.listAgentBlocksOfContactClosure = { [service] _ in service.listAgentBlocksOfContactCallsCount == 1 ? .success([]) : .success([Self.ariaBlock]) }
        let viewModel = makeUserProfile(userID: RoomMemberProxyMock.mockAlice.userID)
        let read = deferFulfillment(viewModel.context.observe(\.viewState.agentBlocksRead)) { $0 == .read }
        try await read.fulfill()
        #expect(!viewModel.context.viewState.showAgentBlocksSection)

        let shown = deferFulfillment(viewModel.context.observe(\.viewState.showAgentBlocksSection)) { $0 }
        viewModel.context.send(viewAction: .appeared)
        try await shown.fulfill()
    }

    @Test
    func userProfileKeepsTheRowsWhenAReadAgainFails() async throws {
        service.listAgentBlocksOfContactClosure = { [service] _ in
            service.listAgentBlocksOfContactCallsCount == 1 ? .success([Self.ariaBlock]) : .failure(.serverError(status: 500))
        }
        let viewModel = makeUserProfile(userID: RoomMemberProxyMock.mockAlice.userID)
        let read = deferFulfillment(viewModel.context.observe(\.viewState.agentBlocksRead)) { $0 == .read }
        try await read.fulfill()

        let failed = deferFulfillment(viewModel.context.observe(\.viewState.agentBlocksRead)) { $0 == .failed }
        viewModel.context.send(viewAction: .appeared)
        try await failed.fulfill()

        #expect(viewModel.context.viewState.agentBlocks == [Self.ariaBlock])
        #expect(viewModel.context.viewState.showAgentBlocksSection)
    }

    /// Two appearances while a read is out start no second read.
    @Test
    func memberDetailsReadsOnceForTwoAppearancesDuringARead() async throws {
        let gate = Gate()
        service.listAgentBlocksOfContactClosure = { _ in
            await gate.wait()
            return .success([Self.ariaBlock])
        }
        let viewModel = makeMemberDetails(member: .mockAlice)
        let reading = deferFulfillment(viewModel.context.$viewState) { $0.agentBlocksRead == .reading }
        try await reading.fulfill()

        viewModel.context.send(viewAction: .appeared)
        viewModel.context.send(viewAction: .appeared)
        let read = deferFulfillment(viewModel.context.$viewState) { $0.agentBlocksRead == .read }
        await gate.open()
        try await read.fulfill()

        #expect(service.listAgentBlocksOfContactCallsCount == 1)
    }

    /// A read that went out before an Unblock's 204 and lands after the read
    /// that followed it is ignored: the row stays gone.
    @Test
    func memberDetailsIgnoresAReadThatWentOutBeforeTheUnblock() async throws {
        let gate = Gate()
        holdTheSecondRead(at: gate)
        let viewModel = makeMemberDetails(member: .mockAlice)
        let shown = deferFulfillment(viewModel.context.$viewState) { $0.agentBlocksRead == .read && $0.showAgentBlocksSection }
        try await shown.fulfill()

        viewModel.context.send(viewAction: .appeared)
        #expect(await eventually { service.listAgentBlocksOfContactCallsCount == 2 })
        viewModel.context.send(viewAction: .unblockAgent(agentID: Self.ariaBlock.agentID))
        // Values only: the current state, emitted on subscribing, must not pass.
        let unblocked = deferFulfillment(viewModel.context.$viewState.dropFirst()) { $0.unblockingAgentID == nil && $0.agentBlocks.isEmpty }
        try #require(viewModel.context.alertInfo).primaryButton.action?()
        try await unblocked.fulfill()
        #expect(service.listAgentBlocksOfContactCallsCount == 3)
        #expect(viewModel.context.viewState.agentBlocks.isEmpty)
        #expect(viewModel.context.viewState.agentBlocksRead == .reading, "the earlier read is still out")

        let settled = deferFulfillment(viewModel.context.$viewState) { $0.agentBlocksRead == .read }
        await gate.open()
        try await settled.fulfill()

        #expect(viewModel.context.viewState.agentBlocks.isEmpty, "the row stays gone")
        #expect(!viewModel.context.viewState.showAgentBlocksSection)
    }

    /// A failed read of the person's own agents is read again on reappearing,
    /// so it never hides the erase and the blocks for the screen's life.
    @Test
    func memberDetailsRetriesAFailedOwnAgentsReadWhenTheScreenReappears() async throws {
        stubOwnAgents(failingFirst: true)
        let viewModel = makeMemberDetails(member: agentMember(Self.strangersAgent))
        let failed = deferFulfillment(viewModel.context.$viewState) { $0.memberDetails != nil && $0.agentOwnership == .unknown(isReading: false) }
        try await failed.fulfill()
        #expect(!viewModel.context.viewState.showEraseAssistantMemorySection)

        let shown = deferFulfillment(viewModel.context.$viewState) { $0.showAgentBlocksSection }
        viewModel.context.send(viewAction: .appeared)
        try await shown.fulfill()

        #expect(service.listMyAgentSpacesCallsCount == 2)
        #expect(viewModel.context.viewState.showEraseAssistantMemorySection)
    }

    @Test
    func userProfileReadsOnceForTwoAppearancesDuringARead() async throws {
        let gate = Gate()
        service.listAgentBlocksOfContactClosure = { _ in
            await gate.wait()
            return .success([Self.ariaBlock])
        }
        let viewModel = makeUserProfile(userID: RoomMemberProxyMock.mockAlice.userID)
        let reading = deferFulfillment(viewModel.context.observe(\.viewState.agentBlocksRead)) { $0 == .reading }
        try await reading.fulfill()

        viewModel.context.send(viewAction: .appeared)
        viewModel.context.send(viewAction: .appeared)
        let read = deferFulfillment(viewModel.context.observe(\.viewState.agentBlocksRead)) { $0 == .read }
        await gate.open()
        try await read.fulfill()

        #expect(service.listAgentBlocksOfContactCallsCount == 1)
    }

    @Test
    func userProfileIgnoresAReadThatWentOutBeforeTheUnblock() async throws {
        let gate = Gate()
        holdTheSecondRead(at: gate)
        let viewModel = makeUserProfile(userID: RoomMemberProxyMock.mockAlice.userID)
        let shown = deferFulfillment(viewModel.context.observe(\.viewState.showAgentBlocksSection)) { $0 }
        try await shown.fulfill()
        let read = deferFulfillment(viewModel.context.observe(\.viewState.agentBlocksRead)) { $0 == .read }
        try await read.fulfill()

        viewModel.context.send(viewAction: .appeared)
        #expect(await eventually { service.listAgentBlocksOfContactCallsCount == 2 })
        viewModel.context.send(viewAction: .unblockAgent(agentID: Self.ariaBlock.agentID))
        let unblocked = deferFulfillment(viewModel.context.observe(\.viewState.unblockingAgentID)) { [service] in $0 == nil && service.unblockContactForAgentCalled }
        try #require(viewModel.context.alertInfo).primaryButton.action?()
        try await unblocked.fulfill()
        #expect(service.listAgentBlocksOfContactCallsCount == 3)
        #expect(viewModel.context.viewState.agentBlocks.isEmpty)
        #expect(viewModel.context.viewState.agentBlocksRead == .reading, "the earlier read is still out")

        let settled = deferFulfillment(viewModel.context.observe(\.viewState.agentBlocksRead)) { $0 == .read }
        await gate.open()
        try await settled.fulfill()

        #expect(viewModel.context.viewState.agentBlocks.isEmpty, "the row stays gone")
        #expect(!viewModel.context.viewState.showAgentBlocksSection)
    }

    @Test
    func userProfileRetriesAFailedOwnAgentsReadWhenTheScreenReappears() async throws {
        stubOwnAgents(failingFirst: true)
        let viewModel = makeUserProfile(userID: Self.strangersAgent)
        let profile = deferFulfillment(viewModel.context.observe(\.viewState.userProfile)) { $0 != nil }
        try await profile.fulfill()
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.agentOwnership)) { $0 == .unknown(isReading: false) }
        try await failed.fulfill()
        #expect(!viewModel.context.viewState.showEraseAssistantMemorySection)

        let shown = deferFulfillment(viewModel.context.observe(\.viewState.showAgentBlocksSection)) { $0 }
        viewModel.context.send(viewAction: .appeared)
        try await shown.fulfill()

        #expect(service.listMyAgentSpacesCallsCount == 2)
        #expect(viewModel.context.viewState.showEraseAssistantMemorySection)
    }

    // MARK: - Helpers

    /// The first read finds Aria's block; the second, on reappearing, was
    /// answered before the Unblock's DELETE and finds it too, but lands only
    /// once the gate opens; every later read comes after the 204.
    private func holdTheSecondRead(at gate: Gate) {
        service.listAgentBlocksOfContactClosure = { [service] _ in
            switch service.listAgentBlocksOfContactCallsCount {
            case 1:
                return .success([Self.ariaBlock])
            case 2:
                await gate.wait()
                return .success([Self.ariaBlock])
            default:
                return .success([])
            }
        }
    }

    /// The first read fails; every later one finds Aria's block.
    private func failTheFirstRead() {
        service.listAgentBlocksOfContactClosure = { [service] _ in
            service.listAgentBlocksOfContactCallsCount == 1 ? .failure(.serverError(status: 500)) : .success([Self.ariaBlock])
        }
    }

    nonisolated static let ownAssistant = "@assistant-me:matrix.org"
    nonisolated static let ownCompanyAgent = "@agent-acme-1:matrix.org"
    nonisolated static let strangersAgent = "@assistant-bob:matrix.org"
    /// The person's own agents as the app knows them: no company agent while companies are hidden (396).
    nonisolated static let ownAgents = SpiralFeatures.companySpaces ? [ownAssistant, ownCompanyAgent] : [ownAssistant]

    /// The person's Personal space holds their assistant, their company space a company agent.
    private func stubOwnAgents(failingFirst: Bool = false) {
        let directory = AgentSpacesDirectory(spaces: [.init(orgID: "solo", name: "Personal", kind: .solo, avatarMXC: nil, agentCount: 1),
                                                      .init(orgID: "acme", name: "Acme", kind: .company, avatarMXC: nil, agentCount: 1)],
                                             provisioningStatus: .ready)
        service.listMyAgentSpacesClosure = { [service] in
            failingFirst && service.listMyAgentSpacesCallsCount == 1 ? .failure(.serverError(status: 500)) : .success(directory)
        }
        service.fetchAgentSpaceOrgIDClosure = { orgID in
            let mxid = orgID == "solo" ? Self.ownAssistant : Self.ownCompanyAgent
            let card = AgentSpaceAgentCard(agentID: "agent-\(orgID)", matrixUserID: mxid, displayName: "Agent", avatarMXC: nil,
                                           kind: orgID == "solo" ? "personal_assistant" : "sales", visibility: "public",
                                           lifecycleState: "active", roomCount: 0, activeToolCount: 0)
            return .success(.init(orgID: orgID, name: orgID, kind: orgID == "solo" ? .solo : .company,
                                  avatarMXC: nil, industry: nil, website: nil, agents: [card]))
        }
    }

    private func agentMember(_ userID: String) -> RoomMemberProxyMock {
        RoomMemberProxyMock(with: .init(userID: userID, displayName: "Assistant", membership: .join))
    }

    private func makeMemberDetails(member: RoomMemberProxyMock, clientProxy: ClientProxyMock = ClientProxyMock(.init()),
                                   identityChanges: CurrentValueSubject<[IdentityStatusChange], Never>? = nil) -> RoomMemberDetailsScreenViewModel {
        let roomProxy = JoinedRoomProxyMock(.init(name: ""))
        roomProxy.getMemberUserIDClosure = { _ in .success(member) }
        if let identityChanges {
            roomProxy.identityStatusChangesPublisher = identityChanges.asCurrentValuePublisher()
        }
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        userSession.agentPlatformService = service
        userSession.agentsStore = AgentsStore(service: service)
        return RoomMemberDetailsScreenViewModel(userID: member.userID,
                                                roomProxy: roomProxy,
                                                userSession: userSession,
                                                analytics: AnalyticsServiceMock(.init()),
                                                userIndicatorController: userIndicatorController)
    }

    private func makeUserProfile(userID: String) -> UserProfileScreenViewModel {
        let clientProxy = ClientProxyMock(.init())
        clientProxy.profileForReturnValue = .success(UserProfile(userID: userID, displayName: userID == RoomMemberProxyMock.mockAlice.userID ? "Alice" : "Me"))
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        userSession.agentPlatformService = service
        userSession.agentsStore = AgentsStore(service: service)
        return UserProfileScreenViewModel(userID: userID,
                                          isPresentedModally: false,
                                          userSession: userSession,
                                          analytics: AnalyticsServiceMock(.init()),
                                          userIndicatorController: userIndicatorController)
    }

    /// Polls for up to three seconds.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<60 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    nonisolated static let ariaBlock = AgentContactBlock(agentID: "agent-aria", agentMXID: "@assistant-me:matrix.org",
                                                         agentName: "Aria", blockedAt: Date(timeIntervalSince1970: 1_791_709_200))
}

/// Holds every read that waits on it until it opens.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}
