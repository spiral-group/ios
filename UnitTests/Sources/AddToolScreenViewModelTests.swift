//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Foundation
@testable import Spiral
import Testing

@MainActor
struct AddToolScreenViewModelTests {
    /// Text kinds and call kinds apart; a kind the catalogue doesn't name isn't offered.
    @Test
    func theKindsAreWhatTheCatalogueNames() async throws {
        let viewModel = makeViewModel(.success(catalog(["translate", "custom", "call_summary"])))
        
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            $0 == .loaded(text: [.translate, .custom], calls: [.callSummary])
        }
        try await deferred.fulfill()
    }
    
    /// Decision 96.
    @Test
    func aKindNewerThanThisBuildIsLeftOut() async throws {
        let viewModel = makeViewModel(.success(catalog(["teleport", "simplify"])))
        
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            $0 == .loaded(text: [.simplify], calls: [])
        }
        try await deferred.fulfill()
    }
    
    /// A failed read is "couldn't check", never "nothing fires here", and Retry reads again.
    @Test
    func aFailedReadSaysSoAndRetryReadsAgain() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .failure(.serverError(status: 500))
        let viewModel = makeViewModel(service: service)
        
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == .failed }
        try await failed.fulfill()
        
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(catalog(["simplify"]))
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 == .loaded(text: [.simplify], calls: []) }
        viewModel.context.send(viewAction: .retry)
        #expect(viewModel.context.viewState.listState == .loading, "Retry shows it has started")
        try await loaded.fulfill()
    }
    
    @Test
    func aKindOpensItsForm() async throws {
        let viewModel = makeViewModel(.success(catalog(["simplify"])))
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .selectKind(.simplify) }
        viewModel.context.send(viewAction: .selectKind(.simplify))
        try await deferred.fulfill()
    }
    
    // MARK: - Helpers
    
    private func catalog(_ kinds: [String]) -> ToolsCatalogView {
        ToolsCatalogView(agentID: "a", roomID: "!r:host", paramsSchema: [:], triggerSchema: [:],
                         textTranslationLanguages: [], voiceTranslationLanguages: [], availableToolKinds: kinds)
    }
    
    private func makeViewModel(_ result: Result<ToolsCatalogView, AgentPlatformError>) -> AddToolScreenViewModel {
        let service = AgentPlatformServiceMock()
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = result
        return makeViewModel(service: service)
    }
    
    private func makeViewModel(service: AgentPlatformServiceMock) -> AddToolScreenViewModel {
        AddToolScreenViewModel(roomID: "!r:host", agentID: "a", agentDisplayName: "Aria", store: AgentsStore(service: service))
    }
}
