//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import AVFoundation
import Combine
@testable import ElementX
import Foundation
import LiveKit
import MatrixRustSDK
import Testing

// AGENT-PLATFORM (Brief 0063)

/// Abandoned-resume coverage for `NativeCallSession` (audit C1/C10,
/// the wave-5 call audit): `bounded()` deliberately does not cancel the
/// work it abandons, so every await in `start()` and in the rejoin can
/// resume into a call that is already over. These tests pin what such a
/// late resume is allowed to do: nothing the user can hear or see.
@MainActor
@Suite(.timeLimit(.minutes(2)))
struct NativeCallSessionTests {
    /// C1 — the P1 of the audit. The user hangs up while the transport
    /// connect is suspended. The late resume used to publish a hot
    /// microphone into the room whose Matrix membership was already left,
    /// overwrite the terminal `.ended` with `.connected`, and hand the
    /// delegate a state that minted a fresh CallKit call. Now: the state
    /// stays ended, the microphone is never requested, and the freshly
    /// made connection is put back.
    @Test
    func hangUpDuringConnectDoesNotResurrectTheCall() async throws {
        let rtcSession = makeRTCSession()
        let transport = makeTransport()
        let gate = Gate()
        transport.connectUrlTokenClosure = { _, _ in await gate.wait() }

        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)
        let delegate = DelegateSpy()
        session.delegate = delegate

        let startTask = Task { await session.start() }
        try await waitUntil { transport.connectUrlTokenCallsCount == 1 }

        // The hang-up lands while start() is suspended inside connect. It
        // sees `isConnected == false` and rightly skips the transport
        // teardown — there is nothing connected yet.
        await session.stop()
        #expect(session.state == .ended(reason: .userHungUp))

        // The abandoned connect resumes into the dead call.
        gate.open()
        await startTask.value

