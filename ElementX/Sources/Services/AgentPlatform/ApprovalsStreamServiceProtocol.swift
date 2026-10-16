//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: protocol surface for live approval lifecycle
// stream. The contract intentionally splits into a "read state"
// half (the `@Observable` properties) and a "lifecycle"
// half (`connect`/`disconnect`) so ViewModels can both observe
// the data and own connection lifetime when they care
// (foreground transitions).
//
// See `docs/project/DESIGNS/sse-and-push-lifecycle.md` for the
// backend contract (events `ready` / `approval` / `lagged`,
// 15 s keepalive comments, server-side tenant+owner filter)
// and `DECISIONS.md` § "ApprovalsStreamService lives at
// UserSession scope" for the placement rationale.

import Foundation

/// Connection-lifecycle state of the SSE stream. Drives both
/// the UI connectivity indicator and the reconciler's reseed
/// trigger (`connect` finishes → backend emits `ready` →
/// service flips to `.connected` AND reseeds via REST).
nonisolated enum ApprovalsStreamConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    /// Reconnect attempt is queued; SwiftUI renders a banner.
    /// `attempt` starts at 1 on the first retry.
    case reconnecting(attempt: Int)
    /// Hard failure that needs user intervention (e.g. auth
    /// rotation that retry-on-401 couldn't resolve). The UI
    /// surfaces a "Tap to reconnect" affordance.
    case failed(reason: String)
}

// sourcery: AutoMockable
/// Server-Sent Events client for `/api/v1/approvals/stream`.
/// One instance per UserSession (per DECISIONS.md). Construct
/// via `UserSessionStore.buildUserSessionWithClient`; tear
/// down on logout.
///
/// The protocol is intentionally `@MainActor` so SwiftUI views
/// can read the `@Observable` properties without trampolining
/// through queues. Long-running work (the SSE byte-pump task)
/// lives on a detached `Task` started from `connect()`.
@MainActor
protocol ApprovalsStreamServiceProtocol: AnyObject {
    /// Brief 0041 D3 (ADR-0054): the pinned "Needs action" union —
    /// pending approvals + verifications,
    /// interleaved newest-first. Seeded from
    /// `GET /api/v1/me/notifications` on connect / frames / `lagged`.
    var needsAction: [NeedsActionItem] { get }

    /// Convenience count for the tab-bar badge. Equivalent to
    /// `needsAction.count` but exposed as its own property so a
    /// Combine-free `withObservationTracking` sink can fence on
    /// just this value without re-rendering on every list edit.
    var pendingCount: Int { get }

    /// Server-computed "new since you last looked" count
    /// (Brief 0041 D1b last-seen marker). Reset locally by
    /// `markSeen()`.
    var unseenCount: Int { get }

    /// Whether `needsAction` holds a successful read made since the stream
    /// last connected. False before the first seed, after a failed one and
    /// once disconnected: a screen then knows nothing, not «nothing waits».
    var isSeeded: Bool { get }

    /// Connection state. See `ApprovalsStreamConnectionState`
    /// for the four possible values.
    var connectionState: ApprovalsStreamConnectionState { get }

    /// Boot the connection. Idempotent: calling `connect()`
    /// while already `.connected` or `.connecting` is a no-op.
    /// Spawns the SSE byte-pump task and triggers an immediate
    /// REST seed once the `ready` frame arrives.
    func connect()

    /// Tear down the byte-pump task. Idempotent. Used by the
    /// app-lifecycle observer when the app moves to background
    /// (iOS kills long-lived HTTP anyway — disconnecting
    /// cleanly avoids cascading errors when the OS later
    /// suspends the URLSession).
    func disconnect()

    /// The session ended (sign-out, account deletion, soft logout, a cache
    /// clear): disconnect for good. Nothing connects or reconnects after it,
    /// so no request goes out with the ended session's token (decision 154).
    func stop()

    /// Force a fresh REST seed without disconnecting. Useful
    /// after `lagged` frames or when a downstream view wants
    /// to confirm freshness on appear.
    func reseed() async

    /// Brief 0041 D3: PUT the last-seen marker (server clock) and
    /// zero `unseenCount` locally. Called when the hub screen
    /// appears.
    func markSeen() async
}
