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

@testable import ElementX
import Combine
import Foundation
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
                                                    presence: .online,
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
    
    private static func readModel(for card: AgentSpaceAgentCard, persona: PersonaView? = persona) -> AgentReadModel {
        AgentReadModel(agentID: card.agentID,
                       matrixUserID: card.matrixUserID,
                       displayName: card.displayName,
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
                               clientProxy: ClientProxyMock? = nil) -> AgentEditScreenViewModel {
        AgentEditScreenViewModel(agent: card,
                                 agentPlatformService: service,
                                 userSession: UserSessionMock(.init(clientProxy: clientProxy ?? ClientProxyMock(.init()))),
                                 userIndicatorController: UserIndicatorControllerMock(),
                                 appSettings: .volatile())
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
    
    @Test
    func removeAvatar_patchesEmptyStringClear() async throws {
        let cardWithAvatar = AgentSpaceAgentCard(agentID: "agent-1",
                                                 matrixUserID: "@assistant-owner:spiral.md",
                                                 displayName: "Personal Assistant",
                                                 avatarMXC: "mxc://host/old",
                                                 kind: "personal_assistant",
                                                 visibility: "public",
                                                 lifecycleState: "active",
                                                 presence: .online,
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
}
