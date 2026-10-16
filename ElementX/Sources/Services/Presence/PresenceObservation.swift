//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0072, ADR-0083): a screen's interest in one person's
// presence, for as long as the screen holds it. Cancelled by `cancel()` or
// by being released — a view model that is dropped without `stop()` must not
// leave its user in the poll.
//

import Combine
import Foundation

final class PresenceObservation {
    let userID: String
    private let service: PresenceObserverServiceProtocol
    private var cancellable: AnyCancellable?
    private var isObserving = true
    
    /// `nil` when there is nothing to observe: no service, no user, the user
    /// themselves, or someone without meaningful presence.
    init?(userID: String?,
          ownUserID: String,
          service: PresenceObserverServiceProtocol?,
          onChange: @escaping (UserPresence?) -> Void) {
        guard let userID, userID != ownUserID, SpiralPresencePolicy.hasPresence(userID), let service else {
            return nil
        }
        self.userID = userID
        self.service = service
        
        service.observe(userID)
        cancellable = service.presencePublisher
            .map { $0[userID] }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: onChange)
    }
    
    isolated deinit {
        cancel()
    }
    
    func cancel() {
        guard isObserving else { return }
        isObserving = false
        cancellable = nil
        service.stopObserving(userID)
    }
}

/// AGENT-PLATFORM (Brief 0072, ADR-0083): the rows of one list on screen,
/// asked for as list rows are (`listInterval`). Its own scope name, so two
/// lists never replace each other's set. Cleared by `cancel()` or on release.
final class PresenceScope {
    private let service: PresenceObserverServiceProtocol
    private let name = "list-\(UUID().uuidString)"
    private var isActive = true
    
    init(service: PresenceObserverServiceProtocol) {
        self.service = service
    }
    
    isolated deinit {
        cancel()
    }
    
    /// The users whose rows are on screen now; replaces the previous set.
    func observe(_ userIDs: Set<String>) {
        guard isActive else { return }
        service.setObserved(userIDs, scope: name)
    }
    
    func cancel() {
        guard isActive else { return }
        isActive = false
        service.setObserved([], scope: name)
    }
}
