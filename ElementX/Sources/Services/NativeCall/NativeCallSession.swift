//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import AVFoundation
import Combine
import Foundation
import UIKit

// AGENT-PLATFORM (Brief 0063): the single owner of a native call.
//
// It composes the MatrixRTC protocol session (membership, SFU authorization,
// media keys) with the LiveKit media transport, and leaves the audio session
// itself to CallKit: the media engine is only allowed to run inside a CallKit
// activation window.

enum NativeCallSessionState: Equatable {
    case connecting
    /// Outgoing only: the room has been notified and we are waiting for a
    /// remote participant to join.
    case ringing
    case connected
    /// G10 — a system audio interruption (a GSM call) took the session; the
    /// call resumes when it ends. Info, never critical — nothing is broken.
    case onHold
    case reconnecting
    case ended(reason: NativeCallEndReason)
}

extension NativeCallSessionState {
    /// Whether a hold means anything from this state.
    ///
    /// `.connected` is the obvious one. `.connecting` and `.reconnecting`
    /// are the ones that were missing and that matter more: both are about
    /// to take an audio route, so an interruption there is the difference
    /// between a call that resumes and a call that reports itself live with
    /// no audio (audit A5-5).
    ///
    /// Terminal states are excluded — holding something already ended is
    /// meaningless — and `.onHold` is excluded because holding twice would
    /// overwrite the state we are meant to restore.
    ///
    /// `.ringing` is excluded deliberately rather than by oversight. It is
    /// an outgoing call waiting for a remote to join, so it can transition
    /// to `.connected` on its own at any moment; restoring a remembered
    /// `.ringing` after an interruption could then undo a join that landed
    /// while we were held. Getting that right needs the two transitions to
    /// be ordered against each other, which is more than this repair is
    /// for.
    var canBeHeld: Bool {
        switch self {
        case .connecting, .connected, .reconnecting:
            true
        default:
            false
        }
    }
}

enum NativeCallEndReason: Equatable {
    case userHungUp
    case remoteEnded
    case declined
    case unanswered
    /// Phase 4 — every other human left a group call. An agent alone does
    /// not hold a conference open (`18 · Call states`).
    case everyoneLeft
    /// The transport dropped and could not re-establish itself in time.
    case connectionLost
    case failed(NativeCallFailure)

    /// The tone confirming how the call finished, matching what phone users
    /// expect: an end beep for a conversation, a busy cue for a refusal.
    var endTone: NativeCallTone? {
        switch self {
        case .userHungUp, .remoteEnded, .connectionLost, .everyoneLeft: .ended
        case .declined, .unanswered: .busy
        case .failed: nil
        }
    }
}

/// Why a call could not be placed or carried on — named, so the alert that
/// reports it is localised like every other call surface (the messages
/// used to be English literals on the reason).
enum NativeCallFailure: Equatable {
    case couldNotJoin
    case serverUnreachable
    case couldNotConnect
    case audioReset
    case disconnected

    var localizedDescription: String {
        switch self {
        case .couldNotJoin: UntranslatedL10n.screenNativeCallFailureJoin
        case .serverUnreachable: UntranslatedL10n.screenNativeCallFailureServer
        case .couldNotConnect: UntranslatedL10n.screenNativeCallFailureConnect
        case .audioReset: UntranslatedL10n.screenNativeCallFailureAudioReset
        case .disconnected: UntranslatedL10n.screenNativeCallFailureDisconnected
        }
    }
}

@MainActor
protocol NativeCallSessionDelegate: AnyObject {
    func nativeCallSession(_ session: NativeCallSession, didChangeState state: NativeCallSessionState)
    func nativeCallSession(_ session: NativeCallSession, didChangeParticipants participants: [NativeCallParticipant])
    /// The join rang the room; declines for this notification mean the callee
    /// refused the call.
    func nativeCallSession(_ session: NativeCallSession, didSendRingNotification eventID: String)
    /// The produced-translation union or the user's listening choice
    /// changed (Brief 0063 Slice 4) — the picker re-renders.
    func nativeCallSession(_ session: NativeCallSession, didChangeListening listening: NativeCallListeningState)
    /// Slice 5 — who is on screen and which stream belongs to them.
    func nativeCallSession(_ session: NativeCallSession, didChangeVideoTiles tiles: [NativeCallVideoTile])
    /// An agent attached, left, or the runtime applied a reconfigure — the
    /// Agent Center's REST snapshot is stale (ADR-0071 D8).
    func nativeCallSessionDidChangeAgentState(_ session: NativeCallSession)
    /// Phase 1 — the agents' claims and live signals changed (see
    /// `NativeCallAgentClaims`): the block's wave is `claimed ∧ speaking`
    /// (the `SpiralAgentDock` rule), the paused set is Phase 4's gap, and
    /// the recording set is the call-wide REC truth the owner-scoped REST
    /// list cannot provide.
    func nativeCallSession(_ session: NativeCallSession, didChangeAgentClaims claims: NativeCallAgentClaims)
    /// Camera video is live for at least one participant.
    func nativeCallSession(_ session: NativeCallSession, didChangeActiveVideo hasActiveVideo: Bool, isSpeakerEnabled: Bool)
    /// The transport's link-quality verdict changed — the meta line's
    /// signal bars render the ladder, G10's note reads its low end.
    func nativeCallSession(_ session: NativeCallSession, didChangeConnectionQuality quality: NativeCallConnectionQuality)
    /// A video call's camera could not start at connect time and the call
    /// went on as audio (audit T3). The screen owes the user that sentence —
    /// silence here meant "asked for video, got audio, no explanation" — and
    /// the camera button remains the retry. Default no-op: only the call
    /// screen has a face to say it with.
    func nativeCallSessionDidDowngradeToAudio(_ session: NativeCallSession)
}

extension NativeCallSessionDelegate {
    func nativeCallSessionDidDowngradeToAudio(_ session: NativeCallSession) { }
}

/// What the listening switch renders: the languages the call's agents
/// currently produce (named, never picked) and the resolved channel.
/// Client-only, never persisted, never sent to the backend.
nonisolated struct NativeCallListeningState: Equatable {
    var producedLanguages: [String] = []
    /// The RESOLVED channel (choice × whether anything is produced) — what
    /// the ears actually get. The header renders it, not the raw choice.
    var channel: NativeCallListeningChannel = .everything
    /// Speakers this device hears in translation — covered by a live
    /// Live-style agent's document (Brief 0066 rev. 2) — with the language.
    /// Their raw microphones are quiet on this device for as long as they
    /// are in here, and their roster rows say "Covered in X" so the eyes
    /// agree with the ears. Empty in the `original` channel.
    var translatedSpeakers: [String: String] = [:]
    /// Covered speakers on the air with no lane of theirs airing, though
    /// one aired here before: their original is back at unity (fail
    /// audible). Always ⊆ translated.
    var falteredSpeakers: Set<String> = []
    /// The agents (by MXID) whose lane that is — their block, and only
    /// theirs, says the translation faltered.
    var falteredAgents: Set<String> = []
}

/// A participant as rendered by the call UI.
nonisolated struct NativeCallParticipant: Identifiable, Hashable {
    /// Agents are derived into the roster so presence, subscriptions and the
    /// agent block can all read one list — but they are NEVER rendered among
    /// the humans (plan §5.1). The screen filters on this role; disclosure is
    /// the header count, the agent block and the Agent Center.
    enum Role: Hashable {
        case human
        case agent
    }

    /// Where this participant's media stands, derived from the one native
    /// snapshot: MatrixRTC membership first, LiveKit transport and media keys
    /// layered on top.
    enum MediaState: Hashable {
        /// An active MatrixRTC membership exists but their transport has not
        /// reached the SFU yet.
        case connecting
        /// The transport is up but this room is encrypted and their media key
        /// has not arrived, so nothing they send can be decrypted yet.
        case waitingForKeys
        case connected
    }

    let id: String
    let userID: String
    let role: Role
    let mediaState: MediaState
    let isSpeaking: Bool
    let isAudioEnabled: Bool
    let isLocal: Bool
    /// B4: a Live agent covers this speaker — their raw voice is quiet under
    /// the translation on this device — and the row shows a translate marker
    /// so the eyes agree with the ears. Always false for agents and the
    /// local user.
    var isTranslated = false
    /// Slice 5: an unmuted camera publication exists for this participant.
    /// A camera is muted rather than unpublished while it is off, so this
    /// is what decides whether a tile renders video or an avatar.
    var isVideoEnabled = false
    /// Brief 0068 Slice 1: the peer announced a hold (or, for the local
    /// participant, we did). Never speaking, never counted as live video
    /// while this is true; the row and the tile say "On hold" instead of
    /// "muted".
    var isOnHold = false
    /// Brief 0068 Slice 3: the SFU lost this peer's link (every device of
    /// theirs). Their row and tile say "Reconnecting…" — the reason their
    /// picture went dark or their voice cut out.
    var isReconnecting = false
}

