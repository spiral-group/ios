//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Spiral
import Testing

// AGENT-PLATFORM (Brief 0063, native call UI Phase 1): the view state's
// derived accessors — G1 (agents are not participants), G2 (REC lives in
// the header) and G4 (humans and agents counted separately).

struct NativeCallScreenViewStateTests {
    private let agentMxid = "@assistant-alice:spiral.md"

    private func participant(_ userID: String, role: NativeCallParticipant.Role) -> NativeCallParticipant {
        NativeCallParticipant(id: "\(userID):DEVICE",
                              userID: userID,
                              role: role,
                              mediaState: .connected,
                              isSpeaking: false,
                              isAudioEnabled: true,
                              isLocal: false)
    }

    private func state(participants: [NativeCallParticipant],
                       sessions: [NativeAgentCenterSession] = [],
                       claimed: [String: [String]] = [:],
                       speaking: Set<String> = []) -> NativeCallScreenViewState {
        var state = NativeCallScreenViewState(roomName: "Localization sync")
        state.callState = .connected
        state.participants = participants
        state.agentClaims.documents = claimed.mapValues { SpiralAgentStateReader.AgentClaim.make(languages: $0) }
        state.agentClaims.speaking = speaking
        state.agentCenter = NativeAgentCenterSnapshot(isAvailable: true, isLoading: false, sessions: sessions)
        return state
    }

    private func session(recording: Bool) -> NativeAgentCenterSession {
        NativeAgentCenterSession(sessionID: "session-1",
                                 agentMxid: agentMxid,
                                 canControl: true,
                                 isEnding: false,
                                 recording: .init(isEnabled: recording, revision: 1, delivery: .notArmed, isStopped: false),
                                 summary: .init(isEnabled: false, revision: 1, delivery: .notArmed, isStopped: false),
                                 translation: .unknown,
                                 conversation: .unknown)
    }

    // MARK: - The assistant's own page (question 383)

    /// The page is for a call with one's own assistant and nobody else: from the ring, before anyone has joined, and
    /// back to the call's usual layout the moment a person joins, so their face and camera show.
    @Test
    func theAssistantsPageIsOnlyForACallWithNobodyElse() {
        let me = NativeCallParticipant(id: "@alice:spiral.md:ALICE", userID: "@alice:spiral.md", role: .human,
                                       mediaState: .connected, isSpeaking: false, isAudioEnabled: true, isLocal: true)
        let assistant = participant(agentMxid, role: .agent)
        let bob = participant("@bob:spiral.md", role: .human)

        var ringing = state(participants: [])
        ringing.scope = .assistant
        #expect(ringing.isAssistantPage, "from the ring: no jump when the assistant joins")

        var alone = state(participants: [me, assistant])
        alone.scope = .assistant
        #expect(alone.isAssistantPage)

        var joined = state(participants: [me, assistant, bob])
        joined.scope = .assistant
        #expect(!joined.isAssistantPage, "a person joined: the usual layout, their camera shows")

        var direct = state(participants: [me, bob])
        direct.scope = .direct
        #expect(!direct.isAssistantPage)

        var group = state(participants: [me, assistant])
        group.scope = .group
        #expect(!group.isAssistantPage)

        #expect(alone.stagePeer?.userID == agentMxid, "the page centres on the assistant")
        #expect(joined.stagePeer?.userID == "@bob:spiral.md", "once the page ends, the person takes the stage")
    }

