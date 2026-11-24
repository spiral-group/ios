//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Foundation
@testable import Spiral
import Synchronization
import Testing

// AGENT-PLATFORM (Brief 0063 Slice 3)

@MainActor
@Suite(.timeLimit(.minutes(2)))
struct NativeAgentCenterControllerTests {
    @Test
    func loadingBuildsSessionsFromBackendTruth() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: true, recordingRevision: 4))
        let controller = makeController(service: service)

        await controller.reload()

        #expect(controller.snapshot.isAvailable)
        #expect(controller.snapshot.isLoading == false)
        #expect(controller.snapshot.sessions.count == 1)
        #expect(controller.snapshot.sessions.first?.recording.isEnabled == true)
        #expect(controller.snapshot.sessions.first?.recording.revision == 4)
        #expect(controller.snapshot.attachedAgentMxids == ["@assistant-red:spiral.md"])
    }

    /// An unreachable platform must not present an Agent Center that can only
    /// fail — the entry point disappears instead.
    @Test
    func anUnreachablePlatformIsReportedAsUnavailable() async {
        let service = AgentPlatformServiceMock()
        service.voiceSessionControlContextsRoomIDReturnValue = .failure(.unavailable("offline"))
        let controller = makeController(service: service)

        await controller.reload()

        #expect(controller.snapshot.isAvailable == false)
        #expect(controller.snapshot.lastError == .unavailable("offline"))
    }

    /// A session that ends between the list and the controls read is dropped,
    /// not allowed to fail the whole load.
    @Test
    func aSessionThatEndsDuringLoadingIsDropped() async {
        let service = makeService(contexts: [makeContext()], controls: nil)
        service.voiceSessionControlsSessionIDReturnValue = .failure(.gone)
        let controller = makeController(service: service)

        await controller.reload()

        #expect(controller.snapshot.isAvailable)
        #expect(controller.snapshot.sessions.isEmpty)
    }

    /// The CAS token must come from backend truth, never from the view.
    @Test
    func anArtifactWriteCarriesTheRevisionFromTheLastRead() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: true, recordingRevision: 7))
        let controller = makeController(service: service)
        await controller.reload()

        service.setVoiceSwitchSessionIDControlEnabledRevisionReturnValue =
            .success(makeControls(recordingEnabled: false, recordingRevision: 8))

        let didSucceed = await controller.setSwitch(sessionID: "session-1", control: .recording, enabled: false)

        #expect(didSucceed)
        #expect(service.setVoiceSwitchSessionIDControlEnabledRevisionReceivedArguments?.revision == 7)
        #expect(service.setVoiceSwitchSessionIDControlEnabledRevisionReceivedArguments?.control == .recording)
        #expect(controller.snapshot.sessions.first?.recording.isEnabled == false)
        #expect(controller.snapshot.sessions.first?.recording.revision == 8)
    }

    // MARK: - Owner optimism (the ONE bridge between REST and the document)

    /// An accepted write records the owner's optimism: the fact, keyed by
    /// the agent, with an expiry — what the presentation bridges.
    @Test
    func anAcceptedArtifactWriteRecordsATimeBoundedOwnerWrite() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 1))
        let controller = makeController(service: service)
        await controller.reload()
        service.setVoiceSwitchSessionIDControlEnabledRevisionReturnValue =
            .success(makeControls(recordingEnabled: true, recordingRevision: 2))

        _ = await controller.setSwitch(sessionID: "session-1", control: .recording, enabled: true)

        let writes = controller.snapshot.pendingOwnerWrites["@assistant-red:spiral.md"] ?? []
        #expect(writes.contains { $0.fact == .recording(true) })
        #expect(writes.allSatisfy { $0.isLive(at: Date()) })
        #expect(writes.allSatisfy { $0.expiresAt.map { $0.timeIntervalSinceNow <= NativeAgentCenterController.ownerWriteWindow } == true },
                "the answer opens the window")
    }

    /// The document caught up: the write is settled and the document rules
    /// from here. A reload in between neither extends nor drops it.
    @Test
    func theDocumentSettlesAMatchingOwnerWrite() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 1))
        let controller = makeController(service: service)
        await controller.reload()
        service.setVoiceSwitchSessionIDControlEnabledRevisionReturnValue =
            .success(makeControls(recordingEnabled: true, recordingRevision: 2))
        _ = await controller.setSwitch(sessionID: "session-1", control: .recording, enabled: true)

        await controller.reload()
        #expect(controller.snapshot.pendingOwnerWrites["@assistant-red:spiral.md"]?.isEmpty == false)

        var claims = NativeCallAgentClaims()
        claims.documents = ["@assistant-red:spiral.md": .make(recording: true)]
        controller.settleOwnerWrites(against: claims)

        #expect(controller.snapshot.pendingOwnerWrites["@assistant-red:spiral.md"] == nil)
    }

    /// A document that does not mention the fact yet leaves the write
    /// standing; the clock retires it regardless — an owner's optimism can
    /// never outlive the window.
    @Test
    func theSweepRetiresExpiredOwnerWrites() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 1))
        let controller = makeController(service: service)
        await controller.reload()
        service.setVoiceSwitchSessionIDControlEnabledRevisionReturnValue =
            .success(makeControls(recordingEnabled: true, recordingRevision: 2))
        _ = await controller.setSwitch(sessionID: "session-1", control: .recording, enabled: true)

        controller.settleOwnerWrites(against: NativeCallAgentClaims())
        #expect(controller.snapshot.pendingOwnerWrites["@assistant-red:spiral.md"]?.isEmpty == false)

        controller.sweepExpiredOwnerWrites(now: Date().addingTimeInterval(NativeAgentCenterController.ownerWriteWindow + 1))

        #expect(controller.snapshot.pendingOwnerWrites.isEmpty)
    }

    /// Remove records `leaving` so the presentation says so on the owner's
    /// device before either the document or the roster does.
    @Test
    func removeRecordsALeavingOwnerWrite() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 1))
        let controller = makeController(service: service)
        await controller.reload()
        service.endVoiceSessionSessionIDReturnValue = .success(())
        service.voiceSessionControlContextsRoomIDReturnValue = .success([makeContext(state: "ending")])

        _ = await controller.remove(sessionID: "session-1")

        #expect(controller.snapshot.pendingOwnerWrites["@assistant-red:spiral.md"]?.contains { $0.fact == .leaving } == true)
    }

    /// Only the fact the tap changed is bridged: a Summary toggle must not
    /// re-open the window for REST's recording flag (critic, 2026-09-03).
    @Test
    func aWriteBridgesOnlyTheFactItChanged() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: true, recordingRevision: 1))
        let controller = makeController(service: service)
        await controller.reload()
        service.setVoiceSwitchSessionIDControlEnabledRevisionReturnValue =
            .success(makeControls(recordingEnabled: true, recordingRevision: 1, summaryEnabled: true))

        _ = await controller.setSwitch(sessionID: "session-1", control: .summary, enabled: true)

        let facts = (controller.snapshot.pendingOwnerWrites["@assistant-red:spiral.md"] ?? []).map(\.fact)
        #expect(facts == [.summary(true)])
    }

    /// A document that still disagrees is indistinguishable from one that
    /// has not republished: the write stands for the window, no longer.
    @Test
    func aContradictingDocumentDoesNotSettleTheWriteTheClockDoes() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 1))
        let controller = makeController(service: service)
        await controller.reload()
        service.setVoiceSwitchSessionIDControlEnabledRevisionReturnValue =
            .success(makeControls(recordingEnabled: true, recordingRevision: 2))
        _ = await controller.setSwitch(sessionID: "session-1", control: .recording, enabled: true)

        var claims = NativeCallAgentClaims()
        claims.documents = ["@assistant-red:spiral.md": .make(recording: false)]
        controller.settleOwnerWrites(against: claims)
        #expect(controller.snapshot.pendingOwnerWrites["@assistant-red:spiral.md"]?.isEmpty == false)

        controller.sweepExpiredOwnerWrites(now: Date().addingTimeInterval(NativeAgentCenterController.ownerWriteWindow + 1))
        #expect(controller.snapshot.pendingOwnerWrites.isEmpty)
    }

    /// The document's `lifecycle: leaving` settles the owner's `.leaving`.
    @Test
    func theDocumentsLifecycleSettlesTheLeavingWrite() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 1))
        let controller = makeController(service: service)
        await controller.reload()
        service.endVoiceSessionSessionIDReturnValue = .success(())
        service.voiceSessionControlContextsRoomIDReturnValue = .success([makeContext(state: "ending")])
        _ = await controller.remove(sessionID: "session-1")
        #expect(controller.snapshot.pendingOwnerWrites["@assistant-red:spiral.md"]?.isEmpty == false)

        var claims = NativeCallAgentClaims()
        claims.documents = ["@assistant-red:spiral.md": .make(lifecycle: .leaving)]
        controller.settleOwnerWrites(against: claims)

        #expect(controller.snapshot.pendingOwnerWrites["@assistant-red:spiral.md"] == nil)
    }

    /// The sweep is armed for the EARLIEST expiry: a later write must not
    /// push it past an earlier one's window.
    @Test
    func theSweepStaysArmedForTheEarliestExpiry() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 1))
        let controller = makeController(service: service)
        await controller.reload()
        service.setVoiceSwitchSessionIDControlEnabledRevisionReturnValue =
            .success(makeControls(recordingEnabled: true, recordingRevision: 2))
        _ = await controller.setSwitch(sessionID: "session-1", control: .recording, enabled: true)
        let first = controller.nextOwnerWriteExpiry

        service.setVoiceSwitchSessionIDControlEnabledRevisionReturnValue =
            .success(makeControls(recordingEnabled: true, recordingRevision: 3, summaryEnabled: true))
        _ = await controller.setSwitch(sessionID: "session-1", control: .summary, enabled: true)

        #expect(controller.nextOwnerWriteExpiry == first)
        #expect(controller.snapshot.pendingOwnerWrites["@assistant-red:spiral.md"]?.count == 2)
    }

    /// The translation write is bridged in the DOCUMENT's currency — the intent's catalog codes, exactly as written —
    /// so it settles against what the reader reads back (ADR-0094 A.6).
    @Test
    func aTranslationWriteIsBridgedInTheIntentsExactCodes() async {
        let service = makeService(contexts: [makeContext()], controls: makeControls(recordingEnabled: false, recordingRevision: 0))
        let controller = makeController(service: service)
        await controller.reload()
        service.setVoiceTranslationSessionIDParamsRevisionReturnValue = .success(makeControls(recordingEnabled: false, recordingRevision: 0,
                                                                                              forLanguage: "pt-BR", overrideRevision: 1))

        _ = await controller.setTranslation(sessionID: "session-1", params: .forLanguage("pt-BR"))

        #expect(controller.snapshot.pendingOwnerWrites["@assistant-red:spiral.md"]?.map(\.fact) == [.translation(languages: ["pt-BR"])])
        var claims = NativeCallAgentClaims()
        claims.documents["@assistant-red:spiral.md"] = .make(translation: .producing("pt-BR", speakers: ["@bob:spiral.md"]))
        controller.settleOwnerWrites(against: claims)
        #expect(controller.snapshot.pendingOwnerWrites["@assistant-red:spiral.md"] == nil)
    }

    /// A transient re-read failure is not "no sessions": the last control
    /// register stays with the error card, and an entry point that was
    /// available does not vanish for one timeout.
    @Test
    func aTransientReloadFailureKeepsTheLastSessions() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 1))
        let controller = makeController(service: service)
        await controller.reload()
        #expect(controller.snapshot.sessions.count == 1)

        service.voiceSessionControlContextsRoomIDReturnValue = .failure(.unavailable("timeout"))
        await controller.reload()

        #expect(controller.snapshot.sessions.count == 1)
        #expect(controller.snapshot.isAvailable)
        #expect(controller.snapshot.availableLanguages.isEmpty == false)
        #expect(controller.snapshot.lastError == .unavailable("timeout"))
    }

    /// A conflict means our revision was stale, so the controller re-reads
    /// rather than reporting an optimistic success.
    @Test
    func aConflictSurfacesAndReloadsFreshTruth() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: true, recordingRevision: 2))
        let controller = makeController(service: service)
        await controller.reload()

        service.setVoiceSwitchSessionIDControlEnabledRevisionReturnValue = .failure(.conflict)
        service.voiceSessionControlsSessionIDReturnValue =
            .success(makeControls(recordingEnabled: true, recordingRevision: 9))

        let didSucceed = await controller.setSwitch(sessionID: "session-1", control: .recording, enabled: false)

        #expect(didSucceed == false)
        #expect(controller.snapshot.lastError == .conflict)
        #expect(controller.snapshot.sessions.first?.recording.revision == 9)
    }

    /// Someone else's agent stays visible but read-only; the write never
    /// reaches the backend.
    @Test
    func aSessionTheUserDoesNotOwnRefusesWritesLocally() async {
        let service = makeService(contexts: [makeContext(canControl: false)],
                                  controls: makeControls(recordingEnabled: true, recordingRevision: 1))
        let controller = makeController(service: service)
        await controller.reload()

        let didSucceed = await controller.setSwitch(sessionID: "session-1", control: .summary, enabled: false)

        #expect(didSucceed == false)
        #expect(service.setVoiceSwitchSessionIDControlEnabledRevisionCalled == false)
    }

    /// Removing a session that already ended is the outcome the caller wanted.
    @Test
    func removingAnAlreadyEndedSessionSucceeds() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 1))
        let controller = makeController(service: service)
        await controller.reload()

        service.endVoiceSessionSessionIDReturnValue = .failure(.gone)
        service.voiceSessionControlContextsRoomIDReturnValue = .success([])

        let didSucceed = await controller.remove(sessionID: "session-1")

        #expect(didSucceed)
        await controller.pendingReconcile?.value
        #expect(controller.snapshot.sessions.isEmpty)
    }

    /// The operator's stuck "Leaving…" (2026-09-03), reproduced as the race
    /// it was: the removal's reconcile reload and the departure doorbell's
    /// reload used to run in PARALLEL, and the earlier one — which had read
    /// the session mid-teardown as `ending` — wrote the snapshot LAST,
    /// after which nothing ever reloaded again. Reloads are serialized
    /// now with one queued follow-up: the read that follows the departure
    /// is guaranteed to be a read that follows it.
    @Test
    func aReloadRequestedMidFlightRunsAfterItAndWins() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 1))
        let controller = makeController(service: service)
        await controller.reload()

        // Sequence the backend: the FIRST contexts read still lists the
        // session (mid-teardown, `ending`); every later read says gone.
        let gate = Mutex<CheckedContinuation<Void, Never>?>(nil)
        let reads = Mutex(0)
        let endingContext = makeContext(state: "ending")
        service.voiceSessionControlContextsRoomIDClosure = { _ in
            let index = reads.withLock { value in value += 1; return value }
            if index == 1 {
                await withCheckedContinuation { continuation in
                    gate.withLock { $0 = continuation }
                }
                return .success([endingContext])
            }
            return .success([])
        }

        // Reload #1 starts and BLOCKS inside the backend on the first read.
        let first = Task { await controller.reload() }
        while gate.withLock({ $0 == nil }) {
            await Task.yield()
        }
        // The departure doorbell rings while #1 is in flight.
        let second = Task { await controller.reload() }
        await Task.yield()
        gate.withLock { $0?.resume() }
        await first.value
        await second.value

        // The follow-up read (gone) is the one that stands.
        #expect(controller.snapshot.sessions.isEmpty)
        #expect(reads.withLock { $0 } >= 2, "the queued reload must actually run")
    }

    /// The tap must land on screen WITHOUT waiting for the reconcile: a
    /// removal used to run a full reload (several sequential round-trips)
    /// before anything changed, so the row repainted identically and the
    /// owner pressed it again. `remove` now returns with the session already
    /// marked leaving.
    @Test
    func removingMarksTheSessionLeavingBeforeAnyReload() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 1))
        let controller = makeController(service: service)
        await controller.reload()
        let reloadsBefore = service.voiceSessionControlContextsRoomIDCallsCount

        service.endVoiceSessionSessionIDReturnValue = .success(())
        // The backend still reports the row while it tears down — exactly the
        // state that used to render "Ready" with an armed Remove button.
        service.voiceSessionControlContextsRoomIDReturnValue = .success([makeContext(state: "ending")])

        let didSucceed = await controller.remove(sessionID: "session-1")

        #expect(didSucceed)
        #expect(controller.snapshot.sessions.first?.isEnding == true,
                "the row must say it is leaving the moment the delete returns")
        #expect(service.voiceSessionControlContextsRoomIDCallsCount == reloadsBefore,
                "no reload may block the interaction path")

        // And the off-path reconcile still runs — the backstop for an agent
        // that never reaches the media plane and so never rings the doorbell.
        await controller.pendingReconcile?.value
        #expect(service.voiceSessionControlContextsRoomIDCallsCount > reloadsBefore)
        #expect(controller.snapshot.sessions.first?.isEnding == true,
                "server truth agrees: still ending")
    }

    /// Walk F6: after "Remove from call" the session stays `ending` for a
    /// moment. The re-read after the removal saw it, and nothing read again
    /// until the agent left the ROOM ~33 s later, so it could not be added
    /// back. An `ending` read now re-reads on its own until the session is
    /// gone, and the agent is offered again straight away.
    @Test
    func aRemovedSessionStillEndingIsReReadUntilTheAgentCanBeAddedAgain() async throws {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 1))
        let controller = makeController(service: service, endingRecheckInterval: .milliseconds(10))
        await controller.reload()
        #expect(controller.snapshot.candidates.map(\.id) == ["agent-1"])

        // The teardown converges after two more reads.
        let reads = Mutex(0)
        let endingContext = makeContext(state: "ending")
        service.voiceSessionControlContextsRoomIDClosure = { _ in
            let index = reads.withLock { value in value += 1; return value }
            return .success(index <= 2 ? [endingContext] : [])
        }
        service.endVoiceSessionSessionIDReturnValue = .success(())

        #expect(await controller.remove(sessionID: "session-1"))
        await controller.pendingReconcile?.value
        #expect(controller.snapshot.sessions.first?.isEnding == true, "the first re-read still sees the teardown")

        for _ in 0..<200 where !controller.snapshot.sessions.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.snapshot.sessions.isEmpty)
        #expect(reads.withLock { $0 } == 3, "re-read until gone, then stopped")
        // Nobody holds the agent any more: it is offered again.
        #expect(!controller.snapshot.attachedAgentMxids.contains("@assistant-red:spiral.md"))
        #expect(controller.snapshot.candidates.map(\.id) == ["agent-1"])
        #expect(controller.pendingEndingRecheck == nil)
    }

    /// Fable review: one failed read inside the teardown window ended the
    /// re-reads, leaving "Removing…" until the next doorbell. A failure keeps
    /// them going while the last known session is still ending.
    @Test
    func aFailedReadWhileASessionIsEndingKeepsReReading() async throws {
        let service = makeService(contexts: [makeContext(state: "ending")],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 1))
        let reads = Mutex(0)
        let endingContext = makeContext(state: "ending")
        service.voiceSessionControlContextsRoomIDClosure = { _ in
            let index = reads.withLock { value in value += 1; return value }
            switch index {
            case 1: return .success([endingContext])
            case 2: return .failure(.unavailable("offline"))
            default: return .success([])
            }
        }
        let controller = makeController(service: service, endingRecheckInterval: .milliseconds(10))
        await controller.reload()
        #expect(controller.snapshot.sessions.first?.isEnding == true)

        for _ in 0..<200 where !controller.snapshot.sessions.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.snapshot.sessions.isEmpty, "the read after the failure saw the session gone")
        #expect(reads.withLock { $0 } == 3)
        #expect(controller.snapshot.candidates.map(\.id) == ["agent-1"])
    }

    /// A session the backend reports as `ending` is inert — the sheet must be
    /// able to SEE that, or it offers actions that cannot land.
    @Test
    func endingStateIsCarriedFromTheBackend() async {
        let service = makeService(contexts: [makeContext(state: "ending")],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 1))
        let controller = makeController(service: service)

        await controller.reload()

        #expect(controller.snapshot.sessions.first?.isEnding == true)
    }

    /// Only the invite-required rejection is retried; a plain policy refusal
    /// must not silently invite an agent into the room.
    @Test
    func anInviteOnlyRoomInvitesThenRetriesTheAttach() async {
        let service = makeService(contexts: [], controls: nil)
        let inviteRecorder = InviteRecorder()
        let controller = makeController(service: service, members: []) { mxid in
            inviteRecorder.record(mxid)
            return true
        }
        await controller.reload()

        let attachCounter = AttachCounter()
        service.attachVoiceAgentAgentIDRoomIDParamsClosure = { _, _, _ in
            attachCounter.increment()
            return attachCounter.count == 1
                ? .failure(.inviteRequired("agent could not auto-join the room (M_FORBIDDEN); please invite the agent manually first"))
                : .success("session-9")
        }

        let didSucceed = await controller.attach(agentID: "agent-1", params: makeAttachParams())

        #expect(didSucceed)
        #expect(attachCounter.count == 2)
        #expect(inviteRecorder.mxids == ["@assistant-red:spiral.md"])
    }

    /// The backend lets the assistant go again when the attach that joined it is refused, a retryable 503 included, so
    /// the automatic retry after the 503 meets an invite-required refusal. The app invites it once more, silently,
    /// as the tap's own invite does (operator, 2026-11-23).
    @Test
    func theRetryAfterAServiceUnavailableReinvitesOnce() async {
        let service = makeService(contexts: [], controls: nil)
        let inviteRecorder = InviteRecorder()
        let controller = makeController(service: service) { mxid in
            inviteRecorder.record(mxid)
            return true
        }
        await controller.reload()

        let attachCounter = AttachCounter()
        service.attachVoiceAgentAgentIDRoomIDParamsClosure = { _, _, _ in
            attachCounter.increment()
            switch attachCounter.count {
            case 1: return .failure(.serviceUnavailable(retryAfter: .zero))
            case 2: return .failure(.inviteRequired("invite it first"))
            default: return .success("session-9")
            }
        }

        let didSucceed = await controller.attach(agentID: "agent-1", params: makeAttachParams())

        #expect(didSucceed)
        #expect(attachCounter.count == 3)
        #expect(inviteRecorder.mxids == ["@assistant-red:spiral.md"])
        #expect(controller.snapshot.joinFailures["agent-1"] == nil)
    }

    /// No loop: one re-invite per tap. When the attach after it still needs an invite, the add row asks to join as
    /// before, and the tap's own invite (the agent is not a member here) does not run on top of it.
    @Test
    func aSecondInviteRequiredAfterTheReinviteIsTheAnswer() async {
        let service = makeService(contexts: [], controls: nil)
        let inviteRecorder = InviteRecorder()
        let controller = makeController(service: service, members: []) { mxid in
            inviteRecorder.record(mxid)
            return true
        }
        await controller.reload()

        let attachCounter = AttachCounter()
        service.attachVoiceAgentAgentIDRoomIDParamsClosure = { _, _, _ in
            attachCounter.increment()
            return attachCounter.count == 1
                ? .failure(.serviceUnavailable(retryAfter: .zero))
                : .failure(.inviteRequired("invite it first"))
        }

        let didSucceed = await controller.attach(agentID: "agent-1", params: makeAttachParams())

        #expect(didSucceed == false)
        #expect(attachCounter.count == 3)
        #expect(inviteRecorder.mxids == ["@assistant-red:spiral.md"])
        #expect(controller.snapshot.joinFailures["agent-1"] == .askToJoin)
    }

    /// The whole path on the phone: the tap invites the assistant, the attach that joined it gets a 503 and the
    /// backend lets it go, so the retry re-invites once and the third attach lands.
    @Test
    func theTapsInviteAndTheRetrysReinviteBothRun() async {
        let service = makeService(contexts: [], controls: nil)
        let inviteRecorder = InviteRecorder()
        let controller = makeController(service: service, members: []) { mxid in
            inviteRecorder.record(mxid)
            return true
        }
        await controller.reload()

        let attachCounter = AttachCounter()
        service.attachVoiceAgentAgentIDRoomIDParamsClosure = { _, _, _ in
            attachCounter.increment()
            switch attachCounter.count {
            case 1, 3: return .failure(.inviteRequired("invite it first"))
            case 2: return .failure(.serviceUnavailable(retryAfter: .zero))
            default: return .success("session-9")
            }
        }

        let didSucceed = await controller.attach(agentID: "agent-1", params: makeAttachParams())

        #expect(didSucceed)
        #expect(attachCounter.count == 4)
        #expect(inviteRecorder.mxids == ["@assistant-red:spiral.md", "@assistant-red:spiral.md"])
    }

    /// The person hangs up while the add waits out a 503: the retry sends nothing, so the assistant is neither
    /// attached to nor invited into the call they left.
    @Test
    func theCallEndingDuringTheWaitSendsNothingMore() async throws {
        let service = makeService(contexts: [], controls: nil)
        let inviteRecorder = InviteRecorder()
        let controller = makeController(service: service, members: []) { mxid in
            inviteRecorder.record(mxid)
            return true
        }
        await controller.reload()

        let attachCounter = AttachCounter()
        service.attachVoiceAgentAgentIDRoomIDParamsClosure = { _, _, _ in
            attachCounter.increment()
            return attachCounter.count == 1
                ? .failure(.serviceUnavailable(retryAfter: .milliseconds(300)))
                : .failure(.inviteRequired("invite it first"))
        }

        let tap = Task { await controller.attach(agentID: "agent-1", params: makeAttachParams()) }
        while attachCounter.count == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        controller.stop()

        #expect(await tap.value == false)
        #expect(attachCounter.count == 1)
        #expect(inviteRecorder.mxids.isEmpty)
        #expect(controller.snapshot.joinFailures["agent-1"] == nil)
        #expect(await controller.attach(agentID: "agent-1", params: makeAttachParams()) == false)
        #expect(attachCounter.count == 1, "a stopped agent center sends no new attach either")
    }

    /// The re-invite refused (an ask-to-join room, D8): the add row asks to join, with no third attach and no second
    /// invite from the tap's own path.
    @Test
    func aRefusedReinviteIsAnAskToJoinRoom() async {
        let service = makeService(contexts: [], controls: nil)
        let inviteRecorder = InviteRecorder()
        let controller = makeController(service: service, members: []) { mxid in
            inviteRecorder.record(mxid)
            return false
        }
        await controller.reload()

        let attachCounter = AttachCounter()
        service.attachVoiceAgentAgentIDRoomIDParamsClosure = { _, _, _ in
            attachCounter.increment()
            return attachCounter.count == 1
                ? .failure(.serviceUnavailable(retryAfter: .milliseconds(20)))
                : .failure(.inviteRequired("invite it first"))
        }

        #expect(await controller.attach(agentID: "agent-1", params: makeAttachParams()) == false)

        #expect(attachCounter.count == 2)
        #expect(inviteRecorder.mxids == ["@assistant-red:spiral.md"])
        #expect(controller.snapshot.joinFailures["agent-1"] == .askToJoin)
    }

    /// The room still lists the assistant (its leave after a refused attach hasn't synced), but the backend says it
    /// needs an invite: the backend's word decides, and the tap invites it.
    @Test
    func aStaleMemberIsInvitedOnTheBackendsWord() async {
        let service = makeService(contexts: [], controls: nil)
        let inviteRecorder = InviteRecorder()
        let controller = makeController(service: service) { mxid in
            inviteRecorder.record(mxid)
            return true
        }
        await controller.reload()

        let attachCounter = AttachCounter()
        service.attachVoiceAgentAgentIDRoomIDParamsClosure = { _, _, _ in
            attachCounter.increment()
            return attachCounter.count == 1 ? .failure(.inviteRequired("invite it first")) : .success("session-9")
        }

        #expect(await controller.attach(agentID: "agent-1", params: makeAttachParams()))

        #expect(attachCounter.count == 2)
        #expect(inviteRecorder.mxids == ["@assistant-red:spiral.md"])
    }

    /// That invite is the tap's one re-invite: a 503 retry after it that needs an invite again is the answer.
    @Test
    func aStaleMembersInviteIsTheTapsOneReinvite() async {
        let service = makeService(contexts: [], controls: nil)
        let inviteRecorder = InviteRecorder()
        let controller = makeController(service: service) { mxid in
            inviteRecorder.record(mxid)
            return true
        }
        await controller.reload()

        let attachCounter = AttachCounter()
        service.attachVoiceAgentAgentIDRoomIDParamsClosure = { _, _, _ in
            attachCounter.increment()
            return attachCounter.count == 2
                ? .failure(.serviceUnavailable(retryAfter: .zero))
                : .failure(.inviteRequired("invite it first"))
        }

        #expect(await controller.attach(agentID: "agent-1", params: makeAttachParams()) == false)

        #expect(attachCounter.count == 3)
        #expect(inviteRecorder.mxids == ["@assistant-red:spiral.md"])
        #expect(controller.snapshot.joinFailures["agent-1"] == .askToJoin)
    }

    @Test
    func aPolicyRejectionIsNotRetriedWithAnInvite() async {
        let service = makeService(contexts: [], controls: nil)
        let inviteRecorder = InviteRecorder()
        let controller = makeController(service: service, members: []) { mxid in
            inviteRecorder.record(mxid)
            return true
        }
        await controller.reload()

        service.attachVoiceAgentAgentIDRoomIDParamsReturnValue = .failure(.rejected("voice disabled for this agent"))

        let didSucceed = await controller.attach(agentID: "agent-1", params: makeAttachParams())

        #expect(didSucceed == false)
        #expect(inviteRecorder.mxids.isEmpty)
        // Question 387 (F3): the refusal lands on the agent's own add row.
        #expect(controller.snapshot.joinFailures["agent-1"] == .failed)
    }

    /// Inviting a bot into a private room must depend on the backend's `type`
    /// URI, never on its prose. This refusal mentions both "invite" and "join"
    /// — the two words the old substring probe keyed on — and still must not
    /// produce an invite, because its type says it is an ordinary policy
    /// refusal that an invite would not fix.
    @Test
    func aPolicyRefusalThatMentionsInviteAndJoinDoesNotInviteAnyone() async {
        let service = makeService(contexts: [], controls: nil)
        let inviteRecorder = InviteRecorder()
        let controller = makeController(service: service, members: []) { mxid in
            inviteRecorder.record(mxid)
            return true
        }
        await controller.reload()

        let attachCounter = AttachCounter()
        service.attachVoiceAgentAgentIDRoomIDParamsClosure = { _, _, _ in
            attachCounter.increment()
            return .failure(.rejected("this agent may not join calls; ask an admin to invite it to the space instead"))
        }

        let didSucceed = await controller.attach(agentID: "agent-1", params: makeAttachParams())

        #expect(didSucceed == false)
        #expect(inviteRecorder.mxids.isEmpty, "prose must not decide who gets invited")
        #expect(attachCounter.count == 1, "a policy refusal is not retried")
    }

    /// Delivery state is reported as the backend sees it, including where a
    /// delivered artifact landed.
    @Test
    func deliveryStateIsCarriedThroughVerbatim() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: true,
                                                         recordingRevision: 1,
                                                         recordingDelivery: "delivered",
                                                         recordingDeliveryTarget: "owner_dm",
                                                         summaryDelivery: "failed"))
        let controller = makeController(service: service)

        await controller.reload()

        #expect(controller.snapshot.sessions.first?.recording.delivery == .delivered(target: "owner_dm"))
        #expect(controller.snapshot.sessions.first?.summary.delivery == .failed)
    }

    // MARK: - One recording per call (question 404)

    /// A start refused because someone else's assistant records is the cover the call screen shows, not a red retry,
    /// and the tap's optimism is withdrawn.
    @Test
    func aCoveredRecordingStartIsTheCoverNotAnError() async {
        let service = makeService(contexts: [makeContext()], controls: makeControls(recordingEnabled: false, recordingRevision: 1))
        let controller = makeController(service: service)
        await controller.reload()
        let cover = VoiceRecordingCover(agentMxid: "@assistant-mira:spiral.md", ownerMxid: "@mira:spiral.md")
        service.setVoiceSwitchSessionIDControlEnabledRevisionReturnValue = .failure(.recordingCovered(cover))

        #expect(await controller.setSwitch(sessionID: "session-1", control: .recording, enabled: true) == false)

        #expect(controller.snapshot.recordingRefusal?.cover == cover)
        #expect(controller.snapshot.lastError == nil)
        #expect((controller.snapshot.pendingOwnerWrites["@assistant-red:spiral.md"] ?? []).contains { $0.fact == .recording(true) } == false)
        await controller.reload()
        #expect(controller.snapshot.recordingRefusal?.cover == cover, "a re-read keeps it")
    }

    /// The same on an add for recording: the agent didn't come, and its add row says nothing went wrong.
    @Test
    func aCoveredRecordingAttachIsNoJoinFailure() async {
        let service = makeService(contexts: [], controls: nil)
        let cover = VoiceRecordingCover(agentMxid: "@assistant-mira:spiral.md", ownerMxid: nil)
        service.attachVoiceAgentAgentIDRoomIDParamsReturnValue = .failure(.recordingCovered(cover))
        let controller = makeController(service: service)
        await controller.reload()

        #expect(await controller.attach(agentID: "agent-1", params: makeAttachParams()) == false)

        #expect(controller.snapshot.joinFailures["agent-1"] == nil)
        #expect(controller.snapshot.recordingRefusal?.cover == cover)
    }

    // MARK: - Helpers

    @MainActor
    private final class InviteRecorder {
        private(set) var mxids: [String] = []

        func record(_ mxid: String) {
            mxids.append(mxid)
        }
    }

    @MainActor
    private final class AttachCounter {
        private(set) var count = 0

        func increment() {
            count += 1
        }
    }

    private func makeController(service: AgentPlatformServiceProtocol?,
                                members: Set<String> = ["@assistant-red:spiral.md"],
                                endingRecheckInterval: Duration = .seconds(1),
                                port: TranslationPortStub = TranslationPortStub(),
                                inviteAgent: @escaping @MainActor (String) async -> Bool = { _ in true }) -> NativeAgentCenterController {
        NativeAgentCenterController(agentPlatformService: service,
                                    roomID: "!room:spiral.md",
                                    roomMemberMxids: { members },
                                    inviteAgent: inviteAgent,
                                    translationPort: port,
                                    endingRecheckInterval: endingRecheckInterval,
                                    joinPollInterval: .milliseconds(1))
    }

    /// A.3: what the owner reads is the intent, the lanes it holds and whether it stands by, with the override's CAS
    /// token.
    @Test
    func translationStateIsReadFromTheEffectiveIntent() async {
        let controls = makeControls(recordingEnabled: false,
                                    recordingRevision: 0,
                                    forLanguage: "uk",
                                    lanes: [.init(speaker: "@bob:spiral.md", language: "uk")],
                                    overrideRevision: 7)
        let service = makeService(contexts: [makeContext()], controls: controls)
        let controller = makeController(service: service)
        await controller.reload()

        let translation = controller.snapshot.sessions.first?.translation
        #expect(translation?.isOn == true)
        #expect(translation?.languages == ["uk"])
        #expect(translation?.effective.lanes == [.init(speaker: "@bob:spiral.md", language: "uk")])
        #expect(translation?.isStandby == false)
        #expect(translation?.style == "simultaneous")
        #expect(translation?.source == "override")
        #expect(translation?.revision == 7)
    }

    /// Rows 7–8: the write is the intent alone, with the snapshot's revision.
    @Test(arguments: [VoiceTranslationParams.forLanguage("zh-Hans"), .pocket("uk", "en")])
    func settingTranslationWritesTheIntentWithTheSnapshotRevision(params: VoiceTranslationParams) async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 0, overrideRevision: 3))
        let controller = makeController(service: service)
        await controller.reload()

        service.setVoiceTranslationSessionIDParamsRevisionReturnValue =
            .success(makeControls(recordingEnabled: false, recordingRevision: 0, forLanguage: "zh-Hans", overrideRevision: 4))
        let ok = await controller.setTranslation(sessionID: "session-1", params: params)

        #expect(ok)
        let call = service.setVoiceTranslationSessionIDParamsRevisionReceivedArguments
        #expect(call?.revision == 3)
        #expect(call?.params == params)
    }

    /// Row 12: a pause or limit refusal says why on the call screen and on the translation row; nothing changed.
    @Test(arguments: [(VoiceTranslationRefusal(reason: .translationPaused, pauseUntil: Date(timeIntervalSince1970: 1_794_787_200)),
                       NativeAgentCenterLimitStop.categoryPaused(.callTranslation, until: Date(timeIntervalSince1970: 1_794_787_200))),
                      (.init(reason: .aiLimit, pauseUntil: nil), .limitReached(isWeekly: false)),
                      (.init(reason: .callCap, pauseUntil: nil), .categoryPaused(.callTranslation, until: nil))])
    func aPausedRefusalSaysWhyAndChangesNothing(refusal: VoiceTranslationRefusal, stop: NativeAgentCenterLimitStop) async {
        let service = makeService(contexts: [makeContext()], controls: makeControls(recordingEnabled: false, recordingRevision: 0))
        let controller = makeController(service: service)
        await controller.reload()
        service.setVoiceTranslationSessionIDParamsRevisionReturnValue = .failure(.translationPaused(refusal))

        let ok = await controller.setTranslation(sessionID: "session-1", params: .forLanguage("uk"))

        #expect(!ok)
        #expect(controller.snapshot.limitStop == stop)
        #expect(controller.snapshot.lastError == .translationPaused(refusal))
        #expect(controller.snapshot.lastErrorScope == .session("session-1", .translation))
        #expect(controller.snapshot.sessions.first?.translation.isOn == false)
    }

    /// Row 12: the form refused for the room is the app's own mistake: quiet, no card.
    @Test
    func anUnavailableIntentIsRefusedQuietly() async {
        let service = makeService(contexts: [makeContext()], controls: makeControls(recordingEnabled: false, recordingRevision: 0))
        let controller = makeController(service: service)
        await controller.reload()
        service.setVoiceTranslationSessionIDParamsRevisionReturnValue = .failure(.intentUnavailable(roomKind: "owner_dm"))

        let ok = await controller.setTranslation(sessionID: "session-1", params: .forLanguage("uk"))

        #expect(!ok)
        #expect(controller.snapshot.lastError == nil)
    }

    // MARK: - ADR-0094 A.8: the catalog before the first attach

    /// The language lists have the catalog with no session and no agent: it is read through the port.
    @Test
    func theLanguagesAreThereBeforeTheFirstAttach() async {
        let service = makeService(contexts: [], controls: nil)
        let controller = makeController(service: service)

        await controller.reload()

        #expect(controller.snapshot.availableLanguages.map(\.code) == ["en", "uk", "zh-Hans"])
    }

    /// A failed catalog read is not "no languages": the known ones stay.
    @Test
    func aFailedCatalogReadKeepsTheKnownLanguages() async {
        let service = makeService(contexts: [], controls: nil)
        let port = TranslationPortStub()
        let controller = makeController(service: service, port: port)
        await controller.reload()

        port.catalog = nil
        await controller.reload()

        #expect(controller.snapshot.availableLanguages.map(\.code) == ["en", "uk", "zh-Hans"])
    }

    /// Row 3: the memberships' languages reach the snapshot without a platform read, and a failed read keeps them.
    @Test
    func theParticipantsLanguagesComeFromTheMemberships() async {
        let port = TranslationPortStub()
        port.membershipLanguages = ["@bob:spiral.md": "pt-BR"]
        let controller = makeController(service: makeService(contexts: [], controls: nil), port: port)

        await controller.refreshParticipantLanguages()
        #expect(controller.snapshot.translationFacts.languages == ["@bob:spiral.md": "pt-BR"])

        port.membershipLanguages = nil
        await controller.refreshParticipantLanguages()
        #expect(controller.snapshot.translationFacts.languages == ["@bob:spiral.md": "pt-BR"])
    }

    private func makeService(contexts: [VoiceSessionControlContext],
                             controls: VoiceControlsState?) -> AgentPlatformServiceMock {
        let service = AgentPlatformServiceMock()
        service.voiceSessionControlContextsRoomIDReturnValue = .success(contexts)
        if let controls {
            service.voiceSessionControlsSessionIDReturnValue = .success(controls)
        }
        service.listMyPersonalAgentsReturnValue = .success(.init(agents: [.init(id: "agent-1",
                                                                                matrixUserID: "@assistant-red:spiral.md",
                                                                                displayName: "Red's Assistant",
                                                                                avatarMXC: nil,
                                                                                visibility: "private",
                                                                                lifecycleState: "active")],
                                                                 provisioningStatus: .ready))
        service.voiceSessionProgressSessionIDReturnValue = .success(.active)
        return service
    }

    private func makeContext(sessionID: String = "session-1",
                             canControl: Bool = true,
                             state: String = "active") -> VoiceSessionControlContext {
        VoiceSessionControlContext(sessionID: sessionID,
                                   agentMxid: "@assistant-red:spiral.md",
                                   canControl: canControl,
                                   state: state)
    }

    private func makeControls(recordingEnabled: Bool,
                              recordingRevision: Int32,
                              recordingDelivery: String? = nil,
                              recordingDeliveryTarget: String? = nil,
                              summaryDelivery: String? = nil,
                              summaryEnabled: Bool = true,
                              forLanguage: String? = nil,
                              lanes: [VoiceTranslationLane] = [],
                              overrideRevision: Int32? = nil,
                              conversation: VoiceConversationState = .init(active: false, available: false, revision: 0)) -> VoiceControlsState {
        VoiceControlsState(sessionID: "session-1",
                           effective: .init(source: forLanguage == nil ? "off" : "override",
                                            style: forLanguage == nil ? nil : "simultaneous",
                                            forLanguage: forLanguage,
                                            lanes: lanes),
                           override: overrideRevision.map { .init(state: "enabled", revision: $0) },
                           artifacts: .init(recording: .init(enabled: recordingEnabled,
                                                             revision: recordingRevision,
                                                             delivery: recordingDelivery,
                                                             deliveryTarget: recordingDeliveryTarget,
                                                             stopped: false),
                                            summary: .init(enabled: summaryEnabled,
                                                           revision: 1,
                                                           delivery: summaryDelivery,
                                                           deliveryTarget: nil,
                                                           stopped: false)),
                           conversation: conversation)
    }

    private func makeAttachParams() -> VoiceAttachParams {
        VoiceAttachParams(translation: nil, recording: false, summary: true, conversation: false)
    }
}