@MainActor
final class NativeCallSession: NSObject {
    private let rtcSession: MatrixRTCSessionProtocol
    /// Read by the screen for the connecting detail line ("Setting up
    /// encryption" only when there is encryption to set up).
    let isRoomEncrypted: Bool
    /// Whether the join notifies the room: the flow's call, except that a
    /// join whose room's call is only this device's own membership starts a
    /// fresh call instead (`start()`).
    private var notifyRoom: Bool
    /// Answering a ring, not joining a call already running in the room.
    /// Both join without notifying; only a group join may then wait alone
    /// for others (operator question 94).
    private let isAnswer: Bool
    private let configuration: NativeCallConfiguration
    /// ALL inputs the derived state depends on — mutated ONLY through
    /// `updateInputs`, which re-derives everything on every change.
    private var inputs = NativeCallDerivationInputs()
    /// The last applied subscription plan; a derivation that produces the
    /// same plan skips the transport round-trip.
    /// The plan the transport has actually accepted.
    private var appliedSubscriptionPlan: NativeCallSubscriptionPlan?
    /// The newest plan the derivation produced; the worker converges on it.
    private var desiredSubscriptionPlan: NativeCallSubscriptionPlan?
    /// Matches the `m.rtc.notification` lifetime so the caller stops ringing
    /// when the callee's ring does.
    private let unansweredRingDuration: Duration
    /// How long a dropped transport may try to come back before the call is
    /// declared lost, the way phone calls give up rather than hang forever.
    private let reconnectTimeoutDuration: Duration
    /// How long the MatrixRTC join gets. It publishes a membership state event
    /// and, when it rings, a notification event too — a homeserver round trip
    /// each, the same one the leave below makes, with room for the SDK's own
    /// retry on a slow network. Past this the callee's ring has aged out of
    /// usefulness and the caller has been staring at "connecting" for a while.
    private let joinTimeout: Duration
    /// How long the SFU authorization round trip gets: one HTTP request that
    /// mints a token. At this point it is a dead request, not a slow one.
    private let credentialsTimeout: Duration
    /// How long reaching the SFU gets: the signalling socket, then ICE and
    /// DTLS. Relay fallback on a hostile network legitimately costs several
    /// seconds, so this covers a full attempt and a retry — not an endless one.
    private let transportConnectTimeout: Duration
    /// How long publishing local media gets once the transport is up: starting
    /// the capture device plus a publish round trip over an established
    /// connection. Seconds here mean a wedged device, not a slow network.
    private let mediaPublishTimeout: Duration
    /// How long the MatrixRTC leave gets during teardown. It is a state-event
    /// round trip through the SDK, so a slow network legitimately needs a few
    /// seconds; past that the user is staring at a call they already ended.
    private let leaveTimeout: Duration
    /// How long the transport disconnect gets. Closing a peer connection and
    /// its signalling socket is local work — seconds here mean a wedge, not a
    /// slow network.
    private let transportDisconnectTimeout: Duration
    /// How long an answer, or a DM call joined, waits once its media is up
    /// for anybody to be there (see `updatePeerWait`). Long enough for a
    /// caller's membership to sync after ours; their media is usually on the
    /// SFU before we are.
    private let peerWaitDuration: Duration
    private let transport: NativeCallTransportProtocol
    private var cancellables = Set<AnyCancellable>()
    /// The state a hold interrupted, so resuming restores it rather than
    /// assuming `.connected` (audit A5-5).
    ///
    /// A call can be held while it is still joining or recovering, and both
    /// used to be dropped on the floor: the guard only recognised
    /// `.connected`, so an interruption arriving mid-connect left the
    /// session believing it still owned an audio route iOS had taken. The
    /// join then published the microphone into a session it did not have,
    /// and the user got a call that says "connected" with dead audio and no
    /// held state to come back from.
    private var stateBeforeHold: NativeCallSessionState?

    /// Holding parks audio, not signaling. Join/reconnect progress must
    /// update the resume state without releasing the system's hold.
    private var unheldState: NativeCallSessionState {
        get { state == .onHold ? stateBeforeHold ?? .connected : state }
        set {
            if state == .onHold {
                stateBeforeHold = newValue
            } else {
                state = newValue
            }
        }
    }

    /// Whether a remote MatrixRTC membership has ever been visible. This is
    /// what turns "nobody joined yet" into "everybody left".
    private var hadRemoteParticipant = false
    /// Whether anybody the call is with is in it now, as the peer wait
    /// counts them: the peer by the leave rules' presence, or for a human
    /// peer anyone on the SFU at all.
    private var isAnyoneInCall = false
    /// A call joined rather than started, from the end of `start()`.
    private var waitsForPeer = false
    // periphery:ignore - auto cancels when reassigned
    @CancellableTask private var peerWaitTask: Task<Void, Never>?
    // periphery:ignore - auto cancels when reassigned
    @CancellableTask private var unansweredRingTask: Task<Void, Never>?
    // periphery:ignore - auto cancels when reassigned
    @CancellableTask private var reconnectTimeoutTask: Task<Void, Never>?
    /// The subscription worker. Deliberately NOT `@CancellableTask`: that
    /// wrapper cancels on assignment, and the worker clears its own handle
    /// when it converges — it would cancel itself mid-walk.
    private var trackSubscriptionTask: Task<Void, Never>?

    /// Keys that arrived before we knew the participant they belong to are
    /// still installed: the key provider is keyed by identity, not by an
    /// established connection, so late-joining media decrypts immediately.
    private var isConnected = false
    /// Video side effects wait until initial local media has settled. Otherwise
    /// an early membership update flips a video call to audio before its camera
    /// has even been requested.
    private var isInitialMediaReady = false
    /// Teardown latch: `stop` awaits an end tone and two round-trips, so it
    /// must not run twice concurrently (hang-up racing a timeout, or the
    /// transport's own disconnect callback re-entering).
    private var isStopping = false
    /// Camera-switch latch: the capturer restarts its capture session, and
    /// overlapping restarts break it (see `switchCamera`).
    private var isSwitchingCamera = false
    /// One hard-disconnect rejoin per call (see `attemptRejoinOrStop`).
    private var didAttemptRejoin = false
    /// This session's claim on the process-wide audio state, held from `start`
    /// until teardown. Nil once released — or never taken, when the call ends
    /// before it starts.
    private var audioOwner: NativeCallAudioOwner?

    weak var delegate: NativeCallSessionDelegate?

    private(set) var state: NativeCallSessionState = .connecting {
        didSet {
            guard state != oldValue else { return }

            updateTones(from: oldValue)
            delegate?.nativeCallSession(self, didChangeState: state)
        }
    }

    private func updateTones(from oldState: NativeCallSessionState) {
        switch state {
        case .ringing:
            NativeCallAudio.isRingbackActive = true
            NativeCallAudio.playTone(.ringback)
        case .connected:
            NativeCallAudio.stopTone()
            NativeCallAudio.isRingbackActive = false

            switch oldState {
            case .ringing, .reconnecting:
                NativeCallAudio.playTone(.connected)
            default:
                break
            }
        case .reconnecting:
            NativeCallAudio.playTone(.reconnecting)
        case .onHold, .connecting, .ended:
            NativeCallAudio.stopTone()
            NativeCallAudio.isRingbackActive = false
        }
    }

    private(set) var participants: [NativeCallParticipant] = [] {
        didSet {
            guard participants != oldValue else { return }
            delegate?.nativeCallSession(self, didChangeParticipants: participants)
        }
    }

    private(set) var videoTiles: [NativeCallVideoTile] = [] {
        didSet {
            guard videoTiles != oldValue else { return }
            delegate?.nativeCallSession(self, didChangeVideoTiles: videoTiles)
        }
    }

    /// Starts nil so the first derivation — which always arrives before any
    /// agent could have changed anything — does not ring the doorbell.
    private var agentStateDocuments: [String: String]? {
        didSet {
            guard let agentStateDocuments, oldValue != nil, agentStateDocuments != oldValue else { return }
            delegate?.nativeCallSessionDidChangeAgentState(self)
        }
    }

    /// Unlike the documents above, this publishes from the FIRST derivation:
    /// an agent already translating when we join has to reach the block, and
    /// there is no doorbell to debounce here. One value so a claim change
    /// and a speaking change cannot race each other into the delegate out
    /// of order.
    private(set) var agentClaims = NativeCallAgentClaims() {
        didSet {
            guard agentClaims != oldValue else { return }
            delegate?.nativeCallSession(self, didChangeAgentClaims: agentClaims)
        }
    }
    
    private var hasActiveVideo: Bool? {
        didSet {
            guard let hasActiveVideo, hasActiveVideo != oldValue else { return }
            delegate?.nativeCallSession(self,
                                        didChangeActiveVideo: hasActiveVideo,
                                        isSpeakerEnabled: NativeCallAudio.isSpeakerEnabled)
        }
    }

    /// G10 — the transport's own quality verdict for our link, narrated by
    /// the screen so degradation never reads as a broken call.
    private(set) var connectionQuality: NativeCallConnectionQuality = .unknown {
        didSet {
            guard connectionQuality != oldValue else { return }
            delegate?.nativeCallSession(self, didChangeConnectionQuality: connectionQuality)
        }
    }

    /// Brief 0063 Slice 4: personal listening. The choice lives only in
    /// this session object — client-side, per-call, never persisted.
    private(set) var listening = NativeCallListeningState() {
        didSet {
            guard listening != oldValue else { return }
            delegate?.nativeCallSession(self, didChangeListening: listening)
        }
    }

