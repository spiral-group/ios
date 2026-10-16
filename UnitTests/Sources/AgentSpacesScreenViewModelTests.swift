//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Brief 0037 — Agents tab rebuilt on the Spaces model.
// Tests for the tab root: one list, a section per space (step B).
//

@testable import ElementX
import Combine
import Foundation
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
                                                       visibility: "public", lifecycleState: "active", presence: .online,
                                                       roomCount: 2, activeToolCount: 1)
    
    private static let salesAgent = AgentSpaceAgentCard(agentID: "agent-2", matrixUserID: "@agent-acme-sales:spiral.md",
                                                        displayName: "Sales · Acme Corp", avatarMXC: nil, kind: "sales",
                                                        visibility: "public", lifecycleState: "active", presence: .offline,
                                                        roomCount: 1, activeToolCount: 0)
    
    private static func detail(_ space: AgentSpaceSummary) -> AgentSpaceDetail {
        AgentSpaceDetail(orgID: space.orgID, name: space.name, kind: space.kind, avatarMXC: space.avatarMXC,
                         industry: nil, website: nil,
                         agents: space.kind == .solo ? [assistant] : [salesAgent])
    }
    
    /// The sections a read of these spaces shows.
    private static func loaded(_ spaces: [AgentSpaceSummary]) -> AgentSpacesScreenListState {
        .loaded(spaces.map { AgentSpaceSection(summary: $0, content: .loaded(detail($0))) })
    }
    
    private func makeViewModel(service: AgentPlatformServiceMock) -> AgentSpacesScreenViewModel {
        if service.fetchAgentSpaceOrgIDClosure == nil {
            service.fetchAgentSpaceOrgIDClosure = { orgID in
                .success(Self.detail(orgID == Self.personalSpace.orgID ? Self.personalSpace : Self.companySpace))
            }
        }
        return AgentSpacesScreenViewModel(userSession: UserSessionMock(.init(clientProxy: ClientProxyMock(.init(userID: "@owner:spiral.md")))),
                                          agentPlatformService: service)
    }
    
    // MARK: - Loading
    
    @Test
    func initialLoad_success_showsSpaces() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace, Self.companySpace],
                                                              provisioningStatus: .ready))
        
        let viewModel = makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            state == Self.loaded([Self.personalSpace, Self.companySpace])
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()
        
        #expect(service.listMyAgentSpacesCallsCount == 1)
    }
    
    @Test
    func initialLoad_failure_showsFailureState() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .failure(.serverError(status: 500))
        
        let viewModel = makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == .failure }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()
    }
    
    @Test
    func initialLoad_emptyAndProvisioning_showsProvisioningState() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [], provisioningStatus: .inProgress))
        
        let viewModel = makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == .provisioning }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()
    }

    /// A ready directory without spaces says the assistant is on its way.
    @Test
    func aReadyDirectoryWithoutSpacesIsNotBlank() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [], provisioningStatus: .ready))

        let viewModel = makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == .loaded([]) }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.hasNoSpaces)
    }

    /// A Personal space without its assistant says so; a company without
    /// agents offers «Новый агент» instead.
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
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.sections.map(\.isAssistantPending) == [true, false])
        #expect(!viewModel.context.viewState.hasNoSpaces)
    }

    @Test
    func retryAfterFailure_reloads() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .failure(.serverError(status: 500))
        
        let viewModel = makeViewModel(service: service)
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == .failure }
        viewModel.context.send(viewAction: .appeared)
        try await failed.fulfill()
        
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace],
                                                              provisioningStatus: .ready))
        
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == Self.loaded([Self.personalSpace]) }
        viewModel.context.send(viewAction: .retry)
        try await loaded.fulfill()
    }
    
    @Test
    func refreshFailure_keepsStaleContent() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace],
                                                              provisioningStatus: .ready))
        
        let viewModel = makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == Self.loaded([Self.personalSpace]) }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()
        
        // A background refresh failing must NOT nuke the visible list.
        service.listMyAgentSpacesReturnValue = .failure(.transport(underlying: URLError(.notConnectedToInternet)))
        viewModel.context.send(viewAction: .refresh)
        
        // Wait for the reload round-trip, then confirm content survived.
        let stillLoaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == Self.loaded([Self.personalSpace]) }
        try await stillLoaded.fulfill()
        #expect(service.listMyAgentSpacesCallsCount == 2)
    }
    
    /// Coverage walk F4: a company made elsewhere showed only after a pull
    /// to refresh. The list reads again whenever it is on screen again, and
    /// keeps its rows until the answer replaces them.
    @Test
    func appearingAgainReadsTheDirectoryAgainWithoutBlankingIt() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace], provisioningStatus: .ready))
        
        let viewModel = makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == Self.loaded([Self.personalSpace]) }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()
        
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace, Self.companySpace], provisioningStatus: .ready))
        var states: [AgentSpacesScreenListState] = []
        let reloaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            states.append(state)
            return state == Self.loaded([Self.personalSpace, Self.companySpace])
        }
        viewModel.context.send(viewAction: .appeared)
        try await reloaded.fulfill()
        
        #expect(service.listMyAgentSpacesCallsCount == 2)
        #expect(!states.contains(.loading))
    }
    
    @Test
    func aFailedReadOnReappearingKeepsTheRows() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace], provisioningStatus: .ready))
        
        let viewModel = makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == Self.loaded([Self.personalSpace]) }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()
        
        service.listMyAgentSpacesReturnValue = .failure(.serverError(status: 500))
        viewModel.context.send(viewAction: .appeared)
        for _ in 0..<100 where service.listMyAgentSpacesCallsCount < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(50))
        
        #expect(service.listMyAgentSpacesCallsCount == 2)
        #expect(viewModel.context.viewState.listState == Self.loaded([Self.personalSpace]))
    }
    
    /// A slower, older answer must not replace a newer one.
    @Test
    func anOlderAnswerArrivingLastIsDropped() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesClosure = { [service] in
            if service.listMyAgentSpacesCallsCount == 1 {
                try? await Task.sleep(for: .milliseconds(300))
                return .success(.init(spaces: [Self.personalSpace], provisioningStatus: .ready))
            }
            return .success(.init(spaces: [Self.personalSpace, Self.companySpace], provisioningStatus: .ready))
        }
        
        let viewModel = makeViewModel(service: service)
        let newest = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == Self.loaded([Self.personalSpace, Self.companySpace]) }
        viewModel.context.send(viewAction: .appeared)
        viewModel.context.send(viewAction: .refresh)
        try await newest.fulfill()
        
        try await Task.sleep(for: .milliseconds(500))
        #expect(viewModel.context.viewState.listState == Self.loaded([Self.personalSpace, Self.companySpace]))
    }
    
    // MARK: - Actions
    
    @Test
    func selectAgent_emitsTheCardWithItsCompany() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace, Self.companySpace], provisioningStatus: .ready))
        
        let viewModel = makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == Self.loaded([Self.personalSpace, Self.companySpace]) }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()
        
        let company = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .selectAgent(let selection) = action { return selection == .init(card: Self.salesAgent, companyName: "Acme Corp") }
            return false
        }
        viewModel.context.send(viewAction: .selectAgent(agentID: Self.salesAgent.agentID))
        try await company.fulfill()
        
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
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace, Self.companySpace], provisioningStatus: .ready))
        service.fetchAgentSpaceOrgIDClosure = { orgID in
            orgID == Self.companySpace.orgID ? .failure(.serverError(status: 500)) : .success(Self.detail(Self.personalSpace))
        }
        
        let viewModel = makeViewModel(service: service)
        let expected = AgentSpacesScreenListState.loaded([AgentSpaceSection(summary: Self.personalSpace, content: .loaded(Self.detail(Self.personalSpace))),
                                                          AgentSpaceSection(summary: Self.companySpace, content: .failed)])
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == expected }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()
        
        #expect(viewModel.context.viewState.sections[1].agents.isEmpty)
    }
    
    @Test
    func createAgentAndEditCompanyNameTheCompany() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace, Self.companySpace], provisioningStatus: .ready))
        
        let viewModel = makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == Self.loaded([Self.personalSpace, Self.companySpace]) }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()
        #expect(viewModel.context.viewState.companies == [Self.companySpace])
        
        let create = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .showCreateAgent(let company) = action { return company == Self.companySpace }
            return false
        }
        viewModel.context.send(viewAction: .createAgent(orgID: Self.companySpace.orgID))
        try await create.fulfill()
        
        let edit = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .showEditCompany(let detail) = action { return detail == Self.detail(Self.companySpace) }
            return false
        }
        viewModel.context.send(viewAction: .editCompany(orgID: Self.companySpace.orgID))
        try await edit.fulfill()
    }
    
    @Test
    func aPausedAgentSaysSoInItsRow() {
        let paused = AgentSpaceAgentCard(agentID: "a", matrixUserID: "@a:spiral.md", displayName: "A", avatarMXC: nil,
                                         kind: "sales", visibility: "public", lifecycleState: "suspended", presence: .online,
                                         roomCount: 0, activeToolCount: 0, isPaused: true)
        #expect(paused.rowSubtitle == "\(UntranslatedL10n.screenCreateAgentRoleSales) · \(UntranslatedL10n.screenAgentsPaused)")
    }
    
    @Test
    func anOfflineAgentsRowDoesNotSaySo() {
        #expect(Self.salesAgent.rowSubtitle == UntranslatedL10n.screenCreateAgentRoleSales)
        
        let offlineAssistant = AgentSpaceAgentCard(agentID: "a", matrixUserID: "@a:spiral.md", displayName: "A", avatarMXC: nil,
                                                   kind: "personal_assistant", visibility: "public", lifecycleState: "active",
                                                   presence: .offline, roomCount: 2, activeToolCount: 1)
        #expect(offlineAssistant.rowSubtitle == "\(UntranslatedL10n.screenAgentsChatCount(2)) · \(UntranslatedL10n.screenAgentsToolCount(1))")
        #expect(Self.assistant.rowSubtitle.hasPrefix(UntranslatedL10n.screenAgentSpaceAgentPresenceOnline))
    }
    
    @Test
    func showSettings_emitsAction() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [], provisioningStatus: .ready))
        
        let viewModel = makeViewModel(service: service)
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .showSettings = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .showSettings)
        try await deferred.fulfill()
    }
}
