//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import Foundation
import LiveKit
import SwiftUI

// AGENT-PLATFORM (Brief 0063): the only file that touches LiveKit for calls.
// Owns the room, its tracks and the E2EE key provider, and projects them into
// the app-owned `NativeCallTransportProtocol` snapshot.

@MainActor
final class LiveKitCallTransport: NSObject, NativeCallTransportProtocol {
    private let room: Room
    private let keyProvider: BaseKeyProvider?
    /// The ring slot our senders encrypt with. `Room.connect` builds a fresh
    /// `E2EEManager` every time, so the slot is re-applied after each connect
    /// rather than trusted to survive one.
    private var senderKeyIndex: Int32 = 0
    /// Brief 0066 — the quiet original under a translation this device hears.
    private lazy var ducking = NativeCallOriginalDuckingController(media: LiveKitDuckableMedia(room: room))

    private let eventsSubject = PassthroughSubject<NativeCallTransportEvent, Never>()
    var events: AnyPublisher<NativeCallTransportEvent, Never> {
        eventsSubject.eraseToAnyPublisher()
    }

    /// Every delegate callback reaches `eventsSubject` through here, so the
    /// session reads them in the order LiveKit raised them.
    private nonisolated let delivery = MainActorSerialDelivery()

    private nonisolated func send(_ event: NativeCallTransportEvent) {
        send { _ in event }
    }

    /// For callbacks that can only name their event by reading the room,
    /// which is main actor state — the read stays on the delivery hop, where
    /// it always happened. Returning `nil` drops the callback.
    private nonisolated func send(_ resolveEvent: @escaping @MainActor @Sendable (LiveKitCallTransport) -> NativeCallTransportEvent?) {
        delivery.enqueue { [weak self] in
            guard let self, let event = resolveEvent(self) else { return }
            ducking.mediaDidChange()
            eventsSubject.send(event)
        }
    }

    var localIdentity: String? {
        room.localParticipant.identity?.stringValue
    }

    var isLocalSpeaking: Bool {
        room.localParticipant.isSpeaking
    }

    var localConnectionQuality: NativeCallConnectionQuality {
        Self.quality(room.localParticipant.connectionQuality)
    }

    private static func quality(_ quality: ConnectionQuality) -> NativeCallConnectionQuality {
        switch quality {
        case .excellent: .excellent
        case .good: .good
        case .poor: .poor
        case .lost: .lost
        case .unknown: .unknown
        }
    }

    var isMicrophoneEnabled: Bool {
        room.localParticipant.isMicrophoneEnabled()
    }

    var isCameraEnabled: Bool {
        room.localParticipant.isCameraEnabled()
    }

    /// The capturer behind our own camera publication, if it is running.
    private var cameraCapturer: CameraCapturer? {
        room.localParticipant.firstCameraPublication?.track
            .flatMap { ($0 as? LocalVideoTrack)?.capturer as? CameraCapturer }
    }

    var remoteParticipants: [NativeCallTransportParticipant] {
        room.remoteParticipants.values.compactMap { participant in
            guard let identity = participant.identity?.stringValue else { return nil }
            return NativeCallTransportParticipant(identity: identity,
                                                  isSpeaking: participant.isSpeaking,
                                                  isAudioEnabled: participant.isMicrophoneEnabled(),
                                                  isAgent: participant.kind == .agent,
                                                  isCameraEnabled: participant.isCameraEnabled(),
                                                  isOnHold: heldIdentities.contains(identity),
                                                  connectionQuality: Self.quality(participant.connectionQuality),
                                                  attributes: participant.attributes)
        }
    }

    // MARK: - Hold (Brief 0068 Slice 1)

    /// Peers that announced a hold and have not announced a resume.
    private var heldIdentities: Set<String> = []
    /// Our own announced state, re-sent to late joiners.
    private var isAnnouncedHeld = false
    nonisolated static let holdTopic = "spiral.hold"

    func announceHold(_ held: Bool) async {
        isAnnouncedHeld = held
        await sendHoldMessage(held)
    }

    private func sendHoldMessage(_ held: Bool) async {
        guard let data = try? JSONEncoder().encode(HoldMessage(held: held)) else { return }
        do {
            try await room.localParticipant.publish(data: data,
                                                    options: DataPublishOptions(topic: Self.holdTopic, reliable: true))
        } catch {
            // The muted microphone underneath still tells the peer something;
            // the label is the courtesy that did not land.
            MXLog.warning("Could not announce hold=\(held): \(error)")
        }
    }

