//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import Foundation

// AGENT-PLATFORM (Brief 0063 Slice 3): the native Agent Center — the one
// client of the session-control REST API. Views observe `snapshotPublisher`
// and never call generated REST code themselves.

/// One agent the owner may add to this call, decorated with the Matrix-side
/// membership the platform cannot know about.
struct NativeAgentCenterCandidate: Hashable, Identifiable {
    let id: String
    let mxid: String
    /// The agent's real name from its platform record — NOT a localpart
    /// dressed up as a name. The two disagree in the worst possible way:
    /// the picker said "Assistant Emmm" (the MXID) while the very same
    /// agent, once in the call, said "Emmm's Assistant 2" (its profile).
    let displayName: String
    /// `nil` until agents get avatars at provisioning; the letter avatar
    /// then renders from `displayName`, which is the whole point of
    /// carrying the real name this far.
    let avatarURL: URL?
    let isRoomMember: Bool
    /// The owner paused it (decision 194): offered with Resume, never hidden (question 387, F3a).
    var isPaused = false
}

/// Why an own agent can't come into this call, or why its last add never reached it (question 387, F3). Each case
/// has one next step in the sheet; none names a person.
enum NativeAgentCenterJoinFailure: Equatable {
    case paused
    case aiConsentOwner
    case aiConsentRoom
    case askToJoin
    case budgetReached
    /// One category's cap is reached (question 395), e.g. calls, with its pause from the agent's usage; nil when that
    /// could not be read.
    case categoryPaused(AgentUsage.Category, AgentUsage.Pause?)
    /// 409 `/errors/conflict` on attach: the agent has no voice (F3f).
    case cannotJoinCalls
    /// The attach or the join failed for a reason the owner can only retry.
    case failed
    /// A reason newer than this build (decision 96).
    case needsUpdate

    init?(_ reason: VoiceJoinCheckReason) {
        switch reason {
        case .ok: return nil
        case .paused: self = .paused
        case .aiConsentOwner: self = .aiConsentOwner
        case .askToJoin: self = .askToJoin
        case .aiConsentRoom: self = .aiConsentRoom
        case .budgetReached: self = .budgetReached
        case .categoryPaused(let pause): self = .categoryPaused(.calls, pause)
        case .unknown: self = .needsUpdate
        }
    }

    /// An ended session's reason, when it says the agent never got in; nil for an ordinary end.
    init?(_ reason: VoiceSessionEndReason) {
        switch reason {
        case .callEnded, .manual, .ownerLeft, .translationNotHere: return nil
        case .optOut, .aiConsentRoom: self = .aiConsentRoom
        case .aiConsentOwner: self = .aiConsentOwner
        case .budgetReached: self = .budgetReached
        case .categoryPaused(let category): self = .categoryPaused(category, nil)
        case .failed: self = .failed
        case .unknown: self = .needsUpdate
        }
    }
}

/// Why the owner's own assistant stopped mid-call (D7, D10): the AI limit, or one category's cap. The call screen says
/// it in one line to the owner only; the others just stop hearing the assistant.
enum NativeAgentCenterLimitStop: Equatable {
    /// `isWeekly` is false for a period without its own words, or when the limit could not be read: the line then
    /// names no period rather than guess one.
    case limitReached(isWeekly: Bool)
    /// `until` is nil without a date: off until changed, or the limit could not be read.
    case categoryPaused(AgentUsage.Category, until: Date?)

    /// A refused enabling write's reason (ADR-0094 A.2): the per-call cap reads as a pause without a date.
    init(_ refusal: VoiceTranslationRefusal) {
        switch refusal.reason {
        case .aiLimit: self = .limitReached(isWeekly: false)
        case .translationPaused, .callCap: self = .categoryPaused(.callTranslation, until: refusal.pauseUntil)
        }
    }

    /// «Перевод на паузе до понедельника», «Лимит ИИ на эту неделю исчерпан».
    func line(now: Date = .now, calendar: Calendar = .current) -> String {
        switch self {
        case .limitReached(let isWeekly):
            return isWeekly ? UntranslatedL10n.screenNativeCallLimitUsedUpThisWeek : UntranslatedL10n.screenNativeCallLimitUsedUp
        case .categoryPaused(let category, let until):
            let until = until.map { AgentLimitWording.until($0, now: now, calendar: calendar) }
            // Translation stops on its own; any other cap ends the assistant's part of the call.
            if category == .callTranslation {
                return until.map(UntranslatedL10n.screenNativeCallLimitTranslationPausedUntil) ?? UntranslatedL10n.screenNativeCallLimitTranslationPaused
            }
            return until.map(UntranslatedL10n.screenNativeCallLimitAssistantPausedUntil) ?? UntranslatedL10n.screenNativeCallLimitAssistantPaused
        }
    }
}

/// Which control a failed write belongs to, so the sheet shows the error on that row (audit F8).
enum NativeAgentCenterErrorScope: Equatable {
    enum Row: Equatable {
        case mainJob, translation, recording, summary, remove
    }

    case session(String, Row)
    /// An own agent's add row, by agent id: a failed resume.
    case agent(String)
    /// Someone else's assistant, by MXID: a failed removal from the chat.
    case foreign(String)
    /// The chat's translation tool wasn't stored (Brief 0085).
    case translationTool
    case global
}

/// An artifact's live truth as the backend reports it. `revision` is the CAS
/// token the next write must carry, so the view never invents one.
struct NativeAgentCenterArtifact: Equatable {
    enum Delivery: Equatable {
        /// The artifact is not armed for this session.
        case notArmed
        case pending
        /// Where a delivered artifact landed, when the backend said so.
        case delivered(target: String?)
        case failed
    }

    let isEnabled: Bool
    let revision: Int32
    let delivery: Delivery
    /// Recording only: capture was stopped mid-call and what was captured is
    /// already on its way (dictaphone semantics).
    let isStopped: Bool

    /// Capturing right now. `isEnabled` alone stays true after a stop — the
    /// artifact still exists and still gets published (EC `RecordingTab`
    /// reference: `recording.enabled && !recording.stopped`).
    var isLive: Bool {
        isEnabled && !isStopped
    }
}

/// A session's translation as the owner reads it (ADR-0094 A.3): the intent, the lanes it holds, whether it stands by,
/// stopped or waits for the runtime, and the CAS token for the next write.
struct NativeAgentCenterTranslation: Equatable {
    var effective: VoiceControlsEffective
    /// CAS revision of the override row; 0 when none exists yet.
    let revision: Int32

    /// `override` | `room_tool` | `off`.
    var source: String {
        effective.source
    }

    /// `consecutive` | `simultaneous`; nil while off or stopped.
    var style: String? {
        effective.style
    }

    /// Call translation is paused by its cap while the session goes on (question 395): the owner's call line, the
    /// sheet's reason, and no translation offered.
    var pause: AgentUsage.Pause? {
        effective.pause
    }

    /// The intent is on: producing, standing by or starting — not stopped, not off.
    var isOn: Bool {
        effective.isEnabled
    }

    var isStandby: Bool {
        effective.isStandby
    }

    var isSyncing: Bool {
        effective.isSyncing
    }

    var stoppedReason: VoiceTranslationStopReason? {
        effective.stoppedReason
    }

    /// The intent's languages.
    var languages: [String] {
        effective.forLanguage.map { [$0] } ?? effective.pocket ?? []
    }

    static let unknown = NativeAgentCenterTranslation(effective: .off, revision: 0)

    init(effective: VoiceControlsEffective, revision: Int32) {
        self.effective = effective
        self.revision = revision
    }

    init(_ controls: VoiceControlsState) {
        effective = controls.effective
        revision = controls.override?.revision ?? 0
    }
}

/// Brief 0080 — the Conversation / Silent switch's CONTROL facts. Whether the
/// agent talks right now is a live fact, read from its document like every
/// other one, so REST's `active` is deliberately not carried here.
struct NativeAgentCenterConversation: Equatable {
    /// False while the call runs the interpreter: the switch is hidden.
    let isAvailable: Bool
    /// CAS revision of the override row; 0 when none exists yet.
    let revision: Int32

