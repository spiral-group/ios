//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063 closeout, 2026-09-03): THE ONLY thing any
// call surface may read about agents.
//
// Three bugs in two days — the recording capsule that said "Ready" on the
// peer's phone, the per-language picker, the "Leaving…" that never left —
// shared one root: a surface read a LIVE fact from the owner-scoped REST
// snapshot instead of from the sources every device sees the instant they
// change (the media ROSTER and the agent's published DOCUMENT). Each fix
// was per-site; this type makes the class impossible by construction.
//
// Two inputs, one pure derive, three named registers per agent:
//
//   `live`     populated ONLY from the roster + document (every device)
//   `control`  populated ONLY from REST (owner-only); nil when REST does
//              not know this agent — a field that cannot lie about a
//              live fact because it holds none
//   `shown`    the verdict surfaces render: `live` ⊕ the owner's
//              time-bounded optimism, audited in `bridged`
//
// A surface reads `shown` and `control`. It never sees the REST snapshot
// and never sees the raw claims; a lint rule and a test keep it that way.

import Foundation

struct NativeCallAgentPresentation: Equatable {
    /// Agents IN THE MEDIA ROSTER, in roster order. Nothing else is ever in
    /// this list: no REST session adds an entry, none removes one.
    let agents: [Agent]
    /// REST sessions whose agent has NOT reached the roster and is NOT
    /// ending — attach lag. Control only; there is no `live` to lie about.
    let joining: [Control]
    /// REST sessions still `ending` whose agent has already left the
    /// roster (walk F6): the removal is under way, so the agent is not
    /// offered again yet. Shown as "Removing…" rather than as nothing.
    let removing: [Control]
    /// The block's / capsule's agent: the airing one, else the first.
    let activeAgent: Agent?
    /// Header REC / bar REC — the CALL fact: any agent shown as recording.
    let isCallRecording: Bool
    /// The bar's wave input: any agent audibly producing sound.
    let isAnyAgentSpeaking: Bool
    /// Roster "Covered in X": speaker MXID → the language a Live agent
    /// translates them into, from its document.
    let coveredSpeakers: [String: String]
    /// Everything REST-only the sheet needs that is not per-agent.
    let panel: Panel

    /// Agents the user controls, for the sheet's expanded cards.
    var ownAgents: [Agent] {
        agents.filter { $0.control?.canControl == true }
    }

    /// Every other agent in the call, for the sheet's read-only rows.
    var foreignAgents: [Agent] {
        agents.filter { $0.control?.canControl != true }
    }

    /// The control register for a session the editor edits — present or
    /// still joining.
    func control(sessionID: String) -> Control? {
        agents.compactMap(\.control).first { $0.sessionID == sessionID }
            ?? joining.first { $0.sessionID == sessionID }
    }

    struct Agent: Equatable, Identifiable {
        var id: String {
            mxid
        }

        let mxid: String
        /// Profile → REST candidate name → MXID rule. Identity, not status:
        /// the one cosmetic place both inputs are consulted, in that order.
        let displayName: String
        let live: Live
        let control: Control?
        let shown: Shown
        /// `1 of 2 agents` — nil for a single agent.
        let ordinal: Ordinal?

        struct Ordinal: Equatable {
            let index: Int
            let count: Int
        }
    }

    // MARK: Source (a) — roster + document. Never reads REST.

    struct Live: Equatable {
        let isSpeaking: Bool
        /// The languages the document says it translates into (configured;
        /// `isPaused` says whether the engine currently produces them).
        /// Empty = translation off.
        let languages: [String]
        let booths: [SpiralAgentStateReader.Booth]
        /// `consecutive` (Interpreter) | `simultaneous` (Live) — nil when
        /// the document claims no translation.
        let style: SpiralAgentStateReader.TranslationStyle?
        /// Brief 0066 — does this agent translate MY voice, and what does
        /// that mean for my ears? Phrased for the foreign row.
        let coversMe: CoversMe?
        let isPaused: Bool
        let isRecording: Bool
        let isSummaryArmed: Bool
        /// Brief 0080 — the document's `conversation` function: the agent
        /// talks in this call. A disclosure every device shows.
        let isConversationActive: Bool
        let isLeaving: Bool
        /// Decision 182 — the runtime says the call is not live yet, so the
        /// agent waits for people and captures nothing. False when unknown.
        let isWaitingForPeople: Bool
        /// The wave: claimed ∧ speaking ∧ producing (`SpiralAgentDock` rule).
        var isAiring: Bool {
            NativeCallAgentPresentation.airing(isSpeaking: isSpeaking,
                                               languages: languages,
                                               isPaused: isPaused,
                                               isConversationActive: isConversationActive) != nil
        }
    }