    nonisolated struct HoldMessage: Codable {
        let held: Bool
    }

    /// 720p front camera. Deliberately NOT the SDK default in one respect:
    /// see `videoPublishOptions`.
    private static let cameraCaptureOptions = CameraCaptureOptions(position: .front,
                                                                   dimensions: .h720_169,
                                                                   fps: 30)

    /// Brief 0068 Slice 3: Low Power Mode asks for less of everything; the
    /// camera is the biggest single draw a call has. 540p/24 keeps a
    /// talking head legible at roughly half the encode cost. Read at each
    /// camera start — a call that began on battery saver and left it gets
    /// full quality the next time the camera comes on.
    private static var currentCameraCaptureOptions: CameraCaptureOptions {
        guard ProcessInfo.processInfo.isLowPowerModeEnabled else { return cameraCaptureOptions }
        return CameraCaptureOptions(position: .front, dimensions: .h540_169, fps: 24)
    }

    /// Simulcast is ON: the sender publishes layered encodings so a grid
    /// subscriber can take the medium layer instead of 7×720p downlink
    /// (`setSubscriptions` asks per publication). `adaptiveStream` stays OFF
    /// on the room — this client drives every subscription itself from the
    /// derived plan, because media may only play for an authorized identity.
    ///
    /// `degradationPreference` is chosen, not left to WebRTC's default: on a
    /// congested uplink a talking head should lose RESOLUTION and keep
    /// MOTION — a soft face that moves reads as a call, a sharp face at
    /// 7 fps reads as broken.
    ///
    /// H264 over the negotiated default (VP8) for the hardware encoder:
    /// VideoToolbox runs 720p30×3-layer simulcast at a fraction of the CPU
    /// of software VP8, which is thermal headroom — and thermal throttling
    /// is a quality degradation no bitrate knob can buy back. Safe with
    /// E2EE (the frame cryptor is codec-aware inside libwebrtc) and does
    /// not touch the voice agent, which subscribes to no video at all.
    private static let videoPublishOptions = VideoPublishOptions(simulcast: true,
                                                                 preferredCodec: .h264,
                                                                 degradationPreference: .maintainFramerate)

    init(encryptMedia: Bool) {
        if encryptMedia {
            // These values are the interoperability contract with Element Call
            // and the voice agent: HKDF over a per-participant ring of 256
            // keys, salted with LiveKit's default frame-encryption salt.
            let options = KeyProviderOptions(sharedKey: false,
                                             ratchetSalt: Data(defaultRatchetSalt.utf8),
                                             ratchetWindowSize: 10,
                                             failureTolerance: -1,
                                             keyRingSize: 256,
                                             keyDerivationAlgorithm: .hkdf)
            keyProvider = BaseKeyProvider(options: options)
        } else {
            keyProvider = nil
        }

        // `dynacast` is ON while `adaptiveStream` stays OFF — they answer
        // different questions. Dynacast lets the SFU pause simulcast LAYERS
        // no subscriber currently wants, sparing the sender's uplink and
        // battery exactly on the networks the quality complaint came from;
        // it never adds a subscription, so the authorization gate (manual
        // subscriptions from the derived plan) is untouched.
        let roomOptions = RoomOptions(defaultCameraCaptureOptions: Self.cameraCaptureOptions,
                                      defaultVideoPublishOptions: Self.videoPublishOptions,
                                      defaultAudioPublishOptions: AudioPublishOptions(name: "microphone"),
                                      adaptiveStream: false,
                                      dynacast: true,
                                      e2eeOptions: keyProvider.map { E2EEOptions(keyProvider: $0) })
        room = Room(roomOptions: roomOptions)

        super.init()

        room.add(delegate: self)
    }

    func connect(url: String, token: String) async throws {
        // A fresh connection knows nothing about who is held; the honest
        // fallback until a peer announces again is their muted glyph.
        heldIdentities.removeAll()
        do {
            // Subscriptions are membership/key gated by the session; automatic
            // subscription would play media from unauthorized identities.
            try await room.connect(url: url,
                                   token: token,
                                   connectOptions: .init(autoSubscribe: false))
        } catch {
            throw NativeCallTransportError.connectionFailed(String(describing: error))
        }
        // The manager this connect created starts every sender on index 0;
        // a key rotated before (or during) a reconnect lives elsewhere.
        room.e2eeManager?.setSenderKeyIndex(senderKeyIndex)
    }

