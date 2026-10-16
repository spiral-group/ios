//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: concrete `ApprovalsStreamServiceProtocol`
// impl. Since Brief 0041 D3 (ADR-0054) it subscribes to the
// unified `GET /api/v1/notifications/stream` (event kinds
// `ready` / `notification` / `lagged`) and seeds from
// `GET /api/v1/me/notifications`, turning them into the
// `@Observable` needs-action + unseen state the rest of the
// app consumes (tab badge, notifications hub).
//
// Implementation notes:
//
// * Transport — `URLSession.bytes(for:)`. No third-party SSE
//   library; the parser is ~30 lines because the format is
//   tiny and the backend keeps the wire shape strict.
// * Auth — `MatrixSDKAuthBridge.currentAccessToken()` resolves
//   the MAS bearer at request time, identically to
//   `AgentPlatformService`. On a 401 mid-stream the byte-pump
//   exits and reconnect logic re-acquires a fresh token via
//   the same bridge (the matrix SDK refreshes on its own 401s
//   in parallel; see `LEARNING.md` L149-3).
// * Reconcile — every `ready`, `notification` and `lagged`
//   frame triggers a REST seed through
//   `AgentPlatformServiceProtocol.fetchNotifications`. We
//   never trust the SSE stream alone for correctness.
// * Reconnect — exponential backoff (1s → 2s → 4s → 8s →
//   capped at 30s). State enters
//   `.reconnecting(attempt:)` while the timer runs so the UI
//   can render an unobtrusive indicator.

import AgentPlatformClient
import Foundation
import OSLog

@MainActor
@Observable
final class ApprovalsStreamService: ApprovalsStreamServiceProtocol {
    // MARK: - Public @Observable surface

    private(set) var needsAction: [NeedsActionItem] = []
    private(set) var pendingCount = 0
    private(set) var unseenCount = 0
    private(set) var isSeeded = false
    private(set) var connectionState: ApprovalsStreamConnectionState = .disconnected

    // MARK: - Dependencies

    private let agentPlatformService: AgentPlatformServiceProtocol
    private let authProvider: AuthTokenProviding
    private let baseURL: URL
    /// The platform client's policy: no response is kept in a URL cache.
    let urlSession: URLSession

    // MARK: - Internal lifecycle

    /// The byte-pump task. Owned solely by this service; cancel
    /// on `disconnect()` or before reconnecting.
    private var pumpTask: Task<Void, Never>?

    /// Reconnect backoff state. Reset on each successful
    /// `connected` transition.
    private var reconnectAttempt = 0

    /// Set by `stop()`: the session is over, and every way back to a request
    /// (`connect()`, a scheduled reconnect, a pump mid-dial) checks it.
    private var isStopped = false

