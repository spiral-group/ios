//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine

protocol AgentChatsScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<AgentChatsScreenViewModelAction, Never> { get }
    var context: AgentChatsScreenViewModel.Context { get }
    
    /// Reads the agent now, after a change deeper in the flow.
    func reload() async
}
