//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0085, question 403): what an own assistant does in a call, as the Assistants sheet's four
// round buttons — Translation · Notes · Recording · Talk, the call dock's own circles (L5). Translation produces into
// "my language"; talking and translating exclude each other (ADR-0071 G1); nothing on is listening. In the private call
// one tap moves from one to the other (L11).

import Foundation

enum NativeCallAssistantJob: CaseIterable, Hashable {
    case translation
    case summary
    case recording
    case conversation

    /// The control a running write of this job belongs to: only it turns.
    var row: NativeAgentCenterErrorScope.Row {
        switch self {
        case .translation: .translation
        case .summary: .summary
        case .recording: .recording
        case .conversation: .mainJob
        }
    }

    /// The attach that brings an assistant for this job alone (scenario 2.1).
    func attachParams(translation: VoiceTranslationParams?) -> VoiceAttachParams {
        VoiceAttachParams(translation: self == .translation ? translation : nil,
                          recording: self == .recording,
                          summary: self == .summary,
                          conversation: self == .conversation)
    }
}

/// The four buttons, for your own assistant (live, joining or not yet called) or someone else's read-only page.
struct NativeCallAssistantDockState: Equatable {
    struct Button: Equatable, Identifiable {
        var id: NativeCallAssistantJob {
            job
        }

        let job: NativeCallAssistantJob
        let isOn: Bool
        let isEnabled: Bool
        let isBusy: Bool
        /// A refusal or a block met this job: red, with its reason under the buttons.
        let isRefused: Bool
        /// Asked for and not on yet — the assistant comes for it, or the sheet asks first: ringed in blue.
        let isPending: Bool
        /// Question 404, recording only: someone else's assistant records the call — dimmed «Записує», a tap says
        /// who — or did, and stopped: «Продовжити».
        var cover: NativeCallRecordingCover.Phase?

        /// Dimmed, yet a tap explains why (question 404).
        var isCovered: Bool {
            cover == .recording
        }
    }

    struct Facts: Equatable {
        var isTranslating = false
        var isTakingNotes = false
        var isRecording = false
        var isTalking = false
        /// Stopped in this call: what was captured is on its way, and a new recording can't start (EC `RecordingTab`).
        var isRecordingStopped = false
        var busy: Set<NativeCallAssistantJob> = []
        var refused: NativeCallAssistantJob?
        /// The job asked for and not on yet (L5 1.2, 1.5, 2.1, 3.4).
        var pending: NativeCallAssistantJob?
        /// Why translation can't start; talking is not a block here, it greys the button.
        var block: NativeCallTranslationBlock?
        /// The runtime hasn't taken the newest translation mode yet (ADR-0094 A.3 `syncing`): ringed like a job asked for.
        var isTranslationSyncing = false
        /// The platform says talking can't start: a translation intent is on, standing by or stopped but not turned off
        /// (ADR-0094 D11).
        var isTalkUnavailable = false
        /// Someone else's assistant: everything shows, nothing is tappable.
        var isReadOnly = false
        /// L11, the private call: a tap on «Перевод» while talking, or on «Разговор» while translating, switches from
        /// one to the other, so neither is ever greyed by the other.
        var switchesTalkAndTranslation = false
        /// Question 404: one recording per call, someone else's assistant has it or had it.
        var recordingCover: NativeCallRecordingCover.Phase?
    }

    let buttons: [Button]

    init(_ facts: Facts) {
        buttons = NativeCallAssistantJob.allCases.map { job in
            // Row 11: a translation the runtime hasn't taken yet shows as asked for — ringed, not filled.
            let isOn = switch job {
            case .translation: facts.isTranslating && !facts.isTranslationSyncing
            case .summary: facts.isTakingNotes
            case .recording: facts.isRecording
            case .conversation: facts.isTalking
            }
            let isEnabled: Bool = switch job {
            case _ where facts.isReadOnly: false
            case .translation: !facts.isTalking || facts.switchesTalkAndTranslation
            case .conversation: facts.switchesTalkAndTranslation || !facts.isTranslating && !facts.isTalkUnavailable
            case .recording: !facts.isRecordingStopped
            case .summary: true
            }
            let isBlocked = job == .translation && !isOn && facts.block.map { $0 != .talking } == true
            // Your own recording never shows as covered: there is one per call, and it is yours.
            // «Продовжити» only when yours can start: not after your own recording stopped in this call.
            let cover = job == .recording && !isOn && (facts.recordingCover == .recording || isEnabled) ? facts.recordingCover : nil
            let isCovered = cover == .recording
            return Button(job: job,
                          isOn: isOn,
                          isEnabled: isEnabled && !isCovered,
                          isBusy: facts.busy.contains(job),
                          isRefused: (facts.refused == job || isBlocked) && !isCovered,
                          isPending: (facts.pending == job && !isOn || job == .translation && facts.isTranslationSyncing)
                              && facts.refused != job && !isBlocked && !isCovered,
                          cover: cover)
        }
    }
}

