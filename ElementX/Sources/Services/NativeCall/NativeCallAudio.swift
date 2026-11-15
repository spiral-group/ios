//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import AVFoundation
import Combine
import Foundation
import LiveKit
import Synchronization

// AGENT-PLATFORM (Brief 0063): CallKit owns the audio session on the native
// call path.
//
// LiveKit configures `AVAudioSession` by itself out of the box, which races
// CallKit: the media engine can start before the system has handed the session
// over, and on a locked device that silently produces a call with no audio.
// The rules here are therefore:
//
//   * the SDK never touches `AVAudioSession`;
//   * the media engine is parked until `provider(_:didActivate:)`;
//   * it is parked again on `provider(_:didDeactivate:)`;
//   * call tones only ever start on an already-activated session — anything
//     started earlier is nullified the moment CallKit activates the call.
/// One selectable audio route for the picker (`08 · Audio routes`).
nonisolated struct NativeCallAudioRoute: Identifiable, Equatable {
    enum Kind: Equatable {
        /// The handset receiver — the "iPhone" row.
        case receiver
        case speaker
        /// AirPods, a car, a wired headset: anything not built in.
        case external
    }

    static let receiverID = "builtin-receiver"
    static let speakerID = "builtin-speaker"

    let id: String
    let name: String
    let kind: Kind
    let isActive: Bool
}

/// A port as the builder sees it — a plain value so the route list is a
/// pure, testable function of the session's reality.
nonisolated struct NativeCallAudioPort: Equatable {
    let type: AVAudioSession.Port
    let name: String
    let uid: String
}

/// G8 — the route list as a PURE function of the session's current
/// outputs and available inputs. `AVAudioSession` itself is unmockable in
/// a simulator test, so everything decidable lives here.
nonisolated enum NativeCallAudioRoutes {
    /// Port types that surface as selectable external routes. Bluetooth
    /// output (A2DP) has no INPUT port; its HFP sibling is what
    /// `availableInputs` lists, and selecting it moves the whole route.
    private static let externalInputTypes: Set<AVAudioSession.Port> = [.bluetoothHFP, .carAudio, .headsetMic, .usbAudio]
    private static let builtInOutputTypes: Set<AVAudioSession.Port> = [.builtInReceiver, .builtInSpeaker]

    /// An external device carries the call's sound now.
    static func hasExternalOutput(activeOutputs: [NativeCallAudioPort]) -> Bool {
        activeOutputs.contains { !builtInOutputTypes.contains($0.type) }
    }

    /// An external device carries the call, or takes it once the session activates: a hands-free-only Bluetooth device
    /// (a car kit, a mono headset) is an input under `.playAndRecord` before it is ever an output (question 407).
    static func hasExternalRoute(activeOutputs: [NativeCallAudioPort], availableInputs: [NativeCallAudioPort]) -> Bool {
        hasExternalOutput(activeOutputs: activeOutputs) || availableInputs.contains { externalInputTypes.contains($0.type) }
    }

    static func build(activeOutputs: [NativeCallAudioPort], availableInputs: [NativeCallAudioPort]) -> [NativeCallAudioRoute] {
        let hasExternalOutput = hasExternalOutput(activeOutputs: activeOutputs)

        var routes = availableInputs
            .filter { externalInputTypes.contains($0.type) }
            .map { port in
                NativeCallAudioRoute(id: port.uid,
                                     name: port.name,
                                     kind: .external,
                                     // Output UIDs do not always match the input's
                                     // (bluetooth pairs differ), so an external
                                     // output is matched by uid OR by name.
                                     isActive: hasExternalOutput && activeOutputs.contains { $0.uid == port.uid || $0.name == port.name })
            }

        routes.append(NativeCallAudioRoute(id: NativeCallAudioRoute.receiverID,
                                           name: UntranslatedL10n.screenNativeCallAudioRouteIphone,
                                           kind: .receiver,
                                           isActive: activeOutputs.contains { $0.type == .builtInReceiver }))
        routes.append(NativeCallAudioRoute(id: NativeCallAudioRoute.speakerID,
                                           name: UntranslatedL10n.screenNativeCallAudioRouteSpeaker,
                                           kind: .speaker,
                                           isActive: activeOutputs.contains { $0.type == .builtInSpeaker }))
        return routes
    }
}

/// Where a call's sound starts, and the pocket interpreter's one move (OPEN_QUESTIONS 407). Pure, like the route list.
enum NativeCallSpeakerPolicy {
    /// A video call starts on the loudspeaker, and so does a call with one's own assistant: a voice assistant is
    /// talked to with the phone away from the ear. Headphones, Bluetooth or a car keep the sound.
    static func startsOnSpeaker(media: NativeCallMedia, scope: NativeCallScope, hasExternalRoute: Bool) -> Bool {
        !hasExternalRoute && (media == .video || scope == .assistant)
    }

