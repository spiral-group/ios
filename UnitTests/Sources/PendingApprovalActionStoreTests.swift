//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM: Agent platform feature, not present upstream.
//
// Exercises the persistent retry-queue in isolation, using an
// in-memory UserDefaults so tests don't touch the real App
// Group container.

@testable import ElementX
import Foundation
import Testing

struct PendingApprovalActionStoreTests {
    // MARK: - Enqueue / read

    @Test
    func enqueueApproveAction_appearsInPending() {
        let store = makeStore()
        store.enqueue(approvalID: "appr-1", decision: .approve)
        let pending = store.allPending()
        #expect(pending.count == 1)
        #expect(pending.first?.approvalID == "appr-1")
        #expect(pending.first?.decisionKind == .approve)
        #expect(pending.first?.editBody == nil)
    }

    @Test
    func enqueueEditAction_preservesNewBody() {
        let store = makeStore()
        store.enqueue(approvalID: "appr-2", decision: .edit(newBody: "Revised draft"))
        let pending = store.allPending()
        #expect(pending.first?.decisionKind == .edit)
        #expect(pending.first?.editBody == "Revised draft")
        if case .edit(let body) = pending.first?.decision {
            #expect(body == "Revised draft")
        } else {
            Issue.record("Expected .edit decision, got \(String(describing: pending.first?.decision))")
        }
    }

    @Test
    func enqueueDuplicateApprovalID_replacesExistingEntry() {
        let store = makeStore()
        store.enqueue(approvalID: "appr-1", decision: .approve)
        store.enqueue(approvalID: "appr-1", decision: .reject)
        let pending = store.allPending()
        #expect(pending.count == 1)
        #expect(pending.first?.decisionKind == .reject)
    }

    // MARK: - Mark completed

    @Test
    func markCompletedRemovesEntry() {
        let store = makeStore()
        store.enqueue(approvalID: "appr-1", decision: .approve)
        store.enqueue(approvalID: "appr-2", decision: .reject)
        store.markCompleted(approvalID: "appr-1")

        let pending = store.allPending()
        #expect(pending.count == 1)
        #expect(pending.first?.approvalID == "appr-2")
    }

    @Test
    func markCompletedForUnknownID_isNoOp() {
        let store = makeStore()
        store.enqueue(approvalID: "appr-1", decision: .approve)
        store.markCompleted(approvalID: "nonexistent")
        #expect(store.allPending().count == 1)
    }

    // MARK: - Increment attempts

    @Test
    func incrementAttempt_bumpsCounterAndTimestamp() async throws {
        let store = makeStore()
        store.enqueue(approvalID: "appr-1", decision: .approve)
        let firstAttempt = try #require(store.allPending().first)
        #expect(firstAttempt.attempts == 1)

        // Sleep briefly so lastAttemptedAt actually differs.
        try await Task.sleep(for: .milliseconds(5))
        store.incrementAttempt(approvalID: "appr-1")
        let secondAttempt = try #require(store.allPending().first)
        #expect(secondAttempt.attempts == 2)
        #expect(secondAttempt.lastAttemptedAt > firstAttempt.lastAttemptedAt)
        #expect(secondAttempt.firstAttemptedAt == firstAttempt.firstAttemptedAt)
    }

    @Test
    func incrementAttemptForUnknownID_isNoOp() {
        let store = makeStore()
        store.incrementAttempt(approvalID: "ghost")
        #expect(store.allPending().isEmpty)
    }

    // MARK: - Retriable filter

    @Test
    func retriableExcludesEntriesAtMaxAttempts() {
        let store = makeStore()
        store.enqueue(approvalID: "appr-1", decision: .approve)
        for _ in 1..<PendingApprovalActionStore.maxAttempts {
            store.incrementAttempt(approvalID: "appr-1")
        }
        // Now at maxAttempts → not retriable.
        #expect(store.allPending().count == 1)
        #expect(store.retriable().isEmpty)
    }

    // MARK: - Persistence across reads

    @Test
    func writesAreObservableFromSecondStore() {
        // Two stores sharing the same UserDefaults — simulates
        // the NSE + main app reading the same persistence layer
        // (today only main app writes; this guards against a
        // future NSE-side change).
        let defaults = inMemoryDefaults()
        let writer = PendingApprovalActionStore(userDefaults: defaults)
        let reader = PendingApprovalActionStore(userDefaults: defaults)

        writer.enqueue(approvalID: "appr-1", decision: .approve)
        #expect(reader.allPending().count == 1)

        writer.markCompleted(approvalID: "appr-1")
        #expect(reader.allPending().isEmpty)
    }

    // MARK: - Helpers

    private func makeStore() -> PendingApprovalActionStore {
        PendingApprovalActionStore(userDefaults: inMemoryDefaults())
    }

    private func inMemoryDefaults() -> UserDefaults {
        // UserDefaults(suiteName:) with a unique name per test
        // gives us an isolated in-memory store with no on-disk
        // side effects on the simulator.
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
