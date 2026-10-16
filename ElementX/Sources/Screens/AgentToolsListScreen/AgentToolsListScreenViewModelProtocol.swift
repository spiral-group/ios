//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
//

import Combine

@MainActor
protocol AgentToolsListScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<AgentToolsListScreenViewModelAction, Never> { get }
    var context: AgentToolsListScreenViewModelType.Context { get }
}
