//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): an agent's page's interest in whose the agent is, for as long as the page
// holds it. Cancelled by `cancel()` or by being released.
//

import Foundation

final class AgentCardObservation {
    let userID: String
    private let store: AgentsStore
    private let onChange: (AgentOwnership) -> Void
    private var isObserving = true
    private var ownership: AgentOwnership?
    
    /// `nil` when there is nothing to observe: no store, or no agent. Otherwise `onChange` hears
    /// the first answer before this returns, so a page made now has its shape for its first render.
    init?(userID: String?, store: AgentsStore?, onChange: @escaping (AgentOwnership) -> Void) {
        guard let userID, SpiralAppPostSession.isAgent(userID), let store else { return nil }
        self.userID = userID
        self.store = store
        self.onChange = onChange
        
        store.show(.spaces, by: self)
        deliver()
        store.observe { [weak self] in
            guard let self, isObserving else { return false }
            deliver()
            return true
        }
    }
    
    isolated deinit {
        cancel()
    }
    
    func cancel() {
        guard isObserving else { return }
        isObserving = false
        store.stopShowing(.spaces, by: self)
    }
    
    /// The page shows again: a failed read gets another go, or it would hide the erase and the blocks for the page's life.
    func readAgainIfUnknown() {
        guard ownership == .unknown(isReading: false) else { return }
        store.rereadStaleShown()
    }
    
    private func deliver() {
        let ownership = store.ownership(matrixUserID: userID)
        guard ownership != self.ownership else { return }
        // The safe page stays for the length of a read: Block doesn't go, only to come back if the read fails again.
        if self.ownership == .unknown(isReading: false), ownership == .unknown(isReading: true) { return }
        self.ownership = ownership
        onChange(ownership)
    }
}
