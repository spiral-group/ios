//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import ElementX
import Foundation
import Testing

// AGENT-PLATFORM (Brief 0063 closeout): pins for THE agent register every
// call surface reads. Two halves — the ladder that picks the block's event
// (Phase 1 of the call UI plan, moved here unchanged) and the rules that
// make the "REST read as a live fact" bug class impossible: live facts
// come from the roster + document only, REST is control only, and the one
// bridge between them is the owner's time-bounded optimism.

struct NativeCallAgentPresentationTests {
    private let agentMxid = "@assistant-alice:spiral.md"
    private let secondAgentMxid = "@assistant-bob:spiral.md"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func agent(_ mxid: String) -> NativeCallParticipant {
        NativeCallParticipant(id: "\(mxid):AGENT",
                              userID: mxid,
                              role: .agent,
                              mediaState: .connected,
                              isSpeaking: false,
                              isAudioEnabled: true,
                              isLocal: false)
    }

    private func session(_ mxid: String,
                         canControl: Bool = true,
                         isEnding: Bool = false,
                         recording: Bool = false,
                         recordingDelivery: NativeAgentCenterArtifact.Delivery = .notArmed,
                         summary: Bool = false,
                         languages: [String] = [],
                         conversation: NativeAgentCenterConversation = .unknown) -> NativeAgentCenterSession {
        NativeAgentCenterSession(sessionID: "session-\(mxid)",
                                 agentMxid: mxid,
                                 canControl: canControl,
                                 isEnding: isEnding,
                                 recording: .init(isEnabled: recording, revision: 1, delivery: recordingDelivery, isStopped: false),
                                 summary: .init(isEnabled: summary, revision: 1, delivery: .notArmed, isStopped: false),
                                 translation: .init(booths: languages.isEmpty
                                     ? []
                                     : [.init(speakerScope: "anyone", speakerMembers: [], targetLanguages: languages)],
                                     style: languages.isEmpty ? nil : "simultaneous",
                                     source: languages.isEmpty ? "off" : "override",
                                     revision: 1),
                                 conversation: conversation)
    }

    private func derive(agents: [NativeCallParticipant],
                        documents: [String: SpiralAgentStateReader.AgentClaim] = [:],
                        speaking: Set<String> = [],
                        sessions: [NativeAgentCenterSession] = [],
                        pendingWrites: [String: [NativeAgentCenterPendingWrite]] = [:],
                        isCallConnected: Bool = true,
                        falteredAgents: Set<String> = [],
                        covered: [String: String] = [:],
                        profiles: [String: NativeCallMemberProfile] = [:],
                        candidates: [NativeAgentCenterCandidate] = [],
                        ownUserID: String? = nil,
                        at time: Date? = nil) -> NativeCallAgentPresentation {
        var claims = NativeCallAgentClaims()
        claims.documents = documents
        claims.speaking = speaking
        var rest = NativeAgentCenterSnapshot(isAvailable: true, isLoading: false, sessions: sessions, candidates: candidates)
        rest.pendingOwnerWrites = pendingWrites
        return NativeCallAgentPresentation.derive(live: .init(participants: agents,
                                                              claims: claims,
                                                              coveredSpeakers: covered,
                                                              isCallConnected: isCallConnected,
                                                              falteredAgents: falteredAgents,
                                                              memberProfiles: profiles,
                                                              ownUserID: ownUserID),
                                                  rest: rest,
                                                  now: time ?? now)
    }

    private func write(_ fact: NativeAgentCenterPendingWrite.Fact, expiresIn seconds: TimeInterval = 10) -> NativeAgentCenterPendingWrite {
        .init(fact: fact, expiresAt: now.addingTimeInterval(seconds))
    }

    // MARK: - Presence (the roster is the only membership source)

    @Test
    func noAgentInTheRosterMeansNoAgentAndNoBlock() {
        let presentation = derive(agents: [], sessions: [session(agentMxid, recording: true)])

        #expect(presentation.agents.isEmpty)
        #expect(presentation.activeAgent == nil)
        // REST's session is control only: it can join, it cannot BE.
        #expect(presentation.joining.map(\.agentMxid) == [agentMxid])
        // And it cannot record a call it has not reached.
        #expect(!presentation.isCallRecording)
    }