    /// Question 400: the assistant's page takes its colour as the avatar shows it, from the ring (the DM's one hero) to
    /// the call (the agent); a person's call, a group and the page once a person joined keep their own field.
    @Test
    func theAssistantsPageTakesTheAssistantsColour() {
        let me = NativeCallParticipant(id: "@alice:spiral.md:ALICE", userID: "@alice:spiral.md", role: .human,
                                       mediaState: .connected, isSpeaking: false, isAudioEnabled: true, isLocal: true)
        let assistant = participant(agentMxid, role: .agent)
        let bob = participant("@bob:spiral.md", role: .human)

        var ringing = state(participants: [])
        ringing.scope = .assistant
        ringing.roomAvatar = .heroes([UserProfile(userID: agentMxid)])
        #expect(ringing.backdropContentID == agentMxid)
        #expect(NativeCallBackdrop.Fill(contentID: ringing.backdropContentID) == .agent(id: agentMxid))

        var alone = state(participants: [me, assistant])
        alone.scope = .assistant
        #expect(alone.backdropContentID == agentMxid)

        var joined = state(participants: [me, assistant, bob])
        joined.scope = .assistant
        joined.roomAvatar = .heroes([UserProfile(userID: agentMxid)])
        #expect(joined.backdropContentID == nil)

        var direct = state(participants: [me, bob])
        direct.scope = .direct
        direct.roomAvatar = .heroes([UserProfile(userID: "@bob:spiral.md")])
        #expect(direct.backdropContentID == nil)

        var group = state(participants: [me, assistant])
        group.scope = .group
        #expect(group.backdropContentID == nil)
    }

    // MARK: - Who is on the 1:1 stage (decision 342)

    private func tile(_ userID: String,
                      isLocal: Bool = false,
                      hasPicture: Bool = false,
                      mediaState: NativeCallParticipant.MediaState = .connected,
                      isCameraEnabled: Bool = false,
                      isMuted: Bool = false,
                      isOnHold: Bool = false,
                      isReconnecting: Bool = false) -> NativeCallVideoTile {
        var person = NativeCallParticipant(id: "\(userID):DEVICE",
                                           userID: userID,
                                           role: .human,
                                           mediaState: mediaState,
                                           isSpeaking: false,
                                           isAudioEnabled: !isMuted,
                                           isLocal: isLocal)
        person.isVideoEnabled = hasPicture || isCameraEnabled
        person.isOnHold = isOnHold
        person.isReconnecting = isReconnecting
        return NativeCallVideoTile(participant: person,
                                   source: hasPicture ? .init(identity: person.id, trackID: "", isLocal: isLocal) : nil)
    }

    @Test
    func aSettledPeerWithTheirCameraOffFillsTheStageWithOurVideoInTheCorner() {
        let local = tile("@alice:spiral.md", isLocal: true, hasPicture: true)
        let peer = tile("@bob:spiral.md")

        let stage = NativeCallVideoStage.tiles(remote: peer, local: local, isPeerSettled: true, isSelfVideoLarge: false)

        #expect(stage.large == peer)
        #expect(stage.small == local)
    }

    @Test
    func aPeerWithAPictureTakesTheStage() {
        let local = tile("@alice:spiral.md", isLocal: true, hasPicture: true)
        let peer = tile("@bob:spiral.md", hasPicture: true)

        let stage = NativeCallVideoStage.tiles(remote: peer, local: local, isPeerSettled: false, isSelfVideoLarge: false)

        #expect(stage.large == peer)
        #expect(stage.small == local)
    }

    @Test(arguments: [true, false])
    func theManualSwapPutsUsOnTheStage(peerHasPicture: Bool) {
        let local = tile("@alice:spiral.md", isLocal: true, hasPicture: true)
        let peer = tile("@bob:spiral.md", hasPicture: peerHasPicture)

        let stage = NativeCallVideoStage.tiles(remote: peer, local: local, isPeerSettled: true, isSelfVideoLarge: true)

        #expect(stage.large == local)
        #expect(stage.small == peer)
    }

    @Test
    func ourCameraKeepsTheStageUntilThePeerAnswers() {
        let local = tile("@alice:spiral.md", isLocal: true, hasPicture: true)

        let stage = NativeCallVideoStage.tiles(remote: nil, local: local, isPeerSettled: false, isSelfVideoLarge: false)

        #expect(stage.large == local)
        #expect(stage.small == nil)
    }

