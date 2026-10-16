//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063): the call screen's derived state as ONE
// PURE FUNCTION of ALL its inputs.
//
// Why: the previous design recomputed the roster, the listening state
// and the media subscriptions from scattered imperative triggers
// (`updateParticipants()` / `reconcileTrackSubscriptions()` sprinkled
// through every event handler plus cross-layer pokes). Every input
// source added by a slice needed its own set of manual triggers, and
// every forgotten trigger was a live defect the operator had to find by
// hand: the stale listening picker after an agent left, the frozen
// "Listening in …" header after a CAS disable, the missing Agent badge
// on a mid-call attach.
//
// Now: event handlers only WRITE INPUTS through the session's single
// `updateInputs` funnel; this module derives everything, always, on any
// input change. The "forgot to recompute" class of defects is gone by
// construction — there are no triggers left to forget.

import Foundation

/// Every fact the derived call state depends on. All of it lives here —
/// if a future slice adds a new source of truth it MUST become an input
/// so the derivation stays total.
nonisolated struct NativeCallDerivationInputs: Equatable {
    /// MatrixRTC memberships — the roster's source of truth.
    var memberships: [MatrixRTCParticipant] = []
    /// Identities whose media key arrived (E2EE readiness).
    var identitiesWithKeys: Set<String> = []
    /// Identities whose frames stopped decrypting AFTER a key arrived —
    /// the transport's E2EE health signal. Presentation-only: the roster
    /// shows them waiting for encryption instead of silently connected.
    var identitiesWithEncryptionFailure: Set<String> = []
    /// The transport's remote peers (SFU presence + speaking/mute).
    var transportParticipants: [NativeCallTransportParticipant] = []
    /// Every remote audio publication (translation routing + liveness).
    var transportTracks: [NativeCallTransportTrack] = []
    var isLocalSpeaking = false
    /// G10 — the transport reports our link degraded.
    var localConnectionQuality: NativeCallConnectionQuality = .unknown
    var isMicrophoneEnabled = true
    /// Whether OUR camera publishes. Read from the engine on every input
    /// write, never from the last request.
    var isCameraEnabled = false
    /// Brief 0068: we put the call on hold — our own row/tile must say so
    /// rather than "muted", which is what the muted publication underneath
    /// would otherwise read as.
    var isLocalOnHold = false
    /// Brief 0068 Slice 2: the hold is CallKit's (a second Spiral call is
    /// active and shares the one audio engine), so nothing of this call may
    /// play — the subscription plan empties. An audio-session interruption
    /// (a GSM call) leaves the plan alone: its engine is already parked by
    /// the deactivation, and a full unsubscribe/re-subscribe walk would only
    /// delay the audio coming back.
    var holdSilencesMedia = false
    /// The identity the transport assigned us; nil until connected.
    var transportLocalIdentity: String?
    /// Our MatrixRTC identity (`<mxid>:<device>`).
    var ownIdentity = ""
    /// Agent MXIDs from the room's member hints (live, not a snapshot).
    var serviceMembers: Set<String> = []
    /// The user's personal listening switch (client-only, per call).
    var listeningChoice: NativeCallListeningChoice = .translation
    /// Brief 0066 rev. 2 — the one piece of HISTORY the ducking rule
    /// needs: simultaneous lanes that have aired on this device. A covered
    /// speaker with a lane in here, no lane airing and their voice on the
    /// air has a FALTERED translation: their original comes back to unity.
    /// The session maintains it through `NativeCallStateDerivation.lanesSeenLive`
    /// on every input write; the derivation itself stays pure.
    var lanesSeenLive: Set<NativeCallLaneKey> = []
    var isRoomEncrypted = false
}

/// One simultaneous lane, `lt:<language>:<speaker>` published by an agent,
/// as the lane memory remembers it. Keyed by the agent's identity so the
/// memory leaves with the agent: a replacement agent starts fresh and
/// ducks from its first document, not from its first sentence.
nonisolated struct NativeCallLaneKey: Hashable {
    let agentIdentity: String
    let language: String
    let speaker: String
}

/// The media-subscription half of the derived state: enough to decide,
/// per track, whether it should be subscribed. Pure and Equatable so
/// the executor can skip a no-op application.
/// Identifies one publication for exclusion decisions. Deliberately not
/// `NativeCallTransportTrack`, whose `isSubscribed` flips as the plan is
/// applied and would make the key unstable.
nonisolated struct NativeCallTrackKey: Hashable {
    let identity: String
    // periphery:ignore - used via the synthesized Hashable conformance
    let trackID: String
    let name: String
}

