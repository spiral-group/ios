//
// Copyright 2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation
import CallKit
import Clocks
import Combine
@testable import ElementX
import Intents
import MatrixRustSDKMocks
import PushKit
import Testing

// The TestClock advances by yielding to background tasks which can be starved on a busy CI runner.
@Suite(.timeLimit(.minutes(2)))
@MainActor
final class CallKitServiceTests {
    private var callProvider: CXProviderMock!
    private var currentDate: Date!
    private var testClock: TestClock<Duration>!
    private var pushRegistry: PKPushRegistry!
    private var callController: CXCallControllerMock!
    private var audio: NativeCallAudioControlSpy!
    private var service: CallKitService!
    
    init() {
        pushRegistry = PKPushRegistry(queue: nil)
        callProvider = CXProviderMock(.init())
        currentDate = Date()
        testClock = TestClock()
        callController = CXCallControllerMock()
        audio = NativeCallAudioControlSpy()
        service = CallKitService(callProvider: callProvider,
                                 callController: callController,
                                 timeProvider: TimeProvider(clock: testClock),
                                 audio: audio)
    }
    
    isolated deinit {
        callProvider = nil
        currentDate = nil
        testClock = nil
        pushRegistry = nil
        callController = nil
        audio = nil
    }
    
    @Test
    func incomingCall() async {
        #expect(!callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
        
        await waitForConfirmation { confirmation in
            let pkPushPayloadMock = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
            
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: pkPushPayloadMock, for: .voIP) {
                confirmation()
            }
        }
        
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
        // Verify the provider was called with a CXCallUpdate that has video enabled
        if let args = callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments {
            #expect(args.update.hasVideo == true)
        } else {
            Issue.record("Expected reportNewIncomingCallWithUpdateCompletionReceivedArguments to be captured")
        }
    }
    
    @Test
    func incomingVoiceCall() async {
        #expect(!callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
        
        await waitForConfirmation { confirmation in
            let pkPushPayloadMock = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
                .updateIsVoice(true)
            
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: pkPushPayloadMock, for: .voIP) {
                confirmation()
            }
        }
        
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
        // AGENT-PLATFORM (Brief 0067): a voice call is reported as one.
        // Upstream reports every call as video so the WebView gets
        // foregrounded; that workaround left with the widget (ADR-0079).
        if let args = callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments {
            #expect(args.update.hasVideo == false)
        } else {
            Issue.record("Expected reportNewIncomingCallWithUpdateCompletionReceivedArguments to be captured")
        }
    }

    @Test
    func incomingNativeVoiceCallUsesAudioCallKitPresentation() async {
        await waitForConfirmation { confirmation in
            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
                .updateIsVoice(true)

            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                confirmation()
            }
        }

        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.update.hasVideo == false)
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.update.remoteHandle?.value == "@tester:spiral.md")
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.update.localizedCallerName == "Tester")
    }

    @Test
    func answeringNativeVoiceCallKeepsIncomingCallKitSession() async throws {
        await waitForConfirmation { confirmation in
            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
                .updateIsVoice(true)

            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                confirmation()
            }
        }

        let (actions, continuation) = AsyncStream<CallKitServiceAction>.makeStream()
        let cancellable = service.actions.sink { continuation.yield($0) }
        let deferredAction = deferFulfillment(actions) {
            guard case .startCall = $0 else { return false }
            return true
        }
        let callID = try #require(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.uuid)

        service.provider(CXProvider(configuration: CXProviderConfiguration()), perform: CXAnswerCallAction(call: callID))

        let action = try await deferredAction.fulfill()
        guard case let .startCall(roomID, isVoiceCall) = action else {
            Issue.record("Expected a native startCall action")
            return
        }
        #expect(roomID == "!room:example.com")
        #expect(isVoiceCall)
        #expect(!callProvider.reportCallWithEndedAtReasonCalled)
        #expect(service.ongoingCallRoomIDPublisher.value == "!room:example.com")
        _ = cancellable
    }

    @Test
    func settingUpAnsweredNativeCallDoesNotStartOutgoingCallKitCall() async {
        await waitForConfirmation { confirmation in
            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
                .updateIsVoice(true)

            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                confirmation()
            }
        }

        let callID = callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.uuid
        if let callID {
            service.provider(CXProvider(configuration: CXProviderConfiguration()), perform: CXAnswerCallAction(call: callID))
        }

        await service.setupCallSession(roomID: "!room:example.com", roomDisplayName: "welcome", isVoiceCall: true)

        #expect(callController.requestedTransactions.isEmpty)
        #expect(service.ongoingCallRoomIDPublisher.value == "!room:example.com")
    }

    // MARK: - Call waiting between Spiral calls (Brief 0068 Slice 2)

    private func ring(room: String, notification: String) async throws -> UUID {
        let push = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30).updateIsVoice(true)
        push.dict[CallKitNotificationKey.roomID.rawValue] = room
        push.dict[CallKitNotificationKey.rtcNotifyEventID.rawValue] = notification
        await waitForConfirmation { confirmation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: push, for: .voIP) { confirmation() }
        }
        return try #require(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedInvocations.last).uuid
    }

    private func answer(_ callKitID: UUID) {
        service.provider(CXProvider(configuration: CXProviderConfiguration()), perform: CXAnswerCallAction(call: callKitID))
    }

    private func holdActions() -> [CXSetHeldCallAction] {
        callController.requestedTransactions.flatMap(\.actions).compactMap { $0 as? CXSetHeldCallAction }
    }

    /// Two answered calls: A live (its screen named the room), B answered
    /// from the CallKit banner.
    private func twoCalls() async throws -> (a: UUID, b: UUID) {
        let a = try await ring(room: "!a:example.com", notification: "$a")
        answer(a)
        await service.setupCallSession(roomID: "!a:example.com", roomDisplayName: "Room A", isVoiceCall: true)
        let b = try await ring(room: "!b:example.com", notification: "$b")
        answer(b)
        return (a, b)
    }

    /// Answering a second Spiral call used to END the first ("one call
    /// screen"). It holds it now: the first call is asked to hold through
    /// CallKit, nobody is told to end, both are tracked, and the pill names
    /// the room the held screen named, not the ring's guess.
    @Test
    func answeringASecondCallHoldsTheFirstInsteadOfEndingIt() async throws {
        var endsSeen = 0
        let cancellable = service.actions.sink { if case .endCall = $0 { endsSeen += 1 } }
        let (a, _) = try await twoCalls()

        #expect(service.ongoingCallRoomIDPublisher.value == "!b:example.com")
        #expect(service.heldCallPublisher.value == CallKitHeldCall(roomID: "!a:example.com", displayName: "Room A"))
        #expect(holdActions().contains { $0.callUUID == a && $0.isOnHold }, "the first call is held through CallKit")
        #expect(!callProvider.reportCallWithEndedAtReasonReceivedInvocations.contains { $0.uuid == a })
        #expect(endsSeen == 0, "nobody is told to end")
        _ = cancellable
    }

    /// The in-app fallback ring parks the live call at the TAP, not when
    /// the new screen registers seconds later — the flow coordinator reads
    /// the held slot when it presents the new screen.
    @Test
    func acceptingAnInAppRingParksTheLiveCallSynchronously() async throws {
        let a = try await ring(room: "!a:example.com", notification: "$a")
        answer(a)
        await service.setupCallSession(roomID: "!a:example.com", roomDisplayName: "Room A", isVoiceCall: true)
        _ = try await ring(room: "!b:example.com", notification: "$b")

        service.handleInAppRingDecision(roomID: "!b:example.com", accepted: true)

        #expect(service.heldCallPublisher.value?.roomID == "!a:example.com", "parked before setupCallSession")
        #expect(holdActions().contains { $0.callUUID == a && $0.isOnHold })
        await service.setupCallSession(roomID: "!b:example.com", roomDisplayName: "Room B", isVoiceCall: true)
        #expect(service.ongoingCallRoomIDPublisher.value == "!b:example.com")
        #expect(service.heldCallPublisher.value?.roomID == "!a:example.com", "the registration adopts the ring, the held slot stands")
    }

    /// Ending the active call brings the held one back — and asks CallKit
    /// to resume it, because CallKit will not on its own.
    @Test
    func endingTheActiveCallResumesTheHeldOne() async throws {
        let (a, b) = try await twoCalls()
        let (stream, continuation) = AsyncStream<CallKitServiceAction>.makeStream()
        let cancellable = service.actions.sink { continuation.yield($0) }
        let activeChanged = deferFulfillment(stream) {
            if case .activeCallChanged(let roomID) = $0 { return roomID == "!a:example.com" }
            return false
        }
        service.endCall(matching: b)
        _ = try await activeChanged.fulfill()

        #expect(service.ongoingCallRoomIDPublisher.value == "!a:example.com")
        #expect(service.heldCallPublisher.value == nil)
        #expect(holdActions().contains { $0.callUUID == a && !$0.isOnHold }, "the held call is resumed through CallKit")
        _ = cancellable
    }

    /// The system UI's swap sends hold(B) + unhold(A) in ONE transaction and
    /// CallKit may deliver them in either order: exactly one active-call
    /// change, and the slots end up A active / B held both ways.
    @Test
    func aSystemSwapPromotesTheHeldCallInEitherOrder() async throws {
        for unholdFirst in [false, true] {
            let (a, b) = try await twoCalls()
            var changes = [String]()
            let cancellable = service.actions.sink { if case .activeCallChanged(let roomID) = $0 { changes.append(roomID) } }
            let provider = CXProvider(configuration: CXProviderConfiguration())
            let hold = CXSetHeldCallAction(call: b, onHold: true)
            let unhold = CXSetHeldCallAction(call: a, onHold: false)
            for action in unholdFirst ? [unhold, hold] : [hold, unhold] {
                service.provider(provider, perform: action)
            }
            #expect(changes == ["!a:example.com"], "unholdFirst=\(unholdFirst)")
            #expect(service.ongoingCallRoomIDPublisher.value == "!a:example.com")
            #expect(service.heldCallPublisher.value == CallKitHeldCall(roomID: "!b:example.com", displayName: "Tester"),
                    "the ring's own name until its screen names the room")
            _ = cancellable
            service.tearDownCallSession(forRoomID: nil)
        }
    }

    /// Declining the second ring leaves the first call exactly as it was —
    /// the W6-5-4 guarantee, now with a held slot in the picture.
    @Test
    func decliningASecondRingLeavesTheFirstCallUntouched() async throws {
        let a = try await ring(room: "!a:example.com", notification: "$a")
        answer(a)
        await service.setupCallSession(roomID: "!a:example.com", roomDisplayName: "Room A", isVoiceCall: true)
        let b = try await ring(room: "!b:example.com", notification: "$b")

        service.endCall(matching: b)

        #expect(service.ongoingCallRoomIDPublisher.value == "!a:example.com")
        #expect(service.heldCallPublisher.value == nil)
        #expect(!callProvider.reportCallWithEndedAtReasonReceivedInvocations.contains { $0.uuid == a })
    }

    /// Ending the HELD call from the system UI leaves the active one alone.
    @Test
    func endingTheHeldCallLeavesTheActiveOneAlone() async throws {
        let (a, _) = try await twoCalls()
        let (stream, continuation) = AsyncStream<CallKitServiceAction>.makeStream()
        let cancellable = service.actions.sink { continuation.yield($0) }
        let endA = deferFulfillment(stream) {
            if case .endCall(let roomID) = $0 { return roomID == "!a:example.com" }
            return false
        }
        service.endCall(matching: a)
        _ = try await endA.fulfill()

        #expect(service.ongoingCallRoomIDPublisher.value == "!b:example.com")
        #expect(service.heldCallPublisher.value == nil)
        _ = cancellable
    }

    /// An UNSCOPED teardown (sign-out, a provider reset) ends BOTH calls —
    /// it must never promote and resume the parked one.
    @Test
    func anUnscopedTeardownEndsTheHeldCallToo() async throws {
        let (a, _) = try await twoCalls()
        var ended = [String]()
        var changes = 0
        let cancellable = service.actions.sink {
            if case .endCall(let roomID) = $0 { ended.append(roomID) }
            if case .activeCallChanged = $0 { changes += 1 }
        }

        service.tearDownCallSession(forRoomID: nil)

        #expect(ended.contains("!a:example.com"), "the held call is told to end")
        #expect(changes == 0, "nothing is promoted on the way out")
        #expect(service.heldCallPublisher.value == nil)
        #expect(service.ongoingCallRoomIDPublisher.value == nil)
        let endActions = callController.requestedTransactions.flatMap(\.actions).compactMap { $0 as? CXEndCallAction }
        #expect(endActions.contains { $0.callUUID == a }, "CallKit is told the held call ended")
        _ = cancellable
    }

    /// An outgoing call while A is active and B held replaces BOTH — the
    /// room screen's call button is live for any other room, so this is
    /// reachable; B must not be left un-held and untracked.
    @Test
    func anOutgoingCallReplacesBothLiveCalls() async throws {
        _ = try await twoCalls()
        var ended = [String]()
        let cancellable = service.actions.sink { if case .endCall(let roomID) = $0 { ended.append(roomID) } }

        await service.setupCallSession(roomID: "!c:example.com", roomDisplayName: "Room C", isVoiceCall: true)

        #expect(ended.contains("!a:example.com"), "the held call is ended, not resumed")
        #expect(service.ongoingCallRoomIDPublisher.value == "!c:example.com")
        #expect(service.heldCallPublisher.value == nil)
        _ = cancellable
    }

    /// CallKit fulfils its mute action on the media stack's answer. Fulfilling
    /// it before the answer even started is what left the system call UI
    /// showing "muted" over a microphone that was still publishing.
    @Test
    func aCallKitMuteIsAnsweredOnlyOnceTheMicrophoneReports() async throws {
        await service.setupCallSession(roomID: "!room:example.com",
                                       roomDisplayName: "Tester",
                                       isVoiceCall: true)

        var reply: CallKitActionReply?
        let cancellable = service.actions.sink { action in
            if case .setAudioEnabled(_, _, let actionReply) = action {
                reply = actionReply
            }
        }
        defer { cancellable.cancel() }

        var outcomes: [Bool] = []
        service.setMuted(true) { outcomes.append($0) }

        #expect(outcomes.isEmpty, "the CallKit action must not be completed before the microphone answers")

        try #require(reply).send(false)
        #expect(outcomes == [false], "a refused mute must fail its action, not fulfil it")
    }

    /// Nobody answering must not leave CallKit waiting either — and the
    /// default answer is failure, because a mute we cannot prove happened must
    /// never be shown as done.
    @Test
    func anUnansweredCallKitMuteFailsItsAction() async {
        await service.setupCallSession(roomID: "!room:example.com",
                                       roomDisplayName: "Tester",
                                       isVoiceCall: true)

        var outcomes: [Bool] = []
        service.setMuted(true) { outcomes.append($0) }

        await waitForScheduledSleep()
        await testClock.advance(by: .seconds(5))
        for _ in 0..<3 {
            await Task.yield()
        }

        #expect(outcomes == [false])
    }

    /// A mute for a call that is no longer there is a no-op, and a no-op is
    /// fulfilled: failing it made CallKit re-issue the action every audio
    /// frame (the retry storm behind the post-call crackle, 2026-09-07).
    @Test
    func aCallKitMuteWithoutAnOngoingCallIsFulfilledAsANoOp() {
        var outcomes: [Bool] = []
        service.setMuted(true) { outcomes.append($0) }

        #expect(outcomes == [true])
    }

    @Test
    func outgoingNativeCallUsesRoomIDAsCallKitHandle() async throws {
        await service.setupCallSession(roomID: "!room:example.com", roomDisplayName: "Tester", isVoiceCall: true)

        let transaction = try #require(callController.requestedTransactions.first)
        let action = try #require(transaction.actions.first as? CXStartCallAction)
        #expect(action.handle.value == "!room:example.com")

        let update = try #require(callProvider.reportCallWithUpdatedReceivedArguments?.update)
        #expect(update.remoteHandle?.value == "!room:example.com")
        #expect(update.localizedCallerName == "Tester")
        #expect(update.hasVideo == false)
    }

    @Test
    func activeCallVideoMetadataChangesInBothDirections() async throws {
        let callKitID = await service.setupCallSession(roomID: "!room:example.com", roomDisplayName: "Tester", isVoiceCall: true)

        service.updateCallVideoState(hasVideo: true, callKitID: callKitID)
        var update = try #require(callProvider.reportCallWithUpdatedReceivedArguments?.update)
        #expect(update.hasVideo)
        #expect(update.localizedCallerName == "Tester")
        #expect(update.remoteHandle?.value == "!room:example.com")

        service.updateCallVideoState(hasVideo: false, callKitID: callKitID)
        update = try #require(callProvider.reportCallWithUpdatedReceivedArguments?.update)
        #expect(!update.hasVideo)
    }

    @Test
    func outgoingNativeCallConnectsOnlyWhenReported() async {
        await service.setupCallSession(roomID: "!room:example.com", roomDisplayName: "Tester", isVoiceCall: true)

        // While ringing the call is connecting; the system timer must not run yet.
        #expect(callProvider.reportOutgoingCallWithStartedConnectingAtCalled)
        #expect(!callProvider.reportOutgoingCallWithConnectedAtCalled)

        service.reportOutgoingCallConnected(roomID: "!room:example.com")
        #expect(callProvider.reportOutgoingCallWithConnectedAtCalled)

        // A second report must not restart the timer.
        service.reportOutgoingCallConnected(roomID: "!room:example.com")
        #expect(callProvider.reportOutgoingCallWithConnectedAtCallsCount == 1)
    }

    /// Audit 2026-09-05 (P2): the peer answers while `setupCallSession` is
    /// still inside `callController.request`. The connected report used to
    /// fail its guard (nothing pending yet) and was never retried, so CallKit
    /// stayed at "connecting" for a call the app showed as live.
    @Test
    func aConnectionReportedDuringCallKitSetupLandsOnceSetupCatchesUp() async throws {
        let gate = LookupGate()
        callController.requestGate = gate
        let setup = Task { await service.setupCallSession(roomID: "!room:example.com", roomDisplayName: "Tester", isVoiceCall: true) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(!callProvider.reportOutgoingCallWithStartedConnectingAtCalled, "precondition: setup is suspended in the request")

        // The peer answers now.
        service.reportOutgoingCallConnected(roomID: "!room:example.com")
        #expect(!callProvider.reportOutgoingCallWithConnectedAtCalled, "nothing to report against yet")

        gate.open()
        await setup.value

        #expect(callProvider.reportOutgoingCallWithStartedConnectingAtCalled)
        #expect(callProvider.reportOutgoingCallWithConnectedAtCallsCount == 1,
                "the early answer is honoured exactly once, after CallKit knows the call")
    }

    @Test
    func outgoingConnectionReportIgnoresOtherRooms() async {
        await service.setupCallSession(roomID: "!room:example.com", roomDisplayName: "Tester", isVoiceCall: true)
        service.reportOutgoingCallConnected(roomID: "!other:example.com")

        #expect(!callProvider.reportOutgoingCallWithConnectedAtCalled)
    }

    @Test
    func donatedCallIntentResolvesRoomIDFromCustomIdentifier() throws {
        let handle = INPersonHandle(value: "@tester:spiral.md", type: .unknown)
        let person = INPerson(personHandle: handle,
                              nameComponents: nil,
                              displayName: "Tester",
                              image: nil,
                              contactIdentifier: nil,
                              customIdentifier: "!zwjWNJioalQOdYtyHa:spiral.md")
        let intent = INStartCallIntent(callRecordFilter: nil,
                                       callRecordToCallBack: nil,
                                       audioRoute: .unknown,
                                       destinationType: .normal,
                                       contacts: [person],
                                       callCapability: .audioCall)

        let details = try #require(AppCoordinator.callDetails(for: intent))
        #expect(details.roomID == "!zwjWNJioalQOdYtyHa:spiral.md")
        #expect(details.isVoiceCall)
    }

    @Test
    func callBackResolvesModernRoomIDFromHandle() throws {
        // Calling back from Recents rebuilds the intent from the CallKit handle
        // alone, and an outgoing call's handle is the room ID. From room version
        // 12 that ID has no homeserver part, which must still resolve.
        let roomID = "!HAeQ7vXbo3RaJnKgJyLKfsHZ0OQ8xW7lM3nBvCzQpUY"
        let person = INPerson(personHandle: .init(value: roomID, type: .unknown),
                              nameComponents: nil,
                              displayName: "Tester",
                              image: nil,
                              contactIdentifier: nil,
                              customIdentifier: nil)
        let intent = INStartCallIntent(callRecordFilter: nil,
                                       callRecordToCallBack: nil,
                                       audioRoute: .unknown,
                                       destinationType: .normal,
                                       contacts: [person],
                                       callCapability: .videoCall)

        let details = try #require(AppCoordinator.callDetails(for: intent))
        #expect(details.roomID == roomID)
        #expect(!details.isVoiceCall)
    }

    @Test
    func callBackResolvesRoomIDFromCallerHandle() throws {
        let callerID = "@tester:spiral.md"
        CallKitRoomRouting.store(roomID: "!zwjWNJioalQOdYtyHa:spiral.md", for: callerID)
        let person = INPerson(personHandle: .init(value: callerID, type: .unknown),
                              nameComponents: nil,
                              displayName: "Tester",
                              image: nil,
                              contactIdentifier: nil,
                              customIdentifier: nil)
        let intent = INStartCallIntent(callRecordFilter: nil,
                                       callRecordToCallBack: nil,
                                       audioRoute: .unknown,
                                       destinationType: .normal,
                                       contacts: [person],
                                       callCapability: .unknown)

        let details = try #require(AppCoordinator.callDetails(for: intent))
        #expect(details.roomID == "!zwjWNJioalQOdYtyHa:spiral.md")
        #expect(details.isVoiceCall)
    }
    
    @Test(.disabled())
    func callIsTimingOut() async {
        #expect(!callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
        
        await confirmation { confirmation in
            let pushPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 20)
            
            service.pushRegistry(pushRegistry,
                                 didReceiveIncomingPushWith: pushPayload,
                                 for: .voIP) {
                confirmation()
            }
        }
        
        await confirmation { confirmation in
            callProvider.reportCallWithEndedAtReasonClosure = { _, _, reason in
                if reason == .unanswered {
                    confirmation()
                } else {
                    Issue.record("Call should have ended as unanswered")
                }
            }
            
            // advance past the timeout
            await testClock.advance(by: .seconds(30))
        }
    }
    
    @Test
    func lifetimeIsCapped() async throws {
        #expect(!callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
        
        let (endedCalls, endedCallsContinuation) = AsyncStream<CXCallEndedReason>.makeStream()
        callProvider.reportCallWithEndedAtReasonClosure = { _, _, reason in
            endedCallsContinuation.yield(reason)
        }
        let deferredEndedCall = deferFulfillment(endedCalls, timeout: .seconds(30)) { _ in true }
        
        let pushPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 300)
        
        service.pushRegistry(pushRegistry,
                             didReceiveIncomingPushWith: pushPayload,
                             for: .voIP) { }
        
        await waitForScheduledSleep()
        
        // Advance past the max timeout but below the 300
        await testClock.advance(by: .seconds(100))
        
        let reason = try await deferredEndedCall.fulfill()
        #expect(reason == .unanswered, "Call should have ended as unanswered")
    }
    
    @Test
    func incomingGroupCallNamesTheRoomAndTheCaller() async {
        await waitForConfirmation { confirmation in
            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
                .updateIsDM(false)
            
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                confirmation()
            }
        }
        
        // A group ring introduces itself as the GROUP's before naming who
        // started it — the caller's name alone made a group call
        // indistinguishable from a DM from that person.
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.update.localizedCallerName == "welcome — Tester")
    }
    
    /// Brief 0068 Slice 3: a ring that died while another Spiral call was
    /// live says so — the user never heard it, and should know why.
    @Test
    func aRingMissedDuringAnotherCallSaysSo() async throws {
        let notificationCenter = UserNotificationCenterMock()
        let service = makeService(notificationCenter: notificationCenter)
        await service.setupCallSession(roomID: "!live:example.com", roomDisplayName: "Live", isVoiceCall: true)

        await waitForConfirmation { confirmation in
            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                confirmation()
            }
        }
        await waitForScheduledSleep()
        await testClock.advance(by: .seconds(40))

        let request = try await missedCallRequest(from: notificationCenter)
        #expect(request.content.body == UntranslatedL10n.notificationMissedCallWhileInCall)
    }

    @Test
    func unansweredRingPostsMissedCallNotification() async throws {
        let notificationCenter = UserNotificationCenterMock()
        let service = makeService(notificationCenter: notificationCenter)
        
        await waitForConfirmation { confirmation in
            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                confirmation()
            }
        }
        
        await waitForScheduledSleep()
        await testClock.advance(by: .seconds(40))
        
        // CallKit's `.unanswered` only writes to Recents; the lock-screen
        // "Missed call" is ours to post or nobody's.
        let request = try await missedCallRequest(from: notificationCenter)
        #expect(request.content.title == "Tester")
        #expect(request.content.body == UntranslatedL10n.notificationMissedCall)
        #expect(request.content.userInfo[NotificationConstants.UserInfoKey.roomIdentifier] as? String == "!room:example.com")
        #expect(request.content.userInfo[NotificationConstants.UserInfoKey.receiverIdentifier] as? String == "@me:spiral.md")
    }
    
    @Test
    func inAppRingDecisionsPostNoMissedCallNotification() async {
        let notificationCenter = UserNotificationCenterMock()
        let service = makeService(notificationCenter: notificationCenter)
        
        await waitForConfirmation { confirmation in
            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                confirmation()
            }
        }
        
        // Declining on the in-app fallback screen used to leave the timer
        // running until the MSC4310 decline event echoed back — offline, that
        // echo never comes and "Missed call" landed over an explicit refusal.
        service.handleInAppRingDecision(roomID: "!room:example.com", accepted: false)
        
        await testClock.advance(by: .seconds(120))
        for _ in 0..<50 {
            await Task.yield()
        }
        
        #expect(notificationCenter.addCallsCount == 0)
    }
    
    @Test
    func expiredPushPostsMissedCallNotification() async throws {
        let notificationCenter = UserNotificationCenterMock()
        let service = makeService(notificationCenter: notificationCenter)
        
        await waitForConfirmation { confirmation in
            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 0)
                .updateIsDM(false)
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                confirmation()
            }
        }
        
        // The push arrived after the ring was already over — the only trace
        // the user can get is this notification, named the group way.
        let request = try await missedCallRequest(from: notificationCenter)
        #expect(request.content.title == "welcome — Tester")
    }
    
    @Test
    func answeredCallPostsNoMissedCallNotification() async {
        let notificationCenter = UserNotificationCenterMock()
        let service = makeService(notificationCenter: notificationCenter)
        
        await waitForConfirmation { confirmation in
            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                confirmation()
            }
        }
        
        // Answering routes through `setupCallSession`, which retires the
        // unanswered timer.
        await service.setupCallSession(roomID: "!room:example.com",
                                       roomDisplayName: "welcome",
                                       isVoiceCall: true)
        
        await testClock.advance(by: .seconds(120))
        for _ in 0..<50 {
            await Task.yield()
        }
        
        #expect(notificationCenter.addCallsCount == 0)
    }
    
    /// Held strongly here — the service only keeps a `weak` reference.
    private var clientProxyMock: ClientProxyMock!
    
    /// Audit 2026-09-05 (Brief 0067 § Phase 6, iOS P1): ring A's room lookup
    /// is slow; ring B replaces A meanwhile and installs its observers; A's
    /// lookup then resumes, installs A's observers over B's, and A's remote
    /// hang-up clears the incoming state — B's timer, B's decline listener —
    /// so answering B fails the UUID guard while the phone is still ringing.
    @Test
    func aStaleRingsLateLookupCannotClearTheRingThatReplacedIt() async throws {
        let service = makeService(notificationCenter: UserNotificationCenterMock())
        let gate = LookupGate()
        let roomA = JoinedRoomProxyMock(.init(id: "!a:example.com", hasOngoingCall: true))
        let roomAInfo = CurrentValueSubject<RoomInfoProxyProtocol, Never>(roomA.infoPublisher.value)
        roomA.infoPublisher = roomAInfo.asCurrentValuePublisher()
        let roomB = JoinedRoomProxyMock(.init(id: "!b:example.com", hasOngoingCall: true))
        for room in [roomA, roomB] {
            room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        }
        clientProxyMock.roomForIdentifierClosure = { roomID in
            if roomID == "!a:example.com" {
                await gate.wait()
                return .joined(roomA)
            }
            return .joined(roomB)
        }
        
        let pushA = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
        pushA.dict[CallKitNotificationKey.roomID.rawValue] = "!a:example.com"
        pushA.dict[CallKitNotificationKey.rtcNotifyEventID.rawValue] = "$a"
        await waitForConfirmation { confirmation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: pushA, for: .voIP) { confirmation() }
        }
        
        let pushB = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
        pushB.dict[CallKitNotificationKey.roomID.rawValue] = "!b:example.com"
        pushB.dict[CallKitNotificationKey.rtcNotifyEventID.rawValue] = "$b"
        await waitForConfirmation { confirmation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: pushB, for: .voIP) { confirmation() }
        }
        let ringB = try #require(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedInvocations.last?.uuid)
        try await Task.sleep(for: .milliseconds(50))
        
        // A's lookup lands late, then A's caller hangs up.
        gate.open()
        try await Task.sleep(for: .milliseconds(50))
        let endedBeforeAHangsUp = callProvider.reportCallWithEndedAtReasonCallsCount
        let infoA = RoomInfoProxyMock(.init(id: "!a:example.com", hasOngoingCall: false))
        roomAInfo.send(infoA)
        try await Task.sleep(for: .milliseconds(50))
        
        let endedSince = callProvider.reportCallWithEndedAtReasonReceivedInvocations.dropFirst(endedBeforeAHangsUp).map(\.uuid)
        #expect(!endedSince.contains(ringB), "A's hang-up must not end B")
        
        // B is still the live ring: answering it must be accepted.
        let (actions, continuation) = AsyncStream<CallKitServiceAction>.makeStream()
        let cancellable = service.actions.sink { continuation.yield($0) }
        let deferredStart = deferFulfillment(actions) {
            guard case .startCall = $0 else { return false }
            return true
        }
        service.provider(CXProvider(configuration: CXProviderConfiguration()), perform: CXAnswerCallAction(call: ringB))
        let action = try await deferredStart.fulfill()
        guard case let .startCall(roomID, _) = action else {
            Issue.record("answering B must start B's call")
            return
        }
        #expect(roomID == "!b:example.com")
        _ = cancellable
    }
    
    private func makeService(notificationCenter: UserNotificationCenterMock) -> CallKitService {
        let service = CallKitService(callProvider: callProvider,
                                     callController: callController,
                                     timeProvider: TimeProvider(clock: testClock),
                                     audio: audio,
                                     notificationCenter: notificationCenter)
        // Missed-call notifications are parked until a session exists — a
        // notification without `receiver_id` has a dead tap.
        clientProxyMock = ClientProxyMock(.init(userID: "@me:spiral.md"))
        service.setClientProxy(clientProxyMock)
        return service
    }
    
    /// The notification is posted from an unstructured task, so the mock is
    /// polled rather than asserted synchronously.
    private func missedCallRequest(from notificationCenter: UserNotificationCenterMock) async throws -> UNNotificationRequest {
        for _ in 0..<500 {
            if let request = notificationCenter.addReceivedRequest {
                return request
            }
            await Task.yield()
        }
        throw TestError.timeout
    }
    
    private enum TestError: Error {
        case timeout
    }
    
    @Test
    func callIntentRawValues() {
        // Test to ensure that the implicit rawValue of the string enum matches the MSC values
        #expect(CallIntent.audio.rawValue == "audio")
        #expect(CallIntent.video.rawValue == "video")
    }
    
    @Test
    func timeoutClearsIncomingCallStateBeforeNextPush() async throws {
        // Drive push #1 to its 60s unanswered timeout
        let (endedCalls, endedCallsContinuation) = AsyncStream<CXCallEndedReason>.makeStream()
        callProvider.reportCallWithEndedAtReasonClosure = { _, _, reason in
            endedCallsContinuation.yield(reason)
        }
        let deferredEndedCall = deferFulfillment(endedCalls, timeout: .seconds(30)) { $0 == .unanswered }
        
        let firstPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 60)
        service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: firstPayload, for: .voIP) { }
        
        await waitForScheduledSleep()
        await testClock.advance(by: .seconds(70))
        try await deferredEndedCall.fulfill()
        
        callProvider.reportCallWithEndedAtReasonClosure = nil
        let firstCallUUID = callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.uuid
        
        // Send push #2 for the same room; the previous incoming state must be cleared,
        // so the second push gets a fresh CallID.
        await waitForConfirmation { confirmation in
            let secondPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 60)
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: secondPayload, for: .voIP) {
                confirmation()
            }
        }
        
        let secondCallUUID = callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.uuid
        
        #expect(firstCallUUID != nil)
        #expect(secondCallUUID != nil)
        #expect(firstCallUUID != secondCallUUID)
        
        let unansweredCount = callProvider.reportCallWithEndedAtReasonReceivedInvocations.filter { $0.reason == .unanswered }.count
        #expect(unansweredCount == 1)
    }
    
    @Test
    func setupCallSessionCancelsPendingUnansweredTimeout() async {
        // Schedule the 60s unanswered timer via an incoming push
        await waitForConfirmation { confirmation in
            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 60)
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                confirmation()
            }
        }
        
        // Make sure the cancellation below exercises a scheduled timer rather than one that never started.
        await waitForScheduledSleep()
        
        // Simulate the answer flow handing off to setupCallSession, which must cancel
        // the pending endUnansweredCallTask as part of clearing the incoming state.
        await service.setupCallSession(roomID: "!room:example.com", roomDisplayName: "welcome", isVoiceCall: true)
        
        var unansweredFired = false
        callProvider.reportCallWithEndedAtReasonClosure = { _, _, reason in
            if reason == .unanswered {
                unansweredFired = true
            }
        }
        
        // Advance past what would have been the 60s unanswered timeout
        await testClock.advance(by: .seconds(120))
        for _ in 0..<3 {
            await Task.yield()
        }
        
        #expect(!unansweredFired, "endUnansweredCallTask should have been cancelled by setupCallSession")
    }
    
    @Test
    func expiredPushReportsMissedCall() async {
        // An expired push is a real call we missed, so it should show up in Recents as one.
        //
        // Expiry is now decided by the NSE from two SERVER timestamps and
        // sent as a remaining duration (audit W6-5-3), so the test says so
        // directly instead of advancing a local clock. That is the change:
        // whether a ring has expired is no longer a question about this
        // device's opinion of the time.
        let pushPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 0)
        await expectImmediatelyEndedCallReported(forPayload: pushPayload, expectedReason: .unanswered)
        
        let update = callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.update
        #expect(update?.localizedCallerName == "welcome")
        #expect(update?.remoteHandle?.value == "!room:example.com")
    }
    
    /// A push that is not going to ring must not take a live ring with it.
    ///
    /// The retire-the-previous-ring step ran BEFORE the new push was
    /// validated, so an expired or malformed second push tore down a call
    /// the user could still have answered — and then reported itself missed
    /// as well. Two calls ended for the price of one bad one, and the good
    /// one was the user's.
    @Test
    func anExpiredSecondPushLeavesTheLiveRingAlone() async throws {
        // A real ring, up and waiting for the user.
        let live = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 60)
        await waitForConfirmation { confirmation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: live, for: .voIP) {
                confirmation()
            }
        }
        let liveCallUUID = callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.uuid
        #expect(liveCallUUID != nil, "precondition: the first push really rang")
        let endedBefore = callProvider.reportCallWithEndedAtReasonCallsCount

        // A second push for a DIFFERENT room that has already expired.
        let stale = PKPushPayloadMock()
        stale.dict[CallKitNotificationKey.roomID.rawValue] = "!other:example.com"
        stale.dict[CallKitNotificationKey.rtcNotifyEventID.rawValue] = "$stale"
        _ = stale.updatingExpiration(currentDate, lifetime: 0)

        await waitForConfirmation { confirmation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: stale, for: .voIP) {
                confirmation()
            }
        }

        // Exactly one call ended — the stale one, reported missed. The live
        // ring must not be among them.
        let endedUUIDs = callProvider.reportCallWithEndedAtReasonReceivedInvocations
            .dropFirst(endedBefore)
            .map(\.uuid)
        #expect(try !endedUUIDs.contains(#require(liveCallUUID)),
                "the live ring must survive a push that was never going to ring")
    }

    /// The defect itself: a device whose clock runs ahead of the homeserver
    /// used to miss every ring (audit W6-5-3).
    ///
    /// The old payload carried an absolute expiry that was compared against
    /// `timeProvider.now()` with zero tolerance, so any skew past the ring
    /// window turned every incoming call into a missed one — CallKit
    /// flashed and died, and the user was never given the chance to answer.
    /// Nothing about the device's clock may reach that decision now.
    @Test
    func aSkewedDeviceClockDoesNotSwallowTheRing() async {
        let pushPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
        // Far enough ahead that the old absolute comparison would have
        // classified this as long expired.
        currentDate = currentDate.addingTimeInterval(3600)
        
        await waitForConfirmation { confirmation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: pushPayload, for: .voIP) {
                confirmation()
            }
        }
        
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCalled,
                "the ring must be reported however wrong this device thinks the time is")
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 0,
                "and it must not be immediately buried as a missed call")
    }
    
    @Test
    func duplicateRoomPushReportsCallAsHandled() async {
        // A duplicate push for an ongoing call is reported as handled, leaving the ongoing call alone.
        await service.setupCallSession(roomID: "!room:example.com", roomDisplayName: "welcome", isVoiceCall: true)
        let pushPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
        await expectImmediatelyEndedCallReported(forPayload: pushPayload, expectedReason: .answeredElsewhere)
        
        // The call should be named so neither the brief system UI nor the Recents entry shows "Unknown".
        let update = callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.update
        #expect(update?.localizedCallerName == "welcome")
        
        #expect(service.ongoingCallRoomIDPublisher.value == "!room:example.com")
    }
    
    // MARK: - The CallKit audio window (AGENT-PLATFORM, Brief 0063)

    /// H3 — CallKit activates whatever audio category is configured when an
    /// action fulfils, which is before any `NativeCallSession` exists. Doing
    /// that configuration with nothing to give back left LiveKit's automatic
    /// configuration disabled for the rest of the process whenever the answered
    /// call never reached a session (the user hangs up while routing, the room
    /// lookup fails, the app is suspended between `fulfill()` and the screen) —
    /// and every later Element Call web-view call then came up with no
    /// microphone.
    @Test
    func aNativeCallThatNeverReachesASessionStillGivesTheAudioBack() async throws {
        await receiveIncomingPush()

        let callID = try #require(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.uuid)
        service.provider(CXProvider(configuration: CXProviderConfiguration()), perform: CXAnswerCallAction(call: callID))

        #expect(audio.isActivationWindowHeld, "answering a native call opens the window")

        // No screen, no session: the call ends exactly where it started.
        service.tearDownCallSession(forRoomID: nil)

        #expect(!audio.isActivationWindowHeld)
        #expect(audio.claims == audio.releases)
    }

    /// The outgoing half of the same window: `CXStartCallAction` fulfils before
    /// the session connects, and the call can still die before one exists.
    @Test
    func anOutgoingNativeCallGivesTheAudioWindowBackWhenItEnds() async throws {
        await service.setupCallSession(roomID: "!room:example.com",
                                       roomDisplayName: "Tester",
                                       isVoiceCall: true)

        let transaction = try #require(callController.requestedTransactions.first)
        let action = try #require(transaction.actions.first as? CXStartCallAction)
        service.provider(CXProvider(configuration: CXProviderConfiguration()), perform: action)

        #expect(audio.isActivationWindowHeld)

        service.tearDownCallSession(forRoomID: nil)

        #expect(!audio.isActivationWindowHeld)
    }

    /// A provider reset takes every call with it, so nothing is left to close
    /// the window the usual way.
    @Test
    func aProviderResetGivesTheAudioWindowBack() async throws {
        await receiveIncomingPush()

        let callID = try #require(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.uuid)
        let provider = CXProvider(configuration: CXProviderConfiguration())
        service.provider(provider, perform: CXAnswerCallAction(call: callID))

        service.providerDidReset(provider)

        #expect(!audio.isActivationWindowHeld)
    }

    /// M6 — CallKit delivers `didDeactivate` only after the end action has
    /// settled, and `tearDownCallSession` clears the ongoing call synchronously
    /// before that. Deciding on the live call therefore made the native path's
    /// own engine-parking a no-op in the ORDINARY ordering, which is precisely
    /// when it is needed.
    @Test
    func theNativeDeactivationStillRunsAfterTheCallHasBeenTornDown() async {
        await service.setupCallSession(roomID: "!room:example.com",
                                       roomDisplayName: "Tester",
                                       isVoiceCall: true)

        let provider = CXProvider(configuration: CXProviderConfiguration())
        service.provider(provider, didActivate: AVAudioSession.sharedInstance())
        #expect(audio.activations == 1)

        service.tearDownCallSession(forRoomID: nil)
        service.provider(provider, didDeactivate: AVAudioSession.sharedInstance())

        #expect(audio.deactivations == 1, "the native engine must still be parked once the call is gone")
    }

    // MARK: - The end action (audit W6-5-4, seam added in wave 8's close-out)

    /// The P1 this pins: the old handler acted on BOTH slots for every end
    /// action, so declining a call-waiting ring hung up the live call. The
    /// fix shipped inside the delegate method, which is compiled out on
    /// simulators — where unit tests run — so for two weeks the fix had no
    /// regression protection at all. `endCall(matching:)` is the seam that
    /// ends that.
    @Test
    func endingTheLiveCallLeavesTheRingAnswerable() async throws {
        // A live native call in room B…
        await service.setupCallSession(roomID: "!b:example.com",
                                       roomDisplayName: "B",
                                       isVoiceCall: true)
        let startUUIDs = callController.requestedTransactions
            .flatMap(\.actions)
            .compactMap { ($0 as? CXStartCallAction)?.callUUID }
        let liveUUID = try #require(startUUIDs.first)

        // …and a ring for room R next to it.
        let ring = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 60)
        ring.dict[CallKitNotificationKey.roomID.rawValue] = "!r:example.com"
        ring.dict[CallKitNotificationKey.rtcNotifyEventID.rawValue] = "$ring-r"
        await waitForConfirmation { confirmation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: ring, for: .voIP) {
                confirmation()
            }
        }
        let ringUUID = try #require(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.uuid)

        var emitted: [CallKitServiceAction] = []
        let cancellable = service.actions.sink { emitted.append($0) }
        defer { cancellable.cancel() }

        service.endCall(matching: liveUUID)

        #expect(emitted.contains { if case .endCall(roomID: "!b:example.com") = $0 { return true }; return false },
                "ending the live call by its own UUID must end room B")
        #expect(service.ongoingCallRoomIDPublisher.value == nil,
                "the live call must be torn down")

        // The ring must still be ANSWERABLE — this is what the old handler
        // destroyed. Answering it must route the call, not fail.
        service.provider(CXProvider(configuration: CXProviderConfiguration()),
                         perform: CXAnswerCallAction(call: ringUUID))
        #expect(emitted.contains { if case .startCall(roomID: "!r:example.com", isVoiceCall: _) = $0 { return true }; return false },
                "the ring must survive the live call's end and still answer")
    }

    /// The other direction of the same defect: ending (= declining) the ring
    /// must not touch the live call.
    @Test
    func decliningTheRingLeavesTheLiveCallAlone() async throws {
        await service.setupCallSession(roomID: "!b:example.com",
                                       roomDisplayName: "B",
                                       isVoiceCall: true)

        let ring = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 60)
        ring.dict[CallKitNotificationKey.roomID.rawValue] = "!r:example.com"
        ring.dict[CallKitNotificationKey.rtcNotifyEventID.rawValue] = "$ring-r2"
        await waitForConfirmation { confirmation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: ring, for: .voIP) {
                confirmation()
            }
        }
        let ringUUID = try #require(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.uuid)

        var emitted: [CallKitServiceAction] = []
        let cancellable = service.actions.sink { emitted.append($0) }
        defer { cancellable.cancel() }

        service.endCall(matching: ringUUID)

        #expect(!emitted.contains { if case .endCall = $0 { return true }; return false },
                "declining a ring must never end the live call — that is the P1")
        #expect(service.ongoingCallRoomIDPublisher.value == "!b:example.com",
                "the live call must survive the ring's decline")

        // And the ring really is retired: answering it now must not route.
        service.provider(CXProvider(configuration: CXProviderConfiguration()),
                         perform: CXAnswerCallAction(call: ringUUID))
        #expect(!emitted.contains { if case .startCall = $0 { return true }; return false },
                "a declined ring must not be answerable")
    }

    /// A UUID this service never tracked must settle with no side effects —
    /// the raced-teardown / provider-reset branch.
    @Test
    func anUntrackedEndActionDoesNothing() async {
        await service.setupCallSession(roomID: "!b:example.com",
                                       roomDisplayName: "B",
                                       isVoiceCall: true)

        var emitted: [CallKitServiceAction] = []
        let cancellable = service.actions.sink { emitted.append($0) }
        defer { cancellable.cancel() }

        service.endCall(matching: UUID())

        #expect(emitted.isEmpty, "an untracked end must emit nothing")
        #expect(service.ongoingCallRoomIDPublisher.value == "!b:example.com",
                "and must not touch the live call")
    }

    // MARK: - Two calls at once (audit wave 8)

    /// Answering a second call must keep the first one TRACKED in CallKit.
    ///
    /// The native answer sets the ongoing slot directly and returns before
    /// `setupCallSession`, which is where the Element Call path ends the
    /// previous call. So the first call was simply dropped from this service
    /// while the system still held it: it could no longer be ended, held or
    /// muted, because every action for it fell through to the untracked
    /// branch, and it sat in the system UI until iOS gave up on it.
    ///
    /// Brief 0068 Slice 2 changed what "tracked" means: the first call is
    /// HELD, not ended — the held slot, a hold action through CallKit, and
    /// every later action for it still matched. What this test guards is
    /// unchanged: nothing is silently dropped.
    @Test
    func answeringASecondCallKeepsTheFirstOneTrackedAsHeld() async throws {
        // A live native call in room A.
        await service.setupCallSession(roomID: "!a:example.com",
                                       roomDisplayName: "A",
                                       isVoiceCall: true)
        let startedUUIDs = callController.requestedTransactions
            .flatMap(\.actions)
            .compactMap { ($0 as? CXStartCallAction)?.callUUID }
        let firstUUID = try #require(startedUUIDs.first)

        // A ring for a DIFFERENT room, which the room-scoped guard lets through.
        let second = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 60)
        second.dict[CallKitNotificationKey.roomID.rawValue] = "!b:example.com"
        second.dict[CallKitNotificationKey.rtcNotifyEventID.rawValue] = "$b"
        await waitForConfirmation { confirmation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: second, for: .voIP) {
                confirmation()
            }
        }
        let secondUUID = try #require(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.uuid)
        let endedBefore = callProvider.reportCallWithEndedAtReasonCallsCount

        service.provider(CXProvider(configuration: CXProviderConfiguration()),
                         perform: CXAnswerCallAction(call: secondUUID))

        let endedUUIDs = callProvider.reportCallWithEndedAtReasonReceivedInvocations
            .dropFirst(endedBefore)
            .map(\.uuid)
        #expect(!endedUUIDs.contains(firstUUID), "the first call is held, not ended")
        #expect(!endedUUIDs.contains(secondUUID),
                "the call just answered must not be ended")
        #expect(service.ongoingCallRoomIDPublisher.value == "!b:example.com")
        #expect(service.heldCallPublisher.value?.roomID == "!a:example.com")
        let holds = callController.requestedTransactions.flatMap(\.actions).compactMap { $0 as? CXSetHeldCallAction }
        #expect(holds.contains { $0.callUUID == firstUUID && $0.isOnHold },
                "the first call is held through CallKit — still tracked, still actionable")
    }

    /// The replaced screen tears itself down seconds later — an end tone, a
    /// Matrix leave, a transport disconnect. By then the ongoing call is the
    /// one the user just answered, and an unscoped teardown ended it.
    @Test
    func aLateTeardownFromAReplacedScreenLeavesTheLiveCallAlone() async {
        await service.setupCallSession(roomID: "!b:example.com",
                                       roomDisplayName: "B",
                                       isVoiceCall: true)
        let requestsBefore = callController.requestedTransactions.count

        // Room A's screen finally finishes stopping and tears its call down.
        service.tearDownCallSession(forRoomID: "!a:example.com")

        #expect(callController.requestedTransactions.count == requestsBefore,
                "a teardown for a call that is no longer live must not end the one that is")
        #expect(service.ongoingCallRoomIDPublisher.value == "!b:example.com",
                "the live call must survive the previous screen's teardown")
    }

    /// Hold is the one control that exists only because a second call does,
    /// so acting on whatever the ongoing slot holds is exactly wrong: a swap
    /// would hold the call it had just resumed.
    @Test
    func aHoldForAnUntrackedCallDoesNotDriveTheLiveOne() async {
        await service.setupCallSession(roomID: "!b:example.com",
                                       roomDisplayName: "B",
                                       isVoiceCall: true)

        var held: [Bool] = []
        let cancellable = service.actions.sink { action in
            if case .setCallHeld(let isHeld, _) = action { held.append(isHeld) }
        }
        defer { cancellable.cancel() }

        service.provider(CXProvider(configuration: CXProviderConfiguration()),
                         perform: CXSetHeldCallAction(call: UUID(), onHold: true))

        #expect(held.isEmpty, "a hold for a call we do not track must drive nothing")
    }

    private func receiveIncomingPush() async {
        await waitForConfirmation { confirmation in
            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
                .updateIsVoice(true)

            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                confirmation()
            }
        }
    }
    
    /// Waits until the unanswered-call timer is sleeping on the test clock — it runs in an
    /// unstructured task, so advancing the clock before that would never wake it.
    /// Note: `checkSuspension()` throws when a sleep is scheduled, which is the state we want.
    private func waitForScheduledSleep() async {
        while await (try? testClock.checkSuspension()) != nil {
            await Task.yield()
        }
    }
    
    private func expectImmediatelyEndedCallReported(forPayload payload: PKPushPayloadMock,
                                                    expectedReason: CXCallEndedReason) async {
        let baselineNewIncomingCount = callProvider.reportNewIncomingCallWithUpdateCompletionCallsCount
        let baselineEndedCount = callProvider.reportCallWithEndedAtReasonCallsCount
        
        await waitForConfirmation { confirmation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                confirmation()
            }
        }
        
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCallsCount == baselineNewIncomingCount + 1)
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == baselineEndedCount + 1)
        
        let reportedCall = callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments
        let endedCall = callProvider.reportCallWithEndedAtReasonReceivedArguments
        #expect(reportedCall?.uuid == endedCall?.uuid)
        #expect(endedCall?.reason == expectedReason)
    }
}