// MARK: - Brief 0080: the conversation switch

extension NativeAgentCenterControllerTests {
    private static let agentMxid = "@assistant-red:spiral.md"

    /// The write carries the conversation's OWN CAS token and bridges only
    /// the conversation; the document then settles it.
    @Test
    func aConversationWriteCarriesItsRevisionAndSettlesAgainstTheDocument() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: true,
                                                         recordingRevision: 4,
                                                         conversation: .init(active: false, available: true, revision: 6)))
        let controller = makeController(service: service)
        await controller.reload()
        #expect(controller.snapshot.sessions.first?.conversation == .init(isAvailable: true, revision: 6))

        service.setVoiceSwitchSessionIDControlEnabledRevisionReturnValue =
            .success(makeControls(recordingEnabled: true,
                                  recordingRevision: 4,
                                  conversation: .init(active: true, available: true, revision: 7)))
        let didSucceed = await controller.setSwitch(sessionID: "session-1", control: .conversation, enabled: true)

        #expect(didSucceed)
        let call = service.setVoiceSwitchSessionIDControlEnabledRevisionReceivedArguments
        #expect(call?.control == .conversation)
        #expect(call?.enabled == true)
        #expect(call?.revision == 6)
        #expect(controller.snapshot.sessions.first?.conversation.revision == 7)
        #expect(controller.snapshot.pendingOwnerWrites[Self.agentMxid]?.map(\.fact) == [.conversation(true)])
        #expect(controller.snapshot.lastError == nil)

        var claims = NativeCallAgentClaims()
        claims.documents = [Self.agentMxid: .make(recording: true)]
        controller.settleOwnerWrites(against: claims)
        #expect(controller.snapshot.pendingOwnerWrites[Self.agentMxid]?.isEmpty == false, "a silent document has not caught up yet")

        claims.documents = [Self.agentMxid: .make(recording: true, conversation: true)]
        controller.settleOwnerWrites(against: claims)
        #expect(controller.snapshot.pendingOwnerWrites[Self.agentMxid] == nil)
    }

    /// 422 on a start: nothing stays bridged — the switch falls back to the
    /// document's silence — the controls are re-read, and the owner reads
    /// that the assistant stays silent AND why. The 422 covers a failed
    /// Realtime spawn, a policy denial, a budget refusal and the
    /// interpreter, and only the backend's detail tells them apart.
    @Test
    func aRefusedConversationStartRollsBackAndSaysTheAssistantStaysSilentAndWhy() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: true,
                                                         recordingRevision: 4,
                                                         conversation: .init(active: false, available: true, revision: 6)))
        let controller = makeController(service: service)
        await controller.reload()
        let readsBefore = service.voiceSessionControlsSessionIDCallsCount

        let detail = "conversation could not start: realtime spawn failed"
        service.setVoiceSwitchSessionIDControlEnabledRevisionReturnValue = .failure(.rejected(detail))
        let didSucceed = await controller.setSwitch(sessionID: "session-1", control: .conversation, enabled: true)

        #expect(didSucceed == false)
        #expect(controller.snapshot.lastError == .conversationRefused(detail))
        #expect(controller.snapshot.lastError?.localizedDescription
            == "\(UntranslatedL10n.screenNativeCallAgentCenterErrorConversationRefused)\n\(detail)")
        #expect(controller.snapshot.pendingOwnerWrites.isEmpty, "a refused start must never show as talking")
        #expect(service.voiceSessionControlsSessionIDCallsCount > readsBefore, "the refusal re-reads backend truth")

        let agent = presentedAgent(controller, document: .make(recording: true))
        #expect(agent?.shown.isConversationActive == false)
        #expect(agent?.control?.conversation.isAvailable == true, "the switch stays offered for another try")
    }

    /// A refusal with no detail still says the outcome — never a bare newline.
    @Test
    func aConversationRefusalWithoutADetailStillSaysTheOutcome() {
        #expect(NativeAgentCenterError.conversationRefused(" ").localizedDescription
            == UntranslatedL10n.screenNativeCallAgentCenterErrorConversationRefused)
    }

    /// Turning a switch ON reads from the tap, not from the answer: a call
    /// that started silent answers the conversation write only once its
    /// conversation runs — seconds — and the toggle used to snap back OFF
    /// for all of them. Same for all three switches. While the write is out
    /// the clock cannot retire it, and a second tap sends nothing.
    @Test(arguments: [VoiceSessionSwitch.conversation, .recording, .summary])
    func anOnTapShowsWhileItsWriteIsOut(_ control: VoiceSessionSwitch) async throws {
        let service = makeService(contexts: [makeContext()], controls: makeSilentControls())
        let controller = makeController(service: service)
        await controller.reload()
        let held = HeldSwitchWrite()
        service.setVoiceSwitchSessionIDControlEnabledRevisionClosure = { _, _, _, _ in await held.hold() }

        let tap = Task { await controller.setSwitch(sessionID: "session-1", control: control, enabled: true) }
        await held.untilHeld()

        #expect(Self.isOn(control, presentedAgent(controller)?.shown) == true, "the request shows before the write answers")
        #expect(controller.snapshot.pendingOwnerWrites[Self.agentMxid] == [.init(fact: Self.fact(control, true), expiresAt: nil)])
        controller.sweepExpiredOwnerWrites(now: .distantFuture)
        #expect(Self.isOn(control, presentedAgent(controller)?.shown) == true, "no clock runs on an unanswered write")

        let secondTap = await controller.setSwitch(sessionID: "session-1", control: control, enabled: false)
        #expect(!secondTap)
        #expect(service.setVoiceSwitchSessionIDControlEnabledRevisionCallsCount == 1, "a double tap sends one write")
        #expect(Self.isOn(control, presentedAgent(controller)?.shown) == true)

        held.answer(.success(makeSilentControls(turningOn: control)))
        let didSucceed = await tap.value

        #expect(didSucceed)
        let write = try #require(controller.snapshot.pendingOwnerWrites[Self.agentMxid]?.first)
        #expect(write.fact == Self.fact(control, true))
        #expect(write.expiresAt != nil, "the answer opens the window")
        #expect(Self.isOn(control, presentedAgent(controller)?.shown) == true)
    }

    /// Refused — 422 or 409 — the tap rolls back the moment the answer
    /// lands: the switch reads the document's silence again and nothing
    /// stays bridged.
    @Test(arguments: [VoiceControlsError.rejected("the realtime conversation did not connect"), .conflict])
    func aRefusedConversationTapRollsTheSwitchBack(_ refusal: VoiceControlsError) async {
        let service = makeService(contexts: [makeContext()], controls: makeSilentControls())
        let controller = makeController(service: service)
        await controller.reload()
        let held = HeldSwitchWrite()
        service.setVoiceSwitchSessionIDControlEnabledRevisionClosure = { _, _, _, _ in await held.hold() }

        let tap = Task { await controller.setSwitch(sessionID: "session-1", control: .conversation, enabled: true) }
        await held.untilHeld()
        #expect(presentedAgent(controller)?.shown.isConversationActive == true)

        held.answer(.failure(refusal))
        let didSucceed = await tap.value

        #expect(!didSucceed)
        #expect(presentedAgent(controller)?.shown.isConversationActive == false)
        #expect(controller.snapshot.pendingOwnerWrites.isEmpty)
        #expect(controller.snapshot.lastError != nil)
    }

    /// Turning a switch OFF never shows OFF before it is true — the
    /// microphone button's rule: a Stop that hid REC while the recorder
    /// still captured would be a privacy defect. The confirmed ON stands
    /// while the write is out; the server's answer then bridges OFF.
    @Test(arguments: [VoiceSessionSwitch.recording, .summary, .conversation])
    func anOffTapShowsTheConfirmedStateUntilTheWriteAnswers(_ control: VoiceSessionSwitch) async {
        let service = makeService(contexts: [makeContext()], controls: makeSilentControls(turningOn: control))
        let controller = makeController(service: service)
        await controller.reload()
        let document = Self.document(showing: control)
        let held = HeldSwitchWrite()
        service.setVoiceSwitchSessionIDControlEnabledRevisionClosure = { _, _, _, _ in await held.hold() }

        let tap = Task { await controller.setSwitch(sessionID: "session-1", control: control, enabled: false) }
        await held.untilHeld()

        #expect(Self.isOn(control, presentedAgent(controller, document: document)?.shown) == true, "still on until the server agrees")
        #expect(controller.snapshot.pendingOwnerWrites[Self.agentMxid] == nil)

        held.answer(.success(makeSilentControls()))
        let didSucceed = await tap.value

        #expect(didSucceed)
        #expect(Self.isOn(control, presentedAgent(controller, document: document)?.shown) == false, "the answer bridges OFF")
    }

    /// The rollback restores what the ON tap superseded: a refused Record
    /// leaves the Stop the server accepted a moment ago in charge, rather
    /// than handing the switch to a document that has not caught up.
    @Test
    func aRefusedTapPutsBackTheWriteItSuperseded() async {
        let service = makeService(contexts: [makeContext()], controls: makeSilentControls(turningOn: .recording))
        let controller = makeController(service: service)
        await controller.reload()
        service.setVoiceSwitchSessionIDControlEnabledRevisionReturnValue = .success(makeSilentControls())
        _ = await controller.setSwitch(sessionID: "session-1", control: .recording, enabled: false)
        let accepted = controller.snapshot.pendingOwnerWrites[Self.agentMxid]
        #expect(accepted?.map(\.fact) == [.recording(false)])

        service.setVoiceSwitchSessionIDControlEnabledRevisionReturnValue = .failure(.rejected("the recording is being published"))
        let didSucceed = await controller.setSwitch(sessionID: "session-1", control: .recording, enabled: true)

        #expect(!didSucceed)
        #expect(controller.snapshot.pendingOwnerWrites[Self.agentMxid] == accepted)
        #expect(presentedAgent(controller, document: .make(recording: true))?.shown.isRecording == false)
    }

    /// The backstop only withdraws. When the server ACCEPTED a write whose
    /// session left the snapshot meanwhile, `apply` has nothing to start
    /// the clock on and the tap goes — and the write it superseded must
    /// not come back, because the server just overrode it.
    @Test
    func anAcceptedWriteWhoseSessionVanishedRestoresNothing() async {
        let service = makeService(contexts: [makeContext()], controls: makeSilentControls(turningOn: .recording))
        let controller = makeController(service: service)
        await controller.reload()
        service.setVoiceSwitchSessionIDControlEnabledRevisionReturnValue = .success(makeSilentControls())
        _ = await controller.setSwitch(sessionID: "session-1", control: .recording, enabled: false)
        #expect(controller.snapshot.pendingOwnerWrites[Self.agentMxid]?.map(\.fact) == [.recording(false)])

        let held = HeldSwitchWrite()
        service.setVoiceSwitchSessionIDControlEnabledRevisionClosure = { _, _, _, _ in await held.hold() }
        let tap = Task { await controller.setSwitch(sessionID: "session-1", control: .recording, enabled: true) }
        await held.untilHeld()
        // The session ends while the write is out; the doorbell reload drops it.
        service.voiceSessionControlContextsRoomIDReturnValue = .success([])
        await controller.reload()
        #expect(controller.snapshot.sessions.isEmpty)

        held.answer(.success(makeSilentControls(turningOn: .recording)))
        let didSucceed = await tap.value

        #expect(didSucceed)
        #expect(controller.snapshot.pendingOwnerWrites[Self.agentMxid] == nil, "neither the tap nor the Stop it superseded")
    }

    // MARK: Helpers

    /// What the sheet would show for the agent: its live document plus the
    /// controller's snapshot — the presentation's two inputs.
    private func presentedAgent(_ controller: NativeAgentCenterController,
                                document: SpiralAgentStateReader.AgentClaim = .make()) -> NativeCallAgentPresentation.Agent? {
        var claims = NativeCallAgentClaims()
        claims.documents = [Self.agentMxid: document]
        let participant = NativeCallParticipant(id: "\(Self.agentMxid):AGENT",
                                                userID: Self.agentMxid,
                                                role: .agent,
                                                mediaState: .connected,
                                                isSpeaking: false,
                                                isAudioEnabled: true,
                                                isLocal: false)
        return NativeCallAgentPresentation.derive(live: .init(participants: [participant], claims: claims),
                                                  rest: controller.snapshot,
                                                  now: Date())
            .agents.first
    }

    /// Every switch off, the conversation offered.
    private func makeSilentControls(turningOn control: VoiceSessionSwitch? = nil) -> VoiceControlsState {
        makeControls(recordingEnabled: control == .recording,
                     recordingRevision: control == .recording ? 2 : 1,
                     summaryEnabled: control == .summary,
                     conversation: .init(active: control == .conversation, available: true, revision: control == .conversation ? 7 : 6))
    }

    private static func isOn(_ control: VoiceSessionSwitch, _ shown: NativeCallAgentPresentation.Shown?) -> Bool? {
        switch control {
        case .recording: shown?.isRecording
        case .summary: shown?.isSummaryArmed
        case .conversation: shown?.isConversationActive
        }
    }

    /// A document that still says `control` is on.
    private static func document(showing control: VoiceSessionSwitch) -> SpiralAgentStateReader.AgentClaim {
        switch control {
        case .recording: .make(recording: true)
        case .summary: .make(summaryArmed: true)
        case .conversation: .make(conversation: true)
        }
    }

    private static func fact(_ control: VoiceSessionSwitch, _ enabled: Bool) -> NativeAgentCenterPendingWrite.Fact {
        switch control {
        case .recording: .recording(enabled)
        case .summary: .summary(enabled)
        case .conversation: .conversation(enabled)
        }
    }

    /// A refused STOP is not "could not start": the backend's reason stands.
    @Test
    func aRefusedConversationStopKeepsTheBackendsReason() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false,
                                                         recordingRevision: 0,
                                                         conversation: .init(active: true, available: true, revision: 3)))
        let controller = makeController(service: service)
        await controller.reload()

        service.setVoiceSwitchSessionIDControlEnabledRevisionReturnValue = .failure(.rejected("the session is ending"))
        let didSucceed = await controller.setSwitch(sessionID: "session-1", control: .conversation, enabled: false)

        #expect(didSucceed == false)
        #expect(controller.snapshot.lastError == .rejected("the session is ending"))
    }

    /// 409: someone switched first. The controller re-reads, so the next
    /// tap carries the fresh token, and bridges nothing.
    @Test
    func aStaleConversationRevisionConflictsAndReloadsTheFreshToken() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false,
                                                         recordingRevision: 0,
                                                         conversation: .init(active: false, available: true, revision: 2)))
        let controller = makeController(service: service)
        await controller.reload()

        service.setVoiceSwitchSessionIDControlEnabledRevisionReturnValue = .failure(.conflict)
        service.voiceSessionControlsSessionIDReturnValue =
            .success(makeControls(recordingEnabled: false,
                                  recordingRevision: 0,
                                  conversation: .init(active: true, available: true, revision: 9)))
        let didSucceed = await controller.setSwitch(sessionID: "session-1", control: .conversation, enabled: true)

        #expect(didSucceed == false)
        #expect(controller.snapshot.lastError == .conflict)
        #expect(controller.snapshot.sessions.first?.conversation.revision == 9)
        #expect(controller.snapshot.pendingOwnerWrites.isEmpty)
    }

    /// A failed controls read offers no switch: there is no token to write.
    @Test
    func aFailedControlsReadOffersNoConversationSwitch() async {
        let service = makeService(contexts: [makeContext()], controls: nil)
        service.voiceSessionControlsSessionIDReturnValue = .failure(.unavailable("timeout"))
        let controller = makeController(service: service)

        await controller.reload()

        #expect(controller.snapshot.sessions.first?.conversation == .unknown)
    }

    /// A 503 on the controls read is the room not readable just now: read again shortly, not an unread session.
    @Test
    func aServiceUnavailableControlsReadIsTriedAgain() async {
        let controls = makeControls(recordingEnabled: true, recordingRevision: 2)
        let service = makeService(contexts: [makeContext()], controls: nil)
        var reads = 0
        service.voiceSessionControlsSessionIDClosure = { _ in
            reads += 1
            return reads < 3 ? .failure(.serviceUnavailable(retryAfter: .zero)) : .success(controls)
        }
        let controller = makeController(service: service)

        await controller.reload()

        #expect(reads == 3)
        #expect(controller.snapshot.sessions.first?.recording.revision == 2)
        #expect(controller.snapshot.lastError == nil)
    }

    /// Two sessions still 503: the retries share one budget for the load, so the second session doesn't add its own
    /// waits (a reload queued behind this one would wait for them); both stay unread, with no error.
    @Test
    func twoServiceUnavailableSessionsShareOneRetryBudget() async {
        let service = makeService(contexts: [makeContext(sessionID: "session-1"), makeContext(sessionID: "session-2")], controls: nil)
        service.voiceSessionControlsSessionIDReturnValue = .failure(.serviceUnavailable(retryAfter: .zero))
        let controller = makeController(service: service)

        await controller.reload()

        #expect(service.voiceSessionControlsSessionIDCallsCount == 2 + NativeAgentCenterController.controlsRetryBudget)
        #expect(controller.snapshot.sessions.map(\.conversation) == [.unknown, .unknown])
        #expect(controller.snapshot.lastError == nil)
    }

    /// Still 503 after the retries: the session is unread (`.unknown`), and no error is shown.
    @Test
    func aControlsReadStill503IsUnreadNotAnError() async {
        let service = makeService(contexts: [makeContext()], controls: nil)
        service.voiceSessionControlsSessionIDReturnValue = .failure(.serviceUnavailable(retryAfter: .zero))
        let controller = makeController(service: service)

        await controller.reload()

        #expect(service.voiceSessionControlsSessionIDCallsCount == 3)
        #expect(controller.snapshot.sessions.first?.conversation == .unknown)
        #expect(controller.snapshot.lastError == nil)
    }
}

