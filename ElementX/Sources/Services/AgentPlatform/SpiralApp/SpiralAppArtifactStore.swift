//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 5.13): artifact bytes, fetched and
// verified before anything is allowed to run them.
//
// A post names its artifact by `sha256` and says where the bytes live. This
// turns that pair into a `SpiralAppArtifact`, or refuses. There is deliberately
// no third outcome: a caller cannot ask for the bytes without the check, and
// cannot get a partially trusted result.
//
// Content addressing does most of the work here. Two posts naming one digest
// are one artifact, so the cache is keyed by digest rather than by event, and
// a second post costs nothing. It also means a cache entry can never go stale:
// the key IS the content.
//

import Foundation
import MatrixRustSDK

enum SpiralAppArtifactStoreError: Error, Equatable {
    /// The bytes could not be fetched. The post may still be fine — the
    /// network, the media repository or the key was not.
    case unavailable
    /// Larger than any artifact has cause to be.
    case tooLarge(Int)
    /// The bytes arrived and are not this artifact — either they do not match
    /// the digest, or they match it and are not a container this build reads.
    ///
    /// One case rather than two because the caller does the same thing for
    /// both, and `SpiralAppArtifact.verified` already logs which it was. Kept
    /// apart from `unavailable` because these mean opposite things: one invites
    /// a retry, the other says this post will never run, however often it is
    /// asked.
    case refused
}

/// Fetches artifacts and verifies them against the digest the post claims.
actor SpiralAppArtifactStore {
    /// An artifact is one JSX module and a manifest; the runtime ships with the
    /// client, not in here. Twenty kilobytes is typical, so this is about a
    /// hundredfold headroom and still small enough that a mistake cannot be
    /// mistaken for a plausible app.
    ///
    /// Checked after the download, not before: the media API hands back the
    /// whole body and offers no length up front, so this bounds what gets
    /// parsed and cached rather than what gets transferred.
    static let maxArtifactBytes = 2 * 1024 * 1024

    /// How many verified artifacts to keep. Small on purpose — a timeline shows
    /// few distinct apps, and an unbounded cache keyed by a value an author
    /// controls is a way to be grown without limit.
    private static let maxCachedArtifacts = 16

    private let mediaLoader: MediaLoaderProtocol
    private var cache: [String: SpiralAppArtifact] = [:]
    private var insertionOrder: [String] = []
    /// One fetch per digest, however many callers ask at once. A room showing
    /// four posts of the same app must not fetch it four times.
    private var inFlight: [String: Task<SpiralAppArtifact, Error>] = [:]

    init(mediaLoader: MediaLoaderProtocol) {
        self.mediaLoader = mediaLoader
    }

    /// The artifact this post names, fetched and verified.
    func artifact(for post: SpiralAppPost) async -> Result<SpiralAppArtifact, SpiralAppArtifactStoreError> {
        let digest = post.digest.lowercased()

        if let cached = cache[digest] {
            return .success(cached)
        }

        let task: Task<SpiralAppArtifact, Error>
        if let existing = inFlight[digest] {
            task = existing
        } else {
            task = Task { [mediaLoader] in
                try await Self.fetchAndVerify(post: post, digest: digest, using: mediaLoader)
            }
            inFlight[digest] = task
        }

        defer { inFlight[digest] = nil }

        do {
            let artifact = try await task.value
            store(artifact, for: digest)
            return .success(artifact)
        } catch let error as SpiralAppArtifactStoreError {
            return .failure(error)
        } catch {
            return .failure(.unavailable)
        }
    }

    /// Whether this digest is already verified and in memory.
    ///
    /// Lets a caller decide to render immediately rather than showing a
    /// placeholder it will replace a frame later.
    func isReady(_ digest: String) -> Bool {
        cache.keys.contains(digest.lowercased())
    }

    private func store(_ artifact: SpiralAppArtifact, for digest: String) {
        guard !cache.keys.contains(digest) else { return }

        cache[digest] = artifact
        insertionOrder.append(digest)

        while insertionOrder.count > Self.maxCachedArtifacts {
            cache[insertionOrder.removeFirst()] = nil
        }
    }

    private static func fetchAndVerify(post: SpiralAppPost,
                                       digest: String,
                                       using mediaLoader: MediaLoaderProtocol) async throws -> SpiralAppArtifact {
        // One constructor for both shapes: `fromJson` reads `{"url"}` and
        // `{"file"}` alike, and `Source.mediaSourceJSON` is what puts the
        // encrypted one under `file` so the SDK decrypts it.
        guard let json = post.source.mediaSourceJSON else {
            throw SpiralAppArtifactStoreError.unavailable
        }
        let source = try MediaSource.fromJson(json: json)

        let packed: Data
        do {
            packed = try await mediaLoader.loadMediaContentForSource(.init(source: source,
                                                                           mimeType: "application/octet-stream"))
        } catch {
            MXLog.error("[SpiralApp] could not fetch \(digest): \(error)")
            throw SpiralAppArtifactStoreError.unavailable
        }

        guard packed.count <= maxArtifactBytes else {
            throw SpiralAppArtifactStoreError.tooLarge(packed.count)
        }

        // `verified` checks the digest before it parses anything, so unverified
        // bytes never reach the container reader.
        guard let artifact = SpiralAppArtifact.verified(packed: packed, claimedDigest: digest) else {
            throw SpiralAppArtifactStoreError.refused
        }

        return artifact
    }
}