// MARK: - In-app ring answers (follow-up L1)

extension CallKitServiceTests {
    /// A live call in room A, and an in-app ring for room B accepted at the
    /// tap, which parks A. B's lookup is in flight; `roomBInfo` is what B's
    /// ring watcher sees.
    private func acceptInAppRingDuringACall(notificationCenter: UserNotificationCenterMock = UserNotificationCenterMock()) async throws -> AcceptedInAppRing {
        service = makeService(notificationCenter: notificationCenter)
        let rooms = ["!a:example.com", "!b:example.com", "!c:example.com"].map { JoinedRoomProxyMock(.init(id: $0, hasOngoingCall: true)) }
        for room in rooms {
            room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        }
        let roomB = rooms[1]
        let roomBInfo = CurrentValueSubject<RoomInfoProxyProtocol, Never>(roomB.infoPublisher.value)
        roomB.infoPublisher = roomBInfo.asCurrentValuePublisher()
        clientProxyMock.roomForIdentifierClosure = { roomID in rooms.first { $0.id == roomID }.map { .joined($0) } }

        let a = try await ring(room: "!a:example.com", notification: "$a")
        answer(a)
        await service.setupCallSession(roomID: "!a:example.com", roomDisplayName: "Room A", isVoiceCall: true)
        let b = try await ring(room: "!b:example.com", notification: "$b")
        try await Task.sleep(for: .milliseconds(50))
        service.handleInAppRingDecision(roomID: "!b:example.com", accepted: true)
        #expect(service.heldCallPublisher.value?.roomID == "!a:example.com", "precondition: A is parked at the tap")
        return AcceptedInAppRing(a: a, b: b, roomB: roomB, roomBInfo: roomBInfo)
    }

