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

typealias OutreachQueueListScreenViewModelType = StateStoreViewModelV2<OutreachQueueListScreenViewState, OutreachQueueListScreenViewAction>

/// Drives `OutreachQueueListScreen`: one agent's outreach queue, with a
/// status filter in the toolbar (`nil` → every status).
///
/// AGENT-PLATFORM: platform sync (decision 289). The rows are the session
/// store's, one list per filter, read again on `agent.outreach` (the outreach
/// worker moving `queued → pending_approval → sent`, an add from the add
/// screen). A filter change shows the other list; the server filters, as the
/// queue can be long.
class OutreachQueueListScreenViewModel: OutreachQueueListScreenViewModelType, OutreachQueueListScreenViewModelProtocol {
    private let agentID: String
    private let store: AgentsStore

    private let actionsSubject: PassthroughSubject<OutreachQueueListScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<OutreachQueueListScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    private var resource: AgentsResource {
        .outreach(agentID: agentID, status: state.statusFilter)
    }

    init(agentID: String,
         store: AgentsStore,
         initialFilter: OutreachTargetStatus? = nil) {
        self.agentID = agentID
        self.store = store
        var initial = OutreachQueueListScreenViewState(agentID: agentID, bindings: OutreachQueueListScreenViewStateBindings())
        initial.statusFilter = initialFilter
        super.init(initialViewState: initial)

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

    override func process(viewAction: OutreachQueueListScreenViewAction) {
        MXLog.info("OutreachQueueListScreenViewModel received view-model action: \(viewAction)")

        switch viewAction {
        case .retry:
            Task { await store.reread(resource) }
        case .selectFilter(let filter):
            guard filter != state.statusFilter else { return }
            store.stopShowing(resource, by: self)
            state.statusFilter = filter
            store.show(resource, by: self)
            render()
        case .openAddTargets:
            actionsSubject.send(.openAddTargets)
        case .dismiss:
            actionsSubject.send(.dismissed)
        }
    }

    private func render() {
        let listState: OutreachQueueListState = switch store.readState(resource, \.outreach) {
        case .loading: .loading
        case .loaded(let entries): .loaded(entries)
        // 409: not an outreach agent; 404: no such agent. Neither changes with a retry.
        case .failed(.conflict(let detail)): .unavailable(reason: detail)
        case .failed(.notFound): .unavailable(reason: "agent not found")
        case .failed(let error): .failed(reason: error.description)
        }
        if state.listState != listState {
            state.listState = listState
        }
        if state.syncStatus != store.syncStatus {
            state.syncStatus = store.syncStatus
        }
    }
}
