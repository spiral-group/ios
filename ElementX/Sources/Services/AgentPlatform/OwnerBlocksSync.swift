//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 98): blocking a person in the messenger makes the
// owner's agents ignore them too, and unblocking there lifts that. The
// platform's agent-contact record stays the agents' one source of truth; this
// tells it the owner's blocks.
//
// The ignore list changes from several screens here and from other devices,
// and `ignoredUsersPublisher` covers all of them, so the whole list is sent:
//
// - never while the list is unknown (`nil`);
// - a burst of changes is one PUT (1 s debounce), one PUT at a time, and the
//   latest list goes last;
// - not before the first sync after launch, which may change a cached list,
//   and then once on every launch;
// - a failed PUT stays pending and is retried on the next sync (throttled to
//   5 s);
// - again when the platform dropped or created the rows the owner's blocks
//   live in: an erase of an assistant's memory about a person, a new company
//   agent, a new personal assistant (decision 136) (`resync()`).
//

import Combine
import Foundation

final class OwnerBlocksSync {
    private let agentPlatformService: AgentPlatformServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    /// The latest known list, for a resync.
    private var latestList: Set<String>?
    /// Not yet accepted by the platform.
    private var pendingList: Set<String>?
    /// Bumped by every change and every resync, so a PUT that was in flight
    /// before one never counts as having sent it, even with the same list.
    private var pendingGeneration = 0
    private var isWriting = false
    /// The first sync after launch has arrived.
    private var hasSynced = false
    /// The session's token was refused (a soft logout): every PUT would be a
    /// 401 until the person signs in again, which builds a new session.
    private var isSignedOut = false
    
    init(clientProxy: ClientProxyProtocol,
         agentPlatformService: AgentPlatformServiceProtocol,
         debounce: DispatchQueue.SchedulerTimeType.Stride = .seconds(1),
         syncThrottle: DispatchQueue.SchedulerTimeType.Stride = .seconds(5)) {
        self.agentPlatformService = agentPlatformService
        
        clientProxy.ignoredUsersPublisher
            .compactMap { $0.map(Set.init) }
            .removeDuplicates()
            .debounce(for: debounce, scheduler: DispatchQueue.main)
            .sink { [weak self] list in self?.listChanged(list) }
            .store(in: &cancellables)
        
        clientProxy.actionsPublisher
            .filter(\.isSyncUpdate)
            .throttle(for: syncThrottle, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in self?.synced() }
            .store(in: &cancellables)
        
        clientProxy.actionsPublisher
            .filter { if case .receivedAuthError = $0 { true } else { false } }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.isSignedOut = true }
            .store(in: &cancellables)
        
        agentPlatformService.ownerBlocksResyncPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.resync() }
            .store(in: &cancellables)
    }
    
    /// The line a block or unblock alert in the messenger adds about the
    /// owner's agents.
    static func alertLine(for isBlocking: Bool) -> String {
        isBlocking ? UntranslatedL10n.screenRoomMemberDetailsBlockAlertAgents : UntranslatedL10n.screenRoomMemberDetailsUnblockAlertAgents
    }
    
    /// Sends the latest list again.
    func resync() {
        guard let latestList else { return }
        setPending(latestList)
    }
    
    // MARK: - Private
    
    private func listChanged(_ list: Set<String>) {
        latestList = list
        setPending(list)
    }
    
    private func setPending(_ list: Set<String>) {
        pendingList = list
        pendingGeneration += 1
        Task { await flush() }
    }
    
    private func synced() {
        hasSynced = true
        Task { await flush() }
    }
    
    /// Writes until nothing is pending. One writer at a time: a change while a
    /// PUT is in flight goes after it, so the platform ends with the latest
    /// list whatever order the requests would have finished in.
    private func flush() async {
        guard hasSynced, !isSignedOut, !isWriting else { return }
        isWriting = true
        defer { isWriting = false }
        
        while let list = pendingList, !isSignedOut {
            let generation = pendingGeneration
            switch await agentPlatformService.syncIgnoredUsers(list.sorted()) {
            case .success:
                if pendingGeneration == generation {
                    pendingList = nil
                }
            case .failure(let error):
                // Kept pending: the next sync retries.
                MXLog.error("Failed sending the ignore list to the agents: \(error)")
                return
            }
        }
    }
}