    /// The user picked what to hear. An input like any other — the
    /// derivation applies it to media subscriptions immediately.
    func setListeningChoice(_ choice: NativeCallListeningChoice) {
        updateInputs { $0.listeningChoice = choice }
    }

    /// Live member-hints update: an agent attached mid-call re-badges as
    /// soon as the backend publishes its hint.
    func updateServiceMembers(_ members: Set<String>) {
        updateInputs { $0.serviceMembers = members }
    }

    /// THE single choke point for state: every event handler mutates the
    /// inputs here and nowhere else, and every mutation re-derives the
    /// roster, the listening state and the subscription plan. There are
    /// no per-source triggers left to forget.
    private func updateInputs(_ mutate: (inout NativeCallDerivationInputs) -> Void) {
        // A dead session's late transport events (LiveKit keeps delivering
        // for a beat after the disconnect) must not walk subscriptions or
        // flip the process-wide audio mode under the call that replaced it.
        if case .ended = state { return }
        var pending = inputs
        // The transport keeps its own mutable state; snapshot it on EVERY
        // input write so a membership or key event never derives against
        // yesterday's media picture (the transport connects concurrently
        // with the MatrixRTC join and has no event for "already there").
        pending.transportParticipants = transport.remoteParticipants
        pending.transportTracks = transport.remoteTracks
        pending.isLocalSpeaking = transport.isLocalSpeaking
        pending.localConnectionQuality = transport.localConnectionQuality
        pending.isMicrophoneEnabled = transport.isMicrophoneEnabled
        pending.isCameraEnabled = transport.isCameraEnabled
        pending.transportLocalIdentity = transport.localIdentity
        mutate(&pending)
        // The lane memory (Brief 0066 rev. 2) is the one derived fact that
        // needs yesterday: it is folded into the inputs here, from the same
        // snapshot the derivation reads, so it is never one write behind.
        pending.lanesSeenLive = NativeCallStateDerivation.lanesSeenLive(previous: inputs.lanesSeenLive, inputs: pending)
        guard pending != inputs else { return }
        // Rooms of any size are native (ADR-0079 D3); crossing the ring
        // limit mid-call changes nothing, but the grid past it is only
        // eyeballed, so the crossing is worth a trace.
        if pending.memberships.count > NativeCallConfiguration.ringMemberLimit,
           inputs.memberships.count <= NativeCallConfiguration.ringMemberLimit {
            MXLog.info("MatrixRTC membership count crossed the ring limit: \(pending.memberships.count)")
        }
        inputs = pending

        let derived = NativeCallStateDerivation.derive(inputs)
        listening = derived.listening
        participants = derived.participants
        videoTiles = derived.videoTiles
        agentStateDocuments = derived.agentStateDocuments
        agentClaims = derived.agentClaims
        connectionQuality = derived.connectionQuality
        applySubscriptionPlanIfChanged(derived.subscriptionPlan)
        applyDirectCallPresence(derived)
        applyGroupCallPresence(derived)
        applyVideoState(derived)
    }

    private func applyVideoState(_ derived: NativeCallDerivedState) {
        // A call parked behind another (Brief 0068 Slice 2) keeps deriving
        // on its transport events; it must not flip the process-wide audio
        // mode under the active call. The resume re-applies ours.
        guard isInitialMediaReady, !inputs.holdSilencesMedia else { return }
        NativeCallAudio.setVideoEnabled(derived.hasActiveVideo)
        hasActiveVideo = derived.hasActiveVideo
    }

    /// The DM telephone semantics, applied from DERIVED presence rather
    /// than from whichever handler happened to notice a change.
    ///
    /// MatrixRTC has conference semantics: nobody's leave ends the session
    /// for anyone else. A DM needs a ring a peer ANSWERS and a hang-up when
    /// the last peer leaves. Both used to be imperative helpers poked from
    /// five event handlers, each rebuilding its own view of presence — the
    /// shape this derivation exists to delete, and the reason an attached
    /// agent answered the ring on the callee's behalf.
    ///
    /// The media-level half matters for the hang-up: a killed app never
    /// sends its membership leave, but the SFU notices the dead connection
    /// within seconds — so presence is memberships OR media, and both are
    /// role-filtered.
    private func applyDirectCallPresence(_ derived: NativeCallDerivedState) {
        guard configuration.scope.isOneToOne else { return }

        // The peer is whoever the DM is WITH. With one's own assistant that
        // is the agent (operator, 2026-09-11: the call rang out while the
        // agent sat in the room); in a DM with a human an agent only
        // attaches, and only the human answers or ends the call.
        let peerIsPresent: Bool
        let peerHasAnswered: Bool
        switch configuration.scope {
        case .assistant:
            peerIsPresent = derived.hasAgentRemote
            peerHasAnswered = derived.hasAuthorizedAgentRemote
        case .direct, .group:
            peerIsPresent = derived.hasHumanRemote
            peerHasAnswered = derived.hasAuthorizedHumanRemote
        }

        isAnyoneInCall = peerIsPresent || (configuration.scope == .direct && derived.hasHumanOnTransport)
        updatePeerWait()
        if peerIsPresent {
            hadRemoteParticipant = true
        }

        if peerHasAnswered, case .ringing = unheldState {
            unansweredRingTask = nil
            unheldState = .connected
            return
        }

        guard hadRemoteParticipant, !peerIsPresent else { return }
        switch state {
        case .connected, .reconnecting, .onHold:
            MXLog.info("The remote participant left the DM call, ending it")
            Task { [weak self] in await self?.stop(reason: .remoteEnded) }
        default:
            break
        }
    }

    /// Phase 4 — the group half of "an agent alone does not hold a call
    /// open" (`18 · Call states`). Conference semantics let everyone leave
    /// without ending the session for anyone else, so a call whose OTHER
    /// humans have all gone would sit in a one-person conference with an
    /// agent — possibly a recording one — for company. Once a human peer
    /// has been seen, their collective departure ends the call here, with
    /// its own reason so the outcome reads "Everyone left", not "ended".
    private func applyGroupCallPresence(_ derived: NativeCallDerivedState) {
        guard configuration.scope == .group else { return }

        isAnyoneInCall = derived.hasHumanRemote || derived.hasHumanOnTransport
        updatePeerWait()
        if derived.hasHumanRemote {
            hadRemoteParticipant = true
        }

        guard hadRemoteParticipant, !derived.hasHumanRemote else { return }
        switch state {
        case .connected, .reconnecting, .onHold:
            MXLog.info("Every other human left the group call, ending it")
            Task { [weak self] in await self?.stop(reason: .everyoneLeft) }
        default:
            break
        }
    }

    /// Transport state isn't pushed — it is RE-READ inside every input
    /// write (see `updateInputs`), so no external event can observe a
    /// stale media snapshot. This explicit refresh exists for transport
    /// events, whose only payload IS that snapshot.
    private func refreshTransportInputs() {
        updateInputs { _ in }
    }

    /// Applies the plan, serialising against itself.
    ///
    /// Media subscriptions are DESIRED state, applied asynchronously: the
    /// transport walks every publication of every participant. The previous
    /// version recorded the plan as applied BEFORE the walk and cancelled the
    /// in-flight walk whenever a new plan arrived — so a cancelled walk left
    /// some publications in the old state while `appliedSubscriptionPlan`
    /// claimed the new one, and the guard above then skipped the correction
    /// forever. That is an audible failure mode: an unsubscribe that never
    /// happened keeps playing media the listener asked to mute.
    ///
    /// Now: the newest plan is remembered, one worker applies plans in order,
    /// and a plan counts as applied only once the transport has accepted it.
    private func applySubscriptionPlanIfChanged(_ plan: NativeCallSubscriptionPlan) {
        guard plan != desiredSubscriptionPlan else { return }
        // The ducking order is the timing now (Brief 0066 rev. 2): a
        // document change with no track change must reach the microphones
        // at once, not after the worker's backoff sleep. The walk below
        // re-applies it as the self-heal for microphones that land later.
        if plan.originalDucking != desiredSubscriptionPlan?.originalDucking {
            transport.setOriginalDucking(plan.originalDucking)
        }
        desiredSubscriptionPlan = plan

        guard trackSubscriptionTask == nil else { return }
        trackSubscriptionTask = Task { [weak self] in
            var retryDelay = Duration.seconds(1)
            // Drain: a plan that arrives while we are applying replaces the
            // target rather than starting a second, racing walk.
            while let self, !Task.isCancelled,
                  let next = desiredSubscriptionPlan, next != appliedSubscriptionPlan {
                logSubscriptionPlan(next)
                let applied = await transport.setSubscriptions(authorizedIdentities: next.authorizedIdentities) { track in
                    next.isTrackExcluded(identity: track.identity,
                                         name: track.name,
                                         kind: track.kind,
                                         trackID: track.trackID,
                                         source: track.source)
                }
                // The ducking order rides every walk, applied or not: it is
                // idempotent and self-heals per subscribed microphone, and
                // gating it on `applied` let a video-quality refusal (which
                // routinely fails for a beat) hold a covered microphone at
                // unity under the translation for the whole backoff.
                transport.setOriginalDucking(next.originalDucking)
                if applied {
                    appliedSubscriptionPlan = next
                    retryDelay = .seconds(1)
                } else {
                    // A publication refused its new state. Recording the plan
                    // as applied anyway would silence the retry forever —
                    // and a failed UNsubscribe keeps playing media the policy
                    // revoked. Back off (bounded, so a wedged transport
                    // cannot spin) and walk again.
                    try? await Task.sleep(for: retryDelay)
                    retryDelay = min(retryDelay * 2, .seconds(8))
                }
            }
            self?.trackSubscriptionTask = nil
        }
    }

