//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: the agent's AI use against its daily limit (Brief 0079 3c).
//

import SwiftUI

typealias AgentUsageScreenViewModelType = StateStoreViewModelV2<AgentUsageScreenViewState, AgentUsageScreenViewAction>

class AgentUsageScreenViewModel: AgentUsageScreenViewModelType, AgentUsageScreenViewModelProtocol {
    private let agentID: String
    private let agentPlatformService: any AgentPlatformServiceProtocol

    init(agentID: String, agentPlatformService: any AgentPlatformServiceProtocol) {
        self.agentID = agentID
        self.agentPlatformService = agentPlatformService
        super.init(initialViewState: AgentUsageScreenViewState())

        Task { await load() }
    }

    override func process(viewAction: AgentUsageScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")

        switch viewAction {
        case .retry:
            state.loadState = .loading
            Task { await load() }
        case .refresh:
            Task { await load() }
        }
    }

    // MARK: - Private

    private func load() async {
        switch await agentPlatformService.fetchAgentUsage(agentID: agentID) {
        case .success(let usage):
            state.loadState = .loaded(usage)
        case .failure(let error):
            MXLog.error("Failed to load the agent's usage: \(error)")
            if case .loaded = state.loadState { return }
            state.loadState = .failure
        }
    }
}