    @Test
    func ourCameraKeepsTheStageUntilThePeerSettles() {
        let local = tile("@alice:spiral.md", isLocal: true, hasPicture: true)
        let peer = tile("@bob:spiral.md")

        let stage = NativeCallVideoStage.tiles(remote: peer, local: local, isPeerSettled: false, isSelfVideoLarge: false)

        #expect(stage.large == local)
        #expect(stage.small == peer)
    }

    @Test
    func aCameraIsOffOnlyWhenThePeerIsConnectedWithNoCamera() {
        #expect(NativeCallVideoStage.isCameraOff(tile("@bob:spiral.md")))
        #expect(!NativeCallVideoStage.isCameraOff(tile("@bob:spiral.md", hasPicture: true)))
        #expect(!NativeCallVideoStage.isCameraOff(tile("@bob:spiral.md", mediaState: .connecting)))
        #expect(!NativeCallVideoStage.isCameraOff(tile("@bob:spiral.md", mediaState: .waitingForKeys)))
        #expect(!NativeCallVideoStage.isCameraOff(tile("@bob:spiral.md", isCameraEnabled: true)))
    }

    @Test
    func thePersonIsOnTheStageOnlyAsTheSettledPeerWithNoPicture() {
        let local = tile("@alice:spiral.md", isLocal: true, hasPicture: true)
        var state = NativeCallScreenViewState(roomName: "Bohdan")
        state.videoTiles = [tile("@bob:spiral.md"), local]

        #expect(!state.isPersonOnStage, "not settled: our camera has the stage")

        state.isPeerSettled = true
        #expect(state.isPersonOnStage)

        state.bindings.isSelfVideoLarge = true
        #expect(!state.isPersonOnStage, "swapped: our camera has the stage")

        state.bindings.isSelfVideoLarge = false
        state.videoTiles = [tile("@bob:spiral.md", hasPicture: true), local]
        #expect(!state.isPersonOnStage, "their picture has the stage")

        state.videoTiles = [local]
        #expect(!state.isPersonOnStage, "no peer")
    }

    // MARK: - What the stage says of the person

    @Test @MainActor
    func theStageSaysNothingOfAPersonWithNothingToSay() {
        let facts = tile("@bob:spiral.md").stageFacts

        #expect(!facts.isMuted)
        #expect(facts.state == nil)
    }

    @Test @MainActor
    func theStageShowsAMutedPeer() {
        let facts = tile("@bob:spiral.md", isMuted: true).stageFacts

        #expect(facts.isMuted)
        #expect(facts.state == nil)
    }

    @Test @MainActor
    func theStageSaysOnHoldRatherThanMuted() {
        let facts = tile("@bob:spiral.md", isMuted: true, isOnHold: true).stageFacts

        #expect(!facts.isMuted)
        #expect(facts.state == UntranslatedL10n.screenNativeCallStatusOnHold)
    }

    @Test @MainActor
    func theStageSaysReconnectingOverALostLink() {
        let facts = tile("@bob:spiral.md", isMuted: true, isReconnecting: true).stageFacts

        #expect(facts.isMuted)
        #expect(facts.state == UntranslatedL10n.screenNativeCallParticipantReconnecting)
    }

    @Test(arguments: [NativeCallParticipant.MediaState.connecting, .waitingForKeys]) @MainActor
    func theStageSaysReconnectingWhenMediaDrops(mediaState: NativeCallParticipant.MediaState) {
        let facts = tile("@bob:spiral.md", mediaState: mediaState, isMuted: true).stageFacts

        #expect(!facts.isMuted, "with its media gone, a peer only reads as muted")
        #expect(facts.state == UntranslatedL10n.screenNativeCallParticipantReconnecting)
    }

    // MARK: - G1: agents are not participants