/// Holds a switch write inside the "backend" until the test answers it —
/// the seconds a call that started silent takes to start its conversation.
private final nonisolated class HeldSwitchWrite: Sendable {
    private let continuation = Mutex<CheckedContinuation<Result<VoiceControlsState, VoiceControlsError>, Never>?>(nil)

    func hold() async -> Result<VoiceControlsState, VoiceControlsError> {
        await withCheckedContinuation { continuation in
            self.continuation.withLock { $0 = continuation }
        }
    }

    func untilHeld() async {
        while continuation.withLock({ $0 == nil }) {
            await Task.yield()
        }
    }

    func answer(_ result: Result<VoiceControlsState, VoiceControlsError>) {
        continuation.withLock { held in
            held?.resume(returning: result)
            held = nil
        }
    }
}

// MARK: - Question 395: the AI limit mid-call (D7, D10)

extension NativeAgentCenterControllerTests {
    /// Monday 16 November 2026, 00:00 UTC.
    private static let monday = Date(timeIntervalSince1970: 1_794_787_200)

    /// The owner's session that ends on a category's cap gives the call screen its line, with the pause's date from
    /// the agent's usage, and the reason on the agent's add row.
    @Test
    func aCategoryCapMidCallGivesTheOwnerTheLine() async {
        let service = makeService(contexts: [makeContext()], controls: makeControls(recordingEnabled: false, recordingRevision: 0))
        service.fetchAgentUsageAgentIDReturnValue = .success(Self.limitUsage(categories: [.init(category: .callTranslation, usedPercent: 30,
                                                                                                pause: .until(Self.monday))]))
        let controller = makeController(service: service)
        await controller.reload()

        service.voiceSessionControlContextsRoomIDReturnValue = .success([])
        service.voiceSessionProgressSessionIDReturnValue = .success(.ended(.categoryPaused(.callTranslation)))
        await controller.reload()

        #expect(controller.snapshot.limitStop == .categoryPaused(.callTranslation, until: Self.monday))
        #expect(controller.snapshot.joinFailures["agent-1"] == .categoryPaused(.callTranslation, .until(Self.monday)))
        #expect(service.fetchAgentUsageAgentIDReceivedAgentID == "agent-1")
    }

