//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 157): the SDK reports an undecryptable event from
// one of its own threads, and `actionsPublisher` delivers it on the main
// actor, where its subscribers' closures are isolated.
//

import Combine
import Foundation
import MatrixRustSDK
@testable import Spiral
import Synchronization
import Testing

/// Whether each action arrived on the main thread. Written from whichever
/// thread delivered it.
private nonisolated final class DeliveryThreads: Sendable {
    private let values = Mutex<[Bool]>([])

    var all: [Bool] {
        values.withLock { $0 }
    }

    func record(isMainThread: Bool) {
        values.withLock { $0.append(isMainThread) }
    }
}

@MainActor
struct ClientProxyDecryptionErrorTests {
    let actionsSubject = PassthroughSubject<ClientProxyAction, Never>()
    let info = UnableToDecryptInfo(eventId: "$event",
                                   timeToDecryptMs: nil,
                                   cause: .unknown,
                                   eventLocalAgeMillis: 0,
                                   userTrustsOwnIdentity: true,
                                   senderHomeserver: "spiral.md",
                                   ownHomeserver: "spiral.md")

    /// The way the SDK calls the delegate: synchronously, off the main thread.
    private func reportFromAnSDKThread() async {
        let delegate = ClientProxy.makeDecryptionErrorDelegate(actionsSubject: actionsSubject)
        let wasMainThread = await Task.detached { [info] in
            Self.report(info, to: delegate)
        }.value
        #expect(!wasMainThread)
    }
    
    /// Returns whether it ran on the main thread.
    private nonisolated static func report(_ info: UnableToDecryptInfo, to delegate: UnableToDecryptDelegate) -> Bool {
        delegate.onUtd(info: info)
        return Thread.isMainThread
    }

    /// A `@Sendable` subscriber is not isolated, so it can record the thread
    /// without the trap the next test is about.
    @Test
    func aReportFromAnSDKThreadArrivesOnTheMainThread() async throws {
        let threads = DeliveryThreads()
        let cancellable = actionsSubject.sink { @Sendable _ in
            threads.record(isMainThread: Thread.isMainThread)
        }
        defer { cancellable.cancel() }
        let delivered = deferFulfillment(actionsSubject) { action in
            if case .receivedDecryptionError = action { true } else { false }
        }

        await reportFromAnSDKThread()

        try await delivered.fulfill()
        #expect(threads.all == [true])
    }

    /// The shape that crashed the app (`OwnerBlocksSync`'s auth error filter):
    /// a closure formed on the main actor checks its isolation when it runs,
    /// and an action delivered off the main thread traps there.
    @Test
    func aMainActorSubscriberSeesTheReport() async throws {
        let decryptionErrors = actionsSubject.filter { action in
            if case .receivedDecryptionError = action { true } else { false }
        }
        let delivered = deferFulfillment(decryptionErrors) { _ in true }

        await reportFromAnSDKThread()

        guard case .receivedDecryptionError(let received) = try await delivered.fulfill() else {
            Issue.record("Expected the decryption error")
            return
        }
        #expect(received == info)
    }
}