nonisolated struct NativeCallSubscriptionPlan: Equatable {
    let authorizedIdentities: Set<String>
    // periphery:ignore - used via the synthesized Equatable conformance
    /// EVERY publication currently on the SFU, subscribed or not.
    ///
    /// The plan is desired state and the executor skips a plan equal to the
    /// applied one — so without the publication set, a lane published AFTER
    /// the plan settled produced an identical plan and was never subscribed.
    /// That is exactly when a per-speaker translation lane appears (the
    /// agent joins, then publishes the lane when it first airs), which made
    /// the agent audible in the recording and silent in the call while its
    /// wave — driven by the server's speaking signal, not by subscriptions
    /// — kept moving. Found on a device, 2026-08-21.
    let publications: Set<NativeCallTrackKey>
    let channel: NativeCallListeningChannel
    /// Publications the agent's own state document no longer claims. They
    /// are never subscribed: a stale lane is either audible nonsense or, in
    /// `.everything`, a second voice over the raw microphone.
    let staleTranslationTracks: Set<NativeCallTrackKey>
    /// Brief 0066 rev. 2 — speakers this device hears in translation
    /// (covered by a live Live-style claim) minus those whose translation
    /// has faltered: exactly whose raw microphones are quiet right now.
    let duckedSpeakers: Set<String>
    /// Identities whose video this device wants to receive. Video is
    /// expensive, so it is subscribed for what is actually on screen — in a
    /// 1:1 that is simply every authorized peer.
    let visibleVideoIdentities: Set<String>
    let userIDByIdentity: [String: String]
    let ownUserID: String

    func isTrackExcluded(identity: String,
                         name: String,
                         kind: NativeCallTransportTrack.Kind,
                         trackID: String = "",
                         source: NativeCallTransportTrack.Source = .unknown) -> Bool {
        // Video has its own policy. The listening rules below are about
        // AUDIO — they read an unnamed publication as "a raw microphone",
        // so routing a camera through them would black out a translated
        // speaker's picture whenever their translation lane went live.
        guard kind == .audio else {
            return !visibleVideoIdentities.contains(identity)
        }
        if staleTranslationTracks.contains(.init(identity: identity, trackID: trackID, name: name)) {
            return true
        }
        // Screen-share audio is presentation audio, not the speaker's raw
        // microphone. Translation may replace speech but never shared media.
        if source == .screenShareAudio, !NativeCallListening.isTranslationTrack(trackName: name) {
            return false
        }
        return NativeCallListening.isTrackExcluded(trackName: name, channel: channel, ownUserID: ownUserID)
    }

    /// Brief 0066 rev. 2 — what the transport ducks: every device of every
    /// ducked speaker, at `NativeCallListening.originalGain`, for as long
    /// as this plan stands. Empty in the `original` channel (the listener
    /// asked for the voices) and for consecutive (nobody is covered).
    var originalDucking: NativeCallOriginalDucking {
        var identitiesBySpeaker: [String: Set<String>] = [:]
        for (identity, userID) in userIDByIdentity where channel == .everything && duckedSpeakers.contains(userID) {
            identitiesBySpeaker[userID, default: []].insert(identity)
        }
        return NativeCallOriginalDucking(floor: NativeCallListening.originalGain, identitiesBySpeaker: identitiesBySpeaker)
    }
}

/// The transport's ducking order (Brief 0066): which raw microphones are
/// attenuated, to what gain, keyed by the speaker MXID so every device of
/// a speaker drops together.
nonisolated struct NativeCallOriginalDucking: Equatable {
    /// Playout gain for a covered microphone.
    let floor: Float
    /// Speaker MXID → the identities (devices) whose microphones drop.
    let identitiesBySpeaker: [String: Set<String>]

    static let none = NativeCallOriginalDucking(floor: 1, identitiesBySpeaker: [:])

    /// Identity → playout gain for its raw microphone. Identities not in
    /// the order are unity (and the controller resets them on the way out).
    var gains: [String: Float] {
        var gains: [String: Float] = [:]
        for identities in identitiesBySpeaker.values {
            for identity in identities {
                gains[identity] = floor
            }
        }
        return gains
    }
}