    @Test
    func theWholeLimitMidCallSaysTheWeek() async {
        let service = makeService(contexts: [makeContext()], controls: makeControls(recordingEnabled: false, recordingRevision: 0))
        service.fetchAgentUsageAgentIDReturnValue = .success(Self.limitUsage(categories: []))
        let controller = makeController(service: service)
        await controller.reload()

        service.voiceSessionControlContextsRoomIDReturnValue = .success([])
        service.voiceSessionProgressSessionIDReturnValue = .success(.ended(.budgetReached))
        await controller.reload()

        #expect(controller.snapshot.limitStop == .limitReached(isWeekly: true))
        #expect(controller.snapshot.joinFailures["agent-1"] == .budgetReached)
    }

    /// A usage read that fails is no answer: the line names no period and no date rather than guess.
    @Test
    func anUnreadableLimitGivesTheLineWithoutADate() async {
        let service = makeService(contexts: [makeContext()], controls: makeControls(recordingEnabled: false, recordingRevision: 0))
        service.fetchAgentUsageAgentIDReturnValue = .failure(.serverError(status: 500))
        let controller = makeController(service: service)
        await controller.reload()

        service.voiceSessionControlContextsRoomIDReturnValue = .success([])
        service.voiceSessionProgressSessionIDReturnValue = .success(.ended(.categoryPaused(.calls)))
        await controller.reload()

        #expect(controller.snapshot.limitStop == .categoryPaused(.calls, until: nil))
    }