extension NativeCallTranslationBlock {
    /// Why your own assistant can't produce a translation right now (scenario 9), from what the sheet knows: the one in
    /// the call, else the one that would come (`pickedAssistantID`, else the first).
    static func current(_ agents: NativeCallAgentPresentation, pickedAssistantID: String?) -> NativeCallTranslationBlock? {
        if let own = agents.ownAgents.first {
            if own.shown.isConversationActive { return .talking }
            if own.control?.translation.pause != nil { return .translationPaused }
            return nil
        }
        let panel = agents.panel
        // On its way: the add already passed every check.
        if !agents.joining.filter(\.canControl).isEmpty { return nil }
        guard panel.isConfigured else { return .noAssistant }
        guard panel.isAvailable else { return nil }
        let candidate = panel.candidates.first { $0.id == pickedAssistantID } ?? panel.candidates.first
        guard let candidate else { return panel.ownAgentMxids.isEmpty ? .noAssistant : nil }
        return panel.startFailure(for: candidate).flatMap(NativeCallTranslationBlock.init)
    }
}

extension NativeCallAgentPresentation.Panel {
    /// Why an own assistant can't come: the latest failed add first, then the pause the device knows, then the
    /// backend's join check (N4).
    func startFailure(for candidate: NativeAgentCenterCandidate) -> NativeAgentCenterJoinFailure? {
        if let failure = joinFailures[candidate.id] { return failure }
        if candidate.isPaused { return .paused }
        return joinChecks[candidate.id].flatMap(NativeAgentCenterJoinFailure.init)
    }
}

/// Critique item 5 — how someone else's assistant is named, in the viewer's language.
enum NativeCallForeignAssistantName: Equatable {
    /// A personal assistant under the platform's default name: "{owner} · assistant", built on the device.
    case personal(owner: String)
    /// A name of its own, with its owner when known.
    case custom(name: String, owner: String?)

    /// The owner is the room member whose localpart the assistant's carries (`@assistant-<owner>[-n]`); the platform
    /// names a personal assistant "{owner} · {role}", which `NativeCallAssistantTitle` splits.
    init(agentMxid: String, displayName: String, people: [String: String]) {
        let owner = Self.owner(of: agentMxid, among: Array(people.keys)).flatMap { people[$0] }
        if let owner, NativeCallAssistantTitle(displayName: displayName).role != nil {
            self = .personal(owner: owner)
        } else {
            self = .custom(name: displayName, owner: owner)
        }
    }

    static func owner(of agentMxid: String, among people: [String]) -> String? {
        let prefix = "@assistant-"
        guard agentMxid.hasPrefix(prefix), let colon = agentMxid.firstIndex(of: ":") else { return nil }
        let localpart = String(agentMxid[agentMxid.index(agentMxid.startIndex, offsetBy: prefix.count)..<colon])
        let server = agentMxid[colon...]
        return people
            .filter { $0.hasSuffix(server) }
            .first { person in
                let personLocalpart = person.dropFirst().prefix { $0 != ":" }
                return localpart == personLocalpart || localpart.hasPrefix("\(personLocalpart)-")
            }
    }
}

/// Question 404, one recording per call: someone else's assistant records it, so yours can't; once theirs stops, yours
/// may continue with a new recording (a new file).
struct NativeCallRecordingCover: Equatable {
    enum Phase: Equatable {
        /// Theirs records: «Запис» is dimmed «Записує», with their avatar.
        case recording
        /// Theirs stopped (its owner left, a limit, turned off): «Продовжити», until yours starts or the call ends.
        case stopped
    }