    /// Attach accepted, agent not in the roster yet: a joining card, never a
    /// "Ready" agent with controls that would race the attach.
    @Test
    func aRestSessionWhoseAgentHasNotArrivedIsJoining() {
        let presentation = derive(agents: [agent(secondAgentMxid)],
                                  sessions: [session(agentMxid), session(secondAgentMxid)])

        #expect(presentation.agents.map(\.mxid) == [secondAgentMxid])
        #expect(presentation.joining.map(\.agentMxid) == [agentMxid])
    }

    /// Decision 182 — the agent is in the call but its runtime holds the
    /// gate (too few people): the block says it waits for people, and it
    /// does not claim to record. A live gate, or none in the document, reads
    /// as before.
    @Test
    func anAgentWhoseRuntimeWaitsForPeopleSaysSo() {
        let waiting = derive(agents: [agent(agentMxid)],
                             documents: [agentMxid: .make(recording: false, callGate: .waiting)])
        #expect(waiting.agents.first?.shown.event == .idle(role: .waitingForPeople, languages: []))
        #expect(waiting.isCallRecording == false)

        for gate in [SpiralAgentStateReader.CallGate.live, nil] {
            let other = derive(agents: [agent(agentMxid)],
                               documents: [agentMxid: .make(recording: true, callGate: gate)])
            #expect(other.agents.first?.shown.event == .idle(role: .recording, languages: []), "\(String(describing: gate))")
        }
    }

    /// Ending ∧ absent: the agent left the media, but the platform still
    /// tears the session down, so it can't be added again yet. Walk F6: it
    /// showed as nothing at all — "No agent has joined" next to "You have no
    /// agents available". It is "Removing…", never an agent card or "Joining…";
    /// the controller re-reads until the session is gone.
    @Test
    func anEndingSessionWhoseAgentLeftTheRosterIsBeingRemoved() {
        let presentation = derive(agents: [], sessions: [session(agentMxid, isEnding: true)])

        #expect(presentation.agents.isEmpty)
        #expect(presentation.joining.isEmpty)
        #expect(presentation.removing.map(\.agentMxid) == [agentMxid])
        #expect(presentation.removing.first?.isEndRequested == true)
    }

    /// REST's `ending` is a CONTROL fact (Remove goes inert), never
    /// presence: REST answering `ending` while the roster still listed the
    /// agent was the eternal "Leaving…". Presence comes from the document
    /// and the owner's bounded write.
    @Test
    func restEndingAloneIsNotLeaving() {
        let presentation = derive(agents: [agent(agentMxid)], sessions: [session(agentMxid, isEnding: true)])

        #expect(presentation.agents.first?.shown.presence == .present)
        #expect(presentation.agents.first?.control?.isEndRequested == true)
    }

    /// v3: the document says leaving before the participant disconnects —
    /// every device sees it, no REST involved.
    @Test
    func theDocumentsLifecycleMakesTheAgentLeavingOnEveryDevice() {
        let presentation = derive(agents: [agent(agentMxid)],
                                  documents: [agentMxid: .make(languages: ["en"], lifecycle: .leaving)])

        #expect(presentation.agents.first?.shown.presence == .leaving)
        #expect(presentation.agents.first?.control == nil)
    }

    @Test
    func anAgentInAnUnansweredCallIsWaiting() {
        let presentation = derive(agents: [agent(agentMxid)],
                                  documents: [agentMxid: .make(languages: ["en"])],
                                  speaking: [agentMxid],
                                  isCallConnected: false)

        #expect(presentation.agents.first?.shown.presence == .waiting)
        #expect(presentation.agents.first?.shown.event == .idle(role: .waiting, languages: []))
    }

