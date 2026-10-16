//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0072, ADR-0083, ADR-0084): who is online.
//
// Sliding sync has no presence extension yet (MSC4186 lists it as a future
// MSC), so a sliding sync client never receives `m.presence` for others.
// Until it does, this service asks `GET /presence/{userId}/status` for the
// users the UI is showing — and only them, only while the app is in the
// foreground. Screens say what they show: `observe` for the one person a
// screen is about (a DM, a profile) — asked every `focusedInterval`; a scope
// for the rows of a list — every `listInterval`. When the extension lands
// this is the one place that changes: the publisher stays.
//
// What it never polls: the user themselves, users without meaningful
// presence (`SpiralPresencePolicy`: agents, bridge puppets and bots), and a
// user the server refused (403: no shared room, or no such user — Synapse
// answers the same for both) for `forbiddenCooldown` after the refusal: a
// shared room can appear later. Privacy is the server's (ADR-0084): what it
// answers — exact, or a coarse bucket — is what the app shows.
//

import Combine
import Foundation
import UIKit

// sourcery: AutoMockable
protocol PresenceObserverServiceProtocol {
    /// Every presence the service has read, by user id. Absent = unknown; a
    /// view shows nothing for an unknown user rather than guess.
    var presencePublisher: CurrentValuePublisher<[String: UserPresence], Never> { get }
    
    /// A screen shows this user; counted, so two screens can show the same one.
    func observe(_ userID: String)
    func stopObserving(_ userID: String)
    /// A list shows these users right now (replaces the scope's previous set).
    func setObserved(_ userIDs: Set<String>, scope: String)
}

final class PresenceObserverService: PresenceObserverServiceProtocol {
    private let clientProxy: ClientProxyProtocol
    private let notificationCenter: NotificationCenter
    private let now: () -> Date
    /// How often the loop wakes to see who is due.
    private let tickInterval: TimeInterval
    /// The person a screen is about: their DM, their profile.
    private let focusedInterval: TimeInterval
    /// The rows of a list.
    private let listInterval: TimeInterval
    private let maxConcurrentRequests: Int
    /// How long a 403 keeps a user out of the poll.
    private let forbiddenCooldown: TimeInterval
    
    private var refCounts: [String: Int] = [:]
    private var scopes: [String: Set<String>] = [:]
    private var forbiddenUntil: [String: Date] = [:]
    private var lastRequested: [String: Date] = [:]
    private var inFlight: Set<String> = []
    private var isForegroundActive: Bool
    private var pollTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    private let presenceSubject = CurrentValueSubject<[String: UserPresence], Never>([:])
    var presencePublisher: CurrentValuePublisher<[String: UserPresence], Never> {
        presenceSubject.asCurrentValuePublisher()
    }
    