    /// Only the owner sees it: someone else's assistant leaving says nothing, and neither does an ordinary end.
    @Test(arguments: [(canControl: false, reason: VoiceSessionEndReason.budgetReached), (canControl: true, reason: .manual), (canControl: true, reason: .callEnded)])
    func noLineForOthersOrAnOrdinaryEnd(canControl: Bool, reason: VoiceSessionEndReason) async {
        let service = makeService(contexts: [makeContext(canControl: canControl)], controls: makeControls(recordingEnabled: false, recordingRevision: 0))
        let controller = makeController(service: service)
        await controller.reload()

        service.voiceSessionControlContextsRoomIDReturnValue = .success([])
        service.voiceSessionProgressSessionIDReturnValue = .success(.ended(reason))
        await controller.reload()

        #expect(controller.snapshot.limitStop == nil)
        #expect(service.fetchAgentUsageAgentIDCallsCount == 0)
    }

    /// Adding the assistant again takes the line away.
    @Test
    func anAcceptedAddClearsTheLine() async {
        let service = makeService(contexts: [makeContext()], controls: makeControls(recordingEnabled: false, recordingRevision: 0))
        service.fetchAgentUsageAgentIDReturnValue = .success(Self.limitUsage(categories: []))
        let controller = makeController(service: service)
        await controller.reload()
        service.voiceSessionControlContextsRoomIDReturnValue = .success([])
        service.voiceSessionProgressSessionIDReturnValue = .success(.ended(.budgetReached))
        await controller.reload()
        #expect(controller.snapshot.limitStop != nil)

        service.attachVoiceAgentAgentIDRoomIDParamsReturnValue = .success("session-9")
        service.voiceSessionProgressSessionIDReturnValue = .success(.active)
        #expect(await controller.attach(agentID: "agent-1", params: makeAttachParams()))

        #expect(controller.snapshot.limitStop == nil)
    }

