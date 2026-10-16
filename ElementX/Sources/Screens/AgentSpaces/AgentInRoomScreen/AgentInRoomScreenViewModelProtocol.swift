//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine

@MainActor
protocol AgentInRoomScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<AgentInRoomScreenViewModelAction, Never> { get }
    var context: AgentInRoomScreenViewModelType.Context { get }
    
    /// Re-fetch this room's tools (after the arm flow pops).
    func reloadRoom() async
}