    func disconnect() async {
        await room.disconnect()
    }

    func setMicrophone(enabled: Bool) async throws {
        do {
            try await room.localParticipant.setMicrophone(enabled: enabled)
        } catch {
            throw NativeCallTransportError.microphoneUnavailable(String(describing: error))
        }
    }

    /// Publishing the camera is a MUTE/UNMUTE of the same publication once
    /// it exists, so toggling never renegotiates and never disturbs audio.
    func setCamera(enabled: Bool) async throws {
        do {
            try await room.localParticipant.setCamera(enabled: enabled,
                                                      captureOptions: Self.currentCameraCaptureOptions,
                                                      publishOptions: Self.videoPublishOptions)
        } catch {
            throw NativeCallTransportError.cameraUnavailable(String(describing: error))
        }
    }

    func switchCamera() async throws {
        guard let cameraCapturer else {
            throw NativeCallTransportError.cameraUnavailable("the camera is not capturing")
        }
        do {
            _ = try await cameraCapturer.switchCameraPosition()
        } catch {
            throw NativeCallTransportError.cameraUnavailable(String(describing: error))
        }
    }

    func setEncryptionKey(_ key: Data, index: Int32, identity: String) {
        guard let keyProvider else {
            MXLog.warning("Received a media key for an unencrypted transport, ignoring it")
            return
        }
        keyProvider.setKey(keyData: key, participantId: identity, index: index)
    }

    func setSenderKeyIndex(_ index: Int32) {
        senderKeyIndex = index
        room.e2eeManager?.setSenderKeyIndex(index)
    }

    var remoteTracks: [NativeCallTransportTrack] {
        var tracks = [NativeCallTransportTrack]()
        for participant in room.remoteParticipants.values {
            guard let identity = participant.identity?.stringValue else { continue }
            for case let publication as RemoteTrackPublication in participant.trackPublications.values {
                guard let track = transportTrack(identity: identity, publication: publication) else { continue }
                tracks.append(track)
            }
        }
        return tracks
    }

    /// Which simulcast layer to ask for, by how many videos are on screen.
    ///
    /// This replaced a two-position switch (1 video high, everything else
    /// medium) that blanketed a 3-way call's half-screen tiles — and a
    /// group's full-bleed stage — with 640×360 upscaled to fill, which is
    /// exactly the softness the operator reported. Two tiles still cover
    /// most of the screen each: they deserve the top layer. Past four, the
    /// tiles are small enough that the low layer both looks right and stops
    /// the downlink growing linearly with the roster.
    nonisolated static func preferredVideoQuality(subscribedVideoCount: Int) -> VideoQuality {
        switch subscribedVideoCount {
        case ..<3: .high
        case 3...4: .medium
        default: .low
        }
    }

    func setSubscriptions(authorizedIdentities: Set<String>,
                          isTrackExcluded: @escaping @Sendable (NativeCallTransportTrack) -> Bool) async -> Bool {
        var allApplied = true
        // With simulcast published, a grid of tiles has no use for every
        // sender's full 720p layer — ask for the medium one as soon as
        // more than one camera is on screen. The full-bleed 1:1 stage is
        // the single-video case and keeps the high layer.
        //
        // Counted from the VIDEO publications this plan actually subscribes,
        // not from authorized identities (audit C7): an audio-only agent is
        // an authorized identity with no camera, and counting it dropped the
        // flagship 1:1-plus-agent video call's full-bleed stage to the
        // medium layer on every call.
        var subscribedVideoCount = 0
        for participant in room.remoteParticipants.values {
            guard let identity = participant.identity?.stringValue,
                  authorizedIdentities.contains(identity) else { continue }
            for case let publication as RemoteTrackPublication in participant.trackPublications.values {
                guard let track = transportTrack(identity: identity, publication: publication),
                      track.kind == .video, !isTrackExcluded(track) else { continue }
                subscribedVideoCount += 1
            }
        }
        let preferredQuality = Self.preferredVideoQuality(subscribedVideoCount: subscribedVideoCount)

        for participant in room.remoteParticipants.values {
            guard let identity = participant.identity?.stringValue else { continue }
            let identityAuthorized = authorizedIdentities.contains(identity)

            for case let publication as RemoteTrackPublication in participant.trackPublications.values {
                guard let track = transportTrack(identity: identity, publication: publication) else { continue }
                let shouldSubscribe = identityAuthorized && !isTrackExcluded(track)
                do {
                    try await publication.set(subscribed: shouldSubscribe)
                } catch {
                    // The plan is only "applied" when the transport really
                    // did it — a swallowed failed unsubscribe kept playing
                    // media the policy had revoked.
                    allApplied = false
                    MXLog.error("Failed updating media subscription for \(identity): \(error)")
                    continue
                }

                if shouldSubscribe, track.kind == .video {
                    do {
                        try await publication.set(videoQuality: preferredQuality)
                    } catch {
                        // Separate from the subscription above because it
                        // fails for a different, EXPECTED reason: the SDK
                        // refuses a quality preference until the subscription
                        // has actually landed, which is routinely a beat after
                        // we asked for it. Reporting that at ERROR made a
                        // normal race look like a policy failure in the logs
                        // (seen on a device while switching cameras). The plan
                        // still counts as unapplied so the caller's retry
                        // carries the preference — without it a grid stays on
                        // the high layer for every sender.
                        allApplied = false
                        MXLog.info("Video quality preference not applied yet for \(identity): \(error)")
                    }
                }
            }
        }
        return allApplied
    }

