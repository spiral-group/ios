//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import AVFoundation
@testable import Spiral
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

/// Question 407: each call's own speaker. A held call keeps its route; the call that resumes gets its own back, never
/// what the last call left; a default (not the person's pick) gives way to a car or headphones.
@MainActor
struct NativeCallSpeakerRegisterTests {
    @Test
    func aResumedCallGetsItsOwnRouteNotTheLastCallsOne() {
        var ownership = NativeCallAudioOwnership()
        var speakers = NativeCallSpeakerRegister()
        let person = ownership.claim()
        let assistant = ownership.claim()

        speakers.start(person, onSpeaker: false)
        speakers.start(assistant, onSpeaker: true)
        speakers.release(assistant)
        speakers.resume(person)
        #expect(!speakers.isSpeakerEnabled, "a person's call doesn't come back on the loudspeaker")

        let second = ownership.claim()
        speakers.start(assistant, onSpeaker: true)
        speakers.start(second, onSpeaker: false)
        speakers.release(second)
        speakers.resume(assistant)
        #expect(speakers.isSpeakerEnabled, "the assistant's call comes back on the loudspeaker")
    }

    /// A call starting before CallKit's hold reaches the other one can't touch the other one's route.
    @Test
    func aCallStartingCantChangeTheRouteOfTheOneItReplaces() {
        var ownership = NativeCallAudioOwnership()
        var speakers = NativeCallSpeakerRegister()
        let first = ownership.claim()
        let second = ownership.claim()

        speakers.start(first, onSpeaker: true)
        speakers.choose(false)
        speakers.start(second, onSpeaker: true)
        speakers.choose(true)

        #expect(speakers.state(for: first) == .init(isEnabled: false, isDefaulted: false))
        #expect(speakers.state(for: second) == .init(isEnabled: true, isDefaulted: false))
    }

    /// A default speaker held, a car connected meanwhile: the resume gives it way, and the hold's restore doesn't
    /// take it back — the person's own pick stays.
    @Test
    func aDefaultSpeakerRestoredAfterAHoldGivesWayToACar() {
        var ownership = NativeCallAudioOwnership()
        var speakers = NativeCallSpeakerRegister()
        let assistant = ownership.claim()
        let other = ownership.claim()
        speakers.start(assistant, onSpeaker: true)
        let saved = speakers.state(for: assistant)
        speakers.start(other, onSpeaker: false)
        speakers.release(other)

        speakers.resume(assistant)
        let didGiveWay = speakers.settle(hasExternalRoute: true)
        let didRestore = speakers.restore(saved, for: assistant)

        #expect(didGiveWay)
        #expect(!didRestore)
        #expect(!speakers.isSpeakerEnabled)

        speakers.choose(true)
        let picked = speakers.state(for: assistant)
        let didPickGiveWay = speakers.settle(hasExternalRoute: true)
        let didRestorePick = speakers.restore(picked, for: assistant)
        #expect(!didPickGiveWay)
        #expect(!didRestorePick)
        #expect(speakers.isSpeakerEnabled, "the person's own speaker stays")
    }

    /// A camera turned back on after a hold sets the speaker as a default; the call's own route wins over it.
    @Test
    func theCallsOwnRouteWinsOverACameraDefaultAfterAHold() {
        var ownership = NativeCallAudioOwnership()
        var speakers = NativeCallSpeakerRegister()
        let call = ownership.claim()
        speakers.start(call, onSpeaker: false)
        let saved = speakers.state(for: call)

        speakers.applyVideoDefault()
        let didRestore = speakers.restore(saved, for: call)

        #expect(didRestore)
        #expect(!speakers.isSpeakerEnabled)
    }

