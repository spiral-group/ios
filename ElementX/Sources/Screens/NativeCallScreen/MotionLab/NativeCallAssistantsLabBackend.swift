//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 401; Brief 0085, question 403): an in-memory platform behind the call's real
// Assistants sheet and its translation, for the call motion lab's `AssistantsLive` stage. It answers the Agent Center
// controller's ports (`AgentPlatformServiceProtocol`'s session-control, join-check, usage, agent and consent calls, the
// room's kick, and the translation port) in backend ADR-0094's shapes, with the real response and error types, and
// plays the other side of the call: people who publish their languages on their memberships, assistants that join and
// publish their state document v6 (as JSON, read by the app's own parser), claim lanes (speaker × input × language, one
// producer each), stand by, sync and stop. Every call waits the scenario's latency; an armed failure answers the next
// action. Fictional names only.
//
// Staging and Debug builds only.

#if DEBUG || SPIRAL_STAGING

import Foundation
import Observation

@Observable
final class NativeCallAssistantsLabBackend {
    // MARK: Scenario

    enum Cast: String, CaseIterable, Identifiable {
        case privateCall = "private"
        case onePerson = "person"
        case personWithAssistant = "personAssistant"
        case group

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .privateCall: "Private"
            case .onePerson: "1:1"
            case .personWithAssistant: "1:1 + asst"
            case .group: "Group 4"
            }
        }

        /// For the pill over the clock, which has room for little.
        var shortTitle: String {
            switch self {
            case .privateCall: "Priv"
            case .onePerson: "1:1"
            case .personWithAssistant: "1:1+A"
            case .group: "G4"
            }
        }
    }

    enum Role: String, CaseIterable, Identifiable {
        case moderator
        case member

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .moderator: "Owner / moderator"
            case .member: "Member"
            }
        }
    }

    enum Latency: String, CaseIterable, Identifiable {
        case none = "0"
        case short = "300ms"
        case long = "1.5s"
        case veryLong = "4s"

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .none: "0"
            case .short: "300 ms"
            case .long: "1.5 s"
            case .veryLong: "4 s"
            }
        }

        var shortTitle: String {
            switch self {
            case .none: "0 s"
            case .short: ".3 s"
            case .long: "1.5 s"
            case .veryLong: "4 s"
            }
        }

        var duration: Duration {
            switch self {
            case .none: .zero
            case .short: .milliseconds(300)
            case .long: .milliseconds(1500)
            case .veryLong: .seconds(4)
            }
        }
    }

    /// What the next action meets. Each case answers only the actions it can happen to, and stays armed until one comes.
    enum Failure: String, CaseIterable, Identifiable {
        case none
        case weeklyLimit
        case translationPaused
        case callsPaused
        /// 503 on the next enabling write: the app retries once, after `Retry-After`.
        case serviceUnavailable
        case consentOwner
        case consentRoom
        case network

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .none: "None"
            case .weeklyLimit: "Weekly limit"
            case .translationPaused: "call_translation paused"
            case .callsPaused: "calls paused"
            case .serviceUnavailable: "503, retried once"
            case .consentOwner: "No AI consent (you)"
            case .consentRoom: "No AI consent (room)"
            case .network: "Network error"
            }
        }
    }

    /// Why own assistants can't be in this call until the scenario is reset: what a limit or a consent answer leaves.
    enum Block: String, CaseIterable, Identifiable {
        case weeklyLimit
        case callsPaused
        case consentOwner
        case consentRoom

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .weeklyLimit: "Weekly limit"
            case .callsPaused: "Calls paused"
            case .consentOwner: "AI not allowed (you)"
            case .consentRoom: "AI not allowed (room)"
            }
        }
    }

    // MARK: The call

    static let me = "@sam:example.org"
    static let myAgent = "@assistant-sam:example.org"
    static let agentID = "lab-own-agent"
    static let john = "@john:example.org"
    static let johnAgent = "@assistant-john:example.org"
    static let mira = "@mira:example.org"
    static let miraAgent = "@assistant-mira:example.org"
    static let alex = "@alex:example.org"
    static let bohdan = "@bohdan:example.org"
    static let bohdanAgent = "@assistant-bohdan:example.org"
    static let roomID = "!lab-live:example.org"
    /// The language every other person publishes on their membership (ADR-0094 A.1), catalog codes.
    static let languages = [john: "en", mira: "en", alex: "de", bohdan: "uk"]
    /// The voice catalog (A.8).
    static let catalog: [VoiceControlsCatalogLanguage] = [.init(code: "en", label: "English"),
                                                          .init(code: "uk", label: "Ukrainian"),
                                                          .init(code: "ru", label: "Russian"),
                                                          .init(code: "de", label: "German"),
                                                          .init(code: "fr", label: "French"),
                                                          .init(code: "es", label: "Spanish"),
                                                          .init(code: "pt-BR", label: "Portuguese (Brazil)"),
                                                          .init(code: "zh-Hans", label: "Chinese (Simplified)")]

    /// Scenario 9.3: own assistants when there are several.
    private static let ownAgents = [OwnAgent(id: agentID, mxid: myAgent, name: "Sam Sample · assistant"),
                                    OwnAgent(id: "lab-work-agent", mxid: "@assistant-sam-2:example.org", name: "Work assistant"),
                                    OwnAgent(id: "lab-interpreter", mxid: "@assistant-sam-3:example.org", name: "Interpreter")]

    let cast: Cast
    let role: Role
    var latency: Latency
    /// Armed by the panel, cleared by the action it answers.
    var nextFailure: Failure = .none
    private(set) var isPaused: Bool
    var block: Block?
    /// The `call_translation` cap is reached: translation stops, and turning it on is refused (ADR-0094 A.2).
    private(set) var isTranslationCapped = false
    private(set) var sessions: [Session] = []
    private(set) var foreignAssistants: [ForeignAssistant]
    /// Scenario 9.3: the person has three own assistants.
    var hasSeveralAssistants = false
    /// The call still rings: an assistant called now comes when someone answers (scenario 9.4).
    private(set) var isRinging = false
    /// Any latency the launch asks for (`-SpiralCallMotionLabLiveLatency <seconds>`), over the panel's pick: the
    /// loading states stay up long enough to see and capture.
    var latencyOverride: Duration?
    /// How long the runtime takes to acknowledge a new mode (ADR-0094 A.3 `syncing`).
    var syncDuration: Duration = .milliseconds(1200)
    /// How long a standby takes to take over the lanes whose producer stopped (D10).
    var takeoverDuration: Duration = .milliseconds(1000)

    /// The session writes in the order they came, for the tests: «conversation off», «translation pocket uk fr»,
    /// «translation off», «conversation on».
    private(set) var writeLog: [String] = []

    /// The language this person published with their membership.
    private(set) var publishedLanguage: String?
    /// This chat's tool (scenario 5), kept by the stage across calls.
    var tool: NativeCallTranslationTool?

    /// The roster and the documents changed: what the media transport would deliver.
    @ObservationIgnored var onRosterChange: ((Roster) -> Void)?
    @ObservationIgnored private var endedReasons: [String: VoiceSessionEndReason] = [:]
    @ObservationIgnored private var sessionCounter = 0
    @ObservationIgnored private var overrideRevisionCounter: Int32 = 0
    @ObservationIgnored private var modeEpoch = 0
    @ObservationIgnored private var timers: [Task<Void, Never>] = []
    /// The lanes a stopped producer left, which your own standby takes over only after `takeoverDuration` (D10).
    @ObservationIgnored private var lanesAwaitingTakeover: Set<VoiceTranslationLane> = []
    /// How long an accepted assistant takes to reach the call, and to leave it; apart from the API's latency.
    @ObservationIgnored let joinDuration: Duration
    @ObservationIgnored let leaveDuration: Duration

    init(cast: Cast,
         role: Role,
         latency: Latency,
         isPaused: Bool = false,
         tool: NativeCallTranslationTool? = nil,
         joinDuration: Duration = .milliseconds(2500),
         leaveDuration: Duration = .milliseconds(1500)) {
        self.cast = cast
        self.role = role
        self.latency = latency
        self.isPaused = isPaused
        self.tool = tool
        self.joinDuration = joinDuration
        self.leaveDuration = leaveDuration
        switch cast {
        case .privateCall, .onePerson:
            foreignAssistants = []
        case .personWithAssistant:
            // John's assistant translates you into English for him, and records.
            foreignAssistants = [ForeignAssistant(mxid: Self.johnAgent, owner: Self.john,
                                                  lanes: [.init(speaker: Self.me, language: "en")], isRecording: true)]
        case .group:
            // Mira's assistant translates Alex and Bohdan into English for her, and records (scenario 7.1); you too once
            // `startTranslatingYou` (question 409).
            foreignAssistants = [ForeignAssistant(mxid: Self.miraAgent, owner: Self.mira,
                                                  lanes: [Self.alex, Self.bohdan].map { .init(speaker: $0, language: "en") },
                                                  isRecording: true)]
        }
        if cast == .privateCall {
            // The private call is with one's assistant: it is in from the start, talking with you and taking notes.
            sessions = [makeSession(agent: Self.myAgent, params: VoiceAttachParams(translation: nil, recording: false, summary: true, conversation: true), phase: .active)]
        } else if let tool, tool.isEnabled, tool.translatesIfNobodyDoes, !wantedLanes(for: tool.language).isEmpty {
            // ADR-0094 D9: the personal Tool starts your assistant when a lane into its language is wanted.
            var session = makeSession(agent: Self.myAgent, params: VoiceAttachParams(translation: .forLanguage(tool.language), recording: false, summary: false, conversation: false),
                                      phase: .active)
            session.source = "room_tool"
            sessions = [session]
        }
    }

    isolated deinit {
        timers.forEach { $0.cancel() }
    }

    // MARK: Who and what

    var scope: NativeCallScope {
        switch cast {
        case .privateCall: .assistant
        case .onePerson, .personWithAssistant: .direct
        case .group: .group
        }
    }

    var roomName: String {
        switch cast {
        case .privateCall: "Sam Sample · assistant"
        case .onePerson, .personWithAssistant: "John Smith"
        case .group: "Book club"
        }
    }

    /// Who is on the other side of a 1:1.
    var peer: String {
        scope == .assistant ? Self.myAgent : Self.john
    }

    var humans: [String] {
        switch cast {
        case .privateCall: [Self.me]
        case .onePerson, .personWithAssistant: [Self.me, Self.john]
        case .group: [Self.me, Self.mira, Self.alex, Self.bohdan]
        }
    }

    var profiles: [String: NativeCallMemberProfile] {
        var profiles: [String: NativeCallMemberProfile] = [Self.me: .init(displayName: "Sam Sample"),
                                                           Self.john: .init(displayName: "John Smith"),
                                                           Self.johnAgent: .init(displayName: "John Smith · assistant"),
                                                           Self.mira: .init(displayName: "Mira Testova"),
                                                           Self.miraAgent: .init(displayName: "Mira Testova · assistant"),
                                                           Self.alex: .init(displayName: "Alex Primer"),
                                                           Self.bohdan: .init(displayName: "Bohdan Zrazok"),
                                                           Self.bohdanAgent: .init(displayName: "Bohdan Zrazok · assistant")]
        for agent in Self.ownAgents {
            profiles[agent.mxid] = .init(displayName: agent.name)
        }
        return profiles
    }

    var roomMembers: Set<String> {
        Set(humans + ownAgentList.map(\.mxid) + foreignAssistants.map(\.mxid))
    }

    var canKick: Bool {
        role == .moderator
    }

    /// The own session in the call or on its way, if any.
    var ownSession: Session? {
        sessions.first
    }

    /// Everyone else's assistants in the call, in roster order.
    var foreignAgentMxids: [String] {
        foreignAssistants.map(\.mxid)
    }

    /// The other side produces your language (scenarios 3.1, 4.1).
    var isSomeoneTranslatingForYou: Bool {
        foreignAssistants.contains { $0.producesForYou && $0.stopped == nil }
    }

    private var ownAgentList: [OwnAgent] {
        hasSeveralAssistants ? Self.ownAgents : [Self.ownAgents[0]]
    }

    /// The published languages of the people in the call, yours included once published (A.1).
    var membershipLanguages: [String: String] {
        var languages = Self.languages.filter { humans.contains($0.key) }
        if let publishedLanguage {
            languages[Self.me] = publishedLanguage
        }
        return languages
    }

    var roster: Roster {
        var participants = humans.map { NativeCallScreen_Previews.participant($0, isLocal: $0 == Self.me) }
        var documents: [String: SpiralAgentStateReader.AgentClaim] = [:]
        for session in sessions where session.phase != .joining {
            participants.append(NativeCallScreen_Previews.participant(session.agent, role: .agent))
            documents[session.agent] = Self.claim(document(of: session))
        }
        for assistant in foreignAssistants {
            participants.append(NativeCallScreen_Previews.participant(assistant.mxid, role: .agent))
            documents[assistant.mxid] = Self.claim(document(of: assistant))
        }
        var claims = NativeCallAgentClaims()
        claims.documents = documents
        return Roster(participants: participants, claims: claims, languages: membershipLanguages)
    }

    // MARK: - Scenario actions

    /// Someone else's assistant starts producing your language: John's in a 1:1 (scenario 1, from his side), Bohdan's in
    /// the group, for Mira only (scenario 3: "1 of 2", "Translate the others").
    func startForeignTranslation() {
        foreignAssistants.removeAll { $0.producesForYou && $0.mxid != Self.johnAgent }
        let language = publishedLanguage ?? "uk"
        switch cast {
        case .privateCall:
            return
        case .onePerson, .personWithAssistant:
            if let index = foreignAssistants.firstIndex(where: { $0.mxid == Self.johnAgent }) {
                foreignAssistants[index].lanes.append(.init(speaker: Self.john, language: language))
                foreignAssistants[index].producesForYou = true
                foreignAssistants[index].stopped = nil
            } else {
                foreignAssistants.append(ForeignAssistant(mxid: Self.johnAgent, owner: Self.john,
                                                          lanes: [.init(speaker: Self.john, language: language)],
                                                          isRecording: false, producesForYou: true))
            }
        case .group:
            foreignAssistants.append(ForeignAssistant(mxid: Self.bohdanAgent, owner: Self.bohdan,
                                                      lanes: [.init(speaker: Self.mira, language: language)],
                                                      isRecording: false, producesForYou: true))
        }
        republishOwnLanes()
    }

    // MARK: Static ducking's release (2026-11-12)

    /// The covered person's original voice as this device hears it while you listen in your language: Mira's in the
    /// group, John's in a 1:1.
    enum OriginalVoice: Equatable {
        /// Nobody translates her into your language.
        case notCovered
        case ducked
        /// None of her lanes aired after 4 s of her speech: heard in full, and nothing on screen says so.
        case heardInFull
    }

    /// Whose lane for you the panel plays: Mira's in the group (Bohdan's assistant), John's in a 1:1 (his own).
    var coveredSpeakerName: String {
        cast == .group ? "Mira" : "John"
    }

    /// They declared English but speak something else: the lane for them into your language exists and never airs.
    var isCoveredLaneSilent = false
    private(set) var coveredOriginal = OriginalVoice.notCovered
    private(set) var isCoveredSpeaking = false
    @ObservationIgnored private var coveredVoice = CallMotionLabSpeaker(seed: 0x4D49_5241)
    @ObservationIgnored private var coveredReports = CallMotionLabSFU()
    @ObservationIgnored private var coveredCoverage: NativeCallUnairedCoverage?

    /// They talk on, and their original follows the call's rule (`NativeCallUnairedCoverage`): their speaking signal as
    /// the SFU reports it, their lane airing with their first word unless it is silent.
    func advanceCoveredVoice(by seconds: Double, now: Date) {
        let steps = Int((seconds / 0.01).rounded())
        for _ in 0..<steps {
            coveredReports.advance(by: 0.01, decibels: coveredVoice.advance(by: 0.01))
        }
        let isSpeaking = coveredReports.reported > 0
        if isCoveredSpeaking != isSpeaking { isCoveredSpeaking = isSpeaking }
        let speaker = cast == .group ? Self.mira : Self.john
        let language = publishedLanguage ?? "uk"
        let isCovered = cast != .privateCall
            && foreignAssistants.contains { $0.liveLanes.contains { $0.speaker == speaker && $0.language == language } }
        guard isCovered else {
            coveredCoverage = nil
            if coveredOriginal != .notCovered { coveredOriginal = .notCovered }
            return
        }
        var coverage = coveredCoverage ?? NativeCallUnairedCoverage()
        coverage.update(isSpeaking: isSpeaking, isAiring: isSpeaking && !isCoveredLaneSilent, now: now)
        coveredCoverage = coverage
        let original: OriginalVoice = coverage.isReleased ? .heardInFull : .ducked
        if coveredOriginal != original { coveredOriginal = original }
    }

    /// Question 409: someone's assistant translates you into English for its owner — Mira's in the group, John's in a 1:1
    /// (from the start with "1:1 + asst").
    var isTranslatingYou: Bool {
        foreignAssistants.contains { $0.liveLanes.contains { $0.speaker == Self.me } }
    }

    /// Question 409: Mira's assistant starts translating you in the group, John's in a 1:1; the capsule says from which
    /// language to a person who never picked theirs.
    func startTranslatingYou() {
        let (agent, owner) = cast == .group ? (Self.miraAgent, Self.mira) : (Self.johnAgent, Self.john)
        guard cast != .privateCall, !isTranslatingYou else { return }
        if let index = foreignAssistants.firstIndex(where: { $0.mxid == agent }) {
            foreignAssistants[index].lanes.append(.init(speaker: Self.me, language: "en"))
        } else {
            foreignAssistants.append(ForeignAssistant(mxid: agent, owner: owner, lanes: [.init(speaker: Self.me, language: "en")], isRecording: false))
        }
        publishRoster()
    }

    /// …and stops translating you; the capsule doesn't say it again in this call.
    func stopTranslatingYou() {
        for index in foreignAssistants.indices {
            foreignAssistants[index].lanes.removeAll { $0.speaker == Self.me }
        }
        publishRoster()
    }

    /// That producer stops (ADR-0094 D6): its owner turned it off, left the call, or its limit ran out (scenario 4.1).
    /// An assistant with nothing else to do leaves with the reason; one that records stays with its translation stopped.
    /// Its listeners fall back to the original and see why.
    func stopForeignTranslation(reason: VoiceTranslationStopReason) {
        guard let index = foreignAssistants.firstIndex(where: { $0.producesForYou && $0.stopped == nil }) else { return }
        if foreignAssistants[index].isRecording {
            foreignAssistants[index].stopped = reason
            foreignAssistants[index].producesForYou = false
            publishRoster()
            return
        }
        let mxid = foreignAssistants[index].mxid
        holdForOwnTakeover(foreignAssistants[index].liveLanes)
        foreignAssistants[index].leavingReason = reason
        publishRoster()
        schedule(after: leaveDuration) { backend in
            backend.foreignAssistants.removeAll { $0.mxid == mxid }
            backend.republishOwnLanes()
        }
    }

    /// Row 10: someone else's assistant covers everyone in your language, and yours — started by your Tool, as when it
    /// lost the race — stands by.
    func startOwnStandby() {
        startForeignTranslation()
        let language = publishedLanguage ?? "uk"
        if cast == .group {
            // Bohdan's covers Mira only here: let it cover Alex too, so nothing is left for yours.
            if let index = foreignAssistants.firstIndex(where: { $0.mxid == Self.bohdanAgent }) {
                foreignAssistants[index].lanes.append(.init(speaker: Self.alex, language: language))
            }
        }
        var session = makeSession(agent: Self.myAgent,
                                  params: VoiceAttachParams(translation: .forLanguage(language), recording: false, summary: false, conversation: false),
                                  phase: .active)
        session.source = "room_tool"
        sessions = [session]
        publishRoster()
    }

    /// D10: someone else's assistant stands by in your language (`active: false`, `lanes: []`, `for_language` set): Bohdan's
    /// in the group, John's in a 1:1. It takes over your lanes when you stop yours.
    func startForeignStandby() {
        let language = publishedLanguage ?? "uk"
        guard cast == .group || cast == .onePerson else { return }
        let mxid = cast == .group ? Self.bohdanAgent : Self.johnAgent
        let owner = cast == .group ? Self.bohdan : Self.john
        foreignAssistants.removeAll { $0.mxid == mxid }
        foreignAssistants.append(ForeignAssistant(mxid: mxid, owner: owner, lanes: [], isRecording: false, standbyLanguage: language))
        publishRoster()
    }

    /// Your own standby takes the stopped lanes over as the backend does, a moment later (D10).
    private func holdForOwnTakeover(_ lanes: [VoiceTranslationLane]) {
        lanesAwaitingTakeover.formUnion(lanes)
        schedule(after: takeoverDuration) { backend in
            backend.lanesAwaitingTakeover.subtract(lanes)
            backend.publishRoster()
        }
    }

    /// The standbys in `language` take the lanes nobody airs any more (D10).
    private func takeOver(_ language: String) {
        for index in foreignAssistants.indices where foreignAssistants[index].standbyLanguage == language && foreignAssistants[index].lanes.isEmpty {
            let claimed = Set(foreignAssistants.flatMap(\.liveLanes)).union(sessions.flatMap(lanes(of:)))
            foreignAssistants[index].lanes = wantedLanes(for: language).filter { !claimed.contains($0) }
            foreignAssistants[index].producesForYou = true
        }
        publishRoster()
    }

    /// Question 404, one recording per call: the backend refuses a second start while someone else's assistant records.
    private var recordingCover: VoiceRecordingCover? {
        foreignAssistants.first(where: \.isRecording).map { VoiceRecordingCover(agentMxid: $0.mxid, ownerMxid: $0.owner) }
    }

    /// Question 404: someone else's assistant stops recording (its owner turned it off, or left); it stays in the call.
    func stopForeignRecording() {
        guard let index = foreignAssistants.firstIndex(where: \.isRecording) else { return }
        foreignAssistants[index].isRecording = false
        publishRoster()
    }

    /// Your own Call translation cap pauses your translation mid-call (scenario 4.2): it stops for everyone who listened.
    func exhaustOwnLimit() {
        isTranslationCapped = true
        for index in sessions.indices where sessions[index].intent != nil {
            sessions[index].stopped = .translationPaused
            sessions[index].translationPause = .until(Self.limitResetsAt)
        }
        publishRoster()
    }

    /// The call rings, or someone answers: an assistant called while it rang joins now (scenario 9.4).
    func setRinging(_ isRinging: Bool) {
        self.isRinging = isRinging
        guard !isRinging else { return }
        for session in sessions where session.phase == .joining {
            let id = session.id
            let isSyncing = session.isSyncing
            schedule(after: joinDuration) { backend in
                backend.update(id) { $0.phase = .active }
                if isSyncing { backend.acknowledgeLater(id) }
            }
        }
    }

    // MARK: - The platform's answers

    func voiceSessionControlContexts(roomID: String) async -> Result<[VoiceSessionControlContext], VoiceControlsError> {
        await wait()
        return .success(sessions.map { session in
            VoiceSessionControlContext(sessionID: session.id, agentMxid: session.agent, canControl: true, state: session.phase.wire)
        })
    }

    func voiceSessionControls(sessionID: String) async -> Result<VoiceControlsState, VoiceControlsError> {
        await wait()
        guard let session = session(sessionID) else { return .failure(.gone) }
        return .success(controls(of: session))
    }

    func voiceLanguages() async -> Result<[VoiceControlsCatalogLanguage], VoiceControlsError> {
        await wait()
        return .success(Self.catalog)
    }

    func listMyPersonalAgents() async -> Result<MyPersonalAgentsView, AgentPlatformError> {
        await wait()
        let agents = ownAgentList.map { agent in
            PersonalAgentSummary(id: agent.id,
                                 matrixUserID: agent.mxid,
                                 displayName: agent.name,
                                 avatarMXC: nil,
                                 visibility: "private",
                                 lifecycleState: isPaused ? "suspended" : "active")
        }
        return .success(MyPersonalAgentsView(agents: agents, provisioningStatus: .ready))
    }

    func voiceJoinCheck(agentID: String, roomID: String) async -> Result<VoiceJoinCheckReason, VoiceControlsError> {
        await wait()
        if isPaused { return .success(.paused) }
        let reason: VoiceJoinCheckReason = switch block {
        case .weeklyLimit: .budgetReached
        case .callsPaused: .categoryPaused(nil)
        case .consentOwner: .aiConsentOwner
        case .consentRoom: .aiConsentRoom
        case nil: .ok
        }
        return .success(reason)
    }

    func voiceSessionProgress(sessionID: String) async -> Result<VoiceSessionProgress, VoiceControlsError> {
        await wait()
        if let session = session(sessionID) {
            let progress: VoiceSessionProgress = switch session.phase {
            case .joining: .joining
            case .active: .active
            case .ending: .ending
            }
            return .success(progress)
        }
        guard let reason = endedReasons[sessionID] else { return .failure(.gone) }
        return .success(.ended(reason))
    }

    func fetchAgentUsage(agentID: String) async -> Result<AgentUsage, AgentPlatformError> {
        await wait()
        return .success(usage)
    }

    func fetchAIConsent() async -> Result<AIConsent, AgentPlatformError> {
        await wait()
        return .success(consent)
    }

    func setAIConsent(granted: Bool) async -> Result<AIConsent, AgentPlatformError> {
        await wait()
        if let error = takeNetworkFailure() { return .failure(.transport(underlying: error)) }
        if granted, block == .consentOwner {
            block = nil
        }
        return .success(consent)
    }

    func attachVoiceAgent(agentID: String, roomID: String, params: VoiceAttachParams) async -> Result<String, VoiceControlsError> {
        await wait()
        if let error = takeNetworkFailure() { return .failure(.unavailable(error.localizedDescription)) }
        if isPaused { return .failure(.agentPaused) }
        if let translation = params.translation, let refusal = refuseEnabling(translation) { return .failure(refusal) }
        if params.recording, let cover = recordingCover { return .failure(.recordingCovered(cover)) }
        // A benign 409: the session already running in the room.
        if let existing = sessions.first(where: { $0.phase != .ending }) { return .success(existing.id) }
        guard let agent = ownAgentList.first(where: { $0.id == agentID }) else { return .failure(.gone) }

        let limit = takeLimit(for: .attach)
        var session = makeSession(agent: agent.mxid, params: params, phase: .joining)
        // The runtime takes the translation once it is in the call.
        session.isSyncing = params.translation != nil
        sessions.append(session)
        let id = session.id
        guard !isRinging else { return .success(id) }
        schedule(after: joinDuration) { backend in
            if let reason = limit ?? backend.block.map(\.endReason) {
                backend.end(id, reason: reason)
            } else {
                backend.update(id) { $0.phase = .active }
                if session.isSyncing { backend.acknowledgeLater(id) }
            }
        }
        return .success(id)
    }

    func endVoiceSession(sessionID: String) async -> Result<Void, VoiceControlsError> {
        await wait()
        if let error = takeNetworkFailure() { return .failure(.unavailable(error.localizedDescription)) }
        guard let session = session(sessionID) else { return .failure(.gone) }
        guard session.phase != .ending else { return .success(()) }
        update(sessionID) { $0.phase = .ending }
        schedule(after: leaveDuration) { backend in
            backend.end(sessionID, reason: .manual)
        }
        return .success(())
    }

    func setVoiceSwitch(sessionID: String, control: VoiceSessionSwitch, enabled: Bool, revision: Int32) async -> Result<VoiceControlsState, VoiceControlsError> {
        await wait()
        if let error = takeNetworkFailure() { return .failure(.unavailable(error.localizedDescription)) }
        guard let session = session(sessionID), session.phase != .ending else { return .failure(.gone) }
        guard session.revision(of: control) == revision else { return .failure(.conflict) }
        if control == .conversation, enabled, !session.isTalkAvailable {
            return .failure(.rejected("The assistant can't talk while it translates."))
        }
        if control == .recording, enabled, let cover = recordingCover { return .failure(.recordingCovered(cover)) }
        let limit = takeLimit(for: .sessionWrite)
        writeLog.append("\(control.rawValue) \(enabled ? "on" : "off")")
        update(sessionID) { $0.flip(control, to: enabled) }
        stopLater(sessionID, reason: limit)
        return controls(sessionID)
    }

    /// An enabling write (A.2): turning it on, a new language, «Продолжить». It clears a stop; a cap still on refuses it.
    func setVoiceTranslation(sessionID: String, params: VoiceTranslationParams, revision: Int32) async -> Result<VoiceControlsState, VoiceControlsError> {
        await wait()
        if let error = takeNetworkFailure() { return .failure(.unavailable(error.localizedDescription)) }
        guard let session = session(sessionID), session.phase != .ending else { return .failure(.gone) }
        guard session.overrideRevision == revision else { return .failure(.conflict) }
        if let refusal = refuseEnabling(params) { return .failure(refusal) }
        let limit = takeLimit(for: .sessionWrite)
        let revision = nextOverrideRevision()
        writeLog.append("translation \(params.labWire)")
        update(sessionID) { session in
            session.intent = params
            session.source = "override"
            session.stopped = nil
            session.isOverrideEnabled = true
            session.overrideRevision = revision
            session.conversation.isOn = false
            session.translationPause = nil
            session.isSyncing = true
        }
        acknowledgeLater(sessionID)
        stopLater(sessionID, reason: limit)
        return controls(sessionID)
    }

    /// Turning it off: the intent goes, the document says `owner_stopped`. Never a 503 (A.2).
    func disableVoiceTranslation(sessionID: String, revision: Int32) async -> Result<VoiceControlsState, VoiceControlsError> {
        await wait()
        if let error = takeNetworkFailure() { return .failure(.unavailable(error.localizedDescription)) }
        guard let session = session(sessionID), session.phase != .ending else { return .failure(.gone) }
        guard session.overrideRevision == revision else { return .failure(.conflict) }
        let limit = takeLimit(for: .sessionWrite)
        let revision = nextOverrideRevision()
        // D10: a standby in that language takes the lanes this one leaves, a moment later.
        if case .forLanguage(let language) = session.intent, !lanes(of: session).isEmpty {
            schedule(after: takeoverDuration) { backend in
                backend.takeOver(language)
            }
        }
        writeLog.append("translation off")
        // The runtime leaves the interpreter's mode only when it acknowledges: the talk waits for it (D11).
        if session.isModeTranslating {
            acknowledgeLater(sessionID)
        }
        update(sessionID) { session in
            session.intent = nil
            session.stopped = .ownerStopped
            session.isOverrideEnabled = false
            session.overrideRevision = revision
            session.translationPause = nil
            session.isSyncing = false
        }
        stopLater(sessionID, reason: limit)
        return controls(sessionID)
    }

    func editAgent(agentID: String, patch: AgentEditPatch) async -> Result<AgentReadModel, AgentPlatformError> {
        await wait()
        if let error = takeNetworkFailure() { return .failure(.transport(underlying: error)) }
        if let paused = patch.paused {
            isPaused = paused
        }
        return .success(AgentReadModel(agentID: agentID,
                                       matrixUserID: Self.myAgent,
                                       displayName: "Sam Sample · assistant",
                                       avatarMXC: nil,
                                       kind: "personal_assistant",
                                       visibility: "private",
                                       lifecycleState: isPaused ? "suspended" : "active",
                                       organizationID: "lab-org",
                                       roomCount: 3,
                                       activeToolCount: tool?.translatesIfNobodyDoes == true ? 1 : 0,
                                       configVersionNumber: 1,
                                       persona: nil,
                                       paused: isPaused))
    }

    /// A moderator removes someone else's assistant from the chat: a Matrix kick from this person's own client.
    func kick(_ agentMxid: String) async -> Bool {
        await wait()
        if takeNetworkFailure() != nil { return false }
        guard canKick, foreignAssistants.contains(where: { $0.mxid == agentMxid }) else { return false }
        foreignAssistants.removeAll { $0.mxid == agentMxid }
        republishOwnLanes()
        return true
    }

    /// Lifts what a limit or a consent answer left.
    func liftBlocks() {
        block = nil
        isTranslationCapped = false
        for index in sessions.indices {
            sessions[index].translationPause = nil
        }
        publishRoster()
    }

    func setPaused(_ isPaused: Bool) {
        self.isPaused = isPaused
    }

    /// Every port the controller reaches, on the generated mock: an unconfigured one traps, so a new port shows here.
    func makeService() -> AgentPlatformServiceMock {
        let service = AgentPlatformServiceMock()
        service.voiceSessionControlContextsRoomIDClosure = { [self] roomID in await voiceSessionControlContexts(roomID: roomID) }
        service.voiceSessionControlsSessionIDClosure = { [self] sessionID in await voiceSessionControls(sessionID: sessionID) }
        service.voiceLanguagesClosure = { [self] in await voiceLanguages() }
        service.listMyPersonalAgentsClosure = { [self] in await listMyPersonalAgents() }
        service.voiceJoinCheckAgentIDRoomIDClosure = { [self] agentID, roomID in await voiceJoinCheck(agentID: agentID, roomID: roomID) }
        service.voiceSessionProgressSessionIDClosure = { [self] sessionID in await voiceSessionProgress(sessionID: sessionID) }
        service.fetchAgentUsageAgentIDClosure = { [self] agentID in await fetchAgentUsage(agentID: agentID) }
        service.fetchAIConsentClosure = { [self] in await fetchAIConsent() }
        service.setAIConsentGrantedClosure = { [self] granted in await setAIConsent(granted: granted) }
        service.attachVoiceAgentAgentIDRoomIDParamsClosure = { [self] agentID, roomID, params in
            await attachVoiceAgent(agentID: agentID, roomID: roomID, params: params)
        }
        service.endVoiceSessionSessionIDClosure = { [self] sessionID in await endVoiceSession(sessionID: sessionID) }
        service.setVoiceSwitchSessionIDControlEnabledRevisionClosure = { [self] sessionID, control, enabled, revision in
            await setVoiceSwitch(sessionID: sessionID, control: control, enabled: enabled, revision: revision)
        }
        service.setVoiceTranslationSessionIDParamsRevisionClosure = { [self] sessionID, params, revision in
            await setVoiceTranslation(sessionID: sessionID, params: params, revision: revision)
        }
        service.disableVoiceTranslationSessionIDRevisionClosure = { [self] sessionID, revision in
            await disableVoiceTranslation(sessionID: sessionID, revision: revision)
        }
        service.editAgentAgentIDPatchClosure = { [self] agentID, patch in await editAgent(agentID: agentID, patch: patch) }
        return service
    }

    // MARK: - Private

    private enum Action {
        case attach, sessionWrite
    }

    private static var limitResetsAt: Date {
        let calendar = Calendar.current
        return calendar.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 0, weekday: 2), matchingPolicy: .nextTime) ?? .now.addingTimeInterval(3 * 86400)
    }

    private func wait() async {
        guard latency != .none else { return }
        try? await Task.sleep(for: latencyOverride ?? latency.duration)
    }

    /// A network error answers any action.
    private func takeNetworkFailure() -> URLError? {
        guard nextFailure == .network else { return nil }
        nextFailure = .none
        return URLError(.networkConnectionLost)
    }

    /// What refuses an enabling write before anything changes (A.2): a paused category (422), or one 503 the app
    /// retries; the pocket interpreter outside the owner's own chat and `for_language` inside it are refused quietly.
    private func refuseEnabling(_ params: VoiceTranslationParams) -> VoiceControlsError? {
        if nextFailure == .serviceUnavailable {
            nextFailure = .none
            return .serviceUnavailable(retryAfter: .seconds(1))
        }
        if isTranslationCapped {
            return .translationPaused(.init(reason: .translationPaused, pauseUntil: Self.limitResetsAt))
        }
        switch (params, cast) {
        case (.pocket, .privateCall), (.forLanguage, .onePerson), (.forLanguage, .personWithAssistant), (.forLanguage, .group):
            return nil
        case (.pocket, _):
            return .intentUnavailable(roomKind: "group")
        case (.forLanguage, .privateCall):
            return .intentUnavailable(roomKind: "owner_dm")
        }
    }

    /// A limit or a consent answer met by an add or a session write: the assistant stops on it (or never gets in), and
    /// its next add says why until the scenario is reset. The `call_translation` cap only stops translation.
    private func takeLimit(for action: Action) -> VoiceSessionEndReason? {
        let block: Block
        switch nextFailure {
        case .weeklyLimit: block = .weeklyLimit
        case .callsPaused: block = .callsPaused
        case .consentOwner: block = .consentOwner
        case .consentRoom: block = .consentRoom
        case .translationPaused:
            nextFailure = .none
            schedule(after: .milliseconds(600)) { $0.exhaustOwnLimit() }
            return nil
        case .none, .serviceUnavailable, .network:
            return nil
        }
        nextFailure = .none
        self.block = block
        return block.endReason
    }

    /// The write lands; the limit stops the assistant a moment later, as a cap reached mid-call does.
    private func stopLater(_ sessionID: String, reason: VoiceSessionEndReason?) {
        guard let reason else { return }
        schedule(after: .milliseconds(600)) { backend in
            backend.end(sessionID, reason: reason)
        }
    }

    /// The runtime applies the new mode and publishes it: `syncing` ends, the document names the lanes.
    private func acknowledgeLater(_ sessionID: String) {
        schedule(after: syncDuration) { backend in
            backend.modeEpoch += 1
            backend.update(sessionID) { session in
                session.isSyncing = false
                session.isModeTranslating = session.intent != nil && session.stopped == nil
            }
        }
    }

    private func schedule(after delay: Duration, _ work: @escaping (NativeCallAssistantsLabBackend) -> Void) {
        timers.append(Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            work(self)
        })
    }

    private func makeSession(agent: String, params: VoiceAttachParams, phase: Session.Phase) -> Session {
        sessionCounter += 1
        var session = Session(id: "lab-session-\(sessionCounter)", agent: agent, phase: phase)
        session.recording.isOn = params.recording
        session.summary.isOn = params.summary
        session.conversation.isOn = params.conversation
        if let translation = params.translation {
            session.intent = translation
            session.isOverrideEnabled = true
            session.overrideRevision = nextOverrideRevision()
        }
        return session
    }

    private func nextOverrideRevision() -> Int32 {
        overrideRevisionCounter += 1
        return overrideRevisionCounter
    }

    private func session(_ id: String) -> Session? {
        sessions.first { $0.id == id }
    }

    private func controls(_ sessionID: String) -> Result<VoiceControlsState, VoiceControlsError> {
        guard let session = session(sessionID) else { return .failure(.gone) }
        return .success(controls(of: session))
    }

    private func update(_ sessionID: String, _ change: (inout Session) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        change(&sessions[index])
        publishRoster()
    }

    private func end(_ sessionID: String, reason: VoiceSessionEndReason) {
        guard sessions.contains(where: { $0.id == sessionID }) else { return }
        sessions.removeAll { $0.id == sessionID }
        endedReasons[sessionID] = reason
        publishRoster()
    }

    private func publishRoster() {
        onRosterChange?(roster)
    }

    /// Someone else's lanes changed: your assistant's claims follow on the next roster.
    private func republishOwnLanes() {
        publishRoster()
    }

    // MARK: Lanes (ADR-0094 D2, D3)

    /// The lanes a `for_language` intent wants: every other person who doesn't speak it (base subtag), or published
    /// nothing; never the owner.
    private func wantedLanes(for language: String) -> [VoiceTranslationLane] {
        humans
            .filter { $0 != Self.me }
            .filter { speaker in membershipLanguages[speaker].map { !NativeCallLanguageCode.isSameSpokenLanguage($0, language) } ?? true }
            .map { VoiceTranslationLane(speaker: $0, language: language) }
    }

    /// What your session holds: the wanted lanes nobody else produces. Nothing while it joins, syncs or stopped.
    private func lanes(of session: Session) -> [VoiceTranslationLane] {
        guard session.phase == .active, session.stopped == nil, !session.isSyncing, let intent = session.intent else { return [] }
        switch intent {
        case .pocket(let first, let second):
            return [.init(speaker: Self.me, language: first), .init(speaker: Self.me, language: second)]
        case .forLanguage(let language):
            let claimed = Set(foreignAssistants.flatMap(\.liveLanes)).union(lanesAwaitingTakeover)
            return wantedLanes(for: language).filter { !claimed.contains($0) }
        }
    }

    // MARK: Documents (A.6) and controls (A.3)

    private func document(of session: Session) -> [String: Any] {
        let lanes = lanes(of: session)
        var functions: [[String: Any]] = []
        // A session still syncing runs its old mode: none here.
        if !session.isSyncing, session.intent != nil || session.stopped != nil {
            functions.append(Self.translationFunction(isActive: !lanes.isEmpty,
                                                      intent: session.intent,
                                                      source: session.source,
                                                      owner: Self.me,
                                                      lanes: lanes,
                                                      stopped: session.stopped))
        }
        if session.recording.isOn, !session.isRecordingStopped {
            functions.append(["kind": "recording", "active": true])
        }
        if session.summary.isOn {
            functions.append(["kind": "summary", "armed": true])
        }
        if session.conversation.isOn {
            functions.append(["kind": "conversation", "active": true])
        }
        return Self.document(lifecycle: session.phase == .ending ? "leaving" : "live",
                             leavingReason: nil,
                             modeEpoch: modeEpoch,
                             functions: functions)
    }

    private func document(of assistant: ForeignAssistant) -> [String: Any] {
        var functions: [[String: Any]] = []
        if !assistant.lanes.isEmpty || assistant.stopped != nil || assistant.standbyLanguage != nil {
            functions.append(Self.translationFunction(isActive: !assistant.liveLanes.isEmpty,
                                                      intent: assistant.lanes.first.map { .forLanguage($0.language) }
                                                          ?? assistant.standbyLanguage.map { .forLanguage($0) },
                                                      source: "override",
                                                      owner: assistant.owner,
                                                      lanes: assistant.liveLanes,
                                                      stopped: assistant.stopped))
        }
        if assistant.isRecording {
            functions.append(["kind": "recording", "active": true])
        }
        return Self.document(lifecycle: assistant.leavingReason == nil ? "live" : "leaving",
                             leavingReason: assistant.leavingReason,
                             modeEpoch: 1,
                             functions: functions)
    }

    private static func translationFunction(isActive: Bool,
                                            intent: VoiceTranslationParams?,
                                            source: String,
                                            owner: String,
                                            lanes: [VoiceTranslationLane],
                                            stopped: VoiceTranslationStopReason?) -> [String: Any] {
        var function: [String: Any] = ["kind": "translation",
                                       "active": isActive,
                                       "source": source,
                                       "owner": owner,
                                       "lanes": lanes.map { ["speaker": $0.speaker, "input": $0.input.rawValue, "language": $0.language] },
                                       "for_language": NSNull(),
                                       "pocket": NSNull(),
                                       "style": NSNull(),
                                       "stopped": stopped.map { ["reason": $0.labWire] } ?? NSNull()]
        switch intent {
        case .forLanguage(let language):
            function["for_language"] = language
            function["style"] = "simultaneous"
        case .pocket(let first, let second):
            function["pocket"] = [first, second]
            function["style"] = "consecutive"
        case nil:
            break
        }
        return function
    }

    private static func document(lifecycle: String, leavingReason: VoiceTranslationStopReason?, modeEpoch: Int, functions: [[String: Any]]) -> [String: Any] {
        ["v": 6,
         "agent": true,
         "lifecycle": lifecycle,
         "leaving_reason": leavingReason.map { $0.labWire as Any } ?? NSNull(),
         "call": "live",
         "mode_epoch": modeEpoch,
         "functions": functions]
    }

    /// The document as the transport delivers it, read by the app's own parser.
    private static func claim(_ document: [String: Any]) -> SpiralAgentStateReader.AgentClaim? {
        guard let data = try? JSONSerialization.data(withJSONObject: document),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return SpiralAgentStateReader.agentClaim(attributes: [SpiralAgentStateReader.attributeKey: json])
    }

    private func controls(of session: Session) -> VoiceControlsState {
        let lanes = lanes(of: session)
        let style: String? = switch session.intent {
        case .pocket where session.stopped == nil: "consecutive"
        case .forLanguage where session.stopped == nil: "simultaneous"
        default: nil
        }
        var forLanguage: String?
        var pocket: [String]?
        switch session.intent {
        case .forLanguage(let language): forLanguage = language
        case .pocket(let first, let second): pocket = [first, second]
        case nil: break
        }
        let effective = VoiceControlsEffective(source: session.intent == nil ? "off" : session.source,
                                               style: style,
                                               forLanguage: forLanguage,
                                               pocket: pocket,
                                               lanes: lanes,
                                               isStandby: session.phase == .active && forLanguage != nil && session.stopped == nil && !session.isSyncing && lanes.isEmpty,
                                               stoppedReason: session.stopped,
                                               isSyncing: session.isSyncing,
                                               pause: session.translationPause)
        let recordingDelivery: String? = session.recording.isOn ? (session.isRecordingStopped ? "delivered" : "pending") : nil
        return VoiceControlsState(sessionID: session.id,
                                  effective: effective,
                                  override: session.overrideRevision == 0 ? nil : VoiceControlsOverride(state: session.isOverrideEnabled ? "enabled" : "disabled",
                                                                                                        revision: session.overrideRevision),
                                  artifacts: VoiceControlsArtifacts(recording: VoiceArtifactState(enabled: session.recording.isOn,
                                                                                                  revision: session.recording.revision,
                                                                                                  delivery: recordingDelivery,
                                                                                                  deliveryTarget: session.isRecordingStopped ? "owner_dm" : nil,
                                                                                                  stopped: session.isRecordingStopped),
                                                                    summary: VoiceArtifactState(enabled: session.summary.isOn,
                                                                                                revision: session.summary.revision,
                                                                                                delivery: session.summary.isOn ? "pending" : nil,
                                                                                                deliveryTarget: nil,
                                                                                                stopped: false)),
                                  conversation: VoiceConversationState(active: session.conversation.isOn,
                                                                       available: session.isTalkAvailable,
                                                                       revision: session.conversation.revision))
    }

    private var usage: AgentUsage {
        let resetsAt = Self.limitResetsAt
        let categories = [AgentUsage.CategoryShare(category: .calls,
                                                   usedPercent: block == .callsPaused ? 100 : 41,
                                                   pause: block == .callsPaused ? .until(resetsAt) : nil),
                          AgentUsage.CategoryShare(category: .callTranslation,
                                                   usedPercent: isTranslationCapped ? 100 : 27,
                                                   pause: isTranslationCapped ? .until(resetsAt) : nil)]
        return AgentUsage(current: .init(period: .week,
                                         startsAt: resetsAt.addingTimeInterval(-7 * 86400),
                                         resetsAt: resetsAt,
                                         usedPercent: block == .weeklyLimit ? 100 : 68,
                                         limitReached: block == .weeklyLimit,
                                         categories: categories),
                          days: [])
    }

    private var consent: AIConsent {
        let isGranted = block != .consentOwner
        return AIConsent(isGranted: isGranted, currentVersion: "lab-1", decidedVersion: isGranted ? "lab-1" : nil)
    }
}