nonisolated struct NativeCallDerivedState: Equatable {
    let participants: [NativeCallParticipant]
    let listening: NativeCallListeningState
    let subscriptionPlan: NativeCallSubscriptionPlan
    /// A HUMAN peer whose media this device is allowed to play is present.
    /// This is what answers a DM ring — an agent attaching for translation
    /// or recording must never do that, and the previous imperative check
    /// had no notion of roles, so an attached agent answered the call two
    /// seconds after it started ringing and cancelled the no-answer
    /// timeout on the callee's behalf.
    let hasAuthorizedHumanRemote: Bool
    /// A human peer is in the call at all — by membership OR by media.
    /// The DM hang-up rule reads this: an agent that stays behind must not
    /// keep the user in an empty "conference".
    let hasHumanRemote: Bool
    /// The agent-shaped twins, for the one call where the agent IS the
    /// peer: a DM with one's own assistant (operator, 2026-09-11 — it rang
    /// until the no-answer timeout although the agent had joined). Read
    /// only when the configuration says the callee is an agent; a
    /// translating agent in a human's DM never answers through these.
    /// Transport presence, not membership: the agent's `m.call.member`
    /// lands a second before its media can flow.
    let hasAuthorizedAgentRemote: Bool
    let hasAgentRemote: Bool
    /// A human is on the SFU at all, whatever their media and whether or not
    /// their membership has synced. Only the wait for anybody to be in a
    /// joined call reads this: a caller on a cold launch's slow sync may be
    /// muted with the camera off. The leave rules keep `hasHumanRemote`,
    /// which leaves out an SFU connection whose owner has left the session.
    let hasHumanOnTransport: Bool
    /// Whether anybody currently publishes camera video. This drives live
    /// presentation and audio-session mode; call intent remains per-member.
    let hasActiveVideo: Bool
    /// Slice 5 — what a video call renders, in tile order (us last, so the
    /// local preview sits on top of the remote picture). Derived here rather
    /// than assembled in the view so the "which stream belongs to whom"
    /// decision is testable and has ONE owner.
    let videoTiles: [NativeCallVideoTile]
    /// The agents' published state documents, verbatim, by identity. An
    /// attach, a detach and every applied reconfigure rewrite this — which is
    /// exactly when the Agent Center's REST snapshot goes stale. Attributes
    /// are the canonical live register (ADR-0071 D8); the panel's controls,
    /// catalogs and candidates still come from REST, so this says WHEN to
    /// re-read, never WHAT to show.
    let agentStateDocuments: [String: String]
    /// What the call's agents claim and audibly do right now, in one value
    /// (see `NativeCallAgentClaims`).
    let agentClaims: NativeCallAgentClaims
    /// The live link-quality ladder: the meta line's signal bars, and
    /// G10's "Poor connection" note when it degrades.
    let connectionQuality: NativeCallConnectionQuality
}

/// What the call's agents claim (their `spiral.agent.state` documents)
/// and audibly do (the transport's speaking signal), by agent MXID. One
/// value, so a claim change and a speaking change cannot race each other
/// out of order.
/// Every live fact the call knows about its agents, keyed by agent MXID —
/// the document each agent publishes (reaches every device) plus the
/// transport's speaking signal. THE live register: the presentation derive
/// reads agents from here and from the roster, never from REST.
nonisolated struct NativeCallAgentClaims: Equatable {
    /// The document as read, per agent. No entry = no valid document.
    var documents: [String: SpiralAgentStateReader.AgentClaim] = [:]
    /// Agents audibly producing sound right now. The block's wave is
    /// `claimed ∧ speaking` — the `SpiralAgentDock` rule
    /// (`src/spiral/voiceLevel.ts`): the runtime squelches
    /// between-utterance silence, so the speaking envelope IS "the
    /// interpreter airs now", in both translation styles. Never a timer.
    var speaking: Set<String> = []
}