    /// The one line that explains silence on a device: what the plan lets
    /// through and what it refuses, per publication. Identities and track
    /// names are Matrix IDs and lane labels — never content.
    private func logSubscriptionPlan(_ plan: NativeCallSubscriptionPlan) {
        var subscribed = 0
        var unauthorized = 0
        var excluded = 0
        for track in inputs.transportTracks {
            guard plan.authorizedIdentities.contains(track.identity) else {
                unauthorized += 1
                MXLog.verbose("Call media refused (unauthorized): \(track.identity) \(track.name)")
                continue
            }
            if plan.isTrackExcluded(identity: track.identity,
                                    name: track.name,
                                    kind: track.kind,
                                    trackID: track.trackID,
                                    source: track.source) {
                excluded += 1
                let reason = plan.staleTranslationTracks.contains(.init(identity: track.identity,
                                                                        trackID: track.trackID,
                                                                        name: track.name))
                    ? "stale" : "policy"
                MXLog.verbose("Call media refused (\(reason)): \(track.identity) \(track.name)")
            } else {
                subscribed += 1
                MXLog.verbose("Call media allowed: \(track.identity) \(track.name)")
            }
        }
        MXLog.info("Applying call media plan: channel \(plan.channel), \(subscribed) allowed, \(unauthorized) unauthorized, \(excluded) excluded")
    }

    /// The transport when it can draw video. Handed to the ONE leaf view
    /// that renders tiles; nothing else in the screen sees it.
    var videoRenderer: NativeCallVideoRendering? {
        transport as? NativeCallVideoRendering
    }

    /// The transport when it can report voice levels. Handed to the agent
    /// block alone, which samples it at display rate while the wave shows.
    var voiceLevelReader: NativeCallVoiceLevelReading? {
        transport as? NativeCallVoiceLevelReading
    }

    init(rtcSession: MatrixRTCSessionProtocol,
         isRoomEncrypted: Bool,
         notifyRoom: Bool,
         isAnswer: Bool = false,
         configuration: NativeCallConfiguration,
         serviceMembers: Set<String> = [],
         serviceMembersPublisher: AnyPublisher<Set<String>, Never>? = nil,
         transport: NativeCallTransportProtocol? = nil,
         unansweredRingDuration: Duration = .seconds(30),
         reconnectTimeoutDuration: Duration = .seconds(30),
         joinTimeout: Duration = .seconds(15),
         credentialsTimeout: Duration = .seconds(10),
         transportConnectTimeout: Duration = .seconds(15),
         mediaPublishTimeout: Duration = .seconds(10),
         leaveTimeout: Duration = .seconds(4),
         transportDisconnectTimeout: Duration = .seconds(2),
         peerWaitDuration: Duration = .seconds(10)) {
        self.rtcSession = rtcSession
        self.isRoomEncrypted = isRoomEncrypted
        self.notifyRoom = notifyRoom
        self.isAnswer = isAnswer
        self.configuration = configuration
        self.transport = transport ?? LiveKitCallTransport(encryptMedia: isRoomEncrypted)
        inputs.serviceMembers = serviceMembers
        inputs.ownIdentity = rtcSession.ownIdentity
        inputs.isRoomEncrypted = isRoomEncrypted
        self.unansweredRingDuration = unansweredRingDuration
        self.reconnectTimeoutDuration = reconnectTimeoutDuration
        self.joinTimeout = joinTimeout
        self.credentialsTimeout = credentialsTimeout
        self.transportConnectTimeout = transportConnectTimeout
        self.mediaPublishTimeout = mediaPublishTimeout
        self.leaveTimeout = leaveTimeout
        self.transportDisconnectTimeout = transportDisconnectTimeout
        self.peerWaitDuration = peerWaitDuration

        super.init()

        observeTransportEvents()
        observeProtocolUpdates()
        observeAudioInterruptions()
        observeTermination()

        // External sources of truth arrive as PUBLISHERS, not as pokes
        // from other layers: member hints re-badge the roster live. The
        // live translation truth needs no feed at all — it rides the
        // agent's `spiral.agent.state` participant attributes inside the
        // transport snapshot.
        serviceMembersPublisher?
            .sink { [weak self] members in
                Task { @MainActor in self?.updateServiceMembers(members) }
            }
            .store(in: &cancellables)
    }

    /// Join the MatrixRTC session and connect the media transport.
    ///
    /// The media engine stays parked until CallKit activates the audio session;
    /// starting it earlier is what breaks audio on a locked device.
    ///
    /// Every external step is bounded. Teardown was bounded first, but
    /// `failStart` is only reachable once these have returned — so a wedged
    /// join left the screen on "connecting" with no alert, no dismissal and no
    /// way out, which is the same dead end from the other side.
    func start() async {
        // It suspends, so it goes before the guards below.
        await settleWhetherTheJoinRings()
        // The call can be over before this even runs — a CallKit end action
        // while the screen was still being built. Claiming the audio then takes
        // a hold that no teardown is left to give back, and the process-wide
        // state never returns to the SDK.
        if case .ended = state { return }
        guard !isStopping else { return }

        // Declared before the session is prepared: CallKit activates the
        // category configured at fulfil time, so the video mode and the
        // speaker default have to be in place first.
        NativeCallAudio.setVideoEnabled(configuration.media == .video)
        audioOwner = NativeCallAudio.prepareForCallKit()

        guard await joinsWithinTimeout() else {
            await failStart(.couldNotJoin)
            return
        }
        if startWasAbandoned {
            await abortAbandonedStart()
            return
        }

        if notifyRoom {
            let notificationEventID = await ringNotificationIDWithinTimeout()
            if startWasAbandoned {
                await abortAbandonedStart()
                return
            }
            if let notificationEventID {
                delegate?.nativeCallSession(self, didSendRingNotification: notificationEventID)
            }
        }

        // The ring begins as soon as the room has been notified, before the
        // media transport is up. Entering `ringing` only after `connect` left a
        // window in which a fast callee — the voice agent answers in about two
        // seconds — joined while the state was still `connecting`, so the
        // answer callback found nothing to promote and the call rang until it
        // timed out. An outgoing ring is not a conversation yet, so `ringing`
        // holds until a remote actually appears.
        if notifyRoom, configuration.scope.isOneToOne {
            unheldState = .ringing
            startUnansweredRingTimeout()
        }

        guard let credentials = await transportCredentialsWithinTimeout() else {
            await failStart(.serverUnreachable)
            return
        }
        if startWasAbandoned {
            await abortAbandonedStart()
            return
        }

        do {
            try await bringUpMedia(with: credentials)
        } catch {
            MXLog.error("Failed connecting the native call transport: \(error)")
            await failStart(.couldNotConnect)
            return
        }
        if startWasAbandoned {
            await abortAbandonedStart()
            return
        }

        isInitialMediaReady = true

        // A hold that began during the connect could tell nobody (nothing was
        // connected); the microphone this join just published must go quiet
        // and the room must hear it now (Brief 0068).
        if case .onHold = state {
            tellPeersAboutHold(true)
        }

        if !notifyRoom || configuration.scope == .group {
            unheldState = .connected
        }

        // Someone may already be in the room by the time we finish connecting,
        // and LiveKit only reports arrivals from that point on — the funnel
        // re-reads the roster and answers the ring.
        refreshTransportInputs()
        // A group call joined, not answered, waits for others for good, as
        // one it starts does (question 94).
        if !notifyRoom, isAnswer || configuration.scope.isOneToOne {
            waitsForPeer = true
            updatePeerWait()
        }
        await updateMediaIntent()
        startAudioIfCallKitStaysSilent()
    }

    /// Connect the transport and publish the media this call starts with, each
    /// step bounded so a wedged SFU or capture device fails the call instead of
    /// suspending the start forever.
    private func bringUpMedia(with credentials: MatrixRTCTransportCredentials) async throws {
        // A connect that resumes into an ended call (hang-up or its own
        // timeout) disconnects itself inside `connectTransport` and throws;
        // the microphone is never requested on it (audit C1: the old code
        // published a hot mic into a room whose Matrix membership was
        // already left).
        try await connectTransport(with: credentials) { [weak self] in self?.startWasAbandoned ?? true }
        isConnected = true
        if startWasAbandoned {
            await abortAbandonedStart()
            throw CancellationError()
        }

        // Publishing is requested here but only produces audio once the engine
        // is allowed to run, i.e. after CallKit activation.
        try await bounded(by: mediaPublishTimeout) { @MainActor [weak self] in
            guard let self else { return }
            try await transport.setMicrophone(enabled: true)
        }

        if startWasAbandoned {
            await abortAbandonedStart()
            throw CancellationError()
        }

        // A video call starts with the camera on — that is what starting a
        // video call means. A failure here is NOT fatal: the call continues
        // as audio — better than dropping a connected call over a busy
        // camera — but it is SAID (audit T3: this used to be a silent
        // downgrade, and the "control offering to retry" this comment once
        // promised did not exist; the delegate's alert now points at the
        // camera button, which is the retry).
        guard configuration.media == .video else { return }

        do {
            try await bounded(by: mediaPublishTimeout) { @MainActor [weak self] in
                guard let self else { return }
                try await transport.setCamera(enabled: true)
            }
        } catch {
            MXLog.error("Could not start the camera; continuing with audio: \(error)")
            delegate?.nativeCallSessionDidDowngradeToAudio(self)
        }
    }

