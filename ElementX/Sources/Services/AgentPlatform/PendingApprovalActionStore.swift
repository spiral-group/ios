//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: persistent queue of approval decisions that
// haven't completed their backend round-trip yet.
//
// Lives in App Group UserDefaults so the NSE could read it in
// the future (currently only the main app writes to and
// reconciles from it; NSE doesn't touch actions). The queue is
// drained on `applicationDidBecomeActive` — see
// `AppCoordinator.reconcilePendingApprovalActions()`.
//
// Failure modes covered:
//   * Network drop mid-request → enqueue, post local "Couldn't
//     deliver" notification, retry on next foreground.
//   * iOS killed the background-launched process before the POST
//     completed → entry survives in UserDefaults, next foreground
//     replays.
//   * Backend returns 5xx → enqueue + local notification + retry.
//   * Backend returns 409 (already decided) → drop silently
//     (idempotent server-side).
//
// 401 and other auth errors are NOT enqueued — they need
// interactive re-auth which can't happen from a background
// launch. Those post a "Sign in required" local notification
// instead.

import Foundation

/// Single queued action. Codable so it round-trips through
/// `UserDefaults` cleanly across process restarts.
nonisolated struct PendingApprovalAction: Codable, Equatable {
    let approvalID: String
    let decisionKind: DecisionKind
    let editBody: String?
    let firstAttemptedAt: Date
    let lastAttemptedAt: Date
    let attempts: Int

    /// Sum-type discriminator for the original `ApprovalDecision`
    /// — flattened because the underlying enum has an associated
    /// value only for `.edit(newBody:)`, which no lock-screen
    /// action carries (they approve or reject; an edit is made on
    /// the card).
    enum DecisionKind: String, Codable {
        case approve
        case reject
        case edit
    }

    var decision: ApprovalDecision {
        switch decisionKind {
        case .approve: return .approve
        case .reject: return .reject
        case .edit: return .edit(newBody: editBody ?? "")
        }
    }
}

/// Persisted queue of in-flight or failed approval-decide
/// requests. Thread-safe via an internal serial queue (not an
/// actor — the API is intentionally synchronous for the
/// notification-action hot path where every millisecond of
/// background-task budget counts).
nonisolated final class PendingApprovalActionStore: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let queue = DispatchQueue(label: "ua.veruslogistics.agent.pendingApprovals")
    private let storageKey = "agent_platform.pending_approval_actions"

    /// Per-action retry cap. After this many attempts the entry
    /// is left in the queue but `reconcile` skips it — the user
    /// must open the app and decide manually. Prevents an
    /// indefinite background-retry loop against a dead backend.
    static let maxAttempts = 5

    /// Construct from the App Group UserDefaults suite. Returns
    /// nil if the App Group isn't readable (e.g. mis-configured
    /// entitlements), which the main app treats as "skip the
    /// retry path entirely" — actions still run via the live
    /// network call, just without persistence across kills.
    init?(appGroupIdentifier: String) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return nil
        }
        userDefaults = defaults
    }

    /// Visible to tests so they can inject an in-memory suite.
    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    // MARK: - Mutations

    /// Insert a fresh failure entry. The caller has just observed
    /// the decide call fail (network / 5xx); we record so the
    /// next foreground can retry.
    func enqueue(approvalID: String, decision: ApprovalDecision) {
        queue.sync {
            var items = readItems()
            // Replace any existing entry for the same approvalID
            // — newer attempts supersede older ones.
            items.removeAll { $0.approvalID == approvalID }
            let entry = PendingApprovalAction(approvalID: approvalID,
                                              decisionKind: decisionKind(for: decision),
                                              editBody: editBody(from: decision),
                                              firstAttemptedAt: Date(),
                                              lastAttemptedAt: Date(),
                                              attempts: 1)
            items.append(entry)
            writeItems(items)
        }
    }

    /// Mark a successful retry — drop the entry from the queue.
    /// Called from `reconcile` once `decideApproval` returns 2xx
    /// or 409 (idempotent-success treated as completion).
    func markCompleted(approvalID: String) {
        queue.sync {
            var items = readItems()
            items.removeAll { $0.approvalID == approvalID }
            writeItems(items)
        }
    }

    /// Bump the attempt counter for a still-failing retry. Caller
    /// is `reconcile`; this is the only way `attempts > 1`.
    func incrementAttempt(approvalID: String) {
        queue.sync {
            var items = readItems()
            guard let index = items.firstIndex(where: { $0.approvalID == approvalID }) else {
                return
            }
            let existing = items[index]
            items[index] = PendingApprovalAction(approvalID: existing.approvalID,
                                                 decisionKind: existing.decisionKind,
                                                 editBody: existing.editBody,
                                                 firstAttemptedAt: existing.firstAttemptedAt,
                                                 lastAttemptedAt: Date(),
                                                 attempts: existing.attempts + 1)
            writeItems(items)
        }
    }

    // MARK: - Reads

    /// Snapshot of all queued entries. Caller iterates and calls
    /// `decideApproval` for each; `markCompleted` or
    /// `incrementAttempt` per outcome.
    func allPending() -> [PendingApprovalAction] {
        queue.sync { readItems() }
    }

    /// Subset that should still be retried — drops entries past
    /// `maxAttempts`. Those stay in storage so the next foreground
    /// can show them on the approvals list (via the SSE reseed),
    /// but `reconcile` skips them to avoid hammering a dead
    /// backend.
    func retriable() -> [PendingApprovalAction] {
        allPending().filter { $0.attempts < Self.maxAttempts }
    }

    // MARK: - Private helpers

    private func readItems() -> [PendingApprovalAction] {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return []
        }
        return (try? JSONDecoder().decode([PendingApprovalAction].self, from: data)) ?? []
    }

    private func writeItems(_ items: [PendingApprovalAction]) {
        if items.isEmpty {
            userDefaults.removeObject(forKey: storageKey)
            return
        }
        if let data = try? JSONEncoder().encode(items) {
            userDefaults.set(data, forKey: storageKey)
        }
    }

    private func decisionKind(for decision: ApprovalDecision) -> PendingApprovalAction.DecisionKind {
        switch decision {
        case .approve: return .approve
        case .reject: return .reject
        case .edit: return .edit
        }
    }

    private func editBody(from decision: ApprovalDecision) -> String? {
        if case .edit(let body) = decision { return body }
        return nil
    }
}
