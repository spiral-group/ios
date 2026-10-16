//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: the agent's AI use against its daily limit (Brief 0079 3c).
//

import Foundation

struct AgentUsageScreenViewState: BindableState {
    var loadState: AgentUsageScreenLoadState = .loading
}

nonisolated enum AgentUsageScreenLoadState: Equatable {
    case loading
    case loaded(AgentUsage)
    case failure
}

enum AgentUsageScreenViewAction {
    case retry
    /// Pull to refresh: the shown usage stays until the new one arrives.
    case refresh
}
