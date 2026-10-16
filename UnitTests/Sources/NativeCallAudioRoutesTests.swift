//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import AVFoundation
@testable import ElementX
import Testing

// AGENT-PLATFORM (Brief 0063, native call UI Phase 5 / G8): the audio
// route list as a pure function of the session's outputs and inputs.
// `AVAudioSession` itself cannot be exercised in a simulator test, so
// everything decidable is pinned here.

struct NativeCallAudioRoutesTests {
    private func port(_ type: AVAudioSession.Port, _ name: String, uid: String? = nil) -> NativeCallAudioPort {
        NativeCallAudioPort(type: type, name: name, uid: uid ?? name)
    }

    /// The phone alone offers its two built-in outputs and nothing else.
    @Test
    func aPhoneAloneOffersReceiverAndSpeaker() {
        let routes = NativeCallAudioRoutes.build(activeOutputs: [port(.builtInReceiver, "Receiver")],
                                                 availableInputs: [port(.builtInMic, "iPhone Microphone")])

        #expect(routes.map(\.kind) == [.receiver, .speaker])
        #expect(routes.first { $0.kind == .receiver }?.isActive == true)
        #expect(routes.first { $0.kind == .speaker }?.isActive == false)
    }

    @Test
    func theSpeakerRouteIsActiveWhileTheSpeakerPlays() {
        let routes = NativeCallAudioRoutes.build(activeOutputs: [port(.builtInSpeaker, "Speaker")],
                                                 availableInputs: [port(.builtInMic, "iPhone Microphone")])

        #expect(routes.first { $0.kind == .speaker }?.isActive == true)
        #expect(routes.first { $0.kind == .receiver }?.isActive == false)
    }

    /// AirPods list as a selectable external route, active while the
    /// output actually plays through them.
    @Test
    func bluetoothInputsBecomeSelectableExternalRoutes() {
        let routes = NativeCallAudioRoutes.build(activeOutputs: [port(.bluetoothA2DP, "AirPods Pro", uid: "airpods-out")],
                                                 availableInputs: [port(.builtInMic, "iPhone Microphone"),
                                                                   port(.bluetoothHFP, "AirPods Pro", uid: "airpods-in")])

        let airpods = routes.first { $0.kind == .external }
        #expect(airpods?.name == "AirPods Pro")
        // Bluetooth in/out UIDs differ; the name is what matches.
        #expect(airpods?.isActive == true)
        #expect(routes.first { $0.kind == .receiver }?.isActive == false)
    }

    /// A paired-but-idle car stays selectable and inactive while the
    /// receiver plays.
    @Test
    func anIdleExternalRouteIsListedInactive() {
        let routes = NativeCallAudioRoutes.build(activeOutputs: [port(.builtInReceiver, "Receiver")],
                                                 availableInputs: [port(.builtInMic, "iPhone Microphone"),
                                                                   port(.carAudio, "Yurii's car", uid: "car")])

        let car = routes.first { $0.kind == .external }
        #expect(car?.name == "Yurii's car")
        #expect(car?.isActive == false)
        #expect(routes.first { $0.kind == .receiver }?.isActive == true)
    }

    /// The built-in microphone is not a route — it must never render as a
    /// selectable row.
    @Test
    func theBuiltInMicrophoneIsNotARoute() {
        let routes = NativeCallAudioRoutes.build(activeOutputs: [port(.builtInReceiver, "Receiver")],
                                                 availableInputs: [port(.builtInMic, "iPhone Microphone")])

        #expect(!routes.contains { $0.kind == .external })
    }
}

// The audio state `NativeCallAudio` guards is process-wide, and its holders
// overlap in BOTH directions: a call's teardown is slow enough — up to 1.8 s of
// busy cadence plus the Matrix leave and the transport disconnect — for the
// next call to have started inside it, and a call claims before it joins, so a
// start that fails releases while the previous call is still connected. Who is
// allowed to run the teardown is therefore a decision, and it is pinned here
// for the same reason the route list is: the `AVAudioSession` and
// `AudioManager` halves cannot be exercised in a test, but this can.