// MARK: - The translation port (ADR-0094's sources beside the documents)

extension NativeCallAssistantsLabBackend: NativeCallTranslationPortProtocol {
    func languages() async -> [VoiceControlsCatalogLanguage]? {
        await wait()
        return Self.catalog
    }

    func participantLanguages(roomID: String) async -> [String: String]? {
        membershipLanguages
    }

    func publishMyLanguage(_ language: String, roomID: String) async -> Bool {
        guard language != publishedLanguage else { return true }
        publishedLanguage = language
        publishRoster()
        return true
    }

    func tool(roomID: String) async -> Result<NativeCallTranslationTool?, NativeCallTranslationPortError> {
        await wait()
        return .success(tool)
    }

    func setTool(_ tool: NativeCallTranslationTool, roomID: String) async -> Bool {
        await wait()
        if takeNetworkFailure() != nil { return false }
        self.tool = tool.isEnabled ? tool : nil
        return true
    }
}

// MARK: - State

extension NativeCallAssistantsLabBackend {
    struct OwnAgent: Equatable {
        let id: String
        let mxid: String
        let name: String
    }

    struct Roster: Equatable {
        let participants: [NativeCallParticipant]
        let claims: NativeCallAgentClaims
        /// The languages the memberships publish (A.1).
        let languages: [String: String]
    }

