//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Foundation
@testable import Spiral
import Testing

/// Pins for the pure function the whole call screen is derived from.
/// It takes `Equatable` inputs and returns `Equatable` outputs, so it is
/// the cheapest place in the feature to encode a rule — every defect the
/// pre-merge audit found in the roster, the listening channel or the
/// subscription plan is reproducible here in a few lines.
struct NativeCallStateDerivationTests {
    private let agentIdentity = "@agent:matrix.org:AGENT"
    private let bobIdentity = "@bob:matrix.org:BOB"

    /// A v6 document as the runtime publishes it (ADR-0094 A.6): one translation function with its style and its
    /// lanes — every human of these tests into each language, unless `speakers` names them. Inactive, it stands by.
    private func agentDocument(languages: [String],
                               active: Bool = true,
                               style: String = "simultaneous",
                               speakers: [String] = ["@alice:matrix.org", "@bob:matrix.org", "@carol:matrix.org"],
                               lifecycle: String = "live") -> [String: String] {
        let lanes = active
            ? speakers.flatMap { speaker in languages.map { #"{"speaker":"\#(speaker)","input":"voice","language":"\#($0)"}"# } }.joined(separator: ",")
            : ""
        let intent = languages.count == 2
            ? #""pocket":["\#(languages[0])","\#(languages[1])"]"#
            : #""for_language":"\#(languages.first ?? "")""#
        let functions = languages.isEmpty
            ? "[]"
            : #"[{"kind":"translation","active":\#(active),\#(intent),"style":"\#(style)","lanes":[\#(lanes)]}]"#
        return [SpiralAgentStateReader.attributeKey: #"{"v":6,"agent":true,"lifecycle":"\#(lifecycle)","functions":\#(functions)}"#]
    }

    private func inputs(agentAttributes: [String: String] = [:],
                        tracks: [NativeCallTransportTrack] = [],
                        choice: NativeCallListeningChoice = .language("uk")) -> NativeCallDerivationInputs {
        var inputs = NativeCallDerivationInputs()
        inputs.ownIdentity = "@alice:matrix.org:DEVICE"
        inputs.transportLocalIdentity = "@alice:matrix.org:DEVICE"
        inputs.memberships = [.init(userID: "@bob:matrix.org", deviceID: "BOB", identity: bobIdentity),
                              .init(userID: "@agent:matrix.org", deviceID: "AGENT", identity: agentIdentity)]
        inputs.transportParticipants = [.init(identity: bobIdentity, isSpeaking: false, isAudioEnabled: true),
                                        .init(identity: agentIdentity, isSpeaking: false, isAudioEnabled: true,
                                              attributes: agentAttributes)]
        inputs.transportTracks = tracks
        inputs.listeningChoice = choice
        return inputs
    }

    /// Audit B4: the state document was applied to the picker only, so a
    /// disabled translation stopped being offered while its stale lane
    /// stayed subscribed — audible over the raw microphone, because an
    /// empty picker resolves the channel to `.everything`, which excludes
    /// nothing.
    @Test
    func aStaleTranslationLaneIsExcludedFromSubscriptions() {
        let stale = NativeCallTransportTrack(identity: agentIdentity, name: "lt:uk:@bob:matrix.org", isSubscribed: true)
        let microphone = NativeCallTransportTrack(identity: bobIdentity, name: "microphone", isSubscribed: true)
        let state = NativeCallStateDerivation.derive(inputs(agentAttributes: agentDocument(languages: []),
                                                            tracks: [stale, microphone]))

        #expect(state.listening.producedLanguages.isEmpty)
        // A language nobody produces is heard as the original (Brief 0085).
        #expect(state.listening.channel == .original)
        #expect(state.subscriptionPlan.isTrackExcluded(identity: agentIdentity, name: "lt:uk:@bob:matrix.org", kind: .audio))
        #expect(!state.subscriptionPlan.isTrackExcluded(identity: bobIdentity, name: "microphone", kind: .audio))
        // A stale lane must not mark its speaker as translated either —
        // that would hide the raw voice (fail silent).
        #expect(state.listening.translatedSpeakers.isEmpty)
        #expect(state.participants.first { $0.userID == "@bob:matrix.org" }?.isTranslated == false)
    }

    /// Bug S2: an assistant kicked from the room leaves the call at once — the SDK takes its membership out, and
    /// its media, still on the SFU until its runtime hangs up, must not bring it back as a participant.
    @Test
    func anAgentWhoseMembershipEndedIsGoneThoughItsMediaLingers() {
        var inCall = inputs(agentAttributes: agentDocument(languages: ["uk"]))
        inCall.transportParticipants = [.init(identity: bobIdentity, isSpeaking: false, isAudioEnabled: true),
                                        .init(identity: agentIdentity, isSpeaking: true, isAudioEnabled: true,
                                              isAgent: true, attributes: agentDocument(languages: ["uk"]))]
        var kicked = inCall
        kicked.memberships.removeAll { $0.userID == "@agent:matrix.org" }
        kicked.departedIdentities = NativeCallStateDerivation.departedIdentities(previous: inCall, inputs: kicked)

        let state = NativeCallStateDerivation.derive(kicked)

        #expect(kicked.departedIdentities == [agentIdentity])
        #expect(state.participants.map(\.userID) == ["@alice:matrix.org", "@bob:matrix.org"])
        #expect(state.agentClaims.documents.isEmpty)
        #expect(state.agentStateDocuments.isEmpty)
        #expect(state.listening.translatedSpeakers.isEmpty, "its claim no longer quiets anyone's voice")
        #expect(!state.subscriptionPlan.authorizedIdentities.contains(agentIdentity))
    }

    /// A membership can blip — a spuriously fired delayed leave, re-published a moment later. Presence still reads
    /// the media on the SFU, so neither a talking peer nor an agent ends the call in between.
    @Test
    func aMembershipBlipDoesNotEndTheCall() {
        var inCall = inputs()
        inCall.transportParticipants = [.init(identity: bobIdentity, isSpeaking: true, isAudioEnabled: true),
                                        .init(identity: agentIdentity, isSpeaking: false, isAudioEnabled: true, isAgent: true)]
        var blip = inCall
        blip.memberships = []
        blip.departedIdentities = NativeCallStateDerivation.departedIdentities(previous: inCall, inputs: blip)
        #expect(blip.departedIdentities == [bobIdentity, agentIdentity])

        let state = NativeCallStateDerivation.derive(blip)

        #expect(state.hasHumanRemote)
        #expect(state.hasHumanOnTransport)
        #expect(state.hasAgentRemote)
        #expect(state.participants.map(\.userID) == ["@alice:matrix.org"], "the roster still drops them")
    }

    /// LiveKit can beat MatrixRTC to the client: an agent on the SFU that never had a membership has not departed.
    @Test
    func anAgentAheadOfItsMembershipIsNotDeparted() {
        var arriving = inputs(agentAttributes: agentDocument(languages: ["uk"]))
        arriving.memberships.removeAll { $0.userID == "@agent:matrix.org" }
        arriving.transportParticipants = [.init(identity: agentIdentity, isSpeaking: false, isAudioEnabled: true, isAgent: true)]

        #expect(NativeCallStateDerivation.departedIdentities(previous: arriving, inputs: arriving).isEmpty)
        #expect(NativeCallStateDerivation.derive(arriving).participants.contains { $0.userID == "@agent:matrix.org" })
    }

    /// A departure ends when the membership comes back (re-added) or the media leaves the SFU.
    @Test
    func aDepartureEndsWithAReturnOrTheHangUp() {
        let inCall = inputs()
        var kicked = inCall
        kicked.memberships.removeAll { $0.userID == "@agent:matrix.org" }
        kicked.departedIdentities = NativeCallStateDerivation.departedIdentities(previous: inCall, inputs: kicked)
        #expect(kicked.departedIdentities == [agentIdentity])

        var stillLingering = kicked
        stillLingering.isLocalSpeaking = true
        #expect(NativeCallStateDerivation.departedIdentities(previous: kicked, inputs: stillLingering) == [agentIdentity],
                "an unrelated input change keeps it")

        var back = kicked
        back.memberships = inCall.memberships
        #expect(NativeCallStateDerivation.departedIdentities(previous: kicked, inputs: back).isEmpty)

        var hungUp = kicked
        hungUp.transportParticipants.removeAll { $0.identity == agentIdentity }
        #expect(NativeCallStateDerivation.departedIdentities(previous: kicked, inputs: hungUp).isEmpty)
    }

    /// Question 383: the plan names the staged person's video devices, and no one's without a stage.
    @Test
    func thePlanNamesTheStagedPersonsVideo() {
        var camera = NativeCallTransportTrack(identity: bobIdentity, name: "camera", isSubscribed: true)
        camera.kind = .video
        var staged = inputs(tracks: [camera])
        #expect(NativeCallStateDerivation.derive(staged).subscriptionPlan.stagedVideoIdentities.isEmpty)

        staged.stagedUserID = "@bob:matrix.org"
        #expect(NativeCallStateDerivation.derive(staged).subscriptionPlan.stagedVideoIdentities == [bobIdentity])

        staged.stagedUserID = "@carol:matrix.org"
        #expect(NativeCallStateDerivation.derive(staged).subscriptionPlan.stagedVideoIdentities.isEmpty)
    }

    @Test
    func aClaimedTranslationLaneStaysSubscribedAndMarksItsSpeaker() {
        let live = NativeCallTransportTrack(identity: agentIdentity, name: "lt:uk:@bob:matrix.org", isSubscribed: true)
        let microphone = NativeCallTransportTrack(identity: bobIdentity, name: "microphone", isSubscribed: true)
        let state = NativeCallStateDerivation.derive(inputs(agentAttributes: agentDocument(languages: ["uk"]),
                                                            tracks: [live, microphone]))

        #expect(state.listening.producedLanguages == ["uk"])
        #expect(state.listening.channel == .translation(language: "uk"))
        #expect(state.listening.translatedSpeakers == ["@bob:matrix.org": "uk"])
        #expect(!state.subscriptionPlan.isTrackExcluded(identity: agentIdentity, name: "lt:uk:@bob:matrix.org", kind: .audio))
        // Brief 0066: Bob's raw microphone STAYS subscribed and is ducked
        // on the device — the plan names his devices.
        #expect(!state.subscriptionPlan.isTrackExcluded(identity: bobIdentity, name: "microphone", kind: .audio))
        #expect(state.subscriptionPlan.originalDucking.identitiesBySpeaker == ["@bob:matrix.org": [bobIdentity]])
        #expect(state.participants.first { $0.userID == "@bob:matrix.org" }?.isTranslated == true)
    }

    // MARK: - Consecutive airing (`agent-<lang>`) — found by ear, 0063 device day

    /// The picker was dead UI in the style production actually runs.
    ///
    /// Its OPTIONS come from the agent's document claim, so they rendered
    /// correctly; its ENFORCEMENT keyed off track names and knew only the
    /// simultaneous `lt:` shape. A consecutive `agent-ru` track was
    /// therefore read as a raw microphone: never excluded, in any channel.
    /// Choosing "original voices" changed nothing, and the operator heard
    /// the translation anyway.
    @Test
    func aConsecutiveTrackIsSubscribedForItsOwnLanguage() {
        let aired = NativeCallTransportTrack(identity: agentIdentity, name: "lt:uk", isSubscribed: true)
        let microphone = NativeCallTransportTrack(identity: bobIdentity, name: "microphone", isSubscribed: true)
        let state = NativeCallStateDerivation.derive(inputs(agentAttributes: agentDocument(languages: ["uk"], style: "consecutive"),
                                                            tracks: [aired, microphone]))

        #expect(state.listening.channel == .translation(language: "uk"))
        #expect(!state.subscriptionPlan.isTrackExcluded(identity: agentIdentity, name: "lt:uk", kind: .audio))
    }

    /// Brief 0085: consecutive is only the pocket interpreter the owner set up for themself, so the original still
    /// plays it.
    @Test
    func aConsecutiveTrackIsHeardInTheOriginalToo() {
        let aired = NativeCallTransportTrack(identity: agentIdentity, name: "lt:uk", isSubscribed: true)
        let state = NativeCallStateDerivation.derive(inputs(agentAttributes: agentDocument(languages: ["uk"], style: "consecutive"),
                                                            tracks: [aired],
                                                            choice: .original))

        #expect(state.listening.channel == .original)
        #expect(!state.subscriptionPlan.isTrackExcluded(identity: agentIdentity, name: "lt:uk", kind: .audio))
    }

    /// ADR-0075 D8 — consecutive stays communal: EVERY configured language
    /// is heard, in turn, by everyone. The test this replaces pinned the
    /// opposite (a picked language silencing the others) and was the
    /// reason a ru+en call played only one of them.
    @Test
    func everyConsecutiveLanguageIsSubscribed() {
        let uk = NativeCallTransportTrack(identity: agentIdentity, name: "lt:uk", isSubscribed: true)
        let en = NativeCallTransportTrack(identity: agentIdentity, name: "lt:en", isSubscribed: true)
        let state = NativeCallStateDerivation.derive(inputs(agentAttributes: agentDocument(languages: ["uk", "en"], style: "consecutive"),
                                                            tracks: [uk, en]))

        #expect(state.listening.producedLanguages == ["en", "uk"])
        #expect(!state.subscriptionPlan.isTrackExcluded(identity: agentIdentity, name: "lt:uk", kind: .audio))
        #expect(!state.subscriptionPlan.isTrackExcluded(identity: agentIdentity, name: "lt:en", kind: .audio))
    }

    /// The half that must NOT be shared with the simultaneous style: a
    /// consecutive rendering airs AFTER the speaker stops, so ducking their
    /// live microphone would blank the voice and then play the rendering
    /// into a silence nobody asked for. Only `lt:` lanes may duck.
    @Test
    func aConsecutiveTrackNeverDucksTheLiveMicrophone() {
        let aired = NativeCallTransportTrack(identity: agentIdentity, name: "lt:uk", isSubscribed: true)
        let microphone = NativeCallTransportTrack(identity: bobIdentity, name: "microphone", isSubscribed: true)
        let state = NativeCallStateDerivation.derive(inputs(agentAttributes: agentDocument(languages: ["uk"], style: "consecutive"),
                                                            tracks: [aired, microphone]))

        #expect(state.listening.translatedSpeakers.isEmpty,
                "an Interpreter claim covers nobody for ducking, whatever its booths say")
        #expect(state.subscriptionPlan.originalDucking.identitiesBySpeaker.isEmpty)
        #expect(!state.subscriptionPlan.isTrackExcluded(identity: bobIdentity, name: "microphone", kind: .audio),
                "the live voice must stay audible while the interpreter waits for a pause")
    }