    /// Calls paused by their cap: the join check names no date, so the agent's usage says until when, and the add row
    /// says it in the Limit page's words.
    @Test
    func aCallsPauseOnTheJoinCheckReadsItsDate() async {
        let service = makeService(contexts: [], controls: nil)
        service.voiceJoinCheckAgentIDRoomIDReturnValue = .success(.categoryPaused(nil))
        service.fetchAgentUsageAgentIDReturnValue = .success(Self.limitUsage(categories: [.init(category: .calls, usedPercent: 40, pause: .until(Self.monday))]))
        let controller = makeController(service: service)
        await controller.reload()

        await controller.refreshJoinChecks()

        #expect(controller.snapshot.joinChecks == ["agent-1": .categoryPaused(.until(Self.monday))])
        #expect(NativeAgentCenterJoinFailure(.categoryPaused(.until(Self.monday))) == .categoryPaused(.calls, .until(Self.monday)))
    }

    @Test
    func theLineSaysWhatStoppedAndUntilWhen() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let thursday = Self.monday.addingTimeInterval(-3.5 * 86400)

        #expect(NativeAgentCenterLimitStop.limitReached(isWeekly: true).line() == UntranslatedL10n.screenNativeCallLimitUsedUpThisWeek)
        #expect(NativeAgentCenterLimitStop.limitReached(isWeekly: false).line() == UntranslatedL10n.screenNativeCallLimitUsedUp)
        #expect(NativeAgentCenterLimitStop.categoryPaused(.callTranslation, until: Self.monday).line(now: thursday, calendar: utc)
            == UntranslatedL10n.screenNativeCallLimitTranslationPausedUntil(UntranslatedL10n.screenAgentUsageUntilMonday))
        #expect(NativeAgentCenterLimitStop.categoryPaused(.callTranslation, until: nil).line() == UntranslatedL10n.screenNativeCallLimitTranslationPaused)
        #expect(NativeAgentCenterLimitStop.categoryPaused(.calls, until: Self.monday).line(now: thursday, calendar: utc)
            == UntranslatedL10n.screenNativeCallLimitAssistantPausedUntil(UntranslatedL10n.screenAgentUsageUntilMonday))
        #expect(NativeAgentCenterLimitStop.categoryPaused(.other, until: nil).line() == UntranslatedL10n.screenNativeCallLimitAssistantPaused)
    }

    private static func limitUsage(categories: [AgentUsage.CategoryShare]) -> AgentUsage {
        AgentUsage(current: .init(period: .week, startsAt: monday.addingTimeInterval(-7 * 86400), resetsAt: monday,
                                  usedPercent: 100, limitReached: false, categories: categories),
                   days: [])
    }
}