    /// The in-app ring's caller hung up while its room was being looked up,
    /// so the ring is gone before the flow coordinator gives up on it. The
    /// call parked for it at the tap must still come back rather than stay
    /// held behind a screen that never appears (follow-up L1).
    @Test
    func theCallParkedForAnInAppRingThatEndedComesBack() async throws {
        let accepted = try await acceptInAppRingDuringACall()

        accepted.roomBInfo.send(RoomInfoProxyMock(.init(id: "!b:example.com", hasOngoingCall: false)))
        try await Task.sleep(for: .milliseconds(50))
        #expect(callProvider.reportCallWithEndedAtReasonReceivedInvocations.contains { $0.uuid == accepted.b && $0.reason == .remoteEnded },
                "precondition: the hang-up retired the ring")

        // The flow coordinator gives up on B.
        service.tearDownCallSession(forRoomID: "!b:example.com")

        #expect(service.heldCallPublisher.value == nil)
        #expect(service.ongoingCallRoomIDPublisher.value == "!a:example.com")
        #expect(holdActions().contains { $0.callUUID == accepted.a && !$0.isOnHold }, "A is resumed through CallKit")
    }

    /// A newer ring replacing the accepted one during its lookup used to
    /// leave the ring slot full, so the teardown that gives up on B was
    /// ignored and A stayed held — and the newer ring keeps ringing.
    @Test
    func aRingReplacedDuringItsLookupStillBringsBackTheParkedCall() async throws {
        let accepted = try await acceptInAppRingDuringACall()
        let c = try await ring(room: "!c:example.com", notification: "$c")

        service.tearDownCallSession(forRoomID: "!b:example.com")

        #expect(service.heldCallPublisher.value == nil)
        #expect(service.ongoingCallRoomIDPublisher.value == "!a:example.com")
        #expect(holdActions().contains { $0.callUUID == accepted.a && !$0.isOnHold }, "A is resumed through CallKit")
        #expect(!callProvider.reportCallWithEndedAtReasonReceivedInvocations.contains { $0.uuid == c }, "C keeps ringing")
    }

    /// The replacing ring's screen is up while B's lookup still runs, and
    /// accepting it took A — parked in both slots — for a third call and
    /// ended it.
    @Test
    func acceptingTheReplacingRingDuringTheLookupKeepsTheParkedCall() async throws {
        let accepted = try await acceptInAppRingDuringACall()
        var ended = [String]()
        let cancellable = service.actions.sink { if case .endCall(let roomID) = $0 { ended.append(roomID) } }
        _ = try await ring(room: "!c:example.com", notification: "$c")

        service.handleInAppRingDecision(roomID: "!c:example.com", accepted: true)

        #expect(!ended.contains("!a:example.com"), "A is not ended")
        #expect(ended == ["!b:example.com"], "B, given up for C, takes its screen down (question 93)")
        #expect(!callProvider.reportCallWithEndedAtReasonReceivedInvocations.contains { $0.uuid == accepted.a })
        #expect(service.heldCallPublisher.value?.roomID == "!a:example.com", "A stays parked, now for C")
        _ = cancellable
    }

    /// B's screen joins before it registers, and our own membership echoes
    /// back to B's ring watcher as "answered elsewhere", which retires the
    /// ring. The registration then took the outgoing path: it ended A and
    /// started a CallKit call for a call the user had answered.
    @Test
    func anAcceptedRingRetiredByOurOwnJoinIsStillAdopted() async throws {
        let accepted = try await acceptInAppRingDuringACall()
        var ended = [String]()
        let cancellable = service.actions.sink { if case .endCall(let roomID) = $0 { ended.append(roomID) } }

        accepted.roomBInfo.send(RoomInfoProxyMock(.init(id: "!b:example.com",
                                                        hasOngoingCall: true,
                                                        activeRoomCallParticipants: [accepted.roomB.ownUserID])))
        try await Task.sleep(for: .milliseconds(50))
        #expect(callProvider.reportCallWithEndedAtReasonReceivedInvocations.contains { $0.uuid == accepted.b && $0.reason == .answeredElsewhere },
                "precondition: the echo retired the ring")

        await service.setupCallSession(roomID: "!b:example.com", roomDisplayName: "Room B", isVoiceCall: true)

        #expect(service.ongoingCallRoomIDPublisher.value == "!b:example.com")
        #expect(service.heldCallPublisher.value?.roomID == "!a:example.com", "A stays parked")
        #expect(!ended.contains("!a:example.com"), "A is not ended")
        let starts = callController.requestedTransactions.flatMap(\.actions).compactMap { $0 as? CXStartCallAction }
        #expect(starts.isEmpty, "an answer starts no outgoing CallKit call")
        _ = cancellable
    }

    /// The user accepted the ring, so its caller hanging up before the
    /// screen came is not a missed call.
    @Test
    func anAcceptedRingThatEndsPostsNoMissedCall() async throws {
        let notificationCenter = UserNotificationCenterMock()
        let accepted = try await acceptInAppRingDuringACall(notificationCenter: notificationCenter)

        accepted.roomBInfo.send(RoomInfoProxyMock(.init(id: "!b:example.com", hasOngoingCall: false)))
        try await Task.sleep(for: .milliseconds(50))
        for _ in 0..<50 {
            await Task.yield()
        }

        #expect(notificationCenter.addCallsCount == 0)
    }

    /// With no other call live, giving up on the accepted ring (its room not
    /// joined, its screen failing to start) fell past the un-park and left
    /// the ring in its slot: its watcher and decline listener stayed up, and
    /// the caller hanging up later posted "Missed call" for a call the user
    /// had accepted.
    @Test
    func givingUpAnAcceptedRingWithNoCallLiveRetiresTheRing() async throws {
        let notificationCenter = UserNotificationCenterMock()
        service = makeService(notificationCenter: notificationCenter)
        let room = JoinedRoomProxyMock(.init(id: "!b:example.com", hasOngoingCall: true))
        let roomInfo = CurrentValueSubject<RoomInfoProxyProtocol, Never>(room.infoPublisher.value)
        room.infoPublisher = roomInfo.asCurrentValuePublisher()
        let declineListener = TaskHandleSDKMock()
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(declineListener)
        clientProxyMock.roomForIdentifierClosure = { _ in .joined(room) }
        let b = try await ring(room: "!b:example.com", notification: "$b")
        try await Task.sleep(for: .milliseconds(50))
        #expect(room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerCalled, "precondition: the ring is watched")
        service.handleInAppRingDecision(roomID: "!b:example.com", accepted: true)

        service.tearDownCallSession(forRoomID: "!b:example.com")

        #expect(declineListener.cancelCalled, "the ring's decline listener goes")
        roomInfo.send(RoomInfoProxyMock(.init(id: "!b:example.com", hasOngoingCall: false)))
        try await Task.sleep(for: .milliseconds(50))
        for _ in 0..<50 {
            await Task.yield()
        }
        #expect(!callProvider.reportCallWithEndedAtReasonReceivedInvocations.contains { $0.uuid == b }, "nothing watches the ring any more")
        #expect(notificationCenter.addCallsCount == 0, "no missed call for an accepted ring")
    }
}