        #expect(session.state == .ended(reason: .userHungUp),
                "a late start resume must never overwrite the terminal state")
        #expect(transport.setMicrophoneEnabledCallsCount == 0,
                "the microphone must never be requested on a call the user already ended")
        #expect(transport.disconnectCallsCount == 1,
                "the connection the late resume made is its own to put back")
        #expect(!delegate.states.contains(.connected),
                "the delegate must never learn `.connected` for a dead call — that is what minted the ghost CallKit call")
    }

    /// C1, earlier await: the hang-up lands while the join is suspended.
    /// Nothing was connected, so the only correct outcome is silence — no
    /// credentials fetch, no connect, no state change.
    @Test
    func hangUpDuringJoinStopsTheStartCold() async throws {
        let rtcSession = makeRTCSession()
        let transport = makeTransport()
        let gate = Gate()
        rtcSession.joinEncryptMediaNotificationMediaClosure = { _, _, _ in
            await gate.wait()
            return .success(())
        }

        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)

        let startTask = Task { await session.start() }
        try await waitUntil { rtcSession.joinEncryptMediaNotificationMediaCallsCount == 1 }

        await session.stop()
        gate.open()
        await startTask.value

        #expect(session.state == .ended(reason: .userHungUp))
        #expect(transport.connectUrlTokenCallsCount == 0,
                "an abandoned start must not open a transport at all")
    }

    /// C10 — the rejoin twin. A hard disconnect puts the call into
    /// `.reconnecting`; the reconnect attempt's connect wedges; the user
    /// hangs up. The late connect resume used to leave a live, unowned
    /// connection behind (`guard case .reconnecting` returned without
    /// disconnecting). Now it puts the connection back.
    @Test
    func hangUpDuringRejoinDisconnectsTheLateTransport() async throws {
        let rtcSession = makeRTCSession()
        let transport = makeTransport()
        let events = PassthroughSubject<NativeCallTransportEvent, Never>()
        transport.underlyingEvents = events.eraseToAnyPublisher()

        // A fully successful start first — instant mocks all the way.
        transport.connectUrlTokenClosure = { _, _ in }
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)
        await session.start()
        #expect(session.state == .connected)

        // The transport drops with an error → the session attempts ONE
        // rejoin, whose connect wedges on the gate.
        let gate = Gate()
        transport.connectUrlTokenClosure = { _, _ in await gate.wait() }
        events.send(.didDisconnect(error: "test: transport dropped"))
        try await waitUntil { transport.connectUrlTokenCallsCount == 2 }
        #expect(session.state == .reconnecting)

        // The user gives up and hangs up while the rejoin is suspended.
        await session.stop()
        let disconnectsAtHangUp = transport.disconnectCallsCount

        gate.open()
        try await waitUntil { transport.disconnectCallsCount > disconnectsAtHangUp }

        #expect(session.state == .ended(reason: .userHungUp),
                "a late rejoin resume must never resurrect the call")
        #expect(transport.disconnectCallsCount > disconnectsAtHangUp,
                "the connection the late rejoin made must be put back, not leaked")
    }

    /// Audit wave 8 — a media-services reset invalidates the category, the
    /// active flag and the engine's units, and nothing observed it: the call
    /// sat connected, timing and silent, while `isSessionActive` kept the
    /// fail-open from ever running. Ending honestly IS the recovery — the
    /// user redials into a fresh audio world.
    @Test
    func aMediaServicesResetEndsTheCallInsteadOfLeavingItSilent() async throws {
        let rtcSession = makeRTCSession()
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: makeTransport())

        NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification,
                                        object: nil)

        try await waitUntil {
            if case .ended(reason: .failed) = session.state { return true }
            return false
        }
        #expect(rtcSession.leaveCallsCount == 1,
                "the membership must be withdrawn — a silent zombie on peers' rosters is the exact symptom this ends")
    }

    /// Device day 2026-09-02. Tapping the camera-flip button a few times in
    /// a row broke the camera: LiveKit answered `deviceNotFound` ("No camera
    /// video capture devices available") and the picture stayed on the old
    /// lens for the rest of the call.
    ///
    /// The capturer flips its own `position` and THEN restarts the capture
    /// session, so two overlapping switches read each other's half-applied
    /// position and tear the session down mid-start. Nothing serialized them:
    /// five affordances send `.switchCamera` and each spawns its own `Task`.
    ///
    /// This pins the latch — and pins that it RELEASES, because a latch that
    /// wedges would disable the camera button for the rest of the call, which
    /// is the same bug wearing a different hat.
    @Test
    func anOverlappingCameraSwitchIsDroppedAndTheLatchReleases() async throws {
        let transport = makeTransport()
        let gate = Gate()
        transport.switchCameraClosure = { await gate.wait() }

        let session = NativeCallSession(rtcSession: makeRTCSession(),
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .video, scope: .group),
                                        transport: transport)

        let first = Task { await session.switchCamera() }
        try await waitUntil { transport.switchCameraCallsCount == 1 }

        // The impatient second tap, while the capturer is still restarting.
        // Spawned rather than awaited so that a MISSING latch fails this
        // test in milliseconds instead of deadlocking on the closed gate.
        let second = Task { await session.switchCamera() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(transport.switchCameraCallsCount == 1,
                "an overlapping switch must never reach the capturer — concurrent restarts are what broke it")

        gate.open()
        await first.value
        await second.value
        #expect(transport.switchCameraCallsCount == 1)

        // A deliberate switch after the first one finished must work.
        await session.switchCamera()
        #expect(transport.switchCameraCallsCount == 2,
                "the latch must release — a stuck latch disables the camera for the whole call")
    }

    @Test
    func hangUpDuringMicrophonePublishNeverStartsTheCamera() async throws {
        let transport = makeTransport()
        let gate = Gate()
        transport.setMicrophoneEnabledClosure = { _ in await gate.wait() }
        let session = NativeCallSession(rtcSession: makeRTCSession(),
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .video, scope: .group),
                                        transport: transport)
        let startTask = Task { await session.start() }
        try await waitUntil { transport.setMicrophoneEnabledCallsCount == 1 }
        await session.stop()
        gate.open()
        await startTask.value

        #expect(transport.setCameraEnabledCallsCount == 0,
                "a microphone publish completing after hang-up must not turn on the camera")
        #expect(session.state == .ended(reason: .userHungUp))
    }

    @Test
    func finishingAJoinWhileHeldPreservesTheHold() async throws {
        let transport = makeTransport()
        let gate = Gate()
        transport.connectUrlTokenClosure = { _, _ in await gate.wait() }
        let session = NativeCallSession(rtcSession: makeRTCSession(),
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)
        let task = Task { await session.start() }
        try await waitUntil { transport.connectUrlTokenCallsCount == 1 }
        session.setOnHold(true)
        gate.open()
        await task.value

        #expect(session.state == .onHold, "finishing a join must not override CallKit's hold")
        session.setOnHold(false)
        #expect(session.state == .connected, "resume must use the state reached during the hold")
        await session.stop()
    }

    @Test
    func reconnectingWhileHeldUpdatesTheStateToResume() async {
        let transport = makeTransport()
        let events = PassthroughSubject<NativeCallTransportEvent, Never>()
        transport.underlyingEvents = events.eraseToAnyPublisher()
        let session = NativeCallSession(rtcSession: makeRTCSession(),
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)
        await session.start()
        events.send(.isReconnecting)
        session.setOnHold(true)
        events.send(.didReconnect)
        #expect(session.state == .onHold)
        session.setOnHold(false)
        #expect(session.state == .connected, "a reconnect received on hold must not be discarded")
        await session.stop()
    }

    @Test
    func aReconnectStartingOnHoldStillHasADeadline() async throws {
        let transport = makeTransport()
        let events = PassthroughSubject<NativeCallTransportEvent, Never>()
        transport.underlyingEvents = events.eraseToAnyPublisher()
        let session = NativeCallSession(rtcSession: makeRTCSession(),
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport,
                                        reconnectTimeoutDuration: .milliseconds(20))
        await session.start()
        session.setOnHold(true)
        events.send(.isReconnecting)

        try await waitUntil { session.state == .ended(reason: .connectionLost) }
        session.setOnHold(false)
        #expect(session.state == .ended(reason: .connectionLost))
    }

    @Test
    func anEndedCallRefusesDelayedMediaActions() async {
        let rtcSession = makeRTCSession()
        let transport = makeTransport()
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .video, scope: .group),
                                        transport: transport)
        await session.stop()

        #expect(await !session.setCameraEnabled(true))
        #expect(await !session.setMicrophoneEnabled(true))
        await session.switchCamera()
        #expect(transport.setCameraEnabledCallsCount == 0)
        #expect(transport.setMicrophoneEnabledCallsCount == 0)
        #expect(transport.switchCameraCallsCount == 0)
        #expect(rtcSession.setMediaCallsCount == 0)
    }

    @Test
    func anOutgoingCallHeldDuringJoinStillAcceptsThePeersDecline() async throws {
        let rtcSession = makeRTCSession()
        let gate = Gate()
        rtcSession.joinEncryptMediaNotificationMediaClosure = { _, _, _ in
            await gate.wait()
            return .success(())
        }
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: true,
                                        configuration: .init(media: .audio, scope: .direct),
                                        transport: makeTransport())
        let task = Task { await session.start() }
        try await waitUntil { rtcSession.joinEncryptMediaNotificationMediaCallsCount == 1 }
        session.setOnHold(true)
        gate.open()
        await task.value

        #expect(session.state == .onHold)
        await session.remoteDeclined()
        #expect(session.state == .ended(reason: .declined))
        await session.stop()
    }

    // MARK: - Calling one's own assistant (operator report 2026-09-11)

    private let assistantIdentity = "@assistant-alice:matrix.org:AGENT"

    /// The assistant answers the way the runtime does on prod: its
    /// `m.call.member` lands (the MatrixRTC update), then its media arrives
    /// on the transport a second later.
    private func assistantAnswers(rtc: PassthroughSubject<MatrixRTCSessionUpdate, Never>,
                                  transport: NativeCallTransportMock,
                                  events: PassthroughSubject<NativeCallTransportEvent, Never>,
                                  hasAgentKind: Bool = true) {
        rtc.send(.participantsChanged([.init(userID: "@assistant-alice:matrix.org",
                                             deviceID: "AGENT",
                                             identity: assistantIdentity)]))
        transport.remoteParticipants = [.init(identity: assistantIdentity,
                                              isSpeaking: false,
                                              isAudioEnabled: true,
                                              isAgent: hasAgentKind)]
        events.send(.participantsUpdated)
    }

    /// The DM's other member is the agent. It answers within seconds — its
    /// membership, then its SFU presence — and that must promote the ring to
    /// a conversation, exactly as a human peer's presence does. It rang
    /// until the no-answer timeout on the phone, because presence had been
    /// made human-only to stop a TRANSLATING agent from answering on a
    /// human's behalf.
    @Test
    func theAssistantAnsweringItsOwnDMPromotesTheRing() async throws {
        let rtcSession = makeRTCSession()
        let rtcUpdates = PassthroughSubject<MatrixRTCSessionUpdate, Never>()
        rtcSession.underlyingUpdates = rtcUpdates.eraseToAnyPublisher()
        let transport = makeTransport()
        let events = PassthroughSubject<NativeCallTransportEvent, Never>()
        transport.underlyingEvents = events.eraseToAnyPublisher()
        transport.connectUrlTokenClosure = { _, _ in }
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: true,
                                        configuration: .init(media: .audio, scope: .assistant),
                                        transport: transport)
        await session.start()
        #expect(session.state == .ringing)

        assistantAnswers(rtc: rtcUpdates, transport: transport, events: events)
        try await waitUntil { session.state == .connected }

        #expect(session.state == .connected)
        await session.stop()
    }

    /// Walk 2026-10-11: the DM with one's own assistant carries no member
    /// hints since backend `02043c5e`. Routed off that room, the agent's
    /// authorized media must still answer the ring — it rang out at 30 s.
    /// Review 2026-10-11: even when its participant arrives with a standard
    /// kind and no `spiral.agent.state` document yet — the namespace says.
    @Test
    func theAssistantAnswersItsOwnDMThatHasNoMemberHints() async throws {
        let roomInfo = RoomInfoProxyMock()
        roomInfo.isDirect = true
        roomInfo.isDM = true
        roomInfo.isSpace = false
        roomInfo.joinedMembersCount = 2
        roomInfo.activeServiceMembersCount = 0
        roomInfo.serviceMembers = []
        roomInfo.heroes = [RoomHero(userId: "@assistant-alice:matrix.org", displayName: nil, avatarUrl: nil, status: nil, call: nil)]
        roomInfo.joinRule = .invite
        let configuration = NativeCallConfiguration(media: .audio, roomInfo: roomInfo, members: [], ownUserID: "@alice:matrix.org")
        #expect(configuration.scope == .assistant)

        let rtcSession = makeRTCSession()
        let rtcUpdates = PassthroughSubject<MatrixRTCSessionUpdate, Never>()
        rtcSession.underlyingUpdates = rtcUpdates.eraseToAnyPublisher()
        let transport = makeTransport()
        let events = PassthroughSubject<NativeCallTransportEvent, Never>()
        transport.underlyingEvents = events.eraseToAnyPublisher()
        transport.connectUrlTokenClosure = { _, _ in }
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: true,
                                        configuration: configuration,
                                        transport: transport)
        await session.start()
        #expect(session.state == .ringing)

        assistantAnswers(rtc: rtcUpdates, transport: transport, events: events, hasAgentKind: false)
        try await waitUntil { session.state == .connected }

        #expect(session.state == .connected)
        #expect(session.participants.first { $0.userID == "@assistant-alice:matrix.org" }?.role == .agent)
        await session.stop()
    }

    /// The control: a DM with a HUMAN whose agent attaches for translation.
    /// The agent joins two seconds in; the ring must go on until the human
    /// answers — the rule this fix must not undo.
    @Test
    func aTranslatingAgentDoesNotAnswerAHumansDM() async throws {
        let rtcSession = makeRTCSession()
        let rtcUpdates = PassthroughSubject<MatrixRTCSessionUpdate, Never>()
        rtcSession.underlyingUpdates = rtcUpdates.eraseToAnyPublisher()
        let transport = makeTransport()
        let events = PassthroughSubject<NativeCallTransportEvent, Never>()
        transport.underlyingEvents = events.eraseToAnyPublisher()
        transport.connectUrlTokenClosure = { _, _ in }
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: true,
                                        configuration: .init(media: .audio, scope: .direct),
                                        transport: transport)
        await session.start()
        #expect(session.state == .ringing)

        assistantAnswers(rtc: rtcUpdates, transport: transport, events: events)
        try await Task.sleep(for: .milliseconds(100))

        #expect(session.state == .ringing, "an attached agent must not answer for the human")
        await session.stop()
    }

    /// And when the assistant leaves its own DM call, the call ends — the
    /// user must not sit in an empty room with the ringback long gone.
    @Test
    func theAssistantLeavingItsOwnDMEndsTheCall() async throws {
        let rtcSession = makeRTCSession()
        let rtcUpdates = PassthroughSubject<MatrixRTCSessionUpdate, Never>()
        rtcSession.underlyingUpdates = rtcUpdates.eraseToAnyPublisher()
        let transport = makeTransport()
        let events = PassthroughSubject<NativeCallTransportEvent, Never>()
        transport.underlyingEvents = events.eraseToAnyPublisher()
        transport.connectUrlTokenClosure = { _, _ in }
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: true,
                                        configuration: .init(media: .audio, scope: .assistant),
                                        transport: transport)
        await session.start()
        assistantAnswers(rtc: rtcUpdates, transport: transport, events: events)
        try await waitUntil { session.state == .connected }

        rtcUpdates.send(.participantsChanged([]))
        transport.remoteParticipants = []
        events.send(.participantsUpdated)
        try await waitUntil { session.state == .ended(reason: .remoteEnded) }

        #expect(session.state == .ended(reason: .remoteEnded))
    }

    // MARK: - Audit 2026-09-05 (Brief 0067 follow-up)

    /// Hang-up used to leave the microphone publishing through the end tone
    /// and the bounded Matrix leave — up to ~4.6 s of hot mic after the
    /// screen had gone. The first thing a hang-up does now is stop local
    /// media; the leave and the disconnect come after.
    @Test
    func hangUpMutesLocalMediaBeforeLeavingTheRoom() async throws {
        let rtcSession = makeRTCSession()
        let transport = makeTransport()
        transport.connectUrlTokenClosure = { _, _ in }
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)
        await session.start()
        #expect(session.state == .connected)
        transport.underlyingIsMicrophoneEnabled = true

        // Gate the Matrix leave so we can observe the order of operations.
        let leaveGate = Gate()
        rtcSession.leaveClosure = { await leaveGate.wait(); return .success(()) }
        let stopTask = Task { await session.stop() }
        try await waitUntil { rtcSession.leaveCallsCount == 1 }

        #expect(transport.setMicrophoneEnabledReceivedInvocations.last == false,
                "the microphone must be off before the Matrix leave starts, not after the transport disconnect")
        #expect(transport.disconnectCallsCount == 0, "the disconnect still comes after the leave")

        leaveGate.open()
        await stopTask.value
        #expect(session.state == .ended(reason: .userHungUp))
        #expect(transport.disconnectCallsCount == 1)
    }

    /// Operator, 2026-09-07, on the phone: crackling after every ANSWERED
    /// call, never after a ring hung up mid-ringback. The device log had
    /// 741 "The call microphone refused a CallKit mute change" lines in
    /// three hang-ups, 16 ms apart: CallKit re-issues a FAILED mute action
    /// every audio frame, and each retry toggled the live engine. A mute
    /// during teardown is already true and must say so.
    @Test
    func aMuteAskedOfAnEndingCallIsAlreadyTrueAndAnUnmuteIsRefused() async throws {
        let rtcSession = makeRTCSession()
        let transport = makeTransport()
        transport.connectUrlTokenClosure = { _, _ in }
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)
        await session.start()

        let leaveGate = Gate()
        rtcSession.leaveClosure = { await leaveGate.wait(); return .success(()) }
        let stopTask = Task { await session.stop() }
        try await waitUntil { rtcSession.leaveCallsCount == 1 }
        let microphoneCalls = transport.setMicrophoneEnabledCallsCount

        #expect(await session.setMicrophoneEnabled(false), "the microphone is already silent")
        #expect(await !(session.setMicrophoneEnabled(true)), "nothing may start publishing again")
        #expect(transport.setMicrophoneEnabledCallsCount == microphoneCalls,
                "neither answer may touch the transport under teardown")

        leaveGate.open()
        await stopTask.value
        #expect(await session.setMicrophoneEnabled(false))
    }

    /// Operator, 2026-09-07: "the end tones, then crackling after the call".
    /// The engine was parked only after the transport had pulled its tracks
    /// out from under the running voice-processing unit — and the end cue
    /// played through that unit, which ducks it. The engine is parked at the
    /// hang-up point now: before the cue, before the leave, before the
    /// disconnect.
    @Test
    func hangUpParksTheEngineBeforeTheEndCueAndTheTransportTeardown() async throws {
        let rtcSession = makeRTCSession()
        let transport = makeTransport()
        transport.connectUrlTokenClosure = { _, _ in }
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)
        await session.start()
        NativeCallAudio.callKitDidActivate()
        #expect(NativeCallAudio.isEngineAvailable)

        let leaveGate = Gate()
        rtcSession.leaveClosure = { await leaveGate.wait(); return .success(()) }
        let stopTask = Task { await session.stop() }
        try await waitUntil { rtcSession.leaveCallsCount == 1 }
        #expect(!NativeCallAudio.isEngineAvailable,
                "the engine must be parked before the Matrix leave, i.e. before the transport is torn down")
        #expect(transport.disconnectCallsCount == 0)

        leaveGate.open()
        await stopTask.value
        #expect(session.state == .ended(reason: .userHungUp))
    }

    /// The GSM call's audio interruption can land before CallKit's hold
    /// action. CallKit's hold must still be recorded, or the interruption's
    /// end resumes the call under the other one — microphone open to the
    /// peers, silent to the user.
    @Test
    func aCallKitHoldOnAnAlreadyInterruptedCallStillLatches() async throws {
        let rtcSession = makeRTCSession()
        let transport = makeTransport()
        transport.connectUrlTokenClosure = { _, _ in }
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)
        await session.start()
        #expect(session.state == .connected)

        // The interruption holds the call first, then CallKit says hold.
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification,
                                        object: nil,
                                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        try await waitUntil { session.state == .onHold }
        session.setOnHold(true)

        // The interruption ends while CallKit still holds: no resume.
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification,
                                        object: nil,
                                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        try await Task.sleep(for: .milliseconds(50))
        #expect(session.state == .onHold, "CallKit's hold outlives the interruption")
        #expect(transport.announceHoldReceivedInvocations == [true], "no resume was announced to the peers")

        session.setOnHold(false)
        #expect(session.state == .connected)
        await session.stop()
    }

    /// A call held behind another (call waiting) is ending while the OTHER
    /// call is on the engine: its hang-up must leave the engine alone.
    @Test
    func aHeldCallHangingUpLeavesTheEngineToTheActiveCall() async {
        let rtcSession = makeRTCSession()
        let transport = makeTransport()
        transport.connectUrlTokenClosure = { _, _ in }
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)
        await session.start()
        session.setOnHold(true)
        // The call in front holds the audio too (its session's claim and
        // CallKit's), so this session's own release is not the last one.
        let callInFront = NativeCallAudio.configureForCallKitActivation()
        NativeCallAudio.callKitDidActivate()
        #expect(NativeCallAudio.isEngineAvailable)

        await session.stop()
        #expect(NativeCallAudio.isEngineAvailable,
                "the engine belongs to the call in front; the held one's teardown must not park it")
        NativeCallAudio.releaseAfterCallKit(owner: callInFront)
    }

    /// The timeout-winning twin of `hangUpDuringConnectDoesNotResurrectTheCall`:
    /// `bounded()` gives up on the connect, `failStart` runs with
    /// `isConnected == false` and skips the transport teardown — and the
    /// connect then SUCCEEDS with nobody owning it. The work that can finish
    /// late owns its own cleanup now.
    @Test
    func connectFinishingAfterItsTimeoutIsDisconnected() async throws {
        let rtcSession = makeRTCSession()
        let transport = makeTransport()
        let gate = Gate()
        transport.connectUrlTokenClosure = { _, _ in await gate.wait() }
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport,
                                        transportConnectTimeout: .milliseconds(100))
        await session.start()
        guard case .ended(.failed) = session.state else {
            Issue.record("the timed-out connect must fail the start, got \(session.state)")
            return
        }
        #expect(transport.disconnectCallsCount == 0, "nothing was connected when the start failed")

        gate.open()
        try await waitUntil { transport.disconnectCallsCount == 1 }
        #expect(transport.setMicrophoneEnabledCallsCount == 0,
                "a connection nobody owns must never publish the microphone")
        if case .ended(.failed) = session.state {} else {
            Issue.record("the late connect must not overwrite the terminal state")
        }
    }

    /// Same hole on the rejoin path: the reconnect's bounded connect times
    /// out, `stop(.connectionLost)` tears down the torn transport, then the
    /// connect completes into a session that already ended.
    @Test
    func rejoinConnectFinishingAfterItsTimeoutIsDisconnected() async throws {
        let rtcSession = makeRTCSession()
        let transport = makeTransport()
        let events = PassthroughSubject<NativeCallTransportEvent, Never>()
        transport.underlyingEvents = events.eraseToAnyPublisher()
        transport.connectUrlTokenClosure = { _, _ in }
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport,
                                        transportConnectTimeout: .milliseconds(100))
        await session.start()
        #expect(session.state == .connected)

        let gate = Gate()
        transport.connectUrlTokenClosure = { _, _ in await gate.wait() }
        events.send(.didDisconnect(error: "test: transport dropped"))
        try await waitUntil { transport.connectUrlTokenCallsCount == 2 }
        try await waitUntil { session.state == .ended(reason: .connectionLost) }
        let disconnectsAtTimeout = transport.disconnectCallsCount

        gate.open()
        try await waitUntil { transport.disconnectCallsCount > disconnectsAtTimeout }
        #expect(session.state == .ended(reason: .connectionLost))
        #expect(transport.setMicrophoneEnabledReceivedInvocations.filter { $0 }.count == 1,
                "the late rejoin must not republish the microphone (one publish: the original start)")
    }

    // MARK: - Hold visible to the peer (Brief 0068 Slice 1)

    /// A hold mutes the publications and tells the room; the resume tells
    /// the room and restores the exact intent — a microphone the user had
    /// muted BEFORE the hold must not come back on.
    @Test
    func aHoldMutesAndAnnouncesAndTheResumeRestoresTheIntent() async throws {
        let transport = makeTransport()
        transport.connectUrlTokenClosure = { _, _ in }
        transport.setMicrophoneEnabledClosure = { enabled in transport.underlyingIsMicrophoneEnabled = enabled }
        transport.setCameraEnabledClosure = { enabled in transport.underlyingIsCameraEnabled = enabled }
        let session = NativeCallSession(rtcSession: makeRTCSession(),
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)
        await session.start()
        #expect(session.state == .connected)
        #expect(transport.isMicrophoneEnabled)

        session.setOnHold(true)
        try await waitUntil { transport.announceHoldReceivedInvocations == [true] }
        #expect(!transport.isMicrophoneEnabled, "held: the microphone publication is muted underneath")

        session.setOnHold(false)
        try await waitUntil { transport.announceHoldReceivedInvocations == [true, false] }
        try await waitUntil { transport.isMicrophoneEnabled }

        // Muted before the hold → still muted after the resume.
        await session.setMicrophoneEnabled(false)
        session.setOnHold(true)
        try await waitUntil { transport.announceHoldReceivedInvocations.count == 3 }
        session.setOnHold(false)
        try await waitUntil { transport.announceHoldReceivedInvocations.count == 4 }
        // start: on; hold 1: off; resume 1: on; user: off; hold 2 + resume 2: nothing.
        #expect(transport.setMicrophoneEnabledReceivedInvocations == [true, false, true, false],
                "the resume restores the user's intent, not \"on\"")
        #expect(!transport.isMicrophoneEnabled)
        await session.stop()
    }

    /// The other way into a hold — a GSM call taking the audio session —
    /// must tell the peers too, and our own row says "On hold", not
    /// "muted", for the duration.
    @Test
    func anAudioInterruptionAnnouncesTheHoldAndMarksTheLocalRow() async throws {
        let transport = makeTransport()
        transport.connectUrlTokenClosure = { _, _ in }
        transport.setMicrophoneEnabledClosure = { enabled in transport.underlyingIsMicrophoneEnabled = enabled }
        let session = NativeCallSession(rtcSession: makeRTCSession(),
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)
        await session.start()
        #expect(session.state == .connected)

        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification,
                                        object: nil,
                                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        try await waitUntil { transport.announceHoldReceivedInvocations == [true] }
        #expect(session.state == .onHold)
        #expect(session.participants.first(where: \.isLocal)?.isOnHold == true,
                "our own row reads \"On hold\", never a mute the user did not make")

        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification,
                                        object: nil,
                                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        try await waitUntil { transport.announceHoldReceivedInvocations == [true, false] }
        try await waitUntil { transport.isMicrophoneEnabled }
        #expect(session.participants.first(where: \.isLocal)?.isOnHold == false)
        await session.stop()
    }

    /// A hold that begins while the connect is still in flight has nobody
    /// to tell; the join that then publishes a microphone into the held
    /// call must mute it and announce — the peer never saw a live mic.
    @Test
    func aJoinFinishingUnderAHoldMutesAndAnnounces() async throws {
        let transport = makeTransport()
        let gate = Gate()
        transport.connectUrlTokenClosure = { _, _ in await gate.wait() }
        transport.setMicrophoneEnabledClosure = { enabled in transport.underlyingIsMicrophoneEnabled = enabled }
        let session = NativeCallSession(rtcSession: makeRTCSession(),
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)
        let task = Task { await session.start() }
        try await waitUntil { transport.connectUrlTokenCallsCount == 1 }
        session.setOnHold(true)
        #expect(transport.announceHoldCallsCount == 0, "nothing connected: nothing to announce yet")

        gate.open()
        await task.value
        try await waitUntil { transport.announceHoldReceivedInvocations == [true] }
        #expect(session.state == .onHold)
        #expect(!transport.isMicrophoneEnabled, "the just-published microphone is muted under the hold")
        session.setOnHold(false)
        try await waitUntil { transport.announceHoldReceivedInvocations == [true, false] }
        await session.stop()
    }

    // MARK: - Harness

    private func makeRTCSession() -> MatrixRTCSessionMock {
        let rtcSession = MatrixRTCSessionMock()
        rtcSession.underlyingOwnIdentity = "@alice:matrix.org:DEVICE"
        rtcSession.underlyingUpdates = Empty().eraseToAnyPublisher()
        rtcSession.joinEncryptMediaNotificationMediaReturnValue = .success(())
        rtcSession.setMediaReturnValue = .success(())
        rtcSession.rtcNotificationEventIDReturnValue = "$ring:matrix.org"
        rtcSession.transportCredentialsReturnValue = URL(string: "wss://rtc.example.org")
            .map { .success(.init(url: $0, token: "token", identity: "@alice:matrix.org:DEVICE")) }
        rtcSession.leaveReturnValue = .success(())
        rtcSession.membershipsReturnValue = .success([.init(userID: "@bob:matrix.org", deviceID: "BOB", identity: "@bob:matrix.org:BOB")])
        return rtcSession
    }

    private func makeTransport() -> NativeCallTransportMock {
        let transport = NativeCallTransportMock()
        transport.underlyingEvents = Empty().eraseToAnyPublisher()
        transport.localIdentity = "@alice:matrix.org:DEVICE"
        transport.remoteParticipants = []
        transport.remoteTracks = []
        transport.underlyingIsLocalSpeaking = false
        transport.underlyingLocalConnectionQuality = .unknown
        transport.underlyingIsMicrophoneEnabled = true
        transport.underlyingIsCameraEnabled = false
        transport.setSubscriptionsAuthorizedIdentitiesIsTrackExcludedClosure = { _, _ in true }
        transport.setEncryptionKeyIndexIdentityClosure = { _, _, _ in }
        return transport
    }

    /// Spin until `condition` holds, bounded so a regression fails the test
    /// instead of wedging the suite.
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<2000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("condition not reached within the wait budget")
    }
}

