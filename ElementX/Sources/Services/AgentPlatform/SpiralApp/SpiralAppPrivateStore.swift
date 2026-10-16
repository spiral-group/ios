//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066 § 5.78): this phone's own corner of a post.
//
// Everything a post writes goes to the room, where every member's phone reads
// it — so a hidden move cannot live there. A sealed move puts its HASH in the
// room and keeps the move here: one small object per account and post, on
// this phone, sent nowhere, until the post opens it. `state.private.read` and
// `state.private.write` are the whole of it; neither reads anything about the
// room, so granting them widens nothing a post can learn (ADR-0007 § 4.8).
//

import CryptoKit
import Foundation

/// Where one session keeps its private object.
@MainActor
protocol SpiralAppPrivateCorner: AnyObject {
    /// What the post keeps here; empty when it has kept nothing.
    var state: [String: Any] { get }
    /// Replace it whole — the SDK always sends the entire object.
    func replace(with state: [String: Any])
}

/// Kept in memory: a preview's rehearsal must go nowhere, this included.
@MainActor
final class SpiralAppMemoryCorner: SpiralAppPrivateCorner {
    private(set) var state: [String: Any] = [:]

    func replace(with state: [String: Any]) {
        self.state = state
    }
}

/// Kept on this phone, for one account and one post.
@MainActor
final class SpiralAppStoredCorner: SpiralAppPrivateCorner {
    private let userID: String
    private let postID: String
    private let store: SpiralAppPrivateStore

    init(userID: String, postID: String, store: SpiralAppPrivateStore) {
        self.userID = userID
        self.postID = postID
        self.store = store
    }

    var state: [String: Any] {
        store.state(userID: userID, postID: postID)
    }

    func replace(with state: [String: Any]) {
        store.replace(userID: userID, postID: postID, with: state)
    }
}

/// The private objects of every post this phone has kept one for, a file per
/// account.
@MainActor
final class SpiralAppPrivateStore {
    static let shared = SpiralAppPrivateStore(directory: URL.applicationSupportDirectory
        .appending(path: "SpiralApp/Private", directoryHint: .isDirectory))

    /// The most a post may keep — the shell refuses more before it gets here.
    static let maxBytes = 8 * 1024
    /// Posts kept per account; the least recently written go first. A sealed
    /// game is long over by the time two hundred newer ones have been played.
    static let maxPosts = 200

    private let directory: URL
    /// Per account: post → (the order it was last written in, what). Read
    /// once, then kept.
    private var accounts: [String: [String: [String: Any]]] = [:]

    init(directory: URL) {
        self.directory = directory
    }

    func state(userID: String, postID: String) -> [String: Any] {
        posts(of: userID)[postID]?["state"] as? [String: Any] ?? [:]
    }

    func replace(userID: String, postID: String, with state: [String: Any]) {
        var posts = posts(of: userID)
        // A counter, not a clock: two writes in one millisecond still have an
        // order, and it carries on from the file across launches.
        let latest = posts.values.compactMap { $0["at"] as? Double }.max() ?? 0
        posts[postID] = ["state": state, "at": latest + 1]
        if posts.count > Self.maxPosts {
            let oldest = posts.sorted { ($0.value["at"] as? Double ?? 0) < ($1.value["at"] as? Double ?? 0) }
                .prefix(posts.count - Self.maxPosts)
            for (post, _) in oldest {
                posts.removeValue(forKey: post)
            }
        }
        accounts[userID] = posts

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: posts)
            try data.write(to: file(of: userID), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Kept in memory for this run; a seal made now can still be opened
            // until the app is quit.
            MXLog.error("[SpiralApp] could not keep a post's private state: \(error)")
        }
    }

    private func posts(of userID: String) -> [String: [String: Any]] {
        if let posts = accounts[userID] { return posts }
        let posts = (try? Data(contentsOf: file(of: userID)))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: [String: Any]] } ?? [:]
        accounts[userID] = posts
        return posts
    }

    /// Named by a hash, so the directory does not list who uses this phone.
    private func file(of userID: String) -> URL {
        let digest = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(digest).json")
    }
}
