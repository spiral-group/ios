//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: the agent's AI use against its weekly limit (Brief 0079 3c, question 394).
//

import SwiftUI

typealias AgentUsageScreenViewModelType = StateStoreViewModelV2<AgentUsageScreenViewState, AgentUsageScreenViewAction>

class AgentUsageScreenViewModel: AgentUsageScreenViewModelType, AgentUsageScreenViewModelProtocol {
    private let agentID: String
    // AGENT-PLATFORM: platform sync (decision 289): `agent.usage` reads it again while shown.
    private let store: AgentsStore

    private var resource: AgentsResource {
        .usage(agentID: agentID)
    }

    init(agentID: String, store: AgentsStore) {
        self.agentID = agentID
        self.store = store
        super.init(initialViewState: AgentUsageScreenViewState())

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

    override func process(viewAction: AgentUsageScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")

        switch viewAction {
        case .retry:
            Task { await store.reread(resource) }
        }
    }

    // MARK: - Private

    private func render() {
        let loadState: AgentUsageScreenLoadState = switch store.readState(resource, \.usage) {
        case .loading: .loading
        case .loaded(let usage): .loaded(AgentLimitPage(usage: usage))
        case .failed: .failure
        }
        if state.loadState != loadState {
            state.loadState = loadState
        }
        if state.syncStatus != store.syncStatus {
            state.syncStatus = store.syncStatus
        }
    }
}
