//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
@testable import ElementX
import Testing

@MainActor
struct NativeCallScreenCoordinatorTests {
    /// A call can start from Recents, a push notification or the room list, and
    /// none of those open the room — so the live timeline is unsubscribed and
    /// its item provider does not exist. Building the call screen used to read
    /// it for the Agent Center doorbell and crashed on the implicitly
    /// unwrapped provider; the doorbell now rides the agents' own state
    /// documents, so a call touches no timeline at all.
    @Test
    func buildingTheCallScreenTouchesNoTimeline() async throws {
        let roomProxy = JoinedRoomProxyMock(.init())
        roomProxy.matrixRTCSessionReturnValue = .success(makeRTCSession())
        let timeline = try #require(roomProxy.timeline as? TimelineProxyMock)

        let coordinator = NativeCallScreenCoordinator(parameters: .init(roomProxy: roomProxy,
                                                                        callKitService: CallKitServiceMock(.init()),
                                                                        agentPlatformService: nil,
                                                                        isRoomEncrypted: false,
                                                                        notifyRoom: false,
                                                                        isAnswer: false,
                                                                        configuration: .init(media: .audio, scope: .direct),
                                                                        appMediator: AppMediatorMock(.init()),
                                                                        mediaProvider: nil))

        // Give any deferred work a chance to run before asserting the absence.
        try await Task.sleep(for: .milliseconds(100))
        #expect(!timeline.subscribeForUpdatesCalled)

        withExtendedLifetime(coordinator) { }
    }

    /// Brief 0068 Slice 2 — the lesson of attempt 1: the tab coordinator
    /// `stop()`s the overlay it replaces and `start()`s the one it presents.
    /// A PARKED call screen must survive the first and not re-join on the
    /// second; only an un-parked stop ends the call.
    @Test
    func aParkedCallScreenSurvivesReplacementAndDoesNotRejoinOnReturn() async throws {
        let roomProxy = JoinedRoomProxyMock(.init())
        let rtcSession = makeRTCSession()
        rtcSession.leaveReturnValue = .success(())
        roomProxy.matrixRTCSessionReturnValue = .success(rtcSession)
        let callKitService = CallKitServiceMock(.init())
        let coordinator = NativeCallScreenCoordinator(parameters: .init(roomProxy: roomProxy,
                                                                        callKitService: callKitService,
                                                                        agentPlatformService: nil,
                                                                        isRoomEncrypted: false,
                                                                        notifyRoom: false,
                                                                        isAnswer: false,
                                                                        configuration: .init(media: .audio, scope: .direct),
                                                                        appMediator: AppMediatorMock(.init()),
                                                                        mediaProvider: nil))
        coordinator.start()
        try await Task.sleep(for: .milliseconds(300))
        // The real transport behind this coordinator fails its connect in a
        // test process, so the session's own start outcome is not the
        // subject here; what the coordinator does with stop()/start() is.
        let joinsAfterFirstStart = rtcSession.joinEncryptMediaNotificationMediaCallsCount
        let leavesAfterFirstStart = rtcSession.leaveCallsCount
        let teardownsAfterFirstStart = callKitService.tearDownCallSessionForRoomIDCallKitIDCallsCount

        // Replaced while parked: the overlay's teardown reaches stop().
        coordinator.isParked = true
        coordinator.stop()
        try await Task.sleep(for: .milliseconds(200))
        #expect(rtcSession.leaveCallsCount == leavesAfterFirstStart, "a parked call is not left")
        #expect(callKitService.tearDownCallSessionForRoomIDCallKitIDCallsCount == teardownsAfterFirstStart,
                "nor torn down in CallKit")

        // Brought back: presented again, so start() runs again.
        coordinator.isParked = false
        coordinator.start()
        try await Task.sleep(for: .milliseconds(200))
        #expect(rtcSession.joinEncryptMediaNotificationMediaCallsCount == joinsAfterFirstStart, "no second join")

        // An un-parked stop is the real thing.
        coordinator.stop()
        try await Task.sleep(for: .milliseconds(300))
        #expect(callKitService.tearDownCallSessionForRoomIDCallKitIDCallsCount == teardownsAfterFirstStart + 1,
                "the un-parked stop tears the call down")
    }

    private func makeRTCSession() -> MatrixRTCSessionMock {
        let rtcSession = MatrixRTCSessionMock()
        rtcSession.underlyingOwnIdentity = "@alice:matrix.org:DEVICE"
        rtcSession.underlyingUpdates = Empty().eraseToAnyPublisher()
        rtcSession.joinEncryptMediaNotificationMediaReturnValue = .success(())
        rtcSession.setMediaReturnValue = .success(())
        rtcSession.rtcNotificationEventIDReturnValue = "$ring:matrix.org"
        rtcSession.transportCredentialsReturnValue = .failure(.roomInvalid)
        rtcSession.membershipsReturnValue = .success([.init(userID: "@bob:matrix.org", deviceID: "BOB", identity: "@bob:matrix.org:BOB")])
        return rtcSession
    }
}