    /// A consecutive track whose language the agent has stopped claiming is
    /// stale in exactly the way an `lt:` lane is, and must go silent.
    @Test
    func aStaleConsecutiveTrackIsExcluded() {
        let stale = NativeCallTransportTrack(identity: agentIdentity, name: "lt:uk", isSubscribed: true)
        let state = NativeCallStateDerivation.derive(inputs(agentAttributes: agentDocument(languages: []),
                                                            tracks: [stale]))

        #expect(state.subscriptionPlan.isTrackExcluded(identity: agentIdentity, name: "lt:uk", kind: .audio))
    }

    /// Two simultaneous lanes in different languages for the same speaker
    /// (Brief 0085: two listeners' choices): only the chosen one is heard.
    @Test
    func onlyTheChosenLanguagesLaneIsSubscribed() {
        let uk = NativeCallTransportTrack(identity: agentIdentity, name: "lt:uk:@bob:matrix.org", isSubscribed: true)
        let de = NativeCallTransportTrack(identity: agentIdentity, name: "lt:de:@bob:matrix.org", isSubscribed: true)
        let state = NativeCallStateDerivation.derive(inputs(agentAttributes: agentDocument(languages: ["uk", "de"]),
                                                            tracks: [uk, de]))
        #expect(state.listening.channel == .translation(language: "uk"))
        #expect(!state.subscriptionPlan.isTrackExcluded(identity: agentIdentity, name: "lt:uk:@bob:matrix.org", kind: .audio))
        #expect(state.subscriptionPlan.isTrackExcluded(identity: agentIdentity, name: "lt:de:@bob:matrix.org", kind: .audio))
        #expect(state.listening.translatedSpeakers["@bob:matrix.org"] == "uk")
    }

