//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SwiftUI

/// The chats an agent is in. A row opens the agent in that chat, as on the agent's screen.
struct AgentChatsScreen: View {
    @Bindable var context: AgentChatsScreenViewModel.Context
    
    var body: some View {
        Form {
            switch context.viewState.loadState {
            case .loading:
                AgentChatsLoadingSection(count: context.viewState.expectedRoomCount, showsHeader: false)
            case .failure:
                AgentSpacesRetryErrorSection(title: UntranslatedL10n.screenAgentDetailErrorTitle) {
                    context.send(viewAction: .retry)
                }
            case .loaded(let rooms):
                AgentChatsSection(rooms: rooms, showsHeader: false, emptyTitle: UntranslatedL10n.screenAgentChatsEmpty) { room in
                    context.viewState.title(for: room)
                } onSelect: { room in
                    context.send(viewAction: .selectRoom(room))
                }
            }
        }
        .spiralGroupedList() // Decision 337
        .feedSyncStatus(context.viewState.syncStatus) // Decision 289
        .navigationTitle(UntranslatedL10n.screenAgentDetailChatsSection)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
    }
}

// MARK: - Previews

struct AgentChatsScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = makeViewModel(rooms: [.init(roomID: "!dm:spiral.md", displayName: "Anna Sampleton", kind: "dm", activeTools: []),
                                                 .init(roomID: "!team:spiral.md", displayName: "Coffee team", kind: "group", activeTools: [])])
    static let emptyViewModel = makeViewModel(rooms: [])
    static let loadingViewModel = makeViewModel(rooms: [], isLoading: true)
    
    static var previews: some View {
        ElementNavigationStack { AgentChatsScreen(context: viewModel.context) }
            .snapshotPreferences(expect: hasLoaded(viewModel))
        
        ElementNavigationStack { AgentChatsScreen(context: emptyViewModel.context) }
            .snapshotPreferences(expect: hasLoaded(emptyViewModel))
            .previewDisplayName("Empty")
        
        ElementNavigationStack { AgentChatsScreen(context: loadingViewModel.context) }
            .environment(\.spiralPreloaderDelay, .zero)
            .previewDisplayName("Loading")
    }
    
    private static func hasLoaded(_ viewModel: AgentChatsScreenViewModel) -> some AsyncSequence<Bool, Never> {
        viewModel.context.observe(\.viewState.loadState).map { $0 != .loading }
    }
    
    private static func makeViewModel(rooms: [AgentRoomEntry], isLoading: Bool = false) -> AgentChatsScreenViewModel {
        let card = AgentProfileMock.assistant
        let service = AgentPlatformServiceMock()
        if isLoading {
            // The snapshot suites share this view model in one run, which can outlast a minute.
            service.fetchAgentRoomsAgentIDClosure = { _ in
                try? await Task.sleep(for: .seconds(24 * 3600))
                return .failure(.serverError(status: 0))
            }
        }
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        service.fetchAgentReadModelAgentIDReturnValue = .success(.init(agentID: card.agentID, matrixUserID: card.matrixUserID, displayName: card.displayName,
                                                                       avatarMXC: nil, kind: card.kind, visibility: card.visibility,
                                                                       lifecycleState: card.lifecycleState, organizationID: "org-1",
                                                                       roomCount: rooms.count, activeToolCount: 0, configVersionNumber: 1, persona: nil))
        service.fetchAgentRoomsAgentIDReturnValue = .success(rooms)
        
        let clientProxy = ClientProxyMock(.init())
        clientProxy.directRoomForUserIDReturnValue = .success(nil)
        return AgentChatsScreenViewModel(agent: card, clientProxy: clientProxy, store: AgentsStore(service: service))
    }
}
