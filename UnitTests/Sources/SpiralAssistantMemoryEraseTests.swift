//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0078, ADR-0019 Principle 5): erasing what a person's
// assistant remembers about one contact, from that contact's profile —
// confirmed first, then `DELETE /me/memory`, then a toast that says what went.
//

@testable import ElementX
import Foundation
import Testing

@MainActor
struct SpiralAssistantMemoryEraseTests {
    let service = AgentPlatformServiceMock()
    let userIndicatorController = UserIndicatorControllerMock()

    init() {
        service.eraseAssistantMemoryAboutContactReturnValue = .success(.counts(memoryEntries: 2))
        // The same profiles read the agents' blocks (decision 87).
        service.listAgentBlocksOfContactReturnValue = .success([])
    }

    // MARK: - What the person is told

    /// The erase reaches every agent and far more than notes; the person is
    /// told it worked whenever anything about the contact went, and only
    /// "nothing" when every count is zero.
    @Test(arguments: [(Result<ContactErasure, AgentPlatformError>.success(.counts(memoryEntries: 3)), AssistantMemoryEraser.Outcome.erased),
                      (.success(.counts(transcriptLines: 7)), .erased),
                      (.success(.counts(toolScopesRewritten: 1)), .erased),
                      (.success(.nothing), .nothingSaved),
                      (.failure(.validation(detail: "your own account and your own agents are not contacts")), .refused),
                      (.failure(.notFound), .failed),
                      (.failure(.serverError(status: 500)), .failed)])
    func outcomeFollowsTheServer(response: Result<ContactErasure, AgentPlatformError>, expected: AssistantMemoryEraser.Outcome) async {
        service.eraseAssistantMemoryAboutContactReturnValue = response
        let eraser = AssistantMemoryEraser(agentPlatformService: service, userIndicatorController: userIndicatorController)

        let outcome = await eraser.erase(contactMXID: "@bob:spiral.md", contactName: "Bob")

        #expect(outcome == expected)
        #expect(service.eraseAssistantMemoryAboutContactReceivedContactMXID == "@bob:spiral.md")
        let toast = userIndicatorController.submitIndicatorDelayReceivedArguments?.indicator.title
        switch expected {
        case .erased: #expect(toast == UntranslatedL10n.screenRoomMemberDetailsEraseAssistantMemoryDone("Bob"))
        case .nothingSaved: #expect(toast == UntranslatedL10n.screenRoomMemberDetailsEraseAssistantMemoryNothing("Bob"))
        case .refused: #expect(toast == UntranslatedL10n.screenRoomMemberDetailsEraseAssistantMemoryRefused)
        case .failed: #expect(toast == UntranslatedL10n.screenRoomMemberDetailsEraseAssistantMemoryFailed)
        }
    }

    @Test
    func confirmationIsDestructiveAndSaysWhatGoes() throws {
        let eraser = AssistantMemoryEraser(agentPlatformService: service, userIndicatorController: userIndicatorController)
        let alert = eraser.confirmation(id: "erase", contactName: "Bob") { }

        #expect(alert.title == UntranslatedL10n.screenRoomMemberDetailsEraseAssistantMemoryAlertTitle("Bob"))
        #expect(alert.message == UntranslatedL10n.screenRoomMemberDetailsEraseAssistantMemoryAlertMessage("Bob"))
        #expect(alert.primaryButton.role == .destructive)
        #expect(try #require(alert.secondaryButton).role == .cancel)
    }

    // MARK: - Room member details

    @Test
    func memberDetailsOffersTheEraseForASpiralAccountOnly() async throws {
        let withAssistant = makeMemberDetails(member: .mockAlice, hasAssistant: true)
        try await waitForMember(withAssistant)
        #expect(withAssistant.context.viewState.showEraseAssistantMemorySection)

        let ownProfile = makeMemberDetails(member: .mockMe, hasAssistant: true)
        try await waitForMember(ownProfile)
        #expect(!ownProfile.context.viewState.showEraseAssistantMemorySection)

        let withoutAssistant = makeMemberDetails(member: .mockAlice, hasAssistant: false)
        try await waitForMember(withoutAssistant)
        #expect(!withoutAssistant.context.viewState.showEraseAssistantMemorySection)
    }

    @Test
    func memberDetailsErasesOnlyAfterTheConfirmation() async throws {
        let viewModel = makeMemberDetails(member: .mockAlice, hasAssistant: true)
        try await waitForMember(viewModel)

        viewModel.context.send(viewAction: .eraseAssistantMemory)
        let alert = try #require(viewModel.context.alertInfo)
        #expect(alert.id == .eraseAssistantMemory)
        #expect(alert.title == UntranslatedL10n.screenRoomMemberDetailsEraseAssistantMemoryAlertTitle("Alice"))
        #expect(!service.eraseAssistantMemoryAboutContactCalled)

        alert.primaryButton.action?()

        // Waits on the toast itself: a view state published before the erase
        // ended can arrive after the call started, so it proves nothing. The
        // screen's own «Loading…» indicator may come and go around it.
        let done = UntranslatedL10n.screenRoomMemberDetailsEraseAssistantMemoryDone("Alice")
        #expect(await eventually { userIndicatorController.submitIndicatorDelayReceivedInvocations.contains { $0.indicator.title == done } })
        #expect(service.eraseAssistantMemoryAboutContactReceivedContactMXID == RoomMemberProxyMock.mockAlice.userID)
    }