    /// Audit B11: before the own membership syncs the local row rendered
    /// `<mxid>:<device>` as the user ID — i.e. for the whole connecting
    /// and ringing window, which is exactly when it is looked at.
    @Test
    func theLocalRowNeverRendersADeviceSuffixedIdentity() {
        var withoutOwnMembership = inputs()
        withoutOwnMembership.transportLocalIdentity = "@alice:matrix.org:DEVICE"
        let state = NativeCallStateDerivation.derive(withoutOwnMembership)
        #expect(state.participants.first(where: \.isLocal)?.userID == "@alice:matrix.org")
    }

    /// Audit B10: a pure derivation must degrade, never trap, on
    /// externally supplied arrays.
    @Test
    func duplicateTransportIdentitiesDoNotTrap() {
        var duplicated = inputs()
        duplicated.transportParticipants.append(.init(identity: bobIdentity, isSpeaking: true, isAudioEnabled: false))
        let state = NativeCallStateDerivation.derive(duplicated)
        #expect(state.participants.contains { $0.userID == "@bob:matrix.org" })
    }

    /// Security (pre-merge review): a track name proves nothing. A person
    /// publishing `lt:uk:@bob` would be heard as Bob's translation — over
    /// Bob's real voice, ducked by an agent that does cover him. A
    /// publisher with no document is never subscribed for it.
    @Test
    func aTranslationTrackFromAPublisherWithoutADocumentIsNeverSubscribed() {
        let forged = NativeCallTransportTrack(identity: bobIdentity, name: "lt:uk:@carol:matrix.org", isSubscribed: true)
        let agentLane = NativeCallTransportTrack(identity: agentIdentity, name: "lt:uk:@bob:matrix.org", isSubscribed: true)
        let state = NativeCallStateDerivation.derive(inputs(tracks: [forged, agentLane]))

        #expect(state.listening.producedLanguages.isEmpty)
        #expect(state.subscriptionPlan.isTrackExcluded(identity: bobIdentity, name: "lt:uk:@carol:matrix.org", kind: .audio))
        #expect(state.subscriptionPlan.isTrackExcluded(identity: agentIdentity, name: "lt:uk:@bob:matrix.org", kind: .audio))
    }