    /// True when the call ended underneath a suspended start step — a CallKit
    /// end action, a hang-up, the unanswered-ring timeout. `bounded()` does
    /// not cancel abandoned work on purpose, so every await in `start()` can
    /// resume into a session that is already over; each one re-checks this
    /// before acting on what it fetched (audit C1, the wave-5 call audit).
    private var startWasAbandoned: Bool {
        if case .ended = state { return true }
        return isStopping
    }

    /// Late-resume teardown for an abandoned `start()`.
    ///
    /// `stop()` already ran — but it ran while `isConnected` was still false
    /// and skipped the transport teardown, so whatever the resumed start has
    /// connected since is this path's to put back. Without it the old code
    /// published a hot microphone (and camera) into a room whose Matrix
    /// membership was already left, overwrote the terminal `.ended` with
    /// `.connected`, and the delegate then minted a fresh CallKit call for a
    /// dead session.
    private func abortAbandonedStart() async {
        MXLog.info("Native call start resumed after the call ended; discarding the late work")
        if isConnected {
            await disconnectTransportWithinTimeout()
            isConnected = false
        }
        releaseAudio()
    }

    /// Single teardown for every way `start` can fail.
    ///
    /// `prepareForCallKit` disables LiveKit's automatic audio configuration
    /// PROCESS-WIDE, so a start that returns without releasing it leaves every
    /// later call — native or Element Call — silent. The transport must also be
    /// disconnected: `setMicrophone` can throw after `connect` succeeded, and a
    /// room left connected is a ghost membership on the SFU.
    private func failStart(_ failure: NativeCallFailure) async {
        // A bounded start step can still be running when the user hangs up, so
        // its failure now lands after the call has already ended. The reason on
        // screen belongs to whoever ended it first, and the teardown below has
        // already run.
        if case .ended = state { return }
        guard !isStopping else { return }

        // Audit wave 8 — this is a second full teardown path, and it has to
        // join the latch `stop()` uses rather than merely read it. It takes
        // seconds (a bounded leave, then a bounded disconnect) and leaves
        // `state` non-terminal throughout, so a hang-up or the SDK's own
        // `Ended` landing in that window passed both of `stop()`'s guards and
        // ran the whole teardown again — a second end tone, a second leave,
        // and a race between two terminal reasons. The dismissal delay
        // differs per reason, so the less informative one usually won and the
        // user lost the sentence explaining why the call failed.
        isStopping = true
        defer { isStopping = false }

        unansweredRingTask = nil
        if isConnected {
            await disconnectTransportWithinTimeout()
            isConnected = false
        }
        await leaveWithinTimeout()
        releaseAudio()
        state = .ended(reason: .failed(failure))
    }

    /// A call-back right after a hang-up finds the room still showing a call:
    /// this device's own membership, until its leave syncs back. Nobody else
    /// is in it, so it is a fresh call and rings the room. An answer never
    /// rings.
    private func settleWhetherTheJoinRings() async {
        guard !notifyRoom, !isAnswer, !startWasAbandoned, await isOnlyThisDeviceInTheRoomCall() else { return }
        MXLog.info("The room's call is only this device's own membership; starting a fresh call")
        notifyRoom = true
    }

    /// Whether every call membership in the room's state is this device's
    /// own, or there is none. A read that fails or wedges says no, and the
    /// flow's join stands.
    private func isOnlyThisDeviceInTheRoomCall() async -> Bool {
        let memberships = try? await bounded(by: joinTimeout) { @MainActor [weak self] () -> [MatrixRTCParticipant]? in
            guard let self, case let .success(memberships) = await rtcSession.memberships() else { return nil }
            return memberships
        }
        guard let memberships else { return false }
        return memberships.allSatisfy { $0.identity == rtcSession.ownIdentity }
    }

    /// Join the MatrixRTC session, giving up if the SDK wedges. Only the
    /// timeout throws — a join that merely fails reports itself.
    private func joinsWithinTimeout() async -> Bool {
        do {
            return try await bounded(by: joinTimeout) { @MainActor [weak self] () -> Bool in
                guard let self else { return false }
                guard case .success = await rtcSession.join(encryptMedia: isRoomEncrypted,
                                                            notification: notifyRoom ? configuration.freshCallNotification : nil,
                                                            media: configuration.media) else { return false }
                return true
            }
        } catch {
            MXLog.error("The MatrixRTC join did not finish within \(joinTimeout); failing the call instead of waiting")
            return false
        }
    }

    /// The `m.rtc.notification` the join sent, on the join's own bound: it
    /// reports what that step did, and a wedge here strands the start exactly
    /// as the join itself would. Losing it only costs the decline listener.
    private func ringNotificationIDWithinTimeout() async -> String? {
        do {
            return try await bounded(by: joinTimeout) { @MainActor [weak self] () -> String? in
                guard let self else { return nil }
                return await rtcSession.rtcNotificationEventID()
            }
        } catch {
            MXLog.error("The ring notification identifier did not arrive within \(joinTimeout); declines will not be observed")
            return nil
        }
    }

    /// Fetch the SFU credentials, giving up if the authorization service wedges.
    private func transportCredentialsWithinTimeout() async -> MatrixRTCTransportCredentials? {
        do {
            return try await bounded(by: credentialsTimeout) { @MainActor [weak self] () -> MatrixRTCTransportCredentials? in
                guard let self, case let .success(credentials) = await rtcSession.transportCredentials() else { return nil }
                return credentials
            }
        } catch {
            MXLog.error("The call server did not authorize this session within \(credentialsTimeout)")
            return nil
        }
    }

    /// Bounds one external START step.
    ///
    /// Same contract as `completes(within:)` — the abandoned work is NOT
    /// cancelled, what matters is that this returns — except that these steps
    /// carry a value or throw. A timeout surfaces as an ordinary error so it
    /// Stop publishing the microphone and camera without leaving anything.
    /// Each call is bounded by a fraction of the publish timeout: this runs
    /// on the hang-up path, where the user is already gone.
    private func silenceLocalMedia() async {
        let budget = Duration.seconds(1)
        if transport.isMicrophoneEnabled {
            try? await bounded(by: budget) { @MainActor [weak self] in
                try await self?.transport.setMicrophone(enabled: false)
            }
        }
        if transport.isCameraEnabled {
            try? await bounded(by: budget) { @MainActor [weak self] in
                try await self?.transport.setCamera(enabled: false)
            }
        }
    }

    /// Connect the transport, bounded — and make the connect OWN its late
    /// completion. `bounded()` does not cancel the work it gives up on, so a
    /// connect that succeeds after its deadline used to leave a live,
    /// unowned SFU connection: the caller had already failed the call with
    /// `isConnected == false` and skipped the transport teardown, and the
    /// abandonment checks after `bounded()` never ran because `bounded()`
    /// threw. The check therefore lives INSIDE the work: whether the call is
    /// over by the time the connect resumes (hang-up or timeout — both leave
    /// `startWasAbandoned` true, and the rejoin ends the call the same way),
    /// the connection is put back here and the throw tells a still-live
    /// caller nothing was connected (audit 2026-09-05).
    private func connectTransport(with credentials: MatrixRTCTransportCredentials,
                                  abandonedIf isAbandoned: @escaping @MainActor () -> Bool) async throws {
        // Both sides of the race run on the main actor, so exactly one of
        // them ends up owning a connection that landed after the deadline:
        // the closure, if the caller has already given up when it resumes;
        // the caller, if the closure got there first but its result was
        // dropped by the expired runner.
        let race = LateConnectRace()
        do {
            try await bounded(by: transportConnectTimeout) { @MainActor [weak self] in
                guard let self else { return }
                try await transport.connect(url: credentials.url.absoluteString,
                                            token: credentials.token)
                race.connected = true
                if race.callerGaveUp || isAbandoned() {
                    // Claimed before the first await so the caller's catch,
                    // should it run while this disconnect is in flight, does
                    // not disconnect a second time.
                    race.putBackByClosure = true
                    MXLog.info("Transport connected after the call moved on; disconnecting the late connection")
                    await disconnectTransportWithinTimeout()
                    throw CancellationError()
                }
            }
        } catch {
            race.callerGaveUp = true
            if race.connected, !race.putBackByClosure, error is ExpiringTaskRunnerError {
                MXLog.info("Transport connected as its deadline expired; disconnecting the unowned connection")
                await disconnectTransportWithinTimeout()
            }
            throw error
        }
    }

    /// Shared between a bounded connect and its caller; see `connectTransport`.
    @MainActor
    private final class LateConnectRace {
        var callerGaveUp = false
        var connected = false
        var putBackByClosure = false
    }