    /// What a booth covering the local user means for them.
    enum CoversMe: Equatable {
        /// Simultaneous: others hear my lane, I never do (self-lane
        /// excluded by topology, ADR-0044 LT5).
        case live(languages: [String])
        /// Consecutive: my clip plays for everyone, me included (D8).
        case interpreter(languages: [String])
    }

    // MARK: Source (b) — REST. Never reads the roster or the document.

    struct Control: Equatable {
        let sessionID: String
        let agentMxid: String
        let canControl: Bool
        /// The backend accepted the DELETE. A control affordance ONLY — a
        /// second DELETE is a no-op, so Remove goes inert — never presence:
        /// REST answering `ending` while the roster still lists the agent
        /// was the eternal "Leaving…"; presence comes from the document's
        /// `lifecycle`, the owner's bounded write, and the roster.
        let isEndRequested: Bool
        let recording: NativeAgentCenterArtifact
        let summary: NativeAgentCenterArtifact
        /// The CAS'd override the EDITOR edits. Never a status source.
        let translation: NativeAgentCenterTranslation
        /// Brief 0080 — whether the switch is offered, and its CAS token.
        /// Whether the agent talks is `shown`, never this.
        let conversation: NativeAgentCenterConversation
        let isDisplaced: Bool
        let isSavedAsRoomDefault: Bool
        /// Whether the editor may offer keeping the translation as the room's rule.
        let canSaveAsRoomDefault: Bool

        /// A delivery the owner must act on — the ONE control fact allowed
        /// into the event ladder, because delivery has no document form.
        var hasDeliveryFailure: Bool {
            recording.delivery == .failed || summary.delivery == .failed
        }
    }

    // MARK: Verdict — live ⊕ unexpired owner optimism.

    struct Shown: Equatable {
        let presence: Presence
        let event: NativeCallAgentEvent
        let languages: [String]
        /// Document-only, no owner bridge (a write settles into
        /// `languages`, the style rides with it); on `shown` so surfaces
        /// read one register.
        let style: SpiralAgentStateReader.TranslationStyle?
        let isRecording: Bool
        let isSummaryArmed: Bool
        let isConversationActive: Bool
        let isPaused: Bool
        /// The wave and the accent line: speaking ∧ a SHOWN function that
        /// airs (translation not paused, else the conversation) — the same
        /// register as the toggles, so a Disable tap cannot leave the head
        /// waving for the window.
        let isAiring: Bool
        /// Which facts came from an unexpired owner write rather than the
        /// document. Tests assert on it; no UI reads it.
        let bridged: Set<NativeAgentCenterPendingWrite.Fact.Kind>

        var isTranslating: Bool {
            !languages.isEmpty
        }
    }

    enum Presence: Equatable {
        /// The call is still being placed: the agent can only wait (G7).
        case waiting
        case present
        /// The document says so, or the owner just asked, and the agent is
        /// still in the roster.
        case leaving
    }

    struct Panel: Equatable {
        let isAvailable: Bool
        let isLoading: Bool
        let lastError: NativeAgentCenterError?
        /// Candidates not already attached — REST's `attachedAgentMxids` is
        /// a control fact: what the backend will refuse to attach twice.
        let candidates: [NativeAgentCenterCandidate]
        let catalog: [VoiceControlsCatalogLanguage]
    }

    // MARK: - Inputs

