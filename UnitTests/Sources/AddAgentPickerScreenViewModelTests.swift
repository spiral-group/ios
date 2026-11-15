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
import Foundation
@testable import Spiral
import Testing

@MainActor
struct AddAgentPickerScreenViewModelTests {
    // MARK: - Helpers

    /// A Personal space with the assistant and a company with a sales agent, which stays hidden (396).
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
                            lifecycleState: lifecycleState, roomCount: 0, activeToolCount: 0)
    }

    private static func makeViewModel(service: AgentPlatformServiceMock,
                                      roomProxy: JoinedRoomProxyProtocol) -> AddAgentPickerScreenViewModel {
        AddAgentPickerScreenViewModel(roomID: "!r:host", roomProxy: roomProxy, store: AgentsStore(service: service))
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
    }

    /// Question 396: companies are hidden, so the picker offers the Personal space's agents alone, and a company the
    /// directory still lists is not read.
    @Test
    func appeared_listsThePersonalSpaceAlone() async throws {
        let service = Self.makeService()
        let viewModel = Self.makeViewModel(service: service, roomProxy: JoinedRoomProxyMock(.init()))

        try await Self.load(viewModel)

        let sections = viewModel.context.viewState.sections
        #expect(sections.map(\.title) == [UntranslatedL10n.screenAgentSpacesKindPersonal])
        #expect(sections.map { $0.agents.map(\.agentID) } == [["a1"]])
        #expect(service.fetchAgentSpaceOrgIDReceivedInvocations == ["personal"])
        #expect(service.listMyPersonalAgentsCalled == false)
    }

    /// A space that couldn't be read is not a space without agents.
    @Test
    func appeared_failedSpaceRead_failsInsteadOfHidingTheSpace() async throws {
        let service = Self.makeService()
        service.fetchAgentSpaceOrgIDClosure = { _ in .failure(.serverError(status: 500)) }
        let viewModel = Self.makeViewModel(service: service, roomProxy: JoinedRoomProxyMock(.init()))

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == .failed }
        try await deferred.fulfill()
    }

    private static func load(_ viewModel: AddAgentPickerScreenViewModel) async throws {
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState)) { state in
            if case .loaded = state.listState { state.isRoomRead } else { false }
        }
        try await deferred.fulfill()
    }

    // MARK: - From the store

    /// What the session holds shows at once, with no read of the spaces of its own.
    @Test
    func theSpacesInTheStoreShowAtInit() async {
        let service = Self.makeService()
        let store = AgentsStore(service: service)
        await store.reread(.spaces)
        let listReads = service.listMyAgentSpacesCallsCount

        let viewModel = AddAgentPickerScreenViewModel(roomID: "!r:host", roomProxy: JoinedRoomProxyMock(.init()), store: store)

        #expect(viewModel.context.viewState.agents.map(\.agentID) == ["a1"])
        #expect(service.listMyAgentSpacesCallsCount == listReads)
    }

    /// The list shows, but what may already be in the chat isn't offered until the room has answered.
    @Test
    func noInviteBeforeTheRoomHasAnswered() async throws {
        let service = Self.makeService()
        let store = AgentsStore(service: service)
        await store.reread(.spaces)
        let answer = try #require(service.fetchRoomToolsRoomIDReturnValue)
        let gate = RoomGate()
        service.fetchRoomToolsRoomIDClosure = { _ in
            await gate.wait()
            return answer
        }
        let roomProxy = JoinedRoomProxyMock(.init())
        roomProxy.inviteUserIDReturnValue = .success(())
        let viewModel = AddAgentPickerScreenViewModel(roomID: "!r:host", roomProxy: roomProxy, store: store)

        viewModel.context.send(viewAction: .invite(id: "a1"))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(roomProxy.inviteUserIDCalled == false)
        #expect(!viewModel.context.viewState.isRoomRead)

        gate.open()
        let read = deferFulfillment(viewModel.context.observe(\.viewState.isRoomRead)) { $0 }
        try await read.fulfill()
        let invited = deferFulfillment(viewModel.actionsPublisher) { if case .invited = $0 { true } else { false } }
        viewModel.context.send(viewAction: .invite(id: "a1"))
        try await invited.fulfill()
    }

    @Test
    func retryReadsAgainWhatFailed() async throws {
        let service = Self.makeService()
        let answer = service.listMyAgentSpacesReturnValue
        service.listMyAgentSpacesReturnValue = .failure(.serverError(status: 500))
        let viewModel = Self.makeViewModel(service: service, roomProxy: JoinedRoomProxyMock(.init()))
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == .failed }
        try await failed.fulfill()

        service.listMyAgentSpacesReturnValue = answer
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { if case .loaded = $0 { true } else { false } }
        viewModel.context.send(viewAction: .retry)
        try await loaded.fulfill()
    }

    // MARK: - Invite

    /// A failed read of the room's agents is not "none in the room": the room's own members still answer.
    /// Taken for an answer, the picker offered an agent the chat's sheet was listing (357 item 8).
    @Test
    func appeared_failedRoomRead_marksTheRoomsOwnMembers() async throws {
        let service = Self.makeService()
        service.fetchRoomToolsRoomIDReturnValue = .failure(.serverError(status: 500))
        let members = [RoomMemberProxyMock(with: .init(userID: "@assistant-alice:host", membership: .join)), .mockMe]
        let viewModel = AddAgentPickerScreenViewModel(roomID: "!r:host",
                                                      roomProxy: JoinedRoomProxyMock(.init(members: members)),
                                                      store: AgentsStore(service: service))

        try await Self.load(viewModel)

        let agents = viewModel.context.viewState.agents
        #expect(agents.first { $0.matrixUserID == "@assistant-alice:host" }?.isInRoom == true)
    }

    /// Neither answered: the screen says so, and never offers what may be in the chat.
    @Test
    func appeared_noReadOfTheRoom_fails() async throws {
        let service = Self.makeService()
        service.fetchRoomToolsRoomIDReturnValue = .failure(.serverError(status: 500))
        let viewModel = AddAgentPickerScreenViewModel(roomID: "!r:host",
                                                      roomProxy: JoinedRoomProxyMock(.init(members: [])),
                                                      store: AgentsStore(service: service))

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == .failed }
        try await deferred.fulfill()
    }

    /// The server lists joined agents only: an invited one is in the chat too.
    @Test
    func appeared_marksAnInvitedAgent() async throws {
        let service = Self.makeService()
        let members = [RoomMemberProxyMock(with: .init(userID: "@assistant-alice:host", membership: .invite)), .mockMe]
        let viewModel = AddAgentPickerScreenViewModel(roomID: "!r:host",
                                                      roomProxy: JoinedRoomProxyMock(.init(members: members)),
                                                      store: AgentsStore(service: service))

        try await Self.load(viewModel)

        #expect(viewModel.context.viewState.agents.first { $0.matrixUserID == "@assistant-alice:host" }?.isInRoom == true)
    }

    @Test
    func invite_success_emitsInvited() async throws {
        let service = Self.makeService()
        let roomProxy = JoinedRoomProxyMock(.init())
        roomProxy.inviteUserIDReturnValue = .success(())
        let viewModel = Self.makeViewModel(service: service, roomProxy: roomProxy)

        try await Self.load(viewModel)

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            // .invited now carries the full item (id + mxid + name) so the flow
            // can open the new agent's capabilities directly.
            if case .invited(let item) = action {
                return item.agentID == "a1" && item.matrixUserID == "@assistant-alice:host"
            }
            return false
        }
        viewModel.context.send(viewAction: .invite(id: "a1"))
        try await deferred.fulfill()

        #expect(roomProxy.inviteUserIDReceivedUserID == "@assistant-alice:host")
    }

    @Test
    func invite_failure_setsAlert() async throws {
        let service = Self.makeService()
        let roomProxy = JoinedRoomProxyMock(.init())
        roomProxy.inviteUserIDReturnValue = .failure(.sdkError(RoomProxyMockError.generic))
        let viewModel = Self.makeViewModel(service: service, roomProxy: roomProxy)

        try await Self.load(viewModel)

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0 != nil }
        viewModel.context.send(viewAction: .invite(id: "a1"))
        try await deferred.fulfill()
        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .inviteFailed)
    }

    @Test
    func invite_inRoomAgent_isNoOp() async throws {
        let service = Self.makeService(inRoomMXIDs: ["@assistant-alice:host"])
        let roomProxy = JoinedRoomProxyMock(.init())
        roomProxy.inviteUserIDReturnValue = .success(())
        let viewModel = Self.makeViewModel(service: service, roomProxy: roomProxy)

        try await Self.load(viewModel)

        // a1 is in the room → invite must not call the proxy.
        viewModel.context.send(viewAction: .invite(id: "a1"))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(roomProxy.inviteUserIDCalled == false)
    }
}

/// Holds a read until the test opens it.
private final class RoomGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
