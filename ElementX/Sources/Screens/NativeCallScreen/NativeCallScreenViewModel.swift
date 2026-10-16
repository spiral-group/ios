//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation
import Combine
import SwiftUI

// AGENT-PLATFORM (Brief 0063)

typealias NativeCallScreenViewModelType = StateStoreViewModel<NativeCallScreenViewState, NativeCallScreenViewAction>

class NativeCallScreenViewModel: NativeCallScreenViewModelType, NativeCallScreenViewModelProtocol {
    private let session: NativeCallSession
    private let callKitService: CallKitServiceProtocol
    private let agentCenter: NativeAgentCenterController
    private let roomID: String
    /// The CallKit call this screen ends when it stops: the one it was
    /// opened for, then the one it registered (follow-up N1). By room alone
    /// its late teardown took whatever call the room had by then.
    private(set) var callKitID: UUID?
    /// Set by `stop()`: this screen's call is ending, and a registration
    /// from now on is of an ending call.
    private var isStopping = false

    var hasCallEnded: Bool {
        if case .ended = state.callState { return true }
        return isStopping
    }

    private let appMediator: AppMediatorProtocol
    /// When the call first connected — the ended state shows how long it
    /// ran (`18 · Call states`).
    private var connectedAt: Date?
    private var subscriptions = Set<AnyCancellable>()
    /// AGENT-PLATFORM (Brief 0067 follow-up, 2026-09-06): whether this
    /// screen currently holds the system idle timer. The WebView call kept
    /// the screen awake as a side effect of WebRTC video; the native stack
    /// has no such side effect, so a video call dimmed and LOCKED the phone
    /// on the system timeout — iOS then stops the camera of a backgrounded
    /// app and the peer lost the picture. Held while video is live on a
    /// call that has not ended; released on every exit, because a flag left
    /// standing is the opposite bug (a screen that never sleeps).
    private var isHoldingIdleTimer = false

    private let actionsSubject: PassthroughSubject<NativeCallScreenViewModelAction, Never> = .init()
    var actions: AnyPublisher<NativeCallScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    /// Brief 0068 Slice 3 — the tap you feel when the call connects and
    /// when it ends: the Phone app's cue, missing from ours. Injected so
    /// tests read it and previews stay silent.
    private let haptics: NativeCallHaptics