    /// No controls read: nothing to offer, so no switch.
    static let unknown = NativeAgentCenterConversation(isAvailable: false, revision: 0)
}

extension NativeAgentCenterConversation {
    init(_ state: VoiceConversationState) {
        isAvailable = state.available
        revision = state.revision
    }
}

/// One attached agent session the owner can act on.
struct NativeAgentCenterSession: Equatable, Identifiable {
    var id: String {
        sessionID
    }

    let sessionID: String
    let agentMxid: String
    /// False when this session belongs to someone else's agent: the call still
    /// shows it, but the controls stay read-only rather than lying.
    let canControl: Bool
    /// The backend is tearing this session down. Every control is inert from
    /// here on (a second DELETE is a no-op, artifact writes would 409/410),
    /// so the row says "Leaving…" and stops offering actions that cannot land.
    var isEnding: Bool
    let recording: NativeAgentCenterArtifact
    let summary: NativeAgentCenterArtifact
    let translation: NativeAgentCenterTranslation
    let conversation: NativeAgentCenterConversation
}

/// The owner's optimism between a tap and the runtime's document — THE one
/// bridge the presentation derive honours over live truth, and the only
/// way REST can ever influence a live fact on screen.
///
/// Time-bounded by construction: an unexpired write overrides the
/// document; a document that catches up settles it; the clock retires it
/// regardless; a refused write is withdrawn at once. "REST said X" can
/// therefore never outlive the document silently — the failure mode behind
/// the stuck recording capsule, the dead picker and the eternal "Leaving…"
/// (closeout audit 2026-09-03).
struct NativeAgentCenterPendingWrite: Equatable {
    enum Fact: Equatable {
        case recording(Bool)
        case summary(Bool)
        /// Brief 0080 — the agent talks (`true`) or stays silent.
        case conversation(Bool)
        /// The intent's catalog codes, the document's currency; empty = translation disabled.
        case translation(languages: [String])
        case leaving

        var kind: Kind {
            switch self {
            case .recording: .recording
            case .summary: .summary
            case .conversation: .conversation
            case .translation: .translation
            case .leaving: .leaving
            }
        }

        enum Kind: Hashable {
            case recording, summary, conversation, translation, leaving
        }
    }

    let fact: Fact
    /// `nil` while the write is still out: the window opens when the
    /// server answers, so a write that takes seconds (a call that started
    /// silent starting its conversation) cannot expire under the tap.
    let expiresAt: Date?

    func isLive(at now: Date) -> Bool {
        guard let expiresAt else { return true }
        return expiresAt > now
    }
}

/// Everything the native Agent Center renders. A single snapshot so the view
/// cannot show a half-applied mix of two loads.
struct NativeAgentCenterSnapshot: Equatable {
    /// This account has an agent platform. Known before any read, so the dock shows its Assistant button from the
    /// first frame (question 401, remark 4); the sheet says "loading" or "unavailable" until the platform answers.
    var isConfigured = false
    /// The platform answered at least once. Until it does, nothing is known about whose assistant is whose.
    var isAvailable = false
    var isLoading = false
    var sessions: [NativeAgentCenterSession] = []
    var candidates: [NativeAgentCenterCandidate] = []
    /// The voice-translation catalog (ADR-0094 A.8): every language list's source, there before any session.
    var availableLanguages: [VoiceControlsCatalogLanguage] = []
    /// Set when the last action failed; cleared by the next successful load.
    var lastError: NativeAgentCenterError?
    /// Where `lastError` belongs; `.global` only for "assistants are unavailable".
    var lastErrorScope: NativeAgentCenterErrorScope = .global
    /// Every own agent's MXID, paused ones included: "mine" never waits for the session list (audit F7).
    var ownAgentMxids: Set<String> = []
    /// The join check per own agent id (B4); absent when not asked yet or it could not be read.
    var joinChecks: [String: VoiceJoinCheckReason] = [:]
    /// Own agent ids whose join check has been asked at least once, answered or not; with `isCheckingJoins`, the sheet
    /// holds a placeholder rather than offer a start the check may refuse a moment later.
    var joinChecksAsked: Set<String> = []
    var isCheckingJoins = false
    /// Per own agent id: why its last add did not reach the call (B1), until the next add.
    var joinFailures: [String: NativeAgentCenterJoinFailure] = [:]
    /// When each accepted attach was answered, per session: "Still joining…" after a while (N8).
    var joinStartedAt: [String: Date] = [:]
    /// Own agent ids whose last add the backend accepted: the add form closes on it, before the re-read that follows
    /// (question 401, board A).
    var acceptedAttaches: Set<String> = []
    /// The local user may kick in this room, so may remove someone else's assistant from the chat (D6).
    var canRemoveOthersFromChat = false
    /// The owner's own assistant stopped mid-call on the AI limit (D7, D10), until the next add.
    var limitStop: NativeAgentCenterLimitStop?
    /// The owner's unsettled optimism, per agent MXID. Carried across
    /// reloads (a REST re-read neither extends nor shortens the window);
    /// settled by the document; swept by the clock once the write answered.
    var pendingOwnerWrites: [String: [NativeAgentCenterPendingWrite]] = [:]
    /// Brief 0085: the call's translation beyond the agents' documents, from the translation port.
    var translationFacts = NativeCallTranslationFacts()
    /// Question 404: the backend refused the latest start of a recording because someone else's assistant records the
    /// call; the call screen shows it as covered until the documents say who records.
    var recordingRefusal: NativeAgentCenterRecordingRefusal?

    /// MXIDs with a live session — the call UI marks these tiles as attached
    /// agents rather than plain service members.
    var attachedAgentMxids: Set<String> {
        Set(sessions.map(\.agentMxid))
    }
}

/// Question 404: a start of a recording the backend refused, one recording per call, and when.
struct NativeAgentCenterRecordingRefusal: Equatable {
    let cover: VoiceRecordingCover
    let at: Date
}

/// Failures the Agent Center surfaces verbatim rather than swallowing. Each
/// case maps to a distinct user-visible outcome.
enum NativeAgentCenterError: Equatable {
    /// 409 — someone else wrote first. The controller has already reloaded;
    /// the view asks the owner to retry against fresh truth.
    case conflict
    /// 410 — the session ended underneath us.
    case gone
    /// 422 — the backend refused the write, and said why.
    case rejected(String)
    /// The write was refused on this device, before the backend saw it.
    case notOwner
    /// 422 on turning the conversation ON — a failed Realtime spawn, a
    /// policy or budget refusal, the interpreter running. The owner must
    /// hear the outcome (the assistant stays silent), which the backend's
    /// detail does not say, AND the reason, which only the detail names.
    case conversationRefused(String)
    /// The owner paused the agent (decision 194): it joins no call.
    case agentPaused
    /// Turning translation on was refused by a pause or a limit (ADR-0094 A.2): nothing changed.
    case translationPaused(VoiceTranslationRefusal)
    case unavailable(String)

    /// The user-facing text. Lives on the model so every surface shows the
    /// same words: the translation editor used to render `String(describing:)`
    /// of this enum, which put `rejected("every booth needs a language…")` —
    /// Swift reflection, quotes and all — on screen.
    var localizedDescription: String {
        switch self {
        case .conflict: UntranslatedL10n.screenNativeCallAgentCenterErrorConflict
        case .gone: UntranslatedL10n.screenNativeCallAgentCenterErrorGone
        // The backend's refusal names the offending rule; it is the only
        // thing that tells the owner WHAT to fix.
        case .rejected(let detail): detail
        case .notOwner: UntranslatedL10n.screenNativeCallAgentCenterErrorNotOwner
        case .conversationRefused(let detail): Self.outcome(UntranslatedL10n.screenNativeCallAgentCenterErrorConversationRefused, reason: detail)
        case .agentPaused: UntranslatedL10n.screenNativeCallAgentCenterErrorAgentPaused
        case .translationPaused(let refusal): NativeAgentCenterLimitStop(refusal).line()
        case .unavailable: UntranslatedL10n.screenNativeCallAgentCenterErrorUnavailable
        }
    }