// MARK: - A call joined after its caller left (follow-up L1a)

extension NativeCallSessionTests {
    private static let bob = MatrixRTCParticipant(userID: "@bob:matrix.org", deviceID: "BOB", identity: "@bob:matrix.org:BOB")

    /// An answer joins without ringing. When the caller hung up after the
    /// answer's screen came up, nobody was ever there to leave, so the call
    /// sat connected and empty until the user hung up.
    @Test
    func anAnswerWhoseCallerIsGoneEnds() async throws {
        let session = NativeCallSession(rtcSession: makeRTCSession(),
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        isAnswer: true,
                                        configuration: .init(media: .audio, scope: .direct),
                                        transport: makeTransport(),
                                        peerWaitDuration: .milliseconds(100))

        await session.start()
        #expect(session.state == .connected)

        try await waitUntil { session.state == .ended(reason: .remoteEnded) }
    }

    /// The group twin: everyone the answer was joining has gone.
    @Test
    func aGroupAnswerWithNobodyLeftEnds() async throws {
        let session = NativeCallSession(rtcSession: makeRTCSession(),
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        isAnswer: true,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: makeTransport(),
                                        peerWaitDuration: .milliseconds(100))

        await session.start()

        try await waitUntil { session.state == .ended(reason: .everyoneLeft) }
    }

