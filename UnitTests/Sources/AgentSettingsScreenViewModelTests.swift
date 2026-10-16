//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: the agent's «Настройки» (decision 194) — one PATCH with
// only what changed, choices at once with a step back on failure, the
// persona rules of step A (B1, B5) and the in-flight fields behind the
// contract flag.
//

@testable import ElementX
import Foundation
import Synchronization
import Testing

@MainActor
struct AgentSettingsScreenViewModelTests {
    /// The call language is named in the app's language, like the tool's picker.
    @Test
    func callLanguagesAreNamedInTheAppsLanguage() {
        let russian = Locale(identifier: "ru")
        #expect(AgentVoiceLanguage.allCases.map { $0.title(locale: russian) } == ["Украинский", "Русский", "Английский"])
        #expect(AgentVoiceLanguage.uk.title(locale: Locale(identifier: "en")) == "Ukrainian")
    }
    
    private static let assistant = AgentSpaceAgentCard(agentID: "agent-1", matrixUserID: "@assistant-owner:spiral.md",
                                                       displayName: "Assistant", avatarMXC: nil, kind: "personal_assistant",
                                                       visibility: "public", lifecycleState: "active", presence: .online,
                                                       roomCount: 1, activeToolCount: 0)

    private static let salesAgent = AgentSpaceAgentCard(agentID: "agent-2", matrixUserID: "@agent-sales:spiral.md",
                                                        displayName: "Sales", avatarMXC: nil, kind: "sales",
                                                        visibility: "private", lifecycleState: "active", presence: .online,
                                                        roomCount: 0, activeToolCount: 0)

    private static let schema = AgentEditSchema(agentID: "agent-1",
                                                kind: "personal_assistant",
                                                displayName: .init(minLength: 1, maxLength: 64),
                                                persona: .init(ownerDisplayName: .init(minLength: 1, maxLength: 64),
                                                               tone: .init(minLength: 1, maxLength: 10),
                                                               greeting: .init(minLength: 1, maxLength: 500),
                                                               visitorGreeting: .init(minLength: 1, maxLength: 500)))

    private static func persona(tone: String = "warm", greeting: String = "Hi!") -> PersonaView {
        PersonaView(agentID: "agent-1", ownerDisplayName: "Boss", tone: tone, greeting: greeting, visitorGreeting: "Hello.",
                    toolUseEnabled: nil, model: nil, configVersionID: "cfg-1", versionNumber: 1)
    }

    private static func readModel(for card: AgentSpaceAgentCard,
                                  persona: PersonaView? = persona(),
                                  visibility: String? = nil,
                                  roleBrief: String? = nil,
                                  visitorPolicy: AgentVisitorPolicy? = nil,
                                  voiceLanguage: AgentVoiceLanguage? = nil) -> AgentReadModel {
        AgentReadModel(agentID: card.agentID, matrixUserID: card.matrixUserID, displayName: card.displayName, avatarMXC: nil,
                       kind: card.kind, visibility: visibility ?? card.visibility, lifecycleState: "active", organizationID: "org-1",
                       roomCount: 0, activeToolCount: 0, configVersionNumber: 1,
                       persona: card.isPersonalAssistant ? persona : nil,
                       roleBrief: roleBrief, voiceLanguage: voiceLanguage, visitorPolicy: visitorPolicy)
    }