    init(agentPlatformService: AgentPlatformServiceProtocol,
         authProvider: AuthTokenProviding,
         baseURL: URL,
         urlSession: URLSession = AgentPlatformClient.makeUncachedURLSession()) {
        self.agentPlatformService = agentPlatformService
        self.authProvider = authProvider
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    // MARK: - ApprovalsStreamServiceProtocol

    func connect() {
        guard !isStopped else { return }
        // Idempotency: only kick the pump when we're cold.
        switch connectionState {
        case .connecting, .connected:
            return
        case .disconnected, .reconnecting, .failed:
            break
        }
        startPump(isReconnect: false)
    }

    func disconnect() {
        pumpTask?.cancel()
        pumpTask = nil
        connectionState = .disconnected
        isSeeded = false
    }

    func stop() {
        isStopped = true
        disconnect()
        MXLog.info("ApprovalsStreamService: stopped for good")
    }

    func reseed() async {
        await performSeed()
    }

    func markSeen() async {
        // Optimistic local zero so the badge clears instantly;
        // the PUT persists it (monotonic server-side). On failure
        // the next seed restores the true count.
        unseenCount = 0
        switch await agentPlatformService.markNotificationsSeen() {
        case .success(let effective):
            MXLog.info("ApprovalsStreamService: last-seen marker bumped to \(effective)")
        case .failure(let error):
            MXLog.error("ApprovalsStreamService: mark-seen failed: \(error)")
        }
    }

    // MARK: - Pump

    private func startPump(isReconnect: Bool) {
        guard !isStopped else { return }
        pumpTask?.cancel()
        connectionState = isReconnect ? .reconnecting(attempt: reconnectAttempt) : .connecting
        isSeeded = false

        pumpTask = Task { [weak self] in
            await self?.runPump()
        }
    }

    /// One full lifetime of the byte stream: build the request,
    /// dial, parse frames until the connection terminates, then
    /// hand off to the reconnect loop.
    private func runPump() async {
        let token = await authProvider.currentAccessToken()
        guard !isStopped else { return }
        guard let token else {
            connectionState = .failed(reason: "no_token")
            MXLog.error("ApprovalsStreamService: no MAS token available — aborting connect")
            return
        }

        var request = URLRequest(url: baseURL.appending(path: "/api/v1/notifications/stream"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 0 // disable URLSession's 60s default; we want the stream long-lived

        do {
            let (bytes, response) = try await urlSession.bytes(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            switch http.statusCode {
            case 200:
                break // Stream opened. Fall through to parse loop.
            case 401:
                // Token expired since connect. Mirror
                // `AgentPlatformService.withUnauthorizedRetry` —
                // matrix SDK refreshes on its own 401s in
                // parallel; sleep briefly so the keychain has
                // a fresh token before reconnect.
                MXLog.warning("ApprovalsStreamService: 401 on stream open — scheduling reconnect")
                try? await Task.sleep(for: .milliseconds(700))
                throw URLError(.userAuthenticationRequired)
            default:
                throw URLError(.badServerResponse,
                               userInfo: ["status": http.statusCode])
            }

            // Connection up. Reset reconnect counter and seed.
            reconnectAttempt = 0
            connectionState = .connected
            await performSeed()
            try await consumeFrames(from: bytes)

            // Graceful EOF — backend closed. Treat as reconnect.
            MXLog.info("ApprovalsStreamService: stream closed by server")
            await scheduleReconnect()

        } catch is CancellationError {
            // disconnect() was called. Don't reconnect.
            MXLog.info("ApprovalsStreamService: pump cancelled")
            return
        } catch {
            MXLog.error("ApprovalsStreamService: pump error: \(error)")
            await scheduleReconnect()
        }
    }

    /// Parse SSE frames from the byte stream. Each frame is a
    /// run of `field: value` lines terminated by a blank line.
    /// We only care about `event:` and `data:`; comment lines
    /// (start with `:`) are dropped silently — they're the 15 s
    /// keepalive heartbeats from the backend.
    ///
    /// ### Why we dispatch on the `data:` line, not the blank line
    ///
    /// `URLSession.AsyncBytes.lines` NEVER yields empty lines —
    /// the spec-canonical "blank line ends the frame" parser
    /// silently dispatches nothing (Brief 0041 D-close live E2E
    /// caught this: the connection opened and seeded, but no
    /// frame was ever delivered; the pre-0041 approvals badge
    /// only looked live because every appear/foreground reseeds).
    /// Our backend's wire shape is strict — axum's `SseEvent`
    /// writes `event:`, optional `id:`, then a single `data:`
    /// line LAST — so the end of the `data:` line IS the end of
    /// the frame, and dispatching there is exact (not a
    /// heuristic) for this producer.
    private func consumeFrames(from bytes: URLSession.AsyncBytes) async throws {
        var event: String?

        for try await line in bytes.lines {
            if line.isEmpty || line.hasPrefix(":") {
                continue // defensive / comment keepalive
            }
            if let colonIndex = line.firstIndex(of: ":") {
                let field = String(line[..<colonIndex])
                let valueStart = line.index(after: colonIndex)
                // SSE spec: a single optional space after the
                // colon is part of syntax, not the value.
                let value = line[valueStart...].hasPrefix(" ")
                    ? String(line[line.index(after: valueStart)...])
                    : String(line[valueStart...])
                switch field {
                case "event":
                    event = value
                case "data":
                    // `data` is the frame's last field on this
                    // backend — dispatch immediately.
                    if let currentEvent = event {
                        await dispatch(event: currentEvent, data: value)
                    }
                    event = nil
                case "id":
                    // We don't yet honour Last-Event-ID on
                    // reconnect — backend doesn't replay
                    // either today. See sse-and-push-lifecycle.
                    break
                default:
                    break
                }
            }
        }
    }

    /// Apply a parsed frame to the observable state.
    private func dispatch(event: String, data: String) async {
        switch event {
        case "ready":
            // Server confirmed subscription. Already seeded in
            // `runPump`; nothing to do here besides log.
            MXLog.info("ApprovalsStreamService: ready frame received")
        case "notification":
            handleNotificationFrame(data: data)
        case "lagged":
            MXLog.warning("ApprovalsStreamService: broadcast channel lagged — reseeding")
            await performSeed()
        default:
            MXLog.warning("ApprovalsStreamService: unknown event '\(event)' — ignored")
        }
    }

    /// Best-effort apply of a single `notification` frame. The
    /// backend payload mirrors `ApprovalEvent` (see
    /// `matrix-agent-platform/src/adapters/approval_events.rs`)
    /// with a `kind` discriminator (`created` / `decided` /
    /// `expired`).
    ///
    /// We treat every frame as a hint, not the source of truth —
    /// any frame schedules an opportunistic REST reseed which
    /// reconciles both needs-action families + the unseen
    /// count in one call (same shape S151 chose for approvals).
    private func handleNotificationFrame(data: String) {
        Task { await performSeed() }
    }

    // MARK: - REST seed

    private func performSeed() async {
        switch await agentPlatformService.fetchNotifications(activityCursor: nil, limit: 25) {
        case .success(let snapshot):
            needsAction = snapshot.needsAction
            pendingCount = needsAction.count
            unseenCount = snapshot.unseenCount
            isSeeded = true
            MXLog.info("ApprovalsStreamService: seeded \(pendingCount) needs-action item(s), \(unseenCount) unseen")
        case .failure(let error):
            isSeeded = false
            MXLog.error("ApprovalsStreamService: seed failed: \(error)")
        }
    }

    // MARK: - Reconnect

    private func scheduleReconnect() async {
        // A disconnect mid-dial ends here, not in `.reconnecting`.
        guard !isStopped, !Task.isCancelled else { return }
        reconnectAttempt += 1
        let delaySeconds = min(pow(2.0, Double(reconnectAttempt - 1)), 30.0)
        let delay: Duration = .seconds(delaySeconds)
        connectionState = .reconnecting(attempt: reconnectAttempt)
        MXLog.info("ApprovalsStreamService: reconnect attempt \(reconnectAttempt) in \(delaySeconds)s")
        try? await Task.sleep(for: delay)
        if Task.isCancelled || isStopped { return }
        startPump(isReconnect: true)
    }
}