    /// The outcome, then the backend's reason on a line of its own.
    private static func outcome(_ outcome: String, reason: String) -> String {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? outcome : "\(outcome)\n\(reason)"
    }

    init(_ error: VoiceControlsError) {
        switch error {
        case .conflict: self = .conflict
        case .gone: self = .gone
        // Both are 422s the owner must read and act on, and the detail is what
        // names the fix; the distinction only matters upstream, where it
        // decides whether to send an invite.
        case .rejected(let detail), .inviteRequired(let detail): self = .rejected(detail)
        case .agentPaused: self = .agentPaused
        case .translationPaused(let refusal): self = .translationPaused(refusal)
        case .intentUnavailable(let roomKind): self = .unavailable("intent unavailable in a \(roomKind) room")
        // The controller shows it as the covered recording before it would get here (question 404).
        case .recordingCovered: self = .conflict
        case .serviceUnavailable: self = .unavailable("service unavailable")
        case .unauthorized: self = .unavailable("unauthorized")
        case .unavailable(let detail): self = .unavailable(detail)
        }
    }
}

@MainActor
final class NativeAgentCenterController {
    private let agentPlatformService: AgentPlatformServiceProtocol?
    private let roomID: String
    /// Matrix-side membership lookup, injected so the controller stays
    /// testable without a room proxy.
    private let roomMemberMxids: @MainActor () async -> Set<String>
    private let inviteAgent: @MainActor (String) async -> Bool
    /// Whether the local user may kick here, and the kick itself (D6): the person's own client acts (ADR-0082).
    private let canKick: @MainActor () async -> Bool
    private let kickAgent: @MainActor (String) async -> Bool
    /// Nil without a platform or a call: nothing to read or write.
    private let translationPort: NativeCallTranslationPortProtocol?
    /// The person's own edit of an agent, for the session's Agents tab to show at once (S5).
    private let agentEdited: @MainActor (AgentReadModel) -> Void

    private let snapshotSubject: CurrentValueSubject<NativeAgentCenterSnapshot, Never>
    var snapshotPublisher: AnyPublisher<NativeAgentCenterSnapshot, Never> {
        snapshotSubject.eraseToAnyPublisher()
    }

    var snapshot: NativeAgentCenterSnapshot {
        snapshotSubject.value
    }

    init(agentPlatformService: AgentPlatformServiceProtocol?,
         roomID: String,
         roomMemberMxids: @escaping @MainActor () async -> Set<String>,
         inviteAgent: @escaping @MainActor (String) async -> Bool,
         canKick: @escaping @MainActor () async -> Bool = { false },
         kickAgent: @escaping @MainActor (String) async -> Bool = { _ in false },
         translationPort: NativeCallTranslationPortProtocol? = nil,
         agentEdited: @escaping @MainActor (AgentReadModel) -> Void = { _ in },
         endingRecheckInterval: Duration = .seconds(1),
         joinPollInterval: Duration = .milliseconds(1500)) {
        self.agentPlatformService = agentPlatformService
        snapshotSubject = .init(NativeAgentCenterSnapshot(isConfigured: agentPlatformService != nil))
        self.roomID = roomID
        self.roomMemberMxids = roomMemberMxids
        self.inviteAgent = inviteAgent
        self.canKick = canKick
        self.kickAgent = kickAgent
        self.translationPort = translationPort
        self.agentEdited = agentEdited
        self.endingRecheckInterval = endingRecheckInterval
        self.joinPollInterval = joinPollInterval
    }

    // MARK: - Loading

    /// Re-reads sessions, their controls and the owner's candidate agents.
    /// This is also the reconnect path: backend truth always wins over
    /// whatever the last local action assumed.
    ///
    /// SERIALIZED, with one queued follow-up (operator's stuck "Leaving…",
    /// 2026-09-03): a removal fires a reconcile reload, and the agent's
    /// departure from the media roster rings the doorbell reload moments
    /// later — the two ran in parallel, ~7 round-trips each, and whichever
    /// finished LAST wrote the snapshot. When the earlier one had read the
    /// session mid-teardown it wrote `isEnding: true` over the later one's
    /// "gone", and nothing ever reloaded again. Now a reload requested while
    /// one is in flight runs AFTER it, exactly once, so the read that
    /// follows the departure is guaranteed to be a read that follows it.
    func reload() async {
        if reloadInFlight != nil {
            reloadRequestedWhileInFlight = true
            await reloadInFlight?.value
            return
        }
        let task = Task { await performReload() }
        reloadInFlight = task
        await task.value
        reloadInFlight = nil
        if reloadRequestedWhileInFlight {
            reloadRequestedWhileInFlight = false
            await reload()
        }
    }

    private var reloadInFlight: Task<Void, Never>?
    private var reloadRequestedWhileInFlight = false

    private func performReload() async {
        guard let agentPlatformService else {
            snapshotSubject.value = NativeAgentCenterSnapshot()
            return
        }

        var pending = snapshotSubject.value
        pending.isLoading = true
        snapshotSubject.value = pending

        let contexts: [VoiceSessionControlContext]
        switch await agentPlatformService.voiceSessionControlContexts(roomID: roomID) {
        case .success(let value):
            contexts = value
        case .failure(let error):
            // A failed re-read is NOT "no sessions": the last known control
            // register stays (the error card says the platform is behind),
            // and an entry point that was available does not vanish for one
            // timeout. Only a platform that never answered is unavailable.
            let last = snapshotSubject.value
            finishLoad(sessions: last.sessions,
                       candidates: last.candidates,
                       availableLanguages: last.availableLanguages,
                       isAvailable: last.isAvailable,
                       error: .init(error))
            // A failed read in a teardown's window must not end the re-reads,
            // or "Removing…" waits for the next doorbell. Still capped.
            scheduleEndingRecheck(isAnySessionEnding: last.sessions.contains(where: \.isEnding))
            return
        }

        var sessions: [NativeAgentCenterSession] = []
        // One retry budget for the whole read: sessions read one after another, and each 503 retried on its own
        // would keep the load (and a reload queued behind it) waiting seconds per session.
        var retries = Self.controlsRetryBudget
        for context in contexts {
            switch await Self.readControls(sessionID: context.sessionID, from: agentPlatformService, retries: &retries) {
            case .success(let controls):
                sessions.append(Self.session(context: context, controls: controls))
            case .failure(.gone):
                // The session ended between the list and the read; simply drop
                // it instead of failing the whole load.
                continue
            case .failure(let error):
                MXLog.warning("Agent center: controls read failed for \(context.sessionID): \(error)")
                sessions.append(Self.session(context: context, controls: nil))
            }
        }

        // The owner's own sessions that are gone since the last read, other than a join still being followed: one
        // of them may have been stopped by the AI limit.
        let ended = snapshotSubject.value.sessions.filter { previous in
            previous.canControl && pendingJoinFollow[previous.sessionID] == nil && !sessions.contains { $0.sessionID == previous.sessionID }
        }

        // A failed list keeps the agents already known; with none known it is "couldn't check", never "you have
        // no assistant" (question 401, checklist 1).
        let loadedCandidates = await loadCandidates(agentPlatformService)
        let candidates = loadedCandidates ?? snapshotSubject.value.candidates
        let ownAgentsUnread = loadedCandidates == nil && snapshotSubject.value.ownAgentMxids.isEmpty
        let availableLanguages = await translationPort?.languages() ?? snapshotSubject.value.availableLanguages
        let canRemoveOthers = await canKick()
        // Before the snapshot that says the platform answered: what reads that answer (the chat's tool at the call's
        // start) must find the facts in it.
        await refreshTranslationFacts()
        // Why an own session ended lands with the snapshot that drops it, so the sheet never says "no assistants" in
        // between (question 401, remark 10).
        for session in ended {
            await noteStop(session, candidates: candidates, service: agentPlatformService)
        }
        finishLoad(sessions: sessions,
                   candidates: candidates,
                   availableLanguages: availableLanguages,
                   isAvailable: true,
                   error: ownAgentsUnread ? .unavailable("own agents unread") : nil)
        var loaded = snapshotSubject.value
        loaded.canRemoveOthersFromChat = canRemoveOthers
        snapshotSubject.value = loaded
        scheduleEndingRecheck(isAnySessionEnding: sessions.contains(where: \.isEnding))
    }