    /// Whether the speaker survives the session's activation: one that came from the default, not from the person,
    /// gives way to an external route found there (a car kit the start couldn't see yet).
    static func keepsSpeakerAtActivation(isSpeakerEnabled: Bool, isDefaulted: Bool, hasExternalRoute: Bool) -> Bool {
        isSpeakerEnabled && !(isDefaulted && hasExternalRoute)
    }

    /// The interpreter's start brings the call off the earpiece, so the person beside you hears the translation;
    /// headphones, Bluetooth or a car connected keep it.
    static func interpreterMovesToSpeaker(isSpeakerEnabled: Bool, hasExternalRoute: Bool) -> Bool {
        !isSpeakerEnabled && !hasExternalRoute
    }

    /// What a device coming or going does to the call's route.
    enum DeviceChange: Equatable {
        /// The call follows the output the system chose.
        case follows(speaker: Bool)
        /// The device went, and the call goes back to the loudspeaker over the earpiece the system chose.
        case returnsToSpeaker
    }

    /// A device came or went (AirPods, a car): the system chose the output, and the call follows it. Nil for any other
    /// route change, our own overrides included. One exception (operator, 2026-11-12): when the device goes, a call that
    /// returns to the speaker (`NativeCallSpeakerRegister.returnsToSpeaker`) gets it back over the system's earpiece,
    /// unless another external device carries the call. What carries it is the output, not a listed input: AirPods
    /// taken out of the ears stay connected, and stay an available hands-free input, while the call is on the receiver.
    static func routeAfterDeviceChange(reason: AVAudioSession.RouteChangeReason,
                                       activeOutputs: [NativeCallAudioPort],
                                       returnsToSpeaker: Bool) -> DeviceChange? {
        let speakerIsOutput = activeOutputs.contains { $0.type == .builtInSpeaker }
        switch reason {
        case .newDeviceAvailable:
            return .follows(speaker: speakerIsOutput)
        case .oldDeviceUnavailable:
            let hasExternalOutput = NativeCallAudioRoutes.hasExternalOutput(activeOutputs: activeOutputs)
            return returnsToSpeaker && !hasExternalOutput ? .returnsToSpeaker : .follows(speaker: speakerIsOutput)
        default:
            return nil
        }
    }
}

/// Each call's own speaker (question 407). A call on hold keeps its route, the call that resumes gets its own back —
/// never what the last call left — and the call in use is the only one a pick, a default or a device changes. Pure,
/// like the ownership register: `AVAudioSession` can't run the decisions in a test.
struct NativeCallSpeakerRegister {
    struct State: Equatable {
        var isEnabled = false
        /// From a default (the start's, a camera's), not from the person: an external route takes it.
        var isDefaulted = false
    }

    private var states: [NativeCallAudioOwner: State] = [:]
    /// Calls with one's own assistant: the loudspeaker is where they go back to when a device goes.
    private var assistantCalls: Set<NativeCallAudioOwner> = []
    /// Calls in which the person picked the earpiece. Sticky until they pick the speaker: picking AirPods afterwards
    /// doesn't undo it, so a call taken off the speaker on purpose never comes back to it by itself.
    private var earpiecePicks: Set<NativeCallAudioOwner> = []
    /// The call whose route is in use.
    private(set) var current: NativeCallAudioOwner?

    var isSpeakerEnabled: Bool {
        state(for: current).isEnabled
    }

    func state(for owner: NativeCallAudioOwner?) -> State {
        owner.flatMap { states[$0] } ?? State()
    }

    /// A call starts, and its route is the one in use.
    mutating func start(_ owner: NativeCallAudioOwner, onSpeaker: Bool, isAssistantCall: Bool = false) {
        current = owner
        states[owner] = State(isEnabled: onSpeaker, isDefaulted: onSpeaker)
        if isAssistantCall {
            assistantCalls.insert(owner)
        }
    }

    /// Whether the call in use goes back to the loudspeaker when a device goes (operator, 2026-11-12): a voice call with
    /// one's own assistant, unless the person picked the earpiece in it. A video call keeps following the system.
    func returnsToSpeaker(isVideo: Bool) -> Bool {
        guard let current, !isVideo else { return false }
        return assistantCalls.contains(current) && !earpiecePicks.contains(current)
    }

    /// A held call comes back with its own route.
    mutating func resume(_ owner: NativeCallAudioOwner) {
        current = owner
    }