    func setOriginalDucking(_ ducking: NativeCallOriginalDucking) {
        self.ducking.setOrder(ducking)
    }

    private func transportTrack(identity: String,
                                publication: RemoteTrackPublication) -> NativeCallTransportTrack? {
        let kind: NativeCallTransportTrack.Kind? = switch publication.kind {
        case .audio: .audio
        case .video: .video
        default: nil
        }
        guard let kind else { return nil }

        let source: NativeCallTransportTrack.Source = switch publication.source {
        case .microphone: .microphone
        case .camera: .camera
        case .screenShareAudio: .screenShareAudio
        case .screenShareVideo: .screenShareVideo
        default: .unknown
        }

        return .init(identity: identity,
                     name: publication.name,
                     isSubscribed: publication.isSubscribed,
                     kind: kind,
                     trackID: publication.sid.stringValue,
                     source: source,
                     isMuted: publication.isMuted,
                     isStreamPaused: publication.streamState == .paused)
    }
}

// MARK: - NativeCallVideoRendering

extension LiveKitCallTransport: NativeCallVideoRendering {
    /// The only place in the app that turns a descriptor into pixels.
    ///
    /// `SwiftUIVideoView` takes a LiveKit `VideoTrack`, which is why the
    /// resolution happens here and not in the view: the view asks for a
    /// descriptor it derived, and gets back an opaque `AnyView`.
    func videoView(for source: NativeCallVideoSource) -> AnyView? {
        guard let track = videoTrack(for: source) else { return nil }
        // `.fill` matches how every messenger renders a call tile, and the
        // mirror mode is left on `.auto` so the front camera mirrors and the
        // back camera does not — which is what users expect from a preview.
        let layoutMode: VideoView.LayoutMode = source.source == .screenShareVideo ? .fit : .fill
        return AnyView(SwiftUIVideoView(track, layoutMode: layoutMode, mirrorMode: .auto))
    }

    func canRenderPictureInPictureVideo(for source: NativeCallVideoSource) -> Bool {
        videoTrack(for: source) != nil
    }

    func pictureInPictureVideoView(for source: NativeCallVideoSource) -> UIView? {
        guard let track = videoTrack(for: source) else { return nil }

        let videoView = VideoView()
        // The whole point of this path: Metal stops rendering in the
        // background, a sample-buffer layer does not.
        videoView.renderMode = .sampleBuffer
        videoView.layoutMode = source.source == .screenShareVideo ? .fit : .fill
        videoView.mirrorMode = .auto
        videoView.track = track
        return videoView
    }

    func tearDownPictureInPictureVideoView(_ view: UIView) {
        // Reassigning the track is the SDK's only deregistration path —
        // `VideoView` has no deinit and the underlying RTC track would keep
        // a dead adapter in its fan-out list otherwise.
        (view as? VideoView)?.track = nil
    }