    /// lands in the step's own failure branch and the user gets the normal
    /// "could not connect" outcome rather than a screen wedged on "connecting".
    private func bounded<T: Sendable>(by timeout: Duration,
                                      _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await ExpiringTaskRunner<T>(work).run(timeout: timeout)
    }

    /// The audio is process-wide and shared with whatever call overlaps this
    /// one, so letting go is all this session may do — the register decides
    /// whether that was the last hold and the teardown runs.
    private func releaseAudio() {
        guard let audioOwner else { return }
        self.audioOwner = nil
        NativeCallAudio.releaseAfterCallKit(owner: audioOwner)
    }

    /// Leave the MatrixRTC session, giving up if it wedges.
    private func leaveWithinTimeout() async {
        // Audit wave 8 — a leave that FAILS lands here too. This used to go
        // through `completes`, which reports false only on a TIMEOUT, so a
        // fast failure read as success and the warning below could not fire
        // for it. Peers cannot tell the two apart, so neither should we.
        let landed: Bool
        do {
            landed = try await bounded(by: leaveTimeout) { @MainActor [weak self] () -> Bool in
                guard let self else { return true }
                guard case .success = await rtcSession.leave() else { return false }
                return true
            }
        } catch {
            landed = false
        }

        if landed {
            return
        }

        // Loud on purpose: nobody else will report this. The membership now
        // stands until it expires, so every peer keeps seeing this device in a
        // call it has already left — and a group call whose last human left
        // will not end for the agents still sitting in it. There is no retry
        // to offer: the SDK takes its state before the network call, so it is
        // already `Idle` and a second leave would do nothing at all.
        MXLog.error("The MatrixRTC leave did not land; ending the call with the membership still standing")
    }

    /// Release the media transport, giving up if it wedges.
    private func disconnectTransportWithinTimeout() async {
        let disconnected = await completes(within: transportDisconnectTimeout) { @MainActor [weak self] in
            guard let self else { return }
            await transport.disconnect()
        }

        if disconnected {
            return
        }

        MXLog.error("The call transport did not disconnect within \(transportDisconnectTimeout); ending the call without it")
    }

    /// Bounds one external teardown step.
    ///
    /// The abandoned work is deliberately NOT cancelled: a leave that lands
    /// late still spares peers the membership expiry, and cancelling a Rust
    /// SDK call mid-flight only adds a second way to fail. What must not
    /// happen is this function not returning — an unbounded `await` here left
    /// `isStopping` true and the state short of `.ended` forever, so the
    /// screen never dismissed, CallKit kept the call and no further call could
    /// be started.
    private func completes(within timeout: Duration, _ work: @escaping @Sendable () async -> Void) async -> Bool {
        do {
            try await ExpiringTaskRunner<Void>(work).run(timeout: timeout)
            return true
        } catch {
            return false
        }
    }

    /// Leave the call and release the media transport.
    func stop(reason: NativeCallEndReason = .userHungUp) async {
        // Already ended, or ending: teardown awaits the end tone and two
        // round-trips, so without this latch a hang-up racing the unanswered
        // timer (or the transport's own disconnect callback) runs teardown
        // twice and the end reason on screen is whichever finished last.
        if case .ended = state { return }
        guard !isStopping else { return }
        isStopping = true

        // The timeout bodies call `stop` themselves, and `@CancellableTask`
        // cancels on assignment — clearing the handle we are running inside
        // would cancel THIS task, cutting the end tone short and running the
        // Matrix leave under cancellation.
        cancelTimers(except: reason)
        trackSubscriptionTask?.cancel()
        trackSubscriptionTask = nil

        // Audit 2026-09-05: the user's hang-up is the moment they stop being
        // heard and seen — not ~650 ms of end tone plus a bounded Matrix
        // leave later, which is how long the microphone used to keep
        // publishing after the screen had already gone. Best-effort and
        // short-bounded: a wedged transport must not delay the hang-up, and
        // the disconnect below is the backstop.
        NativeCallAudio.stopTone()
        if isConnected {
            await silenceLocalMedia()
        }
        // The engine goes first, and only if it is ours: a call held behind
        // another (`holdSilencesMedia`) is ending while the other call is
        // on that engine.
        if !inputs.holdSilencesMedia {
            NativeCallAudio.parkEngineForHangUp()
        }

        // The audible confirmation has to play while the session is still
        // alive; the short wait lets the cue land before teardown. The busy
        // cadence needs a couple of cycles to be recognisable.
        if let endTone = reason.endTone {
            NativeCallAudio.playTone(endTone)
            try? await Task.sleep(for: .milliseconds(endTone == .busy ? 1800 : 650))
        }

        // Leave the Matrix session first: it is what other participants and the
        // agent observe, and it must happen even if the transport is wedged.
        await leaveWithinTimeout()

        if isConnected {
            await disconnectTransportWithinTimeout()
            isConnected = false
        }

        // `.ended` first: its tone update writes `isRingbackActive`, whose
        // observer re-arms the engine while another holder keeps the
        // session active (call waiting) — that has to happen before, not
        // after, this call's share of the audio is given back.
        state = .ended(reason: reason)
        releaseAudio()
        isStopping = false
    }

    /// Clears the lifecycle timers without cancelling the one whose body is
    /// calling us: `@CancellableTask` cancels on assignment, so a timeout
    /// that tears the call down would otherwise cancel itself mid-teardown.
    private func cancelTimers(except reason: NativeCallEndReason) {
        if reason != .unanswered {
            unansweredRingTask = nil
        }
        if reason != .connectionLost {
            reconnectTimeoutTask = nil
        }
        // Its stop runs on a task of its own, so it never cancels itself.
        peerWaitTask = nil
    }

    /// The callee refused the ring (MSC4310 decline).
    func remoteDeclined() async {
        guard configuration.scope == .direct else { return }
        guard case .ringing = unheldState else { return }
        await stop(reason: .declined)
    }

    /// Publish or mute the camera. Same contract as the microphone: the
    /// engine's own state is what reaches the UI, so a refused change (no
    /// permission, device busy) cannot leave the control lying.
    @discardableResult
    func setCameraEnabled(_ enabled: Bool) async -> Bool {
        guard !startWasAbandoned else { return false }
        let succeeded: Bool
        do {
            try await transport.setCamera(enabled: enabled)
            succeeded = true
        } catch {
            MXLog.error("Failed changing the camera state: \(error)")
            succeeded = false
        }
        guard !startWasAbandoned else { return false }
        refreshTransportInputs()
        await updateMediaIntent()
        return succeeded
    }

    /// Audit wave 8 — bounded like every other external step, which this one
    /// was not despite sitting in `start()`.
    ///
    /// The Rust side takes a mutex that the membership refresh loop and the
    /// self-heal republish both hold across a homeserver PUT, so a slow or
    /// retrying publish blocks this call for as long as it lasts. In `start()`
    /// that stranded the line after it — the audio fail-open — so a call whose
    /// CallKit activation never arrived stayed connected, timing, and silent,
    /// with no second trigger.
    private func updateMediaIntent() async {
        guard !startWasAbandoned else { return }
        let media: NativeCallMedia = transport.isCameraEnabled ? .video : .audio
        do {
            let updated = try await bounded(by: mediaPublishTimeout) { @MainActor [weak self] () -> Bool in
                guard let self, !startWasAbandoned else { return false }
                guard case .success = await rtcSession.setMedia(media) else { return false }
                return true
            }
            if !updated {
                MXLog.error("The camera changed but the MatrixRTC membership intent did not")
            }
        } catch {
            MXLog.error("Timed out updating the MatrixRTC membership intent")
        }
    }

    /// Flip the capture device. Failing is not worth an alert — the picture
    /// simply stays as it was.
    ///
    /// Serialized on purpose. The capturer flips its own `position` and THEN
    /// restarts the capture session; two overlapping switches read each
    /// other's half-applied position and tear the session down mid-start,
    /// which surfaces as LiveKit `deviceNotFound` ("No camera video capture
    /// devices available") and leaves the picture stuck on the old lens. That
    /// is not an edge case here: five separate affordances send
    /// `.switchCamera`, each spawning its own `Task`, so an impatient
    /// double-tap overlaps by construction. Found on a device, 2026-09-02.
    ///
    /// A tap during a switch is dropped rather than queued: the hardware
    /// cannot flip faster than one switch at a time, so honouring the second
    /// tap would only return the lens to where it started.
    func switchCamera() async {
        guard !startWasAbandoned else { return }
        guard !isSwitchingCamera else {
            MXLog.info("Ignoring a camera switch while one is still in flight")
            return
        }
        isSwitchingCamera = true
        defer { isSwitchingCamera = false }

        do {
            try await transport.switchCamera()
        } catch {
            MXLog.error("Failed switching the camera: \(error)")
        }
    }

    /// Returns whether the engine accepted the change. A refused mute must
    /// reach the caller: CallKit fulfils its action on the result, and the
    /// control must never claim a microphone is off while it publishes.
    @discardableResult
    func setMicrophoneEnabled(_ enabled: Bool) async -> Bool {
        // A call that is ending (or over) has silenced its microphone as the
        // first thing the hang-up did. A mute asked of it now is already
        // true, and saying otherwise is what crackled after every call:
        // CallKit re-issues a FAILED `CXSetMutedCallAction` every audio
        // frame, ~60 times a second, and each retry reached the transport
        // and toggled the running voice-processing unit (device log
        // 2026-09-07: 741 refusals across three hang-ups). An unmute of a
        // dead call is refused, honestly — nothing is publishing.
        guard !startWasAbandoned else { return !enabled }
        do {
            try await transport.setMicrophone(enabled: enabled)
            guard !startWasAbandoned else { return false }
            refreshTransportInputs()
            return true
        } catch {
            MXLog.error("Failed changing the microphone state: \(error)")
            // The snapshot still holds the truth the engine reports.
            refreshTransportInputs()
            return false
        }
    }

