//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine

@MainActor
protocol AgentSpacesScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<AgentSpacesScreenViewModelAction, Never> { get }
    var context: AgentSpacesScreenViewModelType.Context { get }
    
    /// Re-fetch the directory (tab re-entry, pull-to-refresh, or after
    /// a mutation elsewhere in the flow changed a space).
    func reload() async
}
