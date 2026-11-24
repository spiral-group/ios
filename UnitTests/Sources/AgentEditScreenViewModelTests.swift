//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Brief 0037 — the agent's «Изменить» (artboard 0037-G /
// ADR-0049): the avatar and the name only since decision 194.
//

import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct AgentEditScreenViewModelTests {
    private static let paCard = AgentSpaceAgentCard(agentID: "agent-1",
                                                    matrixUserID: "@assistant-owner:spiral.md",
                                                    displayName: "Personal Assistant",
                                                    avatarMXC: nil,
                                                    kind: "personal_assistant",
                                                    visibility: "public",
                                                    lifecycleState: "active",
                                                    roomCount: 1,
                                                    activeToolCount: 0)
    
    private static let paSchema = AgentEditSchema(agentID: "agent-1",
                                                  kind: "personal_assistant",
                                                  displayName: .init(minLength: 1, maxLength: 64),
                                                  persona: .init(ownerDisplayName: .init(minLength: 0, maxLength: 64),
                                                                 tone: .init(minLength: 0, maxLength: 120),
                                                                 greeting: .init(minLength: 0, maxLength: 500),
                                                                 visitorGreeting: .init(minLength: 0, maxLength: 500)))
    
    private static let persona = PersonaView(agentID: "agent-1",
                                             ownerDisplayName: "Boss",
                                             tone: "warm",
                                             greeting: "Hi!",
                                             visitorGreeting: "Hello.",
                                             toolUseEnabled: nil,
                                             model: nil,
                                             configVersionID: "cfg-1",
                                             versionNumber: 1)
    
    private static func readModel(for card: AgentSpaceAgentCard, displayName: String? = nil, persona: PersonaView? = persona) -> AgentReadModel {
        AgentReadModel(agentID: card.agentID,
                       matrixUserID: card.matrixUserID,
                       displayName: displayName ?? card.displayName,
                       avatarMXC: card.avatarMXC,
                       kind: card.kind,
                       visibility: card.visibility,
                       lifecycleState: card.lifecycleState,
                       organizationID: "org-1",
                       roomCount: card.roomCount,
                       activeToolCount: card.activeToolCount,
                       configVersionNumber: 1,
                       persona: card.kind == "personal_assistant" ? persona : nil)
    }

    private func makeViewModel(service: AgentPlatformServiceMock,
                               card: AgentSpaceAgentCard = paCard,
                               store: AgentsStore? = nil,
                               clientProxy: ClientProxyMock? = nil) -> AgentEditScreenViewModel {
        service.fetchAgentRoomsAgentIDReturnValue = .success([])
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        return AgentEditScreenViewModel(agent: card,
                                        agentPlatformService: service,
                                        store: store ?? AgentsStore(service: service, retryDelays: []),
                                        userSession: UserSessionMock(.init(clientProxy: clientProxy ?? ClientProxyMock(.init()))),
                                        userIndicatorController: UserIndicatorControllerMock())
    }
    
    /// A store that read the agent and its limits: what opening from the agent's screen finds.
    private func storeHoldingTheAgent(displayName: String, service: AgentPlatformServiceMock) async -> AgentsStore {
        service.fetchAgentEditSchemaAgentIDReturnValue = .success(Self.paSchema)
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(for: Self.paCard, displayName: displayName))
        service.fetchAgentRoomsAgentIDReturnValue = .success([])
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        let store = AgentsStore(service: service, retryDelays: [])
        await store.reread(.agent(agentID: Self.paCard.agentID))
        await store.reread(.editSchema(agentID: Self.paCard.agentID))
        return store
    }
    
    private static func imageMediaInfo() -> MediaInfo {
        .image(imageURL: .picturesDirectory,
               thumbnailURL: .picturesDirectory,
               imageInfo: .init(height: 1, width: 1, mimetype: "image/png", size: nil, thumbnailInfo: nil, thumbnailSource: nil, blurhash: nil, isAnimated: nil))
    }
    
    @Test
    func load_seedsCurrentValuesAndCannotSaveUnchanged() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentEditSchemaAgentIDReturnValue = .success(Self.paSchema)
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(for: Self.paCard))
        
        let viewModel = makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(Self.paSchema) }
        try await deferred.fulfill()
        
        #expect(viewModel.context.displayName == "Personal Assistant")
        // RoomDetailsEdit canon: nothing changed yet → Save disabled.
        #expect(viewModel.context.viewState.canSave == false)
        viewModel.context.displayName = "Renamed"
        #expect(viewModel.context.viewState.canSave == true)
    }
    
    /// Brief 0083, question 359: the first frame is the final form. The card can be stale after a save (0038 I1 fix),
    /// so what the store holds comes first.
    @Test
    func theFormOpensFilledFromTheStore() async {
        let service = AgentPlatformServiceMock()
        let store = await storeHoldingTheAgent(displayName: "Renamed before", service: service)
        
        let viewModel = makeViewModel(service: service, store: store)
        
        #expect(viewModel.context.displayName == "Renamed before")
        #expect(viewModel.context.viewState.initialDisplayName == "Renamed before")
        #expect(viewModel.context.viewState.schema != nil)
    }
    
    /// Brief 0083, question 359: the card fills the form, and nothing replaces it. The name can't be checked without
    /// its limits, so it can't be saved.
    @Test
    func theCardFillsTheFormWhileTheLimitsAreOnTheirWay() async throws {
        let service = AgentPlatformServiceMock()
        let limits = HeldRead<AgentEditSchema>(answer: .success(Self.paSchema))
        service.fetchAgentEditSchemaAgentIDClosure = { _ in await limits.answer() }
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(for: Self.paCard))
        
        let viewModel = makeViewModel(service: service)
        #expect(viewModel.context.displayName == "Personal Assistant")
        #expect(viewModel.context.viewState.loadState == .loading)
        
        viewModel.context.displayName = "Typed anyway"
        #expect(viewModel.context.viewState.canSave == false)
        viewModel.context.displayName = "Personal Assistant"
        
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(Self.paSchema) }
        limits.release()
        try await loaded.fulfill()
    }
    
    /// Brief 0083, question 359: a failure keeps the form, says so and retries; it is never a schema to check against.
    @Test
    func aFailedLimitsReadKeepsTheFormAndCanBeRetried() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentEditSchemaAgentIDReturnValue = .failure(.serverError(status: 500))
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(for: Self.paCard))
        
        let viewModel = makeViewModel(service: service)
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .failure }
        try await failed.fulfill()
        #expect(viewModel.context.displayName == "Personal Assistant")
        viewModel.context.displayName = "Renamed"
        #expect(viewModel.context.viewState.canSave == false)
        
        service.fetchAgentEditSchemaAgentIDReturnValue = .success(Self.paSchema)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(Self.paSchema) }
        viewModel.context.send(viewAction: .retry)
        try await loaded.fulfill()
        #expect(viewModel.context.viewState.canSave == true)
    }
    
    /// Brief 0083, question 359: a later read moves the baseline and leaves an edit alone.
    @Test
    func aLaterReadNeverOverwritesAnEdit() async throws {
        let service = AgentPlatformServiceMock()
        let store = await storeHoldingTheAgent(displayName: "Personal Assistant", service: service)
        let viewModel = makeViewModel(service: service, store: store)
        viewModel.context.displayName = "My edit"
        
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(for: Self.paCard, displayName: "From the server"))
        let adopted = deferFulfillment(viewModel.context.observe(\.viewState.initialDisplayName)) { $0 == "From the server" }
        await store.reread(.agent(agentID: Self.paCard.agentID))
        try await adopted.fulfill()
        
        #expect(viewModel.context.displayName == "My edit")
    }
    
    /// An untouched name follows what is read.
    @Test
    func aLaterReadFillsAnUntouchedName() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentEditSchemaAgentIDReturnValue = .success(Self.paSchema)
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(for: Self.paCard, displayName: "From the server"))
        
        let viewModel = makeViewModel(service: service)
        #expect(viewModel.context.displayName == "Personal Assistant")
        
        let adopted = deferFulfillment(viewModel.context.observe(\.viewState.initialDisplayName)) { $0 == "From the server" }
        try await adopted.fulfill()
        #expect(viewModel.context.displayName == "From the server")
    }
    
    @Test
    func displayNameOutOfBounds_blocksSave() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentEditSchemaAgentIDReturnValue = .success(Self.paSchema)
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(for: Self.paCard))
        
        let viewModel = makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(Self.paSchema) }
        try await deferred.fulfill()
        
        viewModel.context.displayName = "   "
        #expect(viewModel.context.viewState.canSave == false)
    }
    
    @Test
    func save_patchesOnlyChangedSurfaces() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentEditSchemaAgentIDReturnValue = .success(Self.paSchema)
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(for: Self.paCard))
        service.editAgentAgentIDPatchReturnValue = .success(Self.readModel(for: Self.paCard))
        
        let viewModel = makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(Self.paSchema) }
        try await loaded.fulfill()
        
        // Change only the display name.
        viewModel.context.displayName = "Sales Pro"
        
        let saved = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .saved = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .save)
        try await saved.fulfill()
        
        #expect(service.editAgentAgentIDPatchCallsCount == 1)
        #expect(service.editAgentAgentIDPatchReceivedArguments?.patch == AgentEditPatch(displayName: "Sales Pro"))
    }
    
    @Test
    func save_uploadsAvatarDeferredAndPatchesMXC() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentEditSchemaAgentIDReturnValue = .success(Self.paSchema)
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(for: Self.paCard))
        service.editAgentAgentIDPatchReturnValue = .success(Self.readModel(for: Self.paCard))
        let clientProxy = ClientProxyMock(.init())
        clientProxy.uploadMediaReturnValue = .success("mxc://host/new-avatar")
        
        let viewModel = makeViewModel(service: service, clientProxy: clientProxy)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(Self.paSchema) }
        try await loaded.fulfill()
        
        viewModel.state.localMedia = Self.imageMediaInfo()
        #expect(viewModel.context.viewState.canSave == true)
        
        let saved = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .saved = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .save)
        try await saved.fulfill()
        
        #expect(clientProxy.uploadMediaCallsCount == 1)
        // Name unchanged → not in the patch.
        #expect(service.editAgentAgentIDPatchReceivedArguments?.patch == AgentEditPatch(avatarMXC: "mxc://host/new-avatar"))
    }
    
    /// S5: the Agents tab's card holds the saved avatar before the form goes, without a read of its own.
    @Test
    func aSavedAvatarIsOnTheAgentsCardBeforeTheFormGoes() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [.init(orgID: "org-1", name: "Personal", kind: .solo, avatarMXC: nil, agentCount: 1)],
                                                              provisioningStatus: .ready))
        service.fetchAgentSpaceOrgIDReturnValue = .success(AgentSpaceDetail(orgID: "org-1", name: "Personal", kind: .solo, avatarMXC: nil,
                                                                            industry: nil, website: nil, agents: [Self.paCard]))
        let store = await storeHoldingTheAgent(displayName: Self.paCard.displayName, service: service)
        await store.reread(.spaces)
        let answer = AgentReadModel(agentID: Self.paCard.agentID, matrixUserID: Self.paCard.matrixUserID, displayName: Self.paCard.displayName,
                                    avatarMXC: "mxc://host/new-avatar", kind: Self.paCard.kind, visibility: Self.paCard.visibility,
                                    lifecycleState: Self.paCard.lifecycleState, organizationID: "org-1", roomCount: 1, activeToolCount: 0,
                                    configVersionNumber: 2, persona: Self.persona)
        service.editAgentAgentIDPatchReturnValue = .success(answer)
        let clientProxy = ClientProxyMock(.init())
        clientProxy.uploadMediaReturnValue = .success("mxc://host/new-avatar")
        let viewModel = makeViewModel(service: service, store: store, clientProxy: clientProxy)
        viewModel.state.localMedia = Self.imageMediaInfo()

        var cardAvatarOnSaved: String?
        let saved = deferFulfillment(viewModel.actionsPublisher) { action in
            guard case .saved = action else { return false }
            cardAvatarOnSaved = store.card(agentID: Self.paCard.agentID)?.avatarMXC
            return true
        }
        viewModel.context.send(viewAction: .save)
        try await saved.fulfill()

        #expect(cardAvatarOnSaved == "mxc://host/new-avatar")
        #expect(service.listMyAgentSpacesCallsCount == 1, "the card shows the answer, not a read")
    }

    @Test
    func removeAvatar_patchesEmptyStringClear() async throws {
        let cardWithAvatar = AgentSpaceAgentCard(agentID: "agent-1",
                                                 matrixUserID: "@assistant-owner:spiral.md",
                                                 displayName: "Personal Assistant",
                                                 avatarMXC: "mxc://host/old",
                                                 kind: "personal_assistant",
                                                 visibility: "public",
                                                 lifecycleState: "active",
                                                 roomCount: 1,
                                                 activeToolCount: 0)
        let service = AgentPlatformServiceMock()
        service.fetchAgentEditSchemaAgentIDReturnValue = .success(Self.paSchema)
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(for: cardWithAvatar))
        service.editAgentAgentIDPatchReturnValue = .success(Self.readModel(for: Self.paCard))
        let clientProxy = ClientProxyMock(.init())
        
        let viewModel = makeViewModel(service: service, card: cardWithAvatar, clientProxy: clientProxy)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(Self.paSchema) }
        try await loaded.fulfill()
        
        viewModel.context.send(viewAction: .removeImage)
        #expect(viewModel.context.viewState.canSave == true, "removing an existing avatar is a change")
        
        let saved = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .saved = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .save)
        try await saved.fulfill()
        
        #expect(clientProxy.uploadMediaCallsCount == 0)
        #expect(service.editAgentAgentIDPatchReceivedArguments?.patch == AgentEditPatch(avatarMXC: ""))
    }
    
    @Test
    func cancelWithUnsavedChanges_gatesWithAlert() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentEditSchemaAgentIDReturnValue = .success(Self.paSchema)
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(for: Self.paCard))
        
        let viewModel = makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(Self.paSchema) }
        try await loaded.fulfill()
        
        viewModel.context.displayName = "Renamed"
        let alerted = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .unsavedChanges }
        viewModel.context.send(viewAction: .cancel)
        try await alerted.fulfill()
    }
    
    @Test
    func cancelWithoutChanges_dismissesImmediately() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentEditSchemaAgentIDReturnValue = .success(Self.paSchema)
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(for: Self.paCard))
        
        let viewModel = makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(Self.paSchema) }
        try await loaded.fulfill()
        
        let cancelled = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .cancel = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .cancel)
        try await cancelled.fulfill()
        #expect(viewModel.context.viewState.bindings.alertInfo == nil)
    }
    
    @Test
    func save_failure_showsAlert() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentEditSchemaAgentIDReturnValue = .success(Self.paSchema)
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(for: Self.paCard))
        service.editAgentAgentIDPatchReturnValue = .failure(.validation(detail: "too long"))
        
        let viewModel = makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(Self.paSchema) }
        try await loaded.fulfill()
        
        viewModel.context.displayName = "New Name"
        
        let alerted = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .saveFailed }
        viewModel.context.send(viewAction: .save)
        try await alerted.fulfill()
    }
    
    @Test
    func load_readsTheAgentOnce() async throws {
        let service = AgentPlatformServiceMock()
        _ = try await loadedViewModel(service: service)
        #expect(service.fetchAgentReadModelAgentIDCallsCount == 1)
    }
    
    // MARK: - B2: a save that half-lands is re-read
    
    private func loadedViewModel(service: AgentPlatformServiceMock, clientProxy: ClientProxyMock? = nil) async throws -> AgentEditScreenViewModel {
        service.fetchAgentEditSchemaAgentIDReturnValue = .success(Self.paSchema)
        if service.fetchAgentReadModelAgentIDReturnValue == nil {
            service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(for: Self.paCard))
        }
        let viewModel = makeViewModel(service: service, clientProxy: clientProxy)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(Self.paSchema) }
        try await loaded.fulfill()
        return viewModel
    }
    
    private func save(_ viewModel: AgentEditScreenViewModel, expecting alert: Bool) async throws {
        if alert {
            let alerted = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .saveFailed }
            viewModel.context.send(viewAction: .save)
            try await alerted.fulfill()
            // The re-read after the failure.
            let reread = deferFulfillment(viewModel.context.observe(\.viewState.isSaving)) { $0 == false }
            try await reread.fulfill()
        } else {
            let saved = deferFulfillment(viewModel.actionsPublisher) { action in
                if case .saved = action { return true }
                return false
            }
            viewModel.context.send(viewAction: .save)
            try await saved.fulfill()
        }
    }
    
    @Test
    func aRetriedSave_doesNotUploadTheAvatarAgain() async throws {
        let service = AgentPlatformServiceMock()
        let clientProxy = ClientProxyMock(.init())
        clientProxy.uploadMediaReturnValue = .success("mxc://host/new-avatar")
        let viewModel = try await loadedViewModel(service: service, clientProxy: clientProxy)
        viewModel.state.localMedia = Self.imageMediaInfo()
        
        service.editAgentAgentIDPatchReturnValue = .failure(.serverError(status: 500))
        try await save(viewModel, expecting: true)
        service.editAgentAgentIDPatchReturnValue = .success(Self.readModel(for: Self.paCard))
        try await save(viewModel, expecting: false)
        
        #expect(clientProxy.uploadMediaCallsCount == 1)
        #expect(service.editAgentAgentIDPatchReceivedArguments?.patch == AgentEditPatch(avatarMXC: "mxc://host/new-avatar"))
    }
    
    @Test
    func aFailedSaveMovesTheBaselineToWhatTheServerHolds() async throws {
        let service = AgentPlatformServiceMock()
        let viewModel = try await loadedViewModel(service: service)
        viewModel.context.displayName = "Renamed"
        
        let landed = AgentReadModel(agentID: "agent-1", matrixUserID: Self.paCard.matrixUserID, displayName: "Renamed",
                                    avatarMXC: nil, kind: Self.paCard.kind, visibility: "public", lifecycleState: "active",
                                    organizationID: "org-1", roomCount: 1, activeToolCount: 0, configVersionNumber: 2,
                                    persona: Self.persona)
        service.editAgentAgentIDPatchReturnValue = .failure(.serverError(status: 500))
        service.fetchAgentReadModelAgentIDReturnValue = .success(landed)
        try await save(viewModel, expecting: true)
        
        #expect(viewModel.context.viewState.initialDisplayName == "Renamed")
        #expect(viewModel.context.viewState.canSave == false)
    }
    
    // MARK: - 1.0.3: a refused name
    
    nonisolated static let nameRefusals: [AgentPlatformError] = [.displayNameReserved, .displayNameInvalidCharacters, .displayNameUnchecked]
    
    /// Spelled out rather than read from `agentNameRefusal`, so the test pins which line each refusal shows.
    static func expectedMessage(for error: AgentPlatformError) -> String? {
        switch error {
        case .displayNameReserved: UntranslatedL10n.errorAgentNameReserved
        case .displayNameInvalidCharacters: UntranslatedL10n.errorAgentNameInvalidCharacters
        case .displayNameUnchecked: UntranslatedL10n.errorAgentNameUnchecked
        default: nil
        }
    }
    
    @Test(arguments: nameRefusals)
    func aRefusedNameSaysWhyAndKeepsWhatWasTyped(_ error: AgentPlatformError) async throws {
        let service = AgentPlatformServiceMock()
        let viewModel = try await loadedViewModel(service: service)
        viewModel.context.displayName = "Spiral Support"
        
        service.editAgentAgentIDPatchReturnValue = .failure(error)
        try await save(viewModel, expecting: true)
        
        #expect(viewModel.context.viewState.bindings.alertInfo?.message == Self.expectedMessage(for: error))
        #expect(viewModel.context.displayName == "Spiral Support")
        #expect(viewModel.context.viewState.initialDisplayName == Self.paCard.displayName)
        #expect(viewModel.context.viewState.canSave)
    }
    
    @Test
    func anotherFailureNamesNoNameRule() async throws {
        let service = AgentPlatformServiceMock()
        let viewModel = try await loadedViewModel(service: service)
        viewModel.context.displayName = "Renamed"
        
        service.editAgentAgentIDPatchReturnValue = .failure(.serverError(status: 500))
        try await save(viewModel, expecting: true)
        
        #expect(viewModel.context.viewState.bindings.alertInfo?.message == nil)
        #expect(viewModel.context.displayName == "Renamed")
    }
}