    /// The person's pick of the speaker or the earpiece, or the interpreter's move, on the call in use.
    mutating func choose(_ isEnabled: Bool) {
        guard let current else { return }
        states[current] = State(isEnabled: isEnabled, isDefaulted: false)
        if isEnabled {
            earpiecePicks.remove(current)
        } else {
            earpiecePicks.insert(current)
        }
    }

    /// The person's pick of an external device (AirPods, a car) on the call in use. Not an earpiece pick.
    mutating func chooseExternal() {
        guard let current else { return }
        states[current] = State(isEnabled: false, isDefaulted: false)
    }

    /// A camera turned on puts the call in use on the speaker, as a default.
    mutating func applyVideoDefault() {
        guard let current else { return }
        states[current] = State(isEnabled: true, isDefaulted: true)
    }

    /// The session (re)activated: a default speaker gives way to an external route found there. True when it did.
    mutating func settle(hasExternalRoute: Bool) -> Bool {
        guard let current, let state = states[current], state.isEnabled,
              !NativeCallSpeakerPolicy.keepsSpeakerAtActivation(isSpeakerEnabled: state.isEnabled,
                                                                isDefaulted: state.isDefaulted,
                                                                hasExternalRoute: hasExternalRoute) else { return false }
        states[current] = State()
        return true
    }

    /// A device came or went and the system chose the output. True when the call's route changed. Going back to the
    /// speaker is a default, so a car or headphones found at the next activation still take it.
    mutating func follow(_ change: NativeCallSpeakerPolicy.DeviceChange) -> Bool {
        guard let current else { return false }
        let new = switch change {
        case .follows(let speaker):
            State(isEnabled: speaker, isDefaulted: false)
        case .returnsToSpeaker:
            State(isEnabled: true, isDefaulted: true)
        }
        // A speaker the call already has stays as it is, the person's included: only a change of output is the device's.
        guard state(for: current).isEnabled != new.isEnabled else { return false }
        states[current] = new
        return true
    }

    /// What a call had before its hold, back after it — only over a default that changed it meanwhile (a camera turned
    /// back on), never over the person's pick or a default that gave way to an external route. True when restored.
    mutating func restore(_ saved: State, for owner: NativeCallAudioOwner) -> Bool {
        guard let state = states[owner], state != saved, state.isDefaulted else { return false }
        states[owner] = saved
        return true
    }

    mutating func release(_ owner: NativeCallAudioOwner) {
        states[owner] = nil
        assistantCalls.remove(owner)
        earpiecePicks.remove(owner)
        if current == owner {
            current = nil
        }
    }
}

/// The call screen's hold on the route, behind a seam: `AVAudioSession` can't be driven from a test, and a preview
/// must not read the Mac's headphones into its snapshot.
struct NativeCallAudioRouting {
    var availableRoutes: () -> [NativeCallAudioRoute]
    /// Headphones, Bluetooth or a car connected, read under the call's category (a hands-free-only device shows there only).
    var hasExternalRoute: () -> Bool
    var setSpeakerEnabled: (Bool) -> Void
    var selectRoute: (String) -> Void
    /// A device came or went: the call's speaker follows the output the system chose.
    var followRouteChange: (AVAudioSession.RouteChangeReason) -> Void
    /// The speaker of the call in use, whenever anything but the screen changes it: a call's start or resume, a default
    /// giving way at activation, a device.
    var speakerChanges: AnyPublisher<Bool, Never>

    static let system = NativeCallAudioRouting(availableRoutes: { NativeCallAudio.availableRoutes },
                                               hasExternalRoute: { NativeCallAudio.hasExternalRouteForCall },
                                               setSpeakerEnabled: { NativeCallAudio.setSpeakerEnabled($0) },
                                               selectRoute: { NativeCallAudio.selectRoute(id: $0) },
                                               followRouteChange: { NativeCallAudio.followRouteChange(reason: $0) },
                                               speakerChanges: NativeCallAudio.speakerChanges.eraseToAnyPublisher())

    /// The phone's two outputs and nothing plugged in; it routes nothing.
    static let inert = NativeCallAudioRouting(availableRoutes: { NativeCallAudioRoutes.build(activeOutputs: [], availableInputs: []) },
                                              hasExternalRoute: { false },
                                              setSpeakerEnabled: { _ in },
                                              selectRoute: { _ in },
                                              followRouteChange: { _ in },
                                              speakerChanges: Empty().eraseToAnyPublisher())
}

/// One holder of the call audio. Opaque on purpose: only a claim mints one, so
/// nothing can release audio it never took, and two holders never collide.
nonisolated struct NativeCallAudioOwner: Hashable {
    // periphery:ignore - used via the synthesized Hashable conformance
    fileprivate let id: UInt64
}