// MARK: - Question 387: why an assistant can't come

extension NativeAgentCenterControllerTests {
    /// B1 — an accepted attach is followed until the session says why it never reached the call.
    @Test(arguments: [(VoiceSessionEndReason.aiConsentRoom, NativeAgentCenterJoinFailure.aiConsentRoom),
                      (.aiConsentOwner, .aiConsentOwner),
                      (.budgetReached, .budgetReached),
                      (.failed, .failed),
                      (.unknown("newer"), .needsUpdate)])
    func anEndedJoinSaysWhyOnTheAgentsRow(reason: VoiceSessionEndReason, failure: NativeAgentCenterJoinFailure) async {
        let service = makeService(contexts: [], controls: nil)
        service.attachVoiceAgentAgentIDRoomIDParamsReturnValue = .success("session-9")
        service.voiceSessionProgressSessionIDReturnValue = .success(.ended(reason))
        let controller = makeController(service: service)
        await controller.reload()

        #expect(await controller.attach(agentID: "agent-1", params: makeAttachParams()))
        await controller.pendingJoinFollow["session-9"]?.value

        #expect(controller.snapshot.joinFailures["agent-1"] == failure)
        #expect(controller.snapshot.joinStartedAt["session-9"] == nil)
    }

    /// An ordinary end (the owner's Remove, the call over, the owner gone, translation not offered here) is no refusal
    /// and no «update the app».
    @Test(arguments: [VoiceSessionEndReason.manual, .callEnded, .ownerLeft, .translationNotHere])
    func anOrdinaryEndIsNoRefusal(reason: VoiceSessionEndReason) async {
        let service = makeService(contexts: [], controls: nil)
        service.attachVoiceAgentAgentIDRoomIDParamsReturnValue = .success("session-9")
        service.voiceSessionProgressSessionIDReturnValue = .success(.ended(reason))
        let controller = makeController(service: service)
        await controller.reload()

        _ = await controller.attach(agentID: "agent-1", params: makeAttachParams())
        await controller.pendingJoinFollow["session-9"]?.value

        #expect(controller.snapshot.joinFailures.isEmpty)
    }

    /// The platform's `owner_left` and `translation_not_here` are known ends; a value newer than this build stays unknown.
    @Test
    func theEndReasonsReadFromTheWire() {
        #expect(VoiceSessionEndReason(wire: "owner_left") == .ownerLeft)
        #expect(VoiceSessionEndReason(wire: "translation_not_here") == .translationNotHere)
        #expect(VoiceSessionEndReason(wire: "something_newer") == .unknown("something_newer"))
        #expect(NativeAgentCenterJoinFailure(VoiceSessionEndReason.ownerLeft) == nil)
        #expect(NativeAgentCenterJoinFailure(VoiceSessionEndReason.translationNotHere) == nil)
    }

    /// A stop mid-call for either reason puts nothing on the owner's row and no call line.
    @Test(arguments: [VoiceSessionEndReason.ownerLeft, .translationNotHere])
    func anOrdinaryStopMidCallSaysNothing(reason: VoiceSessionEndReason) async {
        let service = makeService(contexts: [makeContext()], controls: makeControls(recordingEnabled: false, recordingRevision: 0))
        let controller = makeController(service: service)
        await controller.reload()

        service.voiceSessionControlContextsRoomIDReturnValue = .success([])
        service.voiceSessionProgressSessionIDReturnValue = .success(.ended(reason))
        await controller.reload()

        #expect(controller.snapshot.joinFailures.isEmpty)
        #expect(controller.snapshot.limitStop == nil)
    }

    /// A failed progress read is not an end: the follow keeps asking.
    @Test
    func aFailedProgressReadKeepsFollowing() async {
        let service = makeService(contexts: [], controls: nil)
        service.attachVoiceAgentAgentIDRoomIDParamsReturnValue = .success("session-9")
        let reads = AttachCounter()
        service.voiceSessionProgressSessionIDClosure = { _ in
            reads.increment()
            return reads.count < 3 ? .failure(.unavailable("offline")) : .success(.active)
        }
        let controller = makeController(service: service)
        await controller.reload()

        _ = await controller.attach(agentID: "agent-1", params: makeAttachParams())
        await controller.pendingJoinFollow["session-9"]?.value

        #expect(reads.count == 3)
        #expect(controller.snapshot.joinFailures.isEmpty)
    }

    /// F3 — a refused attach lands on the agent's add row with the reason the owner can act on.
    @Test(arguments: [(VoiceControlsError.agentPaused, NativeAgentCenterJoinFailure.paused),
                      (.conflict, .cannotJoinCalls),
                      (.translationPaused(.init(reason: .aiLimit, pauseUntil: nil)), .budgetReached),
                      (.translationPaused(.init(reason: .callCap, pauseUntil: nil)), .categoryPaused(.callTranslation, .untilChanged)),
                      (.intentUnavailable(roomKind: "owner_dm"), .failed),
                      (.serviceUnavailable(retryAfter: .zero), .failed),
                      (.unavailable("offline"), .failed)])
    func aRefusedAttachLandsOnTheAddRow(error: VoiceControlsError, failure: NativeAgentCenterJoinFailure) async {
        let service = makeService(contexts: [], controls: nil)
        service.attachVoiceAgentAgentIDRoomIDParamsReturnValue = .failure(error)
        let controller = makeController(service: service)
        await controller.reload()

        #expect(await controller.attach(agentID: "agent-1", params: makeAttachParams()) == false)
        #expect(controller.snapshot.joinFailures["agent-1"] == failure)
    }

    /// D8 — an ask-to-join room refuses the client's invite: "only admins can add members".
    @Test
    func aRefusedInviteIsAnAskToJoinRoom() async {
        let service = makeService(contexts: [], controls: nil)
        service.attachVoiceAgentAgentIDRoomIDParamsReturnValue = .failure(.inviteRequired("invite it first"))
        let controller = makeController(service: service, members: []) { _ in false }
        await controller.reload()

        #expect(await controller.attach(agentID: "agent-1", params: makeAttachParams()) == false)
        #expect(controller.snapshot.joinFailures["agent-1"] == .askToJoin)
    }

