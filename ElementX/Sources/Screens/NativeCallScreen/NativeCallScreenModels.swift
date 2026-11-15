//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

// AGENT-PLATFORM (Brief 0063)

enum NativeCallScreenViewModelAction {
    case dismiss
    /// The outgoing join rang the room; the coordinator should start watching
    /// decline events for this notification.
    case didSendRingNotification(eventID: String)
    /// G13 — back to the chat with the call running; the call bar is what
    /// the user lands on.
    case minimize
    /// G9 — the call bar was tapped; the full screen returns.
    case expand
    /// The assistant's "…" menu (question 401, settings concept A): its profile, over the call's bar.
    case showProfile(userID: String)
}

enum NativeCallScreenViewAction {
    /// Brief 0068 Slice 2 — the "on hold" pill: hold this call, resume the
    /// parked one.
    case swapCalls
    case toggleMicrophone
    case toggleSpeaker
    /// Phase 5 (G8) — open the audio route picker.
    case showAudioRoutes
    /// Phase 5 (G8) — the user picked a route in the sheet.
    case selectAudioRoute(id: String)
    /// G13 — leave the screen, keep the call.
    case minimize
    /// G9 — return to the full call screen from the bar.
    case expand
    case hangUp
    /// Slice 5 — publish or mute our own camera.
    case toggleCamera
    /// Slice 5 — flip the capture device: the dock's Camera control only, never a tap on a tile (decision 341).
    case switchCamera
    /// A tap on the corner tile: the large picture and the corner one change places, and back (question 383).
    case swapVideos
    /// VoiceOver started or stopped: while it runs, a group's stage holds still so focus isn't reset (question 383).
    case voiceOverStatusChanged(isRunning: Bool)
    /// Brief 0085 — the 文A menu: the language to hear the call in, or the original.
    case setListeningChoice(NativeCallListeningChoice)
    /// The 文A menu opened: its new languages are seen, and the dot goes.
    case translateMenuOpened
    /// "Start translation" / "Continue": your own assistant produces your language; a language someone else already
    /// translates is heard instead, free (L4.3).
    case produceTranslation
    /// The 文A menu's "+ Add your translation" (L4): the Assistants sheet opens right at creating one, or at your
    /// assistant's translation when it already runs.
    case addOwnTranslation
    /// The language you hear and speak (L1): nil is the phone's. What your assistant produces follows it.
    case setMyLanguage(String?)
    /// Question 409: the 文A menu's «Я говорю: … ›» — the language list, as the capsule's «Змінити» opens it.
    case showSpokenLanguage
    /// The capsule's event button; elsewhere on the capsule opens the sheet.
    case runCapsuleAction
    /// A stopped track in the 文A menu: «Продолжить», as the capsule's event offers it.
    case continueTranslation(language: String)
    /// Scenario 8.2: the pocket interpreter's other side.
    case setNeighbourLanguage(String)
    /// The own assistant's four buttons (scenario 2): in the call, on or off; with none in it, the tap brings one.
    case toggleAssistantJob(NativeCallAssistantJob)
    /// A tap on one of the Assistants sheet's four buttons: recording asks first, or explains whose recording covers
    /// the call (question 404); the rest toggle.
    case tapAssistantJob(NativeCallAssistantJob)
    /// Scenario 9.3: which own assistant comes, remembered for this chat.
    case pickAssistant(agentID: String, job: NativeCallAssistantJob)
    /// Scenario 5: this chat's tool "Call translation".
    case setTranslationTool(NativeCallTranslationTool)
    // Slice 3 — the native Agent Center.
    /// An enabling translation write (ADR-0094 A.2): `for_language`, or the pocket interpreter.
    case applyAgentTranslation(sessionID: String, params: VoiceTranslationParams)
    case disableAgentTranslation(sessionID: String)
    /// Brings an own assistant with its jobs, translation as its intent.
    case attachAgentConfigured(agentID: String, params: VoiceAttachParams)
    case showAgentCenter
    /// The agent pill: someone else's agent on it opens the sheet on "In the call" (question 401, remark 15).
    case showAgentCenterFromPill
    /// "My limit" beside a limit's refusal: the agent's weekly Limit page (question 401, board A).
    case showAgentLimit(agentMxid: String)
    /// The assistant's "…" menu: its profile, with the call minimised to its bar.
    case showAgentProfile(agentMxid: String)
    case dismissAgentCenter
    /// `19 · Failure states` — the error card's recovery: drop the stale
    /// snapshot and read the platform again.
    case reloadAgentCenter
    case removeAgent(sessionID: String)
    /// Recording / summary / conversation: every on/off control shares one write.
    case setAgentSwitch(sessionID: String, control: VoiceSessionSwitch, enabled: Bool)
    /// N8: let go of a join that takes too long.
    case cancelAgentJoin(sessionID: String)
    /// F3a: take the owner's pause off.
    case resumeAgent(agentID: String)
    /// F3b: show the AI consent prompt; and its answer came back.
    case allowAI
    case aiConsentAnswered
    /// D6: a moderator removes someone else's assistant from the chat.
    case removeAgentFromChat(agentMxid: String)
}