    /// Removed before the peer answered: leaving, not idling (G7 ∧ remove).
    @Test
    func leavingOutranksWaiting() {
        let presentation = derive(agents: [agent(agentMxid)],
                                  pendingWrites: [agentMxid: [write(.leaving)]],
                                  isCallConnected: false)

        #expect(presentation.agents.first?.shown.presence == .leaving)
    }

    // MARK: - Own vs foreign (REST decides control, never presence)

    @Test
    func controlSplitsOwnFromForeignWithoutAffectingTheRoster() {
        let presentation = derive(agents: [agent(agentMxid), agent(secondAgentMxid)],
                                  sessions: [session(agentMxid, canControl: true)])

        #expect(presentation.ownAgents.map(\.mxid) == [agentMxid])
        #expect(presentation.foreignAgents.map(\.mxid) == [secondAgentMxid])
        #expect(presentation.foreignAgents.first?.control == nil)
    }

    /// A read-only REST session is control only: its translation is NEVER
    /// shown as what the agent does — the document is.
    @Test
    func aReadOnlyRestSessionCannotSupplyALiveLanguage() {
        let restOnly = derive(agents: [agent(agentMxid)],
                              sessions: [session(agentMxid, canControl: false, languages: ["de"])])
        #expect(restOnly.agents.first?.shown.languages == [])
        #expect(restOnly.agents.first?.control?.translation.languages == ["de"])

        let documentToo = derive(agents: [agent(agentMxid)],
                                 documents: [agentMxid: .make(languages: ["en"])],
                                 sessions: [session(agentMxid, canControl: false, languages: ["de"])])
        #expect(documentToo.agents.first?.shown.languages == ["en"])
    }

    // MARK: - Live facts come from the document only

    /// The recorder's own REST session must NOT light REC by itself: that
    /// is what made the owner's phone say "Recording" while the peer's said
    /// "Ready" (2026-09-02). Only the document — or a fresh owner write.
    @Test
    func restRecordingAloneIsNotARecording() {
        let presentation = derive(agents: [agent(agentMxid)], sessions: [session(agentMxid, recording: true)])

        #expect(presentation.agents.first?.shown.isRecording == false)
        #expect(presentation.agents.first?.live.isRecording == false)
        #expect(!presentation.isCallRecording)
        #expect(presentation.agents.first?.shown.event == .idle(role: nil, languages: []))
    }

    @Test
    func theDocumentsRecordingClaimLightsRecOnEveryDevice() {
        let presentation = derive(agents: [agent(agentMxid)], documents: [agentMxid: .make(recording: true)])

        #expect(presentation.agents.first?.shown.isRecording == true)
        #expect(presentation.isCallRecording)
        #expect(presentation.agents.first?.shown.event == .idle(role: .recording, languages: []))
        #expect(presentation.agents.first?.shown.bridged.isEmpty == true)
    }

    /// Brief 0080 — "the assistant talks" is a disclosure: it comes from
    /// the document, so every device shows it, the owner's or not.
    @Test
    func theDocumentsConversationTellsEveryDeviceTheAgentTalks() {
        let foreign = derive(agents: [agent(agentMxid)], documents: [agentMxid: .make(conversation: true)])
        #expect(foreign.agents.first?.control == nil)
        #expect(foreign.agents.first?.live.isConversationActive == true)
        #expect(foreign.agents.first?.shown.isConversationActive == true)
        #expect(foreign.agents.first?.shown.event == .idle(role: .conversation, languages: []))

        let silent = derive(agents: [agent(agentMxid)], documents: [agentMxid: .make(recording: true)])
        #expect(silent.agents.first?.shown.isConversationActive == false)
    }

    /// Talking leads the resting roles — REC keeps its own call-level pill
    /// — and a translation still names its languages.
    @Test
    func talkingOutranksRecordingAndSummaryButNotLanguages() {
        let both = derive(agents: [agent(agentMxid)], documents: [agentMxid: .make(recording: true, summaryArmed: true, conversation: true)])
        #expect(both.agents.first?.shown.event == .idle(role: .conversation, languages: []))
        #expect(both.isCallRecording, "a talking agent's capture is still disclosed on the header")

        let translating = derive(agents: [agent(agentMxid)], documents: [agentMxid: .make(languages: ["en"], conversation: true)])
        #expect(translating.agents.first?.shown.event == .idle(role: nil, languages: ["en"]))
    }