    init(session: NativeCallSession,
         callKitService: CallKitServiceProtocol,
         agentCenter: NativeAgentCenterController,
         appMediator: AppMediatorProtocol,
         haptics: NativeCallHaptics = .system,
         mediaProvider: MediaProviderProtocol? = nil,
         isVideoCall: Bool,
         roomID: String,
         roomName: String,
         scope: NativeCallScope = .direct,
         roomAvatar: RoomAvatar = .room(id: "", name: nil, avatarURL: nil),
         memberProfiles: AnyPublisher<[String: NativeCallMemberProfile], Never> = Empty().eraseToAnyPublisher(),
         roomPresentation: AnyPublisher<NativeCallRoomPresentation, Never> = Empty().eraseToAnyPublisher()) {
        self.session = session
        self.callKitService = callKitService
        self.agentCenter = agentCenter
        self.appMediator = appMediator
        self.haptics = haptics
        self.roomID = roomID
        callKitID = callKitService.callKitID(forRoomID: roomID)

        super.init(initialViewState: NativeCallScreenViewState(roomName: roomName,
                                                               scope: scope,
                                                               roomAvatar: roomAvatar,
                                                               isRoomEncrypted: session.isRoomEncrypted,
                                                               // A video call comes up on the speaker.
                                                               isSpeakerEnabled: isVideoCall,
                                                               isVideoCall: isVideoCall),
                   mediaProvider: mediaProvider)

        session.delegate = self
        // An outgoing video call shows the local preview while connecting —
        // the screen must not dim on it either.
        refreshIdleTimer()

        // Brief 0068 Slice 2 — the parked call, for the pill. Only the ACTIVE
        // screen shows it: the parked screen sees its own room and hides it.
        callKitService.heldCallPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] held in
                guard let self else { return }
                state.heldCall = held?.roomID == roomID ? nil : held
            }
            .store(in: &subscriptions)

        agentCenter.snapshotPublisher
            .sink { [weak self] snapshot in
                self?.state.agentCenter = snapshot
            }
            .store(in: &subscriptions)

        // Phase 2 — Matrix member profiles (names + avatars) for the call
        // screens. Matrix-side truth, so it rides its own publisher instead
        // of the platform snapshot.
        memberProfiles
            .sink { [weak self] profiles in
                self?.state.memberProfiles = profiles
            }
            .store(in: &subscriptions)

        roomPresentation
            .sink { [weak self] presentation in
                self?.state.roomName = presentation.name
                self?.state.roomAvatar = presentation.avatar
            }
            .store(in: &subscriptions)

        // Phase 5 (G8) — AirPods arriving or a cable pulled while the route
        // sheet is up must re-render the list; the system already announces
        // every change.
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, state.bindings.isAudioRoutePickerPresented else { return }
                state.audioRoutes = NativeCallAudio.availableRoutes
            }
            .store(in: &subscriptions)

        // CallKit owns muting, so a mute performed from the system UI has to
        // reach the media stack the same way the in-app button does.
        callKitService.actions
            .sink { [weak self] action in
                guard let self else { return }

                switch action {
                case .setAudioEnabled(let enabled, let roomID, let reply) where roomID == self.roomID:
                    // CallKit fulfils its action on this answer, so a refusal
                    // has to travel all the way back rather than be dropped.
                    Task {
                        let succeeded = await self.setMicrophoneEnabled(enabled)
                        reply.send(succeeded)
                    }
                case .setCallHeld(let isHeld, let roomID) where roomID == self.roomID:
                    // Brief 0068 Slice 2: an outgoing call still RINGING
                    // cannot be held (its ringback would keep the engine
                    // parked and the other call silent). Answering someone
                    // else while you ring somebody is giving up on the ring.
                    if isHeld, case .ringing = state.callState {
                        MXLog.info("Held while ringing; ending the outgoing ring")
                        // The slot clears now, not after the session's stop:
                        // the new call's pill must not name this ring.
                        callKitService.tearDownCallSession(forRoomID: roomID, callKitID: callKitID)
                        actionsSubject.send(.dismiss)
                        return
                    }
                    session.setOnHold(isHeld)
                case .endCall(let roomID) where roomID == self.roomID:
                    actionsSubject.send(.dismiss)
                default:
                    break
                }
            }
            .store(in: &subscriptions)
    }

    func start() {
        Task {
            await session.start()
        }

        Task {
            await agentCenter.reload()
        }
    }

    func remoteDeclined() {
        Task {
            await session.remoteDeclined()
        }
    }

    func bind(toCallKitID callKitID: UUID) {
        self.callKitID = callKitID
    }

    func stop() {
        isStopping = true
        setIdleTimerHeld(false)
        // Over for the app now; CallKit keeps it until the teardown below.
        if let callKitID {
            callKitService.markCallEnding(callKitID: callKitID)
        }
        Task {
            await session.stop()
            callKitService.tearDownCallSession(forRoomID: roomID, callKitID: callKitID)
        }
    }

    isolated deinit {
        setIdleTimerHeld(false)
    }

    /// The single writer of the idle-timer flag for this screen.
    private func setIdleTimerHeld(_ held: Bool) {
        guard held != isHoldingIdleTimer else { return }
        isHoldingIdleTimer = held
        appMediator.setIdleTimerDisabled(held)
    }

    /// Video live on a call that is still going → the screen stays awake.
    private func refreshIdleTimer() {
        let callIsLive = switch state.callState {
        case .ended: false
        default: true
        }
        setIdleTimerHeld(state.isVideoCall && callIsLive)
    }

    override func process(viewAction: NativeCallScreenViewAction) {
        switch viewAction {
        case .swapCalls:
            callKitService.swapCalls()
        case .toggleMicrophone:
            Task { await toggleMicrophone() }
        case .toggleCamera:
            Task { await setCameraEnabled(!state.isCameraEnabled) }
        case .switchCamera:
            Task { await session.switchCamera() }
        case .toggleSpeaker:
            // G8 — with an external route in play (AirPods, a car) a binary
            // speaker flip cannot express the choice: the tap opens the
            // picker instead. With only the phone's two outputs the toggle
            // stays the fast path.
            let routes = NativeCallAudio.availableRoutes
            if routes.contains(where: { $0.kind == .external }) {
                state.audioRoutes = routes
                state.bindings.isAudioRoutePickerPresented = true
            } else {
                let enabled = !state.isSpeakerEnabled
                session.setSpeakerEnabled(enabled)
                state.isSpeakerEnabled = enabled
            }
        case .showAudioRoutes:
            // G8 — refresh at presentation time: the list is cheap and the
            // session's reality may have changed since the last look.
            state.audioRoutes = NativeCallAudio.availableRoutes
            state.bindings.isAudioRoutePickerPresented = true
        case .selectAudioRoute(let id):
            NativeCallAudio.selectRoute(id: id)
            state.isSpeakerEnabled = id == NativeCallAudioRoute.speakerID
            state.audioRoutes = NativeCallAudio.availableRoutes
            state.bindings.isAudioRoutePickerPresented = false
        case .setListeningChoice(let choice):
            session.setListeningChoice(choice)
        case .minimize:
            actionsSubject.send(.minimize)
        case .expand:
            actionsSubject.send(.expand)
        case .hangUp:
            actionsSubject.send(.dismiss)
        case .showAgentCenter:
            state.bindings.isAgentCenterPresented = true
            Task { await agentCenter.reload() }
        case .dismissAgentCenter:
            state.bindings.isAgentCenterPresented = false
            agentCenter.clearError()
        case .reloadAgentCenter:
            agentCenter.clearError()
            Task { await agentCenter.reload() }
        case .attachAgentConfigured(let agentID, let params):
            runAgentAction { await self.agentCenter.attach(agentID: agentID, params: params) }
        case .removeAgent(let sessionID):
            runAgentAction { await self.agentCenter.remove(sessionID: sessionID) }
        case .setAgentSwitch(let sessionID, let control, let enabled):
            runAgentAction { await self.agentCenter.setSwitch(sessionID: sessionID, control: control, enabled: enabled) }
        case .applyAgentTranslation(let sessionID, let params):
            runAgentAction { await self.agentCenter.setTranslation(sessionID: sessionID, params: params) }
        case .disableAgentTranslation(let sessionID):
            runAgentAction { await self.agentCenter.disableTranslation(sessionID: sessionID) }
        case .clearAgentTranslationOverride(let sessionID):
            runAgentAction { await self.agentCenter.clearTranslationOverride(sessionID: sessionID) }
        case .saveAgentTranslationAsRoomDefault(let sessionID):
            // The server says where the promotion can land (ADR-0088); unknown is no.
            guard state.agents.control(sessionID: sessionID)?.canSaveAsRoomDefault == true else {
                MXLog.warning("Ignoring a room-default save the server does not offer for \(sessionID)")
                return
            }
            runAgentAction { await self.agentCenter.saveTranslationAsRoomDefault(sessionID: sessionID) }
        case .attachAgentTranslateMe(let agentID, let language):
            let params = VoiceAttachParams(translation: .init(booths: [.init(speakerScope: VoiceSpeakerScope.ownerOnly.rawValue,
                                                                             speakerMembers: [],
                                                                             targetLanguages: [language])],
                                                              style: NativeCallTranslationStyleDefault.wire),
                                           recording: false,
                                           summary: false,
                                           conversation: false)
            runAgentAction { await self.agentCenter.attach(agentID: agentID, params: params) }
        }
    }

    // MARK: - Private

    /// Serialises Agent Center writes behind one in-flight flag so a
    /// double-tap cannot race two CAS writes against the same revision.
    ///
    /// Failure visibility: the controller reports every failed write into
    /// the snapshot (`lastError`, rendered by the sheet), so the discarded
    /// Bool here loses nothing the user was owed.
    private func runAgentAction(_ action: @escaping () async -> Bool) {
        guard !state.isAgentActionInFlight else {
            // Every surface that can send one of these is `.disabled` while
            // one is in flight, so this firing means some surface forgot
            // that rail. Loud, because the silent drop read as "the button
            // did nothing" with no trace anywhere (audit T5).
            MXLog.warning("Agent Center action arrived while another is in flight; dropping it")
            return
        }
        state.isAgentActionInFlight = true

        Task {
            _ = await action()
            state.isAgentActionInFlight = false
        }
    }

    /// The button does NOT write the mute state: a failed
    /// `setMicrophone` would then show "muted" while the microphone is
    /// still publishing — a privacy defect, not a cosmetic one. The
    /// derived transport snapshot (`didChangeParticipants`) is the single
    /// writer, so the control can only ever show what the engine does.
    ///
    /// The in-app button. CallKit carries the change when it can (the
    /// system UI and Recents show the mute state, and they must agree with
    /// the microphone — audit 2026-09-05, P2); it then comes back through
    /// `.setAudioEnabled` above. When CallKit will not carry it, the change
    /// is applied directly, as before.
    private func toggleMicrophone() async {
        let enabled = !state.isMicrophoneEnabled
        if await callKitService.requestAudioEnabled(enabled, roomID: roomID) {
            return
        }
        await setMicrophoneEnabled(enabled)
    }

    /// Returns whether the engine took the change, for the CallKit action
    /// waiting on it.
    @discardableResult
    private func setMicrophoneEnabled(_ enabled: Bool) async -> Bool {
        let succeeded = await session.setMicrophoneEnabled(enabled)
        // That snapshot only reaches the delegate when it CHANGES, and a
        // refused mute changes nothing — so re-read it here, or the control
        // keeps whatever the last successful change left on screen.
        if let local = session.participants.first(where: \.isLocal) {
            state.isMicrophoneEnabled = local.isAudioEnabled
        }
        return succeeded
    }

    /// Turning the camera ON asks for permission first: publishing without
    /// it fails inside the media engine, where the user sees nothing but a
    /// control that did not work.
    private func setCameraEnabled(_ enabled: Bool) async {
        if enabled, await !appMediator.requestAuthorizationIfNeeded() {
            // Phase 4 — the copy says what to do and the button goes there:
            // the control cannot work until Settings changes, so a plain
            // OK is a dead end.
            state.bindings.alertInfo = .init(id: .cameraDenied,
                                             title: UntranslatedL10n.screenNativeCallCameraDeniedTitle,
                                             message: UntranslatedL10n.screenNativeCallCameraDeniedMessage,
                                             primaryButton: .init(title: UntranslatedL10n.screenNativeCallCameraDeniedSettings) { [weak self] in
                                                 self?.appMediator.openAppSettings()
                                             },
                                             secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
            return
        }
        let succeeded = await session.setCameraEnabled(enabled)
        if enabled, !succeeded {
            // Permission was granted (checked above), so this is the engine
            // refusing — a busy device, a capture failure. Log-only left the
            // tapped control silently off (audit T3): the button stayed
            // honest (engine-derived) but the user got no word on why.
            state.bindings.alertInfo = .init(id: .cameraUnavailable,
                                             title: UntranslatedL10n.screenNativeCallCameraFailedTitle,
                                             message: UntranslatedL10n.screenNativeCallCameraFailedMessage)
        }
    }
}