/// The ownership register — pure, and separate for the same reason the route
/// builder is: `AVAudioSession` and LiveKit's `AudioManager` cannot be
/// exercised in a test, but the rule deciding whose teardown runs can.
///
/// Everything the release below touches is process-wide, and the holders
/// OVERLAP in both directions:
///
///   * a `NativeCallSession` teardown is slow — up to 1.8 s of busy cadence
///     plus the Matrix leave and the transport disconnect — so the next call
///     routinely claims before the previous one has released;
///   * a call claims BEFORE it joins, so a start that fails releases while the
///     call it overlapped with is still connected;
///   * `CallKitService` holds the CallKit-activation window across the gap
///     between fulfilling an action and a session existing at all.
///
/// A newest-wins generation counter only closes the first case; in the second
/// it lets a dead call's release park a live call's engine, drop its speaker
/// route and hand the session back to the SDK. Counting holders closes all of
/// them: the teardown runs when the LAST holder lets go, and never before.
nonisolated struct NativeCallAudioOwnership {
    /// What a release means for the audio itself.
    enum Release: Equatable {
        /// The last holder let go — the audio teardown runs now.
        case teardown
        /// Someone else is still on this audio and it must survive untouched.
        case stillHeld(owners: Int)
        /// This token holds nothing: it released already, or the register was
        /// reset under it. Either way the teardown is not this caller's to run.
        case alreadyReleased
    }

    private var lastID: UInt64 = 0
    private var owners: Set<NativeCallAudioOwner> = []

    var isHeld: Bool {
        !owners.isEmpty
    }

    mutating func claim() -> NativeCallAudioOwner {
        lastID += 1
        let owner = NativeCallAudioOwner(id: lastID)
        owners.insert(owner)
        return owner
    }

    mutating func release(_ owner: NativeCallAudioOwner) -> Release {
        guard owners.remove(owner) != nil else { return .alreadyReleased }
        return owners.isEmpty ? .teardown : .stillHeld(owners: owners.count)
    }
}

/// Whether a call currently owns the process-wide audio session.
///
/// Separate from the register above because that one is `@MainActor` and the
/// app's two other audio users are not: voice message playback and recording
/// configure the shared `AVAudioSession` from their own queues. Without
/// something they can ask, they reconfigure it out from under a live call —
/// `.playback` has no input, so the microphone dies, and their matching
/// `setActive(false)` kills the call outright. `NativeCallAudio.isSessionActive`
/// still reads `true` afterwards, so the fail-open recovery refuses to run and
/// the call is silent for the rest of its life.
nonisolated enum NativeCallAudioSession {
    private static let heldByCall = Mutex(false)

    /// True while a call holds the session. Other audio users must leave the
    /// category and the active flag alone; playback still works, because a
    /// call session is `.playAndRecord`.
    static var isHeldByCall: Bool {
        heldByCall.withLock { $0 }
    }

    static func setHeldByCall(_ isHeld: Bool) {
        heldByCall.withLock { $0 = isHeld }
    }
}

@MainActor
enum NativeCallAudio {
    /// A video call routes to the speaker and uses the video mode: holding a
    /// phone to your ear while looking at it is not a thing, and `.videoChat`
    /// is what tells the system this session carries a camera. Set BEFORE
    /// `prepareForCallKit`, because CallKit activates whatever is configured
    /// at fulfil time and automatic configuration is off.
    private static var isVideoEnabled = false

    /// Video live on the call in use. A call that isn't in use (one being held while another starts) changes nothing:
    /// the mode and the speaker are the call in use's.
    static func setVideoEnabled(_ enabled: Bool, owner: NativeCallAudioOwner?) {
        guard owner != nil, owner == speakers.current, enabled != isVideoEnabled else { return }
        isVideoEnabled = enabled

        if enabled, !hasExternalOutput {
            updateSpeakers { $0.applyVideoDefault() }
        }

        configureAudioSession()
        guard isSessionActive else { return }
        applyOutputRoute()
    }

    /// Hand audio-session control to CallKit, park the media engine, and take
    /// a share of the audio for this call. The returned token is the only thing
    /// that can give it back — see `NativeCallAudioOwnership`.
    ///
    /// The video mode and the speaker go in first: CallKit activates whatever is configured at fulfil time. A video
    /// call and a call with one's own assistant start on the speaker, unless headphones, Bluetooth or a car are
    /// there (question 407), read under the call's category so a hands-free-only device counts.
    static func prepareForCallKit(media: NativeCallMedia, scope: NativeCallScope) -> NativeCallAudioOwner {
        // The outgoing owner's cue belongs to a call that is over, and its own
        // release can no longer stop it: a busy cadence loops forever, and a
        // tone deferred until activation would otherwise fire on THIS call.
        stopTone()

        isVideoEnabled = media == .video
        configureAudioSession()
        let startsOnSpeaker = NativeCallSpeakerPolicy.startsOnSpeaker(media: media, scope: scope, hasExternalRoute: hasExternalRoute)
        MXLog.info("The call starts on the \(startsOnSpeaker ? "loudspeaker" : "default route")")
        return claimForCallKitActivation(startsOnSpeaker: startsOnSpeaker, isAssistantCall: scope == .assistant)
    }