    /// AirPods arriving take the call off the speaker; a lost device leaves it where the system put it.
    @Test
    func theSpeakerFollowsADeviceTheSystemRoutedTo() {
        let speaker = NativeCallAudioPort(type: .builtInSpeaker, name: "Speaker", uid: "Speaker")
        let receiver = NativeCallAudioPort(type: .builtInReceiver, name: "Receiver", uid: "Receiver")
        let airPods = NativeCallAudioPort(type: .bluetoothHFP, name: "AirPods", uid: "airpods")
        func change(_ reason: AVAudioSession.RouteChangeReason, _ outputs: [NativeCallAudioPort]) -> NativeCallSpeakerPolicy.DeviceChange? {
            NativeCallSpeakerPolicy.routeAfterDeviceChange(reason: reason, activeOutputs: outputs, returnsToSpeaker: false)
        }
        #expect(change(.newDeviceAvailable, [airPods]) == .follows(speaker: false))
        #expect(change(.oldDeviceUnavailable, [receiver]) == .follows(speaker: false))
        #expect(change(.oldDeviceUnavailable, [speaker]) == .follows(speaker: true))
        #expect(change(.override, [receiver]) == nil)
        #expect(change(.categoryChange, [receiver]) == nil)

        var ownership = NativeCallAudioOwnership()
        var speakers = NativeCallSpeakerRegister()
        speakers.start(ownership.claim(), onSpeaker: true)
        let didFollow = speakers.follow(.follows(speaker: false))
        let didFollowAgain = speakers.follow(.follows(speaker: false))

        #expect(didFollow)
        #expect(!didFollowAgain)
        #expect(!speakers.isSpeakerEnabled)
    }

    // MARK: Headphones removed (operator, 2026-11-12)

    private static let receiver = NativeCallAudioPort(type: .builtInReceiver, name: "Receiver", uid: "Receiver")
    private static let speakerPort = NativeCallAudioPort(type: .builtInSpeaker, name: "Speaker", uid: "Speaker")
    private static let airPods = NativeCallAudioPort(type: .bluetoothHFP, name: "AirPods", uid: "airpods")

    /// AirPods connected, then removed, with the system on the earpiece (`.voiceChat`'s choice) — or on the speaker
    /// in `.videoChat`, or on another device still connected.
    private func connectAndRemoveAirPods(_ speakers: inout NativeCallSpeakerRegister,
                                         isVideo: Bool = false,
                                         systemOutput: NativeCallAudioPort? = nil) -> NativeCallSpeakerPolicy.DeviceChange? {
        let arrived = NativeCallSpeakerPolicy.routeAfterDeviceChange(reason: .newDeviceAvailable,
                                                                     activeOutputs: [Self.airPods],
                                                                     returnsToSpeaker: speakers.returnsToSpeaker(isVideo: isVideo))
        if let arrived {
            _ = speakers.follow(arrived)
        }
        #expect(!speakers.isSpeakerEnabled, "AirPods take the sound")
        let removed = NativeCallSpeakerPolicy.routeAfterDeviceChange(reason: .oldDeviceUnavailable,
                                                                     activeOutputs: [systemOutput ?? Self.receiver],
                                                                     returnsToSpeaker: speakers.returnsToSpeaker(isVideo: isVideo))
        if let removed {
            _ = speakers.follow(removed)
        }
        return removed
    }