    // MARK: - Agents' profiles

    @Test
    func memberDetailsOffersTheEraseOnAStrangersAgent() async throws {
        stubOwnAgents()
        let viewModel = makeMemberDetails(member: agentMember(Self.strangersAgent), hasAssistant: true)

        let offered = deferFulfillment(viewModel.context.$viewState) { $0.showEraseAssistantMemorySection }
        try await offered.fulfill()
    }

    @Test(arguments: [SpiralAssistantMemoryEraseTests.ownAssistant, SpiralAssistantMemoryEraseTests.ownCompanyAgent])
    func memberDetailsOffersNoEraseOnTheirOwnAgent(agentID: String) async throws {
        stubOwnAgents()
        let viewModel = makeMemberDetails(member: agentMember(agentID), hasAssistant: true)

        let known = deferFulfillment(viewModel.context.$viewState) { $0.memberDetails != nil && $0.ownAgentMXIDs != nil }
        try await known.fulfill()
        #expect(!viewModel.context.viewState.showEraseAssistantMemorySection)
    }

    @Test
    func anAgentsProfileOffersNoEraseUntilTheirOwnAgentsAreKnown() async throws {
        stubOwnAgents()
        service.fetchAgentSpaceOrgIDClosure = { _ in .failure(.serverError(status: 500)) }
        let viewModel = makeMemberDetails(member: agentMember(Self.strangersAgent), hasAssistant: true)
        try await waitForMember(viewModel)
        try await Task.sleep(for: .milliseconds(200))

        #expect(service.fetchAgentSpaceOrgIDCalled)
        #expect(viewModel.context.viewState.ownAgentMXIDs == nil)
        #expect(!viewModel.context.viewState.showEraseAssistantMemorySection)
    }

    @Test
    func aPersonsProfileNeedsNoAgentList() async throws {
        let viewModel = makeMemberDetails(member: .mockAlice, hasAssistant: true)
        try await waitForMember(viewModel)

        #expect(viewModel.context.viewState.showEraseAssistantMemorySection)
        #expect(!service.listMyAgentSpacesCalled)
    }

    @Test
    func ownAgentsComeFromEverySpace() async {
        stubOwnAgents()
        let eraser = AssistantMemoryEraser(agentPlatformService: service, userIndicatorController: userIndicatorController)

        #expect(await eraser.ownAgentMXIDs() == [Self.ownAssistant, Self.ownCompanyAgent])
        #expect(Set(service.fetchAgentSpaceOrgIDReceivedInvocations) == ["solo", "acme"])
    }

    // MARK: - User profile