    /// D12: an `ltd:` track is reserved — never subscribed, even from an
    /// agent whose document covers that speaker in that language, and even
    /// published as screen-share audio, which is otherwise always heard.
    @Test
    func aReservedDeviceTrackIsNeverSubscribed() {
        let state = NativeCallStateDerivation.derive(inputs(agentAttributes: agentDocument(languages: ["uk"]),
                                                            tracks: [.init(identity: agentIdentity, name: "ltd:uk:@bob:matrix.org", isSubscribed: false)]))

        #expect(state.subscriptionPlan.isTrackExcluded(identity: agentIdentity, name: "ltd:uk:@bob:matrix.org", kind: .audio))
        #expect(state.subscriptionPlan.isTrackExcluded(identity: agentIdentity, name: "ltd:uk:@bob:matrix.org", kind: .audio,
                                                       source: .screenShareAudio))
    }

    /// A.6: an agent's track is heard only for a lane its own document
    /// lists — Bob's, in this language. Its document airing Ukrainian for
    /// others is no licence for a lane it doesn't list.
    @Test
    func anAgentsTrackItsDocumentDoesNotListIsNeverSubscribed() {
        let listed = NativeCallTransportTrack(identity: agentIdentity, name: "lt:uk:@carol:matrix.org", isSubscribed: true)
        let unlisted = NativeCallTransportTrack(identity: agentIdentity, name: "lt:uk:@bob:matrix.org", isSubscribed: true)
        let state = NativeCallStateDerivation.derive(inputs(agentAttributes: agentDocument(languages: ["uk"], speakers: ["@carol:matrix.org"]),
                                                            tracks: [listed, unlisted]))

        #expect(!state.subscriptionPlan.isTrackExcluded(identity: agentIdentity, name: "lt:uk:@carol:matrix.org", kind: .audio))
        #expect(state.subscriptionPlan.isTrackExcluded(identity: agentIdentity, name: "lt:uk:@bob:matrix.org", kind: .audio))
        #expect(state.listening.translatedSpeakers.isEmpty, "nobody listed covers Bob, so his voice isn't ducked")
    }

    /// Brief 0068 Slice 1: a peer that announced a hold is never speaking
    /// and never live video, whatever the transport reports underneath —
    /// and only when EVERY device of theirs is held (one phone on hold, a
    /// laptop still talking, is a talking peer).
    @Test
    func aHeldPeerIsNeitherSpeakingNorVideoUntilEveryDeviceResumes() {
        var held = inputs()
        held.transportParticipants = [.init(identity: bobIdentity, isSpeaking: true, isAudioEnabled: true,
                                            isCameraEnabled: true, isOnHold: true)]
        let bob = NativeCallStateDerivation.derive(held).participants.first { $0.userID == "@bob:matrix.org" }
        #expect(bob?.isOnHold == true)
        #expect(bob?.isSpeaking == false)
        #expect(bob?.isVideoEnabled == false)

        var twoDevices = inputs()
        twoDevices.memberships.append(.init(userID: "@bob:matrix.org", deviceID: "LAPTOP", identity: "@bob:matrix.org:LAPTOP"))
        twoDevices.transportParticipants = [.init(identity: bobIdentity, isSpeaking: false, isAudioEnabled: false, isOnHold: true),
                                            .init(identity: "@bob:matrix.org:LAPTOP", isSpeaking: true, isAudioEnabled: true)]
        let bobTwice = NativeCallStateDerivation.derive(twoDevices).participants.first { $0.userID == "@bob:matrix.org" }
        #expect(bobTwice?.isOnHold == false, "one device still talking is a talking peer")
        #expect(bobTwice?.isSpeaking == true)
    }

    /// Brief 0068 Slice 3: the SFU losing a peer's link is a fact their row
    /// can state — and only when every device of theirs is gone.
    @Test
    func aPeerWhoseLinkTheSFULostIsReconnecting() {
        var lost = inputs()
        lost.transportParticipants = [.init(identity: bobIdentity, isSpeaking: false, isAudioEnabled: true,
                                            connectionQuality: .lost)]
        let bob = NativeCallStateDerivation.derive(lost).participants.first { $0.userID == "@bob:matrix.org" }
        #expect(bob?.isReconnecting == true)

        var poor = inputs()
        poor.transportParticipants = [.init(identity: bobIdentity, isSpeaking: false, isAudioEnabled: true,
                                            connectionQuality: .poor)]
        let bobPoor = NativeCallStateDerivation.derive(poor).participants.first { $0.userID == "@bob:matrix.org" }
        #expect(bobPoor?.isReconnecting == false, "poor is degraded, not gone")
    }

    /// Brief 0068 Slice 2: a CallKit hold silences this call entirely —
    /// nothing subscribed — while presence still counts its people; an
    /// audio-session interruption leaves the plan alone.
    @Test
    func aCallKitHoldEmptiesTheSubscriptionPlanButNotThePresence() {
        var held = inputs()
        held.isLocalOnHold = true
        held.holdSilencesMedia = true
        let silenced = NativeCallStateDerivation.derive(held)
        #expect(silenced.subscriptionPlan.authorizedIdentities.isEmpty)
        #expect(silenced.hasAuthorizedHumanRemote, "a call we hold still has its people in it")

        var interrupted = inputs()
        interrupted.isLocalOnHold = true
        let untouched = NativeCallStateDerivation.derive(interrupted)
        #expect(untouched.subscriptionPlan.authorizedIdentities.contains(bobIdentity),
                "a GSM interruption's engine is already parked; the plan stays")
    }

    @Test
    func liveKitAgentKindWinsBeforeMembershipAndAttributesArrive() {
        var earlyMedia = NativeCallDerivationInputs()
        earlyMedia.ownIdentity = "@alice:matrix.org:DEVICE"
        earlyMedia.transportLocalIdentity = "@alice:matrix.org:DEVICE"
        earlyMedia.transportParticipants = [.init(identity: agentIdentity,
                                                  isSpeaking: true,
                                                  isAudioEnabled: true,
                                                  isAgent: true)]

        let state = NativeCallStateDerivation.derive(earlyMedia)

        #expect(!state.hasHumanRemote)
        #expect(!state.hasAuthorizedHumanRemote)
    }

    @Test
    func liveKitAgentKindClassifiesAnIdleAgentWithoutADocument() {
        var idleAgent = inputs()
        idleAgent.serviceMembers = []
        idleAgent.transportParticipants = [.init(identity: bobIdentity, isSpeaking: false, isAudioEnabled: true),
                                           .init(identity: agentIdentity,
                                                 isSpeaking: false,
                                                 isAudioEnabled: false,
                                                 isAgent: true)]

        let state = NativeCallStateDerivation.derive(idleAgent)

        #expect(state.participants.first { $0.userID == "@agent:matrix.org" }?.role == .agent)
    }

    @Test
    func sameNameRepublishChangesTheSubscriptionPlan() {
        let old = NativeCallTransportTrack(identity: agentIdentity,
                                           name: "lt:uk:@bob:matrix.org",
                                           isSubscribed: false,
                                           trackID: "TR_old")
        let new = NativeCallTransportTrack(identity: agentIdentity,
                                           name: "lt:uk:@bob:matrix.org",
                                           isSubscribed: false,
                                           trackID: "TR_new")

        let oldPlan = NativeCallStateDerivation.derive(inputs(tracks: [old])).subscriptionPlan
        let newPlan = NativeCallStateDerivation.derive(inputs(tracks: [new])).subscriptionPlan

        #expect(oldPlan != newPlan)
    }

    /// The runtime publishes a lane MUTED and unmutes it on the first
    /// usable frame. Before that frame the claim stands and the original is
    /// already quiet (rev. 2); the microphone stays subscribed either way.
    @Test
    func aMutedLaneThatNeverAiredLeavesTheClaimStanding() {
        let translation = NativeCallTransportTrack(identity: agentIdentity,
                                                   name: "lt:uk:@bob:matrix.org",
                                                   isSubscribed: true,
                                                   source: .microphone,
                                                   isMuted: true)
        let microphone = NativeCallTransportTrack(identity: bobIdentity,
                                                  name: "microphone",
                                                  isSubscribed: true,
                                                  source: .microphone)

        let state = NativeCallStateDerivation.derive(inputs(agentAttributes: agentDocument(languages: ["uk"]),
                                                            tracks: [translation, microphone]))

        #expect(state.listening.translatedSpeakers == ["@bob:matrix.org": "uk"])
        #expect(state.listening.falteredSpeakers.isEmpty)
        #expect(state.subscriptionPlan.duckedSpeakers == ["@bob:matrix.org"])
        #expect(!state.subscriptionPlan.isTrackExcluded(identity: bobIdentity,
                                                        name: "microphone",
                                                        kind: .audio,
                                                        source: .microphone))
    }

    // MARK: - Brief 0066 rev. 2 — coverage IS ducking, statically

    private let carolIdentity = "@carol:matrix.org:CAROL"

    /// Alice (us), Bob, Carol and one agent, no lanes published yet: the
    /// document alone decides who is quiet for us.
    private func groupInputs(agentAttributes: [String: String],
                             tracks: [NativeCallTransportTrack] = [],
                             choice: NativeCallListeningChoice = .language("en"),
                             lanesSeenLive: Set<NativeCallLaneKey> = []) -> NativeCallDerivationInputs {
        var inputs = inputs(agentAttributes: agentAttributes, tracks: tracks, choice: choice)
        inputs.memberships.append(.init(userID: "@carol:matrix.org", deviceID: "CAROL", identity: carolIdentity))
        inputs.transportParticipants.append(.init(identity: carolIdentity, isSpeaking: false, isAudioEnabled: true))
        inputs.lanesSeenLive = lanesSeenLive
        return inputs
    }

    /// Scenario 1 — "translate only me" as Bob hears it: the booth names
    /// Alice, so nobody on Bob's device is ducked. As Alice hears it (this
    /// test's device is Alice): Bob and Carol are at unity too. The
    /// mirror — Bob's device ducking Alice — is scenario 1b.
    @Test
    func aBoothCoveringOnlyMeDucksNobodyForMe() {
        let document = agentDocument(languages: ["en"], speakers: ["@alice:matrix.org"])
        let state = NativeCallStateDerivation.derive(groupInputs(agentAttributes: document))

        #expect(state.listening.translatedSpeakers.isEmpty)
        #expect(state.subscriptionPlan.originalDucking.identitiesBySpeaker.isEmpty)
    }

    /// Scenario 1b — the same booth from Bob's chair: Alice is quiet for
    /// him from the moment the document says so, no lane needed.
    @Test
    func aBoothCoveringAnotherSpeakerDucksThemBeforeTheirFirstWord() {
        let document = agentDocument(languages: ["en"], speakers: ["@bob:matrix.org"])
        let state = NativeCallStateDerivation.derive(groupInputs(agentAttributes: document))

        #expect(state.listening.translatedSpeakers == ["@bob:matrix.org": "en"])
        #expect(state.subscriptionPlan.originalDucking.identitiesBySpeaker == ["@bob:matrix.org": [bobIdentity]])
        #expect(state.subscriptionPlan.originalDucking.floor == 0.15)
        #expect(state.participants.first { $0.userID == "@bob:matrix.org" }?.isTranslated == true)
        #expect(state.participants.first { $0.userID == "@carol:matrix.org" }?.isTranslated == false)
    }

    /// Scenario 2 — "translate everyone": every other human is quiet for
    /// us; the agent (named by `anyone` too) and we ourselves are not.
    @Test
    func anOpenBoothDucksEveryRemoteHumanAndNoAgent() {
        let state = NativeCallStateDerivation.derive(groupInputs(agentAttributes: agentDocument(languages: ["en"])))

        #expect(state.listening.translatedSpeakers == ["@bob:matrix.org": "en", "@carol:matrix.org": "en"])
        #expect(state.subscriptionPlan.originalDucking.identitiesBySpeaker == ["@bob:matrix.org": [bobIdentity],
                                                                               "@carol:matrix.org": [carolIdentity]])
    }

    /// Scenario 3 — the listener switches to the original voices: nothing
    /// is ducked and no lane is subscribed, on this device only.
    @Test
    func choosingTheOriginalVoicesLiftsEveryDuck() {
        let state = NativeCallStateDerivation.derive(groupInputs(agentAttributes: agentDocument(languages: ["en"]),
                                                                 choice: .original))

        #expect(state.listening.channel == .original)
        #expect(state.listening.translatedSpeakers.isEmpty)
        #expect(state.subscriptionPlan.originalDucking.identitiesBySpeaker.isEmpty)
    }

    /// Scenario 4 — a paused agent (configured, not active) or a leaving
    /// one covers nobody.
    @Test
    func aPausedOrLeavingAgentDucksNobody() {
        let paused = NativeCallStateDerivation.derive(groupInputs(agentAttributes: agentDocument(languages: ["en"], active: false)))
        #expect(paused.listening.translatedSpeakers.isEmpty)

        let leaving = NativeCallStateDerivation.derive(groupInputs(agentAttributes: agentDocument(languages: ["en"], lifecycle: "leaving")))
        #expect(leaving.listening.translatedSpeakers.isEmpty)
    }

    /// Scenario 5 is `aConsecutiveTrackNeverDucksTheLiveMicrophone`.
    /// Scenario 6 — two devices of one covered speaker drop together.
    @Test
    func everyDeviceOfACoveredSpeakerIsDucked() {
        var inputs = groupInputs(agentAttributes: agentDocument(languages: ["en"]))
        inputs.memberships.append(.init(userID: "@bob:matrix.org", deviceID: "PAD", identity: "@bob:matrix.org:PAD"))
        inputs.transportParticipants.append(.init(identity: "@bob:matrix.org:PAD", isSpeaking: false, isAudioEnabled: true))
        let state = NativeCallStateDerivation.derive(inputs)

        #expect(state.subscriptionPlan.originalDucking.identitiesBySpeaker["@bob:matrix.org"] == [bobIdentity, "@bob:matrix.org:PAD"])
    }

    /// A speaker with no lane is heard in the original (D10).
    @Test
    func aSpeakerWithoutALaneIsSpared() {
        let state = NativeCallStateDerivation.derive(groupInputs(agentAttributes: agentDocument(languages: ["en"], speakers: ["@carol:matrix.org"])))

        #expect(state.listening.translatedSpeakers == ["@carol:matrix.org": "en"])
    }

    // MARK: - Fail audible (variant A): a lane that aired and stopped under a talking speaker

    private var bobLane: NativeCallLaneKey {
        .init(agentIdentity: agentIdentity, language: "en", speaker: "@bob:matrix.org")
    }

    private func speaking(_ inputs: NativeCallDerivationInputs, _ identities: Set<String>) -> NativeCallDerivationInputs {
        var inputs = inputs
        inputs.transportParticipants = inputs.transportParticipants.map { participant in
            .init(identity: participant.identity,
                  isSpeaking: identities.contains(participant.identity),
                  isAudioEnabled: participant.isAudioEnabled,
                  isAgent: participant.isAgent,
                  attributes: participant.attributes)
        }
        return inputs
    }

    /// Bob's lane aired on this device, the runtime muted it (echo breaker)
    /// and Bob is talking with nothing over him: he comes back to unity,
    /// only he, and only his agent's block says its translation faltered.
    /// The claim (roster marker) stands.
    @Test
    func aTalkingSpeakerWhoseAiredLaneIsMutedIsHeardInFullAgain() {
        let muted = NativeCallTransportTrack(identity: agentIdentity, name: "lt:en:@bob:matrix.org", isSubscribed: true, isMuted: true)
        let inputs = speaking(groupInputs(agentAttributes: agentDocument(languages: ["en"]), tracks: [muted], lanesSeenLive: [bobLane]),
                              [bobIdentity])
        let state = NativeCallStateDerivation.derive(inputs)

        #expect(state.listening.translatedSpeakers.keys.sorted() == ["@bob:matrix.org", "@carol:matrix.org"])
        #expect(state.listening.falteredSpeakers == ["@bob:matrix.org"])
        #expect(state.listening.falteredAgents == ["@agent:matrix.org"])
        #expect(state.subscriptionPlan.duckedSpeakers == ["@carol:matrix.org"], "only the faltered speaker is lifted")
        #expect(state.participants.first { $0.userID == "@bob:matrix.org" }?.isTranslated == true)
    }

    /// The lane coming back (unmuted, or republished) ends the falter.
    @Test
    func aLaneAiringAgainDucksItsSpeakerAgain() {
        let airing = NativeCallTransportTrack(identity: agentIdentity, name: "lt:en:@bob:matrix.org", isSubscribed: true)
        let inputs = speaking(groupInputs(agentAttributes: agentDocument(languages: ["en"]), tracks: [airing], lanesSeenLive: [bobLane]),
                              [bobIdentity])
        let state = NativeCallStateDerivation.derive(inputs)

        #expect(state.listening.falteredSpeakers.isEmpty)
        #expect(state.subscriptionPlan.duckedSpeakers == ["@bob:matrix.org", "@carol:matrix.org"])
    }

    /// Two agents cover Bob; one lane is muted while the other airs — Bob
    /// IS being translated, nothing faltered.
    @Test
    func aSecondAgentsAiringLaneKeepsTheSpeakerDucked() {
        let otherAgent = "@other:matrix.org:OTHER"
        let muted = NativeCallTransportTrack(identity: agentIdentity, name: "lt:en:@bob:matrix.org", isSubscribed: true, isMuted: true)
        let airing = NativeCallTransportTrack(identity: otherAgent, name: "lt:de:@bob:matrix.org", isSubscribed: true)
        var inputs = groupInputs(agentAttributes: agentDocument(languages: ["en"]), tracks: [muted, airing], lanesSeenLive: [bobLane])
        inputs.memberships.append(.init(userID: "@other:matrix.org", deviceID: "OTHER", identity: otherAgent))
        inputs.transportParticipants.append(.init(identity: otherAgent, isSpeaking: false, isAudioEnabled: true,
                                                  attributes: agentDocument(languages: ["de"])))
        let state = NativeCallStateDerivation.derive(speaking(inputs, [bobIdentity]))

        #expect(state.listening.falteredSpeakers.isEmpty)
        #expect(state.subscriptionPlan.duckedSpeakers.contains("@bob:matrix.org"))
    }

    /// A memory of a lane nobody claims any more is not a falter: the
    /// coverage ended, so did the duck — nothing to report. The airing
    /// lane of an uncovered speaker changes nothing either: the document
    /// decides, not the track.
    @Test
    func aLaneMemoryWithoutACoveringClaimIsNotAFalter() {
        let airing = NativeCallTransportTrack(identity: agentIdentity, name: "lt:en:@bob:matrix.org", isSubscribed: true)
        let inputs = speaking(groupInputs(agentAttributes: agentDocument(languages: []), tracks: [airing], lanesSeenLive: [bobLane]),
                              [bobIdentity])
        let state = NativeCallStateDerivation.derive(inputs)

        #expect(state.listening.falteredSpeakers.isEmpty)
        #expect(state.subscriptionPlan.duckedSpeakers.isEmpty)
    }

    // MARK: - Never aired after 4 s of speech (operator, 2026-11-12)

    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// One input write `seconds` into the call: Bob speaking or not, his lane into English on the air (unmuted, the
    /// agent speaking) or not, the agent speaking for someone else, and his coverage standing or not. The lane memory is
    /// folded as the session does, so a rule that read it would see the same airing.
    private func look(_ memory: [NativeCallCoverageKey: NativeCallUnairedCoverage],
                      at seconds: TimeInterval,
                      bobSpeaks: Bool,
                      bobsLaneAired: Bool = false,
                      agentSpeaks: Bool = false,
                      bobCovered: Bool = true,
                      isOneToOne: Bool = false) -> [NativeCallCoverageKey: NativeCallUnairedCoverage] {
        let document = bobCovered ? agentDocument(languages: ["en"]) : agentDocument(languages: ["en"], speakers: ["@carol:matrix.org"])
        let tracks = bobsLaneAired ? [airingLane()] : []
        var call = isOneToOne ? inputs(agentAttributes: document, tracks: tracks, choice: .language("en"))
            : groupInputs(agentAttributes: document, tracks: tracks)
        let speakers = Set([bobSpeaks ? bobIdentity : nil, bobsLaneAired || agentSpeaks ? agentIdentity : nil].compactMap(\.self))
        call = speaking(call, speakers)
        call.lanesSeenLive = NativeCallStateDerivation.lanesSeenLive(previous: [], inputs: call)
        return NativeCallStateDerivation.unairedCoverage(previous: memory, inputs: call, now: start.addingTimeInterval(seconds))
    }

    private func ducked(_ memory: [NativeCallCoverageKey: NativeCallUnairedCoverage], bobSpeaks: Bool = false) -> Set<String> {
        var inputs = speaking(groupInputs(agentAttributes: agentDocument(languages: ["en"])), bobSpeaks ? [bobIdentity] : [])
        inputs.unairedCoverage = memory
        return NativeCallStateDerivation.derive(inputs).subscriptionPlan.duckedSpeakers
    }

    /// A Russian UI, Ukrainian speech: Bob's lane exists and never airs. After 4 s of his speech he is heard in full —
    /// not a falter, nothing says so — and stays so through a long pause.
    @Test
    func aSpeakerWhoseLaneNeverAirsIsHeardInFullAfterFourSecondsOfSpeech() {
        var memory = look([:], at: 0, bobSpeaks: true)
        memory = look(memory, at: 2, bobSpeaks: true)
        #expect(ducked(memory, bobSpeaks: true) == ["@bob:matrix.org", "@carol:matrix.org"])

        memory = look(memory, at: 4.1, bobSpeaks: true)
        #expect(memory[.init(speaker: "@bob:matrix.org", language: "en")]?.isReleased == true)
        var inputs = speaking(groupInputs(agentAttributes: agentDocument(languages: ["en"])), [bobIdentity])
        inputs.unairedCoverage = memory
        let state = NativeCallStateDerivation.derive(inputs)
        #expect(state.subscriptionPlan.duckedSpeakers == ["@carol:matrix.org"])
        #expect(state.listening.unairedSpeakers == ["@bob:matrix.org"])
        #expect(state.listening.falteredSpeakers.isEmpty)
        #expect(state.listening.falteredAgents.isEmpty)

        memory = look(memory, at: 5, bobSpeaks: false)
        memory = look(memory, at: 600, bobSpeaks: false)
        #expect(ducked(memory) == ["@carol:matrix.org"])
    }

    /// Speech, not wall time: two seconds, a long pause, two more — released; silence alone releases nobody.
    @Test
    func theReleaseCountsSpeechNotTime() {
        var memory = look([:], at: 0, bobSpeaks: true)
        memory = look(memory, at: 2, bobSpeaks: false)
        memory = look(memory, at: 300, bobSpeaks: false)
        #expect(ducked(memory) == ["@bob:matrix.org", "@carol:matrix.org"])
        #expect(memory[.init(speaker: "@bob:matrix.org", language: "en")]?.releaseDate == nil)

        memory = look(memory, at: 310, bobSpeaks: true)
        #expect(memory[.init(speaker: "@bob:matrix.org", language: "en")]?.releaseDate == start.addingTimeInterval(312))
        memory = look(memory, at: 312.1, bobSpeaks: false)
        #expect(ducked(memory) == ["@carol:matrix.org"])
    }

    /// A real foreign speaker: the lane airs 2.5 s into the first sentence. Ducked from the first word, and still after
    /// long speech.
    @Test
    func aSpeakerWhoseLaneAirsStaysDuckedFromTheFirstWord() {
        var memory = look([:], at: 0, bobSpeaks: true)
        #expect(ducked(memory, bobSpeaks: true).contains("@bob:matrix.org"))
        memory = look(memory, at: 2.5, bobSpeaks: true, bobsLaneAired: true)
        memory = look(memory, at: 3, bobSpeaks: true, bobsLaneAired: true)
        memory = look(memory, at: 3.5, bobSpeaks: true)
        memory = look(memory, at: 10, bobSpeaks: true)
        memory = look(memory, at: 11, bobSpeaks: false)
        #expect(ducked(memory, bobSpeaks: true).contains("@bob:matrix.org"))
        #expect(memory[.init(speaker: "@bob:matrix.org", language: "en")]?.releaseDate == nil)
    }

    /// Released, then a lane of his airs at last: ducked again, as today.
    @Test
    func aReleasedSpeakerIsDuckedAgainWhenHisLaneAirs() {
        var memory = look([:], at: 0, bobSpeaks: true)
        memory = look(memory, at: 5, bobSpeaks: true)
        #expect(!ducked(memory).contains("@bob:matrix.org"))

        memory = look(memory, at: 6, bobSpeaks: true, bobsLaneAired: true)
        memory = look(memory, at: 20, bobSpeaks: true)
        #expect(ducked(memory).contains("@bob:matrix.org"))
    }

    /// Review of 2026-11-12: Bob's lane sitting published unmuted while the agent voices Carol isn't Bob's translation.
    /// He is still released after 4 s of his own speech.
    @Test
    func aLaneAiringWhileTheAgentVoicesSomeoneElseIsntHisTranslation() {
        var memory = look([:], at: 0, bobSpeaks: false, bobsLaneAired: true)
        memory = look(memory, at: 1, bobSpeaks: false, agentSpeaks: true)
        memory = look(memory, at: 20, bobSpeaks: true)
        memory = look(memory, at: 24.5, bobSpeaks: true)
        #expect(!ducked(memory).contains("@bob:matrix.org"))
    }

    /// …nor is a lane unmuted for a beat (under half a second) before the runtime mutes it.
    @Test
    func aBeatOfAiringIsntHisTranslation() {
        var memory = look([:], at: 0, bobSpeaks: true)
        memory = look(memory, at: 1, bobSpeaks: true, bobsLaneAired: true)
        memory = look(memory, at: 1.2, bobSpeaks: true)
        memory = look(memory, at: 4.5, bobSpeaks: true)
        #expect(!ducked(memory).contains("@bob:matrix.org"))
    }

    /// A 1:1 with Bob the same (operator, 2026-11-12).
    @Test
    func theReleaseHoldsInAOneToOneCall() {
        var memory = look([:], at: 0, bobSpeaks: true, isOneToOne: true)
        memory = look(memory, at: 4.5, bobSpeaks: true, isOneToOne: true)
        var inputs = speaking(inputs(agentAttributes: agentDocument(languages: ["en"]), choice: .language("en")), [bobIdentity])
        inputs.unairedCoverage = memory
        let state = NativeCallStateDerivation.derive(inputs)
        #expect(state.listening.translatedSpeakers == ["@bob:matrix.org": "en"])
        #expect(state.subscriptionPlan.duckedSpeakers.isEmpty)
    }

    /// Coverage that ends and comes back counts from zero.
    @Test
    func coverageStartingAnewCountsFromZero() {
        var memory = look([:], at: 0, bobSpeaks: true)
        memory = look(memory, at: 3, bobSpeaks: false)
        memory = look(memory, at: 4, bobSpeaks: false, bobCovered: false)
        #expect(memory[.init(speaker: "@bob:matrix.org", language: "en")] == nil)

        memory = look(memory, at: 5, bobSpeaks: true)
        memory = look(memory, at: 7, bobSpeaks: false)
        #expect(ducked(memory).contains("@bob:matrix.org"))
    }

    // MARK: - The lane memory

    private func airingLane(_ language: String = "en", agent: String? = nil) -> NativeCallTransportTrack {
        .init(identity: agent ?? agentIdentity, name: "lt:\(language):@bob:matrix.org", isSubscribed: true)
    }

    private func mutedLane(_ language: String = "en") -> NativeCallTransportTrack {
        .init(identity: agentIdentity, name: "lt:\(language):@bob:matrix.org", isSubscribed: true, isMuted: true)
    }

    private func memory(_ previous: Set<NativeCallLaneKey>,
                        tracks: [NativeCallTransportTrack],
                        speaking: Set<String> = [],
                        languages: [String] = ["en"]) -> Set<NativeCallLaneKey> {
        let inputs = self.speaking(inputs(agentAttributes: agentDocument(languages: languages), tracks: tracks), speaking)
        return NativeCallStateDerivation.lanesSeenLive(previous: previous, inputs: inputs)
    }

    /// A lane is remembered once it airs with its agent audibly speaking —
    /// the runtime publishes a lane unmuted for a beat before muting it,
    /// so "unmuted" alone is not "aired".
    @Test
    func aLaneJoinsTheMemoryOnceItAirsWithTheAgentSpeaking() {
        #expect(memory([], tracks: [airingLane()]).isEmpty)
        #expect(memory([], tracks: [mutedLane()], speaking: [agentIdentity]).isEmpty)
        #expect(memory([], tracks: [airingLane()], speaking: [agentIdentity]) == [bobLane])
        #expect(memory([], tracks: [.init(identity: agentIdentity, name: "lt:en", isSubscribed: true)], speaking: [agentIdentity]).isEmpty,
                "a shared consecutive track names no speaker")
    }

    /// The runtime closes a lane that idles for ten minutes and reopens it
    /// on the next voiced frame: a lane that stops while its speaker is
    /// SILENT ended normally and is forgotten — the next sentence lands
    /// over a quiet original, not over a pumped one. A lane that stops
    /// while the speaker is TALKING is kept, and that is the falter.
    @Test
    func aLaneThatStopsUnderASilentSpeakerIsForgottenAndUnderATalkingOneIsKept() {
        #expect(memory([bobLane], tracks: [mutedLane()]).isEmpty)
        #expect(memory([bobLane], tracks: []).isEmpty)
        #expect(memory([bobLane], tracks: [mutedLane()], speaking: [bobIdentity]) == [bobLane])
        #expect(memory([bobLane], tracks: [], speaking: [bobIdentity]) == [bobLane])
        #expect(memory([bobLane], tracks: [airingLane()]) == [bobLane], "an airing lane is kept whoever is speaking")
    }

    /// This device unsubscribing the lane (the listener chose the original
    /// voices, the call is held) is not a failure; nor is the owner moving
    /// the speaker to another language — the old lane is stale, not broken.
    @Test
    func aLaneThisDeviceDroppedOrTheAgentStoppedClaimingIsForgotten() {
        let unsubscribed = NativeCallTransportTrack(identity: agentIdentity, name: "lt:en:@bob:matrix.org", isSubscribed: false)
        #expect(memory([bobLane], tracks: [unsubscribed], speaking: [bobIdentity]).isEmpty)
        #expect(memory([bobLane], tracks: [airingLane()], speaking: [bobIdentity], languages: ["de"]).isEmpty)
    }

    /// The memory leaves with the agent — a replacement agent ducks from its
    /// first document, not from its first sentence.
    @Test
    func theLaneMemoryLeavesWithTheAgent() {
        var agentGone = speaking(inputs(tracks: []), [bobIdentity])
        agentGone.transportParticipants.removeAll { $0.identity == agentIdentity }
        #expect(NativeCallStateDerivation.lanesSeenLive(previous: [bobLane], inputs: agentGone).isEmpty)
    }

    // MARK: - The agent as the callee (operator report 2026-09-11)

    /// Calling one's own assistant: the DM's other member IS the agent. Its
    /// presence must be derivable on its own — `hasHumanRemote` stays
    /// human-only so a translating agent never answers a human's ring.
    @Test
    func anAgentOnTheTransportIsPresentAndAuthorizedAsAnAgent() {
        var alone = NativeCallDerivationInputs()
        alone.ownIdentity = "@alice:matrix.org:DEVICE"
        alone.transportLocalIdentity = "@alice:matrix.org:DEVICE"
        alone.memberships = [.init(userID: "@agent:matrix.org", deviceID: "AGENT", identity: agentIdentity)]
        alone.transportParticipants = [.init(identity: agentIdentity, isSpeaking: false, isAudioEnabled: true, isAgent: true)]

        let state = NativeCallStateDerivation.derive(alone)

        #expect(state.hasAgentRemote)
        #expect(state.hasAuthorizedAgentRemote)
        #expect(!state.hasHumanRemote, "an agent is still not a human peer")
        #expect(!state.hasAuthorizedHumanRemote)
    }

    /// Review 2026-10-11: with no member hints (one's own assistant's DM,
    /// backend `02043c5e`) and a participant that arrives with a standard
    /// kind before its document, the agent is still the call's agent — the
    /// same rule the call scope uses — never a human peer.
    @Test
    func anUnhintedAgentIsAnAgentBeforeItsKindOrDocument() {
        let assistantIdentity = "@assistant-alice:matrix.org:AGENT"
        var unhinted = NativeCallDerivationInputs()
        unhinted.ownIdentity = "@alice:matrix.org:DEVICE"
        unhinted.transportLocalIdentity = "@alice:matrix.org:DEVICE"
        unhinted.serviceMembers = []
        unhinted.memberships = [.init(userID: "@assistant-alice:matrix.org", deviceID: "AGENT", identity: assistantIdentity)]

        let announced = NativeCallStateDerivation.derive(unhinted)
        #expect(!announced.hasHumanRemote, "the assistant's membership is not a human peer")
        #expect(announced.participants.first { $0.userID == "@assistant-alice:matrix.org" }?.role == .agent)

        unhinted.transportParticipants = [.init(identity: assistantIdentity, isSpeaking: false, isAudioEnabled: true, isAgent: false)]
        let answered = NativeCallStateDerivation.derive(unhinted)
        #expect(answered.hasAgentRemote)
        #expect(answered.hasAuthorizedAgentRemote)
        #expect(!answered.hasHumanRemote)
        #expect(!answered.hasAuthorizedHumanRemote)
    }

    // MARK: - Anybody on the SFU, for the joined-call wait (review of L1a)

    private func onlyOnTheSFU(_ participants: [NativeCallTransportParticipant],
                              memberships: [MatrixRTCParticipant] = [],
                              serviceMembers: Set<String> = []) -> NativeCallDerivedState {
        var inputs = NativeCallDerivationInputs()
        inputs.ownIdentity = "@alice:matrix.org:DEVICE"
        inputs.transportLocalIdentity = "@alice:matrix.org:DEVICE"
        inputs.serviceMembers = serviceMembers
        inputs.memberships = memberships
        inputs.transportParticipants = participants
        return NativeCallStateDerivation.derive(inputs)
    }

    /// A muted caller with the camera off whose membership has not synced:
    /// on the SFU for the wait, nobody for the leave rules.
    @Test
    func aMutedHumanWithoutAMembershipIsOnTheTransportOnly() {
        let state = onlyOnTheSFU([.init(identity: bobIdentity, isSpeaking: false, isAudioEnabled: false)])

        #expect(state.hasHumanOnTransport)
        #expect(!state.hasHumanRemote)
    }

    /// An agent the room's hints name is not a human on the SFU.
    @Test
    func aHintedAgentIsNotAHumanOnTheTransport() {
        let state = onlyOnTheSFU([.init(identity: agentIdentity, isSpeaking: false, isAudioEnabled: true)],
                                 memberships: [.init(userID: "@agent:matrix.org", deviceID: "AGENT", identity: agentIdentity)],
                                 serviceMembers: ["@agent:matrix.org"])

        #expect(!state.hasHumanOnTransport)
    }

    /// Nor is a participant LiveKit marks as an agent, before any membership
    /// or hint says so.
    @Test
    func aLiveKitAgentIsNotAHumanOnTheTransport() {
        let state = onlyOnTheSFU([.init(identity: "@carol:matrix.org:CAROL", isSpeaking: false, isAudioEnabled: false, isAgent: true)])

        #expect(!state.hasHumanOnTransport)
    }

    /// Nor is another device of the user's own.
    @Test
    func anotherOwnDeviceIsNotAHumanOnTheTransport() {
        let state = onlyOnTheSFU([.init(identity: "@alice:matrix.org:PHONE", isSpeaking: false, isAudioEnabled: true)])

        #expect(!state.hasHumanOnTransport)
    }

    /// The rule names this server's agents only: another server's
    /// `@assistant-…` is a person (ADR-0082's namespaces are ours alone).
    @Test
    func anotherServersAgentNamespaceIsAPerson() {
        let strangerIdentity = "@assistant-mallory:elsewhere.org:DEVICE"
        var foreign = NativeCallDerivationInputs()
        foreign.ownIdentity = "@alice:matrix.org:DEVICE"
        foreign.transportLocalIdentity = "@alice:matrix.org:DEVICE"
        foreign.memberships = [.init(userID: "@assistant-mallory:elsewhere.org", deviceID: "DEVICE", identity: strangerIdentity)]
        foreign.transportParticipants = [.init(identity: strangerIdentity, isSpeaking: false, isAudioEnabled: true, isAgent: false)]

        let state = NativeCallStateDerivation.derive(foreign)

        #expect(state.hasHumanRemote)
        #expect(!state.hasAgentRemote)
    }

    /// The agent's `m.call.member` lands ~1 s before it joins the SFU. A
    /// membership alone is "on its way", not "answered": the ring goes on
    /// until media can flow.
    @Test
    func anAgentMembershipWithoutTransportIsNotAnAnswer() {
        var announced = NativeCallDerivationInputs()
        announced.ownIdentity = "@alice:matrix.org:DEVICE"
        announced.transportLocalIdentity = "@alice:matrix.org:DEVICE"
        announced.memberships = [.init(userID: "@agent:matrix.org", deviceID: "AGENT", identity: agentIdentity)]
        announced.serviceMembers = ["@agent:matrix.org"]

        let state = NativeCallStateDerivation.derive(announced)

        #expect(!state.hasAgentRemote)
        #expect(!state.hasAuthorizedAgentRemote)
    }

    @Test
    func aHumanPeerIsNotAnAgentRemote() {
        var humanOnly = inputs()
        humanOnly.transportParticipants.removeAll { $0.identity == agentIdentity }
        humanOnly.memberships.removeAll { $0.identity == agentIdentity }

        let state = NativeCallStateDerivation.derive(humanOnly)

        #expect(state.hasHumanRemote)
        #expect(!state.hasAgentRemote)
        #expect(!state.hasAuthorizedAgentRemote)
    }
}
