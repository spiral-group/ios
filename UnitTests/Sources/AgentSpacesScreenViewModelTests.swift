//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Brief 0037 — Agents tab rebuilt on the Spaces model.
// Tests for the tab root: one list, a section per space (step B). With
// companies hidden (question 396) the list is the Personal space alone.
//

import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct AgentSpacesScreenViewModelTests {
    // MARK: - Helpers
    
    private static let personalSpace = AgentSpaceSummary(orgID: "org-personal",
                                                         name: "Personal",
                                                         kind: .solo,
                                                         avatarMXC: nil,
                                                         agentCount: 1)
    
    private static let companySpace = AgentSpaceSummary(orgID: "org-acme",
                                                        name: "Acme Corp",
                                                        kind: .company,
                                                        avatarMXC: "mxc://host/logo",
                                                        agentCount: 3)
    
    private static let assistant = AgentSpaceAgentCard(agentID: "agent-1", matrixUserID: "@assistant-owner:spiral.md",
                                                       displayName: "Assistant", avatarMXC: nil, kind: "personal_assistant",
                                                       visibility: "public", lifecycleState: "active", roomCount: 2, activeToolCount: 1)
    
    private static let salesAgent = AgentSpaceAgentCard(agentID: "agent-2", matrixUserID: "@agent-acme-sales:spiral.md",
                                                        displayName: "Sales · Acme Corp", avatarMXC: nil, kind: "sales",
                                                        visibility: "public", lifecycleState: "active", roomCount: 1, activeToolCount: 0)
    
    private static func detail(_ space: AgentSpaceSummary) -> AgentSpaceDetail {
        AgentSpaceDetail(orgID: space.orgID, name: space.name, kind: space.kind, avatarMXC: space.avatarMXC,
                         industry: nil, website: nil,
                         agents: space.kind == .solo ? [assistant] : [salesAgent])
    }
    
    /// The sections a read of these spaces shows.
    private static func loaded(_ spaces: [AgentSpaceSummary]) -> AgentSpacesScreenListState {
        .loaded(spaces.map { AgentSpaceSection(summary: $0, content: .loaded(detail($0))) })
    }
    
    private func makeViewModel(service: AgentPlatformServiceMock, store: AgentsStore? = nil) -> AgentSpacesScreenViewModel {
        if service.fetchAgentSpaceOrgIDClosure == nil {
            service.fetchAgentSpaceOrgIDClosure = { orgID in
                .success(Self.detail(orgID == Self.personalSpace.orgID ? Self.personalSpace : Self.companySpace))
            }
        }
        return AgentSpacesScreenViewModel(userSession: UserSessionMock(.init(clientProxy: ClientProxyMock(.init(userID: "@owner:spiral.md")))),
                                          store: store ?? AgentsStore(service: service))
    }
    
    // MARK: - Loading
    
    /// Question 396: a company an older account still has is neither read nor shown.
    @Test
    func initialLoad_showsThePersonalSpaceAlone() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace, Self.companySpace],
                                                              provisioningStatus: .ready))
        
        let viewModel = makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            state == Self.loaded([Self.personalSpace])
        }
        try await deferred.fulfill()
        
        #expect(service.listMyAgentSpacesCallsCount == 1)
        #expect(service.fetchAgentSpaceOrgIDReceivedInvocations == [Self.personalSpace.orgID])
    }
    
    @Test
    func initialLoad_failure_showsFailureState() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .failure(.serverError(status: 500))
        
        let viewModel = makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == .failure }
        try await deferred.fulfill()
    }
    
    @Test
    func initialLoad_emptyAndProvisioning_showsProvisioningState() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [], provisioningStatus: .inProgress))
        
        let viewModel = makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == .provisioning }
        try await deferred.fulfill()
    }

    /// A ready directory without spaces says the assistant is on its way.
    @Test
    func aReadyDirectoryWithoutSpacesIsNotBlank() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [], provisioningStatus: .ready))

        let viewModel = makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == .loaded([]) }
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.hasNoSpaces)
    }

    /// A Personal space without its assistant says so.
    @Test
    func aPersonalSpaceWithoutItsAssistantSaysSo() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace, Self.companySpace], provisioningStatus: .ready))
        service.fetchAgentSpaceOrgIDClosure = { orgID in
            let space = orgID == Self.personalSpace.orgID ? Self.personalSpace : Self.companySpace
            return .success(AgentSpaceDetail(orgID: space.orgID, name: space.name, kind: space.kind, avatarMXC: nil,
                                             industry: nil, website: nil, agents: []))
        }

        let viewModel = makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { if case .loaded = $0 { true } else { false } }
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.sections.map(\.isAssistantPending) == [true])
        #expect(!viewModel.context.viewState.hasNoSpaces)
    }

    @Test
    func retryAfterFailure_reloads() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .failure(.serverError(status: 500))
        
        let viewModel = makeViewModel(service: service)
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == .failure }
        try await failed.fulfill()
        
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace],
                                                              provisioningStatus: .ready))
        
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == Self.loaded([Self.personalSpace]) }
        viewModel.context.send(viewAction: .retry)
        try await loaded.fulfill()
    }
    
    /// A read the stream asked for that fails must not blank the visible list.
    @Test
    func aFailedRereadKeepsTheRows() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace],
                                                              provisioningStatus: .ready))
        let store = AgentsStore(service: service)
        
        let viewModel = makeViewModel(service: service, store: store)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == Self.loaded([Self.personalSpace]) }
        try await loaded.fulfill()
        
        service.listMyAgentSpacesReturnValue = .failure(.transport(underlying: URLError(.notConnectedToInternet)))
        store.apply([.spaceUpdated(spaceID: Self.personalSpace.orgID)])
        await store.settle()
        
        #expect(service.listMyAgentSpacesCallsCount == 2)
        #expect(viewModel.context.viewState.listState == Self.loaded([Self.personalSpace]))
    }
    
    /// Coverage walk F4, now by the stream: a space change is read again with the rows kept, and a company it
    /// brings stays hidden (396).
    @Test
    func aCompanyFromTheStreamStaysHidden() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace], provisioningStatus: .ready))
        let store = AgentsStore(service: service)
        
        let viewModel = makeViewModel(service: service, store: store)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == Self.loaded([Self.personalSpace]) }
        try await loaded.fulfill()
        
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace, Self.companySpace], provisioningStatus: .ready))
        store.apply([.spaceUpdated(spaceID: Self.companySpace.orgID)])
        await store.settle()
        
        #expect(service.listMyAgentSpacesCallsCount == 2)
        #expect(viewModel.context.viewState.listState == Self.loaded([Self.personalSpace]))
    }
    
    /// The Personal space's provisioning ends with its assistant's row, which
    /// the stream says (`agent.updated` on insert): nothing polls meanwhile.
    @Test
    func provisioningEndsByTheStreamNotByAPoll() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [], provisioningStatus: .inProgress))
        let store = AgentsStore(service: service)
        
        let viewModel = makeViewModel(service: service, store: store)
        let provisioning = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == .provisioning }
        try await provisioning.fulfill()
        try await Task.sleep(for: .milliseconds(2200)) // the poll was every 2 s
        #expect(service.listMyAgentSpacesCallsCount == 1)
        
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace], provisioningStatus: .ready))
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == Self.loaded([Self.personalSpace]) }
        store.apply([.agentUpdated(agentID: Self.assistant.agentID, spaceID: Self.personalSpace.orgID)])
        try await loaded.fulfill()
    }
    
    /// The bell counts what waits for the owner, as the session's badge reads it.
    @Test
    func theBellCountsWhatWaits() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [], provisioningStatus: .ready))
        service.fetchNotificationsActivityCursorLimitReturnValue = .success(.init(needsAction: [.approval(.init(id: "a1", agentID: "agent-1", draftBody: "x",
                                                                                                                 targetRoomID: "!r:host", createdAt: .now))],
                                                                                  activity: [], nextActivityCursor: nil, lastSeenAt: nil, unseenCount: 0))
        let store = AgentsStore(service: service)
        let viewModel = makeViewModel(service: service, store: store)
        
        let counted = deferFulfillment(viewModel.context.observe(\.viewState.pendingApprovalsCount)) { $0 == 1 }
        store.show(.needsAction, by: service)
        try await counted.fulfill()
    }
    
    // MARK: - Actions
    
    @Test
    func selectAgent_emitsTheAssistantWithNoCompany() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace, Self.companySpace], provisioningStatus: .ready))
        
        let viewModel = makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == Self.loaded([Self.personalSpace]) }
        try await loaded.fulfill()
        
        let personal = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .selectAgent(let selection) = action { return selection == .init(card: Self.assistant, companyName: nil) }
            return false
        }
        viewModel.context.send(viewAction: .selectAgent(agentID: Self.assistant.agentID))
        try await personal.fulfill()
    }
    
    /// Checklist 1: a space whose read failed is not a space without agents.
    @Test
    func aSpaceThatFailsToReadSaysSoInItsSection() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace], provisioningStatus: .ready))
        service.fetchAgentSpaceOrgIDClosure = { _ in .failure(.serverError(status: 500)) }
        
        let viewModel = makeViewModel(service: service)
        let expected = AgentSpacesScreenListState.loaded([AgentSpaceSection(summary: Self.personalSpace, content: .failed)])
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == expected }
        try await loaded.fulfill()
        
        #expect(viewModel.context.viewState.sections[0].agents.isEmpty)
        #expect(!viewModel.context.viewState.sections[0].isAssistantPending)
    }
    
    /// Question 396: no way to make, edit or open a company or its agents, even with a stale company in the directory.
    @Test
    func noCompanyEntryPointsWhileCompaniesAreHidden() async throws {
        #expect(!SpiralFeatures.companySpaces, "turning companies back on goes through review (396)")
        
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace, Self.companySpace], provisioningStatus: .ready))
        
        let viewModel = makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == Self.loaded([Self.personalSpace]) }
        try await loaded.fulfill()
        #expect(viewModel.context.viewState.companies.isEmpty)
        
        var actions: [AgentSpacesScreenViewModelAction] = []
        let cancellable = viewModel.actionsPublisher.sink { actions.append($0) }
        viewModel.context.send(viewAction: .createCompany)
        viewModel.context.send(viewAction: .createAgent(orgID: Self.companySpace.orgID))
        viewModel.context.send(viewAction: .editCompany(orgID: Self.companySpace.orgID))
        viewModel.context.send(viewAction: .selectAgent(agentID: Self.salesAgent.agentID))
        cancellable.cancel()
        
        #expect(actions.isEmpty)
    }
    
    // MARK: - Rows made anew (S5)

    /// The rows changed while the agent's screen covered the list: they are made anew as it shows again.
    @Test
    func aChangeWhileCoveredMakesTheRowsAnewOnReturn() async throws {
        let (viewModel, store, service) = try await shownViewModel()
        viewModel.context.send(viewAction: .disappeared)

        Self.serveAssistant(avatarMXC: "mxc://host/new", from: service)
        store.apply([.agentUpdated(agentID: Self.assistant.agentID, spaceID: Self.personalSpace.orgID)])
        let changed = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0.avatar(of: Self.assistant.agentID) == "mxc://host/new" }
        try await changed.fulfill()
        #expect(viewModel.context.viewState.listGeneration == 0, "nothing is made anew off screen")

        viewModel.context.send(viewAction: .appeared)
        #expect(viewModel.context.viewState.listGeneration == 1)
        viewModel.context.send(viewAction: .appeared)
        #expect(viewModel.context.viewState.listGeneration == 1, "once per change")
    }

    @Test
    func noChangeWhileCoveredKeepsTheRows() async throws {
        let (viewModel, _, _) = try await shownViewModel()
        viewModel.context.send(viewAction: .disappeared)
        viewModel.context.send(viewAction: .appeared)
        #expect(viewModel.context.viewState.listGeneration == 0)
    }

    /// A change on screen updates the rows in place: their images load as usual.
    @Test
    func aChangeOnScreenKeepsTheRows() async throws {
        let (viewModel, store, service) = try await shownViewModel()

        Self.serveAssistant(avatarMXC: "mxc://host/new", from: service)
        store.apply([.agentUpdated(agentID: Self.assistant.agentID, spaceID: Self.personalSpace.orgID)])
        let changed = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0.avatar(of: Self.assistant.agentID) == "mxc://host/new" }
        try await changed.fulfill()
        viewModel.context.send(viewAction: .disappeared)
        viewModel.context.send(viewAction: .appeared)
        #expect(viewModel.context.viewState.listGeneration == 0)
    }

    /// A card's new avatar from the stream reaches the row.
    @Test
    func aCardsNewAvatarReachesTheList() async throws {
        let (viewModel, store, service) = try await shownViewModel()
        Self.serveAssistant(avatarMXC: "mxc://host/streamed", from: service)

        store.apply([.agentUpdated(agentID: Self.assistant.agentID, spaceID: Self.personalSpace.orgID)])
        let changed = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0.avatar(of: Self.assistant.agentID) == "mxc://host/streamed" }
        try await changed.fulfill()
    }

    /// The list loaded and on screen.
    private func shownViewModel() async throws -> (AgentSpacesScreenViewModel, AgentsStore, AgentPlatformServiceMock) {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace], provisioningStatus: .ready))
        let store = AgentsStore(service: service)
        let viewModel = makeViewModel(service: service, store: store)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == Self.loaded([Self.personalSpace]) }
        try await loaded.fulfill()
        viewModel.context.send(viewAction: .appeared)
        await store.settle()
        return (viewModel, store, service)
    }

    /// The Personal space as the server answers it now: its assistant with this avatar.
    private static func serveAssistant(avatarMXC: String, from service: AgentPlatformServiceMock) {
        let card = AgentSpaceAgentCard(agentID: assistant.agentID, matrixUserID: assistant.matrixUserID, displayName: assistant.displayName,
                                       avatarMXC: avatarMXC, kind: assistant.kind, visibility: assistant.visibility,
                                       lifecycleState: assistant.lifecycleState, roomCount: assistant.roomCount, activeToolCount: assistant.activeToolCount)
        let detail = AgentSpaceDetail(orgID: personalSpace.orgID, name: personalSpace.name, kind: personalSpace.kind, avatarMXC: nil,
                                      industry: nil, website: nil, agents: [card])
        service.fetchAgentSpaceOrgIDClosure = { _ in .success(detail) }
    }

    @Test
    func aPausedAgentSaysSoInItsRow() {
        let paused = AgentSpaceAgentCard(agentID: "a", matrixUserID: "@a:spiral.md", displayName: "A", avatarMXC: nil,
                                         kind: "sales", visibility: "public", lifecycleState: "suspended", roomCount: 0, activeToolCount: 0, isPaused: true)
        #expect(paused.localizedRole == UntranslatedL10n.screenCreateAgentRoleSales)
        #expect(paused.presence() == .paused(UntranslatedL10n.screenAgentsPaused))
    }
    
    @Test
    func aPausedAgentIsPausedEvenWhileOnline() {
        let paused = AgentSpaceAgentCard(agentID: "a", matrixUserID: "@a:spiral.md", displayName: "A", avatarMXC: nil,
                                         kind: "personal_assistant", visibility: "public", lifecycleState: "active",
                                         roomCount: 0, activeToolCount: 0, isPaused: true)
        #expect(paused.presence() == .paused(UntranslatedL10n.screenAgentsPaused))
    }
    
    @Test
    func aLaterReadOfThePauseWinsOverTheCard() {
        #expect(Self.assistant.presence(isPaused: true) == .paused(UntranslatedL10n.screenAgentsPaused))
        
        let listedAsPaused = AgentSpaceAgentCard(agentID: "a", matrixUserID: "@a:spiral.md", displayName: "A", avatarMXC: nil,
                                                 kind: "sales", visibility: "public", lifecycleState: "active",
                                                 roomCount: 0, activeToolCount: 0, isPaused: true)
        #expect(listedAsPaused.presence(isPaused: false) == .online(UntranslatedL10n.screenAgentSpaceAgentPresenceOnline))
    }
    
    /// Online unless paused or no longer active: the same meaning as in the chats (357 item 10).
    @Test
    func anAgentIsOnlineUnlessPausedOrNoLongerActive() {
        #expect(Self.assistant.presence() == .online(UntranslatedL10n.screenAgentSpaceAgentPresenceOnline))
        #expect(Self.salesAgent.presence() == .online(UntranslatedL10n.screenAgentSpaceAgentPresenceOnline))
        
        for lifecycleState in ["suspended", "archived"] {
            let gone = AgentSpaceAgentCard(agentID: "a", matrixUserID: "@a:spiral.md", displayName: "A", avatarMXC: nil,
                                           kind: "personal_assistant", visibility: "public", lifecycleState: lifecycleState,
                                           roomCount: 2, activeToolCount: 1)
            #expect(gone.presence() == nil)
            #expect(gone.chatsAndTools == "\(UntranslatedL10n.screenAgentsChatCount(2)) · \(UntranslatedL10n.screenAgentsToolCount(1))")
        }
    }
    
    @Test
    func aRowsFactsAreForAgentsWithoutARole() {
        #expect(Self.assistant.rowFacts == Self.assistant.chatsAndTools)
        #expect(Self.salesAgent.rowFacts == nil)
        
        let unknownKind = AgentSpaceAgentCard(agentID: "a", matrixUserID: "@a:spiral.md", displayName: "A", avatarMXC: nil,
                                              kind: "a_kind_from_a_later_build", visibility: "public", lifecycleState: "active",
                                              roomCount: 3, activeToolCount: 2)
        #expect(unknownKind.localizedRole == nil)
        #expect(unknownKind.rowFacts == unknownKind.chatsAndTools)
    }
}

private extension AgentSpacesScreenListState {
    func avatar(of agentID: String) -> String? {
        guard case .loaded(let sections) = self else { return nil }
        return sections.flatMap(\.agents).first { $0.agentID == agentID }?.avatarMXC
    }
}