    // MARK: - The bridge: owner optimism, time-bounded

    @Test
    func anUnexpiredOwnerWriteOverridesTheDocument() {
        let presentation = derive(agents: [agent(agentMxid)],
                                  sessions: [session(agentMxid, recording: true)],
                                  pendingWrites: [agentMxid: [write(.recording(true))]])

        #expect(presentation.agents.first?.shown.isRecording == true)
        #expect(presentation.agents.first?.live.isRecording == false)
        #expect(presentation.agents.first?.shown.bridged == [.recording])
        #expect(presentation.isCallRecording)
    }

    @Test
    func anExpiredOwnerWriteIsIgnoredAndTheDocumentRules() {
        let presentation = derive(agents: [agent(agentMxid)],
                                  sessions: [session(agentMxid, recording: true)],
                                  pendingWrites: [agentMxid: [write(.recording(true), expiresIn: -1)]])

        #expect(presentation.agents.first?.shown.isRecording == false)
        #expect(presentation.agents.first?.shown.bridged.isEmpty == true)
    }

    @Test
    func aTranslationWriteBridgesTheLanguagesUntilTheDocumentAgrees() {
        let optimistic = derive(agents: [agent(agentMxid)],
                                sessions: [session(agentMxid, languages: ["uk"])],
                                pendingWrites: [agentMxid: [write(.translation(languages: ["uk"]))]])
        #expect(optimistic.agents.first?.shown.languages == ["uk"])
        #expect(optimistic.agents.first?.shown.bridged == [.translation])
        #expect(optimistic.agents.first?.shown.event == .idle(role: nil, languages: ["uk"]))

        // Disable: the write says "empty", which beats a stale document.
        let disabled = derive(agents: [agent(agentMxid)],
                              documents: [agentMxid: .make(languages: ["uk"])],
                              pendingWrites: [agentMxid: [write(.translation(languages: []))]])
        #expect(disabled.agents.first?.shown.languages == [])
        #expect(disabled.agents.first?.shown.isTranslating == false)
    }

    /// Brief 0080 — the owner's switch is bridged like any other until the
    /// document agrees; REST only says whether the switch is offered.
    @Test
    func aConversationWriteBridgesUntilTheDocumentAgrees() {
        let offered = NativeAgentCenterConversation(isAvailable: true, revision: 1)
        let restOnly = derive(agents: [agent(agentMxid)], sessions: [session(agentMxid, conversation: offered)])
        #expect(restOnly.agents.first?.shown.isConversationActive == false)
        #expect(restOnly.agents.first?.control?.conversation == offered)

        let optimistic = derive(agents: [agent(agentMxid)],
                                sessions: [session(agentMxid, conversation: offered)],
                                pendingWrites: [agentMxid: [write(.conversation(true))]])
        #expect(optimistic.agents.first?.live.isConversationActive == false)
        #expect(optimistic.agents.first?.shown.isConversationActive == true)
        #expect(optimistic.agents.first?.shown.bridged == [.conversation])
        #expect(optimistic.agents.first?.shown.event == .idle(role: .conversation, languages: []))

        // Silencing: the write says "silent", which beats a stale document.
        let silenced = derive(agents: [agent(agentMxid)],
                              documents: [agentMxid: .make(conversation: true)],
                              pendingWrites: [agentMxid: [write(.conversation(false))]])
        #expect(silenced.agents.first?.shown.isConversationActive == false)

        let expired = derive(agents: [agent(agentMxid)],
                             pendingWrites: [agentMxid: [write(.conversation(true), expiresIn: -1)]])
        #expect(expired.agents.first?.shown.isConversationActive == false)
    }

