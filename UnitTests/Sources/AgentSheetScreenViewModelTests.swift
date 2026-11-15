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
struct AgentSheetScreenViewModelTests {
    // MARK: - The groups (board A)

    @Test
    func eachOfYourAgentsIsAGroupWithItsTools() async throws {
        let (viewModel, _) = Self.makeViewModel(agents: [Self.mine(tools: [Self.ownTool("t1")])])
        let mine = try await Self.loaded(viewModel).mine

        #expect(mine.map(\.agent.agentID) == ["mine"])
        #expect(mine[0].tools.map(\.title) == [UntranslatedL10n.screenAgentToolsListTitleTranslate(TranslationLanguageDisplayName.localizedName(for: "en"))])
        #expect(mine[0].tools[0].subtitle == AgentToolTrigger.line(forKind: "translate", audience: .anyone))
        #expect(mine[0].quickAdd == .none, "with tools, it is «Add a tool» that stands there")
    }

    /// Brief 0043 P4: other people's agents are read-only, and one with no tools isn't listed.
    @Test
    func otherPeoplesAgentsComeWithTheirTools() async throws {
        let (viewModel, _) = Self.makeViewModel(agents: [Self.mine(tools: []),
                                                         Self.theirs(tools: [Self.slicedTool()]),
                                                         RoomToolAgentEntry(agentID: "carol", matrixUserID: "@carol-agent:host", displayName: "Carol's agent",
                                                                            ownerUserID: "@c:host", isMine: false, tools: [])])
        let others = try await Self.loaded(viewModel).others

        #expect(others.map(\.agent.agentID) == ["bob"])
        #expect(others[0].tools.map(\.title) == [UntranslatedL10n.screenArmToolKindSummarize])
        #expect(others[0].tools[0].subtitle == UntranslatedL10n.screenAgentRoomToolTriggerMessages)
    }