    /// The roster renders humans only. An agent is disclosed by the header
    /// count, the block and the sheet — never as a peer with a badge.
    @Test
    func agentsAreFilteredOutOfTheRenderedRoster() {
        let state = state(participants: [participant("@alice:spiral.md", role: .human),
                                         participant("@bob:spiral.md", role: .human),
                                         participant(agentMxid, role: .agent)])

        #expect(state.humanParticipants.map(\.userID) == ["@alice:spiral.md", "@bob:spiral.md"])
        #expect(state.agentParticipants.map(\.userID) == [agentMxid])
        #expect(!state.humanParticipants.contains { $0.role == .agent })
    }

    /// The block exists only when an agent is actually in the call.
    @Test
    func theBlockIsAbsentWithoutAnAgent() {
        let state = state(participants: [participant("@alice:spiral.md", role: .human),
                                         participant("@bob:spiral.md", role: .human)])

        #expect(state.agentBlock == nil)
    }

    @Test
    func theBlockAppearsWhenAnAgentJoins() {
        let state = state(participants: [participant("@alice:spiral.md", role: .human),
                                         participant(agentMxid, role: .agent)],
                          claimed: [agentMxid: ["en"]],
                          speaking: [agentMxid])

        #expect(state.agentBlock?.event == .airing(.translation(languages: ["en"])))
    }

    @Test
    func theAgentBlockUsesTheMatrixProfileName() {
        var state = state(participants: [participant(agentMxid, role: .agent)])
        state.memberProfiles[agentMxid] = .init(displayName: "Marta's Assistant")

        #expect(state.agentBlock?.name == "Marta's Assistant")
    }

    // MARK: - G2: REC in the header

    @Test
    func recordingIsOffWhenNoAgentIsCapturing() {
        let state = state(participants: [participant(agentMxid, role: .agent)],
                          sessions: [session(recording: false)])

        #expect(state.isRecording == false)
    }

    /// The owner-scoped REST session is CONTROL, not a live fact: alone it
    /// lights nothing (it is what made the peer's phone disagree with the
    /// owner's). The owner's fresh write bridges until the document agrees.
    @Test
    func recordingIsOnWhileTheOwnersWriteIsFreshNotFromRestAlone() {
        var state = state(participants: [participant(agentMxid, role: .agent)],
                          sessions: [session(recording: true)])
        #expect(state.isRecording == false)

        state.agentCenter.pendingOwnerWrites = [agentMxid: [.init(fact: .recording(true), expiresAt: .distantFuture)]]
        #expect(state.isRecording)
    }

    /// A stopped recording still publishes what it captured, but it is no
    /// longer capturing — REC must go out (`isLive`, not `isEnabled`).
    @Test
    func aStoppedRecordingClearsTheHeaderBadge() {
        let stopped = NativeAgentCenterSession(sessionID: "session-1",
                                               agentMxid: agentMxid,
                                               canControl: true,
                                               isEnding: false,
                                               recording: .init(isEnabled: true, revision: 1, delivery: .pending, isStopped: true),
                                               summary: .init(isEnabled: false, revision: 1, delivery: .notArmed, isStopped: false),
                                               translation: .unknown,
                                               conversation: .unknown)
        let state = state(participants: [participant(agentMxid, role: .agent)], sessions: [stopped])

        #expect(state.isRecording == false)
    }

    /// The REST session list is owner-scoped — REC for everyone ELSE comes
    /// from the agents' shared state documents (found live: recording never
    /// lit on any device but the owner's).
    @Test
    func aForeignRecordingClaimLightsTheHeaderBadgeWithoutAnyRestSession() {
        var state = state(participants: [participant(agentMxid, role: .agent)])
        state.agentClaims.documents[agentMxid] = .make(recording: true)

        #expect(state.isRecording)
        // The sheet's row names the capturer.
        #expect(state.agents.foreignAgents.first?.shown.isRecording == true)
    }

