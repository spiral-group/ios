//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0066, step 6): a generated Interactive Post the
// owner has not published yet, as a timeline row.
//
// The agent wrote it into the owner's DM thread (notebook § 5.35). The row
// shows a live preview of the code, lets the owner read the source, and
// publishes it — packs, hashes, encrypts, uploads and sends `com.spiral.app`
// into the room the owner chose — from this client, as the owner.
//

import Foundation
import MatrixRustSDK

nonisolated struct InteractiveDraftRoomTimelineItem: EventBasedTimelineItemProtocol, Equatable {
    let id: TimelineItemIdentifier
    let body: String
    let timestamp: Date
    let isOutgoing: Bool
    let isEditable: Bool
    let canBeRepliedTo: Bool

    let sender: TimelineItemSender

    let draft: SpiralAppDraft

    var properties = RoomTimelineItemProperties()
}

/// What a draft carries, read from the event.
nonisolated struct SpiralAppDraft: Equatable {
    let title: String
    let aspect: String
    /// The manifest exactly as the agent serialised it. Packed as TEXT, so
    /// the digest this client computes is the one the agent computed.
    let manifestJSON: String
    let source: String
    /// The agent's digest of `pack(manifestJSON, source)`.
    let sha256: String
    let version: UInt32
    let generatedByAgentID: String?
    /// The room the post is FOR, when the thread's root said (the modal
    /// flow): publishing sends it there, not into the DM the draft sits in.
    let targetRoomID: String?

    init(_ content: InteractiveDraftContent) {
        title = content.title
        aspect = content.aspect
        manifestJSON = content.manifestJson
        source = content.source
        sha256 = content.sha256
        version = content.version
        generatedByAgentID = content.generatedByAgentId
        targetRoomID = content.targetRoomId
    }

    /// `aspect` as a ratio, for the row's frame.
    var displayAspectRatio: CGFloat {
        let parts = aspect.split(separator: ":")
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), w > 0, h > 0 else {
            return 4 / 3
        }
        return CGFloat(w / h)
    }

    /// The artifact this draft packs to, verified against the agent's
    /// digest. Nil when the two do not agree — which means this client and
    /// the agent pack differently, and the post must not be published
    /// under a digest the receiving clients would then reject.
    var artifact: SpiralAppArtifact? {
        guard let manifest = SpiralAppManifest(json: Data(manifestJSON.utf8)) else { return nil }
        let packed = SpiralAppContainer.pack(manifestJSON: manifestJSON, entry: manifest.entry, source: source)
        return SpiralAppArtifact.verified(packed: packed, claimedDigest: sha256)
    }

    /// The packed bytes, for upload.
    var packed: Data? {
        guard let manifest = SpiralAppManifest(json: Data(manifestJSON.utf8)) else { return nil }
        return SpiralAppContainer.pack(manifestJSON: manifestJSON, entry: manifest.entry, source: source)
    }
}
