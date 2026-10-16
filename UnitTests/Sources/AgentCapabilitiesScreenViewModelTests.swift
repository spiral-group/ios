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
struct AgentCapabilitiesScreenViewModelTests {
    @Test
    func appearedAction_loadsAndProjectsOwnAgentTools() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: [
            Self.tool(id: "t1", kind: "translate", params: .translate(targetLanguage: "English")),
            Self.tool(id: "t2", kind: "live_translate",
                      params: .liveTranslate(targetLanguages: ["Ukrainian"], style: .simultaneous)),
            Self.tool(id: "t3", kind: "call_summary", params: .callSummary),
            Self.tool(id: "t4", kind: "call_recording", params: .callRecording)
        ]))

        let viewModel = Self.makeViewModel(service: service)

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        let translate = viewModel.context.viewState.activeTool(for: .translateMessages)
        let liveCall = viewModel.context.viewState.activeTool(for: .liveCallTranslation)
        #expect(translate?.toolIDs == ["t1"])
        #expect(translate?.summary == UntranslatedL10n.screenAgentToolsListTitleTranslate("English"))
        #expect(liveCall?.toolIDs == ["t2"])
        #expect(viewModel.context.viewState.activeTool(for: .callSummary)?.toolIDs == ["t3"])
        #expect(viewModel.context.viewState.activeTool(for: .callRecording)?.toolIDs == ["t4"])
        #expect(service.fetchRoomToolsRoomIDCallsCount == 1)
    }

    @Test
    func appearedAction_withNoOwnTools_projectsEmpty() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: []))

        let viewModel = Self.makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.activeTool(for: .translateMessages) == nil)
        #expect(viewModel.context.viewState.activeTool(for: .liveCallTranslation) == nil)
        #expect(viewModel.context.viewState.activeTool(for: .callSummary) == nil)
        #expect(viewModel.context.viewState.activeTool(for: .callRecording) == nil)
    }

    @Test
    func groupsMultipleTransformsUnderTranslateCapability() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: [
            Self.tool(id: "t1", kind: "translate", params: .translate(targetLanguage: "English")),
            Self.tool(id: "t2", kind: "summarize", params: .summarize)
        ]))

        let viewModel = Self.makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        let translate = viewModel.context.viewState.activeTool(for: .translateMessages)
        #expect(translate?.count == 2)
        #expect(translate?.summary == UntranslatedL10n.screenAgentsToolCount(2))
    }

    @Test
    func appearedAction_skipsRefetchWhenAlreadyLoaded() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: []))

        let viewModel = Self.makeViewModel(service: service)
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))
        #expect(service.fetchRoomToolsRoomIDCallsCount == 1)

        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))
        #expect(service.fetchRoomToolsRoomIDCallsCount == 1)
    }

    @Test
    func retryAction_refetchesEvenWhenLoaded() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: []))

        let viewModel = Self.makeViewModel(service: service)
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))
        #expect(service.fetchRoomToolsRoomIDCallsCount == 1)

        viewModel.context.send(viewAction: .retry)
        try await Task.sleep(for: .milliseconds(20))
        #expect(service.fetchRoomToolsRoomIDCallsCount == 2)
    }

    @Test
    func failedFetch_setsFailedStateAndShowsAlert() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .failure(.serverError(status: 500))

        let viewModel = Self.makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .failed = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.isFailed)
        #expect(viewModel.context.viewState.bindings.alertInfo != nil)
    }

    @Test
    func selectCapability_emitsCoordinatorActionWithActiveTool() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: [
            Self.tool(id: "t1", kind: "translate", params: .translate(targetLanguage: "English"))
        ]))

        let viewModel = Self.makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .selectCapability(.translateMessages, let active) = action {
                return active?.toolIDs == ["t1"]
            }
            return false
        }
        viewModel.context.send(viewAction: .selectCapability(.translateMessages))
        try await deferred.fulfill()
    }

    @Test
    func doneAction_emitsDismiss() async throws {
        let viewModel = Self.makeViewModel(service: AgentPlatformServiceMock())
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .dismiss = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .done)
        try await deferred.fulfill()
    }

    // MARK: - What can fire here (ADR-0088)

    @Test(arguments: [
        // The owner DM: only the call tools.
        (["call_summary", "call_recording"], [AgentCapability.callSummary, .callRecording]),
        // Another 1:1 room: everything but call translation.
        (["translate", "simplify", "correct", "rephrase", "summarize", "custom", "call_summary", "call_recording"],
         [.translateMessages, .callSummary, .callRecording]),
        // A group: everything.
        (groupRoomToolKinds, [.translateMessages, .liveCallTranslation, .callSummary, .callRecording]),
        // A kind this build does not know offers nothing new.
        (["call_recording", "dance"], [.callRecording])
    ])
    func offersOnlyCapabilitiesThatFireHere(availableToolKinds: [String], offered: [AgentCapability]) async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: []))
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(Self.catalog(availableToolKinds: availableToolKinds))

        let viewModel = Self.makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.offeredCapabilities == offered)
        #expect(service.fetchToolsCatalogAgentIDRoomIDReceivedArguments?.agentID == "agent-1")
        #expect(service.fetchToolsCatalogAgentIDRoomIDReceivedArguments?.roomID == "!room:example.com")
    }

    @Test
    func beforeTheReadsLoadNothingIsOffered() {
        let viewModel = Self.makeViewModel(service: AgentPlatformServiceMock())

        #expect(viewModel.context.viewState.offeredCapabilities.isEmpty)
    }

    /// Decision 168: a company agent's call tools never fire, so a failed
    /// catalog read can't mean "the call tools fire everywhere". It is
    /// "couldn't check", with a retry.
    @Test
    func aFailedCatalogIsCouldNotCheck() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: [
            Self.tool(id: "t3", kind: "call_summary", params: .callSummary)
        ]))
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .failure(.serverError(status: 500))

        let viewModel = Self.makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .failed = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.offeredCapabilities.isEmpty)
        #expect(viewModel.context.viewState.activeTool(for: .callSummary) == nil)
        #expect(viewModel.context.viewState.bindings.alertInfo != nil)
    }

    /// Review #1: an active tool must stay reachable so it can be turned off,
    /// even when the catalog leaves its kind out. It is not "On" then: the
    /// server lists it, but it never runs here.
    @Test
    func aCapabilityThatIsOnButCannotFireHereSaysSo() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: [
            Self.tool(id: "t2", kind: "live_translate", params: .liveTranslate(targetLanguages: ["uk"], style: .simultaneous)),
            Self.tool(id: "t3", kind: "call_summary", params: .callSummary)
        ]))
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(Self.catalog(availableToolKinds: ["call_summary", "call_recording"]))

        let viewModel = Self.makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        let viewState = viewModel.context.viewState
        #expect(viewState.offeredCapabilities == [.liveCallTranslation, .callSummary, .callRecording])
        #expect(viewState.isUnavailable(.liveCallTranslation))
        #expect(!viewState.isUnavailable(.callSummary))
        #expect(!viewState.isUnavailable(.callRecording))
    }

    /// Decision 168 (walk F4): the catalog leaves the call tools out for a
    /// company agent. None is offered, and one armed before 1.0.1 is not
    /// shown as on.
    @Test
    func aCompanyAgentIsOfferedNoCallTools() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: [
            Self.tool(id: "t1", kind: "translate", params: .translate(targetLanguage: "English")),
            Self.tool(id: "t3", kind: "call_summary", params: .callSummary)
        ]))
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(Self.catalog(availableToolKinds: Self.textToolKinds))

        let viewModel = Self.makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        let viewState = viewModel.context.viewState
        #expect(viewState.offeredCapabilities == [.translateMessages, .callSummary])
        #expect(!viewState.isUnavailable(.translateMessages))
        #expect(viewState.isUnavailable(.callSummary))
    }

    /// Fable review: the "Not available" row opened the full arm form, whose
    /// Turn on only the backend's 422 stopped. It offers only turning off,
    /// as the tools list does.
    @Test
    func anUnavailableRowOffersOnlyTurningItOff() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: [
            Self.tool(id: "t3", kind: "call_summary", params: .callSummary)
        ]))
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(Self.catalog(availableToolKinds: Self.textToolKinds))
        service.disableToolAgentIDRoomIDToolIDReturnValue = .success(ControlSetResultView(status: .applied, actionLogID: "log"))

        let viewModel = Self.makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()

        var forms = 0
        let cancellable = viewModel.actionsPublisher.sink { if case .selectCapability = $0 { forms += 1 } }
        let alerted = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo?.id)) { $0 != nil }
        viewModel.context.send(viewAction: .selectCapability(.callSummary))
        try await alerted.fulfill()

        #expect(forms == 0, "no arm form")
        let alert = try #require(viewModel.context.viewState.bindings.alertInfo)
        #expect(alert.id == .unavailable)
        let turnOff = try #require(alert.secondaryButton)
        #expect(turnOff.title == UntranslatedL10n.screenArmToolTurnOff)

        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: []))
        let reloaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded(let active) = $0 { return active.isEmpty }
            return false
        }
        turnOff.action?()
        try await reloaded.fulfill()
        #expect(service.disableToolAgentIDRoomIDToolIDReceivedArguments?.toolID == "t3")
        #expect(viewModel.context.viewState.offeredCapabilities == [.translateMessages])
        _ = cancellable
    }

    /// A row that can fire still opens the form.
    @Test
    func anAvailableRowOpensTheArmForm() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(Self.roomTools(ownTools: [
            Self.tool(id: "t3", kind: "call_summary", params: .callSummary)
        ]))
        let viewModel = Self.makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()

        let selected = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .selectCapability(.callSummary, let active) = action { return active?.toolIDs == ["t3"] }
            return false
        }
        viewModel.context.send(viewAction: .selectCapability(.callSummary))
        try await selected.fulfill()
        #expect(viewModel.context.viewState.bindings.alertInfo == nil)
    }

    /// Review #5: a pull-to-refresh while the first read is still out must
    /// not be undone when that older read lands last.
    @Test
    func anOlderReadNeverOverwritesANewerOne() async throws {
        let service = AgentPlatformServiceMock()
        let older = Self.roomTools(ownTools: [Self.tool(id: "t-old", kind: "translate", params: .translate(targetLanguage: "English"))])
        let newer = Self.roomTools(ownTools: [Self.tool(id: "t-new", kind: "call_summary", params: .callSummary)])
        service.fetchRoomToolsRoomIDClosure = { [service] _ in
            if service.fetchRoomToolsRoomIDCallsCount == 1 {
                try? await Task.sleep(for: .milliseconds(300))
                return .success(older)
            }
            return .success(newer)
        }

        let viewModel = Self.makeViewModel(service: service)
        viewModel.context.send(viewAction: .appeared)
        // The first read is out before the second one starts.
        for _ in 0..<100 where service.fetchRoomToolsRoomIDCallsCount < 1 {
            try await Task.sleep(for: .milliseconds(5))
        }
        let newerLoaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0.isLoaded(toolID: "t-new") }
        viewModel.context.send(viewAction: .retry)
        try await newerLoaded.fulfill()

        // Past the moment the older read answers.
        try await Task.sleep(for: .milliseconds(500))

        #expect(viewModel.context.viewState.activeTool(for: .callSummary)?.toolIDs == ["t-new"])
        #expect(viewModel.context.viewState.activeTool(for: .translateMessages) == nil)
    }

    // MARK: - Helpers

    private nonisolated static let groupRoomToolKinds = ["translate", "simplify", "correct", "rephrase", "summarize", "custom",
                                                         "live_translate", "call_summary", "call_recording"]
    private nonisolated static let textToolKinds = ["translate", "simplify", "correct", "rephrase", "summarize", "custom"]

    private static func catalog(availableToolKinds: [String]) -> ToolsCatalogView {
        ToolsCatalogView(agentID: "agent-1",
                         roomID: "!room:example.com",
                         paramsSchema: [:],
                         triggerSchema: [:],
                         textTranslationLanguages: [],
                         voiceTranslationLanguages: [],
                         availableToolKinds: availableToolKinds)
    }

    /// Every load reads the catalog too; a test that does not care about it
    /// gets a group room, where everything fires.
    private static func makeViewModel(service: any AgentPlatformServiceProtocol) -> AgentCapabilitiesScreenViewModel {
        if let mock = service as? AgentPlatformServiceMock, mock.fetchToolsCatalogAgentIDRoomIDReturnValue == nil {
            mock.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(catalog(availableToolKinds: groupRoomToolKinds))
        }
        return AgentCapabilitiesScreenViewModel(roomID: "!room:example.com",
                                                agentID: "agent-1",
                                                agentDisplayName: "Aria",
                                                agentPlatformService: service)
    }

    private static func tool(id: String, kind: String, params: ToolParams) -> RoomToolView {
        RoomToolView(toolID: id,
                     toolKind: kind,
                     triggerKind: kind == "live_translate" || kind.hasPrefix("call_") ? "on_voice_call" : "on_message",
                     targetLanguage: nil,
                     params: params,
                     trigger: kind == "live_translate" || kind.hasPrefix("call_") ? .onVoiceCall(speakerScope: .anyone) : .onMessage(senderScope: .anyone),
                     safeSliceSalt: id)
    }

    private static func roomTools(ownTools: [RoomToolView]) -> RoomToolsView {
        RoomToolsView(roomID: "!room:example.com",
                      agents: [
                          RoomToolAgentEntry(agentID: "agent-1",
                                             matrixUserID: "@agent:example.com",
                                             displayName: "Aria",
                                             ownerUserID: "@owner:example.com",
                                             isMine: true,
                                             tools: ownTools)
                      ])
    }
}

private extension AgentCapabilitiesListState {
    func isLoaded(toolID: String) -> Bool {
        guard case .loaded(let active) = self else { return false }
        return active.values.contains { $0.toolIDs.contains(toolID) }
    }
}
