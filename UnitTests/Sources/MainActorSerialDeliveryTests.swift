//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import Foundation
@testable import Spiral
import Testing

// AGENT-PLATFORM (Brief 0063): `LiveKitCallTransport` funnels every LiveKit
// room callback through `MainActorSerialDelivery`, so these pin the funnel —
// which is where the ordering lives. Driving the transport itself would need
// LiveKit declared as a dependency of this target, and most of its callbacks
// carry a `RemoteParticipant`/`RemoteTrackPublication`/`Track.Sid`, none of
// which have a public initialiser to build one from.

/// `NativeCallSession` reads these events as a sequence: it only promotes a
/// call that is already `reconnecting` back to `connected`. A `didReconnect`
/// that overtook its `isReconnecting` is dropped by that guard and the call
/// then dies on the 30s reconnect timeout, so order is the contract.
struct MainActorSerialDeliveryTests {
    /// LiveKit raises every room callback on one serial queue off the main
    /// actor, so everything offered there has to reach the subject in that
    /// same order, with nothing dropped.
    @Test
    func aBurstOfferedOffTheMainActorArrivesInOrder() async throws {
        let count = 500
        let delivery = MainActorSerialDelivery()
        let sink = EventSink()

        var received = [Int]()
        let deferred = deferFulfillment(sink.subject) { value in
            received.append(value)
            return received.count == count
        }

        offerBurstOffTheMainActor(count: count, to: delivery) { sink.subject.send($0) }

        try await deferred.fulfill()
        #expect(received == Array(0..<count))
    }

    /// Delivery stays a hop, as it was when each callback spawned its own
    /// task: a callback must never re-enter the session's state machine
    /// while LiveKit is still inside the delegate call that raised it.
    @Test
    func nothingIsDeliveredBeforeTheOfferingCallReturns() async throws {
        let delivery = MainActorSerialDelivery()
        let sink = EventSink()

        var received = [Int]()
        let deferred = deferFulfillment(sink.subject) { value in
            received.append(value)
            return received.count == 2
        }

        delivery.enqueue { sink.subject.send(0) }
        delivery.enqueue { sink.subject.send(1) }
        #expect(received.isEmpty)

        try await deferred.fulfill()
        #expect(received == [0, 1])
    }
}

/// Stands in for the transport: a main actor object owning the subject the
/// session subscribes to.
private final class EventSink {
    let subject = PassthroughSubject<Int, Never>()
}

/// Offers `count` values from a single serial queue — `MulticastDelegate`'s
/// shape — and holds the main actor until they are all queued, so the whole
/// burst piles up before the consumer can drain any of it.
private func offerBurstOffTheMainActor(count: Int,
                                       to delivery: MainActorSerialDelivery,
                                       work: @escaping @MainActor @Sendable (Int) -> Void) {
    let queue = DispatchQueue(label: "LiveKitSDK.Multicast.RoomDelegate")
    let queued = DispatchSemaphore(value: 0)

    queue.async {
        for index in 0..<count {
            delivery.enqueue { work(index) }
        }
        queued.signal()
    }

    #expect(queued.wait(timeout: .now() + .seconds(5)) == .success)
}
