//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import SwiftUI

typealias AgentBlockedScreenViewModelType = StateStoreViewModelV2<AgentBlockedScreenViewState, AgentBlockedScreenViewAction>

protocol AgentBlockedScreenViewModelProtocol {
    var context: AgentBlockedScreenViewModelType.Context { get }
}

class AgentBlockedScreenViewModel: AgentBlockedScreenViewModelType, AgentBlockedScreenViewModelProtocol {
    /// The platform's own page size, so the agent screen's count reads the same page.
    static let pageSize = 50

    private let agentPlatformService: AgentPlatformServiceProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    /// Guards a page against a retry that started after it.
    private var loadGeneration: UInt64 = 0

    init(agent: AgentSpaceAgentCard,
         agentPlatformService: AgentPlatformServiceProtocol,
         userIndicatorController: UserIndicatorControllerProtocol) {
        self.agentPlatformService = agentPlatformService
        self.userIndicatorController = userIndicatorController
        super.init(initialViewState: AgentBlockedScreenViewState(agent: agent))

        Task { await loadFirstPage() }
    }

    override func process(viewAction: AgentBlockedScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")

        switch viewAction {
        case .retry:
            Task { await loadFirstPage() }
        case .loadMore:
            guard case .loaded(let blocks, let loadMore) = state.listState else { return }
            switch loadMore {
            case .idle(let cursor), .failed(let cursor):
                Task { await loadNextPage(after: blocks, cursor: cursor) }
            case .loading, .exhausted:
                return
            }
        case .unblock(let contactMXID):
            guard state.unblockingMXID == nil, let block = state.blocks.first(where: { $0.contactMXID == contactMXID }) else { return }
            confirmUnblock(block)
        }
    }

    // MARK: - Private

    private func loadFirstPage() async {
        loadGeneration += 1
        let generation = loadGeneration
        state.listState = .loading

        let result = await agentPlatformService.listBlockedContacts(agentID: state.agent.agentID, cursor: nil, limit: Self.pageSize)
        guard generation == loadGeneration else { return }

        switch result {
        case .success(let page):
            state.listState = .loaded(page.blocks, loadMore: Self.loadMore(after: page))
        case .failure(let error):
            MXLog.error("Failed to read the blocks of agent \(state.agent.agentID): \(error)")
            state.listState = .failed
        }
    }

    private func loadNextPage(after blocks: [AgentBlockedContact], cursor: String) async {
        let generation = loadGeneration
        state.listState = .loaded(blocks, loadMore: .loading)

        let result = await agentPlatformService.listBlockedContacts(agentID: state.agent.agentID, cursor: cursor, limit: Self.pageSize)
        guard generation == loadGeneration, case .loaded(let current, _) = state.listState else { return }

        switch result {
        case .success(let page):
            // An unblock while the page was out may have removed a row; a
            // person already shown is never shown twice.
            let shown = Set(current.map(\.contactMXID))
            state.listState = .loaded(current + page.blocks.filter { !shown.contains($0.contactMXID) }, loadMore: Self.loadMore(after: page))
        case .failure(let error):
            MXLog.error("Failed to read more blocks of agent \(state.agent.agentID): \(error)")
            state.listState = .loaded(current, loadMore: .failed(cursor: cursor))
        }
    }

    private static func loadMore(after page: AgentBlockedContactsPage) -> LoadMoreState {
        page.nextCursor.map { .idle(cursor: $0) } ?? .exhausted
    }

    private func confirmUnblock(_ block: AgentBlockedContact) {
        let agentName = state.agent.displayName
        state.bindings.alertInfo = AlertInfo(id: .confirmUnblock,
                                             title: UntranslatedL10n.screenRoomMemberDetailsAgentUnblockAlertTitle(block.name, agentName),
                                             message: UntranslatedL10n.screenRoomMemberDetailsAgentUnblockAlertMessage(agentName),
                                             primaryButton: .init(title: UntranslatedL10n.screenRoomMemberDetailsAgentUnblockAction) { [weak self] in
                                                 Task { await self?.unblock(block) }
                                             },
                                             secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
    }

    /// The row goes once the platform says so; a failure keeps it and says so.
    private func unblock(_ block: AgentBlockedContact) async {
        state.unblockingMXID = block.contactMXID
        defer { state.unblockingMXID = nil }

        switch await agentPlatformService.unblockContact(block.contactMXID, forAgent: state.agent.agentID) {
        case .success:
            MXLog.info("Unblocked a contact for agent \(state.agent.agentID)")
            if case .loaded(let blocks, let loadMore) = state.listState {
                state.listState = .loaded(blocks.filter { $0.contactMXID != block.contactMXID }, loadMore: loadMore)
            }
            userIndicatorController.submitIndicator(UserIndicator(title: UntranslatedL10n.screenRoomMemberDetailsAgentUnblockDone(state.agent.displayName),
                                                                  icon: \.checkCircle))
        case .failure(let error):
            MXLog.error("Unblocking a contact for agent \(state.agent.agentID) failed: \(error)")
            userIndicatorController.submitIndicator(UserIndicator(type: .toast,
                                                                  title: UntranslatedL10n.screenRoomMemberDetailsAgentUnblockFailed,
                                                                  icon: \.error))
        }
    }
}