    private func loadedViewModel(section: AgentSettingsSection,
                                 card: AgentSpaceAgentCard = Self.assistant,
                                 service: AgentPlatformServiceMock) async throws -> AgentSettingsScreenViewModel {
        service.fetchAgentEditSchemaAgentIDReturnValue = .success(Self.schema)
        if service.fetchAgentReadModelAgentIDReturnValue == nil {
            service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(for: card))
        }
        let viewModel = AgentSettingsScreenViewModel(agent: card,
                                                     section: section,
                                                     agentPlatformService: service,
                                                     userIndicatorController: UserIndicatorControllerMock())
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 != .loading }
        try await loaded.fulfill()
        return viewModel
    }

    private func save(_ viewModel: AgentSettingsScreenViewModel, service: AgentPlatformServiceMock) async throws {
        let before = service.editAgentAgentIDPatchCallsCount
        let done = deferFulfillment(viewModel.context.observe(\.viewState.isSaving)) { isSaving in
            !isSaving && service.editAgentAgentIDPatchCallsCount > before
        }
        viewModel.context.send(viewAction: .save)
        try await done.fulfill()
    }

    // MARK: - Sections

    @Test
    func eachSectionHasItsOwnFields() async throws {
        let character = try await loadedViewModel(section: .character, service: AgentPlatformServiceMock())
        #expect(character.context.viewState.personaFields == [.ownerDisplayName, .tone, .greeting])
        #expect(!character.context.viewState.showsSearchToggle)

        let people = try await loadedViewModel(section: .people, service: AgentPlatformServiceMock())
        #expect(people.context.viewState.personaFields == [.visitorGreeting])
        #expect(people.context.viewState.showsSearchToggle)

        let roleBrief = try await loadedViewModel(section: .character, card: Self.salesAgent, service: AgentPlatformServiceMock())
        #expect(roleBrief.context.viewState.personaFields.isEmpty)
        #expect(roleBrief.context.viewState.showsRoleBrief)
    }

    /// B1: without a read there is nothing to compare against — no fields.
    @Test
    func aFailedReadShowsNoFields() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentReadModelAgentIDReturnValue = .failure(.serverError(status: 500))
        let viewModel = try await loadedViewModel(section: .character, service: service)

        #expect(viewModel.context.viewState.loadState == .failure)
        #expect(viewModel.context.viewState.personaFields.isEmpty)
        #expect(!viewModel.context.viewState.canSave)
    }

    /// Decisions 193/194: each choice shows the server's value, and no row
    /// for a value the server hasn't given (or one this build doesn't know).
    @Test
    func theChoicesShowTheServersValues() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(for: Self.assistant, visitorPolicy: .off, voiceLanguage: .ru))
        let people = try await loadedViewModel(section: .people, service: service)
        #expect(people.context.viewState.visitorPolicy == .off)
        #expect(people.context.visitorPolicy == .off)
        let calls = try await loadedViewModel(section: .calls, service: service)
        #expect(calls.context.viewState.voiceLanguage == .ru)
        #expect(calls.context.voiceLanguage == .ru)

        let withoutValue = try await loadedViewModel(section: .people, service: AgentPlatformServiceMock())
        #expect(withoutValue.context.viewState.visitorPolicy == nil)
        let silent = try await loadedViewModel(section: .calls, service: AgentPlatformServiceMock())
        #expect(silent.context.viewState.voiceLanguage == nil)
    }

    // MARK: - Text

    @Test
    func saveSendsOnlyTheChangedText() async throws {
        let service = AgentPlatformServiceMock()
        let viewModel = try await loadedViewModel(section: .character, service: service)
        #expect(!viewModel.context.viewState.canSave)

        viewModel.context.greeting = "Hello there"
        #expect(viewModel.context.viewState.canSave)
        service.editAgentAgentIDPatchReturnValue = .success(Self.readModel(for: Self.assistant, persona: Self.persona(greeting: "Hello there")))
        try await save(viewModel, service: service)

        #expect(service.editAgentAgentIDPatchReceivedArguments?.patch == AgentEditPatch(persona: .init(greeting: "Hello there")))
        #expect(!viewModel.context.viewState.canSave)
    }

    @Test
    func anEmptiedFieldBlocksSaveAndAWhitespaceEditIsNoChange() async throws {
        let viewModel = try await loadedViewModel(section: .character, service: AgentPlatformServiceMock())
        viewModel.context.greeting = "   "
        #expect(viewModel.context.viewState.personaIssue(.greeting) == .empty)
        #expect(!viewModel.context.viewState.canSave)

        viewModel.context.greeting = " Hi! "
        #expect(!viewModel.context.viewState.personaDidChange(.greeting))
        #expect(!viewModel.context.viewState.canSave)
    }

    /// B5: the limit is why Save is off, counted as the server counts.
    @Test
    func aTooLongFieldBlocksSave() async throws {
        let viewModel = try await loadedViewModel(section: .character, service: AgentPlatformServiceMock())
        viewModel.context.send(viewAction: .selectTone(.custom))
        viewModel.context.tone = "a much longer tone"
        #expect(viewModel.context.viewState.personaIssue(.tone) == .tooLong)
        #expect(!viewModel.context.viewState.canSave)

        viewModel.context.tone = "👍🏽👍🏽"
        #expect(viewModel.context.viewState.personaLength(.tone) == 4)
        #expect(viewModel.context.viewState.personaIssue(.tone) == nil)
    }

    /// A save that fails may have half-landed: re-read, keep the edit.
    @Test
    func aFailedSaveRereadsAndKeepsTheEdit() async throws {
        let service = AgentPlatformServiceMock()
        let viewModel = try await loadedViewModel(section: .character, service: service)
        viewModel.context.greeting = "Hello there"

        service.editAgentAgentIDPatchReturnValue = .failure(.serverError(status: 500))
        try await save(viewModel, service: service)

        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .saveFailed)
        #expect(service.fetchAgentReadModelAgentIDCallsCount == 2)
        #expect(viewModel.context.greeting == "Hello there")
        #expect(viewModel.context.viewState.canSave)
    }

    @Test
    func aRoleBriefSavesAlone() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(for: Self.salesAgent, roleBrief: "Sell."))
        let viewModel = try await loadedViewModel(section: .character, card: Self.salesAgent, service: service)
        #expect(viewModel.context.roleBrief == "Sell.")

        viewModel.context.roleBrief = "Sell coffee."
        service.editAgentAgentIDPatchReturnValue = .success(Self.readModel(for: Self.salesAgent, roleBrief: "Sell coffee."))
        try await save(viewModel, service: service)

        #expect(service.editAgentAgentIDPatchReceivedArguments?.patch == AgentEditPatch(roleBrief: "Sell coffee."))
    }

    // MARK: - Choices

    /// A preset tone is a choice: written at once, alone.
    @Test
    func aPresetToneAppliesAtOnce() async throws {
        let service = AgentPlatformServiceMock()
        let viewModel = try await loadedViewModel(section: .character, service: service)
        #expect(viewModel.context.viewState.toneChoice == .custom)

        let friendly = UntranslatedL10n.screenAgentEditToneFriendly
        service.editAgentAgentIDPatchReturnValue = .success(Self.readModel(for: Self.assistant, persona: Self.persona(tone: friendly)))
        let applied = deferFulfillment(viewModel.actionsPublisher) { if case .changed = $0 { true } else { false } }
        viewModel.context.send(viewAction: .selectTone(.friendly))
        try await applied.fulfill()

        #expect(service.editAgentAgentIDPatchReceivedArguments?.patch == AgentEditPatch(persona: .init(tone: friendly)))
        #expect(viewModel.context.viewState.toneChoice == .friendly)
        #expect(!viewModel.context.viewState.canSave)
    }

    @Test
    func aFailedChoiceStepsBack() async throws {
        let service = AgentPlatformServiceMock()
        let viewModel = try await loadedViewModel(section: .people, service: service)
        #expect(viewModel.context.showInSearch)

        service.editAgentAgentIDPatchReturnValue = .failure(.serverError(status: 500))
        let reread = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { _ in service.fetchAgentReadModelAgentIDCallsCount == 2 }
        viewModel.context.send(viewAction: .setShowInSearch(false))
        #expect(!viewModel.context.showInSearch)
        try await reread.fulfill()

        #expect(service.editAgentAgentIDPatchReceivedArguments?.patch == AgentEditPatch(visibility: "private"))
        #expect(viewModel.context.showInSearch)
    }

    @Test
    func theVisitorPolicyAppliesAtOnce() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(for: Self.assistant, visitorPolicy: .askFirst))
        let viewModel = try await loadedViewModel(section: .people, service: service)

        service.editAgentAgentIDPatchReturnValue = .success(Self.readModel(for: Self.assistant, visitorPolicy: .reply))
        let applied = deferFulfillment(viewModel.actionsPublisher) { if case .changed = $0 { true } else { false } }
        viewModel.context.send(viewAction: .setVisitorPolicy(.reply))
        try await applied.fulfill()

        #expect(service.editAgentAgentIDPatchReceivedArguments?.patch == AgentEditPatch(visitorPolicy: .reply))
        #expect(viewModel.context.visitorPolicy == .reply)
    }

    /// A second choice while the first one's PATCH is out is dropped, not
    /// raced: one write, and the shown value is the server's.
    @Test
    func aChoiceWhileOneIsSavingIsDropped() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(for: Self.assistant, visitorPolicy: .askFirst))
        let viewModel = try await loadedViewModel(section: .people, service: service)

        let gate = Mutex<CheckedContinuation<Void, Never>?>(nil)
        let serverModel = Self.readModel(for: Self.assistant, visitorPolicy: .reply)
        service.editAgentAgentIDPatchClosure = { _, _ in
            await withCheckedContinuation { continuation in gate.withLock { $0 = continuation } }
            return .success(serverModel)
        }

        viewModel.context.send(viewAction: .setVisitorPolicy(.reply))
        while gate.withLock({ $0 == nil }) {
            await Task.yield()
        }
        #expect(viewModel.context.viewState.isWriting)

        viewModel.context.send(viewAction: .setShowInSearch(false))
        viewModel.context.send(viewAction: .setVisitorPolicy(.off))
        #expect(viewModel.context.showInSearch)
        #expect(viewModel.context.visitorPolicy == .reply)

        let done = deferFulfillment(viewModel.context.observe(\.viewState.isWriting)) { !$0 }
        gate.withLock { $0?.resume() }
        try await done.fulfill()

        #expect(service.editAgentAgentIDPatchCallsCount == 1)
        #expect(viewModel.context.visitorPolicy == .reply)
        #expect(viewModel.context.showInSearch == (serverModel.visibility == "public"))
    }

    /// A preset tone whose write and re-read both fail shows the tone the
    /// server last confirmed again.
    @Test
    func aFailedPresetToneStepsBackWhenTheRereadFailsToo() async throws {
        let service = AgentPlatformServiceMock()
        let viewModel = try await loadedViewModel(section: .character, service: service)
        #expect(viewModel.context.tone == "warm")

        service.editAgentAgentIDPatchReturnValue = .failure(.serverError(status: 500))
        service.fetchAgentReadModelAgentIDReturnValue = .failure(.serverError(status: 500))
        let done = deferFulfillment(viewModel.context.observe(\.viewState.isWriting)) { isWriting in
            !isWriting && service.fetchAgentReadModelAgentIDCallsCount == 2
        }
        viewModel.context.send(viewAction: .selectTone(.friendly))
        #expect(viewModel.context.viewState.toneChoice == .friendly)
        try await done.fulfill()

        #expect(service.fetchAgentReadModelAgentIDCallsCount == 2)
        #expect(viewModel.context.tone == "warm")
        #expect(viewModel.context.viewState.toneChoice == .custom)
        #expect(!viewModel.context.viewState.canSave)
    }
}
