//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). A Spiral push is answered once: with its
// words when naming ends in time, with the generic words when iOS ends the
// extension first — never with the raw payload's bare "Spiral", never twice.
//

@testable import Spiral
import Synchronization
import Testing
import UserNotifications

struct SpiralPushDeliveryTests {
    /// M2: a slow refresh outlasts the extension's time; the generic words show and the late naming is dropped.
    @Test
    func timeRunningOutDeliversTheGenericWords() async {
        let answers = Answers()
        let delivery = SpiralPushDelivery(generic: Self.content(body: "Someone commented on your post"), contentHandler: answers.record)
        let (naming, finishNaming) = AsyncStream.makeStream(of: Void.self)

        let pushTask = Task {
            for await _ in naming { }
            delivery.deliver(Self.content(body: "Olena: so true"))
        }
        delivery.expire()
        #expect(answers.bodies == ["Someone commented on your post"])

        finishNaming.finish()
        await pushTask.value
        #expect(answers.bodies == ["Someone commented on your post"], "the late naming is not a second answer")
    }

    @Test
    func aPushNamedInTimeIsAnsweredOnce() {
        let answers = Answers()
        let delivery = SpiralPushDelivery(generic: Self.content(body: "Someone commented on your post"), contentHandler: answers.record)

        delivery.deliver(Self.content(body: "Olena: so true"))
        delivery.expire()

        #expect(answers.bodies == ["Olena: so true"])
    }

    // MARK: - Helpers

    private static func content(body: String) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Spiral"
        content.body = body
        return content
    }

    /// What the push was answered with, in order.
    private final nonisolated class Answers: Sendable {
        private let received = Mutex<[String]>([])

        var bodies: [String] {
            received.withLock { $0 }
        }

        func record(_ content: UNNotificationContent) {
            received.withLock { $0.append(content.body) }
        }
    }
}