    /// A held call comes back: its own mode and its own speaker, never what the call before it left.
    static func resume(owner: NativeCallAudioOwner?, isVideoEnabled isVideo: Bool) {
        guard let owner else { return }
        updateSpeakers { $0.resume(owner) }
        if isVideo != isVideoEnabled {
            isVideoEnabled = isVideo
            configureAudioSession()
        }
        resumeEngineIfSessionActive()
    }

    /// What a call's route was before its hold — `restoreSpeaker` puts it back after one.
    static func speakerState(for owner: NativeCallAudioOwner?) -> NativeCallSpeakerRegister.State {
        speakers.state(for: owner)
    }

    static func isSpeakerEnabled(for owner: NativeCallAudioOwner?) -> Bool {
        speakers.state(for: owner).isEnabled
    }

    /// The route a call had before its hold, back over a default that changed it meanwhile (a camera turned back on).
    static func restoreSpeaker(_ saved: NativeCallSpeakerRegister.State, owner: NativeCallAudioOwner?) {
        guard let owner else { return }
        var isRestored = false
        updateSpeakers { isRestored = $0.restore(saved, for: owner) }
        guard isRestored, owner == speakers.current, isSessionActive else { return }
        applyActivatedRoute()
    }

    /// The same hand-over for a CallKit action that fulfils OUTSIDE the owning
    /// session: CallKit activates whatever category is set at fulfil time, and
    /// on an answered incoming call that moment precedes the session entirely.
    ///
    /// The caller holds the returned token for that window and must release it.
    /// Configuring with nothing to release is what left automatic configuration
    /// disabled for the rest of the process whenever an answered call never
    /// reached a session, and every later call then came up with no
    /// microphone.
    ///
    /// Unlike `prepareForCallKit` the tones are left alone: an outgoing call
    /// requests its `CXStartCallAction` while its own ringback is playing.
    static func configureForCallKitActivation() -> NativeCallAudioOwner {
        claimForCallKitActivation(startsOnSpeaker: nil)
    }

    /// `startsOnSpeaker` is a starting call's route, in use from now; nil keeps the route in use (an answer's window).
    private static func claimForCallKitActivation(startsOnSpeaker: Bool?, isAssistantCall: Bool = false) -> NativeCallAudioOwner {
        let owner = ownership.claim()
        if let startsOnSpeaker {
            updateSpeakers { $0.start(owner, onSpeaker: startsOnSpeaker, isAssistantCall: isAssistantCall) }
        }
        NativeCallAudioSession.setHeldByCall(true)

        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false

        // With automatic configuration off nobody else sets the category, and
        // CallKit activates whatever category the app configured. Without
        // `.playAndRecord` the engine comes up with no microphone and the call
        // connects silent.
        configureAudioSession()

        if isSessionActive {
            setEngineAvailability(.default)
            applyActivatedRoute()
            logAudioRoute()
        } else {
            setEngineAvailability(.none)
        }

        return owner
    }

    private static var ownership = NativeCallAudioOwnership()

    /// While an outgoing call is ringing the media engine stays parked even
    /// inside an active CallKit session: the voice-processing unit would
    /// silence the ringback tone and there is no media to carry yet.
    static var isRingbackActive = false {
        didSet {
            // Same-value writes happen on every state change (`updateTones`);
            // acting on them re-armed the engine a hang-up had just parked.
            guard oldValue != isRingbackActive, !isRingbackActive, isSessionActive else { return }
            setEngineAvailability(.default)
            applyActivatedRoute()
        }
    }

    /// The hang-up point: park the media engine BEFORE the end cue and
    /// BEFORE the transport pulls its tracks. Two audible defects lived in
    /// the old order (engine parked only after the transport was gone): the
    /// voice-processing unit ducked the end cue the way it silences the
    /// ringback — the reason `isRingbackActive` parks it — and it was still
    /// running while the tracks went away underneath it, so its
    /// reconfiguration and then the session deactivation racing its
    /// teardown were what crackled after the call. Operator report
    /// 2026-09-07. A call that is on hold behind another must not do this:
    /// the engine is the other call's.
    static func parkEngineForHangUp() {
        setEngineAvailability(.none)
    }