    /// Both truths at once must not double-count or flicker: the union is
    /// still just "recording".
    @Test
    func ownRestTruthAndDocumentTruthUnionIntoOneRecordingFact() {
        var state = state(participants: [participant(agentMxid, role: .agent)],
                          sessions: [session(recording: true)])
        state.agentClaims.documents[agentMxid] = .make(recording: true)

        #expect(state.isRecording)
        // The controllable session's agent is OWN, not foreign.
        #expect(state.agents.foreignAgents.isEmpty)
    }

    // MARK: - The minimized bar's wave

    /// The bar's wave lights for ANY sound — a human peer or an agent —
    /// not only an airing interpreter (operator request 2026-08-21).
    @Test
    func theBarWaveLightsForAnySpeaker() {
        var state = state(participants: [participant("@bob:spiral.md", role: .human)])
        #expect(!state.isAnyoneSpeaking)

        state.participants = [NativeCallParticipant(id: "@bob:spiral.md:BOB",
                                                    userID: "@bob:spiral.md",
                                                    role: .human,
                                                    mediaState: .connected,
                                                    isSpeaking: true,
                                                    isAudioEnabled: true,
                                                    isLocal: false)]
        #expect(state.isAnyoneSpeaking)

        // An agent's sound counts too — a ROSTER agent: the speaking
        // signal is a media fact and cannot exist for one that is not here.
        state.participants = [participant("@agent:spiral.md", role: .agent)]
        state.agentClaims.speaking = ["@agent:spiral.md"]
        #expect(state.isAnyoneSpeaking)
    }

    // MARK: - G4: separate counts

    @Test
    func theStatusLineCountsHumansAndAgentsSeparately() {
        let state = state(participants: [participant("@alice:spiral.md", role: .human),
                                         participant("@bob:spiral.md", role: .human),
                                         participant("@carol:spiral.md", role: .human),
                                         participant("@dan:spiral.md", role: .human),
                                         participant(agentMxid, role: .agent),
                                         participant("@assistant-bob:spiral.md", role: .agent)])

        #expect(state.statusText == "4 people · 2 agents")
    }

    /// Singulars matter — `1 agent`, not `1 agents`.
    @Test
    func oneAgentIsSingular() {
        let state = state(participants: [participant("@alice:spiral.md", role: .human),
                                         participant("@bob:spiral.md", role: .human),
                                         participant(agentMxid, role: .agent)])

        #expect(state.statusText == "2 people · 1 agent")
    }

    /// No agent, no agent clause.
    @Test
    func peopleOnlyCallsSayNothingAboutAgents() {
        let state = state(participants: [participant("@alice:spiral.md", role: .human),
                                         participant("@bob:spiral.md", role: .human)])

        #expect(state.statusText == "2 people")
    }

    /// An agent must not make a one-person call look populated — but it must
    /// not go unmentioned either, because it can be recording.
    @Test
    func aloneWithAnAgentStillReadsAsWaiting() {
        let state = state(participants: [participant("@alice:spiral.md", role: .human),
                                         participant(agentMxid, role: .agent)])

        #expect(state.statusText == "\(UntranslatedL10n.screenNativeCallStatusWaiting) · 1 agent")
    }

    /// A call WITH one's own assistant is not "waiting for others" (operator
    /// report 2026-09-11): the line under its name is what the assistant is
    /// doing — the Agent Center's head line, idle here — never a head-count.
    @Test
    func aCallWithTheAssistantReadsItsStatusNotAHeadCount() {
        // Alice is the local person: a remote one would end the assistant's page (question 383).
        let alice = NativeCallParticipant(id: "@alice:spiral.md:ALICE", userID: "@alice:spiral.md", role: .human,
                                          mediaState: .connected, isSpeaking: false, isAudioEnabled: true, isLocal: true)
        var state = state(participants: [alice, participant(agentMxid, role: .agent)])
        state.scope = .assistant

        #expect(state.stagePeer?.userID == agentMxid, "the assistant is the face the 1:1 stage centres on")
        #expect(state.statusText == UntranslatedL10n.screenNativeCallAgentBlockIdle)
        #expect(!state.statusText.contains(UntranslatedL10n.screenNativeCallStatusWaiting))
    }

