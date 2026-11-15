//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: the agent's AI use against its weekly limit (Brief 0079 3c, question 394).
//

import Foundation

struct AgentUsageScreenViewState: BindableState {
    var loadState: AgentUsageScreenLoadState = .loading
    /// The sync's state at the top while the stream is not live (decision 289).
    var syncStatus: PlatformSyncStatus?
}

nonisolated enum AgentUsageScreenLoadState: Equatable {
    case loading
    case loaded(AgentLimitPage)
    case failure
}

enum AgentUsageScreenViewAction {
    case retry
}
