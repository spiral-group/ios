//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 5.13): does the store refuse what it
// should refuse, and fetch no more than once?
//
// The interesting assertions here are about the two things a content-addressed
// fetch buys: nothing unverified escapes, and one digest is one download
// however many posts name it. Both are properties a caller cannot check for
// itself, which is why they live behind the store rather than at each call.
//

import CryptoKit
import Foundation
import MatrixRustSDK
@testable import Spiral
import SpiralAppTestArtifacts
import Testing

struct SpiralAppArtifactStoreTests {
    // MARK: - Nothing unverified escapes

    #if DEBUG
    @Test
    func aTruthfulPostYieldsItsArtifact() async throws {
        let packed = try #require(SpiralAppTestArtifacts.conformance)
        let loader = Self.loader(returning: packed.bytes)
        let store = SpiralAppArtifactStore(mediaLoader: loader)

        let result = await store.artifact(for: Self.post(digest: packed.digest))

        let artifact = try #require(try? result.get())
        #expect(artifact.manifest.appID == "conformance")
        #expect(artifact.digest == packed.digest)
    }

    @Test
    func bytesThatDoNotMatchTheClaimedDigestAreRefused() async throws {
        let packed = try #require(SpiralAppTestArtifacts.conformance)
        // The bytes are a real, valid artifact — they are simply not the one
        // this post claims. That is the case the digest exists to catch: a
        // media repository serving something else entirely.
        let store = SpiralAppArtifactStore(mediaLoader: Self.loader(returning: packed.bytes))

        let result = await store.artifact(for: Self.post(digest: String(repeating: "a", count: 64)))

        #expect(result.failure == .refused)
    }

    @Test
    func aMatchingDigestOverSomethingThatIsNotAContainerIsRefused() async {
        // Honest bytes, honestly hashed, and still not runnable. Verifying the
        // digest is not the same as knowing what arrived.
        let notAContainer = Data("this is not SPIRALv1".utf8)
        let digest = SHA256.hash(data: notAContainer).map { String(format: "%02x", $0) }.joined()
        let store = SpiralAppArtifactStore(mediaLoader: Self.loader(returning: notAContainer))

        let result = await store.artifact(for: Self.post(digest: digest))

        #expect(result.failure == .refused)
    }

    @Test
    func anArtifactLargerThanTheCapIsRefusedBeforeItIsParsed() async {
        let huge = Data(count: SpiralAppArtifactStore.maxArtifactBytes + 1)
        let digest = SHA256.hash(data: huge).map { String(format: "%02x", $0) }.joined()
        let store = SpiralAppArtifactStore(mediaLoader: Self.loader(returning: huge))

        let result = await store.artifact(for: Self.post(digest: digest))

        #expect(result.failure == .tooLarge(huge.count))
    }

    @Test
    func aFetchThatFailsIsUnavailableRatherThanRefused() async throws {
        // The distinction is the whole point of having two cases: this post may
        // be perfectly good and the network merely down, so a caller may retry.
        let packed = try #require(SpiralAppTestArtifacts.conformance)
        let loader = MediaLoaderMock()
        loader.loadMediaContentForSourceThrowableError = MediaLoaderError.unexpectedResponse
        let store = SpiralAppArtifactStore(mediaLoader: loader)

        let result = await store.artifact(for: Self.post(digest: packed.digest))

        #expect(result.failure == .unavailable)
    }

    // MARK: - One digest, one download

    @Test
    func aSecondAskForTheSameDigestDoesNotFetchAgain() async throws {
        let packed = try #require(SpiralAppTestArtifacts.conformance)
        let loader = Self.loader(returning: packed.bytes)
        let store = SpiralAppArtifactStore(mediaLoader: loader)
        let post = Self.post(digest: packed.digest)

        _ = await store.artifact(for: post)
        _ = await store.artifact(for: post)

        #expect(loader.loadMediaContentForSourceCallsCount == 1)
    }

    @Test
    func postsAskingAtTheSameMomentShareOneFetch() async throws {
        // A room showing four posts of one app must not fetch it four times.
        // Without coalescing this passes the cache test above and still makes
        // four requests, because none of them has finished to populate it.
        let packed = try #require(SpiralAppTestArtifacts.conformance)
        let loader = Self.loader(returning: packed.bytes, delay: .milliseconds(120))
        let store = SpiralAppArtifactStore(mediaLoader: loader)
        let post = Self.post(digest: packed.digest)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask { _ = await store.artifact(for: post) }
            }
        }

        #expect(loader.loadMediaContentForSourceCallsCount == 1)
    }

    @Test
    func readinessIsFalseUntilSomethingIsVerified() async throws {
        let packed = try #require(SpiralAppTestArtifacts.conformance)
        let store = SpiralAppArtifactStore(mediaLoader: Self.loader(returning: packed.bytes))

        #expect(await store.isReady(packed.digest) == false)
        _ = await store.artifact(for: Self.post(digest: packed.digest))
        #expect(await store.isReady(packed.digest) == true)
    }

    @Test
    func aRefusedArtifactIsNotRemembered() async throws {
        // Caching a failure would turn one bad response into a permanent one.
        let packed = try #require(SpiralAppTestArtifacts.conformance)
        let store = SpiralAppArtifactStore(mediaLoader: Self.loader(returning: packed.bytes))
        let liar = Self.post(digest: String(repeating: "b", count: 64))

        _ = await store.artifact(for: liar)

        #expect(await store.isReady(liar.digest) == false)
    }
    #endif

    // MARK: - Helpers

    private static func loader(returning bytes: Data, delay: Duration? = nil) -> MediaLoaderMock {
        let loader = MediaLoaderMock()
        loader.loadMediaContentForSourceClosure = { _ in
            if let delay { try? await Task.sleep(for: delay) }
            return bytes
        }
        return loader
    }

    private static func post(digest: String) -> SpiralAppPost {
        SpiralAppPost(InteractivePostContent(body: "Conformance",
                                             appId: "conformance",
                                             runtime: "1",
                                             title: "Conformance",
                                             aspect: "4:3",
                                             stateChannel: "default",
                                             sha256: digest,
                                             url: "mxc://spiral.md/abcdef",
                                             fileJson: nil))
    }
}

private extension Result {
    var failure: Failure? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
