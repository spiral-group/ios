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
    
    /// Read the spaces now, after the person's own change elsewhere in the flow.
    func reload()
}
