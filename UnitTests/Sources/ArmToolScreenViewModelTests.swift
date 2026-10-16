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
struct ArmToolScreenViewModelTests {
    @Test
    func submitTranslate_armsTypedParamsAndTrigger() async throws {
        let service = AgentPlatformServiceMock()
        service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReturnValue = .success(Self.appliedResult)

        let viewModel = Self.makeViewModel(service: service, capability: .translateMessages)
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

    @Test
    func submitLiveTranslation_armsVoiceTriggerWithStyle() async throws {
        let service = AgentPlatformServiceMock()
        service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReturnValue = .success(Self.appliedResult)

        let viewModel = Self.makeViewModel(service: service, capability: .liveCallTranslation)
        viewModel.applyLanguageSelection("Ukrainian")
        viewModel.applyLanguageSelection("German")
        viewModel.context.liveStyle = .consecutive
        viewModel.context.scope = .nonSelfNonOwner

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .finished = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .submit)
        try await deferred.fulfill()

        let received = try #require(service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReceivedArguments)
        #expect(received.params == .liveTranslate(targetLanguages: ["Ukrainian", "German"], style: .consecutive))
        #expect(received.trigger == .onVoiceCall(speakerScope: .nonSelfNonOwner))
    }

    @Test(arguments: [(AgentCapability.callSummary, ToolParams.callSummary),
                      (.callRecording, .callRecording)])
    func submitCallCapability_usesFixedVoiceTrigger(capability: AgentCapability, params: ToolParams) async throws {
        let service = AgentPlatformServiceMock()
        service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReturnValue = .success(Self.appliedResult)
        let viewModel = Self.makeViewModel(service: service, capability: capability)

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
    func liveTranslationLanguages_preserveOrderAndSupportRemoveAndMove() {
        let viewModel = Self.makeViewModel(service: AgentPlatformServiceMock(), capability: .liveCallTranslation)
        viewModel.applyLanguageSelection("en")
        viewModel.applyLanguageSelection("de")
        viewModel.applyLanguageSelection("uk")
        viewModel.context.send(viewAction: .moveLanguages(fromOffsets: IndexSet(integer: 2), toOffset: 0))
        viewModel.context.send(viewAction: .removeLanguage(index: 1))

        #expect(viewModel.context.viewState.bindings.targetLanguages == ["uk", "de"])
        #expect(viewModel.context.viewState.canSubmit)
    }

    @Test
    func liveTranslationRequiresAtLeastOneLanguage() {
        let viewModel = Self.makeViewModel(service: AgentPlatformServiceMock(), capability: .liveCallTranslation)
        #expect(!viewModel.context.viewState.canSubmit)
    }

    @Test
    func submitSpecificSenders_carriesMembersInScope() async throws {
        let service = AgentPlatformServiceMock()
        service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReturnValue = .success(Self.appliedResult)

        let viewModel = Self.makeViewModel(service: service, capability: .translateMessages)
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
        let viewModel = Self.makeViewModel(service: AgentPlatformServiceMock(), capability: .translateMessages)
        viewModel.context.scope = .anyone
        // No language typed.
        #expect(!viewModel.context.viewState.canSubmit)
    }

    @Test
    func submitBlocked_whenSpecificSendersHasNoMembers() {
        let viewModel = Self.makeViewModel(service: AgentPlatformServiceMock(), capability: .translateMessages)
        viewModel.context.language = "English"
        viewModel.context.scope = .specificSenders
        #expect(viewModel.context.viewState.isMissingMembers)
        #expect(!viewModel.context.viewState.canSubmit)
    }

    @Test
    func simplify_needsNoParamsAndCanSubmit() {
        let viewModel = Self.makeViewModel(service: AgentPlatformServiceMock(), capability: .translateMessages)
        viewModel.context.kind = .simplify
        viewModel.context.scope = .anyone
        #expect(viewModel.context.viewState.canSubmit)
    }

    @Test
    func turnOff_disablesEveryActiveTool() async throws {
        let service = AgentPlatformServiceMock()
        service.disableToolAgentIDRoomIDToolIDReturnValue = .success(Self.appliedResult)

        let viewModel = Self.makeViewModel(service: service,
                                           capability: .translateMessages,
                                           active: ActiveCapabilityTool(toolIDs: ["t1", "t2"], summary: "x", count: 2))

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .finished = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .turnOff)
        try Self.confirmTurnOff(viewModel)
        try await deferred.fulfill()

        #expect(service.disableToolAgentIDRoomIDToolIDCallsCount == 2)
    }