// MARK: - NativeCallSessionDelegate

extension NativeCallScreenViewModel: NativeCallSessionDelegate {
    func nativeCallSessionDidDowngradeToAudio(_ session: NativeCallSession) {
        // The start-time twin of the engine refusal above: the user asked
        // for a VIDEO call and got audio — that sentence must be said, not
        // logged (audit T3).
        state.bindings.alertInfo = .init(id: .cameraUnavailable,
                                         title: UntranslatedL10n.screenNativeCallCameraFailedTitle,
                                         message: UntranslatedL10n.screenNativeCallCameraFailedMessage)
    }

    func nativeCallSession(_ session: NativeCallSession, didChangeState state: NativeCallSessionState) {
        switch state {
        case .connecting:
            self.state.callState = .connecting
        case .ringing:
            self.state.callState = .ringing
            // The CallKit call has to exist while ringing — it is what
            // activates the audio session — but it is reported as still
            // connecting so the system timer only starts on answer.
            Task { await setupCallKitSession() }
        case .connected:
            let wasRinging = self.state.callState == .ringing
            let wasReconnecting = self.state.callState == .reconnecting
            self.state.callState = .connected
            if connectedAt == nil {
                connectedAt = Date()
                self.state.callConnectedAt = connectedAt
                haptics.connected()
            }

            // Sessions may have been added, removed or reconfigured while we
            // were away, so backend truth is re-read rather than assumed.
            if wasReconnecting {
                Task { await agentCenter.reload() }
            }
            // CallKit is told about the call only once media is actually up, so
            // the system never shows an active call that cannot carry audio.
            Task {
                if wasRinging {
                    self.callKitService.reportOutgoingCallConnected(roomID: self.roomID)
                } else {
                    await self.setupCallKitSession()
                    self.callKitService.reportOutgoingCallConnected(roomID: self.roomID)
                }
            }
        case .onHold:
            self.state.callState = .onHold
        case .reconnecting:
            self.state.callState = .reconnecting
        case .ended(let reason):
            self.state.callState = .ended(status: Self.endedStatus(for: reason))
            self.state.endedCallDuration = connectedAt.flatMap { Self.durationFormatter.string(from: Date().timeIntervalSince($0)) }
            refreshIdleTimer()
            haptics.ended()

            switch reason {
            case .failed(let failure):
                self.state.bindings.alertInfo = AlertInfo(id: .callFailed,
                                                          title: UntranslatedL10n.screenNativeCallErrorTitle,
                                                          message: failure.localizedDescription,
                                                          primaryButton: .init(title: L10n.actionOk) { [weak self] in
                                                              self?.actionsSubject.send(.dismiss)
                                                          })
                // The alert is a courtesy for whoever is looking, not the only
                // exit (audit C8): while the call is minimized the full screen
                // is unmounted, nothing can present the alert, and `.failed`
                // used to be the ONE end reason with no self-dismissal — a
                // dead call's bar kept ticking and its CallKit call stayed up
                // until the user happened to tap. A slightly longer delay than
                // the other reasons so the message is readable when the screen
                // IS up.
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    self?.actionsSubject.send(.dismiss)
                }
            case .userHungUp:
                actionsSubject.send(.dismiss)
            case .remoteEnded, .declined, .unanswered, .connectionLost, .everyoneLeft:
                // Leave the outcome on screen long enough to read, the way
                // phone calls do.
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1.5))
                    self?.actionsSubject.send(.dismiss)
                }
            }
        }
    }

    private static func endedStatus(for reason: NativeCallEndReason) -> String {
        switch reason {
        case .userHungUp, .remoteEnded, .failed: UntranslatedL10n.screenNativeCallStatusEnded
        case .declined: UntranslatedL10n.screenNativeCallStatusDeclined
        case .unanswered: UntranslatedL10n.screenNativeCallStatusNoAnswer
        case .connectionLost: UntranslatedL10n.screenNativeCallStatusConnectionLost
        case .everyoneLeft: UntranslatedL10n.screenNativeCallStatusEveryoneLeft
        }
    }

    /// "24 min 18 s"-shaped, localized by the system formatter.
    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    func nativeCallSession(_ session: NativeCallSession, didChangeParticipants participants: [NativeCallParticipant]) {
        state.participants = participants

        if let local = participants.first(where: \.isLocal) {
            state.isMicrophoneEnabled = local.isAudioEnabled
            // Same single-writer rule as the microphone: the engine's own
            // state reaches the control, never the last request.
            state.isCameraEnabled = local.isVideoEnabled
        }
    }

    func nativeCallSession(_ session: NativeCallSession, didChangeVideoTiles tiles: [NativeCallVideoTile]) {
        state.videoTiles = tiles
    }

    func nativeCallSession(_ session: NativeCallSession, didChangeConnectionQuality quality: NativeCallConnectionQuality) {
        state.connectionQuality = quality
    }

    /// The agents' own documents are the live register (ADR-0071 D8); the
    /// panel's controls, catalogs and candidates are REST. A changed document
    /// is therefore the signal to re-read, replacing the `com.spiral.session`
    /// timeline doorbell — one source of truth, pushed to every device alike.
    func nativeCallSessionDidChangeAgentState(_ session: NativeCallSession) {
        Task { await agentCenter.reload() }
    }

    /// Phase 1 — the agent block's languages and wave. This is the agents'
    /// own claim plus the transport's speaking signal, so it reaches the
    /// view directly rather than waiting for the REST reload the doorbell
    /// above kicks off.
    func nativeCallSession(_ session: NativeCallSession, didChangeAgentClaims claims: NativeCallAgentClaims) {
        state.agentClaims = claims
        // The document caught up with the owner's taps: settle the
        // optimism it now confirms (or contradicts).
        agentCenter.settleOwnerWrites(against: claims)
    }

    func nativeCallSession(_ session: NativeCallSession,
                           didChangeActiveVideo hasActiveVideo: Bool,
                           isSpeakerEnabled: Bool) {
        // ONE call: "video" is not a kind, it is whether video is LIVE
        // right now. The dock's camera toggle upgrades an audio call, all
        // cameras going dark falls back to the avatar stage — the
        // Telegram model (operator decision 2026-08-21). The initial
        // value comes from the start intent so an outgoing video call
        // opens on the video stage before the transport connects.
        state.isVideoCall = hasActiveVideo
        state.isSpeakerEnabled = isSpeakerEnabled
        callKitService.updateCallVideoState(hasVideo: state.isVideoCall, callKitID: callKitID)
        refreshIdleTimer()
    }

    private func setupCallKitSession() async {
        // A stopped screen registers nothing: an ending call would take the
        // outgoing path and replace the calls that are live.
        guard !isStopping else { return }
        let openedFor = callKitID
        if let registered = await callKitService.setupCallSession(roomID: roomID,
                                                                  roomDisplayName: state.roomName,
                                                                  isVoiceCall: !state.isVideoCall,
                                                                  callKitID: openedFor) {
            callKitID = registered
            // The screen stopped while CallKit was registering.
            if isStopping {
                callKitService.markCallEnding(callKitID: registered)
            }
        } else if openedFor != nil {
            // The call this screen was opened for is gone (a newer accept
            // gave it up, question 93), so the screen goes too.
            MXLog.info("The call this screen was opened for is gone; dismissing it")
            actionsSubject.send(.dismiss)
            return
        }
        // An answered incoming call already owns its CallKit UUID, so the ring's
        // metadata — guessed from the push payload — is all the system has. This
        // also re-applies a kind that settled before the transaction completed.
        callKitService.updateCallVideoState(hasVideo: state.isVideoCall, callKitID: callKitID)
    }

    func nativeCallSession(_ session: NativeCallSession, didSendRingNotification eventID: String) {
        actionsSubject.send(.didSendRingNotification(eventID: eventID))
    }

    func nativeCallSession(_ session: NativeCallSession, didChangeListening listening: NativeCallListeningState) {
        state.listening = listening
    }
}