    /// A caller whose membership reaches us only after the media is up (a
    /// slow sync) is there: the wait must not end that answer. Their later
    /// hang-up ends it the usual way.
    @Test
    func aPeerSeenWithinTheWaitKeepsTheAnswer() async throws {
        let rtcSession = makeRTCSession()
        let rtcUpdates = PassthroughSubject<MatrixRTCSessionUpdate, Never>()
        rtcSession.underlyingUpdates = rtcUpdates.eraseToAnyPublisher()
        let transport = makeTransport()
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .direct),
                                        transport: transport,
                                        peerWaitDuration: .milliseconds(300))
        await session.start()

        rtcUpdates.send(.participantsChanged([Self.bob]))
        try await Task.sleep(for: .milliseconds(600))
        #expect(!hasBegunEnding(transport), "the caller is there")
        #expect(session.state == .connected)

        rtcUpdates.send(.participantsChanged([]))
        try await waitUntil { session.state == .ended(reason: .remoteEnded) }
    }

    /// A call this device starts waits for others as long as it rings (a
    /// DM) or for good (a group): nobody being there yet is not an end.
    @Test
    func aFreshGroupCallDoesNotWaitForAPeer() async throws {
        let transport = makeTransport()
        let session = NativeCallSession(rtcSession: makeRTCSession(),
                                        isRoomEncrypted: false,
                                        notifyRoom: true,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport,
                                        peerWaitDuration: .milliseconds(50))
        await session.start()
        try await Task.sleep(for: .milliseconds(300))

        #expect(!hasBegunEnding(transport))
        #expect(session.state == .connected)
        await session.stop()
    }
}