/// One rendered participant in a video call: who it is, and which stream
/// (if any) to draw. Kept `Equatable` so the view diffs it like any other
/// state — the renderer is resolved from `source` at the leaf.
nonisolated struct NativeCallVideoTile: Equatable, Identifiable {
    let participant: NativeCallParticipant
    /// nil when the participant's camera is off — the tile shows their
    /// identity instead of an empty rectangle.
    let source: NativeCallVideoSource?
    /// G10 — the SFU paused this stream to save the channel: the sound
    /// stays, the picture self-restores, and the tile says so instead of
    /// freezing silently.
    var isStreamPaused = false

    var id: String {
        participant.id
    }
}

struct NativeCallScreenViewState: BindableState {
    var roomName: String
    /// Direct/group presentation is a room/call fact, never a participant
    /// count. Agents and temporarily disconnected devices cannot change it.
    var scope: NativeCallScope = .direct
    /// The same reactive avatar the room header renders. Group calls keep the
    /// room identity instead of borrowing an arbitrary participant's face.
    var roomAvatar: RoomAvatar = .room(id: "", name: nil, avatarURL: nil)
    /// Whether this call's room is E2EE — the connecting detail line says
    /// "Setting up encryption" only when there is encryption to set up.
    var isRoomEncrypted = false
    var callState: NativeCallScreenState = .connecting
    /// Brief 0068 Slice 2 — the Spiral call parked behind this one, if any;
    /// the pill under the header names it and swaps on tap.
    var heldCall: CallKitHeldCall?
    /// Phase 4 — how long the call ran, formatted, once it has ended
    /// (`18 · Call states`: "Call ended / 24 min 18 s").
    var endedCallDuration: String?
    /// G9 — when the call connected; the minimized bar's live timer
    /// counts from here.
    var callConnectedAt: Date?
    var participants: [NativeCallParticipant] = []
    /// Slice 4 — the listening picker: languages the call produces + the
    /// user's choice. The picker renders only when languages are produced.
    var listening = NativeCallListeningState()
    var isMicrophoneEnabled = true
    var isSpeakerEnabled = false
    /// Slice 5 — whether OUR camera publishes, as reported by the engine.
    var isCameraEnabled = false
    /// nil until initial local media settles; afterwards reflects whether any
    /// participant currently publishes camera video.
    /// True for a call that started as video: the camera control shows, and
    /// the layout gives video the whole screen instead of a roster list.
    var isVideoCall = false
    /// What to render, derived. Empty in an audio call and while nobody has
    /// their camera on, which is what keeps an audio call looking like one.
    var videoTiles: [NativeCallVideoTile] = []
    /// The 1:1 stage is the peer's until they leave: they had a picture, or their camera stayed off long enough to
    /// count as off (decision 342). From here on a track or a key coming and going doesn't move the stage.
    var isPeerSettled = false
    /// Public agent state, kept beside the human tiles rather than mixed into
    /// them (Brief 0063 Slice 3).
    var agentCenter = NativeAgentCenterSnapshot()
    /// An action is in flight; the panel disables its controls rather than
    /// letting a second write race the first.
    var agentActionsInFlight: Set<NativeCallAgentAction> = []
    var isAgentActionInFlight: Bool {
        !agentActionsInFlight.isEmpty
    }

