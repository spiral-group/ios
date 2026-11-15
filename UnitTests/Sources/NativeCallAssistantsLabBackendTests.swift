//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

#if DEBUG || SPIRAL_STAGING

import Foundation
@testable import Spiral
import Testing

// AGENT-PLATFORM (Brief 0083, question 401; Brief 0085, question 403): the lab's mocked platform changes its state the
// way the sheet and the call's translation expect.

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct NativeCallAssistantsLabBackendTests {
    private typealias Backend = NativeCallAssistantsLabBackend

    @Test
    func anAddedAssistantJoinsTheRosterWithItsDocument() async throws {
        let backend = makeBackend(.onePerson)

        let sessionID = try await backend.attachVoiceAgent(agentID: Backend.agentID, roomID: Backend.roomID, params: listening).get()
        #expect(try await backend.voiceSessionProgress(sessionID: sessionID).get() == .joining)
        #expect(backend.roster.participants.contains { $0.userID == Backend.myAgent } == false)

        await waitUntil { backend.ownSession?.phase == .active }
        #expect(try await backend.voiceSessionProgress(sessionID: sessionID).get() == .active)
        #expect(backend.roster.participants.contains { $0.userID == Backend.myAgent })
        #expect(backend.roster.claims.documents[Backend.myAgent]?.isSummaryArmed == true)
    }

    /// ADR-0094 D2/D3: your `for_language` intent claims only the lanes nobody else airs; with all of them taken it
    /// stands by, and the document says so (v6, read by the app's parser).
    @Test
    func yourIntentClaimsWhatIsFreeOrStandsBy() async throws {
        let backend = makeBackend(.group)
        backend.syncDuration = .milliseconds(10)
        let sessionID = try await activeSession(backend)

        _ = try await backend.setVoiceTranslation(sessionID: sessionID, params: .forLanguage("uk"), revision: 0).get()
        await waitUntil { backend.roster.claims.documents[Backend.myAgent]?.translation.isActive == true }
        // Mira speaks English and Alex German; Bohdan speaks Ukrainian, so he isn't translated into it.
        #expect(backend.roster.claims.documents[Backend.myAgent]?.translation.lanes.map(\.speaker).sorted() == [Backend.alex, Backend.mira])

        backend.startOwnStandby()
        let standby = try await backend.voiceSessionControls(sessionID: backend.ownSession?.id ?? "").get()
        #expect(standby.effective.isStandby)
        #expect(backend.roster.claims.documents[Backend.myAgent]?.translation.isStandby == true)
    }

    /// A.2: the pocket interpreter only in the owner's chat, `for_language` only between people; a paused category
    /// refuses an enabling write and changes nothing; a 503 answers once.
    @Test
    func enablingWritesAreRefusedTheContractsWay() async throws {
        let backend = makeBackend(.group)
        let sessionID = try await activeSession(backend)

        guard case .failure(.intentUnavailable(let roomKind)) = await backend.setVoiceTranslation(sessionID: sessionID, params: .pocket("uk", "en"), revision: 0) else {
            Issue.record("The pocket interpreter in a group should be refused")
            return
        }
        #expect(roomKind == "group")

        backend.nextFailure = .serviceUnavailable
        guard case .failure(.serviceUnavailable) = await backend.setVoiceTranslation(sessionID: sessionID, params: .forLanguage("uk"), revision: 0) else {
            Issue.record("An armed 503 should answer the write")
            return
        }
        _ = try await backend.setVoiceTranslation(sessionID: sessionID, params: .forLanguage("uk"), revision: 0).get()

        backend.exhaustOwnLimit()
        let revision = backend.ownSession?.overrideRevision ?? 0
        guard case .failure(.translationPaused(let refusal)) = await backend.setVoiceTranslation(sessionID: sessionID, params: .forLanguage("uk"), revision: revision) else {
            Issue.record("A paused category should refuse turning translation on")
            return
        }
        #expect(refusal.reason == .translationPaused)
        #expect(backend.ownSession?.stopped == .translationPaused)
    }

    /// Scenarios 3 and 4.1, D6: Bohdan's assistant translates Mira into Ukrainian; it stops on its owner leaving and,
    /// with nothing else to do, leaves with that reason.
    @Test
    func someoneElsesLaneStartsAndStopsWithItsReason() async {
        let backend = makeBackend(.group)
        #expect(backend.membershipLanguages == [Backend.mira: "en", Backend.alex: "de", Backend.bohdan: "uk"])

        backend.startForeignTranslation()
        let lanes = NativeCallTranslationLane.lanes(documents: backend.roster.claims.documents).filter { $0.language == "uk" }
        #expect(lanes == [NativeCallTranslationLane(speaker: Backend.mira, input: .voice, language: "uk", producer: Backend.bohdanAgent, owner: Backend.bohdan)])

        backend.stopForeignTranslation(reason: .ownerLeft)
        #expect(backend.roster.claims.documents[Backend.bohdanAgent]?.leavingReason == .ownerLeft)
        await waitUntil { backend.roster.claims.documents[Backend.bohdanAgent] == nil }
        #expect(backend.roster.claims.documents[Backend.bohdanAgent] == nil)
    }

    /// One that records stays, its translation stopped.
    @Test
    func aRecordingAssistantStaysWithItsTranslationStopped() {
        let backend = makeBackend(.personWithAssistant)
        backend.startForeignTranslation()

        backend.stopForeignTranslation(reason: .ownerLeft)

        let translation = backend.roster.claims.documents[Backend.johnAgent]?.translation
        #expect(translation?.stoppedReason == .ownerLeft)
        #expect(translation?.lanes.isEmpty == true)
        #expect(backend.roster.claims.documents[Backend.johnAgent]?.isRecording == true)
    }

    /// Scenario 9.4: an assistant called while the call rings joins once someone answers.
    @Test
    func anAssistantCalledWhileItRingsComesOnTheAnswer() async throws {
        let backend = makeBackend(.onePerson)
        backend.setRinging(true)

        _ = try await backend.attachVoiceAgent(agentID: Backend.agentID, roomID: Backend.roomID, params: listening).get()
        try await Task.sleep(for: .milliseconds(50))
        #expect(backend.ownSession?.phase == .joining)

        backend.setRinging(false)
        await waitUntil { backend.ownSession?.phase == .active }
        #expect(backend.ownSession?.phase == .active)
    }

    /// Scenario 5: the chat's tool is stored and published, and so is "my language".
    @Test
    func theToolAndMyLanguageAreStored() async throws {
        let backend = makeBackend(.onePerson)
        let tool = NativeCallTranslationTool(isEnabled: true, language: "uk", translatesIfNobodyDoes: true)

        #expect(await backend.setTool(tool, roomID: Backend.roomID))
        #expect(await backend.publishMyLanguage("uk", roomID: Backend.roomID))

        #expect(try await backend.tool(roomID: Backend.roomID).get() == tool)
        #expect(await backend.participantLanguages(roomID: Backend.roomID)?[Backend.me] == "uk")
    }

    @Test
    func theWeeklyLimitOnAnAddEndsTheJoinAndStaysForTheNextCheck() async throws {
        let backend = makeBackend(.onePerson)
        backend.nextFailure = .weeklyLimit

        let sessionID = try await backend.attachVoiceAgent(agentID: Backend.agentID, roomID: Backend.roomID, params: listening).get()
        #expect(backend.nextFailure == .none, "the failure answers one action")

        await waitUntil { backend.ownSession == nil }
        #expect(try await backend.voiceSessionProgress(sessionID: sessionID).get() == .ended(.budgetReached))
        #expect(try await backend.voiceJoinCheck(agentID: Backend.agentID, roomID: Backend.roomID).get() == .budgetReached)
        #expect(try await backend.fetchAgentUsage(agentID: Backend.agentID).get().current.limitReached)
        #expect(try await backend.voiceSessionControlContexts(roomID: Backend.roomID).get().isEmpty)
    }

    @Test
    func aStaleRevisionConflictsAndStoppingARecordingKeepsIt() async throws {
        let backend = makeBackend(.onePerson)
        let sessionID = try await activeSession(backend, params: .init(translation: nil, recording: true, summary: false, conversation: false))

        #expect(await backend.setVoiceSwitch(sessionID: sessionID, control: .recording, enabled: false, revision: 7).isConflict)

        let stopped = try await backend.setVoiceSwitch(sessionID: sessionID, control: .recording, enabled: false, revision: 1).get()
        #expect(stopped.artifacts.recording.enabled)
        #expect(stopped.artifacts.recording.stopped)
        #expect(stopped.artifacts.recording.delivery == "delivered")
        #expect(stopped.artifacts.recording.revision == 2)
        #expect(backend.roster.claims.documents[Backend.myAgent]?.isRecording == false)
    }

    @Test
    func aRemovedAssistantLeavesThroughEnding() async throws {
        let backend = makeBackend(.onePerson)
        let sessionID = try await activeSession(backend)

        try await backend.endVoiceSession(sessionID: sessionID).get()
        #expect(try await backend.voiceSessionControlContexts(roomID: Backend.roomID).get().first?.isEnding == true)
        #expect(backend.roster.claims.documents[Backend.myAgent]?.lifecycle == .leaving)

        await waitUntil { backend.ownSession == nil }
        #expect(try await backend.voiceSessionProgress(sessionID: sessionID).get() == .ended(.manual))
        #expect(backend.roster.participants.contains { $0.userID == Backend.myAgent } == false)
    }

    @Test
    func onlyAModeratorRemovesSomeoneElsesAssistant() async {
        let member = makeBackend(.personWithAssistant, role: .member)
        #expect(await member.kick(Backend.johnAgent) == false)
        #expect(member.foreignAssistants.count == 1)

        let moderator = makeBackend(.personWithAssistant, role: .moderator)
        #expect(await moderator.kick(Backend.johnAgent))
        #expect(moderator.foreignAssistants.isEmpty)
        #expect(moderator.roster.claims.documents[Backend.johnAgent] == nil)
    }

    @Test
    func aNetworkErrorAnswersOneActionOnly() async {
        let backend = makeBackend(.onePerson)
        backend.nextFailure = .network

        #expect(await backend.attachVoiceAgent(agentID: Backend.agentID, roomID: Backend.roomID, params: listening).isUnavailable)
        #expect(await backend.attachVoiceAgent(agentID: Backend.agentID, roomID: Backend.roomID, params: listening).isUnavailable == false)
    }

    @Test
    func aPausedAssistantIsRefusedUntilResumed() async throws {
        let backend = Backend(cast: .onePerson, role: .moderator, latency: .none, isPaused: true)
        #expect(try await backend.voiceJoinCheck(agentID: Backend.agentID, roomID: Backend.roomID).get() == .paused)

        var patch = AgentEditPatch()
        patch.paused = false
        _ = try await backend.editAgent(agentID: Backend.agentID, patch: patch).get()

        #expect(try await backend.voiceJoinCheck(agentID: Backend.agentID, roomID: Backend.roomID).get() == .ok)
        #expect(try await backend.listMyPersonalAgents().get().agents.first?.lifecycleState == "active")
    }

    // MARK: - Helpers

    private let listening = VoiceAttachParams(translation: nil, recording: false, summary: true, conversation: false)

    private func makeBackend(_ cast: Backend.Cast, role: Backend.Role = .moderator) -> Backend {
        Backend(cast: cast, role: role, latency: .none, joinDuration: .milliseconds(10), leaveDuration: .milliseconds(10))
    }

    private func activeSession(_ backend: Backend, params: VoiceAttachParams? = nil) async throws -> String {
        let sessionID = try await backend.attachVoiceAgent(agentID: Backend.agentID, roomID: Backend.roomID, params: params ?? listening).get()
        await waitUntil { backend.ownSession?.phase == .active }
        return sessionID
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private extension Result where Failure == VoiceControlsError {
    var isConflict: Bool {
        if case .failure(.conflict) = self { return true }
        return false
    }

    var isUnavailable: Bool {
        if case .failure(.unavailable) = self { return true }
        return false
    }
}

#endif