    init(clientProxy: ClientProxyProtocol,
         notificationCenter: NotificationCenter = .default,
         initialApplicationState: UIApplication.State = UIApplication.shared.applicationState,
         now: @escaping () -> Date = Date.init,
         tickInterval: TimeInterval = 5,
         focusedInterval: TimeInterval = 10,
         listInterval: TimeInterval = 30,
         maxConcurrentRequests: Int = 4,
         forbiddenCooldown: TimeInterval = 10 * 60) {
        self.clientProxy = clientProxy
        self.notificationCenter = notificationCenter
        self.now = now
        self.tickInterval = tickInterval
        self.focusedInterval = focusedInterval
        self.listInterval = listInterval
        self.maxConcurrentRequests = maxConcurrentRequests
        self.forbiddenCooldown = forbiddenCooldown
        isForegroundActive = initialApplicationState == .active
        
        notificationCenter.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.applicationStateChanged(isActive: false) }
            .store(in: &cancellables)
        notificationCenter.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.applicationStateChanged(isActive: true) }
            .store(in: &cancellables)
    }
    
    isolated deinit {
        pollTask?.cancel()
    }
    
    // MARK: - Protocol
    
    func observe(_ userID: String) {
        refCounts[userID, default: 0] += 1
        reschedule()
        refreshSoon()
    }
    
    func stopObserving(_ userID: String) {
        guard let count = refCounts[userID] else { return }
        if count <= 1 {
            refCounts[userID] = nil
        } else {
            refCounts[userID] = count - 1
        }
        reschedule()
    }
    
    func setObserved(_ userIDs: Set<String>, scope: String) {
        if userIDs.isEmpty {
            scopes[scope] = nil
        } else {
            scopes[scope] = userIDs
        }
        reschedule()
        refreshSoon()
    }
    
    // MARK: - Private
    
    /// Whom to poll at all: everything observed, minus ourselves, users
    /// without meaningful presence, and users still inside a 403 cooldown.
    private var pollable: Set<String> {
        let observed = Set(refCounts.keys).union(scopes.values.reduce(into: Set<String>()) { $0.formUnion($1) })
        let ownUserID = clientProxy.userID
        let now = now()
        return observed.filter { userID in
            userID != ownUserID
                && SpiralPresencePolicy.hasPresence(userID)
                && (forbiddenUntil[userID].map { $0 <= now } ?? true)
        }
    }
    
    /// Whom to poll on this tick: the pollable whose interval has passed —
    /// the focused one sooner than a list row.
    private func due(at now: Date) -> Set<String> {
        pollable.filter { userID in
            guard let last = lastRequested[userID] else { return true }
            let interval = refCounts[userID] != nil ? focusedInterval : listInterval
            return now.timeIntervalSince(last) >= interval
        }
    }
    
    /// A newly shown user should not wait for the next tick.
    private func refreshSoon() {
        guard pollTask != nil else { return }
        Task { [weak self] in await self?.refresh() }
    }
    
    private func applicationStateChanged(isActive: Bool) {
        isForegroundActive = isActive
        reschedule()
    }
    
    /// Start the loop if there is anyone to poll in the foreground; stop it
    /// otherwise. A running loop reads `pollable` on every tick, so a change
    /// in whom to poll needs no restart — only the first tick is brought
    /// forward when the loop was idle.
    private func reschedule() {
        let shouldRun = isForegroundActive && !pollable.isEmpty
        if !shouldRun {
            pollTask?.cancel()
            pollTask = nil
            return
        }
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await refresh()
                try? await Task.sleep(for: .seconds(tickInterval))
            }
        }
    }
    
    /// One round: ask for every pollable user not already being asked, a
    /// few at a time, and publish one dictionary at the end so a list
    /// re-renders once per round.
    private func refresh() async {
        let start = now()
        let userIDs = due(at: start).subtracting(inFlight)
        guard !userIDs.isEmpty else { return }
        inFlight.formUnion(userIDs)
        defer { inFlight.subtract(userIDs) }
        for userID in userIDs {
            lastRequested[userID] = start
        }
        
        // `maxConcurrentRequests` at a time. Child `Task`s inherit this actor
        // (a `TaskGroup` would need `clientProxy` to be `Sendable`); the
        // requests themselves run off it inside the proxy, so they overlap.
        var results: [(String, Result<UserPresence, ClientProxyError>)] = []
        for chunk in userIDs.sorted().chunked(into: maxConcurrentRequests) {
            let tasks = chunk.map { userID in
                Task { await (userID, clientProxy.userPresence(for: userID)) }
            }
            for task in tasks {
                await results.append(task.value)
            }
        }
        
        var presences = presenceSubject.value
        var changed = false
        let now = now()
        for (userID, result) in results {
            switch result {
            case .success(let presence):
                // An answer that shows the same is not news: keeping the
                // stored one spares every observer a redraw per poll.
                if presences[userID].map({ !$0.isEquivalent(to: presence) }) ?? true {
                    presences[userID] = presence
                    changed = true
                }
            case .failure(.forbiddenAccess):
                forbiddenUntil[userID] = now.addingTimeInterval(forbiddenCooldown)
                if presences.removeValue(forKey: userID) != nil {
                    changed = true
                }
            case .failure(let error):
                MXLog.warning("Presence for \(userID) failed: \(error)")
            }
        }
        if changed {
            presenceSubject.send(presences)
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