    @Test
    func userProfileErasesOnlyAfterTheConfirmation() async throws {
        let viewModel = makeUserProfile(userID: RoomMemberProxyMock.mockAlice.userID, hasAssistant: true)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.showEraseAssistantMemorySection)) { $0 }
        try await loaded.fulfill()

        viewModel.context.send(viewAction: .eraseAssistantMemory)
        let alert = try #require(viewModel.context.alertInfo)
        #expect(alert.id == .eraseAssistantMemory)
        #expect(!service.eraseAssistantMemoryAboutContactCalled)

        let finished = deferFulfillment(viewModel.context.observe(\.viewState.isErasingAssistantMemory)) { !$0 && service.eraseAssistantMemoryAboutContactCalled }
        alert.primaryButton.action?()
        try await finished.fulfill()

        #expect(service.eraseAssistantMemoryAboutContactReceivedContactMXID == RoomMemberProxyMock.mockAlice.userID)
    }

    @Test
    func userProfileOffersNoEraseOnYourOwnProfileOrWithoutAnAssistant() async throws {
        let own = makeUserProfile(userID: RoomMemberProxyMock.mockMe.userID, hasAssistant: true)
        let ownLoaded = deferFulfillment(own.context.observe(\.viewState.userProfile)) { $0 != nil }
        try await ownLoaded.fulfill()
        #expect(!own.context.viewState.showEraseAssistantMemorySection)

        let other = makeUserProfile(userID: RoomMemberProxyMock.mockAlice.userID, hasAssistant: false)
        let otherLoaded = deferFulfillment(other.context.observe(\.viewState.userProfile)) { $0 != nil }
        try await otherLoaded.fulfill()
        #expect(!other.context.viewState.showEraseAssistantMemorySection)
    }

    @Test
    func userProfileOffersTheEraseOnAStrangersAgent() async throws {
        stubOwnAgents()
        let viewModel = makeUserProfile(userID: Self.strangersAgent, hasAssistant: true)

        let offered = deferFulfillment(viewModel.context.observe(\.viewState.showEraseAssistantMemorySection)) { $0 }
        try await offered.fulfill()
    }

    @Test(arguments: [SpiralAssistantMemoryEraseTests.ownAssistant, SpiralAssistantMemoryEraseTests.ownCompanyAgent])
    func userProfileOffersNoEraseOnTheirOwnAgent(agentID: String) async throws {
        stubOwnAgents()
        let viewModel = makeUserProfile(userID: agentID, hasAssistant: true)

        let known = deferFulfillment(viewModel.context.observe(\.viewState.ownAgentMXIDs)) { $0 != nil }
        try await known.fulfill()
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.userProfile)) { $0 != nil }
        try await loaded.fulfill()
        #expect(!viewModel.context.viewState.showEraseAssistantMemorySection)
    }

    // MARK: - Helpers

    nonisolated static let ownAssistant = "@assistant-me:matrix.org"
    nonisolated static let ownCompanyAgent = "@agent-acme-1:matrix.org"
    nonisolated static let strangersAgent = "@assistant-bob:matrix.org"

    /// The person's Personal space holds their assistant, their company space a company agent.
    private func stubOwnAgents() {
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [.init(orgID: "solo", name: "Personal", kind: .solo, avatarMXC: nil, agentCount: 1),
                                                                       .init(orgID: "acme", name: "Acme", kind: .company, avatarMXC: nil, agentCount: 1)],
                                                              provisioningStatus: .ready))
        service.fetchAgentSpaceOrgIDClosure = { orgID in
            let mxid = orgID == "solo" ? Self.ownAssistant : Self.ownCompanyAgent
            let card = AgentSpaceAgentCard(agentID: "agent-\(orgID)", matrixUserID: mxid, displayName: "Agent", avatarMXC: nil,
                                           kind: orgID == "solo" ? "personal_assistant" : "sales", visibility: "public",
                                           lifecycleState: "active", presence: .online, roomCount: 0, activeToolCount: 0)
            return .success(.init(orgID: orgID, name: orgID, kind: orgID == "solo" ? .solo : .company,
                                  avatarMXC: nil, industry: nil, website: nil, agents: [card]))
        }
    }

    /// Polls for up to three seconds.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<60 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    private func agentMember(_ userID: String) -> RoomMemberProxyMock {
        RoomMemberProxyMock(with: .init(userID: userID, displayName: "Assistant", membership: .join))
    }

    private func makeMemberDetails(member: RoomMemberProxyMock, hasAssistant: Bool) -> RoomMemberDetailsScreenViewModel {
        let roomProxy = JoinedRoomProxyMock(.init(name: ""))
        roomProxy.getMemberUserIDClosure = { _ in .success(member) }
        let userSession = UserSessionMock(.init())
        userSession.agentPlatformService = hasAssistant ? service : nil
        return RoomMemberDetailsScreenViewModel(userID: member.userID,
                                                roomProxy: roomProxy,
                                                userSession: userSession,
                                                userIndicatorController: userIndicatorController,
                                                analytics: AnalyticsServiceMock(.init()))
    }

    private func waitForMember(_ viewModel: RoomMemberDetailsScreenViewModel) async throws {
        let loaded = deferFulfillment(viewModel.context.$viewState) { $0.memberDetails != nil }
        try await loaded.fulfill()
    }

    private func makeUserProfile(userID: String, hasAssistant: Bool) -> UserProfileScreenViewModel {
        let clientProxy = ClientProxyMock(.init())
        clientProxy.profileForReturnValue = .success(UserProfile(userID: userID, displayName: userID == RoomMemberProxyMock.mockAlice.userID ? "Alice" : "Me"))
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        userSession.agentPlatformService = hasAssistant ? service : nil
        return UserProfileScreenViewModel(userID: userID,
                                          isPresentedModally: false,
                                          userSession: userSession,
                                          userIndicatorController: userIndicatorController,
                                          analytics: AnalyticsServiceMock(.init()))
    }
}

nonisolated extension ContactErasure {
    /// An erasure with the given counts and zero for the rest.
    static func counts(memoryEntries: Int = 0, transcriptLines: Int = 0, toolScopesRewritten: Int = 0) -> ContactErasure {
        ContactErasure(memoryEntries: memoryEntries, relationships: 0, transcriptLines: transcriptLines, outreachTargets: 0,
                       approvals: 0, keyRelayRows: 0, verifications: 0, actionLogEntriesScrubbed: 0,
                       sessionControlsScrubbed: 0, inviteRedemptionsScrubbed: 0,
                       toolScopesRewritten: toolScopesRewritten, toolsTurnedOff: 0)
    }
}