// MARK: - Call-race follow-ups

extension CallKitServiceTests {
    /// Follow-up N3: a ring showing in the app when its room's call starts
    /// another way (the room's call button, a link) is adopted by that
    /// call's registration. Its in-app screen and haptic stayed up, and its
    /// Decline then declined the call the user had just joined.
    @Test
    func adoptingAnUnacceptedRingTakesItsInAppScreenDown() async throws {
        service = makeService(notificationCenter: UserNotificationCenterMock())
        let room = JoinedRoomProxyMock(.init(id: "!b:example.com", hasOngoingCall: true))
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        clientProxyMock.roomForIdentifierClosure = { _ in .joined(room) }
        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(CXErrorCodeIncomingCallError(.filteredByDoNotDisturb))
        }
        var inAppRings = [String]()
        let cancellable = service.actions.sink { action in
            switch action {
            case .startInAppRinging(let roomID, _, _, _, _): inAppRings.append("start \(roomID)")
            case .stopInAppRinging(let roomID): inAppRings.append("stop \(roomID)")
            default: break
            }
        }
        let b = try await ring(room: "!b:example.com", notification: "$b")
        try await Task.sleep(for: .milliseconds(50))
        #expect(inAppRings == ["start !b:example.com"], "precondition: the ring shows in the app")