    /// The add each own agent was last sent with, by its MXID: its group holds those rows while it joins (board A).
    var attachesSent: [String: VoiceAttachParams] = [:]

    // MARK: Brief 0085 — translation for everyone

    /// What this person hears the call in; the original until they pick (model point 1).
    var listeningChoice = NativeCallListeningChoice.original
    /// D10: your own assistant's lanes in the language you hear just went; a standby may take them over in a moment, so
    /// the language stays chosen until `NativeCallScreenViewModel.takeoverWindow` runs out.
    var takeoverLanguage: String?
    /// The languages whose lane you listened to stopped, until continued, carried again, or the call ends: the 文A menu
    /// keeps «Продолжить» for each after the capsule's event is gone.
    var stoppedTrackLanguages: [String] = []
    /// "My language": the language they hear and speak, as the screens name it.
    var myLanguage = "en"
    /// The same as a catalog code, the only form ever published or asked for (ADR-0094 D1); nil while the catalog is
    /// unknown or has no such language.
    var myLanguageCode: String? = "en"
    /// Nil: as on the phone.
    var chosenLanguage: String?
    /// The person picked «Моя мова» — "As on the phone" too — rather than living with the default (question 409).
    var isMyLanguageChosen = false
    /// The catalog the device kept, until the platform answers.
    var cachedLanguageCodes: [String] = []

    /// The catalog's codes: the platform's, or the kept one before it answers, so a list has its languages at once.
    var languageCodes: [String] {
        let live = agents.panel.catalog.map(\.code)
        return live.isEmpty ? cachedLanguageCodes : live
    }
    /// The app's language as a catalog code, what "As on the phone" means; nil while the catalog has none.
    var phoneLanguage: String?
    /// The languages the 文A menu already showed: the rest get the dot.
    var seenTranslationLanguages: Set<String> = []
    /// A translation your assistant was asked for: heard as soon as its lanes run.
    var pendingListenLanguage: String?
    /// The capsule's events, one at a time.
    var capsule = NativeCallCapsuleQueue()
    /// Question 404: someone else's assistant records the call, or did and stopped, while yours doesn't.
    var recordingCover: NativeCallRecordingCover?
    /// The pocket interpreter's other side (scenario 8.2).
    var neighbourLanguage: String?
    /// L11, the private call: the job a one-tap switch between talking and translating is turning on, ringed until
    /// its two writes are done.
    var switchingAssistantJob: NativeCallAssistantJob?
    /// The own assistant chosen for this chat, when there are several (scenario 9.3).
    var pickedAssistantID: String?

    /// What the call's agents claim and audibly do — the live register
    /// every device shares (`spiral.agent.state` + the speaking signal).
    /// Drives the block (`claimed ∧ speaking` is the wave), the paused
    /// state, and the call-wide REC truth the owner-scoped REST list
    /// cannot provide.
    var agentClaims = NativeCallAgentClaims()
    /// A group's stage (question 383): whoever has held the floor, the others in a strip. Moved only by a sustained
    /// turn (`NativeCallGroupFocus`).
    var groupFocusUserID: String?
    /// Phase 5 (G8) — the selectable audio routes, refreshed when the
    /// picker opens and on every system route change while it is up.
    var audioRoutes: [NativeCallAudioRoute] = []
    /// The live link-quality ladder from the transport — the meta line's
    /// signal bars render it, G10's note reads its low end.
    var connectionQuality: NativeCallConnectionQuality = .unknown

    var isConnectionPoor: Bool {
        connectionQuality.isPoor
    }

    /// Phase 2 — Matrix profiles by MXID, from the room's member list. The
    /// screen renders PEOPLE (display name + avatar), never raw MXIDs; the
    /// Agent Center names a foreign agent by its profile ("Marta's
    /// Assistant" — the platform provisions the owner into the name), so
    /// the owner is named without any owner-only REST.
    var memberProfiles: [String: NativeCallMemberProfile] = [:]

