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
    /// Slice 5 — flip the capture device. Bound to a tap on the local
    /// preview: the control row is full, and the gesture is the one users
    /// already know from every other video app.
    case switchCamera
    /// Slice 4 — personal listening: the user picked what to hear.
    case setListeningChoice(NativeCallListeningChoice)
    // Slice 3 — the native Agent Center.
    /// Brief 0062 parity — owner translation writes edit the FULL booth
    /// list; the flat languages write is gone (it erased per-speaker
    /// configuration on every Apply).
    case applyAgentTranslation(sessionID: String, params: VoiceTranslationParams)
    case disableAgentTranslation(sessionID: String)
    case clearAgentTranslationOverride(sessionID: String)
    case saveAgentTranslationAsRoomDefault(sessionID: String)
    /// One-tap "translate me": attach with a single `owner_only` booth
    /// in the simultaneous style (per-speaker lanes; every listener
    /// hears the lane, the speaker never hears their own).
    case attachAgentTranslateMe(agentID: String, language: String)
    /// `11 · Add an agent` — attach with the composed starting functions
    /// (translation / recording / summary toggles).
    case attachAgentConfigured(agentID: String, params: VoiceAttachParams)
    case showAgentCenter
    case dismissAgentCenter
    /// `19 · Failure states` — the error card's recovery: drop the stale
    /// snapshot and read the platform again.
    case reloadAgentCenter
    case removeAgent(sessionID: String)
    /// Recording / summary / conversation: every on/off control shares one write.
    case setAgentSwitch(sessionID: String, control: VoiceSessionSwitch, enabled: Bool)
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
    /// Public agent state, kept beside the human tiles rather than mixed into
    /// them (Brief 0063 Slice 3).
    var agentCenter = NativeAgentCenterSnapshot()
    /// An action is in flight; the panel disables its controls rather than
    /// letting a second write race the first.
    var isAgentActionInFlight = false
    /// What the call's agents claim and audibly do — the live register
    /// every device shares (`spiral.agent.state` + the speaking signal).
    /// Drives the block (`claimed ∧ speaking` is the wave), the paused
    /// state, and the call-wide REC truth the owner-scoped REST list
    /// cannot provide.
    var agentClaims = NativeCallAgentClaims()
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

    /// The one face a 1:1 call centres on: the human peer of a direct call,
    /// the agent of a call with one's own assistant. Nil for a group.
    var stagePeer: NativeCallParticipant? {
        switch scope {
        case .direct: humanParticipants.first { !$0.isLocal }
        case .assistant: agentParticipants.first
        case .group: nil
        }
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
                                                       coveredSpeakers: listening.translatedSpeakers,
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
    var agentBlock: NativeCallAgentBlockState? {
        agents.activeAgent.map(NativeCallAgentBlockState.init)
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

/// `11 · Add an agent` — what the owner picked, as the one attach it becomes.
/// Conversation and Translation exclude each other, as in the Agent Center:
/// turning one on turns the other off (decision 180).
struct NativeCallAddAgentForm: Equatable {
    private(set) var conversation = false
    private(set) var translation = false
    /// Target languages for the one `anyone` booth, from the agent's catalog.
    var languages: [String]
    var recording = false
    var summary = false

    /// Seeds the language with the device locale when the catalog offers it.
    init(catalog: [VoiceControlsCatalogLanguage]) {
        languages = VoiceTranslationBooths.localeSeed(catalog: catalog).map { [$0] } ?? []
    }

    mutating func setConversation(_ isOn: Bool) {
        conversation = isOn
        if isOn { translation = false }
    }

    mutating func setTranslation(_ isOn: Bool) {
        translation = isOn
        if isOn { conversation = false }
    }

    /// Translation on needs a language to translate into.
    var canAdd: Bool {
        !translation || !languages.isEmpty
    }

    /// WYSIWYG: every toggle goes into the attach, off included.
    var params: VoiceAttachParams {
        VoiceAttachParams(translation: translation && !languages.isEmpty
            ? .init(booths: [.init(speakerScope: VoiceSpeakerScope.anyone.rawValue,
                                   speakerMembers: [],
                                   targetLanguages: languages)],
                    style: NativeCallTranslationStyleDefault.wire)
            : nil,
            recording: recording,
            summary: summary,
            conversation: conversation)
    }
}
