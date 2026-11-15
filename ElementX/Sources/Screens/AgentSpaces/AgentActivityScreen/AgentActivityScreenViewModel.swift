//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreenViewModel.swift`.

import Combine
import SwiftUI

typealias AgentActivityScreenViewModelType = StateStoreViewModelV2<AgentActivityScreenViewState, AgentActivityScreenViewAction>

/// Drives `AgentActivityScreen`. Owner-visible audit timeline of
/// the agent's `agent_action_log` rows (`GET /api/v1/agents/:id/activity`,
/// Phase R3.5 E1, Brief 0002).
///
/// AGENT-PLATFORM: platform sync (decision 289). The rows are the session
/// store's, one list per filter; `agent.activity` reads the shown one again,
/// as many rows as it holds, so a list scrolled down stays. The bottom
/// sentinel's `.loadMore` appends the next page to the store's list.
class AgentActivityScreenViewModel: AgentActivityScreenViewModelType, AgentActivityScreenViewModelProtocol {
    private let agentID: String
    private let store: AgentsStore
    private let clientProxy: any ClientProxyProtocol

    /// Default page size, the backend's default.
    static let defaultPageSize = 25

    /// The next page on its way, or the last one that could not be read; `nil` follows the list's cursor.
    private var loadMore: LoadMoreState?

    private let actionsSubject: PassthroughSubject<AgentActivityScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentActivityScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    private var resource: AgentsResource {
        .activity(agentID: agentID, filter: state.filter)
    }

    init(agentID: String,
         initialFilter: ActionOutcomeFilter = .all,
         store: AgentsStore,
         clientProxy: any ClientProxyProtocol) {
        self.agentID = agentID
        self.store = store
        self.clientProxy = clientProxy
        super.init(initialViewState: AgentActivityScreenViewState(filter: initialFilter))

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

    // MARK: - Public

    override func process(viewAction: AgentActivityScreenViewAction) {
        MXLog.info("AgentActivityScreenViewModel received view action: \(viewAction)")

        switch viewAction {
        case .retry:
            Task { await store.reread(resource) }
        case .loadMore:
            // The sentinel's `.onAppear` can fire twice when SwiftUI rebuilds the bottom row.
            guard case .loaded(_, let sentinel) = state.listState else { return }
            switch sentinel {
            case .idle, .failed:
                Task { await loadNextPage() }
            case .loading, .exhausted:
                return
            }
        case .selectFilter(let filter):
            guard filter != state.filter else { return }
            store.stopShowing(resource, by: self)
            state.filter = filter
            loadMore = nil
            store.show(resource, by: self)
            render()
        case .selectItem(let id):
            guard let item = state.items.first(where: { $0.id == id }) else { return }
            if let approvalID = item.approvalID {
                actionsSubject.send(.openApproval(approvalID: approvalID))
            } else if let roomID = item.roomID {
                actionsSubject.send(.openRoom(roomID: roomID))
            }
        }
    }

    // MARK: - Private

    private func render() {
        let listState: AgentActivityListState = switch store.readState(resource, \.activity) {
        case .loading: .loading
        case .failed: .failed
        case .loaded(let page): .loaded(page.items.map { Self.mapItem($0, clientProxy: clientProxy) },
                                        loadMore: loadMore ?? Self.makeLoadMoreState(from: page.nextCursor))
        }
        if state.listState != listState {
            state.listState = listState
        }
        if state.syncStatus != store.syncStatus {
            state.syncStatus = store.syncStatus
        }
    }

    /// The previous rows stay on screen; a failure keeps the sentinel's cursor for its retry.
    private func loadNextPage() async {
        guard case .loaded(_, let sentinel) = state.listState else { return }
        let filter = state.filter
        loadMore = .loading
        render()
        let isRead = await store.loadMore(.activity(agentID: agentID, filter: filter))
        // A filter change meanwhile started its own list.
        guard filter == state.filter else { return }
        if isRead {
            loadMore = nil
        } else if case .idle(let cursor) = sentinel {
            loadMore = .failed(cursor: cursor)
        } else {
            loadMore = sentinel
        }
        render()
    }

    /// Wire the per-row preview shape. Defined as a static so
    /// preview providers + tests can synthesise items without
    /// instantiating a full ViewModel.
    static func mapItem(_ entry: AgentActivityEntry, clientProxy: any ClientProxyProtocol) -> AgentActivityListItem {
        AgentActivityListItem(id: entry.id,
                              capabilityName: entry.capabilityName,
                              policyDecision: entry.policyDecision,
                              outcome: entry.outcome,
                              title: AgentActivityLabels.action(forCapability: entry.capabilityName),
                              reason: AgentActivityLabels.reason(forPolicyReason: entry.policyReason, capabilityName: entry.capabilityName),
                              roomName: AgentRoomLabel.text(for: entry.roomID, clientProxy: clientProxy),
                              createdAt: entry.createdAt,
                              // Only a chat this device has opens; a visitor's chat
                              // with the agent, which the owner isn't in, doesn't.
                              roomID: entry.roomID.flatMap { clientProxy.roomSummaryForIdentifier($0) != nil ? $0 : nil },
                              approvalID: entry.approvalID,
                              agentID: entry.agentID)
    }

    /// Translate the wire `nextCursor` into a sentinel state.
    /// `nil` → `.exhausted` (no more rows); otherwise `.idle`
    /// carrying the cursor for the next `.loadMore` action.
    private static func makeLoadMoreState(from nextCursor: String?) -> LoadMoreState {
        if let cursor = nextCursor { return .idle(cursor: cursor) }
        return .exhausted
    }
}