    /// A held call coming back needs the engine it lost when the call in
    /// front of it hung up (see `parkEngineForHangUp`). CallKit's
    /// re-activation does this on a device; without CallKit (the simulator,
    /// the fail-open path) the session never deactivated, so nothing else
    /// would.
    private static func resumeEngineIfSessionActive() {
        guard isSessionActive, !isRingbackActive else { return }
        setEngineAvailability(.default)
        applyActivatedRoute()
    }

    /// Called from `CXProviderDelegate.provider(_:didActivate:)`.
    static func callKitDidActivate() {
        isSessionActive = true
        isActivatedByCallKit = true
        allowHapticsDuringCall()

        if !isRingbackActive {
            setEngineAvailability(.default)
        }

        applyActivatedRoute()
        logAudioRoute()
        startPendingToneIfNeeded()
    }

    /// Called from `CXProviderDelegate.provider(_:didDeactivate:)`.
    static func callKitDidDeactivate() {
        isSessionActive = false
        tonePlayer.stop()
        setEngineAvailability(.none)
    }

    // MARK: Tones

    /// Play a call tone, deferring it until the session is activated when
    /// CallKit has not handed the audio over yet.
    static func playTone(_ tone: NativeCallTone) {
        guard isSessionActive else {
            MXLog.info("Deferring the \(tone) tone until the audio session activates")
            pendingTone = tone
            return
        }

        pendingTone = nil
        tonePlayer.play(tone)
    }

    static func stopTone() {
        pendingTone = nil
        tonePlayer.stop()
    }

    private static let tonePlayer = NativeCallTonePlayer()
    private static var pendingTone: NativeCallTone?

    private static func startPendingToneIfNeeded() {
        guard let tone = pendingTone else { return }
        pendingTone = nil
        tonePlayer.play(tone)
    }

    /// Start the media engine when CallKit has not activated the session.
    ///
    /// The Simulator never delivers `didActivate`, and on a device the
    /// activation can be lost if the CallKit call fails to start. Waiting
    /// forever would leave a connected call permanently silent, so this fails
    /// open: the call gets audio, it just loses the CallKit guarantees until
    /// the system hands the session over.
    static func activateWithoutCallKitIfNeeded() {
        guard !isSessionActive else { return }

        MXLog.warning("CallKit did not activate the audio session, starting audio directly")

        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // A session that refused to activate carries nothing. Claiming it
            // anyway un-parks the engine into silence, burns the pending tone
            // and makes every later `isSessionActive` branch — including the
            // deactivation in `releaseAfterCallKit` — act on a session we were
            // never handed. Staying inactive keeps the retries meaningful: a
            // later CallKit activation, or the next resume, still recovers.
            MXLog.error("Failed activating the call audio session: \(error)")
            return
        }

        isSessionActive = true
        isActivatedByCallKit = false
        allowHapticsDuringCall()

        if !isRingbackActive {
            setEngineAvailability(.default)
        }