    // MARK: - The AI limit mid-call (D7, D10)

    /// Reads why an own session ended: on the AI limit, the call screen's line and the reason on the agent's add row;
    /// on a consent stop, the reason on the row only (flows N6). A read that fails says nothing: the session may have
    /// ended for any reason.
    private func noteStop(_ session: NativeAgentCenterSession,
                          candidates: [NativeAgentCenterCandidate],
                          service: AgentPlatformServiceProtocol) async {
        guard case .success(.ended(let reason)) = await service.voiceSessionProgress(sessionID: session.sessionID) else { return }
        let agentID = candidates.first { $0.mxid == session.agentMxid }?.id

        let stop: NativeAgentCenterLimitStop?
        let failure: NativeAgentCenterJoinFailure
        switch reason {
        case .budgetReached:
            let usage = await usage(of: agentID, service: service)
            stop = .limitReached(isWeekly: usage?.current.period == .week)
            failure = .budgetReached
        case .categoryPaused(let category):
            let pause = await categoryPause(category, of: agentID, service: service)
            if case .until(let date) = pause {
                stop = .categoryPaused(category, until: date)
            } else {
                stop = .categoryPaused(category, until: nil)
            }
            failure = .categoryPaused(category, pause)
        case .optOut, .aiConsentOwner, .aiConsentRoom:
            guard let consent = NativeAgentCenterJoinFailure(reason) else { return }
            stop = nil
            failure = consent
        case .callEnded, .manual, .ownerLeft, .translationNotHere, .failed, .unknown:
            return
        }

        var pending = snapshotSubject.value
        if let stop {
            pending.limitStop = stop
        }
        if let agentID {
            pending.joinFailures[agentID] = failure
        }
        snapshotSubject.value = pending
    }

    /// A category's pause from the agent's usage; nil when it could not be read, or says no pause.
    private func categoryPause(_ category: AgentUsage.Category, of agentID: String?, service: AgentPlatformServiceProtocol) async -> AgentUsage.Pause? {
        await usage(of: agentID, service: service)?.current.categories.first { $0.category == category }?.pause
    }

    /// The agent's usage for the line's date and period; nil when it could not be read.
    private func usage(of agentID: String?, service: AgentPlatformServiceProtocol) async -> AgentUsage? {
        guard let agentID else { return nil }
        switch await service.fetchAgentUsage(agentID: agentID) {
        case .success(let usage):
            return usage
        case .failure(let error):
            MXLog.warning("Agent center: usage read failed after a limit stop: \(error)")
            return nil
        }
    }

    // MARK: - Teardown re-reads

    /// Walk F6: a removed session stays `ending` for a second or two, and
    /// while it does its agent is neither on a card nor offered to add. The
    /// only re-read used to be the room's doorbell, which rings when the
    /// agent leaves the ROOM — after it has posted its recording and summary,
    /// ~33 s later. So an `ending` read re-reads on its own until the session
    /// is gone, and the agent can be added again as soon as the platform lets go.
    private let endingRecheckInterval: Duration
    /// Bounds the re-reads for a teardown that never converges (~30 s at the
    /// default interval); the doorbell still covers what comes after.
    private static let endingRecheckLimit = 30
    private var endingRechecks = 0
    /// Test seam, like `pendingReconcile`.
    private(set) var pendingEndingRecheck: Task<Void, Never>?

    private func scheduleEndingRecheck(isAnySessionEnding: Bool) {
        guard isAnySessionEnding else {
            endingRechecks = 0
            return
        }
        guard pendingEndingRecheck == nil, endingRechecks < Self.endingRecheckLimit else { return }
        endingRechecks += 1
        pendingEndingRecheck = Task { [weak self, endingRecheckInterval] in
            try? await Task.sleep(for: endingRecheckInterval)
            guard let self, !Task.isCancelled else { return }
            pendingEndingRecheck = nil
            await reload()
        }
    }

    // MARK: - Actions

    /// Set by `stop()`: the call is over for this agent center.
    private(set) var isStopped = false

    /// Adds an agent to this call. An invite-only room refuses the attach
    /// until the agent is a member, so that one rejection — and only that
    /// one — is retried after inviting. The backend's invite-required answer
    /// decides, not the room's local membership, which can lag the backend
    /// letting the agent go after a refused attach. A 503 is retried in
    /// `sendAttach`, re-inviting at most once. A call that ends meanwhile
    /// stops the tap: nothing more is sent. A refusal lands on the agent's
    /// own add row (question 387, F3), and an accepted attach is followed
    /// until the agent is in the call or its session says why it never got
    /// there (B1).
    func attach(agentID: String, params: VoiceAttachParams) async -> Bool {
        guard let agentPlatformService, !isStopped else { return false }

        guard let candidate = snapshotSubject.value.candidates.first(where: { $0.id == agentID }) else {
            setJoinFailure(.failed, for: agentID)
            return false
        }
        var cleared = snapshotSubject.value
        cleared.joinFailures[agentID] = nil
        cleared.acceptedAttaches.remove(agentID)
        snapshotSubject.value = cleared

        var reinvited = false
        guard var result = await sendAttach(agentID: agentID, agentMxid: candidate.mxid, params: params,
                                            service: agentPlatformService, reinvited: &reinvited) else { return false }

        if !reinvited, case .failure(let error) = result, Self.isInviteRequired(error) {
            guard !isStopped else { return false }
            // Listed as a member yet refused as one: the local membership lags, so this invite is the tap's re-invite.
            if candidate.isRoomMember { reinvited = true }
            guard await inviteAgent(candidate.mxid) else {
                guard !isStopped else { return false }
                // An ask-to-join room: only admins may add members (D8).
                await reload()
                setJoinFailure(.askToJoin, for: agentID)
                return false
            }
            guard let next = await sendAttach(agentID: agentID, agentMxid: candidate.mxid, params: params,
                                              service: agentPlatformService, reinvited: &reinvited) else { return false }
            result = next
        }

        // The call ended while the answer was on its way: nothing more to show or follow.
        guard !isStopped else { return false }

        switch result {
        case .success(let sessionID):
            var pending = snapshotSubject.value
            pending.limitStop = nil
            pending.acceptedAttaches.insert(agentID)
            pending.joinStartedAt[sessionID] = pending.joinStartedAt[sessionID] ?? Date()
            snapshotSubject.value = pending
            await reload()
            followJoin(sessionID: sessionID, agentID: agentID)
            return true
        case .failure(.recordingCovered(let cover)):
            // Before the re-read, so the button never shows a start that can't happen while it runs.
            setRecordingRefusal(cover)
            await reload()
            return false
        case .failure(let error):
            Self.logQuietRefusal(error)
            await reload()
            setJoinFailure(Self.joinFailure(error), for: agentID)
            return false
        }
    }