    /// The live half. Built by the view state from the derived call state.
    struct LiveInputs: Equatable {
        var participants: [NativeCallParticipant] = []
        var claims = NativeCallAgentClaims()
        var coveredSpeakers: [String: String] = [:]
        var isCallConnected = true
        /// Agents whose translation faltered for a speaker on the air
        /// (session lane memory): only THEIR block reads "Original voices".
        var falteredAgents: Set<String> = []
        var memberProfiles: [String: NativeCallMemberProfile] = [:]
        /// The local user, for "translates you" on a foreign agent.
        var ownUserID: String?
    }

    // MARK: - Derive

    /// Two fact inputs and a clock. The clock is not a fact source; it
    /// exists only to expire the owner's optimism.
    static func derive(live: LiveInputs, rest: NativeAgentCenterSnapshot, now: Date) -> NativeCallAgentPresentation {
        let rosterAgents = live.participants.filter { $0.role == .agent }
        let sessionsByMxid = Dictionary(rest.sessions.map { ($0.agentMxid, $0) }) { first, _ in first }
        let rosterMxids = Set(rosterAgents.map(\.userID))

        let agents: [Agent] = rosterAgents.enumerated().map { index, participant in
            let liveFacts = liveFacts(participant, claims: live.claims, ownUserID: live.ownUserID)
            let control = sessionsByMxid[participant.userID].map { controlFacts($0, rest: rest) }
            let shown = shownFacts(live: liveFacts,
                                   control: control,
                                   pendingWrites: rest.pendingOwnerWrites[participant.userID] ?? [],
                                   isCallConnected: live.isCallConnected,
                                   isListeningFailAudible: live.falteredAgents.contains(participant.userID),
                                   now: now)
            return Agent(mxid: participant.userID,
                         displayName: displayName(participant.userID, profiles: live.memberProfiles, rest: rest),
                         live: liveFacts,
                         control: control,
                         shown: shown,
                         ordinal: rosterAgents.count > 1 ? .init(index: index + 1, count: rosterAgents.count) : nil)
        }

        // REST sessions with no roster presence: joining (attach lag) or
        // gone (teardown requested and already left) — never "Ready".
        let absent = rest.sessions.filter { !rosterMxids.contains($0.agentMxid) }
        let joining = absent.filter { !$0.isEnding }.map { controlFacts($0, rest: rest) }
        let removing = absent.filter(\.isEnding).map { controlFacts($0, rest: rest) }

        // The airing one, by the same fact the wave uses — not by the
        // event, where a delivery failure outranks airing.
        let active = agents.first { $0.shown.isAiring } ?? agents.first

        return NativeCallAgentPresentation(agents: agents,
                                           joining: joining,
                                           removing: removing,
                                           activeAgent: active,
                                           isCallRecording: agents.contains { $0.shown.isRecording },
                                           isAnyAgentSpeaking: agents.contains { $0.live.isSpeaking },
                                           coveredSpeakers: live.coveredSpeakers,
                                           panel: Panel(isAvailable: rest.isAvailable,
                                                        isLoading: rest.isLoading,
                                                        lastError: rest.lastError,
                                                        candidates: rest.candidates.filter { !rest.attachedAgentMxids.contains($0.mxid) },
                                                        catalog: rest.availableLanguages))
    }

    /// Enforced by signature: `Live` is built from a participant and the
    /// claims — no REST value is in scope here.
    private static func liveFacts(_ participant: NativeCallParticipant,
                                  claims: NativeCallAgentClaims,
                                  ownUserID: String?) -> Live {
        let document = claims.documents[participant.userID]
        let booths = document?.translation.activeBooths ?? []
        return Live(isSpeaking: claims.speaking.contains(participant.userID),
                    languages: document?.translation.configuredLanguages ?? [],
                    booths: booths,
                    style: document?.translation.style,
                    coversMe: coversMe(booths: booths, style: document?.translation.style, ownUserID: ownUserID),
                    isPaused: document?.translation.isPaused ?? false,
                    isRecording: document?.isRecording ?? false,
                    isSummaryArmed: document?.isSummaryArmed ?? false,
                    isConversationActive: document?.isConversationActive ?? false,
                    isLeaving: document?.lifecycle == .leaving,
                    isWaitingForPeople: document?.callGate == .waiting)
    }