    /// B4 — the check runs for own agents not in the call; one that could not be read leaves no verdict.
    @Test
    func joinChecksAreKeptOnlyWhenTheyWereRead() async {
        let service = makeService(contexts: [], controls: nil)
        service.listMyPersonalAgentsReturnValue = .success(.init(agents: [.init(id: "agent-1", matrixUserID: "@assistant-red:spiral.md",
                                                                                displayName: "Red", avatarMXC: nil, visibility: "private",
                                                                                lifecycleState: "active"),
                                                                          .init(id: "agent-2", matrixUserID: "@assistant-red-2:spiral.md",
                                                                                displayName: "Red 2", avatarMXC: nil, visibility: "private",
                                                                                lifecycleState: "active")],
                                                                 provisioningStatus: .ready))
        service.voiceJoinCheckAgentIDRoomIDClosure = { agentID, _ in
            agentID == "agent-1" ? .success(.aiConsentRoom) : .failure(.unavailable("status 503"))
        }
        let controller = makeController(service: service)
        await controller.reload()

        await controller.refreshJoinChecks()

        #expect(controller.snapshot.joinChecks == ["agent-1": .aiConsentRoom])
    }

    /// F3a / audit F7 — a paused agent is offered with Resume, and every own agent counts as "mine".
    @Test
    func pausedAgentsAreOfferedAndAllOwnAgentsAreMine() async {
        let service = makeService(contexts: [], controls: nil)
        service.listMyPersonalAgentsReturnValue = .success(.init(agents: [.init(id: "agent-1", matrixUserID: "@assistant-red:spiral.md",
                                                                                displayName: "Red", avatarMXC: nil, visibility: "private",
                                                                                lifecycleState: "suspended"),
                                                                          .init(id: "agent-3", matrixUserID: "@assistant-old:spiral.md",
                                                                                displayName: "Old", avatarMXC: nil, visibility: "private",
                                                                                lifecycleState: "archived")],
                                                                 provisioningStatus: .ready))
        let controller = makeController(service: service)

        await controller.reload()

        #expect(controller.snapshot.candidates.map(\.id) == ["agent-1"])
        #expect(controller.snapshot.candidates.first?.isPaused == true)
        #expect(controller.snapshot.ownAgentMxids == ["@assistant-red:spiral.md", "@assistant-old:spiral.md"])
    }

    @Test
    func resumingTakesThePauseOffAndAsksAgain() async {
        let service = makeService(contexts: [], controls: nil)
        service.editAgentAgentIDPatchReturnValue = .failure(.serverError(status: 500))
        service.editAgentAgentIDPatchClosure = { _, patch in
            #expect(patch.paused == false)
            return .failure(.serverError(status: 0))
        }
        let controller = makeController(service: service)
        await controller.reload()

        #expect(await controller.resume(agentID: "agent-1") == false)
        #expect(service.editAgentAgentIDPatchCallsCount == 1)
        #expect(controller.snapshot.lastErrorScope == .agent("agent-1"), "on the add row, not the whole-sheet card")
    }

    /// D6 — a refused kick stays on that assistant, not the whole-sheet "unavailable" card.
    @Test
    func aRefusedRemovalFromTheChatStaysOnThatAssistant() async {
        let service = makeService(contexts: [], controls: nil)
        let controller = NativeAgentCenterController(agentPlatformService: service,
                                                     roomID: "!room:spiral.md",
                                                     roomMemberMxids: { [] },
                                                     inviteAgent: { _ in false },
                                                     kickAgent: { _ in false })
        await controller.reload()

        #expect(await controller.removeFromChat(agentMxid: "@assistant-blue:spiral.md") == false)
        #expect(controller.snapshot.lastErrorScope == .foreign("@assistant-blue:spiral.md"))
    }
}

// MARK: - Question 401: the sheet never shows a failure or a gap as "no assistants"

extension NativeAgentCenterControllerTests {
    /// Remark 4: the dock knows the platform is there before it answers, so it never grows a button late.
    @Test
    func theDockKnowsThePlatformBeforeItAnswers() {
        #expect(makeController(service: AgentPlatformServiceMock()).snapshot.isConfigured)
        #expect(!makeController(service: AgentPlatformServiceMock()).snapshot.isAvailable)
        #expect(!makeController(service: nil).snapshot.isConfigured)
    }

    /// Remark 10: the snapshot that drops the owner's stopped session already says why, so the sheet never shows
    /// "No assistants in this call yet" in between.
    @Test
    func aLimitStopArrivesWithTheSnapshotThatDropsTheSession() async {
        let service = makeService(contexts: [makeContext()], controls: makeControls(recordingEnabled: false, recordingRevision: 0))
        service.fetchAgentUsageAgentIDReturnValue = .success(Self.limitUsage(categories: []))
        let controller = makeController(service: service)
        await controller.reload()
        var published: [NativeAgentCenterSnapshot] = []
        let subscription = controller.snapshotPublisher.sink { published.append($0) }

        service.voiceSessionControlContextsRoomIDReturnValue = .success([])
        service.voiceSessionProgressSessionIDReturnValue = .success(.ended(.budgetReached))
        await controller.reload()
        subscription.cancel()

        let withoutTheSession = published.filter(\.sessions.isEmpty)
        #expect(!withoutTheSession.isEmpty)
        #expect(withoutTheSession.allSatisfy { $0.joinFailures["agent-1"] == .budgetReached })
    }

    /// Flows N6: a consent stop mid-call puts its reason on the owner's add row; it is no limit, so no call line.
    @Test(arguments: [(VoiceSessionEndReason.aiConsentRoom, NativeAgentCenterJoinFailure.aiConsentRoom),
                      (.optOut, .aiConsentRoom),
                      (.aiConsentOwner, .aiConsentOwner)])
    func aConsentStopMidCallSaysWhyOnTheOwnersRow(reason: VoiceSessionEndReason, failure: NativeAgentCenterJoinFailure) async {
        let service = makeService(contexts: [makeContext()], controls: makeControls(recordingEnabled: false, recordingRevision: 0))
        let controller = makeController(service: service)
        await controller.reload()

        service.voiceSessionControlContextsRoomIDReturnValue = .success([])
        service.voiceSessionProgressSessionIDReturnValue = .success(.ended(reason))
        await controller.reload()

        #expect(controller.snapshot.joinFailures["agent-1"] == failure)
        #expect(controller.snapshot.limitStop == nil)
    }

    /// Remark 8: the re-read that a write's own effect rings keeps the refusal on its row; the sheet's global state
    /// is what a good read answers.
    @Test
    func aReReadKeepsARowsRefusal() async {
        let service = makeService(contexts: [makeContext()], controls: makeControls(recordingEnabled: false, recordingRevision: 0))
        service.setVoiceTranslationSessionIDParamsRevisionReturnValue = .failure(.rejected("not now"))
        let controller = makeController(service: service)
        await controller.reload()
        #expect(await controller.setTranslation(sessionID: "session-1", params: .forLanguage("en")) == false)

        await controller.reload()

        #expect(controller.snapshot.lastError == .rejected("not now"))
        #expect(controller.snapshot.lastErrorScope == .session("session-1", .translation))
    }

    /// Board A: the add form closes when the backend accepts the add, before the re-read; a refusal keeps it open.
    @Test
    func anAcceptedAddIsKnownAndARefusedOneIsNot() async {
        let service = makeService(contexts: [], controls: nil)
        service.attachVoiceAgentAgentIDRoomIDParamsReturnValue = .success("session-9")
        service.voiceSessionProgressSessionIDReturnValue = .success(.active)
        let controller = makeController(service: service)
        await controller.reload()

        #expect(await controller.attach(agentID: "agent-1", params: makeAttachParams()))
        #expect(controller.snapshot.acceptedAttaches == ["agent-1"])

        service.attachVoiceAgentAgentIDRoomIDParamsReturnValue = .failure(.agentPaused)
        #expect(await controller.attach(agentID: "agent-1", params: makeAttachParams()) == false)
        #expect(controller.snapshot.acceptedAttaches.isEmpty)
        #expect(controller.snapshot.joinFailures["agent-1"] == .paused)
    }

    /// Checklist 1: an unread list of one's own agents is "couldn't check", never "you don't have an assistant".
    @Test
    func anUnreadAgentListIsNotNoAssistant() async {
        let service = makeService(contexts: [], controls: nil)
        service.listMyPersonalAgentsReturnValue = .failure(.serverError(status: 503))
        let controller = makeController(service: service)

        await controller.reload()

        guard case .unavailable = controller.snapshot.lastError else {
            Issue.record("Expected the platform to read as unavailable, got \(String(describing: controller.snapshot.lastError))")
            return
        }
        #expect(controller.snapshot.lastErrorScope == .global)
    }

    /// The agents already known stay when a later list fails.
    @Test
    func aFailedAgentListKeepsTheAgentsAlreadyKnown() async {
        let service = makeService(contexts: [], controls: nil)
        let controller = makeController(service: service)
        await controller.reload()
        #expect(controller.snapshot.candidates.map(\.id) == ["agent-1"])

        service.listMyPersonalAgentsReturnValue = .failure(.serverError(status: 503))
        await controller.reload()

        #expect(controller.snapshot.candidates.map(\.id) == ["agent-1"])
        #expect(controller.snapshot.lastError == nil)
    }
}

/// The translation port's sources (ADR-0094), in memory.
final class TranslationPortStub: NativeCallTranslationPortProtocol {
    var catalog: [VoiceControlsCatalogLanguage]? = [.init(code: "en", label: "English"),
                                                    .init(code: "uk", label: "Ukrainian"),
                                                    .init(code: "zh-Hans", label: "Chinese (Simplified)")]
    var membershipLanguages: [String: String]? = [:]
    var tool: Result<NativeCallTranslationTool?, NativeCallTranslationPortError> = .success(nil)
    private(set) var published: [String] = []
    private(set) var stored: [NativeCallTranslationTool] = []

    func languages() async -> [VoiceControlsCatalogLanguage]? {
        catalog
    }

    func participantLanguages(roomID: String) async -> [String: String]? {
        membershipLanguages
    }

    func publishMyLanguage(_ language: String, roomID: String) async -> Bool {
        published.append(language)
        return true
    }

    func tool(roomID: String) async -> Result<NativeCallTranslationTool?, NativeCallTranslationPortError> {
        tool
    }

    func setTool(_ tool: NativeCallTranslationTool, roomID: String) async -> Bool {
        stored.append(tool)
        self.tool = .success(tool.isEnabled ? tool : nil)
        return true
    }
}