    var bindings = NativeCallScreenViewStateBindings()

    // MARK: - Derived

    /// G1: agents are NEVER listed among humans. Disclosure moves to the
    /// header count, the agent block and the Agent Center — a chain that is
    /// stronger than a badge in the roster (plan §5.1).
    var humanParticipants: [NativeCallParticipant] {
        participants.filter { $0.role != .agent }
    }

    var agentParticipants: [NativeCallParticipant] {
        participants.filter { $0.role == .agent }
    }

    /// Who fills the 1:1 video stage and who floats in the corner.
    var videoStage: (large: NativeCallVideoTile?, small: NativeCallVideoTile?) {
        NativeCallVideoStage.tiles(remote: videoTiles.first { !$0.participant.isLocal },
                                   local: videoTiles.first(where: \.participant.isLocal),
                                   isPeerSettled: isPeerSettled,
                                   isSelfVideoLarge: bindings.isSelfVideoLarge)
    }

    /// The peer fills the 1:1 stage with no picture: their field, which needs no shades, as white already reads on it.
    var isPersonOnStage: Bool {
        guard let largeTile = videoStage.large else { return false }
        return !largeTile.participant.isLocal && largeTile.source == nil
    }

    /// The one face a 1:1 call centres on: the human peer of a direct call,
    /// the agent of a call with one's own assistant. Nil for a group.
    var stagePeer: NativeCallParticipant? {
        switch scope {
        case .direct: humanParticipants.first { !$0.isLocal }
        // Once a person joins a call with one's assistant, the page ends and the person takes the stage.
        case .assistant: isAssistantPage ? agentParticipants.first : humanParticipants.first { !$0.isLocal }
        case .group: nil
        }
    }

    /// A call with one's own assistant and nobody else is the assistant's page (question 383). It holds from the ring,
    /// before anyone has joined, so nothing jumps when the assistant answers; a person joining turns it back into a call
    /// with them, their face and their camera.
    var isAssistantPage: Bool {
        scope == .assistant && humanParticipants.allSatisfy(\.isLocal)
    }

    /// THE agent register every surface reads — the block, the header REC,
    /// the bar, the sheet, the roster's covered marks. One pure derive from
    /// the live sources (roster + documents) and the owner's REST snapshot,
    /// so no surface can ever again read an owner-scoped REST value as a
    /// live fact (closeout audit 2026-09-03). The clock only expires the
    /// owner's optimism; the controller republishes when it does.
    var agents: NativeCallAgentPresentation {
        NativeCallAgentPresentation.derive(live: .init(participants: participants,
                                                       claims: agentClaims,
                                                       isCallConnected: callState == .connected,
                                                       falteredAgents: listening.falteredAgents,
                                                       memberProfiles: memberProfiles,
                                                       ownUserID: ownUserID),
                                           rest: agentCenter,
                                           now: Date())
    }

    /// The local user's MXID, from the roster's local participant.
    var ownUserID: String? {
        participants.first { $0.isLocal }?.userID
    }

    /// G1: the block exists only when an agent is in the call, and it shows
    /// the ACTIVE one — every agent is still named in the Agent Center.
    /// While you hear a translation it is the assistant that produces it (403, L2): the capsule says what you hear.
    var agentBlock: NativeCallAgentBlockState? {
        let presentation = agents
        let heard = heardProducer.flatMap { producer in presentation.agents.first { $0.mxid == producer } }
        return (heard ?? presentation.activeAgent).map { NativeCallAgentBlockState($0, among: presentation.agents) }
    }

    /// The assistant producing the language you hear: yours when it is yours, else the first other one.
    private var heardProducer: String? {
        let translation = translation
        guard let language = translation.listeningLanguage,
              let option = translation.options.first(where: { $0.language == language }) else { return nil }
        if option.isYours, let own = agents.ownAgents.first?.mxid { return own }
        return option.producers.first
    }