    /// The languages of every booth that covers me, by style. Nil when no
    /// booth does (or the local user is unknown).
    private static func coversMe(booths: [SpiralAgentStateReader.Booth],
                                 style: SpiralAgentStateReader.TranslationStyle?,
                                 ownUserID: String?) -> CoversMe? {
        guard let ownUserID else { return nil }
        let languages = Array(Set(booths.filter { $0.coverage.covers(ownUserID) }.flatMap(\.targetLanguages))).sorted()
        guard !languages.isEmpty else { return nil }
        return style == .consecutive ? .interpreter(languages: languages) : .live(languages: languages)
    }

    /// Enforced by signature: `Control` is built from a REST session — no
    /// roster or document value is in scope here.
    private static func controlFacts(_ session: NativeAgentCenterSession, rest: NativeAgentCenterSnapshot) -> Control {
        Control(sessionID: session.sessionID,
                agentMxid: session.agentMxid,
                canControl: session.canControl,
                isEndRequested: session.isEnding,
                recording: session.recording,
                summary: session.summary,
                translation: session.translation,
                conversation: session.conversation,
                isDisplaced: rest.displacedSessionIDs.contains(session.sessionID),
                isSavedAsRoomDefault: rest.savedAsRoomDefaultSessionIDs.contains(session.sessionID),
                canSaveAsRoomDefault: session.canSaveAsRoomDefault)
    }

    /// The verdict. Starts from `live`; each fact is overridden only by a
    /// matching UNEXPIRED owner write. No `control.*` value is consulted
    /// for a shown fact except delivery, which has no document form — the
    /// bridge is the only door, and it closes on its own.
    private static func shownFacts(live: Live,
                                   control: Control?,
                                   pendingWrites: [NativeAgentCenterPendingWrite],
                                   isCallConnected: Bool,
                                   isListeningFailAudible: Bool,
                                   now: Date) -> Shown {
        var languages = live.languages
        var isRecording = live.isRecording
        var isSummaryArmed = live.isSummaryArmed
        var isConversationActive = live.isConversationActive
        var isLeavingByOwner = false
        var bridged = Set<NativeAgentCenterPendingWrite.Fact.Kind>()
        for write in pendingWrites where write.isLive(at: now) {
            switch write.fact {
            case .recording(let value):
                isRecording = value
                bridged.insert(.recording)
            case .summary(let value):
                isSummaryArmed = value
                bridged.insert(.summary)
            case .conversation(let value):
                isConversationActive = value
                bridged.insert(.conversation)
            case .translation(let value):
                languages = value
                bridged.insert(.translation)
            case .leaving:
                isLeavingByOwner = true
                bridged.insert(.leaving)
            }
        }

        // Leaving before waiting: an agent removed while the call is still
        // being placed is leaving, not idling.
        let presence: Presence = if live.isLeaving || isLeavingByOwner {
            .leaving
        } else if !isCallConnected {
            .waiting
        } else {
            .present
        }

        let airing = Self.airing(isSpeaking: live.isSpeaking,
                                 languages: languages,
                                 isPaused: live.isPaused,
                                 isConversationActive: isConversationActive)
        let event = event(presence: presence,
                          languages: languages,
                          airing: airing,
                          isPaused: live.isPaused,
                          isRecording: isRecording,
                          isSummaryArmed: isSummaryArmed,
                          isConversationActive: isConversationActive,
                          hasDeliveryFailure: control?.hasDeliveryFailure == true,
                          isListeningFailAudible: isListeningFailAudible,
                          isWaitingForPeople: live.isWaitingForPeople)

        return Shown(presence: presence,
                     event: event,
                     languages: languages,
                     style: live.style,
                     isRecording: isRecording,
                     isSummaryArmed: isSummaryArmed,
                     isConversationActive: isConversationActive,
                     isPaused: live.isPaused,
                     isAiring: airing != nil,
                     bridged: bridged)
    }

    /// What the agent puts on the air while it speaks — one rule for both
    /// functions everyone hears: its translation when it produces one, else
    /// its conversation's answer. The runtime sends audio only while it
    /// says something, so the speaking envelope is the on-air signal for
    /// both, never a timer.
    static func airing(isSpeaking: Bool,
                       languages: [String],
                       isPaused: Bool,
                       isConversationActive: Bool) -> NativeCallAgentEvent.Airing? {
        guard isSpeaking else { return nil }
        if !languages.isEmpty {
            return isPaused ? nil : .translation(languages: languages)
        }
        return isConversationActive ? .conversation : nil
    }