// MARK: - The peer wait counts anybody on the SFU (review of L1a)

extension NativeCallSessionTests {
    private static let mutedBobOnTheSFU = NativeCallTransportParticipant(identity: bob.identity, isSpeaking: false, isAudioEnabled: false)

    /// A stop has begun: the first thing it does to a connected call is mute
    /// it. Read rather than the state, which stays live through the end tone.
    private func hasBegunEnding(_ transport: NativeCallTransportMock) -> Bool {
        transport.setMicrophoneEnabledReceivedInvocations.contains(false)
    }

    /// A caller on the SFU whose membership has not synced (a cold launch
    /// from a VoIP push) and who is muted with the camera off is in the
    /// call. The leave rules' presence counts such a participant only with
    /// live media, so the wait ended the answer as `.remoteEnded`.
    @Test
    func aMutedCallerOnlyOnTheSFUKeepsTheAnswer() async throws {
        let transport = makeTransport()
        transport.remoteParticipants = [Self.mutedBobOnTheSFU]
        let session = NativeCallSession(rtcSession: makeRTCSession(),
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        isAnswer: true,
                                        configuration: .init(media: .audio, scope: .direct),
                                        transport: transport,
                                        peerWaitDuration: .milliseconds(100))
        await session.start()
        try await Task.sleep(for: .milliseconds(400))

        #expect(!hasBegunEnding(transport))
        #expect(session.state == .connected)
        await session.stop()
    }

