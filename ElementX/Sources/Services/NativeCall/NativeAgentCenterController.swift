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

/// A session's live translation state: the FULL booth list the engine
/// actually runs (never a flattened projection — Brief 0062's central
/// rule), the style, the source of truth and the CAS token.
struct NativeAgentCenterTranslation: Equatable {
    /// The booths the engine runs; empty when translation is off.
    let booths: [VoiceTranslationBooth]
    /// `consecutive` | `simultaneous`; nil while off.
    let style: String?
    /// `override` | `room_tool` | `off` — where the running config
    /// comes from. The editor shows it so the owner knows whether an
    /// Apply overrides a session tweak or the room's standing rule.
    let source: String
    /// CAS revision of the override row; 0 when none exists yet.
    let revision: Int32

    var isOn: Bool {
        !booths.isEmpty
    }

    /// Flat union for the status line only — NEVER written back.
    var languages: [String] {
        Array(Set(booths.flatMap(\.targetLanguages))).sorted()
    }

    static let unknown = NativeAgentCenterTranslation(booths: [], style: nil, source: "off", revision: 0)

    init(booths: [VoiceTranslationBooth], style: String?, source: String, revision: Int32) {
        self.booths = booths
        self.style = style
        self.source = source
        self.revision = revision
    }

    init(_ controls: VoiceControlsState) {
        booths = controls.effective.booths
        style = controls.effective.style
        source = controls.effective.source
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
    /// The server's word on keeping this call's translation as the room's
    /// rule; false until a controls read says otherwise.
    var canSaveAsRoomDefault = false
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
        /// Base-normalised codes (`LanguageTag.base`), the document's
        /// currency; empty = translation disabled.
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
    /// Whether the platform is reachable at all. Views hide the entry point
    /// rather than offering actions that can only fail.
    var isAvailable = false
    var isLoading = false
    var sessions: [NativeAgentCenterSession] = []
    var candidates: [NativeAgentCenterCandidate] = []
    /// The tenant's selectable translation languages, from the owner's
    /// agent's catalog — there before any session (decision 180).
    var availableLanguages: [VoiceControlsCatalogLanguage] = []
    /// Brief 0062 W5 (ADR-0075 D4): sessions whose translation coverage
    /// was NARROWED by the system (another participant brought their own
    /// agent for their own voice) rather than by this owner's edit. The
    /// editor shows the displaced notice for them.
    var displacedSessionIDs: Set<String> = []
    /// Sessions whose override the owner promoted to the room's standing
    /// rule during THIS call. Client-only and per-call: the backend has no
    /// "was promoted" flag, and the editor must not claim a promotion the
    /// write never made — the button used to latch on tap, so an action the
    /// view model dropped (one already in flight) or a refusal still read
    /// "Saved as the room standard" and disabled itself.
    var savedAsRoomDefaultSessionIDs: Set<String> = []
    /// Set when the last action failed; cleared by the next successful load.
    var lastError: NativeAgentCenterError?
    /// The owner's unsettled optimism, per agent MXID. Carried across
    /// reloads (a REST re-read neither extends nor shortens the window);
    /// settled by the document; swept by the clock once the write answered.
    var pendingOwnerWrites: [String: [NativeAgentCenterPendingWrite]] = [:]

    /// MXIDs with a live session — the call UI marks these tiles as attached
    /// agents rather than plain service members.
    var attachedAgentMxids: Set<String> {
        Set(sessions.map(\.agentMxid))
    }
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
    case invalidBooths
    /// 422 on turning the conversation ON — a failed Realtime spawn, a
    /// policy or budget refusal, the interpreter running. The owner must
    /// hear the outcome (the assistant stays silent), which the backend's
    /// detail does not say, AND the reason, which only the detail names.
    case conversationRefused(String)
    /// The owner paused the agent (decision 194): it joins no call.
    case agentPaused
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
        case .invalidBooths: UntranslatedL10n.screenNativeCallAgentCenterErrorInvalidBooths
        case .conversationRefused(let detail): Self.outcome(UntranslatedL10n.screenNativeCallAgentCenterErrorConversationRefused, reason: detail)
        case .agentPaused: UntranslatedL10n.screenNativeCallAgentCenterErrorAgentPaused
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
        // The arm form's words, so a refused room rule reads the same wherever it is set.
        case .toolRefused(let refusal): self = .rejected(refusal.message)
        case .agentPaused: self = .agentPaused
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

    private let snapshotSubject: CurrentValueSubject<NativeAgentCenterSnapshot, Never> = .init(.init())
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
         endingRecheckInterval: Duration = .seconds(1)) {
        self.agentPlatformService = agentPlatformService
        self.roomID = roomID
        self.roomMemberMxids = roomMemberMxids
        self.inviteAgent = inviteAgent
        self.endingRecheckInterval = endingRecheckInterval
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
        for context in contexts {
            switch await agentPlatformService.voiceSessionControls(sessionID: context.sessionID) {
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

        let candidates = await loadCandidates(agentPlatformService)
        let availableLanguages = await loadLanguages(agentPlatformService, sessions: sessions, candidates: candidates)
        finishLoad(sessions: sessions, candidates: candidates, availableLanguages: availableLanguages, isAvailable: true, error: nil)
        scheduleEndingRecheck(isAnySessionEnding: sessions.contains(where: \.isEnding))
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

    /// Adds an agent to this call. An invite-only room refuses the attach
    /// until the agent is a member, so that one rejection — and only that one
    /// — is retried after inviting.
    func attach(agentID: String, params: VoiceAttachParams) async -> Bool {
        guard let agentPlatformService else { return false }

        guard let candidate = snapshotSubject.value.candidates.first(where: { $0.id == agentID }) else {
            setError(.unavailable("agent not found"))
            return false
        }

        var result = await agentPlatformService.attachVoiceAgent(agentID: agentID, roomID: roomID, params: params)

        if !candidate.isRoomMember, case .failure(let error) = result, Self.isInviteRequired(error) {
            guard await inviteAgent(candidate.mxid) else {
                setError(.unavailable("could not invite the agent"))
                return false
            }
            result = await agentPlatformService.attachVoiceAgent(agentID: agentID, roomID: roomID, params: params)
        }

        switch result {
        case .success:
            await reload()
            return true
        case .failure(let error):
            await reloadReporting(.init(error))
            return false
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
            await reloadReporting(.init(error))
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
            setError(.unavailable("session not found"))
            return false
        }

        guard session.canControl else {
            setError(.notOwner)
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
        case .failure(let error):
            // An ON tap is rolled back before the re-read, which takes
            // several round trips (an OFF tap bridged nothing). Conflict and
            // gone both mean our view of the world is stale, so the only
            // honest next step is to re-read it.
            withdrawInFlight(fact, for: session.agentMxid, restoring: superseded)
            await reloadReporting(Self.switchError(error, control: control, enabled: enabled))
            return false
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

    /// Owner-authorized translation write. Takes the FULL booth list +
    /// style — the editor edits what the engine runs, never a flat
    /// projection that would erase per-speaker configuration on Apply
    /// (the exact defect Brief 0062 removed from the web widget and the
    /// first native editor reintroduced). CAS revision comes from the
    /// snapshot so a stale view conflicts instead of clobbering.
    func setTranslation(sessionID: String, params: VoiceTranslationParams) async -> Bool {
        guard let agentPlatformService,
              let session = snapshotSubject.value.sessions.first(where: { $0.sessionID == sessionID }) else {
            setError(.unavailable("session not found"))
            return false
        }
        guard session.canControl else {
            setError(.notOwner)
            return false
        }
        guard VoiceTranslationBooths.isValid(params.booths) else {
            setError(.invalidBooths)
            return false
        }

        markOwnerWrite(sessionID: sessionID)
        switch await agentPlatformService.setVoiceTranslation(sessionID: sessionID,
                                                              params: params,
                                                              revision: session.translation.revision) {
        case .success(let controls):
            apply(controls: controls,
                  sessionID: sessionID,
                  written: .translation(languages: Self.documentLanguages(params.booths)))
            return true
        case .failure(let error):
            await reloadReporting(.init(error))
            return false
        }
    }

    /// Drop the session override and fall back to the room's standing
    /// rule (`room_tool`) or off. The owner's mental model is "tools
    /// live in the room" — this is the way back to that rule.
    func clearTranslationOverride(sessionID: String) async -> Bool {
        guard let agentPlatformService else { return false }
        markOwnerWrite(sessionID: sessionID)
        switch await agentPlatformService.clearVoiceTranslationOverride(sessionID: sessionID) {
        case .success(let controls):
            // Back to the room's rule: what the engine now runs is the
            // effective booth list the server returned.
            apply(controls: controls,
                  sessionID: sessionID,
                  written: .translation(languages: Self.documentLanguages(controls.effective.booths)))
            return true
        case .failure(let error):
            await reloadReporting(.init(error))
            return false
        }
    }

    /// Promote the CURRENT override to the room's standing rule so the
    /// next call starts with it without reconfiguring.
    func saveTranslationAsRoomDefault(sessionID: String) async -> Bool {
        guard let agentPlatformService else { return false }
        switch await agentPlatformService.saveVoiceTranslationAsRoomDefault(sessionID: sessionID) {
        case .success:
            var pending = snapshotSubject.value
            pending.savedAsRoomDefaultSessionIDs.insert(sessionID)
            snapshotSubject.value = pending
            // The promotion changes the effective source (override →
            // room_tool); re-read so the editor stops offering to clear an
            // override that is now the room's rule.
            await reload()
            return true
        case .failure(let error):
            await reloadReporting(.init(error))
            return false
        }
    }

    func disableTranslation(sessionID: String) async -> Bool {
        guard let agentPlatformService,
              let session = snapshotSubject.value.sessions.first(where: { $0.sessionID == sessionID }) else {
            setError(.unavailable("session not found"))
            return false
        }
        guard session.canControl else {
            setError(.notOwner)
            return false
        }
        markOwnerWrite(sessionID: sessionID)
        switch await agentPlatformService.disableVoiceTranslation(sessionID: sessionID,
                                                                  revision: session.translation.revision) {
        case .success(let controls):
            apply(controls: controls, sessionID: sessionID, written: .translation(languages: []))
            return true
        case .failure(let error):
            await reloadReporting(.init(error))
            return false
        }
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
    private func reloadReporting(_ error: NativeAgentCenterError) async {
        await reload()
        setError(error)
    }

    /// The owner's agent's catalog — read without a session, so the Add
    /// sheet can pick a language before the FIRST attach (decision 180). The
    /// agent in the call when there is one, else the first one offered. A
    /// failed read keeps the languages already known: it is not "none".
    private func loadLanguages(_ service: AgentPlatformServiceProtocol,
                               sessions: [NativeAgentCenterSession],
                               candidates: [NativeAgentCenterCandidate]) async -> [VoiceControlsCatalogLanguage] {
        let inCall = sessions.first(where: \.canControl).flatMap { session in
            candidates.first { $0.mxid == session.agentMxid }
        }
        // No agent to read for (or its list failed): nothing new is known.
        guard let agent = inCall ?? candidates.first else { return snapshotSubject.value.availableLanguages }
        switch await service.voiceControlsCatalog(agentID: agent.id) {
        case .success(let catalog):
            return catalog.voiceTranslationLanguages
        case .failure(let error):
            MXLog.warning("Agent center: catalog read failed for \(agent.id): \(error)")
            return snapshotSubject.value.availableLanguages
        }
    }

    private func loadCandidates(_ service: AgentPlatformServiceProtocol) async -> [NativeAgentCenterCandidate] {
        switch await service.listMyPersonalAgents() {
        case .failure(let error):
            MXLog.warning("Agent center: listMyPersonalAgents failed: \(error)")
            return []
        case .success(let view):
            let members = await roomMemberMxids()
            return view.agents
                .filter { $0.lifecycleState == "active" }
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
                                                      isRoomMember: members.contains(agent.matrixUserID))
                }
        }
    }

    private func finishLoad(sessions: [NativeAgentCenterSession],
                            candidates: [NativeAgentCenterCandidate],
                            availableLanguages: [VoiceControlsCatalogLanguage] = [],
                            isAvailable: Bool,
                            error: NativeAgentCenterError?) {
        var pending = NativeAgentCenterSnapshot(isAvailable: isAvailable,
                                                isLoading: false,
                                                sessions: sessions,
                                                candidates: candidates,
                                                availableLanguages: availableLanguages,
                                                lastError: error)
        // Doorbell reloads are how ANOTHER participant's displacement
        // reaches us — diff every surviving session's coverage.
        pending.displacedSessionIDs = snapshotSubject.value.displacedSessionIDs
        pending.savedAsRoomDefaultSessionIDs = snapshotSubject.value.savedAsRoomDefaultSessionIDs
            .intersection(sessions.map(\.sessionID))
        pending.pendingOwnerWrites = snapshotSubject.value.pendingOwnerWrites
        for session in sessions {
            guard let previous = snapshotSubject.value.sessions
                .first(where: { $0.sessionID == session.sessionID }) else { continue }
            updateDisplacement(sessionID: session.sessionID,
                               previous: previous.translation.booths,
                               next: session.translation.booths,
                               pending: &pending)
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
        updateDisplacement(sessionID: sessionID,
                           previous: existing.translation.booths,
                           next: controls.effective.booths,
                           pending: &pending)
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
                                                           conversation: .init(controls.conversation),
                                                           canSaveAsRoomDefault: controls.canSaveAsRoomDefault)
        pending.lastError = nil
        // The owner's optimism, time-bounded: what the server just accepted
        // shows at once (an ON tap already did), and expires unless the
        // agent's document agrees.
        Self.record(written, for: pending.sessions[index].agentMxid, in: &pending, expiresAt: Self.ownerWriteExpiry(from: Date()))
        snapshotSubject.value = pending
        rescheduleSweep()
    }

    /// The document's currency for a booth list: base-normalised codes,
    /// unique, sorted — what `SpiralAgentStateReader` reads back, so a
    /// write can settle against it.
    static func documentLanguages(_ booths: [VoiceTranslationBooth]) -> [String] {
        Array(Set(booths.flatMap(\.targetLanguages).map(LanguageTag.base(of:)))).sorted()
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
                case .translation(let languages): Set(document.translation.configuredLanguages) != Set(languages)
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

    /// Timestamps of the last translation write THIS controller issued,
    /// per session. A coverage shrink that lands shortly after our own
    /// write is the write echoing back, not displacement.
    private var lastOwnerWriteAt: [String: Date] = [:]
    private static let ownerWriteEchoWindow: TimeInterval = 10

    private func markOwnerWrite(sessionID: String) {
        lastOwnerWriteAt[sessionID] = Date()
    }

    /// Compare the incoming translation state against what we last
    /// showed; flag the session as displaced when coverage strictly
    /// shrank and the owner did not just write themself.
    private func updateDisplacement(sessionID: String,
                                    previous: [VoiceTranslationBooth],
                                    next: [VoiceTranslationBooth],
                                    pending: inout NativeAgentCenterSnapshot) {
        let recentOwnerWrite = lastOwnerWriteAt[sessionID]
            .map { Date().timeIntervalSince($0) < Self.ownerWriteEchoWindow } ?? false
        if recentOwnerWrite {
            pending.displacedSessionIDs.remove(sessionID)
            return
        }
        if VoiceTranslationBooths.coverageShrank(previous: previous, next: next) {
            pending.displacedSessionIDs.insert(sessionID)
        }
    }

    private func setError(_ error: NativeAgentCenterError) {
        var pending = snapshotSubject.value
        pending.lastError = error
        snapshotSubject.value = pending
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
                                 conversation: controls.map { .init($0.conversation) } ?? .unknown,
                                 canSaveAsRoomDefault: controls?.canSaveAsRoomDefault ?? false)
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