        applyActivatedRoute()
        logAudioRoute()
        startPendingToneIfNeeded()
    }

    /// Restore the SDK's own audio handling once the LAST holder has let go.
    ///
    /// Keyed by the token the claim handed out and counted, because holders
    /// overlap in both directions (see `NativeCallAudioOwnership`): a call the
    /// user has already replaced must not park the engine, drop the speaker
    /// route or give the session back to the SDK underneath the call that
    /// replaced it — and a call whose start failed must not do it underneath
    /// the call that is still connected.
    static func releaseAfterCallKit(owner: NativeCallAudioOwner) {
        // This call's route goes with it, whoever else still holds the audio.
        updateSpeakers { $0.release(owner) }
        switch ownership.release(owner) {
        case .stillHeld(let owners):
            MXLog.info("Keeping the call audio session, \(owners) other holder(s) still have it")
            return
        case .alreadyReleased:
            MXLog.info("Ignoring a call audio release, this holder has already released it")
            return
        case .teardown:
            break
        }

        isVideoEnabled = false
        stopTone()
        setEngineAvailability(.none)

        if isSessionActive {
            isSessionActive = false
            // A session CallKit activated is CallKit's to deactivate: it does
            // so once the end action settles and tells us in `didDeactivate`.
            // Deactivating it ourselves first, from under a call the system
            // still holds, is a second teardown racing the first — audible
            // on a device as a crackle after the end cue (operator,
            // 2026-09-07), never on the simulator, which has no CallKit
            // activation to race.
            if !isActivatedByCallKit {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
        isActivatedByCallKit = false

        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = true
        NativeCallAudioSession.setHeldByCall(false)
    }

    /// Whether the audio session is currently active for a call.
    private static var isSessionActive = false
    /// Whether that activation was CallKit's (a device) rather than our own
    /// fail-open one (the simulator, a lost activation).
    private static var isActivatedByCallKit = false

    /// A silent call is almost always a routing problem rather than a media one,
    /// so the port the session ended up on is worth recording.
    private static func logAudioRoute() {
        let route = AVAudioSession.sharedInstance().currentRoute
        let outputs = route.outputs.map(\.portType.rawValue).joined(separator: ", ")
        let inputs = route.inputs.map(\.portType.rawValue).joined(separator: ", ")
        MXLog.info("Call audio route: outputs [\(outputs)], inputs [\(inputs)]")
    }

    static func setSpeakerEnabled(_ enabled: Bool) {
        updateSpeakers { $0.choose(enabled) }
        applyOutputRoute()
    }

    // MARK: Routes (G8)

    /// The selectable routes right now. Reads the same observation the
    /// route logging uses; the decision logic is the pure builder above.
    static var availableRoutes: [NativeCallAudioRoute] {
        let session = AVAudioSession.sharedInstance()
        return NativeCallAudioRoutes.build(activeOutputs: session.currentRoute.outputs.map(\.nativeCallPort),
                                           availableInputs: (session.availableInputs ?? []).map(\.nativeCallPort))
    }

    /// Apply the user's pick. Invariant 4 holds: this only ever runs on the
    /// session CallKit activated (the picker is reachable from an active
    /// call screen alone), and it changes the ROUTE, never the session
    /// lifecycle.
    static func selectRoute(id: String) {
        let session = AVAudioSession.sharedInstance()
        switch id {
        case NativeCallAudioRoute.speakerID:
            setSpeakerEnabled(true)
        case NativeCallAudioRoute.receiverID:
            updateSpeakers { $0.choose(false) }
            if let builtInMicrophone = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtInMicrophone)
            }
            applyOutputRoute()
        default:
            updateSpeakers { $0.chooseExternal() }
            if let port = session.availableInputs?.first(where: { $0.uid == id }) {
                do {
                    try session.setPreferredInput(port)
                } catch {
                    MXLog.error("Failed selecting the \(port.portName) audio route: \(error)")
                }
            }
            applyOutputRoute()
        }
        logAudioRoute()
    }

    /// Each call's speaker, remembered across activations and holds (question 407).
    private static var speakers = NativeCallSpeakerRegister()
    static let speakerChanges = PassthroughSubject<Bool, Never>()

    /// The output port the call in use should use.
    static var isSpeakerEnabled: Bool {
        speakers.isSpeakerEnabled
    }

    /// The one writer of the register: the screen hears every change of the speaker in use.
    private static func updateSpeakers(_ change: (inout NativeCallSpeakerRegister) -> Void) {
        let wasEnabled = speakers.isSpeakerEnabled
        change(&speakers)
        if speakers.isSpeakerEnabled != wasEnabled {
            speakerChanges.send(speakers.isSpeakerEnabled)
        }
    }

    /// A device came or went: the call in use follows the output the system chose for it — or, when the device went
    /// from a call with one's own assistant, goes back to the loudspeaker (operator, 2026-11-12). The screen of a held
    /// call doesn't ask: it waits for its resume.
    static func followRouteChange(reason: AVAudioSession.RouteChangeReason) {
        guard isSessionActive else { return }
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.nativeCallPort)
        guard let change = NativeCallSpeakerPolicy.routeAfterDeviceChange(reason: reason,
                                                                          activeOutputs: outputs,
                                                                          returnsToSpeaker: speakers.returnsToSpeaker(isVideo: isVideoEnabled)) else { return }
        var didChange = false
        updateSpeakers { didChange = $0.follow(change) }
        switch change {
        case .returnsToSpeaker:
            // The system put the call on the earpiece; the override is ours to re-assert.
            MXLog.info("A device went from a call with one's own assistant; back to the loudspeaker")
            applyOutputRoute()
        case .follows(let speaker):
            if didChange {
                MXLog.info("A device changed the call's route; the speaker follows it: \(speaker)")
            }
        }
    }

    static var hasExternalOutput: Bool {
        NativeCallAudioRoutes.hasExternalOutput(activeOutputs: AVAudioSession.sharedInstance().currentRoute.outputs.map(\.nativeCallPort))
    }

    /// The screen's read, before its call may have started: the call's category goes in first when no call holds the
    /// session yet, so the first frame sees a hands-free-only device as the start will.
    static var hasExternalRouteForCall: Bool {
        if !NativeCallAudioSession.isHeldByCall {
            configureAudioSession()
        }
        return hasExternalRoute
    }

    static var hasExternalRoute: Bool {
        let session = AVAudioSession.sharedInstance()
        return NativeCallAudioRoutes.hasExternalRoute(activeOutputs: session.currentRoute.outputs.map(\.nativeCallPort),
                                                      availableInputs: (session.availableInputs ?? []).map(\.nativeCallPort))
    }

    private static func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord,
                                                            mode: isVideoEnabled ? .videoChat : .voiceChat,
                                                            options: [.allowBluetoothHFP, .allowBluetoothA2DP])
        } catch {
            MXLog.error("Failed configuring the call audio session category: \(error)")
        }
        allowHapticsDuringCall()
    }

    /// iOS mutes haptics while the microphone records: the call's taps (connected, the capsule's events) need this,
    /// set with the category and again on every activation (operator, 2026-11-12).
    private static func allowHapticsDuringCall() {
        do {
            try AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
        } catch {
            MXLog.error("Failed allowing haptics during the call: \(error)")
        }
    }

    /// The route on a session that has just (re)activated. A default speaker gives way to an external route that only
    /// showed up now: overriding to the speaker would pull a call in the car onto the phone.
    private static func applyActivatedRoute() {
        var didGiveWay = false
        updateSpeakers { didGiveWay = $0.settle(hasExternalRoute: hasExternalRoute) }
        if didGiveWay {
            MXLog.info("An external route is there at activation; the default speaker gives way")
        }
        applyOutputRoute()
    }

    /// Route overrides only apply to the session that is currently active and
    /// are dropped when it is activated, so a route chosen before the hand-over
    /// has to be re-asserted afterwards.
    private static func applyOutputRoute() {
        // With automatic configuration disabled the SDK no longer overrides the
        // port, so the route is set directly on the session CallKit activated.
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(isSpeakerEnabled ? .speaker : .none)
        } catch {
            MXLog.error("Failed changing the call audio route: \(error)")
        }
    }

    /// Whether the last availability asked of the engine let it run — what
    /// a test can read, since `AudioManager` itself cannot be observed from one.
    private(set) static var isEngineAvailable = false

    private static func setEngineAvailability(_ availability: AudioEngineAvailability) {
        isEngineAvailable = availability.isInputAvailable || availability.isOutputAvailable
        do {
            try AudioManager.shared.setEngineAvailability(availability)
        } catch {
            MXLog.error("Failed changing the call audio engine availability: \(error)")
        }
    }
}

