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
    private let peerSettleDuration: Duration
    /// The peer's picture, slower to go than `videoTiles`: a brief drop is not their camera going off.
    private var isPeerPictureSettled = false
    @CancellableTask private var peerSettleTask: Task<Void, Never>?
    private var groupFocus = NativeCallGroupFocus()
    private var aiConsentCancellable: AnyCancellable?
    /// VoiceOver is running: the stage stays on whoever has it until they leave, so the reader's focus holds.
    private var isStageHeld = false
    /// Looks at the group's stage again when a speaker's turn becomes sustained.
    @CancellableTask private var groupFocusTask: Task<Void, Never>?
    // Brief 0085 — translation for everyone.
    private let myLanguageStore: NativeCallMyLanguageStore
    /// The last look at the call's translation, to tell what changed.
    private var lastTranslation: NativeCallTranslationState?
    /// The stops the documents told (ADR-0094 D6), with the last document of each assistant that left.
    private var stopHistory = NativeCallTranslationStopHistory()
    private var seenStopIDs: Set<Int> = []
    private var recordingCoverTracker = NativeCallRecordingCoverTracker()
    /// The last covered refusal of a recording start, so each opens the card once (question 404).
    private var lastRecordingRefusal: NativeAgentCenterRecordingRefusal?
    /// A language heard until its lanes went, so the stop that explains it still shows.
    private var droppedLanguage: String?
    private var hasAppliedTool = false
    /// The catalog code last handed to the membership: the session keeps it sent from then on.
    private var handedLanguage: String?
    /// The capsule already said the chat's tool turned your assistant's translation on.
    private var hasShownToolStart = false
    /// Question 409: the language the capsule last said someone translates you from; nil until it said so once.
    private var announcedSpokenLanguage: String?
    @CancellableTask private var capsuleTask: Task<Void, Never>?
    /// D10: how long the language you hear holds once its lanes go, for a standby to take them over (the backend's
    /// takeover takes about a second).
    static let takeoverWindow: Duration = .seconds(3)
    @CancellableTask private var takeoverTask: Task<Void, Never>?
    /// L11's one-tap switch: its two writes, cancelled with the call.
    @CancellableTask private var switchTask: Task<Void, Never>?

    private let actionsSubject: PassthroughSubject<NativeCallScreenViewModelAction, Never> = .init()
    var actions: AnyPublisher<NativeCallScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    /// Brief 0068 Slice 3 — the tap you feel when the call connects and
    /// when it ends: the Phone app's cue, missing from ours. Injected so
    /// tests read it and previews stay silent.
    private let haptics: NativeCallHaptics
    // AGENT-PLATFORM (407): the route, through a seam a test can read.
    private let audioRouting: NativeCallAudioRouting

    init(session: NativeCallSession,
         callKitService: CallKitServiceProtocol,
         agentCenter: NativeAgentCenterController,
         appMediator: AppMediatorProtocol,
         haptics: NativeCallHaptics = .system,
         audioRouting: NativeCallAudioRouting = .system,
         mediaProvider: MediaProviderProtocol? = nil,
         peerSettleDuration: Duration = NativeCallVideoStage.settleDuration,
         isVideoCall: Bool,
         roomID: String,
         roomName: String,
         scope: NativeCallScope = .direct,
         roomAvatar: RoomAvatar = .room(id: "", name: nil, avatarURL: nil),
         memberProfiles: AnyPublisher<[String: NativeCallMemberProfile], Never> = Empty().eraseToAnyPublisher(),
         roomPresentation: AnyPublisher<NativeCallRoomPresentation, Never> = Empty().eraseToAnyPublisher(),
         myLanguageStore: NativeCallMyLanguageStore = .standard,
         languageCatalog: NativeCallLanguageCatalogCache = .standard) {
        self.session = session
        self.callKitService = callKitService
        self.agentCenter = agentCenter
        self.appMediator = appMediator
        self.haptics = haptics
        self.audioRouting = audioRouting
        self.peerSettleDuration = peerSettleDuration
        self.roomID = roomID
        self.myLanguageStore = myLanguageStore
        callKitID = callKitService.callKitID(forRoomID: roomID)

        super.init(initialViewState: NativeCallScreenViewState(roomName: roomName,
                                                               scope: scope,
                                                               roomAvatar: roomAvatar,
                                                               isRoomEncrypted: session.isRoomEncrypted,
                                                               // A video call, and one with one's own assistant, come up on the
                                                               // speaker: the session decides the same (AGENT-PLATFORM (407)).
                                                               isSpeakerEnabled: NativeCallSpeakerPolicy.startsOnSpeaker(media: isVideoCall ? .video : .audio,
                                                                                                                         scope: scope,
                                                                                                                         hasExternalRoute: audioRouting.hasExternalRoute()),
                                                               isVideoCall: isVideoCall),
                   mediaProvider: mediaProvider)

        // The catalog kept on the device resolves "As on the phone" from the first frame; the platform's answer
        // re-resolves it only if the catalog changed (stable UI).
        let catalog = (languageCatalog.languages ?? []).map(\.code)
        state.chosenLanguage = myLanguageStore.chosen
        state.isMyLanguageChosen = myLanguageStore.isChosen
        state.cachedLanguageCodes = catalog
        applyMyLanguage(catalog: catalog)
        state.neighbourLanguage = myLanguageStore.neighbourLanguage
        state.pickedAssistantID = myLanguageStore.assistant(roomID: roomID)

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
                self?.resolveMyLanguage()
                self?.updateTranslation()
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

        // AGENT-PLATFORM (407): «Звук» follows the call's speaker wherever it changes — a start or a resume, a default
        // giving way to a car at activation, a device coming or going.
        audioRouting.speakerChanges
            .sink { [weak self] in self?.state.isSpeakerEnabled = $0 }
            .store(in: &subscriptions)

        // Phase 5 (G8) — AirPods arriving or a cable pulled while the route
        // sheet is up must re-render the list; the system already announces
        // every change.
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }
                // AGENT-PLATFORM (407): the speaker follows a device the system routed to. A held call's screen passes
                // nothing on: the call does nothing until its resume, which brings its own route back.
                if state.callState != .onHold,
                   let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) {
                    audioRouting.followRouteChange(reason)
                }
                guard state.bindings.isAudioRoutePickerPresented else { return }
                state.audioRoutes = audioRouting.availableRoutes()
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
            // "My language" rides the join's membership (ADR-0094 A.1) when the catalog is known; else it is published
            // once the catalog arrives (D1).
            if let code = state.myLanguageCode {
                handedLanguage = code
                await session.setLanguage(code)
            }
            await session.start()
        }

        Task {
            await agentCenter.reload()
            // Known before the sheet first opens, so it never shows a start that a check then refuses.
            await agentCenter.refreshJoinChecks()
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
        switchTask = nil
        // An add still waiting to retry must not attach or invite the assistant into the call being left.
        agentCenter.stop()
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
        case .swapVideos:
            state.bindings.isSelfVideoLarge.toggle()
        case .voiceOverStatusChanged(let isRunning):
            isStageHeld = isRunning
            updateGroupFocus()
        case .toggleSpeaker:
            toggleSpeaker()
        case .showAudioRoutes:
            // G8 — refresh at presentation time: the list is cheap and the
            // session's reality may have changed since the last look.
            state.audioRoutes = audioRouting.availableRoutes()
            state.bindings.isAudioRoutePickerPresented = true
        case .selectAudioRoute(let id):
            audioRouting.selectRoute(id)
            state.isSpeakerEnabled = id == NativeCallAudioRoute.speakerID
            state.audioRoutes = audioRouting.availableRoutes()
            state.bindings.isAudioRoutePickerPresented = false
        case .setListeningChoice(let choice):
            setListeningChoice(choice)
        case .translateMenuOpened:
            state.seenTranslationLanguages.formUnion(state.translation.options.map(\.language))
        case .produceTranslation:
            produceTranslation()
        case .addOwnTranslation:
            addOwnTranslation()
        case .showSpokenLanguage:
            showSpokenLanguage()
        case .setMyLanguage(let language):
            setMyLanguage(language)
        case .pickTranslationLanguage(let language):
            pickTranslationLanguage(language)
        case .applyPickedTranslationLanguage:
            applyPickedTranslationLanguage()
        case .runCapsuleAction:
            runCapsuleAction()
        case .continueTranslation(let language):
            continueTranslation(language)
        case .setNeighbourLanguage(let language):
            myLanguageStore.setNeighbourLanguage(language)
            state.neighbourLanguage = language
            state.bindings.isNeighbourLanguagePresented = false
            producePocketTranslation(isNeighbourPicked: true)
        case .toggleAssistantJob, .tapAssistantJob, .confirmAssistantJob, .retryAssistantJob:
            processJobAction(viewAction)
        case .pickAssistant(let agentID, let job):
            myLanguageStore.setAssistant(agentID, roomID: roomID)
            state.pickedAssistantID = agentID
            state.bindings.assistantPickerJob = nil
            if job == .translation {
                produceTranslation()
            } else {
                callAssistant(for: job, translation: nil)
            }
        case .setTranslationTool(let tool):
            runAgentAction(.translationTool) { await self.agentCenter.setTranslationTool(tool) }
        case .minimize:
            actionsSubject.send(.minimize)
        case .expand:
            actionsSubject.send(.expand)
        case .hangUp:
            actionsSubject.send(.dismiss)
        case .showAgentCenter, .showAgentCenterFromPill:
            let isForeignPill = if case .showAgentCenterFromPill = viewAction { state.agentBlock?.isOwn == false } else { false }
            state.bindings.agentCenterPage = isForeignPill ? .inTheCall : nil
            presentAgentCenter()
        case .showAgentLimit(let agentMxid):
            guard let agentID = state.agentCenter.candidates.first(where: { $0.mxid == agentMxid })?.id,
                  let viewModel = agentCenter.makeUsageViewModel(agentID: agentID) else {
                MXLog.warning("No Limit page for this agent")
                return
            }
            state.bindings.agentLimitPage = NativeCallAgentLimitPage(viewModel: viewModel)
        case .showAgentProfile(let agentMxid):
            state.bindings.isAgentCenterPresented = false
            actionsSubject.send(.showProfile(userID: agentMxid))
        case .dismissAgentCenter:
            // Every page the sheet can open on is cleared, so the next open starts on its own (a swipe-down too).
            state.bindings.isAgentCenterPresented = false
            state.bindings.isNeighbourLanguagePresented = false
            state.bindings.assistantPickerJob = nil
            state.bindings.assistantConfirmation = nil
            // A language picked while translation ran was never applied: closing the sheet leaves it where it was.
            state.pickedTranslationLanguage = nil
            agentCenter.clearError()
        case .reloadAgentCenter:
            agentCenter.clearError()
            Task { await agentCenter.reload() }
        case .attachAgentConfigured, .removeAgent, .cancelAgentJoin, .setAgentSwitch, .applyAgentTranslation,
             .disableAgentTranslation, .resumeAgent, .allowAI, .aiConsentAnswered, .removeAgentFromChat:
            processAgentCenter(viewAction: viewAction)
        }
    }

    /// The Agent Center's writes, each behind its own control's in-flight key (question 387, F9).
    private func processAgentCenter(viewAction: NativeCallScreenViewAction) {
        switch viewAction {
        case .attachAgentConfigured(let agentID, let params):
            if let agentMxid = state.agentCenter.candidates.first(where: { $0.id == agentID })?.mxid {
                state.attachesSent[agentMxid] = params
            }
            runAgentAction(.add(agentID: agentID)) { await self.agentCenter.attach(agentID: agentID, params: params) }
        case .removeAgent(let sessionID):
            runAgentAction(.session(sessionID, .remove)) { await self.agentCenter.remove(sessionID: sessionID) }
        case .cancelAgentJoin(let sessionID):
            runAgentAction(.session(sessionID, .remove)) { await self.agentCenter.cancelJoin(sessionID: sessionID) }
        case .setAgentSwitch(let sessionID, let control, let enabled):
            let row: NativeAgentCenterErrorScope.Row = switch control {
            case .recording: .recording
            case .summary: .summary
            case .conversation: .mainJob
            }
            runAgentAction(.session(sessionID, row)) { await self.agentCenter.setSwitch(sessionID: sessionID, control: control, enabled: enabled) }
        case .applyAgentTranslation(let sessionID, let params):
            runAgentAction(.session(sessionID, .translation)) {
                await self.agentCenter.setTranslation(sessionID: sessionID, params: params)
            } then: { isWritten in
                if isWritten {
                    self.sendPocketPairIfMoved(from: params, sessionID: sessionID)
                }
            }
        case .disableAgentTranslation(let sessionID):
            state.pickedTranslationLanguage = nil
            runAgentAction(.session(sessionID, .translation)) { await self.agentCenter.disableTranslation(sessionID: sessionID) }
        case .resumeAgent(let agentID):
            runAgentAction(.resume(agentID: agentID)) { await self.agentCenter.resume(agentID: agentID) }
        case .allowAI:
            guard let viewModel = agentCenter.makeAIConsentViewModel() else { return }
            state.bindings.aiConsentPrompt = NativeCallAIConsentPrompt(viewModel: viewModel)
            aiConsentCancellable = viewModel.actionsPublisher.sink { [weak self] action in
                switch action {
                case .done: self?.process(viewAction: .aiConsentAnswered)
                }
            }
        case .aiConsentAnswered:
            state.bindings.aiConsentPrompt = nil
            aiConsentCancellable = nil
            Task { await agentCenter.refreshJoinChecks() }
        case .removeAgentFromChat(let agentMxid):
            runAgentAction(.removeFromChat(agentMxid: agentMxid)) { await self.agentCenter.removeFromChat(agentMxid: agentMxid) }
        default:
            break
        }
    }

    // MARK: - Translation for everyone (Brief 0085)

    /// The own assistant the sheet's buttons act on: in the call, else on its way.
    private var ownControl: NativeCallAgentPresentation.Control? {
        let agents = state.agents
        return agents.ownAgents.first?.control ?? agents.joining.first(where: \.canControl)
    }

    private func setListeningChoice(_ choice: NativeCallListeningChoice) {
        state.listeningChoice = choice
        if state.takeoverLanguage != nil {
            state.takeoverLanguage = nil
            takeoverTask = nil
        }
        if choice != .original {
            state.pendingListenLanguage = nil
        }
        session.setListeningChoice(choice)
        dropCapsuleEvents { event in
            if case .translationAvailable(let language, _, _) = event { return choice.language == language }
            return false
        }
    }

    /// Looks at the call's translation again and says what changed: the capsule's events, a lane heard that ended, a
    /// translation asked for that now runs, the chat's tool at the call's start.
    private func updateTranslation() {
        updateRecordingCover()
        let next = state.translation
        let previous = lastTranslation
        lastTranslation = next
        if state.bindings.assistantConfirmation == .nothingToTranslate, !next.isNothingToTranslate(into: next.myLanguage) {
            // Someone speaks another language now, or «Translate into» changed: the buttons come back to start it.
            state.bindings.assistantConfirmation = nil
        }

        // A language held for «Translate into …» goes with the translation it would have moved.
        if state.pickedTranslationLanguage != nil, state.agents.ownAgents.first?.isTranslationOn != true {
            state.pickedTranslationLanguage = nil
        }

        let stops = stopHistory.stops.filter { !seenStopIDs.contains($0.id) }
        seenStopIDs.formUnion(stops.map(\.id))

        // A stopped track goes once a lane carries its language again: continued, or someone else's.
        let carried = Set(next.options.map(\.language))
        if state.stoppedTrackLanguages.contains(where: carried.contains) {
            state.stoppedTrackLanguages.removeAll(where: carried.contains)
        }
        // D10: listening is a choice of language, not of producer. The lanes in it went, whoever produced them: a
        // standby may take them over in a moment, so the language holds for the takeover window, the button unchanged.
        if let held = state.takeoverLanguage, next.options.contains(where: { $0.language == held }) {
            state.takeoverLanguage = nil
            takeoverTask = nil
        }
        if let language = state.listeningChoice.language, previous?.listeningLanguage == language, next.listeningLanguage == nil {
            holdForTakeover(language)
        }
        if let pending = state.pendingListenLanguage, next.options.contains(where: { $0.language == pending }) {
            setListeningChoice(.language(pending))
        }

        // The chat's tool first: when it started your assistant, that is what the capsule says first.
        applyTranslationToolIfNeeded()
        if let previous {
            let events = NativeCallCapsuleEvent.events(from: previous,
                                                       to: next,
                                                       newStops: stops,
                                                       heardLanguage: previous.listeningLanguage ?? droppedLanguage,
                                                       ownAgents: state.agents.panel.ownAgentMxids)
            if !stops.isEmpty {
                droppedLanguage = nil
            }
            // The capsule's «Продолжить» stays in the 文A menu as a stopped track (D6).
            for case .translationStopped(let language, _, _, _) in events where !state.stoppedTrackLanguages.contains(language) {
                state.stoppedTrackLanguages.append(language)
            }
            events.forEach(showCapsuleEvent)
        }
        updateSpokenLanguageEvent(next)
    }

    /// Question 409: someone's assistant translates you — said once per call to a person who never picked their language,
    /// and again after they change it from there.
    private func updateSpokenLanguageEvent(_ translation: NativeCallTranslationState) {
        dropCapsuleEvents { $0.isStale(in: translation) }
        guard state.callState == .connected,
              let event = NativeCallCapsuleEvent.spokenLanguageEvent(translation,
                                                                     announced: announcedSpokenLanguage,
                                                                     isLanguageChosen: state.isMyLanguageChosen) else { return }
        // A confirmation follows the pick it confirms, or never: it counts as said at once. The first event counts once
        // it shows (`didShowCapsuleEvent`).
        if case .translatingYou(let language, _, _, true) = event {
            announcedSpokenLanguage = language
        }
        showCapsuleEvent(event)
    }

    /// Question 404: whose recording covers the call, from the documents and the backend's refusal; the explanation a
    /// tap opened goes once nobody's recording covers it.
    private func updateRecordingCover() {
        let agents = state.agents
        // Until the call is up and the platform has said which assistants are yours, a roster gap or your own assistant
        // could read as someone else's recording, or its stop.
        guard state.callState == .connected, agents.panel.isAvailable else { return }
        let people = (state.humanParticipants.map(\.userID) + state.memberProfiles.keys.sorted()).reduce(into: [String]()) { people, person in
            if !people.contains(person) { people.append(person) }
        }
        // Yours by its document, not by the tap's optimism: a start that fails keeps «Продовжити».
        recordingCoverTracker.update(recorders: NativeCallRecordingCoverTracker.recorders(agents, people: people),
                                     undetermined: NativeCallRecordingCoverTracker.undetermined(agents),
                                     isOwnRecording: agents.ownAgents.contains { agents.documents[$0.mxid]?.holdsRecording == true },
                                     refusal: state.agentCenter.recordingRefusal,
                                     now: Date())
        if state.recordingCover != recordingCoverTracker.cover {
            state.recordingCover = recordingCoverTracker.cover
        }
        if state.recordingCover?.phase != .recording, state.bindings.assistantConfirmation == .recordingCovered {
            // Theirs stopped while the card was open: the buttons come back, «Продовжити» among them.
            state.bindings.assistantConfirmation = nil
        }
        if let refusal = state.agentCenter.recordingRefusal, refusal != lastRecordingRefusal {
            lastRecordingRefusal = refusal
            // A start the platform refused as covered — someone else's began before the button could show it — says
            // whose at once, in the sheet that asked.
            if state.recordingCover?.phase == .recording, state.bindings.isAgentCenterPresented {
                state.bindings.assistantConfirmation = .recordingCovered
            }
        }
    }

    /// G8 — with an external route in play (AirPods, a car) a binary speaker flip cannot express the choice: the tap
    /// opens the picker instead. With only the phone's two outputs the toggle stays the fast path.
    /// G8 — with an external route in play (AirPods, a car) a binary speaker flip cannot express the choice: the tap
    /// opens the picker instead. With only the phone's two outputs the toggle stays the fast path.
    private func toggleSpeaker() {
        let routes = audioRouting.availableRoutes() // AGENT-PLATFORM (407)
        if routes.contains(where: { $0.kind == .external }) {
            state.audioRoutes = routes
            state.bindings.isAudioRoutePickerPresented = true
        } else {
            let enabled = !state.isSpeakerEnabled
            audioRouting.setSpeakerEnabled(enabled)
            state.isSpeakerEnabled = enabled
        }
    }

    /// A tap on the sheet's buttons. Recording concerns everyone, so a start asks first, in place (L5 1.5); while
    /// someone else's recording covers the call, the card says whose instead of the buttons (question 404, layout C).
    /// 1.0.3 (operator's pick C in the call lab, 2026-11-21): a button only picks its job. Turning Notes, Talk or
    /// Recording on asks under the buttons first, and a second tap on the ringed button takes the question back.
    /// Translation's question is the resting state, so its button brings it back; «nothing to translate» comes from
    /// that question's Start, not from the button. Turning a job off stays one tap. The private call's interpreter keeps
    /// its own pair (L11).
    private func tapAssistantJob(_ job: NativeCallAssistantJob) {
        if job == .translation, !state.isAssistantPage, isTranslationOffAndOpen {
            // Its question, even over a refusal or a failed join — its Start is the retry.
            state.bindings.assistantConfirmation = .start(.translation)
            return
        }
        guard job != .translation, !isJobOn(job) else {
            state.bindings.assistantConfirmation = nil
            toggleAssistantJob(job)
            return
        }
        if state.bindings.assistantConfirmation == .start(job) {
            state.bindings.assistantConfirmation = nil
        } else if job == .recording, state.recordingCover?.phase == .recording {
            state.bindings.assistantConfirmation = .recordingCovered
        } else {
            state.bindings.assistantConfirmation = .start(job)
        }
    }

    /// The four job buttons' actions, out of `process(viewAction:)` to keep it readable.
    private func processJobAction(_ viewAction: NativeCallScreenViewAction) {
        switch viewAction {
        case .toggleAssistantJob(let job): toggleAssistantJob(job)
        case .tapAssistantJob(let job): tapAssistantJob(job)
        case .confirmAssistantJob(let job): confirmAssistantJob(job)
        case .retryAssistantJob(let job): retryAssistantJob(job)
        default: break
        }
    }

    /// A job's question answered yes: turns it on — never off, when it turned on meanwhile
    /// (another device, a room tool).
    private func confirmAssistantJob(_ job: NativeCallAssistantJob) {
        state.bindings.assistantConfirmation = nil
        guard !isJobOn(job) else { return }
        toggleAssistantJob(job)
    }

    /// A refusal's «Try again»: the refused write again. A failed language switch already moved your language, so the
    /// running translation follows it; otherwise the last write of that job says which way it went, and a write that
    /// went through after all (a lost answer) is left alone rather than reversed.
    private func retryAssistantJob(_ job: NativeCallAssistantJob) {
        state.bindings.assistantConfirmation = nil
        if job == .translation, isJobOn(.translation),
           let translating = state.translation.ownLanguage, translating != state.myLanguage {
            followMyLanguage()
            return
        }
        let wasEnabling = lastJobWrite?.job == job ? lastJobWrite?.isEnabling == true : !isJobOn(job)
        guard wasEnabling != isJobOn(job) else { return }
        toggleAssistantJob(job)
    }

    /// The last start or turn-off a job button sent, so «Try again» repeats that one.
    private var lastJobWrite: (job: NativeCallAssistantJob, isEnabling: Bool)?

    /// Translation is off and nothing blocks it: its question can stand under the buttons.
    private var isTranslationOffAndOpen: Bool {
        if state.agents.ownAgents.first?.shown.isTranslating == true || ownControl?.translation.isOn == true { return false }
        return state.translation.block == nil
    }

    /// Whether your assistant already does `job`, so a tap turns it off.
    private func isJobOn(_ job: NativeCallAssistantJob) -> Bool {
        let shown = state.agents.ownAgents.first?.shown
        switch job {
        case .translation: return shown?.isTranslating == true || ownControl?.translation.isOn == true
        case .summary: return shown?.isSummaryArmed == true
        case .recording: return shown?.isRecording == true
        case .conversation: return shown?.isConversationActive == true
        }
    }

    /// The lanes in the language you hear stopped (D10): it stays chosen while a standby may take them over, and goes
    /// back to the original (model point 7) only when no lane in it is there once the window runs out. Your own
    /// assistant standing by in it may take over later still (the sweeper's 30 s): its lanes then bring you back.
    private func holdForTakeover(_ language: String) {
        state.takeoverLanguage = language
        lastTranslation = state.translation
        takeoverTask = Task { [weak self] in
            try? await Task.sleep(for: Self.takeoverWindow)
            guard !Task.isCancelled, let self, state.takeoverLanguage == language else { return }
            state.takeoverLanguage = nil
            if !state.translation.options.contains(where: { $0.language == language }) {
                droppedLanguage = language
                setListeningChoice(.original)
                if state.agents.ownAgents.contains(where: { $0.live.languages.contains(language) }) {
                    state.pendingListenLanguage = language
                }
            }
            lastTranslation = state.translation
        }
    }

    /// Scenario 5.2 (ADR-0094 D9, D10, row 14): once per call, the chat's tool picks what you hear — the lanes into its
    /// language as soon as they exist. Starting your assistant is the server's (the Tool fires on the call), so the
    /// capsule says it, with "Cancel", once your assistant's document names the Tool as its source.
    private func applyTranslationToolIfNeeded() {
        if !hasAppliedTool, state.agentCenter.isAvailable, state.callState == .connected, !state.isAssistantPage {
            hasAppliedTool = true
            if let tool = state.agentCenter.translationFacts.tool, tool.isEnabled {
                if state.translation.options.contains(where: { $0.language == tool.language }) {
                    setListeningChoice(.language(tool.language))
                } else {
                    state.pendingListenLanguage = tool.language
                }
            }
        }
        // Yours by the agents list, or by the owner its document names before that list is read.
        let ownUserID = state.ownUserID
        if !hasShownToolStart,
           let own = state.agents.agents.first(where: { $0.isOwn || ($0.live.owner != nil && $0.live.owner == ownUserID) }),
           own.live.isFromTool, own.shown.isTranslating {
            hasShownToolStart = true
            showCapsuleEvent(.toolSwitchedOn(language: own.shown.languages.first ?? state.myLanguage))
        }
    }

    private func showCapsuleEvent(_ event: NativeCallCapsuleEvent) {
        guard state.capsule.enqueue(event) else { return }
        didShowCapsuleEvent(event)
    }

    /// Events that no longer hold go; one waiting behind a dropped current shows now, as after its turn.
    private func dropCapsuleEvents(where isStale: (NativeCallCapsuleEvent) -> Bool) {
        let current = state.capsule.current
        state.capsule.drop(where: isStale)
        guard state.capsule.current != current else { return }
        if let next = state.capsule.current {
            didShowCapsuleEvent(next)
        } else {
            capsuleTask = nil
        }
    }

    /// An event became the capsule's: VoiceOver reads it, an action for you taps the hand once (2026-11-12), and its
    /// five seconds start.
    private func didShowCapsuleEvent(_ event: NativeCallCapsuleEvent) {
        announce(event)
        if event.action != nil, !NativeCallHaptics.isAtEar(audioRouting.availableRoutes()) {
            haptics.capsuleEvent()
        }
        // Question 409: said once it shows — an event dropped unshown (its lane blinked) comes back with the lane.
        if case .translatingYou(let language, _, _, false) = event {
            announcedSpokenLanguage = language
        }
        scheduleCapsuleAdvance()
    }

    private func scheduleCapsuleAdvance() {
        capsuleTask = Task { [weak self] in
            try? await Task.sleep(for: NativeCallCapsuleQueue.duration)
            guard !Task.isCancelled else { return }
            self?.advanceCapsule()
        }
    }

    private func advanceCapsule() {
        state.capsule.advance()
        guard let next = state.capsule.current else {
            capsuleTask = nil
            return
        }
        didShowCapsuleEvent(next)
    }

    /// VoiceOver reads the event as it expands the capsule.
    private func announce(_ event: NativeCallCapsuleEvent) {
        let copy = NativeCallCapsuleEventCopy(event, viewState: state)
        AccessibilityNotification.Announcement(copy.announcement).post()
    }

    private func runCapsuleAction() {
        guard let action = state.capsule.current?.action else { return }
        advanceCapsule()
        switch action {
        case .listen(let language):
            setListeningChoice(.language(language))
        case .continueTranslation(let language):
            continueTranslation(language)
        case .changeSpokenLanguage:
            showSpokenLanguage()
        case .cancelTool:
            // D9: «Отменить» turns this call's translation off; the Tool stays armed for the next call.
            setListeningChoice(.original)
            state.pendingListenLanguage = nil
            if let control = ownControl {
                processAgentCenter(viewAction: .disableAgentTranslation(sessionID: control.sessionID))
            }
        }
    }

    /// "Translate into my language", "Translate the others", "Continue": your own assistant produces your language for
    /// the speakers nobody covers in it (model points 3, 4), and you hear it as soon as it runs. Blocked, the sheet
    /// opens on the reason and its way out.
    private func produceTranslation() {
        // Its question was answered: a refusal or a failed join that follows shows, not the question again.
        if state.bindings.assistantConfirmation == .start(.translation) { state.bindings.assistantConfirmation = nil }
        state.pickedTranslationLanguage = nil
        if state.isAssistantPage {
            producePocketTranslation()
            return
        }
        let translation = state.translation
        guard translation.block == nil else {
            state.bindings.agentCenterPage = nil
            presentAgentCenter()
            return
        }
        guard let params = translation.productionParams else {
            // L4.3: everyone is already translated into your language, by someone else's assistant: hear theirs, free.
            if translation.options.contains(where: { $0.language == translation.myLanguage }) {
                setListeningChoice(.language(translation.myLanguage))
            } else if translation.isNothingToTranslate(into: translation.myLanguage) {
                // Everyone already speaks it: the platform would only stand by, so nothing is asked and the sheet says
                // why in the buttons' place (operator, 2026-11-15).
                state.bindings.agentCenterPage = nil
                state.bindings.assistantConfirmation = .nothingToTranslate
                presentAgentCenter()
            }
            return
        }
        state.pendingListenLanguage = translation.myLanguage
        if let control = ownControl {
            processAgentCenter(viewAction: .applyAgentTranslation(sessionID: control.sessionID, params: params))
        } else {
            callAssistant(for: .translation, translation: params)
        }
    }

    /// «Продолжить» on a stopped track (D6): your own assistant produces that language, and it becomes your language —
    /// the language you choose to hear is yours (403 b, L1, L4), as a language picked for «+ Добавить свой перевод» is.
    /// Carried again by the time you tap, it is simply heard.
    private func continueTranslation(_ language: String) {
        state.stoppedTrackLanguages.removeAll { $0 == language }
        if state.translation.options.contains(where: { $0.language == language }) {
            setListeningChoice(.language(language))
            return
        }
        if language != state.myLanguage {
            let isOwnTranslating = state.agents.ownAgents.first?.shown.isTranslating == true || ownControl?.translation.isOn == true
            setMyLanguage(language == state.phoneLanguage ? nil : language)
            // Your running translation already moved to it with your language: heard once its lanes run.
            if isOwnTranslating {
                state.pendingListenLanguage = language
                return
            }
        }
        produceTranslation()
    }

    /// The 文A menu's «Add your own translation…» opens the sheet's root, where Translation's question is the resting
    /// state — one path whichever way it opens (operator, 2026-11-21: «щоб був один сценарій»).
    private func addOwnTranslation() {
        state.bindings.agentCenterPage = nil
        state.bindings.assistantConfirmation = nil
        presentAgentCenter()
    }

    /// 1.0.3 (operator's pick B, 2026-11-19): while your translation runs, a pick in «Translate into» only says where
    /// «Translate into …» would move it, so nothing changes mid-call by browsing the list. Otherwise it is your language
    /// at once, which «Start translation» then uses. The private call's «Я говорю» moves the interpreter at once (L11).
    private func pickTranslationLanguage(_ language: String) {
        guard !state.isAssistantPage, let own = state.agents.ownAgents.first, own.isTranslationOn else {
            state.pickedTranslationLanguage = nil
            setMyLanguage(language == state.phoneLanguage ? nil : language)
            return
        }
        state.pickedTranslationLanguage = language == own.translationLanguage ? nil : language
    }

    /// «Translate into …»: the held language becomes yours, and your running translation follows it the usual way. It
    /// waits for a translation write still out, and is the retry once a switch failed.
    private func applyPickedTranslationLanguage() {
        guard let language = state.pickedTranslationLanguage else { return }
        if let control = ownControl, state.agentActionsInFlight.contains(.session(control.sessionID, .translation)) { return }
        state.pickedTranslationLanguage = nil
        let previous = state.myLanguage
        setMyLanguage(language == state.phoneLanguage ? nil : language)
        // A switch that failed already moved your language: only the translation is left to move.
        if state.myLanguage == previous {
            followMyLanguage()
        }
    }

    /// Question 409: the capsule's «Змінити» and the 文A menu's «Я говорю»: the language list «Моя мова» is picked in.
    private func showSpokenLanguage() {
        state.bindings.agentCenterPage = .spokenLanguage
        presentAgentCenter()
    }

    private func presentAgentCenter() {
        let wasPresented = state.bindings.isAgentCenterPresented
        state.bindings.isAgentCenterPresented = true
        guard !wasPresented else { return }
        Task {
            await agentCenter.reload()
            await agentCenter.refreshJoinChecks()
        }
    }

    private func setMyLanguage(_ language: String?) {
        let previous = state.myLanguage
        let previousCode = state.myLanguageCode
        myLanguageStore.setChosen(language)
        state.chosenLanguage = language
        state.isMyLanguageChosen = true
        applyMyLanguage(catalog: state.agentCenter.availableLanguages.map(\.code))
        keepPocketPairApart(previousCode: previousCode)
        // Question 409: a change while nobody translates you isn't confirmed later, when someone starts again.
        if announcedSpokenLanguage != nil, state.translation.yourTranslator == nil {
            announcedSpokenLanguage = state.myLanguage
        }
        updateTranslation()
        publishMyLanguageIfNeeded()
        if state.myLanguage != previous {
            followMyLanguage()
        }
    }

    /// S1: the pocket pair is always two languages. In the private call, picking the neighbour's language as yours swaps
    /// the two sides — the neighbour takes your previous one — so an inverted pair is fixed in one pick.
    private func keepPocketPairApart(previousCode: String?) {
        guard state.isAssistantPage,
              let mine = state.myLanguageCode, mine == state.neighbourLanguage,
              let previousCode, previousCode != mine else { return }
        myLanguageStore.setNeighbourLanguage(previousCode)
        state.neighbourLanguage = previousCode
    }

    /// "As on the phone" again, once the catalog the platform sent differs from the one the device kept: the closest
    /// catalog code may differ. Published when it changed, or when it is the first catalog known (D1).
    private func resolveMyLanguage() {
        let catalog = state.agentCenter.availableLanguages.map(\.code)
        guard !catalog.isEmpty else { return }
        let previous = state.myLanguage
        applyMyLanguage(catalog: catalog)
        // Only a language you picked is confirmed in the capsule (question 409), not the catalog's closer code: the
        // capsule's language follows this change alone, never one you made before.
        if announcedSpokenLanguage == previous, state.myLanguage != previous {
            announcedSpokenLanguage = state.myLanguage
        }
        publishMyLanguageIfNeeded()
    }

    /// ADR-0094 D1: the code comes from the catalog only; until there is one, the screens name the app's language.
    private func applyMyLanguage(catalog: [String]) {
        let code = myLanguageStore.resolved(catalog: catalog)
        state.myLanguageCode = code
        state.phoneLanguage = myLanguageStore.phoneCode(catalog: catalog)
        let language = code ?? myLanguageStore.displayLanguage
        if language != state.myLanguage {
            state.myLanguage = language
        }
    }

    private func publishMyLanguageIfNeeded() {
        guard let code = state.myLanguageCode, code != handedLanguage else { return }
        handedLanguage = code
        Task { await publishMyLanguage(code) }
    }

    /// Nothing to tell the user when it doesn't land: the call session sends it again until the membership carries it.
    private func publishMyLanguage(_ language: String) async {
        guard await agentCenter.publishMyLanguage(language) else {
            MXLog.warning("My language isn't on the membership yet; the call session retries it")
            return
        }
    }

    /// L1, row 9 (ADR-0094 D3): the language you hear changed. Your assistant's intent is rewritten with it — the
    /// server keeps what it may claim and stands by for the rest — and a translation you were hearing moves to the
    /// new language, or back to the original when there is none in it.
    private func followMyLanguage() {
        let translation = state.translation
        let isOwnTranslating = state.agents.ownAgents.first?.shown.isTranslating == true || ownControl?.translation.isOn == true
        if isOwnTranslating, let control = ownControl, let code = state.myLanguageCode {
            let params: VoiceTranslationParams? = if state.isAssistantPage {
                state.neighbourLanguage.map { .pocket(code, $0) }
            } else {
                .forLanguage(code)
            }
            if let params {
                processAgentCenter(viewAction: .applyAgentTranslation(sessionID: control.sessionID, params: params))
                // Heard as soon as the new lanes run, as when it was first asked for.
                if state.listeningChoice != .original {
                    state.pendingListenLanguage = state.myLanguage
                }
            }
        }
        if state.listeningChoice != .original {
            let hasLanguage = translation.options.contains { $0.language == state.myLanguage }
            setListeningChoice(hasLanguage ? .language(state.myLanguage) : .original)
        }
    }

    /// Scenario 8.2: the pocket interpreter, once the neighbour's language is known — your side is always "my
    /// language", so the neighbour's is the one pick. L11: while the assistant talks with you, «Перевод» opens that pick
    /// first (the last neighbour preselected), and the pick ends the talk and starts the interpreter in one action.
    private func producePocketTranslation(isNeighbourPicked: Bool = false) {
        let isTalking = state.agents.ownAgents.first?.shown.isConversationActive == true
        guard let mine = state.myLanguageCode else {
            // No catalog code for your side yet (D1): nothing is asked for in another.
            state.bindings.isAgentCenterPresented = true
            return
        }
        guard let neighbour = state.neighbourLanguage, neighbour != mine, isNeighbourPicked || !isTalking else {
            state.bindings.isAgentCenterPresented = true
            state.bindings.isNeighbourLanguagePresented = true
            return
        }
        let params = VoiceTranslationParams.pocket(mine, neighbour)
        moveToSpeakerForInterpreter()
        if let control = ownControl {
            if isTalking {
                switchToInterpreter(control, params: params)
            } else {
                processAgentCenter(viewAction: .applyAgentTranslation(sessionID: control.sessionID, params: params))
            }
        } else {
            callAssistant(for: .translation, translation: params)
        }
    }

    /// AGENT-PLATFORM (407): the person beside you must hear the translation. The interpreter's start brings the call
    /// off the earpiece, once per start; headphones, Bluetooth and a car keep the sound, and a later pick is kept.
    private func moveToSpeakerForInterpreter() {
        guard NativeCallSpeakerPolicy.interpreterMovesToSpeaker(isSpeakerEnabled: state.isSpeakerEnabled,
                                                                hasExternalRoute: audioRouting.hasExternalRoute()) else { return }
        MXLog.info("The pocket interpreter starts: moving the call to the loudspeaker")
        audioRouting.setSpeakerEnabled(true)
        state.isSpeakerEnabled = true
    }

    /// L11, the private call (ADR-0094 D11: talking and translating exclude each other): the talk goes off, then the
    /// interpreter goes on — two writes in that order, «Перевод» ringed meanwhile. A refused second write leaves the talk
    /// off and says why on «Перевод», as any failed start does; the talk is never turned back on behind your back.
    private func switchToInterpreter(_ control: NativeCallAgentPresentation.Control, params: VoiceTranslationParams) {
        guard beginSwitch(to: .translation, sessionID: control.sessionID) else { return }
        let sessionID = control.sessionID
        switchTask = Task { [weak self, agentCenter] in
            var isWritten = false
            if await agentCenter.setSwitch(sessionID: sessionID, control: .conversation, enabled: false),
               self?.isSwitchGoingOn == true {
                isWritten = await agentCenter.setTranslation(sessionID: sessionID, params: params)
            }
            self?.endSwitch(sessionID: sessionID)
            if isWritten, self?.isSwitchGoingOn == true {
                self?.sendPocketPairIfMoved(from: params, sessionID: sessionID)
            }
        }
    }

    /// S1, DEBT B21: the pair the sheet shows is the pair that runs. A «Я говорю» or neighbour pick made while a pair
    /// was being written — during the talk→interpreter switch, when the interpreter isn't on yet and nothing is sent,
    /// or a second quick pick the in-flight write drops — would leave the written one running; the latest pair is sent
    /// once that write lands. Each send is the newest pair, so it settles on the last pick.
    private func sendPocketPairIfMoved(from written: VoiceTranslationParams, sessionID: String) {
        guard case .pocket = written, state.isAssistantPage, !hasCallEnded,
              ownControl?.sessionID == sessionID,
              let mine = state.myLanguageCode, let neighbour = state.neighbourLanguage, neighbour != mine else { return }
        let latest = VoiceTranslationParams.pocket(mine, neighbour)
        guard latest != written else { return }
        MXLog.info("The pocket pair changed while it was written; sending the latest")
        processAgentCenter(viewAction: .applyAgentTranslation(sessionID: sessionID, params: latest))
        if state.listeningChoice != .original {
            state.pendingListenLanguage = state.myLanguage
        }
    }

    /// L11, the other way: the interpreter goes off, then the talk goes on, in one tap. The platform refuses the talk
    /// while the runtime still runs the interpreter (`conversation.available` is false until it acknowledges the new
    /// mode), so the second write waits for that — a bounded wait; a talk still refused then says why on «Разговор».
    private func switchToConversation(_ control: NativeCallAgentPresentation.Control) {
        guard beginSwitch(to: .conversation, sessionID: control.sessionID) else { return }
        let sessionID = control.sessionID
        switchTask = Task { [weak self, agentCenter] in
            if await agentCenter.disableTranslation(sessionID: sessionID) {
                await Self.waitUntilTalkIsAvailable(sessionID: sessionID, agentCenter: agentCenter)
                if self?.isSwitchGoingOn == true {
                    _ = await agentCenter.setSwitch(sessionID: sessionID, control: .conversation, enabled: true)
                }
            }
            self?.endSwitch(sessionID: sessionID)
        }
    }

    /// The switch's next write is still wanted: not cancelled, and the call goes on.
    private var isSwitchGoingOn: Bool {
        !Task.isCancelled && !hasCallEnded
    }

    /// A switch writes both jobs, so it holds both controls while it runs: neither button can race its two writes.
    private func beginSwitch(to job: NativeCallAssistantJob, sessionID: String) -> Bool {
        let keys = Self.switchKeys(sessionID: sessionID)
        guard state.switchingAssistantJob == nil, state.agentActionsInFlight.isDisjoint(with: keys) else { return false }
        state.agentActionsInFlight.formUnion(keys)
        state.switchingAssistantJob = job
        return true
    }

    private func endSwitch(sessionID: String) {
        state.switchingAssistantJob = nil
        state.agentActionsInFlight.subtract(Self.switchKeys(sessionID: sessionID))
    }

    private static func switchKeys(sessionID: String) -> Set<NativeCallAgentAction> {
        [.session(sessionID, .translation), .session(sessionID, .mainJob)]
    }

    private static func waitUntilTalkIsAvailable(sessionID: String, agentCenter: NativeAgentCenterController) async {
        func isAvailable() -> Bool {
            agentCenter.snapshot.sessions.first { $0.sessionID == sessionID }?.conversation.isAvailable == true
        }
        for _ in 0..<talkWaitAttempts where !isAvailable() && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            await agentCenter.reload()
        }
    }

    /// Half-second reads: ten seconds for the runtime to leave the interpreter.
    private static let talkWaitAttempts = 20

    /// One of the four buttons: on or off for the assistant in the call (or on its way); with none, the tap brings
    /// one for that job (scenario 2.1).
    private func toggleAssistantJob(_ job: NativeCallAssistantJob) {
        lastJobWrite = (job, !isJobOn(job))
        // L11: a switch between talking and translating is under way; it ends on its own.
        guard state.switchingAssistantJob == nil || job == .summary || job == .recording else { return }
        guard let control = ownControl else {
            if job == .translation {
                produceTranslation()
            } else {
                callAssistant(for: job, translation: nil)
            }
            return
        }
        let shown = state.agents.ownAgents.first?.shown
        switch job {
        case .translation:
            if shown?.isTranslating == true || control.translation.isOn {
                processAgentCenter(viewAction: .disableAgentTranslation(sessionID: control.sessionID))
            } else {
                produceTranslation()
            }
        case .summary:
            processAgentCenter(viewAction: .setAgentSwitch(sessionID: control.sessionID, control: .summary, enabled: shown?.isSummaryArmed != true))
        case .recording:
            processAgentCenter(viewAction: .setAgentSwitch(sessionID: control.sessionID, control: .recording, enabled: shown?.isRecording != true))
        case .conversation:
            let isTalking = shown?.isConversationActive == true
            // L11: in the private call a tap on «Разговор» while the interpreter runs switches to the talk at once.
            if !isTalking, state.isAssistantPage, shown?.isTranslating == true || control.translation.isOn {
                switchToConversation(control)
            } else {
                processAgentCenter(viewAction: .setAgentSwitch(sessionID: control.sessionID, control: .conversation, enabled: !isTalking))
            }
        }
    }

    /// Brings your assistant for `job`: the one picked for this chat, the only one, or the sheet asks which (9.3).
    private func callAssistant(for job: NativeCallAssistantJob, translation: VoiceTranslationParams?) {
        let candidates = state.agents.panel.candidates
        guard let candidate = candidates.first(where: { $0.id == state.pickedAssistantID }) ?? (candidates.count == 1 ? candidates.first : nil) else {
            if candidates.count > 1 {
                state.bindings.isAgentCenterPresented = true
                state.bindings.assistantPickerJob = job
            }
            return
        }
        processAgentCenter(viewAction: .attachAgentConfigured(agentID: candidate.id, params: job.attachParams(translation: translation)))
    }

    // MARK: - Private

    /// Serialises Agent Center writes behind one in-flight flag so a
    /// double-tap cannot race two CAS writes against the same revision.
    ///
    /// Failure visibility: the controller reports every failed write into
    /// the snapshot (`lastError`, rendered by the sheet), so the discarded
    /// Bool here loses nothing the user was owed.
    /// `then` runs with the write's result once the control is free again, so it may write the same control.
    private func runAgentAction(_ key: NativeCallAgentAction,
                                _ action: @escaping () async -> Bool,
                                then: ((Bool) -> Void)? = nil) {
        guard state.agentActionsInFlight.insert(key).inserted else {
            // The same control is already writing: its row shows progress and takes no second tap.
            MXLog.warning("Agent Center action arrived while the same one is in flight; dropping it")
            return
        }

        Task {
            let result = await action()
            state.agentActionsInFlight.remove(key)
            then?(result)
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
            updateTranslation()
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
            switchTask = nil
            agentCenter.stop()
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
        let wasAssistantPage = state.isAssistantPage
        state.participants = participants
        // A person joined the call with one's assistant: the page ends, and so does a swap made on it, whatever their
        // camera does (question 383).
        if wasAssistantPage, !state.isAssistantPage {
            state.bindings.isSelfVideoLarge = false
        }
        updateGroupFocus()
        updateTranslation()
        // A membership may carry a new language (ADR-0094 A.1): read from the memberships, no platform round trip.
        Task { await agentCenter.refreshParticipantLanguages() }

        if let local = participants.first(where: \.isLocal) {
            state.isMicrophoneEnabled = local.isAudioEnabled
            // Same single-writer rule as the microphone: the engine's own
            // state reaches the control, never the last request.
            state.isCameraEnabled = local.isVideoEnabled
        }
    }

    /// A peer switched «Я говорю» mid-call (ADR-0094 A.1): their language reads anew, as with a roster change.
    func nativeCallSessionDidChangeParticipantLanguages(_ session: NativeCallSession) {
        Task { await agentCenter.refreshParticipantLanguages() }
    }

    func nativeCallSession(_ session: NativeCallSession, didChangeVideoTiles tiles: [NativeCallVideoTile]) {
        state.videoTiles = tiles
        settlePeerStage(on: tiles.first { !$0.participant.isLocal })
    }

    /// A group's stage follows the conversation, turned only by a sustained turn (question 383).
    private func updateGroupFocus() {
        guard state.scope == .group else { return }
        // Monotonic: a clock change mid-call must not stretch or skip a turn.
        let now = ProcessInfo.processInfo.systemUptime
        let others = state.humanParticipants.filter { !$0.isLocal }
        let candidates = others.map(\.userID)
        groupFocus.update(at: now, candidates: candidates, speaking: Set(others.filter(\.isSpeaking).map(\.userID)))
        let isHeld = isStageHeld && state.groupFocusUserID.map(candidates.contains) == true
        if !isHeld, state.groupFocusUserID != groupFocus.focused {
            state.groupFocusUserID = groupFocus.focused
            session.setStagedUser(groupFocus.focused)
        }
        guard let next = groupFocus.nextDecision(after: now) else {
            groupFocusTask = nil
            return
        }
        groupFocusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(next - now))
            guard !Task.isCancelled else { return }
            self?.updateGroupFocus()
        }
    }

    /// Decision 342: the stage changes once. It goes to the peer on their first picture, or when their camera has
    /// stayed off for `peerSettleDuration`, and stays theirs. A swap ends when their picture really comes or goes.
    private func settlePeerStage(on peer: NativeCallVideoTile?) {
        guard let peer else {
            peerSettleTask = nil
            state.isPeerSettled = false
            isPeerPictureSettled = false
            return
        }

        if peer.source != nil {
            peerSettleTask = nil
            state.isPeerSettled = true
            if !isPeerPictureSettled {
                isPeerPictureSettled = true
                state.bindings.isSelfVideoLarge = false
            }
            return
        }

        guard isPeerPictureSettled || (!state.isPeerSettled && NativeCallVideoStage.isCameraOff(peer)) else {
            peerSettleTask = nil
            return
        }
        guard peerSettleTask == nil else { return }

        peerSettleTask = Task { [weak self, peerSettleDuration] in
            try? await Task.sleep(for: peerSettleDuration)
            guard !Task.isCancelled else { return }
            self?.peerSettleTimeElapsed()
        }
    }

    private func peerSettleTimeElapsed() {
        peerSettleTask = nil
        state.isPeerSettled = true
        if isPeerPictureSettled {
            isPeerPictureSettled = false
            state.bindings.isSelfVideoLarge = false
        }
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
        stopHistory.update(documents: claims.documents)
        updateTranslation()
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
