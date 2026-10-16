//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import Foundation

// AGENT-PLATFORM (Brief 0063): app-owned view of the SFU media transport.
// `NativeCallSession` owns the call lifecycle; nothing above this protocol
// imports LiveKit.

enum NativeCallTransportError: Error {
    case connectionFailed(String)
    case microphoneUnavailable(String)
    case cameraUnavailable(String)
}

/// A remote peer as currently seen by the media transport.
nonisolated struct NativeCallTransportParticipant: Hashable {
    /// The identity this peer uses on the SFU — the same opaque value
    /// MatrixRTC memberships carry.
    let identity: String
    let isSpeaking: Bool
    let isAudioEnabled: Bool
    /// LiveKit's server-assigned participant kind. This reaches the client
    /// before MatrixRTC membership and participant attributes can settle.
    var isAgent = false
    /// Whether this peer currently publishes an unmuted camera. LiveKit
    /// MUTES a camera publication rather than unpublishing it, so this is
    /// the only honest source for "their video is on".
    var isCameraEnabled = false
    /// Brief 0068 Slice 1: this peer told the room it put the call on hold
    /// (`spiral.hold` data message). Their microphone is muted underneath
    /// as the fallback signal; this is what lets the screen say "On hold"
    /// rather than "muted".
    var isOnHold = false
    /// Brief 0068 Slice 3: the SFU's view of this peer's link. `.lost` is
    /// what the screen renders as "Reconnecting…" on their row and tile —
    /// the reason a picture went dark or a voice cut out, which used to
    /// read as nothing at all.
    var connectionQuality: NativeCallConnectionQuality = .unknown
    /// LiveKit participant attributes — an agent publishes its live state
    /// document here (`spiral.agent.state`, ADR-0071 D8), pushed to every
    /// device on change.
    var attributes: [String: String] = [:]
}

/// A remote track publication as currently seen by the transport.
///
/// Audio routing (Brief 0063 Slice 4) works on NAMES — `lt:<language>:<mxid>`
/// is a translation — and on SUBSCRIPTION liveness: a speaker's raw mic is
/// hidden only while their translation is actually flowing.
///
/// `kind` exists because those name rules are about AUDIO. Without it a
/// camera publication (LiveKit names it `camera`) reads as "a raw
/// microphone", so a translated speaker's video would be unsubscribed
/// together with their voice.
nonisolated struct NativeCallTransportTrack: Hashable {
    nonisolated enum Kind: Hashable {
        case audio
        case video
    }

    nonisolated enum Source: Hashable {
        case unknown
        case microphone
        case camera
        case screenShareAudio
        case screenShareVideo
    }

    /// The publishing peer's SFU identity.
    let identity: String
    /// The publication name; empty for an unnamed (plain microphone) track.
    let name: String
    let isSubscribed: Bool
    /// Defaults to audio so the Slice 4 fixtures keep reading as they did.
    var kind: Kind = .audio
    /// Stable publication SID. It changes when a track is republished even
    /// if its human-readable name does not.
    var trackID = ""
    /// The capture source, kept separate from media kind so screen-share
    /// audio is never treated as a microphone and screen video as a camera.
    var source: Source = .unknown
    /// Publication mute state. A subscribed but muted translation lane is not
    /// live and must restore the speaker's original microphone.
    var isMuted = false
    /// G10 — the SFU paused this stream to save the channel (congestion).
    /// The sound stays; the picture self-restores. Only meaningful for
    /// video.
    var isStreamPaused = false
}

/// The transport's live link-quality verdict for our own uplink — the
/// meta line's signal bars (`03`/`04`/`06`) render the whole ladder,
/// G10's "Poor connection" note reads its low end.
nonisolated enum NativeCallConnectionQuality: Equatable {
    case unknown
    case excellent
    case good
    case poor
    case lost

    var isPoor: Bool {
        self == .poor || self == .lost
    }

    /// How many of the meta line's three bars are filled.
    var filledBars: Int {
        switch self {
        case .excellent: 3
        case .good: 2
        case .poor: 1
        case .lost, .unknown: 0
        }
    }
}