    /// One attach as the tap sends it. A 503 (ADR-0094 A.2: the room couldn't be read, or another attach holds it) is
    /// tried once more after its `Retry-After`. The backend lets the assistant go again when the attach that joined it
    /// is refused, so that retry can meet an invite-required refusal: the assistant is then re-invited, silently like
    /// the tap's own invite, and the attach goes once more (operator, 2026-11-23). One re-invite per tap; whatever
    /// comes after it is the answer. `nil` when the call ended or the tap was cancelled during the wait: nothing more
    /// is sent and nothing is shown.
    private func sendAttach(agentID: String,
                            agentMxid: String,
                            params: VoiceAttachParams,
                            service: AgentPlatformServiceProtocol,
                            reinvited: inout Bool) async -> Result<String, VoiceControlsError>? {
        guard !isStopped else { return nil }
        let first = await service.attachVoiceAgent(agentID: agentID, roomID: roomID, params: params)
        guard case .failure(.serviceUnavailable(let retryAfter)) = first else { return first }
        MXLog.info("Agent center: attach unavailable, retrying once after \(retryAfter)")
        do {
            try await Task.sleep(for: retryAfter)
        } catch {
            MXLog.info("Agent center: the add was cancelled during the attach's wait; not retrying")
            return nil
        }
        guard !isStopped else {
            MXLog.info("Agent center: the call ended during the attach's wait; not retrying")
            return nil
        }

        let retried = await service.attachVoiceAgent(agentID: agentID, roomID: roomID, params: params)
        guard !reinvited, case .failure(let error) = retried, Self.isInviteRequired(error) else { return retried }
        guard !isStopped else { return nil }
        reinvited = true
        // A refused invite is an ask-to-join room (D8): the invite-required answer says so on the add row.
        guard await inviteAgent(agentMxid) else { return retried }
        guard !isStopped else { return nil }
        return await service.attachVoiceAgent(agentID: agentID, roomID: roomID, params: params)
    }

    /// The call this agent center serves has ended, or its screen stopped: an add still waiting to retry sends
    /// nothing more, so no assistant is attached to, or invited into, a call the person left.
    func stop() {
        isStopped = true
    }

    /// `translation-intent-unavailable` (ADR-0094 A.2) is the app's own mistake, never the person's: refused quietly,
    /// with the room kind for whoever reads the log.
    private static func logQuietRefusal(_ error: VoiceControlsError) {
        if case .intentUnavailable(let roomKind) = error {
            MXLog.error("Agent center: the translation intent was refused in a \(roomKind) room")
        }
    }

    /// Lets go of a join that is taking too long (N8): the same teardown as Remove.
    func cancelJoin(sessionID: String) async -> Bool {
        await remove(sessionID: sessionID)
    }

    /// Takes the owner's pause off (F3a), then asks again whether the agent can come.
    func resume(agentID: String) async -> Bool {
        guard let agentPlatformService else { return false }
        var patch = AgentEditPatch()
        patch.paused = false
        switch await agentPlatformService.editAgent(agentID: agentID, patch: patch) {
        case .success(let readModel):
            agentEdited(readModel)
            setJoinFailure(nil, for: agentID)
            await reload()
            await refreshJoinChecks()
            return true
        case .failure(let error):
            MXLog.warning("Agent center: resume failed for \(agentID): \(error)")
            setError(.unavailable("resume failed"), scope: .agent(agentID))
            return false
        }
    }

    /// Removes someone else's assistant from the chat (D6): a Matrix kick from this person's own client, which ends
    /// its call session. Only offered with kick rights.
    func removeFromChat(agentMxid: String) async -> Bool {
        guard await kickAgent(agentMxid) else {
            setError(.unavailable("kick refused"), scope: .foreign(agentMxid))
            return false
        }
        await reload()
        return true
    }

    /// Asks the backend, for each own agent not in the call, whether it can come (B4). A check that could not be read
    /// leaves no entry: the sheet then offers the plain add, and the attach still says why.
    func refreshJoinChecks() async {
        guard let agentPlatformService else { return }
        var checking = snapshotSubject.value
        checking.isCheckingJoins = true
        snapshotSubject.value = checking
        let snapshot = checking
        var checks: [String: VoiceJoinCheckReason] = [:]
        for candidate in snapshot.candidates where !snapshot.attachedAgentMxids.contains(candidate.mxid) {
            guard case .success(let reason) = await agentPlatformService.voiceJoinCheck(agentID: candidate.id, roomID: roomID) else { continue }
            if case .categoryPaused = reason {
                // The check names no date; the usage says until when Calls are paused.
                checks[candidate.id] = await .categoryPaused(categoryPause(.calls, of: candidate.id, service: agentPlatformService))
            } else {
                checks[candidate.id] = reason
            }
        }
        var pending = snapshotSubject.value
        pending.joinChecks = checks
        pending.joinChecksAsked.formUnion(snapshot.candidates.map(\.id))
        pending.isCheckingJoins = false
        snapshotSubject.value = pending
    }

    /// The consent prompt the sheet shows for "Allow AI" (F3b): Brief 0078's own screen and words.
    /// The weekly Limit page for an own agent (Brief 0079 3c), read through its own store: "My limit" next to a limit's
    /// refusal (question 401, board A). Nil without a platform.
    func makeUsageViewModel(agentID: String) -> AgentUsageScreenViewModel? {
        guard let agentPlatformService else { return nil }
        return AgentUsageScreenViewModel(agentID: agentID, store: AgentsStore(service: agentPlatformService))
    }

    func makeAIConsentViewModel() -> AIConsentPromptScreenViewModel? {
        agentPlatformService.map {
            AIConsentPromptScreenViewModel(store: AgentsStore(service: $0), privacyURL: SpiralEnvironment.current.privacyURL)
        }
    }

    // MARK: - Following a join (B1, N8)

    private let joinPollInterval: Duration
    /// About three minutes at the default interval; a ringing call waits without a timeout on screen, and the
    /// doorbell reload still covers a join that lands later.
    private static let joinPollLimit = 120
    /// Test seam, like `pendingReconcile`.
    private(set) var pendingJoinFollow: [String: Task<Void, Never>] = [:]

    private func followJoin(sessionID: String, agentID: String) {
        pendingJoinFollow[sessionID]?.cancel()
        pendingJoinFollow[sessionID] = Task { [weak self, joinPollInterval] in
            for _ in 0..<Self.joinPollLimit {
                guard let self, !Task.isCancelled,
                      let service = agentPlatformService else { return }
                switch await service.voiceSessionProgress(sessionID: sessionID) {
                case .success(.joining):
                    break
                case .success(.active), .success(.ending), .failure(.gone):
                    finishFollowing(sessionID: sessionID)
                    return
                case .success(.ended(let reason)):
                    finishFollowing(sessionID: sessionID)
                    await reload()
                    setJoinFailure(NativeAgentCenterJoinFailure(reason), for: agentID)
                    return
                case .failure(let error):
                    // A failed read is not an end: keep asking.
                    MXLog.warning("Agent center: join progress read failed for \(sessionID): \(error)")
                }
                try? await Task.sleep(for: joinPollInterval)
            }
            self?.finishFollowing(sessionID: sessionID)
        }
    }

    private func finishFollowing(sessionID: String) {
        pendingJoinFollow[sessionID] = nil
        var pending = snapshotSubject.value
        pending.joinStartedAt[sessionID] = nil
        snapshotSubject.value = pending
    }

    private func setRecordingRefusal(_ cover: VoiceRecordingCover) {
        var pending = snapshotSubject.value
        pending.recordingRefusal = NativeAgentCenterRecordingRefusal(cover: cover, at: Date())
        snapshotSubject.value = pending
    }

    private func setJoinFailure(_ failure: NativeAgentCenterJoinFailure?, for agentID: String) {
        var pending = snapshotSubject.value
        pending.joinFailures[agentID] = failure
        snapshotSubject.value = pending
    }

    private static func joinFailure(_ error: VoiceControlsError) -> NativeAgentCenterJoinFailure {
        switch error {
        case .agentPaused: .paused
        case .inviteRequired: .askToJoin
        case .conflict: .cannotJoinCalls
        case .translationPaused(let refusal):
            switch refusal.reason {
            case .aiLimit: .budgetReached
            case .translationPaused, .callCap: .categoryPaused(.callTranslation, refusal.pauseUntil.map(AgentUsage.Pause.until) ?? .untilChanged)
            }
        case .gone, .rejected, .intentUnavailable, .recordingCovered, .serviceUnavailable, .unauthorized, .unavailable: .failed
        }
    }