    /// Brief 0085 — the call's translation for this person: the 文A button, its menu, the capsule's events, the badges.
    var translation: NativeCallTranslationState {
        let presentation = agents
        let facts = presentation.translationFacts
        let speakers = humanParticipants.filter { !$0.isLocal }.map(\.userID)
        var languages = facts.languages
        if let ownUserID {
            languages[ownUserID] = myLanguage
        }
        let ownAgents = presentation.panel.ownAgentMxids
        let lanes = NativeCallTranslationLane.lanes(documents: presentation.documents)
        return NativeCallTranslationState(.init(ownUserID: ownUserID,
                                                myLanguage: myLanguage,
                                                speakers: speakers,
                                                languages: languages,
                                                lanes: lanes,
                                                ownAgents: ownAgents,
                                                choice: listeningChoice,
                                                heldLanguage: takeoverLanguage,
                                                stoppedLanguages: stoppedTrackLanguages,
                                                seenLanguages: seenTranslationLanguages,
                                                block: NativeCallTranslationBlock.current(presentation, pickedAssistantID: pickedAssistantID),
                                                isPrivateCall: scope == .assistant,
                                                canProduceMyLanguage: myLanguageCode != nil,
                                                isLanguageChosen: isMyLanguageChosen,
                                                isOwnTranslating: presentation.ownAgents.first?.shown.isTranslating == true
                                                    || (presentation.ownAgents.first?.control ?? presentation.joining.first(where: \.canControl))?.translation.isOn == true))
    }

    /// L12: the pocket interpreter's badge on the assistant's stage avatar, the neighbour's language only; nil outside
    /// the private call and while it doesn't translate.
    var interpreterBadge: NativeCallAvatarBadge? {
        guard isAssistantPage else { return nil }
        let presentation = agents
        return (presentation.ownAgents.first ?? presentation.agents.first).flatMap { NativeCallAvatarBadge($0, myLanguage: myLanguage) }
    }

    /// L12, one visual everywhere: the badge on `userID`'s avatar — the stage's or a tile's. The interpreter's on the
    /// assistant's page; elsewhere the language you hear that person in, while your translation covers them.
    func avatarBadge(for userID: String) -> NativeCallAvatarBadge? {
        if isAssistantPage {
            return userID == stagePeer?.userID ? interpreterBadge : nil
        }
        return translation.badges[userID].map { NativeCallAvatarBadge(language: $0, isPending: false, kind: .heardIn) }
    }

    /// The agent capsule (Brief 0085): the active agent's block; your assistant's while it comes to a call that still
    /// rings (scenario 9.4), or while an event about it shows before it is in.
    var capsuleBlock: NativeCallAgentBlockState? {
        if let agentBlock { return agentBlock }
        let presentation = agents
        let isRinging = callState == .ringing || callState == .connecting
        let joining = presentation.joining.first(where: \.canControl)?.agentMxid
            ?? presentation.panel.candidates.first { presentation.panel.acceptedAttaches.contains($0.id) }?.mxid
        let own = joining ?? (capsule.current == nil ? nil : presentation.panel.candidates.first?.mxid)
        guard let own, isRinging && joining != nil || capsule.current != nil else { return nil }
        return NativeCallAgentBlockState(name: memberProfiles[own]?.displayName ?? UntranslatedL10n.screenNativeCallAgentPillYourAssistant,
                                         event: .idle(role: nil, languages: []),
                                         agentUserID: own,
                                         isOwn: true,
                                         joinsWhenAnswered: isRinging && joining != nil)
    }

    /// The chat's personal tool "Call translation", nil when not set up (scenario 5).
    var translationTool: NativeCallTranslationTool? {
        agents.translationFacts.tool
    }

    /// The AI limit stopped the owner's assistant mid-call (D7, D10): «Перевод на паузе до понедельника».
    var limitLine: String? {
        agents.limitStop?.line()
    }