    @Test
    func aLeavingWriteMakesTheAgentLeavingBeforeRestOrTheDocumentSaySo() {
        let presentation = derive(agents: [agent(agentMxid)],
                                  sessions: [session(agentMxid)],
                                  pendingWrites: [agentMxid: [write(.leaving)]])

        #expect(presentation.agents.first?.shown.presence == .leaving)
        #expect(presentation.agents.first?.shown.bridged == [.leaving])
    }

    // MARK: - The ladder (Phase 1, unchanged)

    @Test
    func airingOutranksIdle() {
        let presentation = derive(agents: [agent(agentMxid)],
                                  documents: [agentMxid: .make(languages: ["en", "de"])],
                                  speaking: [agentMxid])

        #expect(presentation.agents.first?.shown.event == .airing(.translation(languages: ["en", "de"])))
        #expect(presentation.agents.first?.live.isAiring == true)
    }

    @Test
    func theLadderRanksFailureAboveAiringAbovePausedAboveOriginalAboveIdle() {
        let ladder: [NativeCallAgentEvent] = [.failure(.deliveryFailed),
                                              .airing(.translation(languages: ["en"])),
                                              .paused,
                                              .original,
                                              .idle(role: nil, languages: [])]

        #expect(ladder.map(\.priority) == [0, 1, 2, 3, 4])
        #expect(ladder.min() == .failure(.deliveryFailed))
        #expect(ladder.reversed().min() == .failure(.deliveryFailed))
    }

    /// Conversation airs exactly like a translation: the document says the
    /// agent talks, and it is speaking — every device shows the wave.
    @Test
    func aTalkingAgentAirsWhileItSpeaks() throws {
        let presentation = derive(agents: [agent(agentMxid)],
                                  documents: [agentMxid: .make(conversation: true)],
                                  speaking: [agentMxid])

        #expect(presentation.agents.first?.control == nil, "a peer sees it with no REST at all")
        #expect(presentation.agents.first?.shown.event == .airing(.conversation))
        #expect(presentation.agents.first?.live.isAiring == true)
        #expect(presentation.agents.first?.shown.isAiring == true)
        #expect(try NativeCallAgentBlockState(#require(presentation.activeAgent)).isAiring)

        let between = derive(agents: [agent(agentMxid)], documents: [agentMxid: .make(conversation: true)])
        #expect(between.agents.first?.shown.event == .idle(role: .conversation, languages: []))
        #expect(between.agents.first?.shown.isAiring == false)
    }

    /// One function airs at a time: a translation names its languages over
    /// the conversation, and a paused one airs nothing.
    @Test
    func aTranslationAirsBeforeTheConversation() {
        let translating = derive(agents: [agent(agentMxid)],
                                 documents: [agentMxid: .make(languages: ["en"], conversation: true)],
                                 speaking: [agentMxid])
        #expect(translating.agents.first?.shown.event == .airing(.translation(languages: ["en"])))

        let paused = derive(agents: [agent(agentMxid)],
                            documents: [agentMxid: .make(languages: ["en"], paused: true, conversation: true)],
                            speaking: [agentMxid])
        #expect(paused.agents.first?.shown.event == .paused)
        #expect(paused.agents.first?.shown.isAiring == false)
    }

    /// The owner's Silent tap stops the wave at once, as a Disable tap does
    /// for a translation.
    @Test
    func aSilentWriteStopsTheConversationWaveBeforeTheDocumentCatchesUp() {
        let presentation = derive(agents: [agent(agentMxid)],
                                  documents: [agentMxid: .make(conversation: true)],
                                  speaking: [agentMxid],
                                  pendingWrites: [agentMxid: [write(.conversation(false))]])

        #expect(presentation.agents.first?.live.isAiring == true)
        #expect(presentation.agents.first?.shown.isAiring == false)
        #expect(presentation.agents.first?.shown.event == .idle(role: nil, languages: []))
    }

    @Test
    func aClaimedButSilentTranslatorDoesNotWave() {
        let presentation = derive(agents: [agent(agentMxid)], documents: [agentMxid: .make(languages: ["en"])])

        #expect(presentation.agents.first?.shown.event == .idle(role: nil, languages: ["en"]))
    }