/// Everything `CallKitService` does to the process-wide call audio, behind
/// one seam. A seam rather than direct calls because LiveKit's `AudioManager`
/// and `AVAudioSession` cannot run inside a unit-test process, while the
/// decisions on the service's side — who holds the CallKit-activation window,
/// and which deactivation belongs to the native stack — are exactly what has to
/// be tested.
protocol NativeCallAudioControlling {
    func claimActivationWindow() -> NativeCallAudioOwner
    func releaseActivationWindow(_ owner: NativeCallAudioOwner)
    func callKitDidActivate(_ audioSession: AVAudioSession)
    func callKitDidDeactivate(_ audioSession: AVAudioSession)
}

struct NativeCallAudioControl: NativeCallAudioControlling {
    func claimActivationWindow() -> NativeCallAudioOwner {
        NativeCallAudio.configureForCallKitActivation()
    }

    func releaseActivationWindow(_ owner: NativeCallAudioOwner) {
        NativeCallAudio.releaseAfterCallKit(owner: owner)
    }

    func callKitDidActivate(_ audioSession: AVAudioSession) {
        NativeCallAudio.callKitDidActivate()
    }

    func callKitDidDeactivate(_ audioSession: AVAudioSession) {
        NativeCallAudio.callKitDidDeactivate()
    }
}

/// Real tokens, no audio. Touching `AudioManager` from a unit-test process
/// takes the run down with it, so the ownership half stays exact while the
/// hardware half is left alone.
final class InertNativeCallAudioControl: NativeCallAudioControlling {
    private var ownership = NativeCallAudioOwnership()

    func claimActivationWindow() -> NativeCallAudioOwner {
        ownership.claim()
    }

    func releaseActivationWindow(_ owner: NativeCallAudioOwner) {
        _ = ownership.release(owner)
    }

    func callKitDidActivate(_ audioSession: AVAudioSession) { }

    func callKitDidDeactivate(_ audioSession: AVAudioSession) { }
}

private extension AVAudioSessionPortDescription {
    nonisolated var nativeCallPort: NativeCallAudioPort {
        NativeCallAudioPort(type: portType, name: portName, uid: uid)
    }
}
