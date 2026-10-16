//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063 Slice 5): the video render boundary.
//
// Everything above `NativeCallTransportProtocol` is deliberately free of
// LiveKit — the roster, the derivation and the view state are `Hashable`
// value types that can be built in a test without an SFU. A renderable
// video track is the one thing that cannot be expressed that way: it is a
// live object owned by the media engine.
//
// So the app passes a DESCRIPTOR (this file), and exactly one view resolves
// it into a renderer at the very edge of the view tree. The derivation keeps
// deciding WHAT should be on screen; only the leaf knows HOW to draw it.

import Foundation
import SwiftUI

/// Identifies one renderable video stream.
///
/// Deliberately not the track itself: a descriptor is `Equatable`, so the
/// view state can diff it, and a test can assert which tile should show
/// video without a media engine.
nonisolated struct NativeCallVideoSource: Equatable {
    /// The publishing peer's SFU identity; the local camera uses the
    /// transport's own identity.
    let identity: String
    /// The publication this descriptor points at. Empty for the local
    /// camera, which the transport resolves through its own participant.
    let trackID: String
    let isLocal: Bool
    /// Camera video fills a person tile; a shared screen preserves its
    /// aspect ratio so document edges are never cropped away.
    var source: NativeCallTransportTrack.Source = .camera
}

/// Who fills the 1:1 stage and who floats in the corner.
///
/// The stage belongs to whoever HAS a picture: while the peer has none —
/// they have not answered yet, or their camera is off — our own camera is
/// the stage, the way every phone shows an outgoing video call. Before
/// this, a peer with no video took the stage and filled it with a
/// camera-off placeholder while our live picture sat in the corner
/// (found on a device, 2026-08-21). The manual swap still wins, and the
/// small tile is always the OTHER tile — never a second copy of the
/// large one.
nonisolated enum NativeCallVideoStage {
    static func tiles(remote: NativeCallVideoTile?,
                      local: NativeCallVideoTile?,
                      isSelfVideoLarge: Bool) -> (large: NativeCallVideoTile?, small: NativeCallVideoTile?) {
        let remoteHasVideo = remote?.source != nil
        let selfLeads = isSelfVideoLarge || !remoteHasVideo

        guard selfLeads, let local else {
            return (remote ?? local, remote == nil ? nil : local)
        }
        return (local, remote)
    }
}

/// Resolves a descriptor into something the media engine can draw into.
///
/// Implemented by the transport (which owns the LiveKit room) and consumed
/// by a single leaf view. Kept separate from `NativeCallTransportProtocol`
/// so the session — which never renders anything — does not gain a
/// dependency on the renderer.
@MainActor
protocol NativeCallVideoRendering: AnyObject {
    /// A view rendering `source`, or nil when the track is gone (the peer
    /// muted their camera, or the subscription has not landed yet). Callers
    /// render a placeholder for nil rather than an empty rectangle.
    func videoView(for source: NativeCallVideoSource) -> AnyView?

    /// Whether `source` resolves to a live track right now — the cheap probe
    /// behind Picture in Picture's placeholder-upgrade check, so asking does
    /// not build a renderer.
    func canRenderPictureInPictureVideo(for source: NativeCallVideoSource) -> Bool

    /// A UIKit view rendering `source` through a sample-buffer layer, for
    /// Picture in Picture.
    ///
    /// Separate from `videoView(for:)` for one reason that is not style:
    /// the Metal renderer behind the normal path stops producing frames
    /// once the app leaves the foreground — which is exactly when PiP
    /// exists. `AVSampleBufferDisplayLayer` keeps drawing, and system PiP
    /// requires a plain `UIView` tree anyway.
    func pictureInPictureVideoView(for source: NativeCallVideoSource) -> UIView?

    /// Releases the renderer registration behind a view built by
    /// `pictureInPictureVideoView(for:)`. Without this the track keeps
    /// fanning frames out to a dead adapter for its whole life — the SDK
    /// only deregisters when the view's track is reassigned, never on
    /// deallocation.
    func tearDownPictureInPictureVideoView(_ view: UIView)
}

/// The agent slot's live amplitude — the server-reported voice level the
/// wave dances to while a translation airs.
///
/// Deliberately a SYNCHRONOUS getter, not a stream, and read at display
/// rate by the leaf view only: the Element Call fork learned that a
/// periodic publisher inside the view-model graph turns every test into a
/// timer (`src/spiral/voiceLevel.ts`), and a level sample invalidates no
/// state — it is amplitude, not an event.
@MainActor
protocol NativeCallVoiceLevelReading: AnyObject {
    /// The voice level 0...1 of the participant whose identity belongs to
    /// `userID` (`userID` or `userID:device`); 0 while they are not
    /// speaking, so the wave settles between utterances.
    func voiceLevel(forUserID userID: String) -> Double
    /// The loudest voice in the call right now — what the minimized bar
    /// shows, where there is no single participant to name.
    var loudestVoiceLevel: Double { get }
}