    @Test
    func aSpeakingAgentWithoutAClaimDoesNotWave() {
        let presentation = derive(agents: [agent(agentMxid)], speaking: [agentMxid])

        #expect(presentation.agents.first?.shown.event == .idle(role: nil, languages: []))
        #expect(presentation.isAnyAgentSpeaking)
    }

    @Test
    func recordingWinsOverSummaryAsTheRoleWord() {
        let presentation = derive(agents: [agent(agentMxid)],
                                  documents: [agentMxid: .make(recording: true, summaryArmed: true)])

        #expect(presentation.agents.first?.shown.event == .idle(role: .recording, languages: []))
    }

    /// Summary has a document form (v3). The owner's REST flag is control:
    /// alone it names nothing; the owner's fresh write bridges.
    @Test
    func summaryComesFromTheDocumentOrTheOwnersWriteNeverFromRestAlone() {
        let fromDocument = derive(agents: [agent(agentMxid)], documents: [agentMxid: .make(summaryArmed: true)])
        #expect(fromDocument.agents.first?.shown.event == .idle(role: .summary, languages: []))
        #expect(fromDocument.agents.first?.shown.isSummaryArmed == true)

        let fromRest = derive(agents: [agent(agentMxid)], sessions: [session(agentMxid, summary: true)])
        #expect(fromRest.agents.first?.shown.event == .idle(role: nil, languages: []))
        #expect(fromRest.agents.first?.shown.isSummaryArmed == false)

        let fromWrite = derive(agents: [agent(agentMxid)],
                               sessions: [session(agentMxid, summary: true)],
                               pendingWrites: [agentMxid: [write(.summary(true))]])
        #expect(fromWrite.agents.first?.shown.event == .idle(role: .summary, languages: []))
        #expect(fromWrite.agents.first?.shown.bridged == [.summary])
    }

    @Test
    func aClaimedButInactiveTranslatorShowsPaused() {
        let presentation = derive(agents: [agent(agentMxid)],
                                  documents: [agentMxid: .make(languages: ["en"], paused: true)],
                                  speaking: [agentMxid])

        #expect(presentation.agents.first?.shown.event == .paused)
        // Paused still names its languages — the sheet's row is not "Off".
        #expect(presentation.agents.first?.shown.languages == ["en"])
        #expect(presentation.agents.first?.shown.isPaused == true)
        #expect(presentation.agents.first?.live.isAiring == false)
    }

    @Test
    func aFailedDeliveryOutranksAiring() {
        let presentation = derive(agents: [agent(agentMxid)],
                                  documents: [agentMxid: .make(languages: ["en"])],
                                  speaking: [agentMxid],
                                  sessions: [session(agentMxid, recording: true, recordingDelivery: .failed)])

        #expect(presentation.agents.first?.shown.event == .failure(.deliveryFailed))
    }

    @Test
    func aFailedDeliveryOutranksWaiting() {
        let presentation = derive(agents: [agent(agentMxid)],
                                  sessions: [session(agentMxid, recording: true, recordingDelivery: .failed)],
                                  isCallConnected: false)

        #expect(presentation.agents.first?.shown.event == .failure(.deliveryFailed))
    }

    /// Only the agent whose lane faltered says so — the other agent's
    /// translation is still playing (Brief 0066 rev. 2, per-agent falter).
    @Test
    func aFalteredTranslationShowsOriginalOnItsOwnAgentOnly() {
        let presentation = derive(agents: [agent(agentMxid), agent(secondAgentMxid)],
                                  documents: [agentMxid: .make(languages: ["en"]), secondAgentMxid: .make(languages: ["de"])],
                                  falteredAgents: [agentMxid])

        #expect(presentation.agents.first { $0.mxid == agentMxid }?.shown.event == .original)
        #expect(presentation.agents.first { $0.mxid == secondAgentMxid }?.shown.event != .original)
    }

    @Test
    func failAudibleWithoutAClaimStaysIdle() {
        let presentation = derive(agents: [agent(agentMxid)], falteredAgents: [agentMxid])

        #expect(presentation.agents.first?.shown.event == .idle(role: nil, languages: []))
    }

