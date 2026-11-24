//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: platform sync (decision 289, contract § 7). One stream per
// session while the app is in the foreground, none in the background (a
// launch into the background included). It keeps the last position in memory
// and resumes from it; `ready {fresh: true}` and `limited` tell every store to
// re-read what is shown. The server ends a stream after 30 minutes, which
// reconnects at once; a failure — a stream that ends before `ready` or within
// seconds of it included — waits, longer each time, or as long as the server
// says. Changes go to each area's store by the prefix of their kind.
//

import Combine
import SwiftUI

/// What the screens show at the top while the stream is not live.
enum PlatformSyncConnectionState: Equatable {
    /// Not started, in the background, or no sync on this backend: nothing is open.
    case idle
    case connecting
    /// The server sent `ready`: the changes that follow are live.
    case live
    /// The last stream failed; the next attempt waits. `isOffline`: it failed
    /// on the network, not on the server's answer (a 429, a 5xx, an early end).
    case waiting(attempt: Int, isOffline: Bool)
    /// The server refused the stream in a way waiting does not mend soon (a `401` after the retry, a `403`,
    /// a certificate): no line, the screens' own reads show what is wrong. It is tried again quietly on a
    /// long wait, and at once on the return to the foreground.
    case refused

    /// The line at the top; `isCatchingUp` while the re-reads of `ready.fresh` or `limited` run.
    func status(isCatchingUp: Bool) -> PlatformSyncStatus? {
        switch self {
        case .idle, .refused: nil
        case .connecting: .updating
        // The server is there but busy: the stream comes back by itself, nothing is wrong with the connection.
        case .waiting(_, let isOffline): isOffline ? .noConnection : .updating
        case .live: isCatchingUp ? .updating : nil
        }
    }
}

/// The line at the top of the feed's and the Agents tab's screens while the stream is not live.
enum PlatformSyncStatus: Equatable {
    case updating
    case noConnection
}

final class PlatformSync {
    private let service: PlatformSyncServiceProtocol
    private let feedStore: FeedStore
    private let agentsStore: AgentsStore?
    private let backoff: (Int) -> Duration
    private let refusalBackoff: (Int) -> Duration
    private let minimumHealthyLife: Duration
    private let isApplicationInBackground: () -> Bool

    /// The last position delivered, `ready`'s included; `nil` until the first stream is ready.
    private(set) var position: String?
    private(set) var connectionState: PlatformSyncConnectionState = .idle {
        didSet {
            feedStore.connectionState = connectionState
            agentsStore?.connectionState = connectionState
        }
    }

    private var isStarted = false
    private var isActive = true
    private var streamTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// - Parameters:
    ///   - backoff: the wait before the attempt after `n` failures in a row.
    ///   - refusalBackoff: the same after a refusal, which is tried again quietly.
    ///   - minimumHealthyLife: a ready stream that ends sooner is a failure, not the server's end.
    ///   - isApplicationInBackground: read on `start`; later changes come as notifications.
    init(service: PlatformSyncServiceProtocol,
         feedStore: FeedStore,
         agentsStore: AgentsStore? = nil,
         backoff: @escaping (Int) -> Duration = PlatformSync.defaultBackoff,
         refusalBackoff: @escaping (Int) -> Duration = PlatformSync.defaultRefusalBackoff,
         minimumHealthyLife: Duration = .seconds(5),
         isApplicationInBackground: @escaping () -> Bool = { UIApplication.shared.applicationState == .background }) {
        self.service = service
        self.feedStore = feedStore
        self.agentsStore = agentsStore
        self.backoff = backoff
        self.refusalBackoff = refusalBackoff
        self.minimumHealthyLife = minimumHealthyLife
        self.isApplicationInBackground = isApplicationInBackground
    }

    isolated deinit {
        streamTask?.cancel()
    }

    /// 1, 2, 4 … 60 s.
    nonisolated static func defaultBackoff(_ failures: Int) -> Duration {
        .seconds(min(60, 1 << min(max(failures - 1, 0), 6)))
    }

    /// 5, 10, 20 … 30 minutes.
    nonisolated static func defaultRefusalBackoff(_ failures: Int) -> Duration {
        .seconds(min(30 * 60, 300 << min(max(failures - 1, 0), 3)))
    }

    // MARK: - Lifecycle