    @Test(arguments: [true, false])
    func aCallWithOnesOwnAssistantGoesBackToTheSpeakerWhenTheAirPodsGo(startedOnSpeaker: Bool) {
        var ownership = NativeCallAudioOwnership()
        var speakers = NativeCallSpeakerRegister()
        // Started on the speaker, or with the AirPods already in.
        speakers.start(ownership.claim(), onSpeaker: startedOnSpeaker, isAssistantCall: true)

        let removed = connectAndRemoveAirPods(&speakers)

        #expect(removed == .returnsToSpeaker)
        #expect(speakers.isSpeakerEnabled)
        #expect(speakers.state(for: speakers.current) == .init(isEnabled: true, isDefaulted: true),
                "a default: a car or headphones at the next activation still take it")
    }

    /// A direct or a group audio call: not a call with one's own assistant.
    @Test
    func aCallWithPeopleStaysOnTheEarpieceWhenTheAirPodsGo() {
        var ownership = NativeCallAudioOwnership()
        var speakers = NativeCallSpeakerRegister()
        speakers.start(ownership.claim(), onSpeaker: false, isAssistantCall: false)

        let removed = connectAndRemoveAirPods(&speakers)

        #expect(removed == .follows(speaker: false))
        #expect(!speakers.isSpeakerEnabled)
    }

    /// The person took the call to the earpiece: it stays there, even after they picked the AirPods in between.
    @Test(arguments: [true, false])
    func thePersonsEarpieceStaysWhenTheAirPodsGo(pickedAirPods: Bool) {
        var ownership = NativeCallAudioOwnership()
        var speakers = NativeCallSpeakerRegister()
        speakers.start(ownership.claim(), onSpeaker: true, isAssistantCall: true)
        speakers.choose(false)
        if pickedAirPods {
            speakers.chooseExternal()
        }

        let removed = connectAndRemoveAirPods(&speakers)

        #expect(removed == .follows(speaker: false))
        #expect(!speakers.isSpeakerEnabled)
    }

    /// The pocket interpreter moves the call off the earpiece; from then on the same rule brings it back after AirPods.
    /// A pick of the AirPods alone isn't an earpiece pick.
    @Test
    func theInterpretersSpeakerComesBackAfterTheAirPods() {
        var ownership = NativeCallAudioOwnership()
        var speakers = NativeCallSpeakerRegister()
        speakers.start(ownership.claim(), onSpeaker: true, isAssistantCall: true)
        speakers.choose(false) // the person's earpiece
        speakers.choose(true) // the interpreter's start
        speakers.chooseExternal() // then the AirPods, picked

        let removed = connectAndRemoveAirPods(&speakers)

        #expect(removed == .returnsToSpeaker)
        #expect(speakers.isSpeakerEnabled)
    }

    /// Video keeps today's behaviour: it follows the system's output either way.
    @Test(arguments: [true, false])
    func aVideoCallKeepsFollowingTheSystem(systemOnSpeaker: Bool) {
        var ownership = NativeCallAudioOwnership()
        var speakers = NativeCallSpeakerRegister()
        speakers.start(ownership.claim(), onSpeaker: true, isAssistantCall: true)

        let removed = connectAndRemoveAirPods(&speakers, isVideo: true, systemOutput: systemOnSpeaker ? Self.speakerPort : Self.receiver)

        #expect(removed == .follows(speaker: systemOnSpeaker))
        #expect(speakers.isSpeakerEnabled == systemOnSpeaker)
    }

    /// Another device the system moved the call to (a car, a wired headset) keeps the sound: nothing overrides it.
    @Test(arguments: [AVAudioSession.Port.carAudio, .headphones, .bluetoothHFP])
    func anotherExternalOutputKeepsTheSoundWhenTheAirPodsGo(other: AVAudioSession.Port) {
        var ownership = NativeCallAudioOwnership()
        var speakers = NativeCallSpeakerRegister()
        speakers.start(ownership.claim(), onSpeaker: true, isAssistantCall: true)

        let removed = connectAndRemoveAirPods(&speakers, systemOutput: .init(type: other, name: "Other", uid: "other"))

        #expect(removed == .follows(speaker: false))
        #expect(!speakers.isSpeakerEnabled)
    }

    /// Each call keeps its own: the assistant call's rule doesn't reach the person's call that resumes after it, and a
    /// released call takes its earpiece pick with it.
    @Test
    func theRuleBelongsToTheCallInUse() {
        var ownership = NativeCallAudioOwnership()
        var speakers = NativeCallSpeakerRegister()
        let assistant = ownership.claim()
        let person = ownership.claim()
        speakers.start(person, onSpeaker: false)
        speakers.start(assistant, onSpeaker: true, isAssistantCall: true)
        #expect(speakers.returnsToSpeaker(isVideo: false))

        speakers.release(assistant)
        speakers.resume(person)
        #expect(!speakers.returnsToSpeaker(isVideo: false))
    }
}
