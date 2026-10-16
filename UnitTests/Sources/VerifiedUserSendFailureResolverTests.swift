//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066 § 5.87): the resolve screen for a send that did
// not go through the send queue, and that its queue behaviour did not move.
//

@testable import ElementX
import Testing

@MainActor
struct VerifiedUserSendFailureResolverTests {
    private let alice = "@alice:matrix.org"
    private let bob = "@bob:matrix.org"

    // MARK: - The send queue: upstream's behaviour

    /// Every answer ignores the WHOLE failure and resends, exactly as before
    /// the resolver existed.
    @Test
    func theQueueResolvesTheWholeFailureOnEveryAnswer() async throws {
        let roomProxy = JoinedRoomProxyMock(.init())
        let devices = [alice: ["A1"], bob: ["B1"]]
        let viewModel = ResolveVerifiedUserSendFailureScreenViewModel(failure: .hasUnsignedDevice(devices: devices),
                                                                      resolver: .sendQueue(sendHandle: .mock, roomProxy: roomProxy),
                                                                      userIndicatorController: UserIndicatorControllerMock())

        try await answerEveryone(viewModel, count: 2)

        let calls = roomProxy.ignoreDeviceTrustAndResendDevicesSendHandleReceivedInvocations
        #expect(calls.count == 2)
        #expect(calls.allSatisfy { $0.devices == devices })
        #expect(!roomProxy.ignoreDeviceTrustDevicesCalled)
    }

    // MARK: - A raw send

    /// One user at a time, and ONE send after the last answer: a raw send has
    /// no queue item, and sending after each answer would repeat the event
    /// once it went through.
    @Test
    func aRawSendAsksEachUserAndSendsOnce() async throws {
        let roomProxy = JoinedRoomProxyMock(.init())
        var attempts = 0
        let resolution = RawSendResolution<String>(roomProxy: roomProxy) {
            attempts += 1
            return .success("$sent")
        }
        let viewModel = ResolveVerifiedUserSendFailureScreenViewModel(failure: .hasUnsignedDevice(devices: [alice: ["A1"], bob: ["B1"]]),
                                                                      resolver: resolution.resolver,
                                                                      userIndicatorController: UserIndicatorControllerMock())

        let deferredFailure = deferFailure(viewModel.actionsPublisher, timeout: .seconds(1)) { $0 == .dismiss }
        viewModel.context.send(viewAction: .resolveAndResend)
        try await deferredFailure.fulfill()
        #expect(roomProxy.ignoreDeviceTrustDevicesReceivedInvocations.count == 1)
        #expect(roomProxy.ignoreDeviceTrustDevicesReceivedInvocations.first?.count == 1, "only the user on screen")
        #expect(attempts == 0, "nobody sends before everyone is answered")

        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .dismiss }
        viewModel.context.send(viewAction: .resolveAndResend)
        try await deferred.fulfill()
        let answered = roomProxy.ignoreDeviceTrustDevicesReceivedInvocations.flatMap(\.keys)
        #expect(Set(answered) == [alice, bob])
        #expect(attempts == 1)
        #expect(!roomProxy.ignoreDeviceTrustAndResendDevicesSendHandleCalled)