    @Test
    func aloneWithoutAnAgentIsPlainWaiting() {
        let state = state(participants: [participant("@alice:spiral.md", role: .human)])

        #expect(state.statusText == UntranslatedL10n.screenNativeCallStatusWaiting)
    }

    // MARK: - Phase 2 (G3): every agent in the call, own vs foreign

    private func session(mxid: String, canControl: Bool, languages: [String] = []) -> NativeAgentCenterSession {
        NativeAgentCenterSession(sessionID: "session-\(mxid)",
                                 agentMxid: mxid,
                                 canControl: canControl,
                                 isEnding: false,
                                 recording: .init(isEnabled: false, revision: 1, delivery: .notArmed, isStopped: false),
                                 summary: .init(isEnabled: false, revision: 1, delivery: .notArmed, isStopped: false),
                                 translation: languages.isEmpty
                                     ? .unknown
                                     : .init(effective: .init(source: "override", style: "consecutive", pocket: languages), revision: 1),
                                 conversation: .unknown)
    }

    /// An agent in the roster with no controllable session is someone
    /// else's: it renders read-only, from the roster and the document alone.
    /// The operator's stuck "Leaving…" (2026-09-03): the peer saw the agent
    /// leave, the owner's sheet kept the leaving row forever, because the
    /// REST snapshot had read the session mid-teardown and nothing reloaded
    /// again. The roster is the truth every device sees the instant the
    /// runtime disconnects — a LEAVING session whose agent is gone from it
    /// is gone from the sheet too, without waiting for REST.
    @Test
    func aLeavingSessionWhoseAgentLeftTheRosterIsGone() {
        var leaving = session(mxid: agentMxid, canControl: true)
        leaving = NativeAgentCenterSession(sessionID: leaving.sessionID,
                                           agentMxid: leaving.agentMxid,
                                           canControl: true,
                                           isEnding: true,
                                           recording: leaving.recording,
                                           summary: leaving.summary,
                                           translation: leaving.translation,
                                           conversation: leaving.conversation)

        // Still in the roster: still leaving — the row stays, honestly.
        let stillHere = state(participants: [participant("@alice:spiral.md", role: .human),
                                             participant(agentMxid, role: .agent)],
                              sessions: [leaving])
        #expect(stillHere.agents.ownAgents.map(\.mxid) == [agentMxid])
        // REST's `ending` inerts Remove; it does not SAY leaving — the
        // document and the owner's bounded write do.
        #expect(stillHere.agents.ownAgents.first?.control?.isEndRequested == true)

        // Gone from the roster: gone from the sheet, REST or no REST.
        let gone = state(participants: [participant("@alice:spiral.md", role: .human)],
                         sessions: [leaving])
        #expect(gone.agents.ownAgents.isEmpty)
        #expect(gone.agents.joining.isEmpty)
    }

    @Test
    func aRosterAgentWithoutAnOwnedSessionIsForeign() {
        let foreignMxid = "@assistant-marta:spiral.md"
        var state = state(participants: [participant("@alice:spiral.md", role: .human),
                                         participant(agentMxid, role: .agent),
                                         participant(foreignMxid, role: .agent)],
                          sessions: [session(mxid: agentMxid, canControl: true)],
                          claimed: [foreignMxid: ["en"]])
        state.memberProfiles = [foreignMxid: .init(displayName: "Marta's Assistant")]

        #expect(state.agents.ownAgents.map(\.mxid) == [agentMxid])
        #expect(state.agents.foreignAgents.map(\.mxid) == [foreignMxid])
        #expect(state.agents.foreignAgents.first?.displayName == "Marta's Assistant")
        #expect(state.agents.foreignAgents.first?.shown.languages == ["en"])
    }