    /// Re-walk R5: a mistap on the bulk "Turn off" turned the room's tool off
    /// at once. It asks first, and cancelling leaves the tools on.
    @Test
    func turnOff_asksFirstAndCancelLeavesToolsOn() async throws {
        let service = AgentPlatformServiceMock()
        service.disableToolAgentIDRoomIDToolIDReturnValue = .success(Self.appliedResult)
        let viewModel = Self.makeViewModel(service: service,
                                           capability: .translateMessages,
                                           active: ActiveCapabilityTool(toolIDs: ["t1"], summary: "x", count: 1))

        viewModel.context.send(viewAction: .turnOff)

        let alert = try #require(viewModel.context.viewState.bindings.alertInfo)
        #expect(alert.id == .confirmTurnOff)
        #expect(alert.secondaryButton?.role == .destructive)
        alert.primaryButton.action?()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!service.disableToolAgentIDRoomIDToolIDCalled)
    }

    /// Re-walk R5: every text kind keeps exactly one parameters row, so a
    /// kind without a language no longer removes the section and slides the
    /// rows below (and the bulk "Turn off") up under the finger.
    @Test
    func everyTextKindKeepsOneParamsRow() {
        let viewModel = Self.makeViewModel(service: AgentPlatformServiceMock(),
                                           capability: .translateMessages,
                                           active: ActiveCapabilityTool(toolIDs: ["t1"], summary: "x", count: 1))
        for kind in ArmToolKind.allCases {
            viewModel.context.kind = kind
            #expect(viewModel.context.viewState.textParamsRow != nil, "\(kind) drops the parameters section")
        }
        viewModel.context.kind = .simplify
        #expect(viewModel.context.viewState.textParamsRow == .nothingToSet)
        viewModel.context.kind = .custom
        #expect(viewModel.context.viewState.textParamsRow == .instruction)
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

        let viewModel = Self.makeViewModel(service: service, capability: .translateMessages)
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

        let viewModel = Self.makeViewModel(service: service, capability: .translateMessages)
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

        let viewModel = Self.makeViewModel(service: service,
                                           capability: .translateMessages,
                                           active: ActiveCapabilityTool(toolIDs: ["t1"], summary: "x", count: 1))

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

        let viewModel = Self.makeViewModel(service: service, capability: .translateMessages)
        viewModel.context.language = "English"

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0 != nil }
        viewModel.context.send(viewAction: .submit)
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .armFailed)
        #expect(viewModel.context.viewState.bindings.alertInfo?.message == message)
    }

    /// Decision 168: the 422 for a call tool on a company agent says the agent
    /// doesn't join calls, not "doesn't work in this room". Told from the
    /// capability and the catalogue, never from the refusal's English detail.
    @Test(arguments: [
        // The call artifacts fire in every room for an agent that joins calls.
        (AgentCapability.callSummary, nil as [String]?, UntranslatedL10n.screenArmToolErrorAgentDoesNotJoinCalls),
        (.callRecording, nil, UntranslatedL10n.screenArmToolErrorAgentDoesNotJoinCalls),
        // Live translation: a catalogue with no call tool is an agent that joins no call…
        (.liveCallTranslation, ["translate", "summarize"], UntranslatedL10n.screenArmToolErrorAgentDoesNotJoinCalls),
        // …one with the call artifacts is a 1:1 room, where only translation is refused.
        (.liveCallTranslation, ["translate", "call_summary", "call_recording"], UntranslatedL10n.screenArmToolErrorDoesNotFireHere),
        (.translateMessages, ["call_summary", "call_recording"], UntranslatedL10n.screenArmToolErrorDoesNotFireHere)
    ])
    func aCallToolRefusedForAnAgentThatJoinsNoCallsSaysSo(capability: AgentCapability, availableToolKinds: [String]?, message: String) async throws {
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

        let viewModel = Self.makeViewModel(service: service, capability: capability)
        if capability == .liveCallTranslation || capability == .translateMessages {
            // The catalogue read the form starts with has answered.
            for _ in 0..<100 where service.fetchToolsCatalogAgentIDRoomIDCallsCount < 1 {
                try await Task.sleep(for: .milliseconds(5))
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        if capability == .liveCallTranslation {
            viewModel.context.targetLanguages = ["en"]
        } else if capability == .translateMessages {
            viewModel.context.language = "English"
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
        let viewModel = Self.makeViewModel(service: AgentPlatformServiceMock(), capability: .translateMessages)
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

        let viewModel = Self.makeViewModel(service: service, capability: .translateMessages)
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
        viewModel.context.send(viewAction: .selectLanguage(index: nil))
        try await deferred.fulfill()
    }

    @Test
    func selectLanguage_liveTranslation_offersVoiceCatalog() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(Self.catalog)

        let viewModel = Self.makeViewModel(service: service, capability: .liveCallTranslation)
        try await Self.waitForLanguages(viewModel, expected: Self.voiceLanguages)

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            // A live_translate (voice) tool MUST offer only the voice
            // allow-list — an off-list code crashes the runtime.
            if case .selectLanguage(let languages, _) = action {
                return languages == Self.voiceLanguages
            }
            return false
        }
        viewModel.context.send(viewAction: .selectLanguage(index: nil))
        try await deferred.fulfill()
    }

    @Test
    func selectLanguage_catalogFailure_offersNoLanguages() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .failure(.serverError(status: 500))

        let viewModel = Self.makeViewModel(service: service, capability: .translateMessages)

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            // A failed catalog fetch leaves the picker empty rather than
            // falling back to the whole ISO catalogue.
            if case .selectLanguage(let languages, _) = action { return languages.isEmpty }
            return false
        }
        viewModel.context.send(viewAction: .selectLanguage(index: nil))
        try await deferred.fulfill()
    }

    @Test
    func applyLanguageSelection_armsThatCode() async throws {
        let service = AgentPlatformServiceMock()
        service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReturnValue = .success(Self.appliedResult)

        let viewModel = Self.makeViewModel(service: service, capability: .translateMessages)
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
        #expect(viewModel.context.kind == .rephrase)
        #expect(viewModel.context.instruction == "more polite")
        #expect(viewModel.context.scope == .everyoneExcept)
        #expect(viewModel.context.viewState.bindings.members == ["@bob:host"])
    }

    @Test
    func editInit_seedsTranslateLanguage() {
        let viewModel = Self.editViewModel(params: .translate(targetLanguage: "German"),
                                           trigger: .onMessage(senderScope: .anyone),
                                           service: AgentPlatformServiceMock())
        #expect(viewModel.context.kind == .translate)
        #expect(viewModel.context.language == "German")
        #expect(viewModel.context.scope == .anyone)
    }

    @Test
    func editInit_seedsAllLiveTranslationLanguagesInOrder() {
        let viewModel = Self.editViewModel(capability: .liveCallTranslation,
                                           params: .liveTranslate(targetLanguages: ["uk", "en", "de"], style: .consecutive),
                                           trigger: .onVoiceCall(speakerScope: .anyone),
                                           service: AgentPlatformServiceMock())
        #expect(viewModel.context.viewState.bindings.targetLanguages == ["uk", "en", "de"])
        #expect(viewModel.context.liveStyle == .consecutive)
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

        let viewModel = Self.makeViewModel(service: service,
                                           capability: .translateMessages,
                                           active: ActiveCapabilityTool(toolIDs: ["t1"], summary: "x", count: 1))
        viewModel.context.language = "French"

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .finished = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .submit)
        try await deferred.fulfill()

        // Adding next to an active tool keeps it: several tools of a kind may be on.
        let armed = try #require(service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReceivedArguments)
        #expect(armed.replacesToolID == nil)
        #expect(!service.disableToolAgentIDRoomIDToolIDCalled)
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

    /// Poll until the view model has absorbed the catalog fetch fired at init.
    /// The fetch is async and not observable, so probe it via the emitted
    /// `selectLanguage` action; a bounded retry avoids racing the Task.
    private static func waitForLanguages(_ viewModel: ArmToolScreenViewModel,
                                         expected: [AgentLanguage]) async throws {
        for _ in 0..<50 {
            var emitted: [AgentLanguage]?
            let cancellable = viewModel.actionsPublisher.sink { action in
                if case .selectLanguage(let languages, _) = action { emitted = languages }
            }
            viewModel.context.send(viewAction: .selectLanguage(index: nil))
            cancellable.cancel()
            if emitted == expected { return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Give any mock a default catalog so the init-time `fetchToolsCatalog`
    /// (fired for translation capabilities) resolves instead of hitting the
    /// mock's un-configured-method crash. Tests that assert on the catalog
    /// set override this before constructing the view model.
    private static func withDefaultCatalog(_ service: any AgentPlatformServiceProtocol) -> any AgentPlatformServiceProtocol {
        if let mock = service as? AgentPlatformServiceMock,
           mock.fetchToolsCatalogAgentIDRoomIDReturnValue == nil {
            mock.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(catalog)
        }
        return service
    }

    private static func editViewModel(capability: AgentCapability = .translateMessages,
                                      params: ToolParams,
                                      trigger: TriggerKind,
                                      service: any AgentPlatformServiceProtocol) -> ArmToolScreenViewModel {
        _ = withDefaultCatalog(service)
        return ArmToolScreenViewModel(roomID: "!room:example.com",
                                      agentID: "agent-1",
                                      agentDisplayName: "Aria",
                                      editing: ActiveToolDetail(toolID: "old-1",
                                                                capability: capability,
                                                                params: params,
                                                                trigger: trigger,
                                                                title: "t", subtitle: "s"),
                                      agentPlatformService: service)
    }

    private static func makeViewModel(service: any AgentPlatformServiceProtocol,
                                      capability: AgentCapability,
                                      active: ActiveCapabilityTool? = nil) -> ArmToolScreenViewModel {
        _ = withDefaultCatalog(service)
        return ArmToolScreenViewModel(roomID: "!room:example.com",
                                      agentID: "agent-1",
                                      agentDisplayName: "Aria",
                                      capability: capability,
                                      active: active,
                                      agentPlatformService: service)
    }
}