enum NativeCallTransportEvent {
    /// The transport dropped for good. `nil` means an orderly server-side
    /// disconnect rather than a failure.
    case didDisconnect(error: String?)
    case isReconnecting
    case didReconnect
    case participantDidConnect
    case participantDidDisconnect
    /// Track publications, subscriptions or speaking activity changed.
    case participantsUpdated
    /// A remote media track became audible/visible to us.
    case didSubscribeToTrack(identity: String)
    /// Frame-crypto health for one participant's media changed: false when
    /// frames stopped decrypting (missing/failed key), true when they
    /// decrypt again. Presentation-only — the media stays subscribed so a
    /// late key can heal it without a resubscribe round-trip.
    case encryptionHealthChanged(identity: String, isHealthy: Bool)
}

// sourcery: AutoMockable
@MainActor
protocol NativeCallTransportProtocol: AnyObject {
    var events: AnyPublisher<NativeCallTransportEvent, Never> { get }

    /// The identity the transport assigned us once connected.
    var localIdentity: String? { get }
    var isLocalSpeaking: Bool { get }
    /// G10 — OUR uplink/downlink quality is degraded (the server's own
    /// assessment). The screen narrates it; silence during degradation
    /// reads as a broken call.
    var localConnectionQuality: NativeCallConnectionQuality { get }
    var isMicrophoneEnabled: Bool { get }
    /// Whether our own camera is publishing. Read from the engine, never
    /// from the last request — a refused `setCamera` must not leave the UI
    /// claiming the camera is on.
    var isCameraEnabled: Bool { get }
    var remoteParticipants: [NativeCallTransportParticipant] { get }
    /// Every remote publication, subscribed or not, audio and video: the
    /// listening picker derives the produced-language union from the audio
    /// ones, the subscription policy derives liveness, and the video tiles
    /// derive what there is to render.
    var remoteTracks: [NativeCallTransportTrack] { get }

    func connect(url: String, token: String) async throws
    func disconnect() async

    func setMicrophone(enabled: Bool) async throws

    /// Publish or mute the camera. Never leaves the session and never
    /// touches audio.
    func setCamera(enabled: Bool) async throws

    /// Flip between the front and back capture device.
    func switchCamera() async throws

    /// Install a participant's media key at the given ring index. Raw key
    /// material — re-encoding it produces silent decryption failures.
    func setEncryptionKey(_ key: Data, index: Int32, identity: String)

    /// Move the local senders to the ring index our current key sits at.
    /// Frames carry their index, so a rotation that announces the new key
    /// under a NEW index leaves the old one decryptable until the switch —
    /// receivers never guess which key slot 0 means. Call it after the key
    /// itself is installed; the index survives reconnects.
    func setSenderKeyIndex(_ index: Int32)

    /// Subscribe to exactly the given identities' media and unsubscribe from
    /// everyone else's. The veto decides individual tracks of an authorized
    /// identity — the self-translation exclusion (a speaker must never
    /// subscribe to `lt:<language>:<speaker>` carrying their own voice), the
    /// Slice 4 listening policy and the video visibility policy all live in
    /// it. The full publication snapshot is passed because those policies
    /// differ by kind and source, and a republish is identified by SID.
    ///
    /// Returns whether EVERY publication reached the requested state. A
    /// false makes the caller retry — a failed unsubscribe of unauthorized
    /// media recorded as "applied" would keep playing it (fail-closed
    /// requires the retry, not the log line).
    func setSubscriptions(authorizedIdentities: Set<String>,
                          isTrackExcluded: @escaping @Sendable (NativeCallTransportTrack) -> Bool) async -> Bool

    /// Brief 0066 — the listener's ducking order: which raw microphones
    /// play at the quiet gain, for as long as the order stands. The
    /// transport owns the per-track playout gain; the plan says who.
    /// Idempotent: a microphone that subscribes later gets its gain then.
    func setOriginalDucking(_ ducking: NativeCallOriginalDucking)

    /// Brief 0068 Slice 1: tell every peer we are on hold (or back). Sent
    /// as a reliable data message on the `spiral.hold` topic — the client
    /// JWT carries no `CanUpdateOwnMetadata`, so participant attributes are
    /// not an option here. Re-sent to late joiners while held.
    func announceHold(_ held: Bool) async
}