struct NativeCallAudioOwnershipTests {
    @Test
    func theOnlyHolderTearsTheAudioDownWhenItLetsGo() {
        var ownership = NativeCallAudioOwnership()

        let call = ownership.claim()
        #expect(ownership.isHeld)

        // `release` is mutating, so it cannot be called inside `#expect` —
        // the macro captures its operand immutably.
        let outcome = ownership.release(call)
        #expect(outcome == .teardown)
        #expect(!ownership.isHeld)
    }

    /// One defect: an old session's `releaseAfterCallKit` landing after a new
    /// session's `prepareForCallKit` used to park the NEW call's engine, hand
    /// the session back to the SDK and drop its speaker route.
    @Test
    func aReleaseThatLandsAfterTheNextCallStartedKeepsTheAudio() {
        var ownership = NativeCallAudioOwnership()

        let first = ownership.claim() // the call the user hung up
        let second = ownership.claim() // the call they started while it tore down

        let staleRelease = ownership.release(first)
        #expect(staleRelease == .stillHeld(owners: 1), "the live call keeps the audio")

        let liveRelease = ownership.release(second)
        #expect(liveRelease == .teardown, "and can still release it normally when it ends")
        #expect(!ownership.isHeld)
    }

    /// The MIRROR defect, which superseding the owner opened: a call claims
    /// BEFORE it joins, so a second call whose join, credentials or connect
    /// fails releases while the first call is still connected. Under a
    /// generation counter that release succeeded — parking the live call's
    /// engine, dropping its speaker route and handing its session back to the
    /// SDK, with the live call's own release then refused so nothing repaired
    /// it.
    @Test
    func aSecondCallThatDiesDoesNotTearDownTheFirstCallsAudio() {
        var ownership = NativeCallAudioOwnership()

        let live = ownership.claim() // connected, talking
        let stillborn = ownership.claim() // start() claimed, then the join failed

        let failedStart = ownership.release(stillborn)
        #expect(failedStart == .stillHeld(owners: 1), "a dead call must not tear down a live one")
        #expect(ownership.isHeld)

        let hangUp = ownership.release(live)
        #expect(hangUp == .teardown, "the live call's own release is what ends the audio")
    }

    /// `stop` and `failStart` both end in a release and a call can be torn down
    /// from either, so the same token arrives twice — the teardown runs once.
    @Test
    func releasingTwiceTearsTheAudioDownOnce() {
        var ownership = NativeCallAudioOwnership()

        let call = ownership.claim()

        let first = ownership.release(call)
        let second = ownership.release(call)
        #expect(first == .teardown)
        #expect(second == .alreadyReleased)
    }

    /// Two calls in a row are two holders: reusing a token would let the first
    /// call's teardown fire on the second.
    @Test
    func eachClaimIsADistinctHolder() {
        var ownership = NativeCallAudioOwnership()

        let first = ownership.claim()
        _ = ownership.release(first)
        let second = ownership.claim()
        let reusedToken = ownership.release(first)

        #expect(first != second)
        #expect(reusedToken == .alreadyReleased)
        #expect(ownership.isHeld, "the second call still holds the audio")
    }

    /// H3 — `CallKitService` holds the CallKit-activation window from the
    /// moment an action fulfils, which is before any session exists. The
    /// session's own release must not end the audio while that window is open,
    /// and the window's release is what finally does.
    @Test
    func theCallKitActivationWindowOutlivesTheSessionItCovers() {
        var ownership = NativeCallAudioOwnership()

        let activationWindow = ownership.claim() // CXAnswerCallAction fulfilled
        let session = ownership.claim() // the screen's NativeCallSession started

        let sessionEnded = ownership.release(session)
        #expect(sessionEnded == .stillHeld(owners: 1))

        let callTornDown = ownership.release(activationWindow)
        #expect(callTornDown == .teardown, "the service's release is what gives the SDK its audio back")
    }

    /// The abandonment H3 is about: the answered call never reaches a session
    /// at all, so the window's own release is the only one there is.
    @Test
    func anActivationWindowWithoutASessionStillTearsTheAudioDown() {
        var ownership = NativeCallAudioOwnership()

        let activationWindow = ownership.claim()

        let callAbandoned = ownership.release(activationWindow)
        #expect(callAbandoned == .teardown)
        #expect(!ownership.isHeld, "automatic configuration goes back to the SDK")
    }
}