    /// Removes the agent from the call. The backend tears the session down
    /// live and delivers whatever artifacts it owes.
    func remove(sessionID: String) async -> Bool {
        guard let agentPlatformService else { return false }

        switch await agentPlatformService.endVoiceSession(sessionID: sessionID) {
        case .success, .failure(.gone):
            // 204 means the teardown is REQUESTED, not finished — the row
            // stays `ending` while the runtime lets go. Mark it locally so
            // the tap lands on screen at once; a full `reload()` here cost
            // ~7 sequential round-trips and repainted the identical row,
            // which is what made the button feel dead. `.gone` is the same
            // outcome the caller wanted.
            markEnding(sessionID: sessionID)
            // Reconcile OFF the interaction path. Needed as a backstop as
            // well as a refresh: an agent that never reached the media
            // plane publishes no state document, so the doorbell that
            // normally reloads us would never ring for it.
            reconcileAfterRemoval()
            return true
        case .failure(let error):
            await reloadReporting(.init(error), scope: .session(sessionID, .remove))
            return false
        }
    }

    /// Flip one session to "leaving" without touching anything else — the
    /// session stays LISTED on purpose. Dropping it here would hand the
    /// agent back to "Add an agent" while it is still leaving, and would
    /// demote the owner's own agent into the read-only "View only" card,
    /// because it is still in the room's roster for a moment longer.
    private func markEnding(sessionID: String) {
        var pending = snapshotSubject.value
        guard let index = pending.sessions.firstIndex(where: { $0.sessionID == sessionID }) else { return }
        pending.sessions[index].isEnding = true
        Self.record(.leaving, for: pending.sessions[index].agentMxid, in: &pending, expiresAt: Self.ownerWriteExpiry(from: Date()))
        snapshotSubject.send(pending)
        rescheduleSweep()
    }

    /// Handle on the off-path reconcile so tests can await the very thing
    /// production deliberately does NOT await. Without this seam the only
    /// way to test the backstop would be a sleep.
    private(set) var pendingReconcile: Task<Void, Never>?

    private func reconcileAfterRemoval() {
        pendingReconcile = Task { [weak self] in
            await self?.reload()
        }
    }

    /// Flips one on/off control. The CAS revision comes from the snapshot,
    /// so a stale local view fails as `conflict` instead of overwriting a
    /// concurrent change.
    ///
    /// Turning a switch ON is optimistic from the tap and rolled back on
    /// refusal: a call that started silent answers the conversation write
    /// only once its Realtime conversation runs — seconds — and the toggle
    /// used to snap back for all of them. Turning one OFF shows the
    /// confirmed state until the server answers. One write per switch at
    /// a time: the rollback restores what the tap superseded, which a
    /// second write would have clobbered.
    func setSwitch(sessionID: String, control: VoiceSessionSwitch, enabled: Bool) async -> Bool {
        guard let agentPlatformService,
              let session = snapshotSubject.value.sessions.first(where: { $0.sessionID == sessionID }) else {
            setError(.gone, scope: .session(sessionID, Self.row(of: control)))
            return false
        }

        guard session.canControl else {
            setError(.notOwner, scope: .session(sessionID, Self.row(of: control)))
            return false
        }

        let inFlight = SwitchWrite(sessionID: sessionID, control: control)
        guard switchWritesInFlight.insert(inFlight).inserted else {
            MXLog.warning("Agent center: a \(control.rawValue) write is already out for \(sessionID); dropping the second tap")
            return false
        }
        defer { switchWritesInFlight.remove(inFlight) }

        let fact = NativeAgentCenterPendingWrite.Fact.switched(control, to: enabled)
        // Optimism only toward disclosure — the microphone button's rule
        // (`NativeCallScreenViewModel.toggleMicrophone`): showing "muted"
        // while still publishing is a privacy defect, not a cosmetic one.
        // An early "recording / summarising / talking" over-discloses, which
        // is safe; an early "stopped / silent" would hide a recorder still
        // capturing for the length of the write, and until the rollback on
        // a refusal.
        let superseded = enabled ? recordInFlight(fact, for: session.agentMxid) : nil
        // A backstop, not the rollback: the tap must never outlive its write,
        // even when the session vanished from the snapshot meanwhile and
        // `apply` had nothing to start the clock on. It restores nothing —
        // on that path the server ACCEPTED the write, so what the tap
        // superseded is exactly what the server just overrode.
        defer { withdrawInFlight(fact, for: session.agentMxid, restoring: nil) }

        switch await agentPlatformService.setVoiceSwitch(sessionID: sessionID,
                                                         control: control,
                                                         enabled: enabled,
                                                         revision: session.revision(of: control)) {
        case .success(let controls):
            apply(controls: controls, sessionID: sessionID, written: fact)
            return true
        case .failure(.recordingCovered(let cover)):
            // Question 404: not a failure to retry — the button shows who records instead.
            withdrawInFlight(fact, for: session.agentMxid, restoring: superseded)
            setRecordingRefusal(cover)
            await reload()
            return false
        case .failure(let error):
            // An ON tap is rolled back before the re-read, which takes
            // several round trips (an OFF tap bridged nothing). Conflict and
            // gone both mean our view of the world is stale, so the only
            // honest next step is to re-read it.
            withdrawInFlight(fact, for: session.agentMxid, restoring: superseded)
            await reloadReporting(Self.switchError(error, control: control, enabled: enabled),
                                  scope: .session(sessionID, Self.row(of: control)))
            return false
        }
    }

    private static func row(of control: VoiceSessionSwitch) -> NativeAgentCenterErrorScope.Row {
        switch control {
        case .recording: .recording
        case .summary: .summary
        case .conversation: .mainJob
        }
    }

    private struct SwitchWrite: Hashable {
        let sessionID: String
        let control: VoiceSessionSwitch
    }

    private var switchWritesInFlight: Set<SwitchWrite> = []

    private static func switchError(_ error: VoiceControlsError, control: VoiceSessionSwitch, enabled: Bool) -> NativeAgentCenterError {
        if control == .conversation, enabled, case .rejected(let detail) = error {
            return .conversationRefused(detail)
        }
        return .init(error)
    }

    /// An enabling translation write (ADR-0094 A.2): turning it on, changing its language, «Продолжить». The CAS
    /// revision comes from the snapshot so a stale view conflicts instead of clobbering. A pause or limit refusal says
    /// why on the call screen and in the sheet; a refused form is quiet.
    func setTranslation(sessionID: String, params: VoiceTranslationParams) async -> Bool {
        guard let agentPlatformService,
              let session = snapshotSubject.value.sessions.first(where: { $0.sessionID == sessionID }) else {
            setError(.gone, scope: .session(sessionID, .translation))
            return false
        }
        guard session.canControl else {
            setError(.notOwner, scope: .session(sessionID, .translation))
            return false
        }

        switch await agentPlatformService.setVoiceTranslation(sessionID: sessionID,
                                                              params: params,
                                                              revision: session.translation.revision) {
        case .success(let controls):
            apply(controls: controls, sessionID: sessionID, written: .translation(languages: params.languages))
            return true
        case .failure(.intentUnavailable(let roomKind)):
            Self.logQuietRefusal(.intentUnavailable(roomKind: roomKind))
            await reload()
            return false
        case .failure(.translationPaused(let refusal)):
            await reload()
            var pending = snapshotSubject.value
            pending.limitStop = NativeAgentCenterLimitStop(refusal)
            snapshotSubject.value = pending
            setError(.translationPaused(refusal), scope: .session(sessionID, .translation))
            return false
        case .failure(let error):
            await reloadReporting(.init(error), scope: .session(sessionID, .translation))
            return false
        }
    }

    func disableTranslation(sessionID: String) async -> Bool {
        guard let agentPlatformService,
              let session = snapshotSubject.value.sessions.first(where: { $0.sessionID == sessionID }) else {
            setError(.gone, scope: .session(sessionID, .mainJob))
            return false
        }
        guard session.canControl else {
            setError(.notOwner, scope: .session(sessionID, .mainJob))
            return false
        }
        switch await agentPlatformService.disableVoiceTranslation(sessionID: sessionID,
                                                                  revision: session.translation.revision) {
        case .success(let controls):
            apply(controls: controls, sessionID: sessionID, written: .translation(languages: []))
            return true
        case .failure(let error):
            await reloadReporting(.init(error), scope: .session(sessionID, .mainJob))
            return false
        }
    }

    // MARK: - Translation for everyone (Brief 0085)