    /// The ladder: `failure > airing > paused > original > idle`. Candidates
    /// are collected and the most important wins, so the order is stated
    /// exactly once — on `NativeCallAgentEvent.priority`.
    private static func event(presence: Presence,
                              languages: [String],
                              airing: NativeCallAgentEvent.Airing?,
                              isPaused: Bool,
                              isRecording: Bool,
                              isSummaryArmed: Bool,
                              isConversationActive: Bool,
                              hasDeliveryFailure: Bool,
                              isListeningFailAudible: Bool,
                              isWaitingForPeople: Bool) -> NativeCallAgentEvent {
        // G7 — the call is still being placed: the agent can only wait. A
        // delivery failure still outranks it; nothing can air before the
        // call exists.
        guard presence != .waiting else {
            return hasDeliveryFailure ? .failure(.deliveryFailed) : .idle(role: .waiting, languages: [])
        }
        // Decision 182 — the agent is in the call but its runtime holds the
        // gate: too few people for the call to be live. It does nothing
        // until then, and says so.
        guard !isWaitingForPeople else {
            return hasDeliveryFailure ? .failure(.deliveryFailed) : .idle(role: .waitingForPeople, languages: [])
        }

        var candidates: [NativeCallAgentEvent] = []
        if hasDeliveryFailure {
            candidates.append(.failure(.deliveryFailed))
        }
        if let airing {
            candidates.append(.airing(airing))
        }
        if isPaused {
            candidates.append(.paused)
        }
        if isListeningFailAudible, !languages.isEmpty {
            candidates.append(.original)
        }
        // Resting: an agent that produces no translation is named by its
        // ROLE, never by a language it does not speak. Talking leads — it is
        // what everyone hears, while REC keeps its own pill on the header —
        // and recording wins over summary, the one happening DURING the call.
        let role: NativeCallAgentEvent.Role? = if !languages.isEmpty {
            nil
        } else if isConversationActive {
            .conversation
        } else if isRecording {
            .recording
        } else if isSummaryArmed {
            .summary
        } else {
            nil
        }
        candidates.append(.idle(role: role, languages: languages))
        return candidates.min() ?? .idle(role: nil, languages: [])
    }

    /// THE agent-name resolution: the room's own profile → the platform's
    /// candidate name → the MXID rule. Identity, not status.
    private static func displayName(_ mxid: String,
                                    profiles: [String: NativeCallMemberProfile],
                                    rest: NativeAgentCenterSnapshot) -> String {
        if let name = profiles[mxid]?.displayName, !name.isEmpty {
            return name
        }
        if let name = rest.candidates.first(where: { $0.mxid == mxid })?.displayName {
            return name
        }
        return NativeCallFallbackName.make(mxid: mxid)
    }
}

/// What the agent is doing right now, highest priority first — string-free;
/// `NativeCallAgentStatusCopy` owns every word.
enum NativeCallAgentEvent: Equatable, Comparable {
    case failure(Failure)
    case airing(Airing)
    case paused
    case original
    case idle(role: Role?, languages: [String])

    enum Failure: Equatable {
        case deliveryFailed
    }

    /// What is on the air: everyone in the call hears it.
    enum Airing: Equatable {
        case translation(languages: [String])
        /// Brief 0080 — the assistant answering its owner in the call.
        case conversation
    }

    enum Role: Equatable {
        /// Brief 0080 — the agent talks in this call.
        case conversation
        case recording, summary, waiting
        /// Decision 182 — the runtime waits for enough people to be live.
        case waitingForPeople
    }

    var priority: Int {
        switch self {
        case .failure: 0
        case .airing: 1
        case .paused: 2
        case .original: 3
        case .idle: 4
        }
    }

    static func < (lhs: NativeCallAgentEvent, rhs: NativeCallAgentEvent) -> Bool {
        lhs.priority < rhs.priority
    }
}
