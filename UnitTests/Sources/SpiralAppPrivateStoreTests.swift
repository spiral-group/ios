//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066 § 5.78): the phone's own corner of a post keeps a
// sealed move until the post opens it — across launches, for one account and
// one post, and nothing bigger than a move needs.
//

import Foundation
@testable import Spiral
import Testing

@MainActor
struct SpiralAppPrivateStoreTests {
    private static func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "spiral-private-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test
    func whatAPostKeepsSurvivesTheApp() {
        let directory = Self.directory()
        SpiralAppPrivateStore(directory: directory)
            .replace(userID: "@a:x", postID: "$p", with: ["sealed": ["r1": ["v": "rock", "s": "ab"]]])

        let reopened = SpiralAppPrivateStore(directory: directory).state(userID: "@a:x", postID: "$p")
        let round = (reopened["sealed"] as? [String: Any])?["r1"] as? [String: Any]
        #expect(round?["v"] as? String == "rock")
    }

    @Test
    func anotherAccountOrAnotherPostSeesNothing() {
        let store = SpiralAppPrivateStore(directory: Self.directory())
        store.replace(userID: "@a:x", postID: "$p", with: ["k": 1])

        #expect(store.state(userID: "@b:x", postID: "$p").isEmpty)
        #expect(store.state(userID: "@a:x", postID: "$q").isEmpty)
    }

    @Test
    func theLeastRecentlyWrittenPostGoesFirst() {
        let store = SpiralAppPrivateStore(directory: Self.directory())
        for index in 0...SpiralAppPrivateStore.maxPosts {
            store.replace(userID: "@a:x", postID: "$\(index)", with: ["i": index])
        }

        #expect(store.state(userID: "@a:x", postID: "$0").isEmpty)
        #expect(store.state(userID: "@a:x", postID: "$1")["i"] as? Int == 1)
        #expect(store.state(userID: "@a:x", postID: "$\(SpiralAppPrivateStore.maxPosts)")["i"] as? Int == SpiralAppPrivateStore.maxPosts)
    }

    @Test
    func theBridgeKeepsAPostsPrivateObjectAndGivesItBack() async {
        let session = SpiralAppPreviewSession(userID: "@a:x", members: [:])

        let write = await session.answer(method: "state.private.write",
                                         args: Data(#"{"state":{"sealed":{"r1":{"v":"rock","s":"ab"}}}}"#.utf8),
                                         activation: SpiralAppActivation())
        #expect(write.contains(#""ok":true"#))

        let read = await session.answer(method: "state.private.read", args: Data("null".utf8), activation: SpiralAppActivation())
        #expect(read.contains("rock"))
    }

    @Test
    func theBridgeRefusesAnythingButASmallObject() async {
        let session = SpiralAppPreviewSession(userID: "@a:x", members: [:])

        let list = await session.answer(method: "state.private.write", args: Data(#"{"state":[1,2]}"#.utf8), activation: SpiralAppActivation())
        #expect(list.contains("rejected"))

        let big = String(repeating: "x", count: SpiralAppPrivateStore.maxBytes)
        let tooBig = await session.answer(method: "state.private.write", args: Data(#"{"state":{"x":"\#(big)"}}"#.utf8),
                                          activation: SpiralAppActivation())
        #expect(tooBig.contains("rejected"))
    }
}
