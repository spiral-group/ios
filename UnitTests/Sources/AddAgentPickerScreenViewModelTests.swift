//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0035/0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenViewModelTests.swift`.
//

import Combine
@testable import ElementX
import Foundation
import Testing

@MainActor
struct AddAgentPickerScreenViewModelTests {
    // MARK: - Helpers

    /// A Personal space with the assistant and a company with a sales agent.
    private static func makeService(inRoomMXIDs: [String] = []) -> AgentPlatformServiceMock {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(AgentSpacesDirectory(spaces: [
            AgentSpaceSummary(orgID: "personal", name: "Alice", kind: .solo, avatarMXC: nil, agentCount: 1),
            AgentSpaceSummary(orgID: "acme", name: "Acme", kind: .company, avatarMXC: nil, agentCount: 2),
            AgentSpaceSummary(orgID: "empty", name: "Empty Co", kind: .company, avatarMXC: nil, agentCount: 0)
        ], provisioningStatus: .ready))
        service.fetchAgentSpaceOrgIDClosure = { orgID in
            switch orgID {
            case "personal":
                .success(space(orgID, kind: .solo, agents: [card("a1", mxid: "@assistant-alice:host", name: "Assistant Alice")]))
            case "acme":
                .success(space(orgID, kind: .company, agents: [card("a2", mxid: "@agent-acme-sales:host", name: "Acme Sales"),
                                                               card("a3", mxid: "@agent-acme-old:host", name: "Old", lifecycleState: "archived")]))
            default:
                .failure(.notFound)
            }
        }
        let roomAgents = inRoomMXIDs.map { mxid in
            RoomToolAgentEntry(agentID: mxid, matrixUserID: mxid, displayName: mxid,
                               ownerUserID: "@o:host", isMine: true, tools: [])
        }
        service.fetchRoomToolsRoomIDReturnValue = .success(RoomToolsView(roomID: "!r:host", agents: roomAgents))
        return service
    }

    private nonisolated static func space(_ orgID: String, kind: AgentSpaceSummary.Kind, agents: [AgentSpaceAgentCard]) -> AgentSpaceDetail {
        AgentSpaceDetail(orgID: orgID, name: orgID == "acme" ? "Acme" : "Alice", kind: kind,
                         avatarMXC: nil, industry: nil, website: nil, agents: agents)
    }

    private nonisolated static func card(_ id: String, mxid: String, name: String, lifecycleState: String = "active") -> AgentSpaceAgentCard {
        AgentSpaceAgentCard(agentID: id, matrixUserID: mxid, displayName: name, avatarMXC: nil,
                            kind: id == "a1" ? "personal_assistant" : "sales", visibility: "private",
                            lifecycleState: lifecycleState, presence: .online, roomCount: 0, activeToolCount: 0)
    }

    private static func makeViewModel(service: AgentPlatformServiceMock,
                                      roomProxy: JoinedRoomProxyProtocol) -> AddAgentPickerScreenViewModel {
        AddAgentPickerScreenViewModel(roomID: "!r:host", roomProxy: roomProxy, agentPlatformService: service)
    }

    // MARK: - Display name

    @Test
    func displayName_fromMatrixUserID() {
        #expect(AgentSummary.displayName(fromMatrixUserID: "@assistant-alice:host") == "Assistant-Alice")
        #expect(AgentSummary.displayName(fromMatrixUserID: "scribe") == "Scribe")
    }

    // MARK: - Crossing

    @Test
    func appeared_marksInRoomAgents() async throws {
        let service = Self.makeService(inRoomMXIDs: ["@assistant-alice:host"])
        let viewModel = Self.makeViewModel(service: service, roomProxy: JoinedRoomProxyMock(.init()))

        try await Self.load(viewModel)

        let agents = viewModel.context.viewState.agents
        #expect(agents.first { $0.agentID == "a1" }?.isInRoom == true) // alice in room
        #expect(agents.first { $0.agentID == "a2" }?.isInRoom == false) // the company agent is addable
    }

    /// Re-walk R1: a company the person owns is a space they act for, so its
    /// agents are offered next to the Personal ones — one section per space.
    @Test
    func appeared_listsEverySpaceTheCallerActsFor() async throws {
        let service = Self.makeService()
        let viewModel = Self.makeViewModel(service: service, roomProxy: JoinedRoomProxyMock(.init()))

        try await Self.load(viewModel)

        let sections = viewModel.context.viewState.sections
        #expect(sections.map(\.title) == [UntranslatedL10n.screenAgentSpacesKindPersonal, "Acme"])
        #expect(sections.map { $0.agents.map(\.agentID) } == [["a1"], ["a2"]], "archived agents and empty spaces left out")
        #expect(service.fetchAgentSpaceOrgIDReceivedInvocations == ["personal", "acme"], "a space without agents isn't read")
        #expect(service.listMyPersonalAgentsCalled == false)
    }

    /// A space that couldn't be read is not a space without agents.
    @Test
    func appeared_failedSpaceRead_failsInsteadOfHidingTheSpace() async throws {
        let service = Self.makeService()
        service.fetchAgentSpaceOrgIDClosure = { orgID in
            orgID == "personal"
                ? .success(Self.space(orgID, kind: .solo, agents: [Self.card("a1", mxid: "@assistant-alice:host", name: "Assistant Alice")]))
                : .failure(.serverError(status: 500))
        }
        let viewModel = Self.makeViewModel(service: service, roomProxy: JoinedRoomProxyMock(.init()))

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == .failed }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()
    }

    private static func load(_ viewModel: AddAgentPickerScreenViewModel) async throws {
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            if case .loaded = state { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()
    }

    // MARK: - Invite

    @Test
    func invite_success_emitsInvited() async throws {
        let service = Self.makeService()
        let roomProxy = JoinedRoomProxyMock(.init())
        roomProxy.inviteUserIDReturnValue = .success(())
        let viewModel = Self.makeViewModel(service: service, roomProxy: roomProxy)

        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            if case .loaded = state { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            // .invited now carries the full item (id + mxid + name) so the flow
            // can open the new agent's capabilities directly.
            if case .invited(let item) = action {
                return item.agentID == "a2" && item.matrixUserID == "@agent-acme-sales:host"
            }
            return false
        }
        viewModel.context.send(viewAction: .invite(id: "a2"))
        try await deferred.fulfill()

        #expect(roomProxy.inviteUserIDReceivedUserID == "@agent-acme-sales:host")
    }

    @Test
    func invite_failure_setsAlert() async throws {
        let service = Self.makeService()
        let roomProxy = JoinedRoomProxyMock(.init())
        roomProxy.inviteUserIDReturnValue = .failure(.sdkError(RoomProxyMockError.generic))
        let viewModel = Self.makeViewModel(service: service, roomProxy: roomProxy)

        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            if case .loaded = state { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0 != nil }
        viewModel.context.send(viewAction: .invite(id: "a2"))
        try await deferred.fulfill()
        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .inviteFailed)
    }

    @Test
    func invite_inRoomAgent_isNoOp() async throws {
        let service = Self.makeService(inRoomMXIDs: ["@assistant-alice:host"])
        let roomProxy = JoinedRoomProxyMock(.init())
        roomProxy.inviteUserIDReturnValue = .success(())
        let viewModel = Self.makeViewModel(service: service, roomProxy: roomProxy)

        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            if case .loaded = state { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()

        // a1 is in the room → invite must not call the proxy.
        viewModel.context.send(viewAction: .invite(id: "a1"))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(roomProxy.inviteUserIDCalled == false)
    }
}