    // MARK: - The active agent and ordinals

    @Test
    func theAiringAgentIsShownWhenSeveralAreAttached() {
        let presentation = derive(agents: [agent(agentMxid), agent(secondAgentMxid)],
                                  documents: [secondAgentMxid: .make(languages: ["de"])],
                                  speaking: [secondAgentMxid])

        #expect(presentation.activeAgent?.mxid == secondAgentMxid)
        #expect(presentation.activeAgent?.ordinal == .init(index: 2, count: 2))
    }

    @Test
    func theTalkingAgentIsShownWhenSeveralAreAttached() {
        let presentation = derive(agents: [agent(agentMxid), agent(secondAgentMxid)],
                                  documents: [agentMxid: .make(recording: true),
                                              secondAgentMxid: .make(conversation: true)],
                                  speaking: [secondAgentMxid])

        #expect(presentation.activeAgent?.mxid == secondAgentMxid)
        #expect(presentation.activeAgent?.shown.event == .airing(.conversation))
    }

    /// Airing is selected by the wave's fact, not by the event — a delivery
    /// failure outranks airing on the ladder but must not hide the wave.
    @Test
    func anAiringAgentWithADeliveryFailureIsStillTheActiveOne() {
        let presentation = derive(agents: [agent(agentMxid), agent(secondAgentMxid)],
                                  documents: [secondAgentMxid: .make(languages: ["de"])],
                                  speaking: [secondAgentMxid],
                                  sessions: [session(secondAgentMxid, recording: true, recordingDelivery: .failed)])

        #expect(presentation.activeAgent?.mxid == secondAgentMxid)
        #expect(presentation.activeAgent?.shown.event == .failure(.deliveryFailed))
        #expect(presentation.activeAgent?.shown.isAiring == true)
    }

    @Test
    func aSpeakingAgentWithoutAClaimIsNotSelectedAsActive() {
        let presentation = derive(agents: [agent(agentMxid), agent(secondAgentMxid)], speaking: [secondAgentMxid])

        #expect(presentation.activeAgent?.mxid == agentMxid)
    }

    /// A Disable tap silences the wave at once: airing follows the SHOWN
    /// languages, not the document's, for the window.
    @Test
    func aDisableWriteStopsTheWaveBeforeTheDocumentCatchesUp() {
        let presentation = derive(agents: [agent(agentMxid)],
                                  documents: [agentMxid: .make(languages: ["en"])],
                                  speaking: [agentMxid],
                                  pendingWrites: [agentMxid: [write(.translation(languages: []))]])

        #expect(presentation.agents.first?.live.isAiring == true)
        #expect(presentation.agents.first?.shown.isAiring == false)
        #expect(presentation.agents.first?.shown.event == .idle(role: nil, languages: []))
    }

    @Test
    func theFirstAgentIsShownWhenNoneIsAiring() {
        let presentation = derive(agents: [agent(agentMxid), agent(secondAgentMxid)],
                                  documents: [secondAgentMxid: .make(languages: ["de"])])

        #expect(presentation.activeAgent?.mxid == agentMxid)
        #expect(presentation.activeAgent?.ordinal == .init(index: 1, count: 2))
    }

    @Test
    func aSingleAgentHasNoOrdinal() {
        #expect(derive(agents: [agent(agentMxid)]).activeAgent?.ordinal == nil)
    }