    /// Phase 4 — the quiet second line under the status (`18 · Call
    /// states`): what the call is doing, or how long it ran once it ended.
    var statusDetail: String? {
        switch callState {
        case .connecting:
            isRoomEncrypted ? UntranslatedL10n.screenNativeCallStatusConnectingDetail : nil
        case .onHold:
            UntranslatedL10n.screenNativeCallStatusOnHoldDetail
        case .reconnecting:
            UntranslatedL10n.screenNativeCallStatusReconnectingDetail
        case .ended:
            endedCallDuration
        case .connected:
            // A CONNECTED call narrates nothing about the channel: the meta
            // line already carries `NativeCallSignalBars`, which shows the
            // live quality ladder continuously rather than only once it
            // degrades. Saying "Poor connection" beside those bars restated
            // the indicator in words — the operator read it as leftover test
            // scaffolding, and it is. Degradation the user cannot see from
            // the bars (`onHold`, `reconnecting`) keeps its line.
            nil
        case .ringing:
            nil
        }
    }

    /// The detail line wears the info hue for the degraded states — the
    /// teal ADR-0005 separates from both the accent and critical.
    var statusDetailIsDegraded: Bool {
        switch callState {
        case .onHold: true
        default: false
        }
    }

    /// G2: REC is a property of the CALL, so it lives in the header and
    /// nowhere else — the presentation's call-level fact.
    var isRecording: Bool {
        agents.isCallRecording
    }

    /// The minimized bar's wave: sound is flowing in the call — ANY
    /// participant or agent, not just an airing interpreter. Bar-only;
    /// the in-call surfaces keep their precise per-source marks.
    var isAnyoneSpeaking: Bool {
        participants.contains(where: \.isSpeaking) || agents.isAnyAgentSpeaking
    }

    /// G4: humans and agents are counted separately — `4 people · 2 agents`.
    /// One roster, two facts; merging them was what made an agent look like
    /// a participant in the first place.
    var statusText: String {
        switch callState {
        case .connecting: UntranslatedL10n.screenNativeCallStatusConnecting
        case .ringing: UntranslatedL10n.screenNativeCallStatusRinging
        case .connected: connectedStatusText
        case .onHold: UntranslatedL10n.screenNativeCallStatusOnHold
        case .reconnecting: UntranslatedL10n.screenNativeCallStatusReconnecting
        case .ended(let status): status
        }
    }

    private var connectedStatusText: String {
        let humans = humanParticipants.count
        let agents = agentParticipants.count
        // A call WITH the assistant is not a call waiting for people: the
        // line under its name is what it is doing (the Agent Center's own
        // head line), never a head-count.
        if scope == .assistant {
            let presentation = self.agents
            guard let assistant = presentation.activeAgent else { return Self.agentCountText(agents) }
            return NativeCallAgentStatusCopy.headStatus(assistant,
                                                        ownUserID: ownUserID,
                                                        profiles: memberProfiles,
                                                        catalog: presentation.panel.catalog)
        }
        guard humans > 1 else {
            // Alone with an agent is still waiting for people, but the agent
            // must not go unmentioned — it can be recording.
            return agents > 0
                ? "\(UntranslatedL10n.screenNativeCallStatusWaiting) · \(Self.agentCountText(agents))"
                : UntranslatedL10n.screenNativeCallStatusWaiting
        }
        let people = UntranslatedL10n.screenNativeCallStatusPeopleCount(humans)
        return agents > 0 ? "\(people) · \(Self.agentCountText(agents))" : people
    }

    /// Audit C11a — the plural rule belongs to the language, not to this
    /// function.
    ///
    /// This used to be `count == 1 ? … : …` against two separate keys. That
    /// expresses English and nothing else: Ukrainian and Russian each need
    /// one/few/many, so `2 агенти` and `5 агентів` both landed in the same
    /// `else` branch and rendered the English string. The app ships 39
    /// locales; a ternary cannot describe any of the Slavic ones.
    ///
    /// `.stringsdict` states the real CLDR categories per language, so this
    /// is now one call and the singular is the platform's problem.
    static func agentCountText(_ count: Int) -> String {
        UntranslatedL10n.screenNativeCallStatusAgentCount(count)
    }
}

