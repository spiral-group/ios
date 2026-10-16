//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import ElementX
import Foundation
import Testing

// AGENT-PLATFORM (Brief 0066 rev. 2): the plan says WHO is ducked; the
// order turns that into a gain per microphone; the controller applies it
// to whatever is subscribed, statically — no meter, no speech gate.

struct NativeCallOriginalDuckingTests {
    private let bob = "@bob:h"
    private let bobPhone = "@bob:h:PHONE"
    private let bobPad = "@bob:h:PAD"
    private let carol = "@carol:h"
    private let carolPhone = "@carol:h:PHONE"

    private func plan(channel: NativeCallListeningChannel = .everything,
                      ducked: Set<String> = []) -> NativeCallSubscriptionPlan {
        NativeCallSubscriptionPlan(authorizedIdentities: [bobPhone, bobPad, carolPhone],
                                   publications: [],
                                   channel: channel,
                                   staleTranslationTracks: [],
                                   duckedSpeakers: ducked,
                                   visibleVideoIdentities: [],
                                   userIDByIdentity: [bobPhone: bob, bobPad: bob, carolPhone: carol],
                                   ownUserID: "@me:h")
    }

    // MARK: - The order (plan → transport)

    @Test
    func theOrderNamesEveryDeviceOfEachDuckedSpeakerAtTheOneGain() {
        let order = plan(ducked: [bob]).originalDucking

        #expect(order.floor == NativeCallListening.originalGain)
        #expect(order.identitiesBySpeaker == [bob: [bobPhone, bobPad]])
        #expect(order.gains == [bobPhone: 0.15, bobPad: 0.15])
    }

    @Test
    func theOrderIsEmptyInTheOriginalChannelAndWithNobodyDucked() {
        #expect(plan(channel: .original, ducked: [bob]).originalDucking.identitiesBySpeaker.isEmpty)
        #expect(plan(ducked: []).originalDucking.identitiesBySpeaker.isEmpty)
        #expect(NativeCallOriginalDucking.none.gains.isEmpty)
    }

    // MARK: - The controller (order + media → volumes)

    @MainActor
    private final class FakeMedia: NativeCallDuckableMedia {
        var audio: [NativeCallRemoteAudio] = []
        var volumes: [String: Float] = [:]
        var writes = 0

        func microphone(_ identity: String, sid: String, hasTrack: Bool = true, source: NativeCallTransportTrack.Source = .microphone) {
            audio.append(.init(identity: identity,
                               sid: sid,
                               name: "microphone",
                               setVolume: hasTrack ? { [weak self] in
                                   self?.volumes[sid] = $0
                                   self?.writes += 1
                               } : nil,
                               source: source))
        }

        func lane(_ name: String, sid: String, identity: String = "@agent:h:AGENT") {
            audio.append(.init(identity: identity, sid: sid, name: name) { [weak self] in self?.volumes[sid] = $0 })
        }

        func remoteAudio() -> [NativeCallRemoteAudio] {
            audio
        }
    }

    /// The whole point of rev. 2: the order alone sets the gain — before
    /// any lane exists, and it stays there with nothing else happening.
    @Test
    @MainActor
    func theOrderDucksACoveredMicrophoneAtOnceAndKeepsItThere() {
        let media = FakeMedia()
        media.microphone(bobPhone, sid: "MIC_BOB")
        media.microphone(bobPad, sid: "MIC_BOB_PAD")
        media.microphone(carolPhone, sid: "MIC_CAROL")
        let controller = NativeCallOriginalDuckingController(media: media)

        controller.setOrder(plan(ducked: [bob]).originalDucking)
        #expect(media.volumes == ["MIC_BOB": 0.15, "MIC_BOB_PAD": 0.15, "MIC_CAROL": 1])

        // Time passes, callbacks fire, nobody speaks: nothing moves.
        let writes = media.writes
        controller.mediaDidChange()
        controller.mediaDidChange()
        #expect(media.volumes["MIC_BOB"] == 0.15)
        #expect(media.writes == writes, "an unchanged order must not rewrite a gain")
    }

    /// A lane's own playout is never touched: it is the translation.
    @Test
    @MainActor
    func aTranslationLaneIsNeverDucked() {
        let media = FakeMedia()
        media.microphone(bobPhone, sid: "MIC_BOB")
        media.lane("lt:en:\(bob)", sid: "LANE_BOB")
        let controller = NativeCallOriginalDuckingController(media: media)
        controller.setOrder(plan(ducked: [bob]).originalDucking)
        #expect(media.volumes["MIC_BOB"] == 0.15)
        #expect(media.volumes["LANE_BOB"] == nil)
    }

    /// A microphone that lands after the order (subscribed a beat later)
    /// gets its gain on the media change, and a re-subscribed one (new
    /// SID, reused receiver) is rewritten rather than assumed.
    @Test
    @MainActor
    func aLateOrResubscribedMicrophoneIsRewritten() {
        let media = FakeMedia()
        let controller = NativeCallOriginalDuckingController(media: media)
        controller.setOrder(plan(ducked: [bob]).originalDucking)

        media.microphone(bobPhone, sid: "MIC_BOB")
        controller.mediaDidChange()
        #expect(media.volumes["MIC_BOB"] == 0.15)

        media.audio = []
        controller.mediaDidChange(unsubscribedSID: "MIC_BOB")
        media.volumes = [:]
        media.microphone(bobPhone, sid: "MIC_BOB")
        controller.mediaDidChange()
        #expect(media.volumes["MIC_BOB"] == 0.15)
    }

    /// A microphone whose track object is not there yet is picked up once
    /// it is — the order stands, the gain is applied late, not lost.
    @Test
    @MainActor
    func aMicrophoneWithoutATrackIsDuckedOnceItHasOne() {
        let media = FakeMedia()
        media.microphone(bobPhone, sid: "MIC_BOB", hasTrack: false)
        let controller = NativeCallOriginalDuckingController(media: media)
        controller.setOrder(plan(ducked: [bob]).originalDucking)
        #expect(media.volumes.isEmpty)

        media.audio = []
        media.microphone(bobPhone, sid: "MIC_BOB")
        controller.mediaDidChange()
        #expect(media.volumes["MIC_BOB"] == 0.15)
    }

    /// The order going away resets a ducked microphone to unity at once.
    @Test
    @MainActor
    func liftingTheOrderRestoresUnity() {
        let media = FakeMedia()
        media.microphone(bobPhone, sid: "MIC_BOB")
        let controller = NativeCallOriginalDuckingController(media: media)
        controller.setOrder(plan(ducked: [bob]).originalDucking)
        #expect(media.volumes["MIC_BOB"] == 0.15)

        controller.setOrder(.none)
        #expect(media.volumes["MIC_BOB"] == 1)
    }

    @Test
    @MainActor
    func translatingASpeakerDoesNotDuckTheirScreenShareAudio() {
        let media = FakeMedia()
        media.microphone(bobPhone, sid: "MIC_BOB")
        media.microphone(bobPhone, sid: "SHARE_BOB", source: .screenShareAudio)
        media.volumes["SHARE_BOB"] = 1
        let controller = NativeCallOriginalDuckingController(media: media)
        controller.setOrder(plan(ducked: [bob]).originalDucking)
        #expect(media.volumes["MIC_BOB"] == 0.15)
        #expect(media.volumes["SHARE_BOB"] == 1)
    }
}