    /// The owner's name comes from the room; the read has only their Matrix ID.
    @Test
    func someoneElsesAgentSaysWhoseItIs() async throws {
        let members = [RoomMemberProxyMock(with: .init(userID: "@b:host", displayName: "Bohdan", membership: .join))]
        let (viewModel, _) = Self.makeViewModel(agents: [Self.theirs(tools: [Self.slicedTool()])], members: members)

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            if case .loaded(_, let others) = state { return others.first?.ownerLine != nil }
            return false
        }
        try await deferred.fulfill()
        let others = try await Self.loaded(viewModel).others
        #expect(others[0].ownerLine == UntranslatedL10n.screenChatToolsOtherAgentOwner("Bohdan"))
    }

    /// Re-walk R1 backend contract: a company agent has no `owner_user_id`;
    /// `is_mine` (true for every agent in a space the caller owns) alone
    /// says whose it is, so a plain member of the company gets no controls.
    @Test
    func aCompanyAgentIsYoursByIsMineAlone() async throws {
        let (viewModel, _) = Self.makeViewModel(agents: [
            RoomToolAgentEntry(agentID: "sales", matrixUserID: "@agent-acme-sales:host", displayName: "Acme Sales",
                               ownerUserID: nil, isMine: true, tools: []),
            RoomToolAgentEntry(agentID: "support", matrixUserID: "@agent-other-support:host", displayName: "Other Support",
                               ownerUserID: nil, isMine: false, tools: [Self.slicedTool()])
        ])
        let groups = try await Self.loaded(viewModel)

        #expect(groups.mine.map(\.agent.agentID) == ["sales"])
        #expect(groups.others.first?.ownerLine == nil)
    }

    // MARK: - Avatars (357 item 8)

    /// The room's tools carry no avatars: an own agent's comes from its card, and goes when its card has none;
    /// another person's agent's comes from the room's member.
    @Test
    func theRowsCarryTheAgentsAvatars() async throws {
        let picture = "mxc://host/own"
        let service = Self.makeService(agents: [
            RoomToolAgentEntry(agentID: "mine", matrixUserID: "@mine:host", displayName: "Mine", ownerUserID: "@o:host", isMine: true, tools: []),
            RoomToolAgentEntry(agentID: "bare", matrixUserID: "@bare:host", displayName: "Bare", ownerUserID: "@o:host", isMine: true, tools: []),
            RoomToolAgentEntry(agentID: "theirs", matrixUserID: "@theirs:host", displayName: "Theirs", ownerUserID: "@p:host", isMine: false, tools: [Self.slicedTool()])
        ])
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [.init(orgID: "o", name: "Personal", kind: .solo, avatarMXC: nil, agentCount: 2)],
                                                              provisioningStatus: .ready))
        func card(_ id: String, avatarMXC: String?) -> AgentSpaceAgentCard {
            AgentSpaceAgentCard(agentID: id, matrixUserID: "@\(id):host", displayName: id, avatarMXC: avatarMXC, kind: "personal_assistant",
                                visibility: "public", lifecycleState: "active", roomCount: 1, activeToolCount: 0)
        }
        service.fetchAgentSpaceOrgIDClosure = { _ in
            .success(.init(orgID: "o", name: "Personal", kind: .solo, avatarMXC: nil, industry: nil, website: nil,
                           agents: [card("mine", avatarMXC: picture), card("bare", avatarMXC: nil)]))
        }
        let memberPicture = URL(string: "mxc://host/member")
        let members = [RoomMemberProxyMock(with: .init(userID: "@theirs:host", avatarURL: memberPicture, membership: .join)),
                       RoomMemberProxyMock(with: .init(userID: "@bare:host", avatarURL: memberPicture, membership: .join))]
        let store = AgentsStore(service: service)
        await store.reread(.spaces)
        let viewModel = Self.makeViewModel(service: service, store: store, members: members)

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            if case .loaded(let mine, _) = state { return mine.first?.agent.avatarURL != nil }
            return false
        }
        try await deferred.fulfill()

        let groups = try await Self.loaded(viewModel)
        #expect(groups.mine.map(\.agent.avatarURL) == [URL(string: picture), nil])
        #expect(groups.others.map(\.agent.avatarURL) == [memberPicture])
    }

    // MARK: - Empty (board 4)

    /// Two rows straight to the form, translation and a call's summary first; "All tools" for the rest.
    @Test
    func anAgentWithNoToolsOffersTwoKindsAndAllTools() async throws {
        let (viewModel, _) = Self.makeViewModel(agents: [Self.mine(tools: [])], availableToolKinds: AgentToolKind.allCases.map(\.rawValue))

        #expect(try await Self.quickAdd(viewModel) == .kinds([.translate, .callSummary], hasMore: true))
    }

    /// The owner's chat with their assistant: the text tools don't fire there, so they aren't offered.
    @Test
    func theRowsOfferOnlyWhatFiresHere() async throws {
        let (viewModel, _) = Self.makeViewModel(agents: [Self.mine(tools: [])], availableToolKinds: ["call_summary", "call_recording"])

        #expect(try await Self.quickAdd(viewModel) == .kinds([.callSummary, .callRecording], hasMore: false))
    }

    /// A catalogue from a newer server may name a kind this build can't open: it isn't offered, and nothing crashes.
    @Test
    func aKindNewerThanThisBuildIsNotOffered() async throws {
        let (viewModel, _) = Self.makeViewModel(agents: [Self.mine(tools: [])], availableToolKinds: ["teleport", "simplify"])

        #expect(try await Self.quickAdd(viewModel) == .kinds([.simplify], hasMore: false))
    }

    /// A failed read of the catalogue is "couldn't check", never an agent with nothing to offer.
    @Test
    func aFailedCatalogueSaysSoAndRetries() async throws {
        let (viewModel, service) = Self.makeViewModel(agents: [Self.mine(tools: [])], catalog: .failure(.serverError(status: 500)))

        #expect(try await Self.quickAdd(viewModel) == .failed)

        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(Self.catalog(["simplify"]))
        let retried = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            if case .loaded(let mine, _) = state { return mine.first?.quickAdd == .kinds([.simplify], hasMore: false) }
            return false
        }
        viewModel.context.send(viewAction: .retryCatalog(agentID: "mine"))
        try await retried.fulfill()
    }

    @Test
    func aQuickRowOpensThatKindsForm() async throws {
        let (viewModel, _) = Self.makeViewModel(agents: [Self.mine(tools: [])])
        _ = try await Self.loaded(viewModel)

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .addToolOfKind(.callSummary, let agent) = action { return agent.agentID == "mine" }
            return false
        }
        viewModel.context.send(viewAction: .addToolOfKind(.callSummary, agentID: "mine"))
        try await deferred.fulfill()
    }

    @Test
    func addToolOpensTheKindsOfThatAgent() async throws {
        let (viewModel, _) = Self.makeViewModel(agents: [Self.mine(tools: [])])
        _ = try await Self.loaded(viewModel)

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .addTool(let agent) = action { return agent.agentID == "mine" }
            return false
        }
        viewModel.context.send(viewAction: .addTool(agentID: "mine"))
        try await deferred.fulfill()
    }

    /// Someone else's agent has no way to add a tool, whatever reaches the view model.
    @Test
    func nothingIsAddedToSomeoneElsesAgent() async throws {
        let (viewModel, _) = Self.makeViewModel(agents: [Self.theirs(tools: [Self.slicedTool()])])
        _ = try await Self.loaded(viewModel)

        var actions: [AgentSheetScreenViewModelAction] = []
        let cancellable = viewModel.actionsPublisher.sink { actions.append($0) }
        defer { cancellable.cancel() }
        viewModel.context.send(viewAction: .addTool(agentID: "bob"))
        viewModel.context.send(viewAction: .addToolOfKind(.translate, agentID: "bob"))
        viewModel.context.send(viewAction: .viewProfile(agentID: "bob"))
        viewModel.context.send(viewAction: .removeAgent(agentID: "bob"))

        #expect(actions.isEmpty)
        #expect(viewModel.context.viewState.bindings.alertInfo == nil)
    }

    // MARK: - Opening a tool

    @Test
    func yourToolOpensItsForm() async throws {
        let tool = Self.ownTool("t1")
        let (viewModel, _) = Self.makeViewModel(agents: [Self.mine(tools: [tool])])
        _ = try await Self.loaded(viewModel)

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .editTool(let detail, let agent) = action { return detail.toolID == "t1" && agent.agentID == "mine" }
            return false
        }
        viewModel.context.send(viewAction: .selectTool(agentID: "mine", toolID: tool.id))
        try await deferred.fulfill()
    }

    /// Board 3: someone's tool opens read-only, from what the safe slice gives.
    @Test
    func someoneElsesToolOpensReadOnly() async throws {
        let tool = Self.slicedTool()
        let (viewModel, _) = Self.makeViewModel(agents: [Self.theirs(tools: [tool])])
        _ = try await Self.loaded(viewModel)

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .viewTool(let detail) = action { return detail.agentName == "Bob's agent" }
            return false
        }
        viewModel.context.send(viewAction: .selectTool(agentID: "bob", toolID: tool.id))
        try await deferred.fulfill()
    }

    /// `isMine` decides: an id on someone else's tool opens no form, and neither does an own tool without an id.
    @Test(arguments: [(false, "t1" as String?), (true, nil)])
    func onlyAnOwnToolWithAnIDReachesTheForm(isMine: Bool, toolID: String?) async throws {
        let tool = RoomToolView(toolID: toolID, toolKind: "translate", triggerKind: "on_message", targetLanguage: "en",
                                params: .translate(targetLanguage: "en"), trigger: .onMessage(senderScope: .anyone),
                                safeSliceSalt: "t", appliesToViewer: .yes)
        let agent = isMine ? Self.mine(tools: [tool]) : Self.theirs(tools: [tool])
        let (viewModel, _) = Self.makeViewModel(agents: [agent])
        _ = try await Self.loaded(viewModel)

        var actions: [AgentSheetScreenViewModelAction] = []
        let cancellable = viewModel.actionsPublisher.sink { actions.append($0) }
        defer { cancellable.cancel() }
        viewModel.context.send(viewAction: .selectTool(agentID: agent.agentID, toolID: tool.id))

        guard case .viewTool = actions.first else {
            Issue.record("Expected the read-only page, got \(actions)")
            return
        }
    }

    /// Decision 168: the server may list a tool that can't fire here: the row says so and offers only turning it off.
    @Test
    func aToolThatCantFireHereOffersOnlyTurningItOff() async throws {
        let tool = Self.ownTool("t1")
        let (viewModel, service) = Self.makeViewModel(agents: [Self.mine(tools: [tool])], availableToolKinds: ["simplify"])
        service.disableToolAgentIDRoomIDToolIDReturnValue = .success(.init(status: .applied, actionLogID: "log"))
        let unavailable = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            if case .loaded(let mine, _) = state { return mine.first?.tools.first?.isUnavailable == true }
            return false
        }
        try await unavailable.fulfill()

        var actions: [AgentSheetScreenViewModelAction] = []
        let cancellable = viewModel.actionsPublisher.sink { actions.append($0) }
        defer { cancellable.cancel() }
        viewModel.context.send(viewAction: .selectTool(agentID: "mine", toolID: tool.id))

        #expect(actions.isEmpty)
        let alert = try #require(viewModel.context.viewState.bindings.alertInfo)
        #expect(alert.id == .unavailable)
        alert.secondaryButton?.action?()
        for _ in 0..<100 where !service.disableToolAgentIDRoomIDToolIDCalled {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(service.disableToolAgentIDRoomIDToolIDReceivedArguments?.toolID == "t1")
        #expect(service.disableToolAgentIDRoomIDToolIDReceivedArguments?.agentID == "mine")
    }

    /// A catalogue not read says nothing: the tool stays a working row, for the server to refuse if it must.
    @Test
    func aFailedCatalogueNeverCallsAToolUnavailable() async throws {
        let tool = Self.ownTool("t1")
        let (viewModel, _) = Self.makeViewModel(agents: [Self.mine(tools: [tool])], catalog: .failure(.serverError(status: 500)))
        let mine = try await Self.loaded(viewModel).mine

        #expect(mine[0].tools[0].isUnavailable == false)
    }

    /// Decision 96: a kind newer than this build has no form: it can only be turned off, knowingly.
    @Test
    func aToolOfANewerKindCanOnlyBeTurnedOff() async throws {
        let tool = RoomToolView(toolID: "t1", toolKind: "teleport", triggerKind: "on_message", targetLanguage: nil,
                                params: .unknown(kind: "teleport"), trigger: .onMessage(senderScope: .anyone),
                                safeSliceSalt: "t", appliesToViewer: .unknown)
        let (viewModel, _) = Self.makeViewModel(agents: [Self.mine(tools: [tool])], availableToolKinds: ["teleport"])
        let mine = try await Self.loaded(viewModel).mine
        #expect(mine[0].tools[0].title == UntranslatedL10n.screenAgentToolsListTitleUnknown)

        viewModel.context.send(viewAction: .selectTool(agentID: "mine", toolID: tool.id))
        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .needsUpdate)
    }

    // MARK: - The agent's menu

    @Test
    func theMenuOpensTheAgentsProfile() async throws {
        let (viewModel, _) = Self.makeViewModel(agents: [Self.mine(tools: [])])
        _ = try await Self.loaded(viewModel)

        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .viewProfile(userID: "@mine:host") }
        viewModel.context.send(viewAction: .viewProfile(agentID: "mine"))
        try await deferred.fulfill()
    }

    @Test
    func removingAnAgentAsksFirstThenLeavesAndReadsAgain() async throws {
        let (viewModel, service) = Self.makeViewModel(agents: [Self.mine(tools: [])])
        service.leaveRoomAgentIDRoomIDReturnValue = .success(())
        _ = try await Self.loaded(viewModel)

        viewModel.context.send(viewAction: .removeAgent(agentID: "mine"))
        #expect(!service.leaveRoomAgentIDRoomIDCalled)

        service.fetchRoomToolsRoomIDReturnValue = .success(RoomToolsView(roomID: Self.roomID, agents: []))
        let gone = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            if case .loaded(let mine, _) = state { return mine.isEmpty }
            return false
        }
        let alert = try #require(viewModel.context.viewState.bindings.alertInfo)
        #expect(alert.id == .confirmRemove)
        alert.primaryButton.action?()
        try await gone.fulfill()

        #expect(service.leaveRoomAgentIDRoomIDReceivedArguments?.agentID == "mine")
        #expect(service.leaveRoomAgentIDRoomIDReceivedArguments?.roomID == Self.roomID)
    }

    @Test
    func aFailedRemovalSaysSoAndTheAgentStays() async throws {
        let (viewModel, service) = Self.makeViewModel(agents: [Self.mine(tools: [])])
        service.leaveRoomAgentIDRoomIDReturnValue = .failure(.serverError(status: 500))
        _ = try await Self.loaded(viewModel)

        viewModel.context.send(viewAction: .removeAgent(agentID: "mine"))
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .removeFailed }
        try #require(viewModel.context.viewState.bindings.alertInfo).primaryButton.action?()
        try await failed.fulfill()

        #expect(try await Self.loaded(viewModel).mine.count == 1)
    }

    /// The owner's own chat with the agent is theirs with it: the agent stays (question 357, item 6).
    @Test
    func theOwnersOwnChatHasNoRemove() async throws {
        let client = ClientProxyMock(.init())
        client.directRoomForUserIDReturnValue = .success(Self.roomID)
        let service = Self.makeService(agents: [Self.mine(tools: [])])
        let viewModel = Self.makeViewModel(service: service, store: AgentsStore(service: service), clientProxy: client)

        #expect(try await Self.loaded(viewModel).mine.first?.canRemoveFromChat == false)
        viewModel.context.send(viewAction: .removeAgent(agentID: "mine"))
        #expect(viewModel.context.viewState.bindings.alertInfo == nil)
    }

    // MARK: - Reading

    /// A failure is no answer: the page says so and keeps "Add agent", and Retry reads again.
    @Test
    func aFailedReadIsNeverNoTools() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .failure(.serverError(status: 500))
        let viewModel = Self.makeViewModel(service: service, store: AgentsStore(service: service))

        let failed = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == .failed }
        try await failed.fulfill()

        service.fetchRoomToolsRoomIDReturnValue = .success(RoomToolsView(roomID: Self.roomID, agents: []))
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { if case .loaded = $0 { true } else { false } }
        viewModel.context.send(viewAction: .retry)
        try await loaded.fulfill()
    }

    /// Rule 359.9: what the store holds is there on the first render.
    @Test
    func whatTheStoreHoldsIsThereAtOnce() async {
        let service = Self.makeService(agents: [Self.mine(tools: [Self.ownTool("t1")])])
        let store = AgentsStore(service: service)
        await store.reread(.roomTools(roomID: Self.roomID))

        let viewModel = Self.makeViewModel(service: service, store: store)

        guard case .loaded(let mine, _) = viewModel.context.viewState.listState else {
            Issue.record("The sheet opened with no shape")
            return
        }
        #expect(mine.first?.tools.count == 1)
    }

    @Test
    func addAgent_emitsAddAgent() async throws {
        let (viewModel, _) = Self.makeViewModel(agents: [])
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .addAgent }
        viewModel.context.send(viewAction: .addAgent)
        try await deferred.fulfill()
    }

    // MARK: - Helpers

    private nonisolated static let roomID = "!r:host"

    private static func mine(tools: [RoomToolView]) -> RoomToolAgentEntry {
        RoomToolAgentEntry(agentID: "mine", matrixUserID: "@mine:host", displayName: "Assistant", ownerUserID: "@o:host", isMine: true, tools: tools)
    }

    private static func theirs(tools: [RoomToolView]) -> RoomToolAgentEntry {
        RoomToolAgentEntry(agentID: "bob", matrixUserID: "@bob-agent:host", displayName: "Bob's agent", ownerUserID: "@b:host", isMine: false, tools: tools)
    }

    private static func ownTool(_ id: String) -> RoomToolView {
        RoomToolView(toolID: id, toolKind: "translate", triggerKind: "on_message", targetLanguage: "en",
                     params: .translate(targetLanguage: "en"), trigger: .onMessage(senderScope: .anyone), safeSliceSalt: id, appliesToViewer: .yes)
    }

    private static func slicedTool() -> RoomToolView {
        RoomToolView(toolID: nil, toolKind: "summarize", triggerKind: "on_message", targetLanguage: nil,
                     params: nil, trigger: nil, safeSliceSalt: "s", appliesToViewer: .no)
    }

    private static func catalog(_ kinds: [String]) -> ToolsCatalogView {
        ToolsCatalogView(agentID: "mine", roomID: roomID, paramsSchema: [:], triggerSchema: [:],
                         textTranslationLanguages: [], voiceTranslationLanguages: [], availableToolKinds: kinds)
    }

    private static func makeService(agents: [RoomToolAgentEntry],
                                    catalog: Result<ToolsCatalogView, AgentPlatformError>? = nil,
                                    availableToolKinds: [String] = ["translate"]) -> AgentPlatformServiceMock {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(RoomToolsView(roomID: roomID, agents: agents))
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = catalog ?? .success(Self.catalog(availableToolKinds))
        return service
    }

    private static func makeViewModel(agents: [RoomToolAgentEntry],
                                      catalog: Result<ToolsCatalogView, AgentPlatformError>? = nil,
                                      availableToolKinds: [String] = ["translate"],
                                      members: [RoomMemberProxyMock] = []) -> (AgentSheetScreenViewModel, AgentPlatformServiceMock) {
        let service = makeService(agents: agents, catalog: catalog, availableToolKinds: availableToolKinds)
        return (makeViewModel(service: service, store: AgentsStore(service: service), members: members), service)
    }

    private static func makeViewModel(service: AgentPlatformServiceMock,
                                      store: AgentsStore,
                                      members: [RoomMemberProxyMock] = [],
                                      clientProxy: ClientProxyMock = ClientProxyMock(.init())) -> AgentSheetScreenViewModel {
        AgentSheetScreenViewModel(roomID: roomID,
                                  roomProxy: JoinedRoomProxyMock(.init(id: roomID, members: members)),
                                  store: store,
                                  agentPlatformService: service,
                                  clientProxy: clientProxy)
    }

    private static func loaded(_ viewModel: AgentSheetScreenViewModel) async throws -> (mine: [AgentSheetGroup], others: [AgentSheetGroup]) {
        if case .loaded(let mine, let others) = viewModel.context.viewState.listState, mine.allSatisfy({ $0.quickAdd != .loading }) {
            return (mine, others)
        }
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            if case .loaded(let mine, _) = state { return mine.allSatisfy { $0.quickAdd != .loading } }
            return false
        }
        try await deferred.fulfill()
        guard case .loaded(let mine, let others) = viewModel.context.viewState.listState else {
            throw CancellationError()
        }
        return (mine, others)
    }

    private static func quickAdd(_ viewModel: AgentSheetScreenViewModel) async throws -> AgentSheetQuickAdd? {
        try await loaded(viewModel).mine.first?.quickAdd
    }
}