    /// The assistant that records, or recorded; nil when only the backend's refusal said so, naming no one.
    let agentMxid: String?
    /// Its owner, whom the line names; nil when unknown, and the line says "another assistant".
    let ownerMxid: String?
    let phase: Phase
}

/// Keeps what the call's documents can't say by themselves: whose recording stopped. A refused start (`409
/// /errors/recording-covered`) is the authority while the documents lag: covered at once, until they say who records.
struct NativeCallRecordingCoverTracker: Equatable {
    /// An assistant holding the call's recording (recording or armed), from its document.
    struct Recorder: Equatable {
        let agentMxid: String
        let ownerMxid: String?
    }

    /// How long a refused start alone keeps the button covered; the recording assistant's document normally takes
    /// over within a second.
    static let refusalWindow: TimeInterval = 20

    private(set) var cover: NativeCallRecordingCover?
    /// A document has shown the cover's assistant recording: only such a cover can stop. One the refusal alone made
    /// lapses to nothing.
    private var isCoverConfirmed = false
    /// The refusal already handed over to the documents, or outlived: it covers nothing any more.
    private var settledRefusalAt: Date?

    /// `recorders` are the other people's assistants whose documents hold the recording, in roster order;
    /// `undetermined` the other people's assistants in the call whose document isn't known.
    mutating func update(recorders: [Recorder],
                         undetermined: Set<String>,
                         isOwnRecording: Bool,
                         refusal: NativeAgentCenterRecordingRefusal?,
                         now: Date) {
        let freshRefusal = refusal.flatMap { $0.at == settledRefusalAt ? nil : $0 }
        if isOwnRecording {
            settle(nil, confirmed: false, refusal: refusal)
            return
        }
        // The one already shown stays named while it records, so a second recorder (a race lost elsewhere) never swaps it.
        if let recorder = recorders.first(where: { $0.agentMxid == cover?.agentMxid }) ?? recorders.first {
            let knownOwner = cover?.agentMxid == recorder.agentMxid ? cover?.ownerMxid : nil
            let refusedOwner = refusal?.cover.agentMxid == recorder.agentMxid ? refusal?.cover.ownerMxid : nil
            settle(NativeCallRecordingCover(agentMxid: recorder.agentMxid, ownerMxid: recorder.ownerMxid ?? knownOwner ?? refusedOwner, phase: .recording),
                   confirmed: true, refusal: refusal)
            return
        }
        // A document that isn't there says nothing: the recording isn't known to have stopped.
        if let current = cover, current.phase == .recording, isCoverConfirmed, let agent = current.agentMxid, undetermined.contains(agent) {
            return
        }
        if let freshRefusal {
            if now.timeIntervalSince(freshRefusal.at) < Self.refusalWindow {
                cover = NativeCallRecordingCover(agentMxid: freshRefusal.cover.agentMxid, ownerMxid: freshRefusal.cover.ownerMxid, phase: .recording)
                isCoverConfirmed = false
                return
            }
            settledRefusalAt = freshRefusal.at
        }
        guard let current = cover, current.phase == .recording else { return }
        cover = isCoverConfirmed ? NativeCallRecordingCover(agentMxid: current.agentMxid, ownerMxid: current.ownerMxid, phase: .stopped) : nil
    }

    private mutating func settle(_ cover: NativeCallRecordingCover?, confirmed: Bool, refusal: NativeAgentCenterRecordingRefusal?) {
        self.cover = cover
        isCoverConfirmed = confirmed
        settledRefusalAt = refusal?.at ?? settledRefusalAt
    }

    /// The other people's assistants holding the call's recording — live, with a recording function, active or armed —
    /// each with its owner: the document's, else the room member the assistant's localpart names (`@assistant-<owner>`).
    static func recorders(_ agents: NativeCallAgentPresentation, people: [String]) -> [Recorder] {
        agents.foreignAgents
            .filter { agents.documents[$0.mxid].map { $0.holdsRecording && $0.lifecycle == .live } == true }
            .map { Recorder(agentMxid: $0.mxid, ownerMxid: $0.live.owner ?? NativeCallForeignAssistantName.owner(of: $0.mxid, among: people)) }
    }

    /// The other people's assistants in the call whose document isn't known: whether they record isn't either.
    static func undetermined(_ agents: NativeCallAgentPresentation) -> Set<String> {
        Set(agents.foreignAgents.filter { agents.documents[$0.mxid] == nil }.map(\.mxid))
    }
}
