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
    // AGENT-PLATFORM: platform sync (decision 289): `agent.blocks` reads the list again while shown.
    private let store: AgentsStore
    private let userIndicatorController: UserIndicatorControllerProtocol
    /// The next page on its way, or the last one that could not be read.
    private var loadMore: LoadMoreState?

    private var resource: AgentsResource {
        .blocks(agentID: state.agent.agentID)
    }

    init(agent: AgentSpaceAgentCard,
         agentPlatformService: AgentPlatformServiceProtocol,
         store: AgentsStore,
         userIndicatorController: UserIndicatorControllerProtocol) {
        self.agentPlatformService = agentPlatformService
        self.store = store
        self.userIndicatorController = userIndicatorController
        super.init(initialViewState: AgentBlockedScreenViewState(agent: agent))

        render()
        store.observe { [weak self] in
            guard let self else { return false }
            render()
            return true
        }
        store.show(resource, by: self)
    }

    isolated deinit {
        store.stopShowing(resource, by: self)
    }

    override func process(viewAction: AgentBlockedScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")

        switch viewAction {
        case .retry:
            Task { await store.reread(resource) }
        case .loadMore:
            guard case .loaded(_, let sentinel) = state.listState else { return }
            switch sentinel {
            case .idle, .failed:
                Task { await loadNextPage() }
            case .loading, .exhausted:
                return
            }
        case .unblock(let contactMXID):
            guard state.unblockingMXID == nil, let block = state.blocks.first(where: { $0.contactMXID == contactMXID }) else { return }
            confirmUnblock(block)
        }
    }

    // MARK: - Private

    private func render() {
        let listState: AgentBlockedListState = switch store.readState(resource, \.blocks) {
        case .loading: .loading
        case .failed: .failed
        case .loaded(let page): .loaded(page.blocks, loadMore: loadMore ?? Self.loadMore(after: page))
        }
        if state.listState != listState {
            state.listState = listState
        }
        if state.syncStatus != store.syncStatus {
            state.syncStatus = store.syncStatus
        }
    }

    private func loadNextPage() async {
        guard case .loaded(_, let sentinel) = state.listState else { return }
        loadMore = .loading
        render()
        let isRead = await store.loadMore(resource)
        if isRead {
            loadMore = nil
        } else if case .idle(let cursor) = sentinel {
            loadMore = .failed(cursor: cursor)
        } else {
            loadMore = sentinel
        }
        render()
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
            store.removeBlock(of: block.contactMXID, agentID: state.agent.agentID)
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