    /// The leave rules never saw that caller, so when they go before their
    /// membership arrives, the wait starts over and ends the call.
    @Test
    func aCallerOnlyOnTheSFUWhoLeavesEndsTheCallAfterTheWait() async throws {
        let transport = makeTransport()
        let events = PassthroughSubject<NativeCallTransportEvent, Never>()
        transport.underlyingEvents = events.eraseToAnyPublisher()
        transport.remoteParticipants = [Self.mutedBobOnTheSFU]
        let session = NativeCallSession(rtcSession: makeRTCSession(),
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        isAnswer: true,
                                        configuration: .init(media: .audio, scope: .direct),
                                        transport: transport,
                                        peerWaitDuration: .milliseconds(100))
        await session.start()
        try await Task.sleep(for: .milliseconds(300))
        #expect(!hasBegunEnding(transport), "precondition: the caller keeps the call")

        transport.remoteParticipants = []
        events.send(.participantsUpdated)

        try await waitUntil { session.state == .ended(reason: .remoteEnded) }
    }
}

// MARK: - The peer wait and a reconnect (review of L1a)

extension NativeCallSessionTests {
    /// A full reconnect empties LiveKit's roster. A caller only on the SFU
    /// was then nobody, and the restarted wait ended the answer while the
    /// reconnect still had its budget. The wait sits out a reconnect and
    /// looks again once the transport is back.
    @Test
    func aReconnectDoesNotEndAnAnswerWhoseCallerIsOnlyOnTheSFU() async throws {
        let transport = makeTransport()
        let events = PassthroughSubject<NativeCallTransportEvent, Never>()
        transport.underlyingEvents = events.eraseToAnyPublisher()
        transport.remoteParticipants = [Self.mutedBobOnTheSFU]
        let session = NativeCallSession(rtcSession: makeRTCSession(),
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        isAnswer: true,
                                        configuration: .init(media: .audio, scope: .direct),
                                        transport: transport,
                                        peerWaitDuration: .milliseconds(100))
        await session.start()

        events.send(.isReconnecting)
        transport.remoteParticipants = []
        events.send(.participantsUpdated)
        try await Task.sleep(for: .milliseconds(400))
        #expect(session.state == .reconnecting)
        #expect(!hasBegunEnding(transport), "the caller cannot be seen while the transport is down")

        transport.remoteParticipants = [Self.mutedBobOnTheSFU]
        events.send(.didReconnect)
        try await Task.sleep(for: .milliseconds(400))
        #expect(session.state == .connected)
        #expect(!hasBegunEnding(transport), "the caller is back")

        transport.remoteParticipants = []
        events.send(.participantsUpdated)
        try await waitUntil { session.state == .ended(reason: .remoteEnded) }
    }
}

