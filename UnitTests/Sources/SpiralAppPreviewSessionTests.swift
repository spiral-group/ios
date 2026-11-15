//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 4.8): a preview must behave like a
// post and publish like nothing.
//
// The owner publishes, so an artifact runs before it is a post. The whole value
// of that is rehearsal: if a preview were more forgiving than a post, an author
// would learn nothing from it, and the first person to find the difference
// would be someone in the room.
//

import Foundation
@testable import Spiral
import Testing

@MainActor
struct SpiralAppPreviewSessionTests {
    // MARK: - It behaves like a post

    @Test
    func anOperationChangesTheStateItReads() async {
        let session = Self.session()

        _ = await session.apply(.increment(path: ["count"], by: 1), summary: nil)
        _ = await session.apply(.increment(path: ["count"], by: 2), summary: nil)

        #expect(session.snapshot.state == .object(["count": .number(3)]))
    }

    @Test
    func everyWriteAdvancesTheSequence() async {
        let session = Self.session()

        #expect(session.snapshot.seq == 0)
        _ = await session.apply(.set(path: ["a"], value: .string("x")), summary: nil)
        #expect(session.snapshot.seq == 1)
    }

    @Test
    func itIsReadyImmediately() {
        // A post can be `loading` while its actions are read. A preview has no
        // history to be incomplete about, and an app that had to wait for one
        // would be waiting for ever.
        #expect(Self.session().snapshot.readiness == .ready)
    }

    @Test
    func itMeetsTheSameBudgetAPostWould() async {
        // The point of the preview. An app that only grows bricks its post once
        // published; the author should hit that wall on their own screen, while
        // they can still change the app.
        let session = Self.session()
        let big = String(repeating: "x", count: SpiralAppPostSession.maxStateBytes + 1)

        let result = await session.apply(.set(path: ["blob"], value: .string(big)), summary: nil)

        guard case .failure(let error) = result else {
            Issue.record("a preview accepted a state no post could carry")
            return
        }
        #expect(error.bridgeCode == SpiralAppPostError.stateTooLarge.bridgeCode)
    }

    @Test
    func arefusedWriteLeavesTheStateAlone() async {
        let session = Self.session()
        _ = await session.apply(.set(path: ["keep"], value: .string("me")), summary: nil)

        let big = String(repeating: "x", count: SpiralAppPostSession.maxStateBytes + 1)
        _ = await session.apply(.set(path: ["blob"], value: .string(big)), summary: nil)

        #expect(session.snapshot.state == .object(["keep": .string("me")]))
        #expect(session.snapshot.seq == 1, "a refused write was counted")
    }

    // MARK: - It publishes like nothing

    @Test
    func itSaysPlainlyThatItIsNotAPost() {
        // An app is not asked to care, but anything that persists against this
        // instance id would be writing against a post that does not exist.
        let context = Self.session().context

        #expect(context["instanceId"] as? String == "preview")
        #expect(context["isPreview"] as? Bool == true)
    }

    @Test
    func itAnswersTheSameBridgeCallsAPostDoes() async {
        // One implementation serves both, so an app cannot tell which it is
        // running in — which is what makes the rehearsal worth anything.
        let session = Self.session()
        let touched = SpiralAppActivation.touched()

        let written = await session.answer(method: SpiralAppCapability.stateSharedWrite.rawValue,
                                           args: Data(#"{"op":{"incr":{"path":["n"],"by":4}}}"#.utf8),
                                           activation: touched)
        let read = await session.answer(method: SpiralAppCapability.stateSharedRead.rawValue, args: Data(), activation: touched)

        #expect(written.contains("\"ok\""))
        #expect(read.contains("\"n\""))
    }

    @Test
    func aCapabilityItWasNotGrantedIsRefused() async {
        let refused = await Self.session().answer(method: "chat.messages.read", args: Data(), activation: .touched())

        #expect(refused.contains("rejected"))
    }

    // MARK: - Helpers

    private static func session() -> SpiralAppPreviewSession {
        SpiralAppPreviewSession(userID: "@author:spiral.md",
                                members: ["members": [], "count": 1])
    }
}