    private func videoTrack(for source: NativeCallVideoSource) -> VideoTrack? {
        if source.isLocal {
            return room.localParticipant.firstCameraVideoTrack
        }
        guard let participant = room.remoteParticipants.values.first(where: {
            $0.identity?.stringValue == source.identity
        }) else {
            return nil
        }
        // Match the publication the descriptor names; falling back to "any
        // camera" would render the wrong stream after a republish.
        let publication = participant.trackPublications.values.first { publication in
            publication.sid.stringValue == source.trackID
        }
        return publication?.track as? VideoTrack
    }
}

// MARK: - NativeCallVoiceLevelReading

extension LiveKitCallTransport: NativeCallVoiceLevelReading {
    /// The LiveKit server refreshes `audioLevel` with its active-speaker
    /// updates, and the runtime squelches between-utterance silence on the
    /// translation tracks — so this envelope is audible speech, the same
    /// signal the EC fork's dock samples.
    func voiceLevel(forUserID userID: String) -> Double {
        // Our OWN voice lives on the local participant: searching only the
        // remotes left every self-facing wave (the roster row, the bar)
        // permanently flat.
        if matches(participant: room.localParticipant, userID: userID) {
            return level(of: room.localParticipant)
        }
        guard let participant = room.remoteParticipants.values.first(where: {
            matches(participant: $0, userID: userID)
        }) else {
            return 0
        }
        return level(of: participant)
    }

    var loudestVoiceLevel: Double {
        let remotes = room.remoteParticipants.values.map { level(of: $0) }
        return ([level(of: room.localParticipant)] + remotes).max() ?? 0
    }

    /// The identity carries a device suffix (`@bob:host:DEVICE`); a caller
    /// naming the user must still match.
    private func matches(participant: Participant, userID: String) -> Bool {
        let identity = participant.identity?.stringValue ?? ""
        return identity == userID || identity.hasPrefix("\(userID):")
    }

    private func level(of participant: Participant) -> Double {
        guard participant.isSpeaking else { return 0 }
        return Double(min(1, max(0, participant.audioLevel)))
    }
}

// MARK: - RoomDelegate