    struct Switch: Equatable {
        var isOn = false
        var revision: Int32 = 1
    }

    /// Someone else's assistant, as its document shows it. The lab lets one hold lanes in two languages (John's in a
    /// 1:1, translating each side), which a real `for_language` intent wouldn't.
    struct ForeignAssistant: Equatable {
        let mxid: String
        let owner: String
        var lanes: [VoiceTranslationLane]
        var isRecording: Bool
        /// Its lanes into your language came from the panel's "Someone translates for you".
        var producesForYou = false
        /// Its translation stopped while it stays (it records).
        var stopped: VoiceTranslationStopReason?
        /// It leaves with this reason.
        var leavingReason: VoiceTranslationStopReason?
        /// D10: it stands by in this language — on, holding no lane — and takes over the lanes of a producer that stops.
        var standbyLanguage: String?

        /// What it airs: nothing once stopped or leaving.
        var liveLanes: [VoiceTranslationLane] {
            stopped == nil && leavingReason == nil ? lanes : []
        }
    }

    struct Session: Equatable {
        enum Phase: Equatable {
            case joining, active, ending

            var wire: String {
                switch self {
                case .joining: "pending_join"
                case .active: "active"
                case .ending: "ending"
                }
            }
        }

        let id: String
        let agent: String
        var phase: Phase
        var recording = Switch()
        /// Recording was stopped mid-call: what was captured went to the owner's chat (dictaphone semantics).
        var isRecordingStopped = false
        var summary = Switch()
        var conversation = Switch()
        /// The enabled translation intent; nil when off.
        var intent: VoiceTranslationParams?
        /// `override`, or `room_tool` when the personal Tool started it.
        var source = "override"
        var stopped: VoiceTranslationStopReason?
        var isOverrideEnabled = false
        var overrideRevision: Int32 = 0
        /// The runtime hasn't acknowledged the newest mode.
        var isSyncing = false
        /// The runtime runs the interpreter's mode (`LiveTranslation`): set when it acknowledges a translation, cleared
        /// when it acknowledges leaving it.
        var isModeTranslating = false
        var translationPause: AILimitPause?

