//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0075 D7 amended and revised 2026-09-06):
// a covered speaker's raw microphone is attenuated on this device for as
// long as the plan names them — statically, from the agent's document,
// not per utterance from the lane's level. Nothing here touches
// subscriptions — the plan already keeps the microphone subscribed — and
// nothing reaches the server: LiveKit's per-track playout gain
// (`RemoteAudioTrack.volume`) is the whole mechanism.
//
// Two layers so the policy can be pinned without an audio engine:
// `NativeCallOriginalDuckingController` applies the order against an
// abstract `NativeCallDuckableMedia`; `LiveKitDuckableMedia` is the one
// LiveKit adapter.

import Foundation
import LiveKit

/// One remote audio publication as the controller sees it.
struct NativeCallRemoteAudio {
    let identity: String
    let sid: String
    let name: String
    /// nil until the track object exists (subscribed and started).
    let setVolume: ((Float) -> Void)?
    var source: NativeCallTransportTrack.Source = .microphone
}

/// What the controller needs from a room: every remote audio publication,
/// on demand. Kept tiny so a test can hand it a list.
@MainActor
protocol NativeCallDuckableMedia: AnyObject {
    func remoteAudio() -> [NativeCallRemoteAudio]
}

/// The room-side controller. Main-actor like the transport that owns it.
@MainActor
final class NativeCallOriginalDuckingController {
    private let media: NativeCallDuckableMedia
    private var order: NativeCallOriginalDucking = .none
    /// The last gain applied per microphone track SID, so a no-op is skipped
    /// and a released microphone is reset to unity exactly once. Cleared on
    /// unsubscribe on purpose: LiveKit reuses the receiver on a resubscribe
    /// (single-PC mode), so the underlying source can keep an old gain —
    /// the next `apply` must rewrite it.
    private var appliedGains: [String: Float] = [:]

    init(media: NativeCallDuckableMedia) {
        self.media = media
    }

    func setOrder(_ order: NativeCallOriginalDucking) {
        self.order = order
        apply()
    }

    /// Any remote audio landed or left: microphones get their gain.
    /// Idempotent — a duplicate callback changes nothing.
    func mediaDidChange(unsubscribedSID: String? = nil) {
        if let unsubscribedSID {
            appliedGains[unsubscribedSID] = nil
        }
        apply()
    }

    /// Walk every remote microphone and set the gain the order wants —
    /// unity for anyone it does not name, applied once.
    private func apply() {
        let publications = media.remoteAudio()
        let playableSIDs = Set(publications.filter { $0.setVolume != nil }.map(\.sid))
        appliedGains = appliedGains.filter { playableSIDs.contains($0.key) }

        let gains = order.gains
        for audio in publications where audio.source != .screenShareAudio && !NativeCallListening.isTranslationTrack(trackName: audio.name) {
            guard let setVolume = audio.setVolume else { continue }
            let gain = gains[audio.identity] ?? 1
            guard appliedGains[audio.sid] != gain else { continue }
            setVolume(gain)
            appliedGains[audio.sid] = gain
            MXLog.info("Original ducking: \(audio.identity) \(audio.name) gain \(gain)")
        }
    }
}

/// The LiveKit adapter: publications → `NativeCallRemoteAudio`.
@MainActor
final class LiveKitDuckableMedia: NativeCallDuckableMedia {
    private let room: Room

    init(room: Room) {
        self.room = room
    }

    func remoteAudio() -> [NativeCallRemoteAudio] {
        var result: [NativeCallRemoteAudio] = []
        for participant in room.remoteParticipants.values {
            guard let identity = participant.identity?.stringValue else { continue }
            for case let publication as RemoteTrackPublication in participant.trackPublications.values where publication.kind == .audio {
                let track = publication.track as? RemoteAudioTrack
                result.append(NativeCallRemoteAudio(identity: identity,
                                                    sid: publication.sid.stringValue,
                                                    name: publication.name,
                                                    setVolume: track.map { track in { track.volume = Double($0) } },
                                                    source: publication.source == .screenShareAudio ? .screenShareAudio : .microphone))
            }
        }
        return result
    }
}