    /// Publishes "my language" with the call membership (ADR-0094 A.1); the facts are read again so the call sees it.
    func publishMyLanguage(_ language: String) async -> Bool {
        guard let translationPort else { return false }
        let isPublished = await translationPort.publishMyLanguage(language, roomID: roomID)
        await refreshTranslationFacts()
        return isPublished
    }

    /// Stores this chat's personal tool "Call translation" (A.5, row 14), then reads it back.
    func setTranslationTool(_ tool: NativeCallTranslationTool) async -> Bool {
        guard let translationPort, await translationPort.setTool(tool, roomID: roomID) else {
            setError(.unavailable("tool not stored"), scope: .translationTool)
            return false
        }
        var pending = snapshotSubject.value
        pending.translationFacts.tool = tool.isEnabled ? tool : nil
        snapshotSubject.value = pending
        await refreshTranslationFacts()
        return true
    }

    /// The participants' languages alone, as the memberships change: no platform round trip.
    func refreshParticipantLanguages() async {
        guard let languages = await translationPort?.participantLanguages(roomID: roomID),
              languages != snapshotSubject.value.translationFacts.languages else { return }
        var pending = snapshotSubject.value
        pending.translationFacts.languages = languages
        snapshotSubject.value = pending
    }

    /// Reads the participants' languages and the chat's tool, without the sessions' round trips. A read that fails
    /// keeps what was known.
    func refreshTranslationFacts() async {
        guard let translationPort else { return }
        let languages = await translationPort.participantLanguages(roomID: roomID)
        let tool = await translationPort.tool(roomID: roomID)
        var pending = snapshotSubject.value
        if let languages {
            pending.translationFacts.languages = languages
        }
        if case .success(let tool) = tool {
            pending.translationFacts.tool = tool
        }
        snapshotSubject.value = pending
    }

    func clearError() {
        var pending = snapshotSubject.value
        pending.lastError = nil
        snapshotSubject.value = pending
    }

    // MARK: - Private

    /// Re-reads backend truth after a failed action while keeping the reason
    /// the action failed. A plain `reload` clears the error, which would hide
    /// exactly the conflict or rejection the owner needs to see.
    private func reloadReporting(_ error: NativeAgentCenterError, scope: NativeAgentCenterErrorScope = .global) async {
        await reload()
        setError(error, scope: scope)
    }

    /// Nil when the list could not be read.
    private func loadCandidates(_ service: AgentPlatformServiceProtocol) async -> [NativeAgentCenterCandidate]? {
        switch await service.listMyPersonalAgents() {
        case .failure(let error):
            MXLog.warning("Agent center: listMyPersonalAgents failed: \(error)")
            return nil
        case .success(let view):
            let members = await roomMemberMxids()
            var pending = snapshotSubject.value
            pending.ownAgentMxids = Set(view.agents.map(\.matrixUserID))
            snapshotSubject.value = pending
            return view.agents
                .filter { $0.lifecycleState == "active" || $0.lifecycleState == "suspended" }
                .map { agent in
                    // The platform name wins; the localpart rule is the LAST
                    // resort, for a record whose name is somehow empty — not
                    // the default it used to be.
                    let name = agent.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    return NativeAgentCenterCandidate(id: agent.id,
                                                      mxid: agent.matrixUserID,
                                                      displayName: name.isEmpty
                                                          ? NativeCallFallbackName.make(mxid: agent.matrixUserID)
                                                          : name,
                                                      avatarURL: agent.avatarMXC.flatMap(URL.init(string:)),
                                                      isRoomMember: members.contains(agent.matrixUserID),
                                                      isPaused: agent.lifecycleState == "suspended")
                }
        }
    }

    private func finishLoad(sessions: [NativeAgentCenterSession],
                            candidates: [NativeAgentCenterCandidate],
                            availableLanguages: [VoiceControlsCatalogLanguage] = [],
                            isAvailable: Bool,
                            error: NativeAgentCenterError?) {
        var pending = NativeAgentCenterSnapshot(isConfigured: snapshotSubject.value.isConfigured,
                                                isAvailable: isAvailable,
                                                isLoading: false,
                                                sessions: sessions,
                                                candidates: candidates,
                                                availableLanguages: availableLanguages,
                                                lastError: error)
        pending.pendingOwnerWrites = snapshotSubject.value.pendingOwnerWrites
        let previous = snapshotSubject.value
        pending.ownAgentMxids = previous.ownAgentMxids
        pending.joinChecks = previous.joinChecks
        pending.joinChecksAsked = previous.joinChecksAsked
        pending.isCheckingJoins = previous.isCheckingJoins
        pending.joinFailures = previous.joinFailures
        pending.joinStartedAt = previous.joinStartedAt
        pending.acceptedAttaches = previous.acceptedAttaches
        pending.limitStop = previous.limitStop
        pending.canRemoveOthersFromChat = previous.canRemoveOthersFromChat
        pending.translationFacts = previous.translationFacts
        pending.recordingRefusal = previous.recordingRefusal
        // A refusal on a row stays until the next write or the sheet closes: the re-read that the write's own effect
        // rings (the doorbell) used to wipe it before it was seen (question 401, remark 8). Only a global error is
        // the platform's state, and a good read answers it.
        if error == nil, previous.lastError != nil, previous.lastErrorScope != .global {
            pending.lastError = previous.lastError
            pending.lastErrorScope = previous.lastErrorScope
        }
        snapshotSubject.value = pending
    }

    /// `written` is THE fact the owner's tap changed — the only one the
    /// bridge may carry. The rest of the controls response is control
    /// state; recording it too would re-open the window for facts the tap
    /// never touched (critic, 2026-09-03: a Summary toggle lighting REC).
    private func apply(controls: VoiceControlsState, sessionID: String, written: NativeAgentCenterPendingWrite.Fact) {
        var pending = snapshotSubject.value
        guard let index = pending.sessions.firstIndex(where: { $0.sessionID == sessionID }) else { return }

        let existing = pending.sessions[index]
        pending.sessions[index] = NativeAgentCenterSession(sessionID: existing.sessionID,
                                                           agentMxid: existing.agentMxid,
                                                           canControl: existing.canControl,
                                                           // Preserved, not re-derived: a controls
                                                           // response says nothing about lifecycle,
                                                           // and dropping it here would un-say
                                                           // "Leaving…" mid-teardown.
                                                           isEnding: existing.isEnding,
                                                           recording: .init(controls.artifacts.recording),
                                                           summary: .init(controls.artifacts.summary),
                                                           translation: .init(controls),
                                                           conversation: .init(controls.conversation))
        pending.lastError = nil
        // The owner's optimism, time-bounded: what the server just accepted
        // shows at once (an ON tap already did), and expires unless the
        // agent's document agrees.
        Self.record(written, for: pending.sessions[index].agentMxid, in: &pending, expiresAt: Self.ownerWriteExpiry(from: Date()))
        snapshotSubject.value = pending
        rescheduleSweep()
    }

    // MARK: - Owner optimism (the ONE bridge)

    /// How long a tap may stand in for the document. Longer hides a
    /// runtime that silently refused; shorter flickers on a slow republish.
    static let ownerWriteWindow: TimeInterval = 10

    private static func ownerWriteExpiry(from now: Date) -> Date {
        now.addingTimeInterval(ownerWriteWindow)
    }

    private static func record(_ fact: NativeAgentCenterPendingWrite.Fact,
                               for agentMxid: String,
                               in snapshot: inout NativeAgentCenterSnapshot,
                               expiresAt: Date?) {
        var writes = snapshot.pendingOwnerWrites[agentMxid, default: []]
        // One write per fact kind: the newest tap replaces the older one.
        writes.removeAll { $0.fact.kind == fact.kind }
        writes.append(.init(fact: fact, expiresAt: expiresAt))
        snapshot.pendingOwnerWrites[agentMxid] = writes
    }