/// A chat's tools: the one screen, and the screens that open from it.
@MainActor
struct AgentToolsFlowStateMachineTests {
    @Test
    func aToolOnTheSheetOpensItsFormAndComesBack() {
        let machine = AgentToolsFlowStateMachine()
        machine.processEvent(.presentAgentSheet)
        
        machine.processEvent(.presentArmTool(agentID: "a", kind: .translate, editingToolID: "t1"))
        #expect(machine.state == .armTool(agentID: "a", kind: .translate, editingToolID: "t1", previousState: .agentSheet))
        machine.processEvent(.dismissedArmTool)
        #expect(machine.state == .agentSheet)
    }
    
    /// «Добавить инструмент» → the kinds → the form. The form's save pops both, the form's dismissal first.
    @Test
    func addingAToolGoesThroughItsKinds() {
        let machine = AgentToolsFlowStateMachine()
        machine.processEvent(.presentAgentSheet)
        
        machine.processEvent(.presentAddTool(agentID: "a"))
        let kinds = AgentToolsFlowStateMachine.State.addTool(agentID: "a", previousState: .agentSheet)
        #expect(machine.state == kinds)
        machine.processEvent(.presentArmTool(agentID: "a", kind: .simplify, editingToolID: nil))
        #expect(machine.state == .armTool(agentID: "a", kind: .simplify, editingToolID: nil, previousState: kinds))
        
        machine.processEvent(.dismissedArmTool)
        machine.processEvent(.dismissedAddTool)
        #expect(machine.state == .agentSheet)
    }
    
    /// A just-added agent's kinds sit on the sheet: back is the sheet, not the popped picker.
    @Test
    func anInvitedAgentGoesStraightToItsKinds() {
        let machine = AgentToolsFlowStateMachine()
        machine.processEvent(.presentAgentSheet)
        machine.processEvent(.presentAddAgentPicker)
        
        machine.processEvent(.presentAddTool(agentID: "new"))
        #expect(machine.state == .addTool(agentID: "new", previousState: .agentSheet))
    }
    
    @Test
    func someonesToolOpensItsPageAndComesBack() {
        let machine = AgentToolsFlowStateMachine()
        machine.processEvent(.presentAgentSheet)
        
        machine.processEvent(.presentToolDetail)
        #expect(machine.state == .toolDetail(previousState: .agentSheet))
        machine.processEvent(.dismissedToolDetail)
        #expect(machine.state == .agentSheet)
    }
}