// MARK: - A room call that is only this device's own membership (review item 5)

extension NativeCallSessionTests {
    private static let ownLingeringMembership = MatrixRTCParticipant(userID: "@alice:matrix.org", deviceID: "DEVICE", identity: "@alice:matrix.org:DEVICE")

    /// The user hangs up and calls again before their leave has synced back:
    /// the room still shows a call, and its only membership is this device's
    /// own. That took the join path: no ring, and as a DM join the wait ended
    /// it after 10 s.
    @Test
    func aCallBackBeforeTheLeaveEchoesRingsTheRoom() async throws {
        let rtcSession = makeRTCSession()
        rtcSession.membershipsReturnValue = .success([Self.ownLingeringMembership])
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .direct),
                                        transport: makeTransport())

        await session.start()

        let join = try #require(rtcSession.joinEncryptMediaNotificationMediaReceivedArguments)
        #expect(join.notification == .ring)
        #expect(session.state == .ringing)
        await session.stop()
    }

    /// Another device of the same user in the call is somebody: this device
    /// joins without a ring.
    @Test
    func aSecondDeviceOfTheUserInTheCallIsJoinedWithoutARing() async throws {
        let rtcSession = makeRTCSession()
        rtcSession.membershipsReturnValue = .success([Self.ownLingeringMembership,
                                                      .init(userID: "@alice:matrix.org", deviceID: "PHONE", identity: "@alice:matrix.org:PHONE")])
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .direct),
                                        transport: makeTransport())

        await session.start()

        let join = try #require(rtcSession.joinEncryptMediaNotificationMediaReceivedArguments)
        #expect(join.notification == nil)
        #expect(session.state == .connected)
        await session.stop()
    }

    /// An answer never rings, whatever the room's state holds.
    @Test
    func anAnswerOnItsOwnMembershipStillDoesNotRing() async throws {
        let rtcSession = makeRTCSession()
        rtcSession.membershipsReturnValue = .success([Self.ownLingeringMembership])
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        isAnswer: true,
                                        configuration: .init(media: .audio, scope: .direct),
                                        transport: makeTransport())

        await session.start()

        let join = try #require(rtcSession.joinEncryptMediaNotificationMediaReceivedArguments)
        #expect(join.notification == nil)
        await session.stop()
    }
}

// MARK: - What the peer wait counts

extension NativeCallSessionTests {
    /// A caller already on the SFU with live media when ours comes up: the
    /// wait never runs.
    @Test
    func aCallerOnTheSFUAtStartNeverStartsTheWait() async throws {
        let transport = makeTransport()
        transport.remoteParticipants = [NativeCallTransportParticipant(identity: Self.bob.identity, isSpeaking: false, isAudioEnabled: true)]
        let session = NativeCallSession(rtcSession: makeRTCSession(),
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        isAnswer: true,
                                        configuration: .init(media: .audio, scope: .direct),
                                        transport: transport,
                                        peerWaitDuration: .milliseconds(100))
        await session.start()
        try await Task.sleep(for: .milliseconds(400))

        #expect(!hasBegunEnding(transport))
        #expect(session.state == .connected)
        await session.stop()
    }

