//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine

@MainActor
protocol AgentDetailScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<AgentDetailScreenViewModelAction, Never> { get }
    var context: AgentDetailScreenViewModelType.Context { get }
    
    /// Read the agent now, after the person's own change deeper in the flow.
    func reload() async
    /// Bring the agent into the chat picked for «В чат».
    func addToChat(roomID: String) async
}