        /// Talking and translating exclude each other while an intent is on, standing by or stopped but not turned off,
        /// and while the runtime still runs the interpreter (ADR-0094 D11, `conversation.available`).
        var isTalkAvailable: Bool {
            intent == nil && (stopped == nil || stopped == .ownerStopped) && !isModeTranslating
        }

        func revision(of control: VoiceSessionSwitch) -> Int32 {
            switch control {
            case .recording: recording.revision
            case .summary: summary.revision
            case .conversation: conversation.revision
            }
        }

        mutating func flip(_ control: VoiceSessionSwitch, to enabled: Bool) {
            switch control {
            case .recording:
                // Stopping keeps the recording: it is delivered, and a new start captures again.
                recording.isOn = recording.isOn || enabled
                isRecordingStopped = !enabled
                recording.revision += 1
            case .summary:
                summary.isOn = enabled
                summary.revision += 1
            case .conversation:
                conversation.isOn = enabled
                conversation.revision += 1
            }
        }
    }
}

private extension VoiceTranslationParams {
    var labWire: String {
        switch self {
        case .forLanguage(let language): "for_language \(language)"
        case .pocket(let first, let second): "pocket \(first) \(second)"
        }
    }
}

private extension VoiceTranslationStopReason {
    var labWire: String {
        switch self {
        case .ownerStopped: "owner_stopped"
        case .ownerLeft: "owner_left"
        case .aiLimit: "ai_limit"
        case .translationPaused: "translation_paused"
        case .callCap: "call_cap"
        case .ended: "ended"
        }
    }
}

private extension NativeCallAssistantsLabBackend.Block {
    var endReason: VoiceSessionEndReason {
        switch self {
        case .weeklyLimit: .budgetReached
        case .callsPaused: .categoryPaused(.calls)
        case .consentOwner: .aiConsentOwner
        case .consentRoom: .aiConsentRoom
        }
    }
}

#endif