    /// The tap shows before the write leaves, with no window yet — the
    /// server's answer opens it. Returns the write this one supersedes, so
    /// a refusal can put it back.
    private func recordInFlight(_ fact: NativeAgentCenterPendingWrite.Fact, for agentMxid: String) -> NativeAgentCenterPendingWrite? {
        var pending = snapshotSubject.value
        let superseded = pending.pendingOwnerWrites[agentMxid]?.first { $0.fact.kind == fact.kind }
        Self.record(fact, for: agentMxid, in: &pending, expiresAt: nil)
        snapshotSubject.value = pending
        return superseded
    }

    /// Rolls an unanswered tap back to what it superseded. A no-op once the
    /// server's answer started its clock, or the document settled it — the
    /// document rules from there.
    private func withdrawInFlight(_ fact: NativeAgentCenterPendingWrite.Fact,
                                  for agentMxid: String,
                                  restoring superseded: NativeAgentCenterPendingWrite?) {
        var pending = snapshotSubject.value
        var writes = pending.pendingOwnerWrites[agentMxid] ?? []
        guard let index = writes.firstIndex(of: .init(fact: fact, expiresAt: nil)) else { return }
        writes.remove(at: index)
        if let superseded {
            writes.append(superseded)
        }
        pending.pendingOwnerWrites[agentMxid] = writes.isEmpty ? nil : writes
        snapshotSubject.value = pending
        rescheduleSweep()
    }

    /// The document caught up: every pending write whose fact the claim
    /// now STATES is settled — the document rules from there. A document
    /// that still disagrees is indistinguishable from one that has not
    /// republished yet, so the write stands until the clock retires it;
    /// a refusal therefore shows for at most the window, never longer.
    /// Called by the view model on every claims change.
    func settleOwnerWrites(against claims: NativeCallAgentClaims) {
        var pending = snapshotSubject.value
        var changed = false
        for (mxid, writes) in pending.pendingOwnerWrites {
            guard let document = claims.documents[mxid] else { continue }
            let remaining = writes.filter { write in
                switch write.fact {
                case .recording(let value): document.isRecording != value
                case .summary(let value): document.isSummaryArmed != value
                case .conversation(let value): document.isConversationActive != value
                case .translation(let languages): Set(document.translation.languages) != Set(languages)
                case .leaving: document.lifecycle != .leaving
                }
            }
            if remaining.count != writes.count {
                pending.pendingOwnerWrites[mxid] = remaining.isEmpty ? nil : remaining
                changed = true
            }
        }
        if changed {
            snapshotSubject.value = pending
        }
    }

    private var sweepTask: Task<Void, Never>?

    /// Retire expired optimism and REPUBLISH, so an expired write can
    /// never sit on screen waiting for an unrelated change to re-render.
    /// Always armed for the EARLIEST expiry: a later write must not push
    /// the sweep past an earlier one's window. A write still out has none.
    private func rescheduleSweep() {
        sweepTask?.cancel()
        guard let next = snapshotSubject.value.pendingOwnerWrites.values.flatMap({ $0 }).compactMap(\.expiresAt).min() else {
            sweepTask = nil
            return
        }
        sweepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow) + 0.05))
            guard !Task.isCancelled else { return }
            self?.sweepExpiredOwnerWrites(now: Date())
        }
    }

    func sweepExpiredOwnerWrites(now: Date) {
        var pending = snapshotSubject.value
        let before = pending.pendingOwnerWrites
        pending.pendingOwnerWrites = before.compactMapValues { writes in
            let live = writes.filter { $0.isLive(at: now) }
            return live.isEmpty ? nil : live
        }
        if pending.pendingOwnerWrites != before {
            snapshotSubject.value = pending
        }
        rescheduleSweep()
    }

    /// The earliest pending expiry — the sweep's next alarm. Test seam.
    var nextOwnerWriteExpiry: Date? {
        snapshotSubject.value.pendingOwnerWrites.values.flatMap { $0 }.compactMap(\.expiresAt).min()
    }

    private func setError(_ error: NativeAgentCenterError, scope: NativeAgentCenterErrorScope = .global) {
        var pending = snapshotSubject.value
        pending.lastError = error
        pending.lastErrorScope = scope
        snapshotSubject.value = pending
    }

    /// Retries of a 503 controls read in one load, all sessions together.
    static let controlsRetryBudget = 2

    /// One session's controls. A 503 is the platform failing to read the room just now: tried again shortly while the
    /// load's budget lasts, then it counts as unread (`.unknown`, never an error); the next refresh reads it again.
    private static func readControls(sessionID: String,
                                     from service: AgentPlatformServiceProtocol,
                                     retries: inout Int) async -> Result<VoiceControlsState, VoiceControlsError> {
        var result = await service.voiceSessionControls(sessionID: sessionID)
        while retries > 0, case .failure(.serviceUnavailable(let retryAfter)) = result {
            retries -= 1
            try? await Task.sleep(for: min(retryAfter, .seconds(2)))
            result = await service.voiceSessionControls(sessionID: sessionID)
        }
        return result
    }

    private static func session(context: VoiceSessionControlContext,
                                controls: VoiceControlsState?) -> NativeAgentCenterSession {
        NativeAgentCenterSession(sessionID: context.sessionID,
                                 agentMxid: context.agentMxid,
                                 canControl: context.canControl,
                                 isEnding: context.isEnding,
                                 recording: controls.map { .init($0.artifacts.recording) } ?? .unknown,
                                 summary: controls.map { .init($0.artifacts.summary) } ?? .unknown,
                                 translation: controls.map { .init($0) } ?? .unknown,
                                 conversation: controls.map { .init($0.conversation) } ?? .unknown)
    }

    /// Whether the backend refused this attach because the room is invite-only
    /// and the agent is not in it yet — the one refusal an invite would fix.
    ///
    /// Keyed on the RFC 7807 `type` URI the backend stamps on that case. It
    /// used to be decided by lowercasing the refusal's English detail and
    /// checking it mentioned both "invite" and "join", which made a bot
    /// account's membership in a private room depend on backend copy.
    private static func isInviteRequired(_ error: VoiceControlsError) -> Bool {
        if case .inviteRequired = error { return true }
        return false
    }
}

/// The call's "Перевод звонков" screen reads and stores the chat's tool through the call (row 14).
extension NativeAgentCenterController: CallTranslationToolServiceProtocol {
    func languages() async -> [VoiceControlsCatalogLanguage]? {
        snapshot.availableLanguages.isEmpty ? await translationPort?.languages() : snapshot.availableLanguages
    }

    func translationTool() async -> Result<NativeCallTranslationTool?, NativeCallTranslationPortError> {
        await translationPort?.tool(roomID: roomID) ?? .failure(.unavailable)
    }

    func storeTranslationTool(_ tool: NativeCallTranslationTool) async -> Bool {
        await setTranslationTool(tool)
    }
}

private extension NativeAgentCenterSession {
    /// The CAS token the next write of `control` must carry.
    func revision(of control: VoiceSessionSwitch) -> Int32 {
        switch control {
        case .recording: recording.revision
        case .summary: summary.revision
        case .conversation: conversation.revision
        }
    }
}

private extension NativeAgentCenterPendingWrite.Fact {
    /// The fact a switch write changes — the only one it may bridge.
    static func switched(_ control: VoiceSessionSwitch, to enabled: Bool) -> Self {
        switch control {
        case .recording: .recording(enabled)
        case .summary: .summary(enabled)
        case .conversation: .conversation(enabled)
        }
    }
}

private extension NativeAgentCenterArtifact {
    /// Used when the controls read failed: the session exists, but nothing is
    /// claimed about its artifacts and every write is refused as stale.
    static var unknown: NativeAgentCenterArtifact {
        NativeAgentCenterArtifact(isEnabled: false, revision: 0, delivery: .notArmed, isStopped: false)
    }

    init(_ state: VoiceArtifactState) {
        isEnabled = state.enabled
        revision = state.revision
        isStopped = state.stopped

        switch state.delivery {
        case "pending": delivery = .pending
        case "delivered": delivery = .delivered(target: state.deliveryTarget)
        case "failed": delivery = .failed
        default: delivery = .notArmed
        }
    }
}
