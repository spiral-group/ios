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

@testable import ElementX
import Combine
import Foundation
import Testing

@MainActor
struct AgentSheetScreenViewModelTests {
    // MARK: - Projection

    @Test
    func projectOwnAgents_filtersMineAndBuildsStatus() {
        let tools = RoomToolsView(roomID: "!r:host", agents: [
            RoomToolAgentEntry(agentID: "mine", matrixUserID: "@mine:host", displayName: "Assistant",
                               ownerUserID: "@o:host", isMine: true,
                               tools: [RoomToolView(toolID: "t1", toolKind: "translate", triggerKind: "on_message",
                                                    targetLanguage: "English",
                                                    params: .translate(targetLanguage: "English"),
                                                    trigger: .onMessage(senderScope: .anyone), safeSliceSalt: "t1")]),
            RoomToolAgentEntry(agentID: "theirs", matrixUserID: "@theirs:host", displayName: "Bob's agent",
                               ownerUserID: "@b:host", isMine: false, tools: [])
        ])

        let agents = AgentSummary.ownAgents(in: tools)
        #expect(agents.count == 1)
        #expect(agents[0].agentID == "mine")
        #expect(agents[0].activeToolCount == 1)
        // Single translate tool → "translating to" summary.
        #expect(agents[0].statusLine == UntranslatedL10n.screenAgentToolsListTitleTranslate("English"))
    }

    /// Re-walk R1 backend contract: a company agent has no `owner_user_id`;
    /// `is_mine` (true for every agent in a space the caller owns) alone
    /// says whose it is, so a plain member of the company gets no controls.
    @Test
    func projectOwnAgents_companyAgentIsYoursByIsMineAlone() {
        let tools = RoomToolsView(roomID: "!r:host", agents: [
            RoomToolAgentEntry(agentID: "sales", matrixUserID: "@agent-acme-sales:host", displayName: "Acme Sales",
                               ownerUserID: nil, isMine: true, tools: []),
            RoomToolAgentEntry(agentID: "support", matrixUserID: "@agent-other-support:host", displayName: "Other Support",
                               ownerUserID: nil, isMine: false, tools: [])
        ])

        #expect(AgentSummary.ownAgents(in: tools).map(\.agentID) == ["sales"])
    }

    /// Several tools say what is counted: «2 инструмента», not «Активных: 2».
    @Test
    func projectOwnAgents_severalTools_countsThemAsTools() {
        let tool = { (id: String) in
            RoomToolView(toolID: id, toolKind: "translate", triggerKind: "on_message", targetLanguage: "English",
                         params: .translate(targetLanguage: "English"), trigger: .onMessage(senderScope: .anyone), safeSliceSalt: id)
        }
        let tools = RoomToolsView(roomID: "!r:host", agents: [
            RoomToolAgentEntry(agentID: "mine", matrixUserID: "@mine:host", displayName: "Scribe",
                               ownerUserID: "@o:host", isMine: true, tools: [tool("t1"), tool("t2")])
        ])
        #expect(AgentSummary.ownAgents(in: tools)[0].statusLine == UntranslatedL10n.screenAgentsToolCount(2))
    }

    @Test
    func projectOwnAgents_noTools_showsSetupPrompt() {
        let tools = RoomToolsView(roomID: "!r:host", agents: [
            RoomToolAgentEntry(agentID: "mine", matrixUserID: "@mine:host", displayName: "Scribe",
                               ownerUserID: "@o:host", isMine: true, tools: [])
        ])
        let agents = AgentSummary.ownAgents(in: tools)
        #expect(agents[0].statusLine == UntranslatedL10n.screenAgentSheetNoTools)
    }

    // MARK: - Loading

