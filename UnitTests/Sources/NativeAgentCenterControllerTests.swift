//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import ElementX
import Foundation
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

    /// The translation write is bridged in the DOCUMENT's currency — base
    /// codes — so it can settle against what the reader reads back.
    @Test
    func aTranslationWriteIsBridgedInBaseCodes() {
        #expect(NativeAgentCenterController.documentLanguages([.init(speakerScope: "anyone", speakerMembers: [], targetLanguages: ["en-US", "UK", "uk_UA"])]) == ["en", "uk"])
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
        #expect(controller.snapshot.lastError == .rejected("voice disabled for this agent"))
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
                                inviteAgent: @escaping @MainActor (String) async -> Bool = { _ in true }) -> NativeAgentCenterController {
        NativeAgentCenterController(agentPlatformService: service,
                                    roomID: "!room:spiral.md",
                                    roomMemberMxids: { members },
                                    inviteAgent: inviteAgent,
                                    endingRecheckInterval: endingRecheckInterval)
    }

    @Test
    func translationStateIsDerivedFromTheEffectiveBooths() async {
        // Slice 4 booth item: what the picker shows is what the engine
        // RUNS (effective booths), with the override's CAS token.
        let controls = makeControls(recordingEnabled: false,
                                    recordingRevision: 0,
                                    booths: [.init(speakerScope: "anyone", speakerMembers: [], targetLanguages: ["uk", "en"]),
                                             .init(speakerScope: "anyone", speakerMembers: [], targetLanguages: ["en"])],
                                    overrideRevision: 7)
        let service = makeService(contexts: [makeContext()], controls: controls)
        let controller = makeController(service: service)
        await controller.reload()

        let translation = controller.snapshot.sessions.first?.translation
        #expect(translation?.isOn == true)
        #expect(translation?.languages == ["en", "uk"])
        // Brief 0062 parity: the FULL booth list + style + source ride
        // the snapshot — the editor edits them, never a flat union.
        #expect(translation?.booths.count == 2)
        #expect(translation?.style == "simultaneous")
        #expect(translation?.source == "override")
        #expect(translation?.revision == 7)
        #expect(controller.snapshot.availableLanguages.map(\.code) == ["en", "uk"])
    }

    @Test
    func settingTranslationWritesTheFullBoothListWithTheSnapshotRevision() async {
        // Brief 0062's central rule: the write carries EXACTLY what the
        // owner configured — a multi-booth, per-speaker setup must not
        // be flattened into one `anyone` booth (the regression the
        // operator caught in the first native editor).
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 0, overrideRevision: 3))
        let controller = makeController(service: service)
        await controller.reload()

        let params = VoiceTranslationParams(booths: [.init(speakerScope: "owner_only", speakerMembers: [], targetLanguages: ["uk"]),
                                                     .init(speakerScope: "specific_senders",
                                                           speakerMembers: ["@bob:spiral.md"],
                                                           targetLanguages: ["en", "de"])],
                                            style: "consecutive")
        service.setVoiceTranslationSessionIDParamsRevisionReturnValue =
            .success(makeControls(recordingEnabled: false,
                                  recordingRevision: 0,
                                  booths: params.booths,
                                  overrideRevision: 4))
        let ok = await controller.setTranslation(sessionID: "session-1", params: params)

        #expect(ok)
        let call = service.setVoiceTranslationSessionIDParamsRevisionReceivedArguments
        #expect(call?.revision == 3)
        #expect(call?.params == params)
        #expect(controller.snapshot.sessions.first?.translation.booths == params.booths)
    }

    @Test
    func anInvalidBoothListIsRejectedBeforeTheWire() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 0))
        let controller = makeController(service: service)
        await controller.reload()

        // A named booth without members must not reach the backend.
        let ok = await controller.setTranslation(sessionID: "session-1",
                                                 params: .init(booths: [.init(speakerScope: "specific_senders",
                                                                              speakerMembers: [],
                                                                              targetLanguages: ["uk"])],
                                                               style: "consecutive"))
        #expect(!ok)
        #expect(service.setVoiceTranslationSessionIDParamsRevisionCallsCount == 0)
    }

    @Test
    func clearingTheOverrideFallsBackToTheRoomRule() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false,
                                                         recordingRevision: 0,
                                                         booths: [.init(speakerScope: "anyone", speakerMembers: [], targetLanguages: ["uk"])],
                                                         overrideRevision: 5))
        let controller = makeController(service: service)
        await controller.reload()

        service.clearVoiceTranslationOverrideSessionIDReturnValue =
            .success(makeControls(recordingEnabled: false, recordingRevision: 0))
        let ok = await controller.clearTranslationOverride(sessionID: "session-1")

        #expect(ok)
        #expect(controller.snapshot.sessions.first?.translation.isOn == false)
    }

    @Test
    func aSystemCoverageShrinkMarksTheSessionDisplaced() async {
        // W5: another participant brought their own agent and the
        // backend narrowed our booth — a shrink WE did not write.
        let broad = makeControls(recordingEnabled: false,
                                 recordingRevision: 0,
                                 booths: [.init(speakerScope: "anyone", speakerMembers: [], targetLanguages: ["uk"])],
                                 overrideRevision: 2)
        let service = makeService(contexts: [makeContext()], controls: broad)
        let controller = makeController(service: service)
        await controller.reload()
        #expect(controller.snapshot.displacedSessionIDs.isEmpty)

        // The doorbell reload brings in the narrowed state.
        service.voiceSessionControlsSessionIDReturnValue =
            .success(makeControls(recordingEnabled: false,
                                  recordingRevision: 0,
                                  booths: [.init(speakerScope: "everyone_except",
                                                 speakerMembers: ["@bob:spiral.md"],
                                                 targetLanguages: ["uk"])],
                                  overrideRevision: 3))
        await controller.reload()
        #expect(controller.snapshot.displacedSessionIDs == ["session-1"])
    }

    // MARK: - Decision 180: the catalog before the first attach

    /// The Add sheet's language picker has languages with no session in the
    /// call: they are read for the owner's agent.
    @Test
    func theLanguagesAreThereBeforeTheFirstAttach() async {
        let service = makeService(contexts: [], controls: nil)
        let controller = makeController(service: service)

        await controller.reload()

        #expect(controller.snapshot.availableLanguages.map(\.code) == ["en", "uk"])
        #expect(service.voiceControlsCatalogAgentIDReceivedAgentID == "agent-1")
    }

    /// A failed catalog read is not "no languages": the known ones stay.
    @Test
    func aFailedCatalogReadKeepsTheKnownLanguages() async {
        let service = makeService(contexts: [], controls: nil)
        let controller = makeController(service: service)
        await controller.reload()

        service.voiceControlsCatalogAgentIDReturnValue = .failure(.unavailable("status 500"))
        await controller.reload()

        #expect(controller.snapshot.availableLanguages.map(\.code) == ["en", "uk"])
    }

    private func makeService(contexts: [VoiceSessionControlContext],
                             controls: VoiceControlsState?) -> AgentPlatformServiceMock {
        let service = AgentPlatformServiceMock()
        service.voiceSessionControlContextsRoomIDReturnValue = .success(contexts)
        if let controls {
            service.voiceSessionControlsSessionIDReturnValue = .success(controls)
        }
        service.voiceControlsCatalogAgentIDReturnValue =
            .success(.init(voiceTranslationLanguages: [.init(code: "en", label: "English"),
                                                       .init(code: "uk", label: "Ukrainian")]))
        service.listMyPersonalAgentsReturnValue = .success(.init(agents: [.init(id: "agent-1",
                                                                                matrixUserID: "@assistant-red:spiral.md",
                                                                                displayName: "Red's Assistant",
                                                                                avatarMXC: nil,
                                                                                visibility: "private",
                                                                                lifecycleState: "active")],
                                                                 provisioningStatus: .ready))
        return service
    }

    private func makeContext(canControl: Bool = true,
                             state: String = "active") -> VoiceSessionControlContext {
        VoiceSessionControlContext(sessionID: "session-1",
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
                              booths: [VoiceTranslationBooth] = [],
                              overrideRevision: Int32? = nil,
                              conversation: VoiceConversationState = .init(active: false, available: false, revision: 0),
                              canSaveAsRoomDefault: Bool = false) -> VoiceControlsState {
        VoiceControlsState(sessionID: "session-1",
                           effective: .init(source: booths.isEmpty ? "off" : "override",
                                            style: booths.isEmpty ? nil : "simultaneous",
                                            booths: booths),
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
                           conversation: conversation,
                           canSaveAsRoomDefault: canSaveAsRoomDefault)
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
}

// MARK: - Room-default promotion (audit 1.4)

extension NativeAgentCenterControllerTests {
    /// The editor's "Saved as the room standard" label used to latch on the
    /// tap. The view model drops actions while one is in flight and the
    /// backend can refuse, so the row could read "saved" and disable itself
    /// having promoted nothing. The flag now comes from the controller,
    /// which records it only after the write succeeded.
    @Test
    func promotionIsRecordedOnlyWhenTheBackendAcceptsIt() async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 0))
        let controller = makeController(service: service)
        await controller.reload()
        #expect(controller.snapshot.savedAsRoomDefaultSessionIDs.isEmpty)

        service.saveVoiceTranslationAsRoomDefaultSessionIDReturnValue = .failure(.rejected("no enabled override"))
        let refused = await controller.saveTranslationAsRoomDefault(sessionID: "session-1")
        #expect(!refused)
        #expect(controller.snapshot.savedAsRoomDefaultSessionIDs.isEmpty, "a refused write must not claim a promotion")

        service.saveVoiceTranslationAsRoomDefaultSessionIDReturnValue = .success(())
        let promoted = await controller.saveTranslationAsRoomDefault(sessionID: "session-1")
        #expect(promoted)
        #expect(controller.snapshot.savedAsRoomDefaultSessionIDs.contains("session-1"))
    }

    /// Review #2: the controls read carries the server's answer, and it
    /// rides the snapshot to the editor; nothing else decides it.
    @Test(arguments: [true, false])
    func theServerSaysWhetherTheTranslationCanBecomeTheRoomRule(canSave: Bool) async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 0, canSaveAsRoomDefault: canSave))
        let controller = makeController(service: service)
        #expect(controller.snapshot.sessions.first?.canSaveAsRoomDefault != true, "unknown until read")

        await controller.reload()

        #expect(controller.snapshot.sessions.first?.canSaveAsRoomDefault == canSave)
    }

    /// ADR-0088: the save is refused like an arm (all-or-nothing), and the
    /// owner reads the arm form's words for it.
    @Test(arguments: [RoomToolRefusal.capReached, .duplicate, .doesNotFireHere(reason: "1:1 room")])
    func aRefusedPromotionSaysWhatTheArmFormSays(refusal: RoomToolRefusal) async {
        let service = makeService(contexts: [makeContext()],
                                  controls: makeControls(recordingEnabled: false, recordingRevision: 0))
        let controller = makeController(service: service)
        await controller.reload()

        service.saveVoiceTranslationAsRoomDefaultSessionIDReturnValue = .failure(.toolRefused(refusal))
        let promoted = await controller.saveTranslationAsRoomDefault(sessionID: "session-1")

        #expect(!promoted)
        #expect(controller.snapshot.savedAsRoomDefaultSessionIDs.isEmpty)
        #expect(controller.snapshot.lastError == .rejected(refusal.message))
        #expect(controller.snapshot.lastError?.localizedDescription == refusal.message)
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
