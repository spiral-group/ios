//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature. This file is Element's screen template
// (Tools/Scripts/Templates/SimpleScreenExample) with the names changed, so it keeps Element's header.

import Combine

@MainActor
protocol AgentActivityScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<AgentActivityScreenViewModelAction, Never> { get }
    var context: AgentActivityScreenViewModelType.Context { get }
}