    /// Opens the stream for the session and follows the app between foreground and background.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        isActive = !isApplicationInBackground()
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.appDidEnterBackground() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.appDidBecomeActive() }
            .store(in: &cancellables)
        connect()
    }

    func stop() {
        isStarted = false
        cancellables.removeAll()
        disconnect()
    }

    func appDidEnterBackground() {
        isActive = false
        disconnect()
    }

    func appDidBecomeActive() {
        isActive = true
        // A read that failed is not left for the next change: the return reads it again.
        agentsStore?.rereadStaleShown()
        // A stream that is still up keeps going; one that ended or waits starts again now.
        guard connectionState != .live, connectionState != .connecting else { return }
        connect()
    }

    // MARK: - The stream

    private func connect() {
        guard isStarted, isActive else { return }
        streamTask?.cancel()
        connectionState = .connecting
        streamTask = Task { [weak self, service, backoff, refusalBackoff, minimumHealthyLife] in
            await Self.run(service: service, backoff: backoff, refusalBackoff: refusalBackoff, minimumHealthyLife: minimumHealthyLife) { self }
        }
    }

    private func disconnect() {
        streamTask?.cancel()
        streamTask = nil
        connectionState = .idle
    }

    /// One stream after another, each from the last position, until cancelled,
    /// the route is missing, or the owner is gone: `owner` is asked again for
    /// every frame, so an open stream never keeps it alive.
    private static func run(service: PlatformSyncServiceProtocol,
                            backoff: (Int) -> Duration,
                            refusalBackoff: (Int) -> Duration,
                            minimumHealthyLife: Duration,
                            owner: () -> PlatformSync?) async {
        var failures = 0
        while !Task.isCancelled {
            guard let since = owner().map(\.position) else { return }
            var wait: Duration?
            var isOffline = false
            var isRefused = false

            switch await service.open(since: since) {
            case .success(let events):
                guard let end = await follow(events, owner: owner) else { return }
                let wasHealthy = end.readyAt.map { .now - $0 >= minimumHealthyLife } ?? false
                if wasHealthy {
                    failures = 0
                }
                // The server's end (30 minutes, a restart) reconnects at once; one before
                // `ready` or right after it is a failure, or a server that ends every stream spins us.
                if end.error != nil || !wasHealthy {
                    failures += 1
                    wait = backoff(failures)
                    // Only a stream that broke off on the network is offline: not one the server ended early, nor TLS or a frame that did not decode.
                    isOffline = end.error.map { PlatformSyncError(thrown: $0) == .transport } ?? false
                }
                MXLog.info("The sync stream \(end.summary(wasHealthy: wasHealthy))")
            case .failure(.invalidPosition) where since != nil:
                // Not a position this server gave out (another deploy, a restore): start fresh, which re-reads what is shown.
                MXLog.info("The sync stream refused its position: starting fresh")
                owner()?.position = nil
                continue
            case .failure(.unavailable):
                guard !Task.isCancelled else { return }
                // No sync on this backend: nothing to follow until the app returns.
                MXLog.info("The sync stream is not on this backend")
                owner()?.connectionState = .idle
                return
            case .failure(let error):
                guard !Task.isCancelled else { return }
                failures += 1
                // A refusal is not "Updating…" for good: it is tried again quietly, on a long wait
                // (a token refreshed late, a captive portal left), and at once on the return to the foreground.
                isRefused = error.isRefusal
                wait = isRefused ? refusalBackoff(failures) : Self.wait(after: error, failures: failures, backoff: backoff)
                isOffline = error == .transport
                MXLog.info("Could not open the sync stream: \(error)")
            }

            // The server's healthy end reconnects at once, from the same position: the screens say nothing of it.
            guard let wait else { continue }
            owner()?.connectionState = isRefused ? .refused : .waiting(attempt: failures, isOffline: isOffline)
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            if !isRefused {
                owner()?.connectionState = .connecting
            }
        }
    }

    /// How one opened stream ended; `nil` when the run is over (cancelled, or the owner gone).
    private static func follow(_ events: PlatformSyncEventStream, owner: () -> PlatformSync?) async -> StreamEnd? {
        var readyAt: ContinuousClock.Instant?
        do {
            for try await event in events {
                guard !Task.isCancelled, let owner = owner() else { return nil }
                if case .ready = event, readyAt == nil {
                    readyAt = .now
                }
                owner.handle(event)
            }
            return Task.isCancelled ? nil : StreamEnd(readyAt: readyAt, error: nil)
        } catch {
            return Task.isCancelled ? nil : StreamEnd(readyAt: readyAt, error: error)
        }
    }

    private struct StreamEnd {
        /// When `ready` came; `nil` when it never did.
        let readyAt: ContinuousClock.Instant?
        let error: (any Error)?

        func summary(wasHealthy: Bool) -> String {
            if let error {
                "failed: \(type(of: error))"
            } else if readyAt == nil {
                "ended before it was ready"
            } else {
                wasHealthy ? "ended" : "ended right after it was ready"
            }
        }
    }

    func handle(_ event: PlatformSyncEvent) {
        position = event.position
        switch event {
        case .ready(_, let fresh):
            connectionState = .live
            if fresh {
                feedStore.markEverythingStale()
                agentsStore?.markEverythingStale()
            } else {
                // A resumed stream: what failed to read while it was down is read now.
                agentsStore?.rereadStaleShown()
            }
        case .changes(_, let changes):
            route(changes)
        case .limited:
            MXLog.info("The sync stream is past the log: everything shown is read again")
            feedStore.markEverythingStale()
            agentsStore?.markEverythingStale()
        }
    }

    /// By the prefix of the kind.
    private func route(_ changes: [PlatformChange]) {
        var feedChanges: [FeedSyncChange] = []
        var agentsChanges: [AgentsSyncChange] = []
        for change in changes {
            switch change {
            case .feed(let feedChange):
                feedChanges.append(feedChange)
            case .agents(let agentsChange):
                agentsChanges.append(agentsChange)
            case .other(let kind):
                MXLog.verbose("Sync change of kind \(kind) has no store here")
            }
        }
        if !feedChanges.isEmpty {
            feedStore.apply(feedChanges)
        }
        if !agentsChanges.isEmpty {
            agentsStore?.apply(agentsChanges)
        }
    }

    /// The server's `Retry-After` over the window or the stream cap, else the backoff.
    static func wait(after error: PlatformSyncError, failures: Int, backoff: (Int) -> Duration) -> Duration {
        switch error {
        case .rateLimited(let seconds?), .temporarilyUnavailable(let seconds?):
            max(.seconds(seconds), backoff(failures))
        default:
            backoff(failures)
        }
    }
}