extension LiveKitCallTransport: RoomDelegate {
    nonisolated func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        send(.didDisconnect(error: error.map { String(describing: $0) }))
    }

    nonisolated func roomIsReconnecting(_ room: Room) {
        send(.isReconnecting)
    }

    nonisolated func roomDidReconnect(_ room: Room) {
        send { transport in
            // Data packets sent while we were reconnecting were dropped on
            // our side (LiveKit only delivers them when connected), so what
            // we knew about holds is stale — fail open to the muted glyph —
            // and nobody re-announced to us, so we re-announce ourselves.
            transport.heldIdentities.removeAll()
            if transport.isAnnouncedHeld {
                Task { await transport.sendHoldMessage(true) }
            }
            return .didReconnect
        }
    }

    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        send { transport in
            // A late joiner never saw our hold announcement.
            if transport.isAnnouncedHeld {
                Task { await transport.sendHoldMessage(true) }
            }
            return .participantDidConnect
        }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        let identity = participant.identity?.stringValue
        send { transport in
            if let identity {
                transport.heldIdentities.remove(identity)
            }
            return .participantDidDisconnect
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant?, didReceiveData data: Data, forTopic topic: String, encryptionType: EncryptionType) {
        // The sender is whoever LiveKit says it is — the payload names
        // nobody, so a peer can only mark itself. Agents never hold.
        guard topic == Self.holdTopic, let participant, participant.kind != .agent,
              let identity = participant.identity?.stringValue else { return }
        guard let message = try? JSONDecoder().decode(HoldMessage.self, from: data) else { return }
        send { transport in
            if message.held {
                transport.heldIdentities.insert(identity)
            } else {
                transport.heldIdentities.remove(identity)
            }
            return .participantsUpdated
        }
    }

    nonisolated func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        send(.participantsUpdated)
    }

    nonisolated func room(_ room: Room, participant: Participant, trackPublication: TrackPublication, didUpdateIsMuted isMuted: Bool) {
        // Mute is its OWN event: no track is published or unpublished and
        // nobody starts speaking, so without this hook a remote mute only
        // surfaced when some unrelated event happened to re-read the
        // snapshot — the operator saw their own mic toggle "fix" the
        // other device's stale state.
        send(.participantsUpdated)
    }

    nonisolated func room(_ room: Room, participant: Participant, didUpdateAttributes attributes: [String: String]) {
        // The agent's live state document (`spiral.agent.state`) changes
        // on every applied reconfigure — the derivation re-reads it from
        // the participant snapshot.
        send(.participantsUpdated)
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didPublishTrack publication: RemoteTrackPublication) {
        send(.participantsUpdated)
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        send { transport in
            transport.ducking.mediaDidChange()
            return .didSubscribeToTrack(identity: participant.identity?.stringValue ?? "unknown")
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        send { transport in
            transport.ducking.mediaDidChange(unsubscribedSID: publication.sid.stringValue)
            return .participantsUpdated
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didUnpublishTrack publication: RemoteTrackPublication) {
        // A withdrawn publication is how a translation lane ends; the
        // derivation must re-read the snapshot or the listening surfaces
        // keep offering a language nobody produces any more.
        send(.participantsUpdated)
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didFailToSubscribeTrackWithSid trackSid: Track.Sid, error: LiveKitError) {
        // A failed subscription is a track we believe we are hearing and
        // are not — a lane that never landed must not keep ducking the
        // original (fail audible: the derivation re-reads the snapshot).
        MXLog.error("Failed subscribing to track \(trackSid) from \(participant.identity?.stringValue ?? "unknown"): \(error)")
        send(.participantsUpdated)
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, trackPublication: RemoteTrackPublication, didUpdateStreamState streamState: StreamState) {
        // G10 — the SFU pausing a congested video stream is a state the
        // screen narrates ("Video paused"), not a silent freeze.
        send(.participantsUpdated)
    }

    nonisolated func room(_ room: Room, participant: Participant, didUpdateConnectionQuality quality: ConnectionQuality) {
        // G10 — quality changes re-derive the "Poor connection" line.
        send(.participantsUpdated)
    }

    nonisolated func room(_ room: Room, trackPublication: TrackPublication, didUpdateE2EEState state: E2EEState) {
        // Frame-decryption truth: this is where an inaudible-but-connected
        // participant explains itself (missingKey, decryptionFailed, ...).
        MXLog.info("E2EE state for track \(trackPublication.sid) (\(trackPublication.kind)): \(state)")
        let isHealthy = switch state {
        case .ok, .key_ratcheted, .new: true
        default: false
        }
        let sid = trackPublication.sid
        send { transport in
            // The publication does not expose its owner — resolve the
            // identity through the roster instead.
            guard let identity = transport.room.remoteParticipants.values.first(where: { participant in
                participant.trackPublications.keys.contains(sid)
            })?.identity?.stringValue else { return nil }
            return .encryptionHealthChanged(identity: identity, isHealthy: isHealthy)
        }
    }
}

// MARK: - Ordered delivery

/// Runs work on the main actor in the order it was offered, one item at a
/// time.
///
/// LiveKit raises every room callback on one serial delegate queue, and
/// `NativeCallSession` reads the resulting events as a sequence: a
/// `didReconnect` is only honoured while the call is already `reconnecting`,
/// so one that overtook its `isReconnecting` would be dropped by the guard
/// and leave a working call to die on the reconnect timeout. An unstructured
/// `Task { @MainActor in }` per callback only preserves that order for as
/// long as the main actor's executor happens to run independent jobs in
/// submission order, which nothing in the language promises.
///
/// This is the mechanism behind `SDKListener.onMainActor`, which the sibling
/// `MatrixRTCSessionProxy` uses for the same reason. That primitive cannot be
/// reused as-is: its input is a private closure reachable only through the
/// Rust SDK's listener protocol conformances, none of which LiveKit adopts.
final nonisolated class MainActorSerialDelivery: Sendable {
    private let continuation: AsyncStream<@MainActor @Sendable () -> Void>.Continuation

    init() {
        // Unbounded by default: a burst has to queue up, never be dropped.
        let (stream, continuation) = AsyncStream<@MainActor @Sendable () -> Void>.makeStream()
        self.continuation = continuation

        Task { @MainActor in
            for await work in stream {
                work()
            }
        }
    }

    /// Queues `work`. Delivery order is the order these calls return in.
    func enqueue(_ work: @escaping @MainActor @Sendable () -> Void) {
        continuation.yield(work)
    }

    deinit {
        // Ends the consumer task above. Releasing the continuation alone does
        // not finish the stream (SE-0406), which would leak that task.
        continuation.finish()
    }
}