        await service.setupCallSession(roomID: "!b:example.com", roomDisplayName: "Room B", isVoiceCall: true)

        #expect(service.ongoingCallRoomIDPublisher.value == "!b:example.com")
        #expect(callProvider.reportCallWithUpdatedReceivedInvocations.contains { $0.uuid == b }, "precondition: the ring was adopted")
        #expect(inAppRings == ["start !b:example.com", "stop !b:example.com"], "the adopted ring's in-app screen goes")
        _ = cancellable
    }

    /// Follow-up N1: a screen's teardown lands seconds after its call ended
    /// from the system UI (the end tone, the Matrix leave). A redial of the
    /// same room accepted in the app meanwhile is not that screen's call,
    /// but the teardown by room took it: the redial's screen then
    /// registered on the outgoing path.
    @Test
    func aDeadScreensLateTeardownLeavesTheNewerAcceptedRingOfItsRoom() async throws {
        service = makeService(notificationCenter: UserNotificationCenterMock())
        let roomID = "!a:example.com"
        let room = JoinedRoomProxyMock(.init(id: roomID, hasOngoingCall: true))
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        clientProxyMock.roomForIdentifierClosure = { _ in .joined(room) }

        let first = try await ring(room: roomID, notification: "$first")
        answer(first)
        let leave = LookupGate()
        let screen = makeCallScreen(roomID: roomID, leave: leave)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room A", isVoiceCall: true)

        // Ended from the system UI; the screen's stop waits on its leave.
        service.endCall(matching: first)
        screen.stop()
        let redial = try await ring(room: roomID, notification: "$redial")
        try await Task.sleep(for: .milliseconds(50))
        service.handleInAppRingDecision(roomID: roomID, accepted: true)
        leave.open()
        try await waitForTheEnd(of: screen)

        #expect(service.isAcceptedRingLive(forRoomID: roomID), "the redial is still the accepted ring")
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room A", isVoiceCall: true)
        let starts = callController.requestedTransactions.flatMap(\.actions).compactMap { $0 as? CXStartCallAction }
        #expect(starts.isEmpty, "the redial's screen registers as the answer it is")
        #expect(!callProvider.reportCallWithEndedAtReasonReceivedInvocations.contains { $0.uuid == redial })
    }

    /// The in-app answer's own screen ending before it registers (its join
    /// failed) still gives its ring up, and the call parked for it comes back.
    @Test
    func anInAppAnswersScreenEndingBeforeItRegistersBringsBackTheParkedCall() async throws {
        let accepted = try await acceptInAppRingDuringACall()
        let leave = LookupGate()
        leave.open()
        let screen = makeCallScreen(roomID: "!b:example.com", leave: leave)

        screen.stop()
        try await waitForTheEnd(of: screen)

        #expect(service.heldCallPublisher.value == nil)
        #expect(service.ongoingCallRoomIDPublisher.value == "!a:example.com")
        #expect(holdActions().contains { $0.callUUID == accepted.a && !$0.isOnHold }, "A is resumed through CallKit")
    }

    /// A screen that never had a CallKit call of its own (a call it started,
    /// stopped before it registered) ends no call of its room's but one still
    /// registering: a ring of the room accepted in the app while the screen
    /// stopped has a screen of its own, which must still find it.
    @Test
    func anUnregisteredScreensLateTeardownLeavesTheRoomsAcceptedRing() async throws {
        service = makeService(notificationCenter: UserNotificationCenterMock())
        let roomID = "!a:example.com"
        let room = JoinedRoomProxyMock(.init(id: roomID, hasOngoingCall: true))
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        clientProxyMock.roomForIdentifierClosure = { _ in .joined(room) }
        let leave = LookupGate()
        let screen = makeCallScreen(roomID: roomID, leave: leave)
        #expect(screen.callKitID == nil, "precondition: the screen has no call of its own")

        screen.stop()
        _ = try await ring(room: roomID, notification: "$ring")
        try await Task.sleep(for: .milliseconds(50))
        service.handleInAppRingDecision(roomID: roomID, accepted: true)
        leave.open()
        try await waitForTheEnd(of: screen)

        #expect(service.isAcceptedRingLive(forRoomID: roomID), "the accepted ring is its own screen's")
    }

    /// Review of N1: a screen opened for an accepted in-app ring is bound to
    /// a redial of the same room that the user answered from the CallKit
    /// banner (the answer returned to that screen). The screen stops before
    /// it registers: its teardown ended the redial and left the first ring,
    /// retired by the redial, accepted, and the room's next call adopted it,
    /// a call with no CallKit start.
    @Test
    func aBoundScreensTeardownGivesUpTheRetiredAcceptedRing() async throws {
        service = makeService(notificationCenter: UserNotificationCenterMock())
        let roomID = "!s:example.com"
        let room = JoinedRoomProxyMock(.init(id: roomID, hasOngoingCall: true))
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        clientProxyMock.roomForIdentifierClosure = { _ in .joined(room) }
        _ = try await ring(room: roomID, notification: "$first")
        service.handleInAppRingDecision(roomID: roomID, accepted: true)
        let leave = LookupGate()
        leave.open()
        let screen = makeCallScreen(roomID: roomID, leave: leave)

        let redial = try await ring(room: roomID, notification: "$redial")
        answer(redial)
        screen.bind(toCallKitID: redial)
        screen.stop()
        try await waitForTheEnd(of: screen)

        #expect(service.callKitID(forRoomID: roomID) == nil, "nothing of the room's is left")
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room S", isVoiceCall: true)
        let starts = callController.requestedTransactions.flatMap(\.actions).compactMap { $0 as? CXStartCallAction }
        #expect(starts.count == 1, "the room's next call is a CallKit call")
    }

    /// L2 review: the user accepts B's redial in the app while B's old call
    /// is stopping, and a ring of C takes the slot before the redial's
    /// screen registers. The old screen's teardown gave the accepted redial
    /// up, as no longer ringing, and the redial's screen then registered
    /// nothing and was dismissed. A call that was live at the accept is an
    /// older screen's: the ring's own screen resolves the ring.
    @Test
    func anOlderScreensTeardownLeavesTheAcceptedRingToItsOwnScreen() async throws {
        service = makeService(notificationCenter: UserNotificationCenterMock())
        let rooms = ["!b:example.com", "!c:example.com"].map { JoinedRoomProxyMock(.init(id: $0, hasOngoingCall: true)) }
        for room in rooms {
            room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        }
        clientProxyMock.roomForIdentifierClosure = { roomID in rooms.first { $0.id == roomID }.map { .joined($0) } }
        let old = try await ring(room: "!b:example.com", notification: "$old")
        answer(old)
        let leave = LookupGate()
        let oldScreen = makeCallScreen(roomID: "!b:example.com", leave: leave)
        await service.setupCallSession(roomID: "!b:example.com", roomDisplayName: "Room B", isVoiceCall: true)
        oldScreen.stop()
        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(CXErrorCodeIncomingCallError(.filteredByDoNotDisturb))
        }
        let redial = try await ring(room: "!b:example.com", notification: "$redial")
        service.handleInAppRingDecision(roomID: "!b:example.com", accepted: true)
        _ = try await ring(room: "!c:example.com", notification: "$c")
        #expect(!service.isAcceptedRingLive(forRoomID: "!b:example.com"), "precondition: C's ring took the slot")

        leave.open()
        try await waitForTheEnd(of: oldScreen)

        #expect(service.callKitID(forRoomID: "!b:example.com") == redial, "the accepted redial is still its screen's")
        let registered = await service.setupCallSession(roomID: "!b:example.com", roomDisplayName: "Room B", isVoiceCall: true, callKitID: redial)
        #expect(registered == redial, "the redial's screen registers it")
    }

    /// The call a screen opened for a room is for: the room's live call, then
    /// its parked one, then the in-app ring accepted for it.
    @Test
    func aScreensCallIsTheLiveThenTheHeldThenTheAcceptedRing() async throws {
        service = makeService(notificationCenter: UserNotificationCenterMock())
        let rooms = ["!a:example.com", "!q:example.com"].map { JoinedRoomProxyMock(.init(id: $0, hasOngoingCall: true)) }
        for room in rooms {
            room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        }
        clientProxyMock.roomForIdentifierClosure = { roomID in rooms.first { $0.id == roomID }.map { .joined($0) } }
        let roomID = "!a:example.com"
        #expect(service.callKitID(forRoomID: roomID) == nil)

        let accepted = try await ring(room: roomID, notification: "$accepted")
        service.handleInAppRingDecision(roomID: roomID, accepted: true)
        #expect(service.callKitID(forRoomID: roomID) == accepted)

        // A redial answered from CallKit before the accepted ring's screen registered.
        let redial = try await ring(room: roomID, notification: "$redial")
        answer(redial)
        #expect(service.callKitID(forRoomID: roomID) == redial, "the live call comes before the accepted ring")

        let other = try await ring(room: "!q:example.com", notification: "$q")
        answer(other)
        #expect(service.heldCallPublisher.value?.roomID == roomID, "precondition: the redial is parked")
        #expect(service.callKitID(forRoomID: roomID) == redial, "the held call comes before the accepted ring")
        #expect(service.callKitID(forRoomID: "!q:example.com") == other)
    }

    /// Earlier follow-up 6a: CallKit refused the ring (Do Not Disturb), so it
    /// rang in the app only. Its registration then only updated a CallKit call
    /// that did not exist: no start action, so no audio activation, no system
    /// call UI and no hold.
    @Test
    func aRingCallKitRefusedRegistersWithAStartAction() async throws {
        service = makeService(notificationCenter: UserNotificationCenterMock())
        let roomID = "!b:example.com"
        let room = JoinedRoomProxyMock(.init(id: roomID, hasOngoingCall: true))
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        clientProxyMock.roomForIdentifierClosure = { _ in .joined(room) }
        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(CXErrorCodeIncomingCallError(.filteredByDoNotDisturb))
        }
        let ringID = try await ring(room: roomID, notification: "$b")
        service.handleInAppRingDecision(roomID: roomID, accepted: true)

        let registered = await service.setupCallSession(roomID: roomID, roomDisplayName: "Room B", isVoiceCall: true)

        #expect(registered == ringID)
        let starts = callController.requestedTransactions.flatMap(\.actions).compactMap { $0 as? CXStartCallAction }
        #expect(starts.map(\.callUUID) == [ringID], "CallKit starts the call it never had")
    }

    /// Review nit: a registration that took the room's accepted ring but
    /// adopted another ring of the room, a redial in the slot, dropped the
    /// accepted one and kept its refused record.
    @Test
    func anAcceptedRingPassedOverForARedialLeavesNoRefusedRecord() async throws {
        let roomID = "!b:example.com"
        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(CXErrorCodeIncomingCallError(.filteredByDoNotDisturb))
        }
        let first = try await ring(room: roomID, notification: "$first")
        service.handleInAppRingDecision(roomID: roomID, accepted: true)
        let redial = try await ring(room: roomID, notification: "$redial")
        #expect(service.ringsCallKitRefused == [first, redial], "precondition")

        let registered = await service.setupCallSession(roomID: roomID, roomDisplayName: "Room B", isVoiceCall: true)

        #expect(registered == redial)
        #expect(service.ringsCallKitRefused.isEmpty)
    }

    /// A ring CallKit presented and the user answered there is CallKit's call
    /// already: its registration starts nothing.
    @Test
    func aRingCallKitPresentedRegistersWithoutAStartAction() async throws {
        service = makeService(notificationCenter: UserNotificationCenterMock())
        let roomID = "!b:example.com"
        let room = JoinedRoomProxyMock(.init(id: roomID, hasOngoingCall: true))
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        clientProxyMock.roomForIdentifierClosure = { _ in .joined(room) }
        let ringID = try await ring(room: roomID, notification: "$b")
        answer(ringID)

        let registered = await service.setupCallSession(roomID: roomID, roomDisplayName: "Room B", isVoiceCall: true)

        #expect(registered == ringID)
        let starts = callController.requestedTransactions.flatMap(\.actions).compactMap { $0 as? CXStartCallAction }
        #expect(starts.isEmpty)
    }

    /// Earlier follow-up 6b: an outgoing call registering while another
    /// room's ring was up cleared that ring silently. A CallKit banner stayed
    /// up with nothing behind it (answering failed the UUID guard, ending it
    /// declined nothing) and an in-app ring kept ringing. The user is calling
    /// out instead of answering, so the ring ends as their decline.
    @Test
    func anOutgoingCallDeclinesTheRingItReplaces() async throws {
        let notificationCenter = UserNotificationCenterMock()
        service = makeService(notificationCenter: notificationCenter)
        let ringingRoomID = "!b:example.com"
        let room = JoinedRoomProxyMock(.init(id: ringingRoomID, hasOngoingCall: true))
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        room.declineCallNotificationIDReturnValue = .success(())
        clientProxyMock.roomForIdentifierClosure = { _ in .joined(room) }
        var stops = [String]()
        let cancellable = service.actions.sink { if case .stopInAppRinging(let roomID) = $0 { stops.append(roomID) } }
        let ringID = try await ring(room: ringingRoomID, notification: "$b")
        try await Task.sleep(for: .milliseconds(50))

        await service.setupCallSession(roomID: "!a:example.com", roomDisplayName: "Room A", isVoiceCall: true)

        #expect(callProvider.reportCallWithEndedAtReasonReceivedInvocations.contains { $0.uuid == ringID && $0.reason == .declinedElsewhere },
                "CallKit takes the ring down")
        #expect(stops == [ringingRoomID], "so does the app")
        var attempts = 0
        while !room.declineCallNotificationIDCalled, attempts < 100 {
            attempts += 1
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(room.declineCallNotificationIDReceivedNotificationID == "$b", "the caller hears the decline")
        #expect(notificationCenter.addCallsCount == 0, "not a missed call: the user called out")
        _ = cancellable
    }

    /// Review item 8: a call of a room placed again in the seconds its last
    /// screen takes to stop (the end tone, the Matrix leave) found the dying
    /// call still ongoing. The room showed it as live, so the new screen took
    /// the join path, took the dying call for its own and registered onto
    /// it, and the old screen's teardown then ended that CallKit call under
    /// the new screen's session.
    @Test
    func aScreenOpenedWhileTheLastOneStopsRegistersACallOfItsOwn() async throws {
        service = makeService(notificationCenter: UserNotificationCenterMock())
        let roomID = "!a:example.com"
        let room = JoinedRoomProxyMock(.init(id: roomID, hasOngoingCall: true))
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        clientProxyMock.roomForIdentifierClosure = { _ in .joined(room) }
        let first = try await ring(room: roomID, notification: "$first")
        answer(first)
        let leave = LookupGate()
        let dying = makeCallScreen(roomID: roomID, leave: leave)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room A", isVoiceCall: true)
        #expect(dying.callKitID == first, "precondition")

        dying.stop()

        #expect(service.ongoingCallRoomIDPublisher.value == nil, "the room's call is over for the app")
        let next = makeCallScreen(roomID: roomID, leave: LookupGate())
        #expect(next.callKitID == nil, "the new screen does not take the dying call")
        let registered = try #require(await service.setupCallSession(roomID: roomID, roomDisplayName: "Room A", isVoiceCall: true))
        #expect(registered != first)
        let starts = callController.requestedTransactions.flatMap(\.actions).compactMap { $0 as? CXStartCallAction }
        #expect(starts.map(\.callUUID) == [registered], "a CallKit call of its own")

        leave.open()
        try await waitForTheEnd(of: dying)
        #expect(service.callKitID(forRoomID: roomID) == registered, "the old screen's teardown leaves the new call")
        #expect(service.ongoingCallRoomIDPublisher.value == roomID)
    }

    /// Review of 6b (medium): the user accepted an in-app ring of room B
    /// while an outgoing call to C was still connecting. C's registration
    /// declined B (its caller saw "declined"), and B's screen then found its
    /// ring gone. The accepted ring is its own screen's: C's registration
    /// leaves it, C waits behind it, and B's registration adopts it.
    @Test
    func anAcceptedRingOutlivesAnOutgoingRegistration() async throws {
        let rooms = try await acceptInAppRingOfB(withALiveCall: false)

        await service.setupCallSession(roomID: rooms.c, roomDisplayName: "Room C", isVoiceCall: true)

        #expect(!callProvider.reportCallWithEndedAtReasonReceivedInvocations.contains { $0.uuid == rooms.b }, "B is not ended")
        #expect(rooms.stops.value.isEmpty, "B's ring is not taken down")
        #expect(service.isAcceptedRingLive(forRoomID: rooms.bRoomID))
        #expect(service.heldCallPublisher.value?.roomID == rooms.c, "C waits behind the accepted ring")
        try await Task.sleep(for: .milliseconds(50))
        #expect(!rooms.room.declineCallNotificationIDCalled, "B's caller is not declined")

        let registered = await service.setupCallSession(roomID: rooms.bRoomID, roomDisplayName: "Room B", isVoiceCall: true)
        #expect(registered == rooms.b)
        #expect(service.ongoingCallRoomIDPublisher.value == rooms.bRoomID)
        #expect(service.heldCallPublisher.value?.roomID == rooms.c)
        _ = rooms.cancellable
    }

    /// The same with a call live at the accept, parked for B: C, an
    /// outgoing call, replaces that call as before, and B dropped silently.
    /// Both now end the same way.
    @Test
    func anAcceptedRingOutlivesAnOutgoingRegistrationWithACallLive() async throws {
        let rooms = try await acceptInAppRingOfB(withALiveCall: true)

        await service.setupCallSession(roomID: rooms.c, roomDisplayName: "Room C", isVoiceCall: true)

        #expect(!callProvider.reportCallWithEndedAtReasonReceivedInvocations.contains { $0.uuid == rooms.b }, "B is not ended")
        #expect(service.isAcceptedRingLive(forRoomID: rooms.bRoomID))
        #expect(service.heldCallPublisher.value?.roomID == rooms.c, "C waits behind the accepted ring")
        try await Task.sleep(for: .milliseconds(50))
        #expect(!rooms.room.declineCallNotificationIDCalled, "B's caller is not declined")

        let registered = await service.setupCallSession(roomID: rooms.bRoomID, roomDisplayName: "Room B", isVoiceCall: true)
        #expect(registered == rooms.b)
        #expect(service.heldCallPublisher.value?.roomID == rooms.c)
        _ = rooms.cancellable
    }

    /// Review of the accepted-ring fix: C is parked while CallKit knows it
    /// only as connecting, and CallKit may refuse that hold. The refusal was
    /// only logged, so C's session never held: a group call kept its
    /// microphone live under B, a ringing DM its ringback.
    @Test
    func aRefusedHoldOfTheOutgoingCallStillHoldsItsSession() async throws {
        let rooms = try await acceptInAppRingOfB(withALiveCall: false)
        callController.refusesHolds = true
        let leave = LookupGate()
        leave.open()
        let (screen, session) = makeCallScreenAndSession(roomID: rooms.c, leave: leave)
        var holds = [String]()
        let cancellable = service.actions.sink { if case .setCallHeld(true, let roomID) = $0 { holds.append(roomID) } }

        await service.setupCallSession(roomID: rooms.c, roomDisplayName: "Room C", isVoiceCall: true)
        try await eventually { !holds.isEmpty }

        #expect(service.heldCallPublisher.value?.roomID == rooms.c, "precondition: C is parked")
        #expect(holds == [rooms.c], "the session holds without CallKit")
        try await eventually { session.state == .onHold }
        #expect(session.state == .onHold)
        withExtendedLifetime(screen) { }
        _ = cancellable
        _ = rooms.cancellable
    }

    /// Operator question 93: two in-app rings accepted before the first one's
    /// screen registers. The first registration found no ring of its room
    /// and took the outgoing path, whose teardown ended the call parked at
    /// the first tap. The latest tap wins: the first accept is given up, its
    /// screen comes down, and no live call ends.
    @Test
    func aSecondInAppAcceptGivesUpTheFirst() async throws {
        service = makeService(notificationCenter: UserNotificationCenterMock())
        let rooms = ["!a:example.com", "!b1:example.com", "!b2:example.com"].map { JoinedRoomProxyMock(.init(id: $0, hasOngoingCall: true)) }
        for room in rooms {
            room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        }
        clientProxyMock.roomForIdentifierClosure = { roomID in rooms.first { $0.id == roomID }.map { .joined($0) } }
        let a = try await ring(room: "!a:example.com", notification: "$a")
        answer(a)
        await service.setupCallSession(roomID: "!a:example.com", roomDisplayName: "Room A", isVoiceCall: true)
        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(CXErrorCodeIncomingCallError(.filteredByDoNotDisturb))
        }
        var ends = [String]()
        let cancellable = service.actions.sink { if case .endCall(let roomID) = $0 { ends.append(roomID) } }
        _ = try await ring(room: "!b1:example.com", notification: "$b1")
        service.handleInAppRingDecision(roomID: "!b1:example.com", accepted: true)
        let leave = LookupGate()
        leave.open()
        let (first, firstSession) = makeCallScreenAndSession(roomID: "!b1:example.com", leave: leave)
        var firstDismissals = 0
        let firstActions = first.actions.sink { if case .dismiss = $0 { firstDismissals += 1 } }
        let b2 = try await ring(room: "!b2:example.com", notification: "$b2")

        service.handleInAppRingDecision(roomID: "!b2:example.com", accepted: true)

        #expect(ends == ["!b1:example.com"], "the first accept's screen is told")
        #expect(firstDismissals == 1, "the first accept's screen comes down")
        #expect(service.callKitID(forRoomID: "!b1:example.com") == nil)
        // Should its registration still come, it finds its call gone and dismisses again.
        first.nativeCallSession(firstSession, didChangeState: .connected)
        try await eventually { firstDismissals == 2 }
        #expect(firstDismissals == 2)
        let starts = callController.requestedTransactions.flatMap(\.actions).compactMap { $0 as? CXStartCallAction }
        #expect(starts.isEmpty, "the first screen registers nothing")
        #expect(endActions(for: a) == 0, "the call parked at the first tap is not ended")
        #expect(service.heldCallPublisher.value?.roomID == "!a:example.com", "it waits for the second answer")
        #expect(!rooms[1].declineCallNotificationIDCalled, "the first caller is not declined")

        let registered = await service.setupCallSession(roomID: "!b2:example.com", roomDisplayName: "Room B2", isVoiceCall: true)
        #expect(registered == b2)
        #expect(service.heldCallPublisher.value?.roomID == "!a:example.com")
        _ = cancellable
        _ = firstActions
    }

    /// L3 review: a stopping screen in the room of a newer call (a redial
    /// answered during its stop) rewrote that call's CallKit video state and
    /// name with its own: the update matched the room, not the screen's call.
    @Test
    func aStoppingScreensVideoStateLeavesTheNewerCallOfItsRoomAlone() async throws {
        service = makeService(notificationCenter: UserNotificationCenterMock())
        let roomID = "!a:example.com"
        let room = JoinedRoomProxyMock(.init(id: roomID, hasOngoingCall: true))
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        clientProxyMock.roomForIdentifierClosure = { _ in .joined(room) }
        let x = try await ring(room: roomID, notification: "$x")
        answer(x)
        let leave = LookupGate()
        let (stopping, stoppingSession) = makeCallScreenAndSession(roomID: roomID, leave: leave)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room A", isVoiceCall: true)
        stopping.stop()
        let redial = try await ring(room: roomID, notification: "$redial")
        answer(redial)
        #expect(service.ongoingCallRoomIDPublisher.value == roomID, "precondition: the redial is the room's call")
        let updatesBefore = callProvider.reportCallWithUpdatedReceivedInvocations.count

        stopping.nativeCallSession(stoppingSession, didChangeActiveVideo: true, isSpeakerEnabled: false)

        #expect(!callProvider.reportCallWithUpdatedReceivedInvocations.dropFirst(updatesBefore).contains { $0.uuid == redial })
        leave.open()
        try await waitForTheEnd(of: stopping)
    }

    /// L4 review: the first in-app accept was of a redial whose room's call
    /// was stopping. A second accept gave the first up but left its screen
    /// up: the room's slot call, merely ending, was taken for a call whose
    /// screen that would be.
    @Test
    func aSecondInAppAcceptBringsTheFirstDownWhileItsRoomsCallStops() async throws {
        service = makeService(notificationCenter: UserNotificationCenterMock())
        let rooms = ["!b1:example.com", "!b2:example.com"].map { JoinedRoomProxyMock(.init(id: $0, hasOngoingCall: true)) }
        for room in rooms {
            room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        }
        clientProxyMock.roomForIdentifierClosure = { roomID in rooms.first { $0.id == roomID }.map { .joined($0) } }
        let old = try await ring(room: "!b1:example.com", notification: "$old")
        answer(old)
        await service.setupCallSession(roomID: "!b1:example.com", roomDisplayName: "Room B1", isVoiceCall: true)
        service.markCallEnding(callKitID: old)
        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(CXErrorCodeIncomingCallError(.filteredByDoNotDisturb))
        }
        _ = try await ring(room: "!b1:example.com", notification: "$redial")
        service.handleInAppRingDecision(roomID: "!b1:example.com", accepted: true)
        var ends = [String]()
        let cancellable = service.actions.sink { if case .endCall(let roomID) = $0 { ends.append(roomID) } }
        _ = try await ring(room: "!b2:example.com", notification: "$b2")

        service.handleInAppRingDecision(roomID: "!b2:example.com", accepted: true)

        #expect(ends == ["!b1:example.com"], "the first accept's screen comes down at once")
        #expect(service.callKitID(forRoomID: "!b1:example.com") == nil)
        _ = cancellable
    }

    /// Residual of item 8: a redial push for a room whose call's screen is
    /// stopping was reported as a duplicate and never rang. It rings now.
    /// This device's own membership, which lingers in the room's call until
    /// its leave syncs back, is not an answer elsewhere; answering the redial
    /// ends the stopping call rather than parking it.
    @Test
    func aRedialDuringAStopRings() async throws {
        service = makeService(notificationCenter: UserNotificationCenterMock())
        let roomID = "!a:example.com"
        let room = JoinedRoomProxyMock(.init(id: roomID, hasOngoingCall: true))
        let roomInfo = CurrentValueSubject<RoomInfoProxyProtocol, Never>(room.infoPublisher.value)
        room.infoPublisher = roomInfo.asCurrentValuePublisher()
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        let rtcSession = roomCallMemberships(of: room, [.init(userID: room.ownUserID, deviceID: "THIS", identity: "\(room.ownUserID):THIS"), Self.caller])
        clientProxyMock.roomForIdentifierClosure = { _ in .joined(room) }
        let x = try await ring(room: roomID, notification: "$x")
        answer(x)
        let leave = LookupGate()
        let stopping = makeCallScreen(roomID: roomID, leave: leave)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room A", isVoiceCall: true)
        stopping.stop()

        let redial = try await ring(room: roomID, notification: "$redial")
        try await Task.sleep(for: .milliseconds(50))
        #expect(!callProvider.reportCallWithEndedAtReasonReceivedInvocations.contains { $0.uuid == redial }, "the redial rings")
        roomInfo.send(RoomInfoProxyMock(.init(id: roomID, hasOngoingCall: true, activeRoomCallParticipants: [room.ownUserID, "@caller:example.com"])))
        try await eventually { rtcSession.membershipsCalled }
        try await Task.sleep(for: .milliseconds(50))
        #expect(!callProvider.reportCallWithEndedAtReasonReceivedInvocations.contains { $0.uuid == redial },
                "this device's lingering membership is not an answer elsewhere")

        answer(redial)

        #expect(service.ongoingCallRoomIDPublisher.value == roomID)
        #expect(service.heldCallPublisher.value == nil, "the stopping call is not parked")
        #expect(endActions(for: x) == 1, "it is ended")
        leave.open()
        try await waitForTheEnd(of: stopping)
        #expect(service.callKitID(forRoomID: roomID) == redial, "its screen's teardown leaves the redial")
    }

    /// Residual of the redial round: while this device's call in the room
    /// ends, another of the user's devices answering the redial was not seen
    /// until the room's call members changed again. This device's own
    /// membership is matched by its device ID now, so the other device's
    /// answers.
    @Test
    func anotherDeviceAnsweringARedialDuringAStopEndsTheRing() async throws {
        service = makeService(notificationCenter: UserNotificationCenterMock())
        let roomID = "!a:example.com"
        let room = JoinedRoomProxyMock(.init(id: roomID, hasOngoingCall: true))
        let roomInfo = CurrentValueSubject<RoomInfoProxyProtocol, Never>(room.infoPublisher.value)
        room.infoPublisher = roomInfo.asCurrentValuePublisher()
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        let thisDevice = MatrixRTCParticipant(userID: room.ownUserID, deviceID: "THIS", identity: "\(room.ownUserID):THIS")
        let rtcSession = roomCallMemberships(of: room, [thisDevice, Self.caller])
        clientProxyMock.roomForIdentifierClosure = { _ in .joined(room) }
        let x = try await ring(room: roomID, notification: "$x")
        answer(x)
        let leave = LookupGate()
        let stopping = makeCallScreen(roomID: roomID, leave: leave)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room A", isVoiceCall: true)
        stopping.stop()
        let redial = try await ring(room: roomID, notification: "$redial")
        try await Task.sleep(for: .milliseconds(50))

        rtcSession.membershipsReturnValue = .success([thisDevice, Self.caller,
                                                      .init(userID: room.ownUserID, deviceID: "OTHER", identity: "\(room.ownUserID):OTHER")])
        roomInfo.send(RoomInfoProxyMock(.init(id: roomID, hasOngoingCall: true,
                                              activeRoomCallParticipants: [room.ownUserID, "@caller:example.com", room.ownUserID])))
        try await eventually { callProvider.reportCallWithEndedAtReasonReceivedInvocations.contains { $0.uuid == redial } }

        #expect(callProvider.reportCallWithEndedAtReasonReceivedInvocations.contains { $0.uuid == redial && $0.reason == .answeredElsewhere },
                "the other device answered")
        #expect(!service.isAcceptedRingLive(forRoomID: roomID))
        leave.open()
        try await waitForTheEnd(of: stopping)
    }

    /// The room's call memberships, as its MatrixRTC session reads them.
    /// This device is `THIS`.
    private func roomCallMemberships(of room: JoinedRoomProxyMock, _ memberships: [MatrixRTCParticipant]) -> MatrixRTCSessionMock {
        clientProxyMock.deviceID = "THIS"
        let rtcSession = MatrixRTCSessionMock()
        rtcSession.underlyingOwnIdentity = "\(room.ownUserID):THIS"
        rtcSession.underlyingUpdates = Empty().eraseToAnyPublisher()
        rtcSession.membershipsReturnValue = .success(memberships)
        room.matrixRTCSessionReturnValue = .success(rtcSession)
        return rtcSession
    }

    nonisolated static let caller = MatrixRTCParticipant(userID: "@caller:example.com", deviceID: "CALLER", identity: "@caller:example.com:CALLER")

    /// L1 review: a redelivered push of the call whose screen is stopping
    /// (an APNs retry, the NSE run again) passed for a redial and rang again.
    @Test
    func aRedeliveredPushOfAStoppingCallIsADuplicate() async throws {
        let x = try await ring(room: "!a:example.com", notification: "$x")
        answer(x)
        await service.setupCallSession(roomID: "!a:example.com", roomDisplayName: "Room A", isVoiceCall: true)
        service.markCallEnding(callKitID: x)

        await expectImmediatelyEndedCallReported(forPayload: redelivery(room: "!a:example.com", notification: "$x"),
                                                 expectedReason: .answeredElsewhere)
    }

    /// Nor does one of the call parked behind the active one.
    @Test
    func aRedeliveredPushOfTheParkedCallIsADuplicate() async throws {
        _ = try await twoCalls()

        await expectImmediatelyEndedCallReported(forPayload: redelivery(room: "!a:example.com", notification: "$a"),
                                                 expectedReason: .answeredElsewhere)
        #expect(service.heldCallPublisher.value?.roomID == "!a:example.com")
    }

    private func redelivery(room: String, notification: String) -> PKPushPayloadMock {
        let push = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30).updateIsVoice(true)
        push.dict[CallKitNotificationKey.roomID.rawValue] = room
        push.dict[CallKitNotificationKey.rtcNotifyEventID.rawValue] = notification
        return push
    }

    /// A refused hold that arrives after the call became active again (its
    /// accepted ring was given up, so it was un-parked) must not hold it.
    @Test
    func aLateRefusedHoldDoesNotHoldACallThatIsActiveAgain() async throws {
        let rooms = try await acceptInAppRingOfB(withALiveCall: false)
        callController.refusesHolds = true
        callController.defersRefusals = true
        var holds = [String]()
        let cancellable = service.actions.sink { if case .setCallHeld(true, let roomID) = $0 { holds.append(roomID) } }
        await service.setupCallSession(roomID: rooms.c, roomDisplayName: "Room C", isVoiceCall: true)
        service.tearDownCallSession(forRoomID: rooms.bRoomID)
        #expect(service.heldCallPublisher.value == nil, "precondition: C is active again")

        callController.deliverRefusals()
        try await Task.sleep(for: .milliseconds(50))

        #expect(holds.isEmpty, "the late refusal does not hold the active call")
        _ = cancellable
        _ = rooms.cancellable
    }

    /// And a refused resume that arrives after the call was parked again
    /// must not resume it.
    @Test
    func aLateRefusedResumeDoesNotResumeACallThatIsParkedAgain() async throws {
        let (a, b) = try await twoCalls()
        let c = try await ring(room: "!c:example.com", notification: "$c")
        callController.refusesResumes = true
        callController.defersRefusals = true
        var resumes = [String]()
        let cancellable = service.actions.sink { if case .setCallHeld(false, let roomID) = $0 { resumes.append(roomID) } }
        service.tearDownCallSession(forRoomID: "!b:example.com", callKitID: b)
        #expect(service.ongoingCallRoomIDPublisher.value == "!a:example.com", "precondition: A was promoted")
        answer(c)
        #expect(service.heldCallPublisher.value?.roomID == "!a:example.com", "precondition: A is parked again")

        callController.deliverRefusals()
        try await Task.sleep(for: .milliseconds(50))

        #expect(resumes.isEmpty, "the late refusal does not resume the parked call")
        _ = a
        _ = cancellable
    }

    /// An in-app ring of room B, accepted while an outgoing call to room C
    /// connects (CallKit refused the ring: Do Not Disturb). With a live call
    /// in room A, A is parked at the tap.
    private func acceptInAppRingOfB(withALiveCall: Bool) async throws -> AcceptedRingOfB {
        service = makeService(notificationCenter: UserNotificationCenterMock())
        let rooms = ["!a:example.com", "!b:example.com"].map { JoinedRoomProxyMock(.init(id: $0, hasOngoingCall: true)) }
        for room in rooms {
            room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .success(TaskHandleSDKMock())
        }
        clientProxyMock.roomForIdentifierClosure = { roomID in rooms.first { $0.id == roomID }.map { .joined($0) } }
        if withALiveCall {
            let a = try await ring(room: "!a:example.com", notification: "$a")
            answer(a)
            await service.setupCallSession(roomID: "!a:example.com", roomDisplayName: "Room A", isVoiceCall: true)
        }
        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(CXErrorCodeIncomingCallError(.filteredByDoNotDisturb))
        }
        let stops = Box([String]())
        let cancellable = service.actions.sink { if case .stopInAppRinging(let roomID) = $0 { stops.value.append(roomID) } }
        let b = try await ring(room: "!b:example.com", notification: "$b")
        service.handleInAppRingDecision(roomID: "!b:example.com", accepted: true)
        return AcceptedRingOfB(b: b, bRoomID: "!b:example.com", c: "!c:example.com", room: rooms[1], stops: stops, cancellable: cancellable)
    }

    /// Review of item 8: a registration that lands after its screen began to
    /// stop was a live call the room showed as ongoing, and nothing would
    /// mark it ending.
    @Test
    func aRegistrationLandingAfterItsScreenStoppedIsEnding() async throws {
        service = makeService(notificationCenter: UserNotificationCenterMock())
        let roomID = "!a:example.com"
        let registering = LookupGate()
        callController.requestGate = registering
        let leave = LookupGate()
        leave.open()
        let (screen, session) = makeCallScreenAndSession(roomID: roomID, leave: leave)
        screen.nativeCallSession(session, didChangeState: .connected)
        try await eventually { !callController.requestedTransactions.isEmpty }
        #expect(!callController.requestedTransactions.isEmpty, "precondition: the registration is in flight")

        screen.stop()
        registering.open()
        try await eventually { screen.callKitID != nil }

        #expect(screen.callKitID != nil, "precondition: the registration landed")
        #expect(service.ongoingCallRoomIDPublisher.value == nil, "the call it registered is ending")
        #expect(service.callKitID(forRoomID: roomID) == nil)
        try await waitForTheEnd(of: screen)
    }

    /// And a stopped screen does not register at all.
    @Test
    func aStoppedScreenRegistersNothing() async throws {
        service = makeService(notificationCenter: UserNotificationCenterMock())
        let leave = LookupGate()
        leave.open()
        let (screen, session) = makeCallScreenAndSession(roomID: "!a:example.com", leave: leave)

        screen.nativeCallSession(session, didChangeState: .connected)
        screen.stop()
        try await Task.sleep(for: .milliseconds(100))

        let starts = callController.requestedTransactions.flatMap(\.actions).compactMap { $0 as? CXStartCallAction }
        #expect(starts.isEmpty)
        #expect(service.ongoingCallRoomIDPublisher.value == nil)
        try await waitForTheEnd(of: screen)
    }

    /// Review of item 8 (low): a ring of another room answered while the
    /// live call's screen stopped held that dying call behind the answer.
    @Test
    func anAnswerDuringAStopEndsTheStoppingCallInsteadOfHoldingIt() async throws {
        let x = try await ring(room: "!a:example.com", notification: "$a")
        answer(x)
        let leave = LookupGate()
        let stopping = makeCallScreen(roomID: "!a:example.com", leave: leave)
        await service.setupCallSession(roomID: "!a:example.com", roomDisplayName: "Room A", isVoiceCall: true)
        stopping.stop()

        let b = try await ring(room: "!b:example.com", notification: "$b")
        answer(b)

        #expect(service.heldCallPublisher.value == nil, "nothing is held for the answer")
        #expect(!holdActions().contains { $0.callUUID == x && $0.isOnHold })
        #expect(endActions(for: x) == 1, "CallKit ends the stopping call")
        #expect(service.ongoingCallRoomIDPublisher.value == "!b:example.com")
        leave.open()
        try await waitForTheEnd(of: stopping)
        #expect(endActions(for: x) == 1, "its screen's teardown finds it gone")
        #expect(service.ongoingCallRoomIDPublisher.value == "!b:example.com")
    }

    /// And a parked call whose screen stopped was resumed when the live call
    /// ended: a CallKit resume and an active-call change for a screen going
    /// away.
    @Test
    func aStoppingParkedCallIsNotResumedWhenTheLiveCallEnds() async throws {
        let (a, b) = try await twoCalls()
        var changes = [String]()
        let cancellable = service.actions.sink { if case .activeCallChanged(let roomID) = $0 { changes.append(roomID) } }
        let leave = LookupGate()
        let parked = makeCallScreen(roomID: "!a:example.com", leave: leave)
        #expect(parked.callKitID == a, "precondition: the parked call's screen")
        parked.stop()

        service.tearDownCallSession(forRoomID: "!b:example.com", callKitID: b)

        #expect(!holdActions().contains { $0.callUUID == a && !$0.isOnHold }, "not resumed")
        #expect(changes.isEmpty, "no screen is brought forward")
        #expect(service.heldCallPublisher.value == nil)
        #expect(service.ongoingCallRoomIDPublisher.value == nil)
        #expect(endActions(for: a) == 1, "CallKit ends it")
        leave.open()
        try await waitForTheEnd(of: parked)
        #expect(endActions(for: a) == 1)
        _ = cancellable
    }

    // MARK: - Replacing a screen that shows its call's end (M1 review)

    /// M1 review, the third-room variant: A parked behind B. B's screen
    /// showed its call's end and a call to C replaced it; B's late teardown
    /// brought A back. C's registration then ended A in CallKit without a
    /// word to A's screen, which stayed up with its session live.
    @Test
    func anOutgoingCallTellsTheScreenOfTheCallItReplaces() async throws {
        let (a, b) = try await twoCalls()
        var ends = [String]()
        let cancellable = service.actions.sink { if case .endCall(let roomID) = $0 { ends.append(roomID) } }
        service.markCallEnding(callKitID: b)
        service.tearDownCallSession(forRoomID: "!b:example.com", callKitID: b)
        #expect(service.ongoingCallRoomIDPublisher.value == "!a:example.com", "precondition: B's teardown brought A back")

        await service.setupCallSession(roomID: "!c:example.com", roomDisplayName: "Room C", isVoiceCall: true)

        #expect(endActions(for: a) == 1, "A is ended in CallKit")
        #expect(ends == ["!a:example.com"], "and its screen is told")
        #expect(service.ongoingCallRoomIDPublisher.value == "!c:example.com")
        _ = cancellable
    }

    /// M1 review: a screen showing its call's end, replaced by a fresh one of
    /// its room while A is parked. Its late teardown brought A back over the
    /// fresh screen, whose registration then ended A under it. Its call ends
    /// at the replacement now, and A stays parked until the fresh call
    /// registers: an outgoing one replaces A and tells A's screen.
    @Test
    func aReplacedScreensCallEndsAtOnceAndTheParkedCallStaysParked() async throws {
        let (a, b) = try await twoCalls()
        var actions = [CallKitServiceAction]()
        let cancellable = service.actions.sink { actions.append($0) }
        service.markCallEnding(callKitID: b)

        service.tearDownReplacedCallSession(forRoomID: "!b:example.com", callKitID: b)

        #expect(endActions(for: b) == 1, "B is ended now")
        #expect(service.heldCallPublisher.value?.roomID == "!a:example.com", "A stays parked")
        #expect(!holdActions().contains { $0.callUUID == a && !$0.isOnHold }, "A is not resumed")
        #expect(!actions.contains { if case .activeCallChanged = $0 { true } else { false } })
        // The replaced screen's own teardown finds its call gone.
        service.tearDownCallSession(forRoomID: "!b:example.com", callKitID: b)
        #expect(service.heldCallPublisher.value?.roomID == "!a:example.com")
        #expect(endActions(for: b) == 1)

        await service.setupCallSession(roomID: "!b:example.com", roomDisplayName: "Room B", isVoiceCall: true)

        #expect(endActions(for: a) == 1, "the fresh outgoing call replaces A")
        #expect(actions.contains { if case .endCall(roomID: "!a:example.com") = $0 { true } else { false } }, "and A's screen is told")
        #expect(service.ongoingCallRoomIDPublisher.value == "!b:example.com")
        _ = cancellable
    }

    /// The fresh screen is an in-app answer of the room's redial: A stays
    /// parked behind it. The replaced screen's late teardown used to bring A
    /// back, and the answer's registration parked it again.
    @Test
    func aReplacedScreensCallLeavesTheParkedCallToTheInAppAnswerOfItsRoom() async throws {
        let (a, b) = try await twoCalls()
        service.markCallEnding(callKitID: b)
        let redial = try await ring(room: "!b:example.com", notification: "$redial")
        service.handleInAppRingDecision(roomID: "!b:example.com", accepted: true)

        service.tearDownReplacedCallSession(forRoomID: "!b:example.com", callKitID: b)

        #expect(service.heldCallPublisher.value?.roomID == "!a:example.com", "A stays parked")
        #expect(!holdActions().contains { $0.callUUID == a && !$0.isOnHold }, "A is not resumed")
        let registered = await service.setupCallSession(roomID: "!b:example.com", roomDisplayName: "Room B", isVoiceCall: true, callKitID: redial)
        #expect(registered == redial, "the answer registers")
        #expect(service.heldCallPublisher.value?.roomID == "!a:example.com", "with A behind it")
        #expect(endActions(for: a) == 0)
    }

    /// The room's own new screen is the one registering: a call that replaces
    /// its room's stopping call tells no screen of its room to end.
    @Test
    func anOutgoingCallReplacingItsRoomsStoppingCallEndsNoScreenOfItsRoom() async throws {
        let x = try await ring(room: "!a:example.com", notification: "$x")
        answer(x)
        await service.setupCallSession(roomID: "!a:example.com", roomDisplayName: "Room A", isVoiceCall: true)
        var ends = [String]()
        let cancellable = service.actions.sink { if case .endCall(let roomID) = $0 { ends.append(roomID) } }
        service.markCallEnding(callKitID: x)

        await service.setupCallSession(roomID: "!a:example.com", roomDisplayName: "Room A", isVoiceCall: true)

        #expect(endActions(for: x) == 1, "the stopping call is ended")
        #expect(ends.isEmpty)
        _ = cancellable
    }

    private func endActions(for callKitID: UUID) -> Int {
        callController.requestedTransactions.flatMap(\.actions).compactMap { $0 as? CXEndCallAction }.count { $0.callUUID == callKitID }
    }

    /// A call screen over this service whose Matrix leave waits on `leave`,
    /// so the test decides when its teardown lands.
    private func makeCallScreen(roomID: String, leave: LookupGate) -> NativeCallScreenViewModel {
        makeCallScreenAndSession(roomID: roomID, leave: leave).screen
    }

    private func makeCallScreenAndSession(roomID: String, leave: LookupGate) -> (screen: NativeCallScreenViewModel, session: NativeCallSession) {
        let rtcSession = MatrixRTCSessionMock()
        rtcSession.underlyingOwnIdentity = "@me:spiral.md:DEVICE"
        rtcSession.underlyingUpdates = Empty().eraseToAnyPublisher()
        rtcSession.leaveClosure = {
            await leave.wait()
            return .success(())
        }
        let transport = NativeCallTransportMock()
        transport.underlyingEvents = Empty().eraseToAnyPublisher()
        transport.localIdentity = "@me:spiral.md:DEVICE"
        transport.remoteParticipants = []
        transport.remoteTracks = []
        transport.underlyingIsLocalSpeaking = false
        transport.underlyingLocalConnectionQuality = .unknown
        transport.underlyingIsMicrophoneEnabled = false
        transport.underlyingIsCameraEnabled = false
        // A hold re-walks the media plan.
        transport.setSubscriptionsAuthorizedIdentitiesIsTrackExcludedClosure = { _, _ in true }
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .direct),
                                        transport: transport)
        let screen = NativeCallScreenViewModel(session: session,
                                               callKitService: service,
                                               agentCenter: NativeAgentCenterController(agentPlatformService: nil,
                                                                                        roomID: roomID,
                                                                                        roomMemberMxids: { [] },
                                                                                        inviteAgent: { _ in false }),
                                               appMediator: AppMediatorMock(.init()),
                                               haptics: .none,
                                               isVideoCall: false,
                                               roomID: roomID,
                                               roomName: "Room A")
        return (screen, session)
    }

    /// Polls `condition` for up to a second.
    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// The screen's session has ended; its teardown follows on the same task.
    private func waitForTheEnd(of screen: NativeCallScreenViewModel) async throws {
        for _ in 0..<500 {
            if case .ended = screen.context.viewState.callState { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .ended = screen.context.viewState.callState else {
            Issue.record("the screen's session never ended")
            return
        }
        try await Task.sleep(for: .milliseconds(100))
    }
}

nonisolated class PKPushPayloadMock: PKPushPayload {
    var dict: [AnyHashable: Any] = [:]
    
    override init() {
        dict[CallKitNotificationKey.roomID.rawValue] = "!room:example.com"
        dict[CallKitNotificationKey.roomDisplayName.rawValue] = "welcome"
        dict[CallKitNotificationKey.callerID.rawValue] = "@tester:spiral.md"
        dict[CallKitNotificationKey.callerDisplayName.rawValue] = "Tester"
        dict[CallKitNotificationKey.rtcNotifyEventID.rawValue] = "$000"
        dict[CallKitNotificationKey.remainingRingSeconds.rawValue] = 0
    }
    
    override var dictionaryPayload: [AnyHashable: Any] {
        dict
    }
    
    /// The `from` anchor is deliberately unused now (audit W6-5-3).
    ///
    /// The payload carries how long the ring has LEFT, computed by the NSE
    /// from two server timestamps, so no absolute instant crosses the
    /// boundary and the device's clock cannot disagree with the
    /// homeserver's. Keeping the parameter means the call sites read the
    /// same; that it no longer matters IS the fix.
    func updatingExpiration(_: Date, lifetime: TimeInterval) -> Self {
        dict[CallKitNotificationKey.remainingRingSeconds.rawValue] = Int(lifetime)
        return self
    }
    
    func updateIsVoice(_ isVoice: Bool) -> Self {
        dict[CallKitNotificationKey.isVoiceCall.rawValue] = isVoice
        return self
    }
    
    func updateIsDM(_ isDM: Bool) -> Self {
        dict[CallKitNotificationKey.isDM.rawValue] = isDM
        return self
    }
}

/// A value a test's sink writes and the test reads.
private final class Box<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private struct AcceptedRingOfB {
    let b: UUID
    let bRoomID: String
    let c: String
    let room: JoinedRoomProxyMock
    let stops: Box<[String]>
    let cancellable: AnyCancellable
}

private struct AcceptedInAppRing {
    let a: UUID
    let b: UUID
    let roomB: JoinedRoomProxyMock
    let roomBInfo: CurrentValueSubject<RoomInfoProxyProtocol, Never>
}

/// Real ownership tokens, no audio: LiveKit's `AudioManager` cannot run in a
/// test process, while the claim/release balance and which deactivation reaches
/// the native stack are exactly what these tests are about.
private final class NativeCallAudioControlSpy: NativeCallAudioControlling {
    private var ownership = NativeCallAudioOwnership()
    private(set) var claims = 0
    private(set) var releases = 0
    private(set) var activations = 0
    private(set) var deactivations = 0

    var isActivationWindowHeld: Bool {
        ownership.isHeld
    }

    func claimActivationWindow() -> NativeCallAudioOwner {
        claims += 1
        return ownership.claim()
    }

    func releaseActivationWindow(_ owner: NativeCallAudioOwner) {
        releases += 1
        _ = ownership.release(owner)
    }

    func callKitDidActivate(_ audioSession: AVAudioSession) {
        activations += 1
    }

    func callKitDidDeactivate(_ audioSession: AVAudioSession) {
        deactivations += 1
    }
}

private final class CXCallControllerMock: CXCallControllerProtocol {
    private(set) var requestedTransactions = [CXTransaction]()
    /// When set, the async `request` suspends until the gate opens.
    var requestGate: LookupGate?
    /// CallKit refusing to hold a call, as it may for one still connecting.
    var refusesHolds = false
    /// And to resume one.
    var refusesResumes = false
    /// Refusals wait for `deliverRefusals()`: an error that arrives late.
    var defersRefusals = false
    private var deferredRefusals = [() -> Void]()

    func deliverRefusals() {
        let refusals = deferredRefusals
        deferredRefusals = []
        refusals.forEach { $0() }
    }

    func request(_ transaction: CXTransaction) async throws {
        requestedTransactions.append(transaction)
        await requestGate?.wait()
    }

    func request(_ transaction: CXTransaction, completion: @escaping @Sendable (Error?) -> Void) {
        requestedTransactions.append(transaction)
        let holds = transaction.actions.compactMap { $0 as? CXSetHeldCallAction }
        let isRefused = (refusesHolds && holds.contains(where: \.isOnHold)) || (refusesResumes && holds.contains { !$0.isOnHold })
        guard isRefused else {
            completion(nil)
            return
        }
        let error = CXErrorCodeRequestTransactionError(.unknown)
        if defersRefusals {
            deferredRefusals.append { completion(error) }
        } else {
            completion(error)
        }
    }
}

/// A manually-opened suspension point for scripting "the next ring arrived
/// while this room lookup was in flight".
private final class LookupGate: @unchecked Sendable {
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
        let waiting: [CheckedContinuation<Void, Never>] = lock.withLock {
            isOpen = true
            defer { continuations.removeAll() }
            return continuations
        }
        waiting.forEach { $0.resume() }
    }
}
