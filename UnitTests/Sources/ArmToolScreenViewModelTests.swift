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

import Foundation
@testable import Spiral
import Testing

@MainActor
struct ArmToolScreenViewModelTests {
    @Test
    func submitTranslate_armsTypedParamsAndTrigger() async throws {
        let service = AgentPlatformServiceMock()
        service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReturnValue = .success(Self.appliedResult)

        let viewModel = Self.makeViewModel(service: service, kind: .translate)
        viewModel.context.language = "English"
        viewModel.context.scope = .anyone

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .finished = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .submit)
        try await deferred.fulfill()

        #expect(service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDCallsCount == 1)
        let received = try #require(service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReceivedArguments)
        #expect(received.params == .translate(targetLanguage: "English"))
        #expect(received.trigger == .onMessage(senderScope: .anyone))
    }

    @Test(arguments: [(AgentToolKind.callSummary, ToolParams.callSummary),
                      (.callRecording, .callRecording)])
    func submitCallTool_usesFixedVoiceTrigger(kind: AgentToolKind, params: ToolParams) async throws {
        let service = AgentPlatformServiceMock()
        service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReturnValue = .success(Self.appliedResult)
        let viewModel = Self.makeViewModel(service: service, kind: kind)

        #expect(!viewModel.context.viewState.showsScopeSelector)
        #expect(viewModel.context.viewState.canSubmit)

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .finished = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .submit)
        try await deferred.fulfill()

        let received = try #require(service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReceivedArguments)
        #expect(received.params == params)
        #expect(received.trigger == .onVoiceCall(speakerScope: .anyone))
    }

    @Test
    func submitSpecificSenders_carriesMembersInScope() async throws {
        let service = AgentPlatformServiceMock()
        service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReturnValue = .success(Self.appliedResult)

        let viewModel = Self.makeViewModel(service: service, kind: .translate)
        viewModel.context.language = "English"
        viewModel.context.scope = .specificSenders
        viewModel.applyMemberSelection(["@bob:host"])

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .finished = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .submit)
        try await deferred.fulfill()

        let received = try #require(service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReceivedArguments)
        #expect(received.trigger == .onMessage(senderScope: .specificSenders(members: ["@bob:host"])))
    }

    @Test
    func submitBlocked_whenTranslateLanguageEmpty() {
        let viewModel = Self.makeViewModel(service: AgentPlatformServiceMock(), kind: .translate)
        viewModel.context.scope = .anyone
        // No language typed.
        #expect(!viewModel.context.viewState.canSubmit)
    }

    @Test
    func submitBlocked_whenSpecificSendersHasNoMembers() {
        let viewModel = Self.makeViewModel(service: AgentPlatformServiceMock(), kind: .translate)
        viewModel.context.language = "English"
        viewModel.context.scope = .specificSenders
        #expect(viewModel.context.viewState.isMissingMembers)
        #expect(!viewModel.context.viewState.canSubmit)
    }

    @Test
    func simplify_needsNoParamsAndCanSubmit() {
        let viewModel = Self.makeViewModel(service: AgentPlatformServiceMock(), kind: .simplify)
        viewModel.context.scope = .anyone
        #expect(viewModel.context.viewState.canSubmit)
    }

    /// Board 2: a new tool opens the same form without "Turn off", which an edit has.
    @Test
    func aNewToolHasNoTurnOff() {
        let viewModel = Self.makeViewModel(service: AgentPlatformServiceMock(), kind: .translate)
        #expect(!viewModel.context.viewState.isEditing)

        let edit = Self.editViewModel(params: .translate(targetLanguage: "German"),
                                      trigger: .onMessage(senderScope: .anyone),
                                      service: AgentPlatformServiceMock())
        #expect(edit.context.viewState.isEditing)
    }

    @Test
    func turnOff_disablesTheEditedTool() async throws {
        let service = AgentPlatformServiceMock()
        service.disableToolAgentIDRoomIDToolIDReturnValue = .success(Self.appliedResult)
        let viewModel = Self.editViewModel(params: .translate(targetLanguage: "German"),
                                           trigger: .onMessage(senderScope: .anyone),
                                           service: service)

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .finished = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .turnOff)
        try Self.confirmTurnOff(viewModel)
        try await deferred.fulfill()

        #expect(service.disableToolAgentIDRoomIDToolIDCallsCount == 1)
        #expect(service.disableToolAgentIDRoomIDToolIDReceivedArguments?.toolID == "old-1")
    }

    /// Re-walk R5: a mistap on "Turn off" turned the room's tool off at once.
    /// It asks first, and cancelling leaves the tool on.
    @Test
    func turnOff_asksFirstAndCancelLeavesToolsOn() async throws {
        let service = AgentPlatformServiceMock()
        service.disableToolAgentIDRoomIDToolIDReturnValue = .success(Self.appliedResult)
        let viewModel = Self.editViewModel(params: .translate(targetLanguage: "German"),
                                           trigger: .onMessage(senderScope: .anyone),
                                           service: service)

        viewModel.context.send(viewAction: .turnOff)

        let alert = try #require(viewModel.context.viewState.bindings.alertInfo)
        #expect(alert.id == .confirmTurnOff)
        #expect(alert.secondaryButton?.role == .destructive)
        alert.primaryButton.action?()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!service.disableToolAgentIDRoomIDToolIDCalled)
    }

    private static func confirmTurnOff(_ viewModel: ArmToolScreenViewModel) throws {
        let alert = try #require(viewModel.context.viewState.bindings.alertInfo)
        #expect(alert.id == .confirmTurnOff)
        let turnOff = try #require(alert.secondaryButton?.action)
        turnOff()
    }

    @Test
    func armFailure_showsAlertAndDoesNotFinish() async throws {
        let service = AgentPlatformServiceMock()
        service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReturnValue = .failure(.failed(.transport(underlying: URLError(.timedOut))))

        let viewModel = Self.makeViewModel(service: service, kind: .translate)
        viewModel.context.language = "English"

        var finished = false
        let cancellable = viewModel.actionsPublisher.sink { action in
            if case .finished = action { finished = true }
        }
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0 != nil }
        viewModel.context.send(viewAction: .submit)
        try await deferred.fulfill()
        cancellable.cancel()

        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .armFailed)
        #expect(viewModel.context.viewState.bindings.alertInfo?.message == L10n.errorUnknown)
        #expect(!finished)
    }

    /// Review: a failure whose cause is known says so; only the rest stay generic.
    @Test(arguments: [(RoomToolArmError.failed(.forbidden), UntranslatedL10n.screenArmToolErrorForbidden),
                      (.failed(.serverError(status: 503)), UntranslatedL10n.screenArmToolErrorServer),
                      (.failed(.transport(underlying: URLError(.notConnectedToInternet))), L10n.errorUnknown)])
    func armFailure_saysWhatIsKnown(error: RoomToolArmError, message: String) async throws {
        let service = AgentPlatformServiceMock()
        service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReturnValue = .failure(error)

        let viewModel = Self.makeViewModel(service: service, kind: .translate)
        viewModel.context.language = "English"

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0 != nil }
        viewModel.context.send(viewAction: .submit)
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.bindings.alertInfo?.message == message)
    }

    @Test
    func turnOffFailure_saysWhatIsKnown() async throws {
        let service = AgentPlatformServiceMock()
        service.disableToolAgentIDRoomIDToolIDReturnValue = .failure(.forbidden)

        let viewModel = Self.editViewModel(params: .translate(targetLanguage: "German"),
                                           trigger: .onMessage(senderScope: .anyone),
                                           service: service)

        viewModel.context.send(viewAction: .turnOff)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .disableFailed }
        try Self.confirmTurnOff(viewModel)
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .disableFailed)
        #expect(viewModel.context.viewState.bindings.alertInfo?.message == UntranslatedL10n.screenArmToolErrorForbidden)
    }

    /// ADR-0088: each refusal the owner can act on says what to do, not
    /// "something went wrong".
    @Test(arguments: [(RoomToolRefusal.capReached, UntranslatedL10n.screenArmToolErrorCapReached),
                      (.duplicate, UntranslatedL10n.screenArmToolErrorDuplicate),
                      (.doesNotFireHere(reason: "a text tool never fires in the owner DM"), UntranslatedL10n.screenArmToolErrorDoesNotFireHere)])
    func armRefusal_showsItsOwnMessage(refusal: RoomToolRefusal, message: String) async throws {
        let service = AgentPlatformServiceMock()
        service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReturnValue = .failure(.refused(refusal))

        let viewModel = Self.makeViewModel(service: service, kind: .translate)
        viewModel.context.language = "English"

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0 != nil }
        viewModel.context.send(viewAction: .submit)
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .armFailed)
        #expect(viewModel.context.viewState.bindings.alertInfo?.message == message)
    }

    /// Decision 168: the 422 for a call tool on a company agent says the agent
    /// doesn't join calls, not "doesn't work in this room". Told from the
    /// kind and the catalogue, never from the refusal's English detail.
    @Test(arguments: [
        // The call artifacts fire in every room for an agent that joins calls.
        (AgentToolKind.callSummary, nil as [String]?, UntranslatedL10n.screenArmToolErrorAgentDoesNotJoinCalls),
        (.callRecording, nil, UntranslatedL10n.screenArmToolErrorAgentDoesNotJoinCalls),
        (.translate, ["call_summary", "call_recording"], UntranslatedL10n.screenArmToolErrorDoesNotFireHere)
    ])
    func aCallToolRefusedForAnAgentThatJoinsNoCallsSaysSo(kind: AgentToolKind, availableToolKinds: [String]?, message: String) async throws {
        let service = AgentPlatformServiceMock()
        service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReturnValue = .failure(.refused(.doesNotFireHere(reason: "the backend's own words")))
        if let availableToolKinds {
            service.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(ToolsCatalogView(agentID: "agent-1",
                                                                                          roomID: "!room:example.com",
                                                                                          paramsSchema: [:],
                                                                                          triggerSchema: [:],
                                                                                          textTranslationLanguages: [.init(code: "en", displayName: "English")],
                                                                                          voiceTranslationLanguages: [.init(code: "en", displayName: "English")],
                                                                                          availableToolKinds: availableToolKinds))
        }

        let viewModel = Self.makeViewModel(service: service, kind: kind)
        // The catalogue read the form starts with has answered.
        let read = deferFulfillment(viewModel.context.observe(\.viewState.isLoadingLanguages)) { !$0 }
        try await read.fulfill()
        if kind.needsLanguage {
            viewModel.context.language = "en"
        }

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0 != nil }
        viewModel.context.send(viewAction: .submit)
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.bindings.alertInfo?.message == message)
    }

    /// Review #4: the form holds the id of a tool that was turned off
    /// elsewhere. It says so, and on OK closes so the list reloads, rather
    /// than leaving the owner retrying a stale edit.
    @Test
    func editOfAToolTurnedOffElsewhere_saysSoThenClosesAndReloads() async throws {
        let service = AgentPlatformServiceMock()
        service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReturnValue = .failure(.replacedGone)

        let viewModel = Self.editViewModel(params: .translate(targetLanguage: "German"),
                                           trigger: .onMessage(senderScope: .anyone),
                                           service: service)
        viewModel.context.language = "French"

        var finished = false
        let cancellable = viewModel.actionsPublisher.sink { action in
            if case .finished = action { finished = true }
        }
        let alertShown = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0 != nil }
        viewModel.context.send(viewAction: .submit)
        try await alertShown.fulfill()

        let alert = try #require(viewModel.context.viewState.bindings.alertInfo)
        #expect(alert.message == UntranslatedL10n.screenArmToolErrorReplacedGone)
        #expect(!finished, "the owner reads why before the form goes")

        alert.primaryButton.action?()
        #expect(finished)
        cancellable.cancel()
    }

    @Test
    func selectMembers_emitsActionWithCurrentSelection() async throws {
        let viewModel = Self.makeViewModel(service: AgentPlatformServiceMock(), kind: .translate)
        viewModel.context.scope = .everyoneExcept
        viewModel.applyMemberSelection(["@a:host"])

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .selectMembers(let current) = action { return current == ["@a:host"] }
            return false
        }
        viewModel.context.send(viewAction: .selectMembers)
        try await deferred.fulfill()
    }

    @Test
    func selectLanguage_emitsActionWithTextCatalogAndCurrentCode() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(Self.catalog)

        let viewModel = Self.makeViewModel(service: service, kind: .translate)
        // The catalog fetch is fired at init; wait until the text set lands.
        try await Self.waitForLanguages(viewModel, expected: Self.textLanguages)
        viewModel.applyLanguageSelection("uk")

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            // A translate (text) tool offers the TEXT catalog set, never the
            // device ISO catalogue nor the voice set.
            if case .selectLanguage(let languages, let current) = action {
                return current == "uk" && languages == Self.textLanguages
            }
            return false
        }
        viewModel.context.send(viewAction: .selectLanguage)
        try await deferred.fulfill()
    }

    /// A failed read of the catalogue says so and reads again: an empty picker would read as "no languages".
    @Test
    func selectLanguage_catalogFailure_saysSoAndReadsAgain() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .failure(.serverError(status: 500))

        let viewModel = Self.makeViewModel(service: service, kind: .translate)
        let read = deferFulfillment(viewModel.context.observe(\.viewState.isLoadingLanguages)) { !$0 }
        try await read.fulfill()

        var opened = false
        let cancellable = viewModel.actionsPublisher.sink { action in
            if case .selectLanguage = action { opened = true }
        }
        defer { cancellable.cancel() }
        viewModel.context.send(viewAction: .selectLanguage)

        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .languagesFailed)
        #expect(!opened)
        for _ in 0..<100 where service.fetchToolsCatalogAgentIDRoomIDCallsCount < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(service.fetchToolsCatalogAgentIDRoomIDCallsCount >= 2)
    }

    @Test
    func applyLanguageSelection_armsThatCode() async throws {
        let service = AgentPlatformServiceMock()
        service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReturnValue = .success(Self.appliedResult)

        let viewModel = Self.makeViewModel(service: service, kind: .translate)
        viewModel.applyLanguageSelection("de")
        viewModel.context.scope = .anyone

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .finished = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .submit)
        try await deferred.fulfill()

        let received = try #require(service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReceivedArguments)
        #expect(received.params == .translate(targetLanguage: "de"))
    }

    // MARK: - Edit mode (F3c)

    @Test
    func editInit_seedsFormFromExistingTool() {
        let viewModel = Self.editViewModel(params: .rephrase(instruction: "more polite"),
                                           trigger: .onMessage(senderScope: .everyoneExcept(members: ["@bob:host"])),
                                           service: AgentPlatformServiceMock())
        #expect(viewModel.context.viewState.isEditing)
        #expect(viewModel.context.viewState.kind == .rephrase)
        #expect(viewModel.context.instruction == "more polite")
        #expect(viewModel.context.scope == .everyoneExcept)
        #expect(viewModel.context.viewState.bindings.members == ["@bob:host"])
    }

    @Test
    func editInit_seedsTranslateLanguage() {
        let viewModel = Self.editViewModel(params: .translate(targetLanguage: "German"),
                                           trigger: .onMessage(senderScope: .anyone),
                                           service: AgentPlatformServiceMock())
        #expect(viewModel.context.viewState.kind == .translate)
        #expect(viewModel.context.language == "German")
        #expect(viewModel.context.scope == .anyone)
    }

    /// ADR-0088: an edit is ONE arm carrying the replaced id; the backend
    /// turns the old tool off in the same transaction, so a separate disable
    /// would only fail (the tool is already off) or race the arm.
    @Test
    func editSubmit_replacesInOneArmCall() async throws {
        let service = AgentPlatformServiceMock()
        service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReturnValue = .success(Self.appliedResult)
        service.disableToolAgentIDRoomIDToolIDReturnValue = .success(Self.appliedResult)

        let viewModel = Self.editViewModel(params: .translate(targetLanguage: "German"),
                                           trigger: .onMessage(senderScope: .anyone),
                                           service: service)
        viewModel.context.language = "French"

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .finished = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .submit)
        try await deferred.fulfill()

        #expect(service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDCallsCount == 1)
        let armed = try #require(service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReceivedArguments)
        #expect(armed.params == .translate(targetLanguage: "French"))
        #expect(armed.replacesToolID == "old-1")
        #expect(!service.disableToolAgentIDRoomIDToolIDCalled)
    }

    @Test
    func createSubmit_replacesNothing() async throws {
        let service = AgentPlatformServiceMock()
        service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReturnValue = .success(Self.appliedResult)

        let viewModel = Self.makeViewModel(service: service, kind: .translate)
        viewModel.context.language = "French"

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .finished = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .submit)
        try await deferred.fulfill()

        // A new tool stands next to the others: several tools of a kind may be on.
        let armed = try #require(service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReceivedArguments)
        #expect(armed.replacesToolID == nil)
        #expect(!service.disableToolAgentIDRoomIDToolIDCalled)
    }

    /// ADR-0094 D9: Call translation is personal and has its own screen; this form never opens for it, new or edited,
    /// whichever flow asks.
    @Test
    func theFormNeverOpensForCallTranslation() {
        let service = AgentPlatformServiceMock()
        Self.withDefaultCatalog(service)
        let trigger = TriggerKind.onVoiceCall(speakerScope: .anyone)
        let tool = RoomToolView(toolID: "old-1", toolKind: "live_translate", triggerKind: trigger.kind, targetLanguage: nil,
                                params: .liveTranslate(language: "uk"), trigger: trigger, safeSliceSalt: "t", appliesToViewer: .yes)
        func coordinator(_ mode: ArmToolScreenCoordinatorParameters.Mode) -> ArmToolScreenCoordinator? {
            ArmToolScreenCoordinator(parameters: .init(roomID: "!room:example.com",
                                                       agentID: "agent-1",
                                                       agentDisplayName: "Aria",
                                                       mode: mode,
                                                       agentPlatformService: service,
                                                       store: AgentsStore(service: service)))
        }

        #expect(coordinator(.create(.liveTranslate)) == nil)
        #expect(ActiveToolDetail(tool).flatMap { coordinator(.edit($0)) } == nil)
        #expect(coordinator(.create(.translate)) != nil)
    }

    // MARK: - Helpers

    private static var appliedResult: ControlSetResultView {
        ControlSetResultView(status: .applied, actionLogID: "log-1")
    }

    private static let textLanguages = [AgentLanguage(code: "en", displayName: "English"),
                                        AgentLanguage(code: "uk", displayName: "Ukrainian"),
                                        AgentLanguage(code: "fr", displayName: "French")]
    private static let voiceLanguages = [AgentLanguage(code: "en", displayName: "English"),
                                         AgentLanguage(code: "de", displayName: "German")]

    private static var catalog: ToolsCatalogView {
        ToolsCatalogView(agentID: "agent-1",
                         roomID: "!room:example.com",
                         paramsSchema: [:],
                         triggerSchema: [:],
                         textTranslationLanguages: textLanguages,
                         voiceTranslationLanguages: voiceLanguages,
                         availableToolKinds: [])
    }

    /// Poll until the store's read of the catalog has landed, by the emitted
    /// `selectLanguage` action; a bounded retry avoids racing the read.
    private static func waitForLanguages(_ viewModel: ArmToolScreenViewModel,
                                         expected: [AgentLanguage]) async throws {
        for _ in 0..<50 {
            var emitted: [AgentLanguage]?
            let cancellable = viewModel.actionsPublisher.sink { action in
                if case .selectLanguage(let languages, _) = action { emitted = languages }
            }
            viewModel.context.send(viewAction: .selectLanguage)
            cancellable.cancel()
            if emitted == expected { return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Give any mock a default catalog so the store's read resolves instead of
    /// hitting the mock's un-configured-method crash. Tests that assert on the
    /// catalog set override this before constructing the view model.
    private static func withDefaultCatalog(_ service: AgentPlatformServiceMock) {
        if service.fetchToolsCatalogAgentIDRoomIDReturnValue == nil {
            service.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(catalog)
        }
    }

    private static func editViewModel(params: ToolParams,
                                      trigger: TriggerKind,
                                      service: AgentPlatformServiceMock) -> ArmToolScreenViewModel {
        withDefaultCatalog(service)
        let tool = RoomToolView(toolID: "old-1", toolKind: params.kind, triggerKind: trigger.kind, targetLanguage: nil,
                                params: params, trigger: trigger, safeSliceSalt: "t", appliesToViewer: .yes)
        guard let detail = ActiveToolDetail(tool),
              let viewModel = ArmToolScreenViewModel(roomID: "!room:example.com",
                                                     agentID: "agent-1",
                                                     agentDisplayName: "Aria",
                                                     editing: detail,
                                                     agentPlatformService: service,
                                                     store: AgentsStore(service: service)) else {
            fatalError("The test's tool is an own tool of a known kind")
        }
        return viewModel
    }

    private static func makeViewModel(service: AgentPlatformServiceMock, kind: AgentToolKind) -> ArmToolScreenViewModel {
        withDefaultCatalog(service)
        return ArmToolScreenViewModel(roomID: "!room:example.com",
                                      agentID: "agent-1",
                                      agentDisplayName: "Aria",
                                      kind: kind,
                                      agentPlatformService: service,
                                      store: AgentsStore(service: service))
    }
}