    @Test
    func appeared_loadsAgents() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(
            RoomToolsView(roomID: "!r:host", agents: [
                RoomToolAgentEntry(agentID: "mine", matrixUserID: "@mine:host", displayName: "Assistant",
                                   ownerUserID: "@o:host", isMine: true, tools: [])
            ]))
        let viewModel = AgentSheetScreenViewModel(roomID: "!r:host", agentPlatformService: service)

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            if case .loaded(let mine, _) = state { return mine.count == 1 }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()
    }

    // MARK: - Brief 0043 P4: multi-participant visibility

    @Test
    func appeared_splitsOwnAndOtherAgents() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(
            RoomToolsView(roomID: "!r:host", agents: [
                RoomToolAgentEntry(agentID: "mine", matrixUserID: "@mine:host", displayName: "Yours",
                                   ownerUserID: "@o:host", isMine: true, tools: []),
                RoomToolAgentEntry(agentID: "bob", matrixUserID: "@bob-agent:host", displayName: "Bob's agent",
                                   ownerUserID: "@b:host", isMine: false,
                                   tools: [RoomToolView(toolID: nil, toolKind: "summarize", triggerKind: "on_message",
                                                        targetLanguage: nil,
                                                        params: nil, trigger: nil, safeSliceSalt: "s")]),
                // Other participant with NO tools armed → excluded from the others list.
                RoomToolAgentEntry(agentID: "carol", matrixUserID: "@carol-agent:host", displayName: "Carol's agent",
                                   ownerUserID: "@c:host", isMine: false, tools: [])
            ]))
        let viewModel = AgentSheetScreenViewModel(roomID: "!r:host", agentPlatformService: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            if case .loaded(let mine, let others) = state { return mine.count == 1 && others.count == 1 }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()
        #expect(viewModel.context.viewState.agents.first?.agentID == "mine")
        #expect(viewModel.context.viewState.otherAgents.first?.agentID == "bob")
        #expect(viewModel.context.viewState.otherAgents.first?.isMine == false)
        #expect(viewModel.context.viewState.hasNoOwnAgent == false)
    }

    @Test
    func appeared_noOwnAgent_flagsCTA() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(
            RoomToolsView(roomID: "!r:host", agents: [
                RoomToolAgentEntry(agentID: "bob", matrixUserID: "@bob-agent:host", displayName: "Bob's agent",
                                   ownerUserID: "@b:host", isMine: false,
                                   tools: [RoomToolView(toolID: nil, toolKind: "translate", triggerKind: "on_message",
                                                        targetLanguage: nil,
                                                        params: nil, trigger: nil, safeSliceSalt: "s")])
            ]))
        let viewModel = AgentSheetScreenViewModel(roomID: "!r:host", agentPlatformService: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            if case .loaded(let mine, _) = state { return mine.isEmpty }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()
        #expect(viewModel.context.viewState.hasNoOwnAgent == true)
        #expect(viewModel.context.viewState.otherAgents.count == 1)
    }

    @Test
    func appeared_failure_setsFailed() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .failure(.serverError(status: 500))
        let viewModel = AgentSheetScreenViewModel(roomID: "!r:host", agentPlatformService: service)

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            if case .failed = state { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()
    }

    // MARK: - Actions

    @Test
    func selectAgent_emitsChosen() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(
            RoomToolsView(roomID: "!r:host", agents: [
                RoomToolAgentEntry(agentID: "mine", matrixUserID: "@mine:host", displayName: "Assistant",
                                   ownerUserID: "@o:host", isMine: true, tools: [])
            ]))
        let viewModel = AgentSheetScreenViewModel(roomID: "!r:host", agentPlatformService: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            if case .loaded = state { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .selectAgent(let item) = action { return item.agentID == "mine" }
            return false
        }
        viewModel.context.send(viewAction: .selectAgent(id: "mine"))
        try await deferred.fulfill()
    }

    /// A second tap while the first agent opens is ignored, so agent B's
    /// screen can't land over agent A's; once A's opened, taps count again.
    @Test
    func selectAgent_ignoresTapsWhileOneOpens() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(
            RoomToolsView(roomID: "!r:host", agents: [
                RoomToolAgentEntry(agentID: "a", matrixUserID: "@a:host", displayName: "A",
                                   ownerUserID: "@o:host", isMine: true, tools: []),
                RoomToolAgentEntry(agentID: "b", matrixUserID: "@b:host", displayName: "B",
                                   ownerUserID: "@o:host", isMine: true, tools: [])
            ]))
        let viewModel = AgentSheetScreenViewModel(roomID: "!r:host", agentPlatformService: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            if case .loaded = state { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()

        var selected: [String] = []
        let cancellable = viewModel.actionsPublisher.sink { action in
            if case .selectAgent(let agent) = action { selected.append(agent.agentID) }
        }
        defer { cancellable.cancel() }

        viewModel.context.send(viewAction: .selectAgent(id: "a"))
        viewModel.context.send(viewAction: .selectAgent(id: "b"))
        #expect(selected == ["a"])
        #expect(viewModel.context.viewState.openingAgentID == "a")

        viewModel.finishOpeningAgent()
        viewModel.context.send(viewAction: .selectAgent(id: "b"))
        #expect(selected == ["a", "b"])
    }

    @Test
    func addAgent_emitsAddAgent() async throws {
        let viewModel = AgentSheetScreenViewModel(roomID: "!r:host", agentPlatformService: AgentPlatformServiceMock())
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .addAgent = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .addAgent)
        try await deferred.fulfill()
    }
}

/// Room details › «Агенты» › an agent: the agent in this chat, then its tools.
@MainActor
struct AgentToolsFlowStateMachineTests {
    @Test
    func anAgentOnTheSheetOpensTheAgentInThisChat() {
        let machine = AgentToolsFlowStateMachine()
        machine.processEvent(.presentAgentSheet)
        machine.processEvent(.presentAgentInRoom(agentID: "a"))
        let inRoom = AgentToolsFlowStateMachine.State.agentInRoom(agentID: "a", previousState: .agentSheet)
        #expect(machine.state == inRoom)
        
        // «Добавить инструмент» → the catalog, and back.
        machine.processEvent(.presentCapabilities(agentID: "a"))
        #expect(machine.state == .capabilities(agentID: "a", previousState: inRoom))
        machine.processEvent(.dismissedCapabilities)
        #expect(machine.state == inRoom)
        
        // A tool → its form, and back.
        machine.processEvent(.presentArmTool(agentID: "a", capability: .translateMessages, editingToolID: "t1"))
        #expect(machine.state == .armTool(agentID: "a", capability: .translateMessages, editingToolID: "t1", previousState: inRoom))
        machine.processEvent(.dismissedArmTool)
        #expect(machine.state == inRoom)
        
        machine.processEvent(.dismissedAgentInRoom)
        #expect(machine.state == .agentSheet)
    }
}