        resolution.resolver.finished()
        #expect(await resolution.outcome() == "$sent")
    }

    @Test
    func aChangedIdentityIsWithdrawnThenSent() async throws {
        let roomProxy = JoinedRoomProxyMock(.init())
        var attempts = 0
        let resolution = RawSendResolution<String>(roomProxy: roomProxy) {
            attempts += 1
            return .success("$sent")
        }
        let viewModel = ResolveVerifiedUserSendFailureScreenViewModel(failure: .changedIdentity(users: [alice]),
                                                                      resolver: resolution.resolver,
                                                                      userIndicatorController: UserIndicatorControllerMock())

        try await answerEveryone(viewModel, count: 1)

        #expect(roomProxy.withdrawVerificationUserIDsReceivedInvocations == [[alice]])
        #expect(attempts == 1)
    }

    /// «Cancel for now», or the sheet swiped away: nothing is sent, and the
    /// caller learns it so it can stop waiting.
    @Test
    func aCancelledRawSendSendsNothing() async {
        let roomProxy = JoinedRoomProxyMock(.init())
        var attempts = 0
        let resolution = RawSendResolution<String>(roomProxy: roomProxy) {
            attempts += 1
            return .success("$sent")
        }

        resolution.resolver.finished()
        resolution.resolver.finished() // the sheet's two ways out, both taken

        #expect(await resolution.outcome() == nil)
        #expect(attempts == 0)
        #expect(!roomProxy.ignoreDeviceTrustDevicesCalled)
    }

    /// Only a refusal for a verified user asks; any other failure is returned
    /// as it was, and a send that works asks nothing.
    @Test
    func onlyAVerifiedUserRefusalAsks() async throws {
        let roomProxy = JoinedRoomProxyMock(.init())
        var asked = 0

        let sent = await RawSendResolution<String>.send(roomProxy: roomProxy,
                                                        present: { _, _ in asked += 1 },
                                                        attempt: { .success("$sent") })
        #expect(try sent.get() == "$sent")

        let failed = await RawSendResolution<String>.send(roomProxy: roomProxy,
                                                          present: { _, _ in asked += 1 },
                                                          attempt: { .failure(.eventNotFound) })
        guard case .failure(.eventNotFound) = failed else {
            Issue.record("expected the failure as it was, got \(failed)")
            return
        }
        #expect(asked == 0)
    }

    /// The whole road: refused, asked, the user agrees, sent — and the
    /// caller gets the event id the second attempt produced.
    @Test
    func aRefusedSendIsSentOnceTheUserAgrees() async throws {
        let roomProxy = JoinedRoomProxyMock(.init())
        var attempts = 0
        let result = await RawSendResolution<String>.send(roomProxy: roomProxy,
                                                          present: { failure, resolver in
                                                              Task {
                                                                  _ = await resolver.resolve(failure, failure, true)
                                                                  resolver.finished()
                                                              }
                                                          },
                                                          attempt: {
                                                              attempts += 1
                                                              return attempts == 1 ? .failure(.verifiedUser(.hasUnsignedDevice(devices: [alice: ["A1"]]))) : .success("$second")
                                                          })

        #expect(try result.get() == "$second")
        #expect(attempts == 2)
        #expect(roomProxy.ignoreDeviceTrustDevicesReceivedInvocations == [[alice: ["A1"]]])
    }

    // MARK: - A post's actions

    /// Two moves refused for the same reason ask ONE question, and both go
    /// out once the user agrees.
    @Test
    func refusedActionsAskOnceAndAllGoOutWhenAgreed() async {
        let roomProxy = JoinedRoomProxyMock(.init())
        var presented: [VerifiedUserSendFailureResolver] = []
        let refusals = SpiralAppSendRefusals(roomProxy: roomProxy) { _, resolver in presented.append(resolver) }
        var resolved = false
        let refusalUntilResolved: () async -> Result<Void, RoomProxyError> = {
            resolved ? .success(()) : .failure(.verifiedUser(.hasUnsignedDevice(devices: [alice: ["A1"]])))
        }

        let first = Task { await refusals.send(refusalUntilResolved) }
        let second = Task { await refusals.send(refusalUntilResolved) }
        while presented.isEmpty {
            await Task.yield()
        }
        // Give the second refusal its turn to wait on the first question.
        for _ in 0..<10 {
            await Task.yield()
        }
        resolved = true
        _ = await presented[0].resolve(.hasUnsignedDevice(devices: [alice: ["A1"]]), .hasUnsignedDevice(devices: [alice: ["A1"]]), true)
        presented[0].finished()

        let results = await [first.value, second.value]
        #expect(presented.count == 1, "one question for the room")
        #expect(results.allSatisfy { if case .success = $0 { true } else { false } })
    }

    @Test
    func refusedActionsAllFailWhenTheUserSaysNotNow() async {
        let roomProxy = JoinedRoomProxyMock(.init())
        var presented: [VerifiedUserSendFailureResolver] = []
        let refusals = SpiralAppSendRefusals(roomProxy: roomProxy) { _, resolver in presented.append(resolver) }

        let alice = alice
        let result = Task { await refusals.send { .failure(.verifiedUser(.hasUnsignedDevice(devices: [alice: ["A1"]]))) } }
        while presented.isEmpty {
            await Task.yield()
        }
        presented[0].finished()

        guard case .failure(.verifiedUser) = await result.value else {
            Issue.record("a move the user did not agree to must fail")
            return
        }
    }

    // MARK: - Helpers

    private func answerEveryone(_ viewModel: ResolveVerifiedUserSendFailureScreenViewModel, count: Int) async throws {
        for _ in 1..<count {
            let deferredFailure = deferFailure(viewModel.actionsPublisher, timeout: .seconds(1)) { $0 == .dismiss }
            viewModel.context.send(viewAction: .resolveAndResend)
            try await deferredFailure.fulfill()
        }
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .dismiss }
        viewModel.context.send(viewAction: .resolveAndResend)
        try await deferred.fulfill()
    }
}