    @Test
    func theBlockProjectsTheActiveAgent() throws {
        let presentation = derive(agents: [agent(agentMxid), agent(secondAgentMxid)],
                                  documents: [agentMxid: .make(recording: true)],
                                  profiles: [agentMxid: .init(displayName: "Alice's Assistant")])
        let block = try NativeCallAgentBlockState(#require(presentation.activeAgent))

        #expect(block.name == "Alice's Assistant")
        #expect(block.agentUserID == agentMxid)
        #expect(block.event == .idle(role: .recording, languages: []))
        #expect(block.agentCountLine == UntranslatedL10n.screenNativeCallAgentBlockCount(1, 2))
        #expect(!block.isAiring)
    }

    // MARK: - Brief 0066: style and "covers me"

    @Test
    func theStyleAndWhoCoversMeComeFromTheDocument() {
        let me = "@me:spiral.md"
        let open = derive(agents: [agent(agentMxid)],
                          documents: [agentMxid: .make(languages: ["en"], style: .simultaneous)],
                          ownUserID: me)
        #expect(open.agents.first?.live.style == .simultaneous)
        #expect(open.agents.first?.live.coversMe == .live(languages: ["en"]))

        let interpreter = derive(agents: [agent(agentMxid)],
                                 documents: [agentMxid: .make(languages: ["en", "de"], style: .consecutive)],
                                 ownUserID: me)
        #expect(interpreter.agents.first?.live.coversMe == .interpreter(languages: ["de", "en"]))

        let exceptMe = derive(agents: [agent(agentMxid)],
                              documents: [agentMxid: .make(languages: ["en"],
                                                           booths: [.init(coverage: .exceptMembers([me]), targetLanguages: ["en"])])],
                              ownUserID: me)
        #expect(exceptMe.agents.first?.live.coversMe == nil)

        let onlyBob = derive(agents: [agent(agentMxid)],
                             documents: [agentMxid: .make(languages: ["en"],
                                                          booths: [.init(coverage: .members(["@bob:spiral.md"]), targetLanguages: ["en"])])],
                             ownUserID: me)
        #expect(onlyBob.agents.first?.live.coversMe == nil)

        // The local user unknown: no claim about me.
        #expect(derive(agents: [agent(agentMxid)], documents: [agentMxid: .make(languages: ["en"])]).agents.first?.live.coversMe == nil)
        #expect(derive(agents: [agent(agentMxid)]).agents.first?.live.style == nil)
    }

    // MARK: - Names and the panel

    @Test
    func theNameIsProfileThenCandidateThenTheMxidRule() {
        let profile = derive(agents: [agent(agentMxid)],
                             profiles: [agentMxid: .init(displayName: "Marta's Assistant")],
                             candidates: [.init(id: "a", mxid: agentMxid, displayName: "Assistant", avatarURL: nil, isRoomMember: true)])
        #expect(profile.agents.first?.displayName == "Marta's Assistant")

        let candidate = derive(agents: [agent(agentMxid)],
                               candidates: [.init(id: "a", mxid: agentMxid, displayName: "Assistant", avatarURL: nil, isRoomMember: true)])
        #expect(candidate.agents.first?.displayName == "Assistant")

        #expect(derive(agents: [agent(agentMxid)]).agents.first?.displayName == "Assistant Alice")
    }

    @Test
    func attachedCandidatesAreNotOfferedAgain() {
        let presentation = derive(agents: [agent(agentMxid)],
                                  sessions: [session(agentMxid)],
                                  candidates: [.init(id: "a", mxid: agentMxid, displayName: "A", avatarURL: nil, isRoomMember: true),
                                               .init(id: "b", mxid: secondAgentMxid, displayName: "B", avatarURL: nil, isRoomMember: true)])

        #expect(presentation.panel.candidates.map(\.mxid) == [secondAgentMxid])
    }

    @Test
    func coveredSpeakersPassThroughForTheRoster() {
        let presentation = derive(agents: [], covered: ["@bob:spiral.md": "en"])

        #expect(presentation.coveredSpeakers == ["@bob:spiral.md": "en"])
    }

    @Test
    func controlLookupCoversPresentAndJoiningSessions() {
        let presentation = derive(agents: [agent(agentMxid)],
                                  sessions: [session(agentMxid), session(secondAgentMxid)])

        #expect(presentation.control(sessionID: "session-\(agentMxid)")?.agentMxid == agentMxid)
        #expect(presentation.control(sessionID: "session-\(secondAgentMxid)")?.agentMxid == secondAgentMxid)
        #expect(presentation.control(sessionID: "nope") == nil)
    }
}
