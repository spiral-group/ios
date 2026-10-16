//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenViewModelTests.swift`.
//

@testable import ElementX
import Foundation
import Testing

@MainActor
struct AgentToolsListScreenViewModelTests {
    @Test
    func translationTitle_localizesCanonicalCode() {
        let name = TranslationLanguageDisplayName.localizedName(for: "zh-Hans")
        let title = AgentToolsListScreenViewModel.title(for: .translate(targetLanguage: "zh-Hans"))

        #expect(title == UntranslatedL10n.screenAgentToolsListTitleTranslate(name))
        #expect(!title.contains("zh-Hans"))
    }

    @Test
    func appearedAction_projectsOwnAgentToolsPerRow() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: [
            Self.tool(id: "t1", kind: "translate", params: .translate(targetLanguage: "English"),
                      trigger: .onMessage(senderScope: .anyone)),
            Self.tool(id: "t2", kind: "rephrase", params: .rephrase(instruction: "more polite"),
                      trigger: .onMessage(senderScope: .everyoneExcept(members: ["@bob:host"]))),
            Self.tool(id: "t3", kind: "call_summary", params: .callSummary,
                      trigger: .onVoiceCall(speakerScope: .anyone))
        ]))

        let viewModel = Self.makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        let tools = viewModel.context.viewState.tools
        #expect(tools.count == 3)
        #expect(tools[0].toolID == "t1")
        #expect(tools[0].params == .translate(targetLanguage: "English"))
        #expect(tools[0].capability == .translateMessages)
        #expect(tools[1].toolID == "t2")
        #expect(tools[1].params == .rephrase(instruction: "more polite"))
        #expect(tools[2].capability == .callSummary)
        #expect(tools[2].title == UntranslatedL10n.screenAgentCapabilitiesCallSummaryTitle)
    }

    @Test
    func projection_dropsToolsMissingId() {
        // Safe-slice tools (nil id/params) must be dropped — only own tools show.
        let roomTools = RoomToolsView(roomID: "!room:example.com",
                                      agents: [RoomToolAgentEntry(agentID: "agent-1",
                                                                  matrixUserID: "@agent:host",
                                                                  displayName: "Aria",
                                                                  ownerUserID: "@owner:host",
                                                                  isMine: true,
                                                                  tools: [
                                                                      Self.tool(id: "t1", kind: "translate",
                                                                                params: .translate(targetLanguage: "en"),
                                                                                trigger: .onMessage(senderScope: .anyone)),
                                                                      RoomToolView(toolID: nil, toolKind: "translate", triggerKind: "on_message",
                                                                                   targetLanguage: nil,
                                                                                   params: nil, trigger: nil, safeSliceSalt: "x")
                                                                  ])])
        let tools = AgentToolsListScreenViewModel.projectTools(from: roomTools, ownAgentID: "agent-1")
        #expect(tools.count == 1)
        #expect(tools[0].toolID == "t1")
    }

    @Test
    func selectTool_emitsEditWithDetail() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: [
            Self.tool(id: "t1", kind: "translate", params: .translate(targetLanguage: "English"),
                      trigger: .onMessage(senderScope: .anyone))
        ]))
        let viewModel = Self.makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .editTool(let detail) = action { return detail.toolID == "t1" }
            return false
        }
        viewModel.context.send(viewAction: .selectTool(id: "t1"))
        try await deferred.fulfill()
    }

    /// Decision 96: an edit replaces the tool, so one whose trigger or scope
    /// this build does not know (a newer platform's) is not opened in the
    /// form, which would write a trigger the user never saw. The row says to
    /// update the app; a tap offers only turning the tool off.
    @Test(arguments: [TriggerKind.unknown(kind: "on_schedule"),
                      .onMessage(senderScope: .unknown(tag: "contacts_only", members: []))])
    func aToolWithAnUnknownTriggerIsNotEdited(trigger: TriggerKind) async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: [
            Self.tool(id: "t1", kind: "translate", params: .translate(targetLanguage: "en"), trigger: trigger)
        ]))
        service.disableToolAgentIDRoomIDToolIDReturnValue = .success(ControlSetResultView(status: .applied, actionLogID: "log"))
        let viewModel = Self.makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()
        #expect(viewModel.context.viewState.tools.first?.subtitle == UntranslatedL10n.screenAgentToolsListNeedsUpdateTitle)

        var edits = 0
        let cancellable = viewModel.actionsPublisher.sink { if case .editTool = $0 { edits += 1 } }
        let alerted = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo?.id)) { $0 != nil }
        viewModel.context.send(viewAction: .selectTool(id: "t1"))
        try await alerted.fulfill()

        #expect(edits == 0, "no edit form")
        let alert = try #require(viewModel.context.viewState.bindings.alertInfo)
        #expect(alert.id == .needsUpdate)
        #expect(alert.title == UntranslatedL10n.screenAgentToolsListNeedsUpdateTitle)
        // Turning it off removes the whole tool, knowingly.
        let turnOff = try #require(alert.secondaryButton)
        #expect(turnOff.title == UntranslatedL10n.screenArmToolTurnOff)
        let reloaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loading = $0 { return true }
            return false
        }
        turnOff.action?()
        try await reloaded.fulfill()
        #expect(service.disableToolAgentIDRoomIDToolIDReceivedArguments?.toolID == "t1")
        _ = cancellable
    }

    /// Decision 168 (walk F4): a company agent's catalogue has no call tools.
    /// An old call tool the server still lists is not shown as armed, and a
    /// tap offers only turning it off — editing would re-arm a dead tool.
    @Test
    func aToolThatCannotFireHereIsShownAsSuchAndOnlyTurnedOff() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: [
            Self.tool(id: "t1", kind: "translate", params: .translate(targetLanguage: "en"), trigger: .onMessage(senderScope: .anyone)),
            Self.tool(id: "t3", kind: "call_summary", params: .callSummary, trigger: .onVoiceCall(speakerScope: .anyone))
        ]))
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(Self.catalog(availableToolKinds: ["translate", "simplify", "correct",
                                                                                                       "rephrase", "summarize", "custom"]))
        service.disableToolAgentIDRoomIDToolIDReturnValue = .success(ControlSetResultView(status: .applied, actionLogID: "log"))
        let viewModel = Self.makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()

        let tools = viewModel.context.viewState.tools
        #expect(tools.map(\.toolID) == ["t1", "t3"])
        #expect(tools.map(\.canFire) == [true, false])

        var edits = 0
        let cancellable = viewModel.actionsPublisher.sink { if case .editTool = $0 { edits += 1 } }
        let alerted = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo?.id)) { $0 != nil }
        viewModel.context.send(viewAction: .selectTool(id: "t3"))
        try await alerted.fulfill()

        #expect(edits == 0, "no edit form")
        let alert = try #require(viewModel.context.viewState.bindings.alertInfo)
        #expect(alert.id == .unavailable)
        let turnOff = try #require(alert.secondaryButton)
        #expect(turnOff.title == UntranslatedL10n.screenArmToolTurnOff)
        let reloaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loading = $0 { return true }
            return false
        }
        turnOff.action?()
        try await reloaded.fulfill()
        #expect(service.disableToolAgentIDRoomIDToolIDReceivedArguments?.toolID == "t3")
        _ = cancellable
    }

    /// Without the catalogue nothing says which listed tools run: "couldn't
    /// check", never a list that calls them all armed.
    @Test
    func aFailedCatalogIsCouldNotCheck() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: [
            Self.tool(id: "t3", kind: "call_summary", params: .callSummary, trigger: .onVoiceCall(speakerScope: .anyone))
        ]))
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .failure(.serverError(status: 500))
        let viewModel = Self.makeViewModel(service: service)
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .failed = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await failed.fulfill()

        #expect(viewModel.context.viewState.tools.isEmpty)
        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .loadFailed)
    }

    @Test
    func turnOffTool_disablesThenReloads() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: [
            Self.tool(id: "t1", kind: "translate", params: .translate(targetLanguage: "en"),
                      trigger: .onMessage(senderScope: .anyone))
        ]))
        service.disableToolAgentIDRoomIDToolIDReturnValue = .success(ControlSetResultView(status: .applied, actionLogID: "log"))

        let viewModel = Self.makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()

        viewModel.context.send(viewAction: .turnOffTool(id: "t1"))
        try await Task.sleep(for: .milliseconds(30))
        #expect(service.disableToolAgentIDRoomIDToolIDCallsCount == 1)
        #expect(service.disableToolAgentIDRoomIDToolIDReceivedArguments?.toolID == "t1")
        // reload → fetch called again (once on appear + once after turn-off).
        #expect(service.fetchRoomToolsRoomIDCallsCount == 2)
    }

    @Test
    func turnOffToolFailure_saysWhatIsKnown() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: [
            Self.tool(id: "t1", kind: "translate", params: .translate(targetLanguage: "en"),
                      trigger: .onMessage(senderScope: .anyone))
        ]))
        service.disableToolAgentIDRoomIDToolIDReturnValue = .failure(.serverError(status: 502))

        let viewModel = Self.makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()

        let alert = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0 != nil }
        viewModel.context.send(viewAction: .turnOffTool(id: "t1"))
        try await alert.fulfill()

        #expect(viewModel.context.viewState.bindings.alertInfo?.message == UntranslatedL10n.screenArmToolErrorServer)
    }

    @Test
    func addTool_emitsAddAction() async throws {
        let viewModel = Self.makeViewModel(service: AgentPlatformServiceMock())
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .addTool = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .addTool)
        try await deferred.fulfill()
    }

    @Test
    func done_emitsDismiss() async throws {
        let viewModel = Self.makeViewModel(service: AgentPlatformServiceMock())
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .dismiss = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .done)
        try await deferred.fulfill()
    }

    @Test
    func failedFetch_setsFailedStateAndAlert() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .failure(.serverError(status: 500))
        let viewModel = Self.makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .failed = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()
        #expect(viewModel.context.viewState.bindings.alertInfo != nil)
    }

    // MARK: - Helpers

    /// Every load reads the catalogue too; a test that does not care about
    /// it gets a group room, where every kind fires.
    private static func makeViewModel(service: any AgentPlatformServiceProtocol) -> AgentToolsListScreenViewModel {
        if let mock = service as? AgentPlatformServiceMock, mock.fetchToolsCatalogAgentIDRoomIDReturnValue == nil {
            mock.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(catalog(availableToolKinds: ["translate", "simplify", "correct", "rephrase",
                                                                                                    "summarize", "custom", "live_translate",
                                                                                                    "call_summary", "call_recording"]))
        }
        return AgentToolsListScreenViewModel(roomID: "!room:example.com",
                                      agentID: "agent-1",
                                      agentDisplayName: "Aria",
                                      agentPlatformService: service)
    }

    private static func catalog(availableToolKinds: [String]) -> ToolsCatalogView {
        ToolsCatalogView(agentID: "agent-1",
                         roomID: "!room:example.com",
                         paramsSchema: [:],
                         triggerSchema: [:],
                         textTranslationLanguages: [],
                         voiceTranslationLanguages: [],
                         availableToolKinds: availableToolKinds)
    }

    private static func tool(id: String, kind: String, params: ToolParams, trigger: TriggerKind) -> RoomToolView {
        RoomToolView(toolID: id, toolKind: kind, triggerKind: trigger.kind,
                     targetLanguage: nil,
                     params: params, trigger: trigger, safeSliceSalt: id)
    }

    private static func roomTools(ownTools: [RoomToolView]) -> RoomToolsView {
        RoomToolsView(roomID: "!room:example.com",
                      agents: [RoomToolAgentEntry(agentID: "agent-1",
                                                  matrixUserID: "@agent:host",
                                                  displayName: "Aria",
                                                  ownerUserID: "@owner:host",
                                                  isMine: true,
                                                  tools: ownTools)])
    }
}