/// A room member's profile as the call screens render it: the person, not
/// the identifier.
struct NativeCallMemberProfile: Equatable {
    var displayName: String?
    var avatarURL: URL?
}

struct NativeCallRoomPresentation: Equatable {
    var name: String
    var avatar: RoomAvatar
}

enum NativeCallScreenState: Equatable {
    case connecting
    case ringing
    case connected
    /// G10 — a phone call interrupted this one; it resumes on hang-up.
    case onHold
    case reconnecting
    case ended(status: String)
}

struct NativeCallScreenViewStateBindings {
    var alertInfo: AlertInfo<NativeCallScreenAlertType>?
    var isAgentCenterPresented = false
    /// The page the Assistants sheet opens on, over its root: "In the call" from someone else's agent on the pill.
    var agentCenterPage: NativeCallAssistantsRoute?
    /// The sheet's root creates a translation (L4.2): "New translation", opened by the 文A menu's "+".
    var isCreatingTranslation = false
    /// A question the sheet asks in place, never as a system alert (L5 1.5, 4.4).
    var assistantConfirmation: NativeCallAssistantConfirmation?
    /// The weekly Limit page pushed in the sheet.
    var agentLimitPage: NativeCallAgentLimitPage?
    /// Scenario 9.3: the sheet asks which own assistant comes, for this job.
    var assistantPickerJob: NativeCallAssistantJob?
    /// Scenario 8.2: the sheet asks the language of the person next to you.
    var isNeighbourLanguagePresented = false
    /// The AI consent prompt "Allow AI" opens over the sheet (question 387, F3b).
    var aiConsentPrompt: NativeCallAIConsentPrompt?
    /// Phase 5 (G8) — the audio route sheet.
    var isAudioRoutePickerPresented = false
    /// G14 — in a 1:1 video call, our own picture takes the stage and the
    /// peer becomes the draggable tile. "Move the other person around the
    /// screen" works exactly this way: make them small first, then drag.
    var isSelfVideoLarge = false
    /// A tap on the video hides the dock for a clean picture (the Telegram
    /// gesture). The header and the agent capsule stay: identity and the
    /// agent disclosure are never hidden (operator decision 2026-08-21).
    var isVideoChromeHidden = false
}

/// A question the Assistants sheet asks in place (L5): recording concerns everyone, removing from the chat is
/// beyond this call.
enum NativeCallAssistantConfirmation: Equatable {
    case recording
    /// Question 404, layout C: not a question — whose recording already covers the call, after a tap on the covered
    /// «Записує» or a start the platform refused as covered. «Зрозуміло» or the recording's end brings the buttons back.
    case recordingCovered
    /// Not a question either: everyone else already speaks the language «Translate into» names, so turning translation
    /// on would translate nobody. Nothing is asked of the platform; «Got it» brings the buttons back, translation off.
    case nothingToTranslate
    case removeFromChat(agentMxid: String)
}

enum NativeCallScreenAlertType {
    case callFailed
    /// The camera was denied in Settings: the control cannot work until the
    /// user changes that, so say so rather than failing silently.
    case cameraDenied
    /// Permission is fine but the engine refused the camera — at connect
    /// time (video call downgraded to audio) or on the toggle. The camera
    /// button is the retry; the alert says so (audit T3).
    case cameraUnavailable
}

/// Question 387 (F9): the control a running Agent Center write belongs to — only it shows progress.
enum NativeCallAgentAction: Hashable {
    case add(agentID: String)
    case resume(agentID: String)
    case session(String, NativeAgentCenterErrorScope.Row)
    case removeFromChat(agentMxid: String)
    case translationTool
}

/// The agent's weekly Limit page in the sheet: Brief 0079's own screen.
struct NativeCallAgentLimitPage: Identifiable, Hashable {
    let id = UUID()
    let viewModel: AgentUsageScreenViewModel

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// The AI consent prompt over the sheet: Brief 0078's own screen.
struct NativeCallAIConsentPrompt: Identifiable {
    let id = UUID()
    let viewModel: AIConsentPromptScreenViewModel
}