nonisolated enum NativeCallStateDerivation {
    /// The whole derived state, in four named passes. Each pass is a pure
    /// function of the inputs plus the previous pass's result, so a reader
    /// can follow one concern at a time and the compiler keeps them honest.
    static func derive(_ inputs: NativeCallDerivationInputs) -> NativeCallDerivedState {
        let membershipsByIdentity = Dictionary(inputs.memberships.map { ($0.identity, $0) }) { _, latest in latest }
        let ownUserID = membershipsByIdentity[inputs.ownIdentity]?.userID
            ?? userID(fromIdentity: inputs.ownIdentity)

        // WHO IS AN AGENT, resolved once for every pass below. The room's
        // service-member list is a server-side hint that can be missing or
        // late; an identity that publishes a valid `spiral.agent.state`
        // document is declaring itself, and that declaration reaches every
        // device with the media. Trusting only the hint rendered agents as
        // people on a real device: a video tile in the grid, a group layout
        // for a 1:1 call, and no capsule.
        let agentUserIDs = agentUserIDs(inputs, membershipsByIdentity: membershipsByIdentity, ownUserID: ownUserID)

        let translation = deriveTranslation(inputs)
        let agentClaims = deriveAgentClaims(inputs, membershipsByIdentity: membershipsByIdentity)
        let listening = deriveListening(inputs,
                                        translation: translation,
                                        claims: agentClaims,
                                        membershipsByIdentity: membershipsByIdentity,
                                        agentUserIDs: agentUserIDs,
                                        ownUserID: ownUserID)
        let authorized = deriveAuthorized(inputs, membershipsByIdentity: membershipsByIdentity)
        let plan = deriveSubscriptionPlan(inputs,
                                          authorized: authorized,
                                          listening: listening,
                                          translation: translation,
                                          membershipsByIdentity: membershipsByIdentity,
                                          ownUserID: ownUserID)
        let participants = deriveRoster(inputs,
                                        membershipsByIdentity: membershipsByIdentity,
                                        agentUserIDs: agentUserIDs,
                                        translatedSpeakers: Set(listening.translatedSpeakers.keys))
        // Presence reads who is AUTHORIZED, not who is subscribed: a call we
        // hold still has its people in it.
        let presence = derivePresence(inputs,
                                      membershipsByIdentity: membershipsByIdentity,
                                      agentUserIDs: agentUserIDs,
                                      authorized: authorized,
                                      ownUserID: ownUserID)
        let videoTiles = deriveVideoTiles(inputs, participants: participants)
        let agentStateDocuments = inputs.transportParticipants.reduce(into: [String: String]()) { documents, participant in
            documents[participant.identity] = SpiralAgentStateReader.agentDocument(attributes: participant.attributes)
        }

        return NativeCallDerivedState(participants: participants,
                                      listening: listening,
                                      subscriptionPlan: plan,
                                      hasAuthorizedHumanRemote: presence.hasAuthorizedHumanRemote,
                                      hasHumanRemote: presence.hasHumanRemote,
                                      hasAuthorizedAgentRemote: presence.hasAuthorizedAgentRemote,
                                      hasAgentRemote: presence.hasAgentRemote,
                                      hasHumanOnTransport: presence.hasHumanOnTransport,
                                      hasActiveVideo: participants.contains(where: \.isVideoEnabled),
                                      videoTiles: videoTiles,
                                      agentStateDocuments: agentStateDocuments,
                                      agentClaims: agentClaims,
                                      connectionQuality: inputs.localConnectionQuality)
    }

    // MARK: - Passes

    /// The union of the room's service members, every member the call
    /// scope's agent rule names (`NativeCallConfiguration.isAgent`) and
    /// every identity that is an agent on the SFU or publishes an agent
    /// document. Returned as USER ids, the key the roster and the presence
    /// rules work in. The rule matters where the hints are silent: the DM
    /// with one's own assistant (backend `02043c5e`), whose participant can
    /// arrive with a standard kind before its document — it rang out there.
    private static func agentUserIDs(_ inputs: NativeCallDerivationInputs,
                                     membershipsByIdentity: [String: MatrixRTCParticipant],
                                     ownUserID: String) -> Set<String> {
        var agents = inputs.serviceMembers
        for membership in inputs.memberships where NativeCallConfiguration.isAgent(membership.userID, ownUserID: ownUserID) {
            agents.insert(membership.userID)
        }
        for participant in inputs.transportParticipants {
            let participantUserID = membershipsByIdentity[participant.identity]?.userID
                ?? userID(fromIdentity: participant.identity)
            if participant.isAgent
                || SpiralAgentStateReader.agentDocument(attributes: participant.attributes) != nil
                || NativeCallConfiguration.isAgent(participantUserID, ownUserID: ownUserID) {
                agents.insert(participantUserID)
            }
        }
        return agents
    }

    /// What the call's agents actually produce right now.
    ///
    /// The agent's `spiral.agent.state` document (ADR-0071 D8, the same
    /// contract the Element Call fork reads) is the canonical live
    /// translation truth — every device sees it, it changes with every
    /// applied reconfigure, and it leaves with the agent. It WINS over the
    /// track snapshot per publishing agent: a publication the document does
    /// not claim is STALE (the lane ended, the SFU has not torn the track
    /// down yet). Staleness is resolved ONCE, here, and every later pass
    /// reads the survivors — applying the document to the picker alone left
    /// a disabled lane subscribed and audible over the raw microphone.
    private static func deriveTranslation(_ inputs: NativeCallDerivationInputs) -> Translation {
        var intent = [String: [String]]()
        for participant in inputs.transportParticipants {
            if let languages = SpiralAgentStateReader.translationLanguages(attributes: participant.attributes) {
                intent[participant.identity] = languages
            }
        }
        let audioTracks = inputs.transportTracks.filter { $0.kind == .audio }
        let staleTracks = Set(audioTracks.filter { track in
            guard let languages = intent[track.identity],
                  let language = NativeCallListening.translationLanguage(trackName: track.name) else { return false }
            return !languages.contains(language)
        }.map { NativeCallTrackKey(identity: $0.identity, trackID: $0.trackID, name: $0.name) })
        // Both sides are already base tags (the reader and the track-name
        // parser normalise on the way in), so this is a like-for-like
        // comparison — an `en-US` claim no longer mutes an `lt:en:` lane.
        let liveTracks = audioTracks.filter { track in
            !staleTracks.contains(.init(identity: track.identity, trackID: track.trackID, name: track.name))
        }
        // A publisher with no valid document keeps its tracks as the truth: a
        // human, or an agent whose document did not land. The runtime
        // publishes it through LiveKit's server API before any track, but
        // fail-soft (`publish_agent_state_attributes`: no API key, or a
        // failed call, skips it and the audio goes on), so an agent's lanes
        // can be live with no document.
        let undocumentedTrackNames = liveTracks
            .filter { intent[$0.identity] == nil }
            .map(\.name)
        let produced = Set(intent.values.joined())
            .union(NativeCallListening.producedLanguages(trackNames: undocumentedTrackNames))

        return Translation(staleTracks: staleTracks,
                           liveTracks: liveTracks,
                           producedLanguages: produced.sorted(),
                           claimedLanguagesByIdentity: intent)
    }

    /// Each agent's translation claim plus whether it is speaking, for the
    /// agent block.
    ///
    /// The document is the canonical claim (ADR-0071 D8) and the transport's
    /// speaking signal is the proof of air time — the same pair the Element
    /// Call fork's `SpiralAgentDock` reads. The first Phase 1 cut intersected
    /// the claim with live `lt:` lanes instead, and the two-simulator gate
    /// falsified it: the consecutive style airs on shared `agent-<lang>`
    /// tracks, so the wave never lit while the translation was audibly
    /// playing. Lane names are a style-dependent detail; speaking is not.
    /// The claim is reported sorted so the block reads the same way twice.
    private static func deriveAgentClaims(_ inputs: NativeCallDerivationInputs,
                                          membershipsByIdentity: [String: MatrixRTCParticipant]) -> NativeCallAgentClaims {
        var state = NativeCallAgentClaims()
        for participant in inputs.transportParticipants {
            guard let claim = SpiralAgentStateReader.agentClaim(attributes: participant.attributes) else {
                // No agent document: not an agent, so it has no block.
                continue
            }
            let userID = membershipsByIdentity[participant.identity]?.userID
                ?? userID(fromIdentity: participant.identity)
            state.documents[userID] = claim
            if participant.isSpeaking {
                state.speaking.insert(userID)
            }
        }
        return state
    }

    private static func deriveListening(_ inputs: NativeCallDerivationInputs,
                                        translation: Translation,
                                        claims: NativeCallAgentClaims,
                                        membershipsByIdentity: [String: MatrixRTCParticipant],
                                        agentUserIDs: Set<String>,
                                        ownUserID: String) -> NativeCallListeningState {
        var listening = NativeCallListeningState()
        listening.producedLanguages = translation.producedLanguages
        listening.channel = NativeCallListening.channel(choice: inputs.listeningChoice,
                                                        producedLanguages: translation.producedLanguages)
        guard listening.channel == .everything else { return listening }

        // Who this device hears in translation is what the documents CLAIM,
        // not which lanes flow: the claim reaches every device the moment
        // the agent is configured; lanes appear on the speaker's first
        // voiced frame. Only remote humans can be covered — an `anyone`
        // booth names the agents too, and the local user is nobody's remote
        // microphone.
        let remoteHumans = Set(inputs.memberships.map(\.userID)
            + inputs.transportParticipants.map { membershipsByIdentity[$0.identity]?.userID ?? userID(fromIdentity: $0.identity) })
            .subtracting(agentUserIDs)
            .subtracting([ownUserID])
        listening.translatedSpeakers = NativeCallListening.translatedSpeakers(speakers: remoteHumans,
                                                                              claims: claims.documents.values)

        // Fail audible: a covered speaker who is on the air with no lane of
        // theirs airing, though one has aired on this device before (the
        // memory still names it — see `lanesSeenLive` for what it forgets).
        // They are heard in full and the agent's block says its translation
        // faltered. A lane that has never aired is simply not there yet:
        // the claim stands, the original stays quiet, the first sentence
        // lands over it.
        let airingSpeakers = Set(airingLanes(translation.liveTracks).map(\.speaker))
        let faltered = inputs.lanesSeenLive.filter { lane in
            listening.translatedSpeakers[lane.speaker] != nil && !airingSpeakers.contains(lane.speaker)
        }
        listening.falteredSpeakers = Set(faltered.map(\.speaker))
        listening.falteredAgents = Set(faltered.map { lane in
            membershipsByIdentity[lane.agentIdentity]?.userID ?? userID(fromIdentity: lane.agentIdentity)
        })
        return listening
    }

    /// Simultaneous lanes this device is receiving right now: subscribed,
    /// unmuted, claimed by their agent's document.
    private static func airingLanes(_ liveTracks: [NativeCallTransportTrack]) -> Set<NativeCallLaneKey> {
        Set(liveTracks
            .filter { $0.kind == .audio && $0.isSubscribed && !$0.isMuted }
            .compactMap { track in
                guard let language = NativeCallListening.translationLanguage(trackName: track.name),
                      let speaker = NativeCallListening.translationSpeaker(trackName: track.name) else { return nil }
                return NativeCallLaneKey(agentIdentity: track.identity, language: language, speaker: speaker)
            })
    }

    /// The lane memory the session carries between input writes (see
    /// `NativeCallDerivationInputs.lanesSeenLive`). Pure, like the
    /// derivation — the session calls it on the pending inputs before
    /// deriving them.
    ///
    /// A lane joins once it airs with its agent audibly speaking (the
    /// runtime publishes a lane unmuted for a beat before it mutes it, so
    /// "unmuted" alone is not "aired"). A lane is forgotten when its agent
    /// leaves the transport, when its language leaves the agent's claim,
    /// when this device unsubscribes it (the listener chose the original
    /// voices, or the call is held — not a failure), and when it stops
    /// airing while its speaker is SILENT: the runtime closes a lane that
    /// idles for ten minutes and reopens it on the next voiced frame, and
    /// that must not read as a falter or the first sentence after a long
    /// pause would pump the original. What is left is the one case that is
    /// a failure: the lane stopped while the speaker is talking.
    static func lanesSeenLive(previous: Set<NativeCallLaneKey>,
                              inputs: NativeCallDerivationInputs) -> Set<NativeCallLaneKey> {
        let participantsByIdentity = Dictionary(inputs.transportParticipants.map { ($0.identity, $0) }) { _, latest in latest }
        let translation = deriveTranslation(inputs)
        let airing = airingLanes(translation.liveTracks)
        let speakingAgents = Set(inputs.transportParticipants.filter(\.isSpeaking).map(\.identity))
        let speakingUsers = Set(inputs.transportParticipants.filter(\.isSpeaking).map { userID(fromIdentity: $0.identity) })
        let unsubscribed = Set(inputs.transportTracks
            .filter { !$0.isSubscribed }
            .map { NativeCallTrackKey(identity: $0.identity, trackID: $0.trackID, name: $0.name) })
        let claimedLanguages = translation.claimedLanguagesByIdentity

        var memory = previous.filter { lane in
            guard participantsByIdentity[lane.agentIdentity] != nil,
                  claimedLanguages[lane.agentIdentity]?.contains(lane.language) ?? true else { return false }
            let trackName = "\(NativeCallListening.translationTrackPrefix)\(lane.language):\(lane.speaker)"
            let isUnsubscribedHere = unsubscribed.contains { $0.identity == lane.agentIdentity && $0.name == trackName }
            guard !isUnsubscribedHere else { return false }
            return airing.contains(lane) || speakingUsers.contains(lane.speaker)
        }
        memory.formUnion(airing.filter { speakingAgents.contains($0.agentIdentity) })
        return memory
    }

    private static func deriveAuthorized(_ inputs: NativeCallDerivationInputs,
                                         membershipsByIdentity: [String: MatrixRTCParticipant]) -> Set<String> {
        Set(inputs.transportParticipants
            .map(\.identity)
            .filter { identity in
                isMediaAuthorized(identity: identity,
                                  membershipsByIdentity: membershipsByIdentity,
                                  identitiesWithKeys: inputs.identitiesWithKeys,
                                  isRoomEncrypted: inputs.isRoomEncrypted)
            })
    }

    private static func deriveSubscriptionPlan(_ inputs: NativeCallDerivationInputs,
                                               authorized allAuthorized: Set<String>,
                                               listening: NativeCallListeningState,
                                               translation: Translation,
                                               membershipsByIdentity: [String: MatrixRTCParticipant],
                                               ownUserID: String) -> NativeCallSubscriptionPlan {
        // Brief 0068 Slice 2: held behind another Spiral call, nothing of
        // this one may play — the two share the one audio engine. Video too:
        // bandwidth for nothing. The resume re-derives.
        let authorized: Set<String> = inputs.holdSilencesMedia ? [] : allAuthorized
        // Duplicate-tolerant: this is a pure function over externally
        // supplied arrays, and `uniqueKeysWithValues` would TRAP on a
        // repeated identity rather than degrade.
        let userIDByIdentity = Dictionary(inputs.transportParticipants.map { participant in
            (participant.identity,
             membershipsByIdentity[participant.identity]?.userID ?? userID(fromIdentity: participant.identity))
        }) { _, latest in latest }

        // Slice 5: every authorized peer that publishes a camera is on
        // screen in a 1:1 and in a small group, so visibility is simply
        // authorization. A larger group would narrow this to the tiles the
        // layout actually shows — the plan is the place that decides.
        let visibleVideoIdentities = Set(inputs.transportTracks
            .filter { $0.kind == .video && authorized.contains($0.identity) }
            .map(\.identity))

        let publications = Set(inputs.transportTracks.map {
            NativeCallTrackKey(identity: $0.identity, trackID: $0.trackID, name: $0.name)
        })

        return NativeCallSubscriptionPlan(authorizedIdentities: authorized,
                                          publications: publications,
                                          channel: listening.channel,
                                          staleTranslationTracks: translation.staleTracks,
                                          duckedSpeakers: Set(listening.translatedSpeakers.keys).subtracting(listening.falteredSpeakers),
                                          visibleVideoIdentities: visibleVideoIdentities,
                                          userIDByIdentity: userIDByIdentity,
                                          ownUserID: ownUserID)
    }

    private static func deriveRoster(_ inputs: NativeCallDerivationInputs,
                                     membershipsByIdentity: [String: MatrixRTCParticipant],
                                     agentUserIDs: Set<String>,
                                     translatedSpeakers: Set<String>) -> [NativeCallParticipant] {
        let localIdentity = inputs.transportLocalIdentity ?? inputs.ownIdentity
        let localUserID = membershipsByIdentity[localIdentity]?.userID ?? userID(fromIdentity: localIdentity)
        var participants = [NativeCallParticipant(id: localIdentity,
                                                  userID: localUserID,
                                                  role: .human,
                                                  mediaState: .connected,
                                                  isSpeaking: inputs.isLocalSpeaking,
                                                  isAudioEnabled: inputs.isMicrophoneEnabled,
                                                  isLocal: true,
                                                  isVideoEnabled: inputs.isCameraEnabled,
                                                  isOnHold: inputs.isLocalOnHold)]

        let remoteByIdentity = Dictionary(inputs.transportParticipants.map { ($0.identity, $0) }) { _, latest in latest }
        let activeVideoIdentities = Set(inputs.transportTracks
            .filter { $0.kind == .video && !$0.isMuted }
            .map(\.identity))
        var membershipsByUserID = Dictionary(grouping: inputs.memberships.filter { membership in
            membership.userID != localUserID
        }, by: \.userID)

        // LiveKit can beat MatrixRTC membership to the client. Only its
        // authoritative agent kind is safe to surface before authorization.
        for media in inputs.transportParticipants where media.isAgent {
            let userID = membershipsByIdentity[media.identity]?.userID ?? userID(fromIdentity: media.identity)
            guard userID != localUserID, membershipsByUserID[userID] == nil else { continue }
            membershipsByUserID[userID] = [.init(userID: userID, deviceID: "", identity: media.identity)]
        }

        participants += membershipsByUserID.map { userID, memberships in
            let ordered = memberships.sorted { $0.identity < $1.identity }
            let representative = ordered.first { activeVideoIdentities.contains($0.identity) }
                ?? ordered.first { remoteByIdentity[$0.identity]?.isSpeaking == true }
                ?? ordered.first { remoteByIdentity[$0.identity] != nil }
                ?? ordered[0]
            let media = ordered.compactMap { remoteByIdentity[$0.identity] }
            let hasHealthyMedia = ordered.contains { membership in
                remoteByIdentity[membership.identity] != nil
                    && (!inputs.isRoomEncrypted
                        || inputs.identitiesWithKeys.contains(membership.identity)
                        && !inputs.identitiesWithEncryptionFailure.contains(membership.identity))
            }
            let mediaState: NativeCallParticipant.MediaState = if media.isEmpty {
                .connecting
            } else if !hasHealthyMedia {
                .waitingForKeys
            } else {
                .connected
            }

            // A held peer (Brief 0068): every device of theirs announced a
            // hold — silence is not speech, a dark camera is not video.
            let isOnHold = !media.isEmpty && media.allSatisfy(\.isOnHold)
            let isReconnecting = !media.isEmpty && media.allSatisfy { $0.connectionQuality == .lost }
            return NativeCallParticipant(id: representative.identity,
                                         userID: userID,
                                         role: agentUserIDs.contains(userID) ? .agent : .human,
                                         mediaState: mediaState,
                                         isSpeaking: !isOnHold && media.contains(where: \.isSpeaking),
                                         isAudioEnabled: media.contains(where: \.isAudioEnabled),
                                         isLocal: false,
                                         isTranslated: translatedSpeakers.contains(userID),
                                         isVideoEnabled: !isOnHold
                                             && (media.contains(where: \.isCameraEnabled)
                                                 || ordered.contains { activeVideoIdentities.contains($0.identity) }),
                                         isOnHold: isOnHold,
                                         isReconnecting: isReconnecting)
        }.sorted { $0.userID < $1.userID }
        return participants
    }

    /// Role-aware presence: an agent is never a peer. This is what answers a
    /// DM ring and what ends the call when the last human leaves — an
    /// attached agent used to do both, because the imperative checks this
    /// replaced counted any remote identity.
    private static func derivePresence(_ inputs: NativeCallDerivationInputs,
                                       membershipsByIdentity: [String: MatrixRTCParticipant],
                                       agentUserIDs: Set<String>,
                                       authorized: Set<String>,
                                       ownUserID: String) -> Presence {
        let humanMembershipIdentities = inputs.memberships
            .filter { $0.userID != ownUserID && !agentUserIDs.contains($0.userID) }
            .map(\.identity)
        let humanTransportIdentities = inputs.transportParticipants
            .filter { participant in
                let participantUserID = membershipsByIdentity[participant.identity]?.userID
                    ?? userID(fromIdentity: participant.identity)
                guard participantUserID != ownUserID, !agentUserIDs.contains(participantUserID) else { return false }
                guard let membership = membershipsByIdentity[participant.identity] else {
                    // Not in MatrixRTC yet: LiveKit's participant kind still
                    // keeps an agent from answering a ring. A lingering SFU
                    // connection whose owner already LEFT the Matrix session
                    // must not hold the call open until the server reaps it.
                    let isMediaActive = participant.isAudioEnabled || participant.isCameraEnabled || participant.isSpeaking
                    return !participant.isAgent && isMediaActive
                }
                return !agentUserIDs.contains(membership.userID)
            }
            .map(\.identity)

        let agentTransportIdentities = inputs.transportParticipants
            .filter { participant in
                let participantUserID = membershipsByIdentity[participant.identity]?.userID
                    ?? userID(fromIdentity: participant.identity)
                return participantUserID != ownUserID
                    && (participant.isAgent || agentUserIDs.contains(participantUserID))
            }
            .map(\.identity)

        let hasHumanOnTransport = inputs.transportParticipants.contains { participant in
            let participantUserID = membershipsByIdentity[participant.identity]?.userID
                ?? userID(fromIdentity: participant.identity)
            return participantUserID != ownUserID && !agentUserIDs.contains(participantUserID) && !participant.isAgent
        }

        return Presence(hasAuthorizedHumanRemote: humanTransportIdentities.contains { authorized.contains($0) },
                        hasHumanRemote: !humanMembershipIdentities.isEmpty || !humanTransportIdentities.isEmpty,
                        hasAuthorizedAgentRemote: agentTransportIdentities.contains { authorized.contains($0) },
                        hasAgentRemote: !agentTransportIdentities.isEmpty,
                        hasHumanOnTransport: hasHumanOnTransport)
    }

    /// Pairs each participant with the stream to draw for them.
    ///
    /// A participant whose camera is off still gets a tile — the call shows
    /// who is there, and a muted camera is a state, not an absence. Remote
    /// tiles come first so the local preview can be laid on top.
    private static func deriveVideoTiles(_ inputs: NativeCallDerivationInputs,
                                         participants: [NativeCallParticipant]) -> [NativeCallVideoTile] {
        let videoTracksByIdentity = Dictionary(grouping: inputs.transportTracks.filter {
            $0.kind == .video && $0.isSubscribed && !$0.isMuted
        }, by: \.identity)

        return participants
            // G1 — an agent is never a tile. It is disclosed by the capsule
            // and the Agent Center; a tile would make it a peer on screen.
            .filter { $0.role != .agent }
            .sorted { !$0.isLocal && $1.isLocal }
            .map { participant in
                guard participant.isVideoEnabled else {
                    return NativeCallVideoTile(participant: participant, source: nil)
                }
                if participant.isLocal {
                    return NativeCallVideoTile(participant: participant,
                                               source: .init(identity: participant.id, trackID: "", isLocal: true))
                }
                let tracks = videoTracksByIdentity[participant.id] ?? []
                guard let track = tracks.first(where: { $0.source == .screenShareVideo })
                    ?? tracks.first(where: { $0.source == .camera })
                    ?? tracks.first else {
                    // Camera reported on, publication not seen yet: render
                    // the placeholder rather than an empty frame.
                    return NativeCallVideoTile(participant: participant, source: nil)
                }
                return NativeCallVideoTile(participant: participant,
                                           source: .init(identity: track.identity,
                                                         trackID: track.trackID,
                                                         isLocal: false,
                                                         source: track.source),
                                           isStreamPaused: track.isStreamPaused)
            }
    }

    private struct Translation {
        let staleTracks: Set<NativeCallTrackKey>
        let liveTracks: [NativeCallTransportTrack]
        let producedLanguages: [String]
        /// Per documented agent identity, the languages it claims to
        /// produce right now. Absent for a participant with no document.
        let claimedLanguagesByIdentity: [String: [String]]
    }

    private struct Presence {
        let hasAuthorizedHumanRemote: Bool
        let hasHumanRemote: Bool
        let hasAuthorizedAgentRemote: Bool
        let hasAgentRemote: Bool
        let hasHumanOnTransport: Bool
    }

    /// Membership + (for E2EE rooms) an arrived media key.
    static func isMediaAuthorized(identity: String,
                                  membershipsByIdentity: [String: MatrixRTCParticipant],
                                  identitiesWithKeys: Set<String>,
                                  isRoomEncrypted: Bool) -> Bool {
        guard membershipsByIdentity[identity] != nil else { return false }
        return !isRoomEncrypted || identitiesWithKeys.contains(identity)
    }

    /// Identity is `<mxid>:<device>`; an MXID contains exactly one colon.
    static func userID(fromIdentity identity: String) -> String {
        var colons = identity.indices.filter { identity[$0] == ":" }.makeIterator()
        _ = colons.next()
        guard let deviceColon = colons.next() else { return identity }
        return String(identity[..<deviceColon])
    }
}