    /// Without a profile name the cosmetic MXID fallback still names the
    /// agent rather than showing a raw identifier as the title.
    @Test
    func aForeignAgentFallsBackToTheCosmeticName() {
        let foreignMxid = "@assistant-marta:spiral.md"
        let state = state(participants: [participant(foreignMxid, role: .agent)])

        #expect(state.agents.foreignAgents.first?.displayName == "Assistant Marta")
    }

    /// The document is the ONLY live language source; a read-only REST
    /// session (should the platform ever return one) is control, never a
    /// status — the closeout rule, enforced by the presentation.
    @Test
    func foreignLanguagesComeFromTheDocumentNeverFromRest() {
        let foreignMxid = "@assistant-marta:spiral.md"
        let restOnly = state(participants: [participant(foreignMxid, role: .agent)],
                             sessions: [session(mxid: foreignMxid, canControl: false, languages: ["de"])])
        #expect(restOnly.agents.foreignAgents.first?.shown.languages == [])

        let documentToo = state(participants: [participant(foreignMxid, role: .agent)],
                                sessions: [session(mxid: foreignMxid, canControl: false, languages: ["de"])],
                                claimed: [foreignMxid: ["en"]])
        #expect(documentToo.agents.foreignAgents.first?.shown.languages == ["en"])
    }

    /// An agent the user controls never appears in the foreign list —
    /// one agent, one row.
    @Test
    func anOwnedAgentIsNeverListedAsForeign() {
        let state = state(participants: [participant(agentMxid, role: .agent)],
                          sessions: [session(mxid: agentMxid, canControl: true)])

        #expect(state.agents.ownAgents.map(\.mxid) == [agentMxid])
        #expect(state.agents.foreignAgents.isEmpty)
    }

    /// The call's identity comes from the SCOPE, never from the roster. The
    /// header shipped deriving it from `humanParticipants.first`, so a group
    /// call wore whichever member — or, before agents were classified, which
    /// AGENT — happened to sort first, under the group's own name.
    @Test
    func aGroupCallIsIdentifiedByTheRoomAndNotByAParticipant() {
        var group = state(participants: [participant("@bob:matrix.org", role: .human)])
        group.scope = .group
        group.roomAvatar = .room(id: "!design:matrix.org", name: "Design team", avatarURL: nil)

        #expect(group.scope == .group)
        // `.room`, not `.heroes`: a group pictures itself.
        guard case .room(_, let name, _) = group.roomAvatar else {
            Issue.record("a group call must carry a room avatar, got \(group.roomAvatar)")
            return
        }
        #expect(name == "Design team")
    }

    /// A DM keeps the peer's face — the SDK already encodes that as `.heroes`,
    /// so the call header agrees with the room list instead of inventing its
    /// own rule.
    @Test
    func aDirectCallKeepsThePeerAvatar() {
        var direct = state(participants: [participant("@bob:matrix.org", role: .human)])
        direct.scope = .direct
        direct.roomAvatar = .heroes([.init(userID: "@bob:matrix.org",
                                           displayName: "Bohdan",
                                           avatarURL: nil)])

        #expect(direct.scope == .direct)
        guard case .heroes(let heroes) = direct.roomAvatar else {
            Issue.record("a DM keeps its hero avatar, got \(direct.roomAvatar)")
            return
        }
        #expect(heroes.map(\.id) == ["@bob:matrix.org"])
    }

    /// A connected call says nothing about the channel in prose — the signal
    /// bars carry it. Only states the bars cannot show keep a detail line.
    @Test
    func aConnectedCallNarratesNoConnectionProse() {
        var poor = state(participants: [participant("@bob:matrix.org", role: .human)])
        poor.connectionQuality = .poor

        #expect(poor.isConnectionPoor)
        #expect(poor.statusDetail == nil)
        #expect(!poor.statusDetailIsDegraded)
    }
}