    func setSpeakerEnabled(_ enabled: Bool) {
        NativeCallAudio.setSpeakerEnabled(enabled)
    }

    // MARK: - Private

    /// CallKit owns the audio session, but it does not always hand it over.
    /// Rather than leave a connected call silent, give it a short grace period
    /// and then start the engine ourselves.
    private func startAudioIfCallKitStaysSilent() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))

            guard let self else { return }

            switch state {
            case .connected, .ringing:
                NativeCallAudio.activateWithoutCallKitIfNeeded()
            default:
                break
            }
        }
    }

    /// Best-effort teardown when the process is about to die: fire the
    /// Matrix leave and the transport disconnect in the seconds iOS grants.
    /// The SDK's staged delayed-leave and the membership expiry remain the
    /// backstop — this just spares peers the wait when iOS lets us.
    private func observeTermination() {
        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in
                guard let self, !isStopping else { return }
                Task { await self.stop(reason: .userHungUp) }
            }
            .store(in: &cancellables)
    }

    /// G10 — a GSM call (or Siri) taking the audio session puts this call
    /// on hold; it resumes when the interruption ends. The session, not the
    /// screen, owns the state: the transport keeps its connection, only the
    /// audio is gone, and "silence with a live timer" is the exact shape
    /// users read as a broken call.
    private func observeAudioInterruptions() {
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

                switch type {
                case .began:
                    // Audit A5-5 — a call being joined or recovered can be
                    // interrupted too, and losing the audio route matters
                    // MORE there: the join is about to publish a microphone
                    // it no longer owns.
                    guard state.canBeHeld else { return }
                    MXLog.info("The audio session was interrupted; the call is on hold")
                    stateBeforeHold = state
                    state = .onHold
                    tellPeersAboutHold(true)
                case .ended:
                    // A hold CallKit placed (another Spiral call is active,
                    // Brief 0068 Slice 2) is CallKit's to lift: a Siri or
                    // alarm interruption ending must not resume it under
                    // the active call — un-muted to the peers, silent to us.
                    guard case .onHold = state, !isHeldByCallKit else { return }
                    let resumed = stateBeforeHold ?? .connected
                    stateBeforeHold = nil
                    MXLog.info("The audio interruption ended; resuming the call as \(resumed)")
                    // Restore what was interrupted, not an assumption. A call
                    // held while connecting must go back to connecting, or
                    // the UI reports a call as live while its join is still
                    // in flight.
                    state = resumed
                    tellPeersAboutHold(false)
                    refreshTransportInputs()
                    // CallKit normally re-activates the session itself; when
                    // it stays silent (the fail-open path, Siri handing back)
                    // the call must not resume into a dead session.
                    startAudioIfCallKitStaysSilent()
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)

        // Audit wave 8 — nobody in the app observed this, and it is the one
        // audio event nothing can recover from in place: a media-services
        // reset invalidates the category, the active flag, every route
        // override and the engine's units. `isSessionActive` kept reading
        // true, so the fail-open refused to run, and the call sat connected,
        // timing and silent until the user gave up. Rare, but its cost was
        // "the call is broken and lies about it".
        //
        // Ending honestly is the recovery: teardown rebuilds nothing, and
        // the user can immediately redial into a fresh audio world.
        NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if case .ended = state { return }
                MXLog.error("Media services were reset; the audio world this call was built on is gone — ending it")
                Task { [weak self] in
                    await self?.stop(reason: .failed(.audioReset))
                }
            }
            .store(in: &cancellables)
    }

    private func observeProtocolUpdates() {
        rtcSession.updates
            .sink { [weak self] update in
                guard let self else { return }

                switch update {
                case .participantsChanged(let participants):
                    updateInputs { $0.memberships = participants }
                case .ownEncryptionKeyChanged(let key):
                    // Key first, index second: senders must never tag a frame
                    // with a slot the key is not in yet.
                    apply(key, for: rtcSession.ownIdentity)
                    transport.setSenderKeyIndex(key.index)
                case .encryptionKeyReceived(let key):
                    apply(key, for: key.participantIdentity)
                case .ended:
                    Task { await self.stop(reason: .remoteEnded) }
                }
            }
            .store(in: &cancellables)
    }

    /// Follow-up L1a: a call this device answers, or joins in a DM, is one
    /// somebody else is in. A caller who hung up after the answer's screen
    /// came up is never seen, so the presence rules, which end a call once
    /// its peer has gone, left it up and empty until the user hung up. Nobody
    /// in the call for a whole `peerWaitDuration` ends it; anybody there
    /// pauses the wait, and it starts over when they go — the leave rules
    /// never end a call for a caller they did not see, one only ever on the
    /// SFU.
    ///
    /// A reconnect empties the transport's roster, so the wait sits it out
    /// and looks again once the transport is back.
    private func updatePeerWait() {
        guard waitsForPeer, !isStopping else { return }
        guard !isAnyoneInCall, unheldState != .reconnecting else {
            peerWaitTask = nil
            return
        }
        guard peerWaitTask == nil else { return }
        peerWaitTask = Task { [weak self, peerWaitDuration] in
            try? await Task.sleep(for: peerWaitDuration)

            guard let self, !Task.isCancelled, !isAnyoneInCall else { return }
            switch unheldState {
            case .connected:
                MXLog.info("Nobody is in the call this device joined; ending it")
                let reason: NativeCallEndReason = configuration.scope == .group ? .everyoneLeft : .remoteEnded
                Task { [weak self] in await self?.stop(reason: reason) }
            case .reconnecting:
                // A reconnect this wait missed: it starts again after it.
                peerWaitTask = nil
            default:
                break
            }
        }
    }

    private func startUnansweredRingTimeout() {
        unansweredRingTask = Task { [weak self, unansweredRingDuration] in
            try? await Task.sleep(for: unansweredRingDuration)

            guard let self, !Task.isCancelled, case .ringing = unheldState else { return }

            MXLog.info("The outgoing call was not answered, ending it")
            await stop(reason: .unanswered)
        }
    }

    private func startReconnectTimeout() {
        reconnectTimeoutTask = Task { [weak self, reconnectTimeoutDuration] in
            try? await Task.sleep(for: reconnectTimeoutDuration)

            guard let self, !Task.isCancelled, case .reconnecting = unheldState else { return }

            MXLog.info("The transport could not reconnect, ending the call")
            await stop(reason: .connectionLost)
        }
    }

    private func apply(_ key: MatrixRTCEncryptionKey, for identity: String) {
        guard isRoomEncrypted else {
            MXLog.warning("Received a media key for an unencrypted call, ignoring it")
            return
        }

        transport.setEncryptionKey(key.key, index: key.index, identity: identity)
        // The key flips this participant out of waitingForKeys and can
        // authorize their subscriptions — one input write covers both.
        updateInputs { _ = $0.identitiesWithKeys.insert(identity) }

        MXLog.info("Applied a media key for \(identity) at index \(key.index)")
    }

    /// One credentialed rejoin after a HARD transport drop (token expiry,
    /// server restart): LiveKit's own resume already failed by the time
    /// `didDisconnect` fires, so this is the last try before the call ends
    /// — fresh credentials, fresh connection, previous media intent
    /// restored. Once per call: a link that keeps collapsing is a lost
    /// connection, not a retry loop.
    private func attemptRejoinOrStop() async {
        guard !isStopping, !didAttemptRejoin, isConnected,
              state == .connected || state == .reconnecting || state == .onHold else {
            await stop(reason: .failed(.disconnected))
            return
        }
        didAttemptRejoin = true
        unheldState = .reconnecting
        startReconnectTimeout()
        updatePeerWait()

        let wasMicrophoneEnabled = inputs.isMicrophoneEnabled
        let wasCameraEnabled = inputs.isCameraEnabled

        guard let credentials = await transportCredentialsWithinTimeout() else {
            await stop(reason: .connectionLost)
            return
        }
        do {
            // Bounded like the corresponding start() steps (audit C10): the
            // rejoin used to await the transport raw, so a wedged SFU held the
            // call in `.reconnecting` until the 30 s timer killed it — and a
            // connect that succeeded AFTER that kill republished the
            // microphone into a connection nothing owned.
            try await connectTransport(with: credentials) { [weak self] in
                guard let self else { return true }
                if !isStopping, case .reconnecting = unheldState { return false }
                return true
            }
            if await rejoinWasAbandoned() { return }

            try await bounded(by: mediaPublishTimeout) { @MainActor [weak self] in
                guard let self else { return }
                try await transport.setMicrophone(enabled: wasMicrophoneEnabled)
            }
            if await rejoinWasAbandoned() { return }

            // Promoted BEFORE the camera restore: the camera is best-effort
            // (same posture as start), and a wedged capture device must not
            // hold a transport-healthy call in `.reconnecting` until the
            // timer ends it with `.connectionLost` (audit C10).
            reconnectTimeoutTask = nil
            unheldState = .connected
            refreshTransportInputs()
            updatePeerWait()
            MXLog.info("Rejoined the call transport after a hard disconnect")

            if wasCameraEnabled {
                try? await bounded(by: mediaPublishTimeout) { @MainActor [weak self] in
                    guard let self else { return }
                    try await transport.setCamera(enabled: true)
                }
            }
        } catch {
            MXLog.error("Rejoining the call transport failed: \(error)")
            await stop(reason: .connectionLost)
        }
    }

    /// True when the call moved on — the reconnect timer fired `stop()`, or
    /// the user hung up — while a rejoin step was suspended. The `stop()` that
    /// ran saw a torn transport and had nothing to disconnect, so the
    /// connection THIS resume has made since is a live leak (a republished
    /// microphone on the SFU with no call attached) and is put back here
    /// before the rejoin gives up (audit C10).
    private func rejoinWasAbandoned() async -> Bool {
        if !isStopping, case .reconnecting = unheldState { return false }
        MXLog.info("Rejoin resumed after the call moved on; disconnecting the late transport")
        await disconnectTransportWithinTimeout()
        isConnected = false
        return true
    }

    /// CallKit's hold action (a second call, the system UI's hold button).
    /// The transport keeps its connection; only the audio engine is parked
    /// — the same shape a GSM interruption produces.
    func setOnHold(_ isHeld: Bool) {
        if isHeld {
            // Already held by an audio interruption (the GSM call's
            // `.began` can land before CallKit's hold action): CallKit's
            // hold still has to be recorded, or the interruption's `.ended`
            // resumes the call under the other one — microphone open to
            // the peers, silent to the user — and CallKit's later resume is
            // a no-op (pre-merge review 2026-09-07).
            if case .onHold = state {
                MXLog.info("CallKit put the already-interrupted call on hold")
                isHeldByCallKit = true
                updateInputs { $0.holdSilencesMedia = true }
                return
            }
            // Same widening as the interruption path (audit A5-5). Answering
            // a second call while the first is reconnecting is the ordinary
            // way to reach this: the reconnect window is up to 30 s, and
            // dropping the hold left the first call's microphone publishing
            // to the SFU while iOS and the user both believed it was held.
            guard state.canBeHeld else { return }
            MXLog.info("CallKit put the call on hold")
            stateBeforeHold = state
            state = .onHold
            isHeldByCallKit = true
            // CallKit's hold means another call has the audio engine (Brief
            // 0068 Slice 2): this call's media must not play at all.
            updateInputs { $0.holdSilencesMedia = true }
            tellPeersAboutHold(true)
        } else {
            guard case .onHold = state else { return }
            let resumed = stateBeforeHold ?? .connected
            stateBeforeHold = nil
            isHeldByCallKit = false
            MXLog.info("CallKit resumed the held call as \(resumed)")
            state = resumed
            // The other call may have left the process-wide audio in ITS
            // mode (a video call held behind an audio one resumed in
            // `.voiceChat` on the earpiece); put ours back.
            NativeCallAudio.setVideoEnabled(hasActiveVideo ?? (configuration.media == .video))
            NativeCallAudio.resumeEngineIfSessionActive()
            updateInputs { $0.holdSilencesMedia = false }
            tellPeersAboutHold(false)
            refreshTransportInputs()
            startAudioIfCallKitStaysSilent()
        }
    }

    // MARK: - Hold, visible to the peer (Brief 0068 Slice 1)

    /// What the microphone, camera and speaker were doing when the hold
    /// began, so the resume restores the user's intent rather than "on".
    /// The speaker is part of it because muting the camera drops the video
    /// stage, and turning it back on re-selects the speaker (`NativeCallAudio.
    /// setVideoEnabled`) — a user on the earpiece would come back on speaker.
    private var mediaBeforeHold: MediaIntent?
    /// Brief 0068 Slice 2: this hold is CallKit's (call waiting), so only
    /// CallKit's resume lifts it — not the end of an unrelated audio
    /// interruption.
    private var isHeldByCallKit = false

    private struct MediaIntent {
        let microphone: Bool
        let camera: Bool
        let speaker: Bool
    }

    /// Serialises the hold/resume transport work so a resume landing while
    /// the hold's mutes are still in flight cannot interleave with them.
    private var holdTask: Task<Void, Never>?

    /// A hold used to be a local fact: the audio engine parked, the
    /// transport kept, and the peer heard silence under a live microphone
    /// icon — the interpreter agent likewise. Now the publications are
    /// muted (the fallback every client already renders) and the room is
    /// told, so the peer's screen says "On hold" and the agent stops
    /// interpreting what is not being said. Off the hold, the exact intent
    /// comes back: a microphone muted before the hold stays muted.
    ///
    /// Every transport step is bounded: LiveKit parks a data publish on a
    /// torn signalling channel with nothing to wake it after `stop()`, and
    /// an unbounded await there kept this session alive for ever.
    private func tellPeersAboutHold(_ held: Bool) {
        updateInputs { $0.isLocalOnHold = held }
        let previous = holdTask
        holdTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, isConnected, !startWasAbandoned else { return }
            if held {
                if mediaBeforeHold == nil {
                    mediaBeforeHold = MediaIntent(microphone: transport.isMicrophoneEnabled,
                                                  camera: transport.isCameraEnabled,
                                                  speaker: NativeCallAudio.isSpeakerEnabled)
                }
                if transport.isMicrophoneEnabled {
                    try? await bounded(by: mediaPublishTimeout) { @MainActor [weak self] in
                        try await self?.transport.setMicrophone(enabled: false)
                    }
                }
                if transport.isCameraEnabled {
                    try? await bounded(by: mediaPublishTimeout) { @MainActor [weak self] in
                        try await self?.transport.setCamera(enabled: false)
                    }
                }
                try? await bounded(by: mediaPublishTimeout) { @MainActor [weak self] in
                    await self?.transport.announceHold(true)
                }
            } else {
                // Media first, then the word: a user must not sit muted
                // while a data publish waits out a reconnect.
                let intent = mediaBeforeHold
                mediaBeforeHold = nil
                if intent?.microphone == true {
                    try? await bounded(by: mediaPublishTimeout) { @MainActor [weak self] in
                        try await self?.transport.setMicrophone(enabled: true)
                    }
                }
                if intent?.camera == true {
                    try? await bounded(by: mediaPublishTimeout) { @MainActor [weak self] in
                        try await self?.transport.setCamera(enabled: true)
                    }
                }
                // After the camera: re-enabling it (and the resume's video
                // mode re-apply) selects the speaker; the user's route wins.
                if let speaker = intent?.speaker, speaker != NativeCallAudio.isSpeakerEnabled {
                    NativeCallAudio.setSpeakerEnabled(speaker)
                }
                try? await bounded(by: mediaPublishTimeout) { @MainActor [weak self] in
                    await self?.transport.announceHold(false)
                }
            }
            guard !startWasAbandoned else { return }
            refreshTransportInputs()
        }
    }

    /// Transport events mirror the previous LiveKit delegate wiring: the
    /// session decides, the transport only reports.
    private func observeTransportEvents() {
        transport.events
            .sink { [weak self] event in
                guard let self else { return }

                switch event {
                case .didDisconnect(let error):
                    guard case .ended = state else {
                        if let error {
                            MXLog.error("The native call transport disconnected: \(error)")
                            Task { await self.attemptRejoinOrStop() }
                        } else {
                            Task { await self.stop(reason: .remoteEnded) }
                        }
                        return
                    }
                case .isReconnecting:
                    guard !isStopping, case .connected = unheldState else { return }
                    unheldState = .reconnecting
                    startReconnectTimeout()
                    updatePeerWait()
                case .didReconnect:
                    // Only a reconnecting call can be promoted back: a late
                    // reconnect must not resurrect an ended call, and it must
                    // never answer a ringing one on the peer's behalf.
                    guard !isStopping, case .reconnecting = unheldState else { return }
                    reconnectTimeoutTask = nil
                    unheldState = .connected
                    refreshTransportInputs()
                    updatePeerWait()
                case .participantDidConnect:
                    // Media presence answers the ring too — it can beat the
                    // membership sync — and the funnel derives that.
                    refreshTransportInputs()
                case .participantDidDisconnect:
                    refreshTransportInputs()
                case .participantsUpdated:
                    refreshTransportInputs()
                case .didSubscribeToTrack(let identity):
                    MXLog.info("Subscribed to a media track from \(identity)")
                    // Hearing someone is the strongest answer signal, and the
                    // funnel derives it from the refreshed roster.
                    refreshTransportInputs()
                case .encryptionHealthChanged(let identity, let isHealthy):
                    // Post-key decryption failure: the roster says "waiting
                    // for encryption" instead of presenting silent media as
                    // connected. Presentation-only — the subscription stays,
                    // so the next key (rotation, ratchet) heals it in place.
                    updateInputs { inputs in
                        if isHealthy {
                            inputs.identitiesWithEncryptionFailure.remove(identity)
                        } else {
                            inputs.identitiesWithEncryptionFailure.insert(identity)
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
}