    /// Media alone, with no membership yet, is somebody: it stops a wait
    /// that is running.
    @Test
    func mediaWithoutAMembershipStopsTheWait() async throws {
        let transport = makeTransport()
        let events = PassthroughSubject<NativeCallTransportEvent, Never>()
        transport.underlyingEvents = events.eraseToAnyPublisher()
        let session = NativeCallSession(rtcSession: makeRTCSession(),
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        isAnswer: true,
                                        configuration: .init(media: .audio, scope: .direct),
                                        transport: transport,
                                        peerWaitDuration: .milliseconds(300))
        await session.start()

        transport.remoteParticipants = [NativeCallTransportParticipant(identity: Self.bob.identity, isSpeaking: false, isAudioEnabled: true)]
        events.send(.participantsUpdated)
        try await Task.sleep(for: .milliseconds(700))

        #expect(!hasBegunEnding(transport))
        #expect(session.state == .connected)
        await session.stop()
    }
}

// MARK: - A joined group call waits for others (operator question 94)

extension NativeCallSessionTests {
    /// A group call this device joins rather than answers waits for others
    /// for good, as one it starts does.
    @Test
    func aJoinedGroupCallWithNobodyInItStays() async throws {
        let transport = makeTransport()
        let session = NativeCallSession(rtcSession: makeRTCSession(),
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport,
                                        peerWaitDuration: .milliseconds(100))
        await session.start()
        try await Task.sleep(for: .milliseconds(400))

        #expect(!hasBegunEnding(transport))
        #expect(session.state == .connected)
        await session.stop()
    }

    /// A DM joined, not answered, still ends when nobody is in it.
    @Test
    func aJoinedDMCallWithNobodyInItEnds() async throws {
        let session = NativeCallSession(rtcSession: makeRTCSession(),
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .direct),
                                        transport: makeTransport(),
                                        peerWaitDuration: .milliseconds(100))
        await session.start()

        try await waitUntil { session.state == .ended(reason: .remoteEnded) }
    }
}

/// A manually-opened suspension point for scripting "the call ended while
/// this step was in flight".
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if isOpen {
                    continuation.resume()
                } else {
                    continuations.append(continuation)
                }
            }
        }
    }

    func open() {
        lock.withLock {
            isOpen = true
            continuations.forEach { $0.resume() }
            continuations.removeAll()
        }
    }
}

@MainActor
private final class DelegateSpy: NativeCallSessionDelegate {
    private(set) var states: [NativeCallSessionState] = []

    func nativeCallSession(_ session: NativeCallSession, didChangeState state: NativeCallSessionState) {
        states.append(state)
    }

    func nativeCallSession(_ session: NativeCallSession, didChangeParticipants participants: [NativeCallParticipant]) { }
    func nativeCallSession(_ session: NativeCallSession, didSendRingNotification eventID: String) { }
    func nativeCallSession(_ session: NativeCallSession, didChangeListening listening: NativeCallListeningState) { }
    func nativeCallSession(_ session: NativeCallSession, didChangeVideoTiles tiles: [NativeCallVideoTile]) { }
    func nativeCallSessionDidChangeAgentState(_ session: NativeCallSession) { }
    func nativeCallSession(_ session: NativeCallSession, didChangeAgentClaims claims: NativeCallAgentClaims) { }
    func nativeCallSession(_ session: NativeCallSession, didChangeActiveVideo hasActiveVideo: Bool, isSpeakerEnabled: Bool) { }
    func nativeCallSession(_ session: NativeCallSession, didChangeConnectionQuality quality: NativeCallConnectionQuality) { }
}

/// Hold semantics (audit A5-5 and its CallKit twin).
///
/// Both hold paths — the AVAudioSession interruption and CallKit's own
/// `setOnHold` — recognised only `.connected`, so a hold arriving while the
/// call was still joining or recovering was dropped on the floor. That is
/// the window where losing the audio route matters MOST: the join is about
/// to publish a microphone the session no longer owns, and the user ends up
/// with a call that reports itself connected and carries no audio, with no
/// held state to resume from.
@MainActor
@Suite(.timeLimit(.minutes(2)))
struct NativeCallSessionHoldTests {
    @Test
    func aCallCanBeHeldWhileItIsStillConnecting() {
        #expect(NativeCallSessionState.connecting.canBeHeld,
                "an interruption during the join is the case that matters most")
        #expect(NativeCallSessionState.connected.canBeHeld)
        #expect(NativeCallSessionState.reconnecting.canBeHeld,
                "the reconnect window is up to 30s; a hold inside it must land")
    }

    @Test
    func terminalAndAlreadyHeldStatesRefuseAHold() {
        // Holding something already over is meaningless...
        #expect(!NativeCallSessionState.ended(reason: .userHungUp).canBeHeld)
        #expect(!NativeCallSessionState.ended(reason: .failed(.disconnected)).canBeHeld)
        // ...an outgoing call still ringing is excluded on purpose: it can
        // become `.connected` by itself, and restoring a remembered
        // `.ringing` afterwards would undo a join that landed while held.
        #expect(!NativeCallSessionState.ringing.canBeHeld)
        // ...and holding twice would overwrite the state we exist to restore,
        // which is how a resumed call would silently become `.connected`
        // when it had been `.connecting`.
        #expect(!NativeCallSessionState.onHold.canBeHeld)
    }
}

/// The subscription quality ladder: which simulcast layer each on-screen
/// video count asks for. A pure function so the policy is pinned without a
/// LiveKit room.
struct NativeCallVideoQualityLadderTests {
    @Test
    func fewVideosTakeTheTopLayer() {
        // The regression this replaces: a 3-way call's half-screen tiles
        // (2 remote videos) dropped to 640×360 upscaled to fill.
        #expect(LiveKitCallTransport.preferredVideoQuality(subscribedVideoCount: 0) == .high)
        #expect(LiveKitCallTransport.preferredVideoQuality(subscribedVideoCount: 1) == .high)
        #expect(LiveKitCallTransport.preferredVideoQuality(subscribedVideoCount: 2) == .high)
    }

    @Test
    func midGridsTakeMediumAndBigGridsTakeLow() {
        #expect(LiveKitCallTransport.preferredVideoQuality(subscribedVideoCount: 3) == .medium)
        #expect(LiveKitCallTransport.preferredVideoQuality(subscribedVideoCount: 4) == .medium)
        // Past four the tiles are small and the downlink otherwise grows
        // linearly with the roster.
        #expect(LiveKitCallTransport.preferredVideoQuality(subscribedVideoCount: 5) == .low)
        #expect(LiveKitCallTransport.preferredVideoQuality(subscribedVideoCount: 9) == .low)
    }
}
