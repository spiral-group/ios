//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import ElementX
import Foundation
import MatrixRustSDK
import Testing

// AGENT-PLATFORM (Brief 0063)

@MainActor
@Suite(.timeLimit(.minutes(2)))
struct NativeCallScreenViewModelTests {
    @Test
    func joiningAnEncryptedRoomRequestsEncryptedMedia() async throws {
        let rtcSession = makeSession()
        let viewModel = makeViewModel(rtcSession: rtcSession, isRoomEncrypted: true)

        viewModel.start()
        try await waitForJoin(on: rtcSession)

        #expect(rtcSession.joinEncryptMediaNotificationMediaReceivedArguments?.encryptMedia == true)
        #expect(rtcSession.joinEncryptMediaNotificationMediaReceivedArguments?.notification == .ring)
        #expect(rtcSession.joinEncryptMediaNotificationMediaReceivedArguments?.media == .audio)
    }

    @Test
    func joiningAnUnencryptedRoomDoesNotRequestEncryptedMedia() async throws {
        let rtcSession = makeSession()
        let viewModel = makeViewModel(rtcSession: rtcSession, isRoomEncrypted: false)

        viewModel.start()
        try await waitForJoin(on: rtcSession)

        #expect(rtcSession.joinEncryptMediaNotificationMediaReceivedArguments?.encryptMedia == false)
    }

    @Test
    func aFailedJoinNeverAsksForTransportCredentials() async throws {
        let rtcSession = makeSession()
        rtcSession.joinEncryptMediaNotificationMediaReturnValue = .failure(.roomInvalid)
        let viewModel = makeViewModel(rtcSession: rtcSession, isRoomEncrypted: true)

        viewModel.start()
        try await waitForJoin(on: rtcSession)
        try await waitFor {
            viewModel.context.viewState.callState == .ended(status: UntranslatedL10n.screenNativeCallStatusEnded)
        }

        // Authorizing against the SFU before we hold a membership would leak a
        // participant that the other side never sees join.
        #expect(rtcSession.transportCredentialsCalled == false)
        #expect(viewModel.context.viewState.callState == .ended(status: UntranslatedL10n.screenNativeCallStatusEnded))
    }

    @Test
    func answeringAnIncomingCallDoesNotNotifyTheRoomAgain() async throws {
        let rtcSession = makeSession()
        let viewModel = makeViewModel(rtcSession: rtcSession, isRoomEncrypted: true, notifyRoom: false)

        viewModel.start()
        try await waitForJoin(on: rtcSession)

        #expect(rtcSession.joinEncryptMediaNotificationMediaReceivedArguments?.notification == nil)
    }

    @Test
    func outgoingRingNotificationIsForwarded() async throws {
        let rtcSession = makeSession()
        let viewModel = makeViewModel(rtcSession: rtcSession, isRoomEncrypted: true)

        var ringEventIDs: [String] = []
        let cancellable = viewModel.actions.sink { action in
            if case let .didSendRingNotification(eventID) = action {
                ringEventIDs.append(eventID)
            }
        }
        defer { cancellable.cancel() }

        viewModel.start()
        try await waitFor { !ringEventIDs.isEmpty }

        #expect(ringEventIDs == ["$ring:matrix.org"])
    }

    @Test
    func answeringAnIncomingCallDoesNotWatchForDeclines() async throws {
        let rtcSession = makeSession()
        let viewModel = makeViewModel(rtcSession: rtcSession, isRoomEncrypted: true, notifyRoom: false)

        var ringActionCount = 0
        let cancellable = viewModel.actions.sink { action in
            if case .didSendRingNotification = action {
                ringActionCount += 1
            }
        }
        defer { cancellable.cancel() }

        viewModel.start()
        try await waitForJoin(on: rtcSession)

        #expect(ringActionCount == 0)
        #expect(!rtcSession.rtcNotificationEventIDCalled)
    }

    @Test
    func videoIntentReachesTheMatrixRTCSession() async {
        let rtcSession = makeSession()
        let session = makeNativeSession(rtcSession: rtcSession, media: .video)

        await session.start()

        #expect(rtcSession.joinEncryptMediaNotificationMediaReceivedArguments?.media == .video)
    }

    @Test
    func cameraCanUpgradeAndDowngradeAnAudioCall() async throws {
        let rtcSession = makeSession()
        let transportURL = try #require(URL(string: "wss://rtc.example.org"))
        rtcSession.transportCredentialsReturnValue = .success(.init(url: transportURL,
                                                                    token: "token",
                                                                    identity: rtcSession.underlyingOwnIdentity))
        let transport = NativeCallTransportMock()
        transport.underlyingEvents = Empty().eraseToAnyPublisher()
        transport.localIdentity = rtcSession.underlyingOwnIdentity
        transport.remoteParticipants = []
        transport.remoteTracks = []
        transport.underlyingIsLocalSpeaking = false
        transport.underlyingLocalConnectionQuality = .unknown
        transport.underlyingIsMicrophoneEnabled = true
        transport.underlyingIsCameraEnabled = false
        transport.setSubscriptionsAuthorizedIdentitiesIsTrackExcludedClosure = { _, _ in true }
        transport.setEncryptionKeyIndexIdentityClosure = { _, _, _ in }
        transport.setCameraEnabledClosure = { enabled in
            transport.underlyingIsCameraEnabled = enabled
        }
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)
        let delegate = NativeCallSessionDelegateSpy()
        session.delegate = delegate

        await session.start()
        #expect(delegate.activeVideoStates.last == false)

        await session.setCameraEnabled(true)
        #expect(rtcSession.setMediaReceivedInvocations.last == .video)
        #expect(delegate.activeVideoStates.last == true)

        await session.setCameraEnabled(false)
        #expect(rtcSession.setMediaReceivedInvocations.last == .audio)
        #expect(delegate.activeVideoStates.last == false)
    }

    @Test
    func anAudioCallShowsAndHidesTheVideoStageAsVideoChanges() {
        let rtcSession = makeSession()
        let callKitService = CallKitServiceMock(.init())
        let viewModel = makeViewModel(rtcSession: rtcSession,
                                      isRoomEncrypted: false,
                                      callKitService: callKitService)
        let session = makeNativeSession(rtcSession: rtcSession)

        #expect(!viewModel.context.viewState.isVideoCall)

        viewModel.nativeCallSession(session, didChangeActiveVideo: true, isSpeakerEnabled: true)
        #expect(viewModel.context.viewState.isVideoCall)
        #expect(viewModel.context.viewState.isSpeakerEnabled)
        #expect(callKitService.updateCallVideoStateHasVideoCallKitIDReceivedArguments?.hasVideo == true)

        viewModel.nativeCallSession(session, didChangeActiveVideo: false, isSpeakerEnabled: true)
        #expect(!viewModel.context.viewState.isVideoCall)
        #expect(callKitService.updateCallVideoStateHasVideoCallKitIDReceivedArguments?.hasVideo == false)
    }

    /// The doorbell moved off `com.spiral.session` timeline events and onto
    /// the agents' own state documents — the register LiveKit pushes to every
    /// device. The panel's controls are still REST, so the document says only
    /// WHEN to re-read.
    @Test
    func aChangedAgentDocumentReloadsTheAgentCenter() async throws {
        let agentPlatformService = AgentPlatformServiceMock()
        agentPlatformService.voiceSessionControlContextsRoomIDReturnValue = .success([])
        agentPlatformService.listMyPersonalAgentsReturnValue = .success(.init(agents: [], provisioningStatus: .ready))
        let rtcSession = makeSession()
        let viewModel = NativeCallScreenViewModel(session: makeNativeSession(rtcSession: rtcSession),
                                                  callKitService: CallKitServiceMock(.init()),
                                                  agentCenter: NativeAgentCenterController(agentPlatformService: agentPlatformService,
                                                                                           roomID: "!room:matrix.org",
                                                                                           roomMemberMxids: { [] },
                                                                                           inviteAgent: { _ in false }),
                                                  appMediator: AppMediatorMock(.init()),
                                                  isVideoCall: false,
                                                  roomID: "!room:matrix.org",
                                                  roomName: "Native call")
        let session = makeNativeSession(rtcSession: rtcSession)

        viewModel.nativeCallSessionDidChangeAgentState(session)

        try await waitFor { agentPlatformService.voiceSessionControlContextsRoomIDCalled }
    }

    /// Review #2: whether a call's translation can become the room's rule is
    /// the server's `can_save_as_room_default`, never the client's own 1:1
    /// guess. The cases where the two disagree are the ones that matter.
    @Test(arguments: [(NativeCallScope.group, false, false),
                      (.direct, true, true),
                      (.assistant, false, false)])
    func aRoomDefaultSaveGoesOutOnlyWhenTheServerAllowsIt(scope: NativeCallScope, canSave: Bool, sends: Bool) async throws {
        let agentPlatformService = AgentPlatformServiceMock()
        agentPlatformService.saveVoiceTranslationAsRoomDefaultSessionIDReturnValue = .success(())
        agentPlatformService.voiceSessionControlContextsRoomIDReturnValue = .success([])
        agentPlatformService.listMyPersonalAgentsReturnValue = .success(.init(agents: [], provisioningStatus: .ready))
        let rtcSession = makeSession()
        let viewModel = NativeCallScreenViewModel(session: makeNativeSession(rtcSession: rtcSession, scope: scope),
                                                  callKitService: CallKitServiceMock(.init()),
                                                  agentCenter: NativeAgentCenterController(agentPlatformService: agentPlatformService,
                                                                                           roomID: "!room:matrix.org",
                                                                                           roomMemberMxids: { [] },
                                                                                           inviteAgent: { _ in false }),
                                                  appMediator: AppMediatorMock(.init()),
                                                  isVideoCall: false,
                                                  roomID: "!room:matrix.org",
                                                  roomName: "Native call",
                                                  scope: scope)
        viewModel.state.agentCenter = NativeAgentCenterSnapshot(isAvailable: true,
                                                                isLoading: false,
                                                                sessions: [Self.translatingSession(canSaveAsRoomDefault: canSave)])

        #expect(viewModel.context.viewState.agents.control(sessionID: "session-1")?.canSaveAsRoomDefault == canSave)

        viewModel.context.send(viewAction: .saveAgentTranslationAsRoomDefault(sessionID: "session-1"))

        if sends {
            try await waitFor { agentPlatformService.saveVoiceTranslationAsRoomDefaultSessionIDCalled }
        } else {
            // The write is dispatched synchronously when it goes out at all.
            #expect(!viewModel.context.viewState.isAgentActionInFlight)
            try await Task.sleep(for: .milliseconds(50))
            #expect(!agentPlatformService.saveVoiceTranslationAsRoomDefaultSessionIDCalled)
        }
    }

    private static func translatingSession(canSaveAsRoomDefault: Bool) -> NativeAgentCenterSession {
        NativeAgentCenterSession(sessionID: "session-1",
                                 agentMxid: "@assistant-alice:matrix.org",
                                 canControl: true,
                                 isEnding: false,
                                 recording: .init(isEnabled: false, revision: 1, delivery: .notArmed, isStopped: false),
                                 summary: .init(isEnabled: false, revision: 1, delivery: .notArmed, isStopped: false),
                                 translation: .init(booths: [.init(speakerScope: VoiceSpeakerScope.anyone.rawValue,
                                                                   speakerMembers: [],
                                                                   targetLanguages: ["uk"])],
                                                    style: "simultaneous",
                                                    source: "override",
                                                    revision: 2),
                                 conversation: .unknown,
                                 canSaveAsRoomDefault: canSaveAsRoomDefault)
    }

    /// ONE call (the Telegram model, operator decision 2026-08-21): a
    /// call that STARTED as video opens on the video stage (the initial
    /// intent), but once every camera is dark it falls back to the avatar
    /// stage — and comes right back when any camera returns. CallKit's
    /// label follows the live truth.
    @Test
    func aVideoCallFallsBackToTheAvatarStageWhenAllCamerasAreOff() {
        let rtcSession = makeSession()
        let callKitService = CallKitServiceMock(.init())
        let viewModel = makeViewModel(rtcSession: rtcSession,
                                      isRoomEncrypted: false,
                                      isVideoCall: true,
                                      callKitService: callKitService)
        let session = makeNativeSession(rtcSession: rtcSession)

        // The initial intent shows the video stage before media connects.
        #expect(viewModel.context.viewState.isVideoCall)

        // All cameras dark: the avatar stage, honestly.
        viewModel.nativeCallSession(session, didChangeActiveVideo: false, isSpeakerEnabled: true)
        #expect(!viewModel.context.viewState.isVideoCall)
        #expect(callKitService.updateCallVideoStateHasVideoCallKitIDReceivedArguments?.hasVideo == false)

        // A camera returns: the video stage again.
        viewModel.nativeCallSession(session, didChangeActiveVideo: true, isSpeakerEnabled: true)
        #expect(viewModel.context.viewState.isVideoCall)
        #expect(callKitService.updateCallVideoStateHasVideoCallKitIDReceivedArguments?.hasVideo == true)
    }

    /// The meta line's signal bars are the transport's live quality
    /// ladder — and the "Poor connection" note reads its low end.
    @Test
    func theConnectionQualityLadderReachesTheViewState() {
        let rtcSession = makeSession()
        let viewModel = makeViewModel(rtcSession: rtcSession, isRoomEncrypted: false)
        let session = makeNativeSession(rtcSession: rtcSession)

        #expect(viewModel.context.viewState.connectionQuality == .unknown)
        #expect(!viewModel.context.viewState.isConnectionPoor)

        viewModel.nativeCallSession(session, didChangeConnectionQuality: .excellent)
        #expect(viewModel.context.viewState.connectionQuality == .excellent)
        #expect(!viewModel.context.viewState.isConnectionPoor)

        viewModel.nativeCallSession(session, didChangeConnectionQuality: .poor)
        #expect(viewModel.context.viewState.connectionQuality == .poor)
        #expect(viewModel.context.viewState.isConnectionPoor)
        #expect(viewModel.context.viewState.connectionQuality.filledBars == 1)
    }

    @Test
    func aVideoCallIsDeclaredToCallKitAsVideo() async throws {
        let rtcSession = makeSession()
        let callKitService = CallKitServiceMock(.init())
        let viewModel = makeViewModel(rtcSession: rtcSession,
                                      isRoomEncrypted: false,
                                      isVideoCall: true,
                                      callKitService: callKitService)
        let session = makeNativeSession(rtcSession: rtcSession)

        viewModel.nativeCallSession(session, didChangeState: .connected)

        try await waitFor { callKitService.setupCallSessionRoomIDRoomDisplayNameIsVoiceCallCallKitIDCalled }
        #expect(callKitService.setupCallSessionRoomIDRoomDisplayNameIsVoiceCallCallKitIDReceivedArguments?.isVoiceCall == false)
        // The kind is asserted again for an answered incoming call, whose CallKit
        // metadata was guessed from the push payload.
        try await waitFor { callKitService.updateCallVideoStateHasVideoCallKitIDCalled }
        #expect(callKitService.updateCallVideoStateHasVideoCallKitIDReceivedArguments?.hasVideo == true)
    }

    @Test
    func resolvedVideoStateIsReappliedAfterCallKitSetup() async throws {
        let rtcSession = makeSession()
        let callKitService = CallKitServiceMock(.init())
        let viewModel = makeViewModel(rtcSession: rtcSession,
                                      isRoomEncrypted: false,
                                      callKitService: callKitService)
        let session = makeNativeSession(rtcSession: rtcSession)

        // Media can settle before the async CallKit transaction creates its
        // ongoing call. The first update is allowed to be a no-op in the real
        // service; setup must apply the latest resolved state again.
        viewModel.nativeCallSession(session, didChangeActiveVideo: true, isSpeakerEnabled: true)
        viewModel.nativeCallSession(session, didChangeState: .connected)

        try await waitFor {
            callKitService.setupCallSessionRoomIDRoomDisplayNameIsVoiceCallCallKitIDCalled
                && callKitService.updateCallVideoStateHasVideoCallKitIDReceivedInvocations.count == 2
        }
        #expect(callKitService.updateCallVideoStateHasVideoCallKitIDReceivedInvocations.last?.hasVideo == true)
    }

    @Test
    func groupCallsDoNotUseDirectCallRinging() async {
        let rtcSession = makeSession()
        let session = makeNativeSession(rtcSession: rtcSession, scope: .group)
        let delegate = NativeCallSessionDelegateSpy()
        session.delegate = delegate

        await session.start()

        #expect(!delegate.states.contains(.ringing))
    }

    @Test
    func aGroupDeclineDoesNotEndTheConference() async {
        let rtcSession = makeSession()
        let session = makeNativeSession(rtcSession: rtcSession, scope: .group)

        await session.remoteDeclined()

        #expect(!rtcSession.leaveCalled)
    }

    @Test
    func groupMembershipChangesDoNotEndTheConference() {
        let updates = PassthroughSubject<MatrixRTCSessionUpdate, Never>()
        let rtcSession = makeSession()
        rtcSession.underlyingUpdates = updates.eraseToAnyPublisher()
        let session = makeNativeSession(rtcSession: rtcSession, scope: .group)
        let bob = MatrixRTCParticipant(userID: "@bob:matrix.org",
                                       deviceID: "BOB",
                                       identity: "opaque-bob-identity")

        updates.send(.participantsChanged([bob]))
        updates.send(.participantsChanged([]))
        updates.send(.participantsChanged([bob]))

        #expect(session.state == .connecting)
        #expect(!rtcSession.leaveCalled)
    }

    /// Operator report 2026-09-11: calling one's own assistant rang until
    /// the no-answer timeout although the agent had joined within seconds.
    /// A DM is a call with its other member; when that member is an agent
    /// the call is WITH the assistant — its own scope.
    @Test
    func aDMWithOnlyTheAssistantIsAnAssistantCall() {
        // Me + my assistant, flagged by the member hints.
        #expect(NativeCallConfiguration.scope(isDM: true, joinedMembersCount: 2, activeServiceMembersCount: 1,
                                              otherMemberIDs: [], ownUserID: Self.me) == .assistant)
        // Me + a human.
        #expect(NativeCallConfiguration.scope(isDM: true, joinedMembersCount: 2, activeServiceMembersCount: 0,
                                              otherMemberIDs: [Self.human], ownUserID: Self.me) == .direct)
        // Me + a human + the human's translating agent: the HUMAN answers,
        // whether or not the heroes leave the service member out.
        #expect(NativeCallConfiguration.scope(isDM: true, joinedMembersCount: 3, activeServiceMembersCount: 1,
                                              otherMemberIDs: [Self.human], ownUserID: Self.me) == .direct)
        #expect(NativeCallConfiguration.scope(isDM: true, joinedMembersCount: 3, activeServiceMembersCount: 1,
                                              otherMemberIDs: [Self.human, Self.humansAgent], ownUserID: Self.me) == .direct)
        // Not a DM at all.
        #expect(NativeCallConfiguration.scope(isDM: false, joinedMembersCount: 2, activeServiceMembersCount: 1,
                                              otherMemberIDs: [Self.assistant], ownUserID: Self.me) == .group)
        #expect(NativeCallConfiguration.scope(isDM: false, joinedMembersCount: 2, activeServiceMembersCount: 0,
                                              otherMemberIDs: [Self.assistant], ownUserID: Self.me) == .group)
        // A DM whose agent has not joined the room yet has no callee to
        // answer; it rings out as a direct call.
        #expect(NativeCallConfiguration.scope(isDM: true, joinedMembersCount: 1, activeServiceMembersCount: 0,
                                              otherMemberIDs: [], ownUserID: Self.me) == .direct)
        #expect(NativeCallConfiguration.scope(isDM: true, joinedMembersCount: 1, activeServiceMembersCount: 0,
                                              otherMemberIDs: [Self.assistant], ownUserID: Self.me) == .direct)
        #expect(NativeCallScope.assistant.isOneToOne && NativeCallScope.direct.isOneToOne && !NativeCallScope.group.isOneToOne)
    }

    /// Walk 2026-10-11: since backend `02043c5e` an agent alone with its
    /// owner is not a service member (so the DM is not «Empty Room»). The
    /// call routed as `.direct` — `activeService 0, serviceMembers []` — and
    /// rang out at 30 s while the agent talked. Who the other member IS
    /// decides, not the hints.
    @Test
    func aDMWithOnlyTheAssistantIsAnAssistantCallWithoutMemberHints() {
        #expect(NativeCallConfiguration.scope(isDM: true, joinedMembersCount: 2, activeServiceMembersCount: 0,
                                              otherMemberIDs: [Self.assistant], ownUserID: Self.me) == .assistant)
        // A company agent is an agent too.
        #expect(NativeCallConfiguration.scope(isDM: true, joinedMembersCount: 2, activeServiceMembersCount: 0,
                                              otherMemberIDs: ["@agent-acme-1:localhost"], ownUserID: Self.me) == .assistant)
        // A human in the DM, unhinted agent beside them: still the human's call.
        #expect(NativeCallConfiguration.scope(isDM: true, joinedMembersCount: 3, activeServiceMembersCount: 0,
                                              otherMemberIDs: [Self.human, Self.humansAgent], ownUserID: Self.me) == .direct)
        // My assistant joined, a human only invited: someone may yet answer.
        #expect(NativeCallConfiguration.scope(isDM: true, joinedMembersCount: 2, activeServiceMembersCount: 0,
                                              otherMemberIDs: [Self.assistant, Self.human], ownUserID: Self.me) == .direct)
        // Another server's `@assistant-…` is a person: agents live on ours.
        #expect(NativeCallConfiguration.scope(isDM: true, joinedMembersCount: 2, activeServiceMembersCount: 0,
                                              otherMemberIDs: ["@assistant-walkb:elsewhere.org"], ownUserID: Self.me) == .direct)
        // A name that merely contains the word is not the namespace.
        #expect(NativeCallConfiguration.scope(isDM: true, joinedMembersCount: 2, activeServiceMembersCount: 0,
                                              otherMemberIDs: ["@my-assistant-bob:localhost"], ownUserID: Self.me) == .direct)
    }

    /// The same, read off the room the way the flow coordinator does —
    /// the walk's exact topology first. Members not loaded yet: the heroes.
    @Test
    func theConfigurationReadsAnAssistantCallOffTheRoom() {
        let roomInfo = Self.dm()
        roomInfo.heroes = [Self.hero(Self.assistant)]
        #expect(Self.configuration(roomInfo).scope == .assistant)

        roomInfo.heroes = []
        roomInfo.activeServiceMembersCount = 1
        #expect(Self.configuration(roomInfo).scope == .assistant)

        roomInfo.heroes = [Self.hero(Self.human)]
        roomInfo.activeServiceMembersCount = 0
        #expect(Self.configuration(roomInfo).scope == .direct)
    }

    /// Review 2026-10-11: heroes are a naming hint — the server sends them
    /// only while the room has no name or alias. A renamed assistant DM has
    /// none, and the call rang out again; its joined members still say who
    /// the call is with.
    @Test
    func aNamedAssistantDMIsAnAssistantCallByItsJoinedMembers() {
        let roomInfo = Self.dm()
        roomInfo.rawName = "My assistant"
        roomInfo.heroes = []
        #expect(Self.configuration(roomInfo, members: [Self.member(Self.me), Self.member(Self.assistant)]).scope == .assistant)

        // A human who joined decides it, whatever the heroes say.
        roomInfo.heroes = [Self.hero(Self.assistant)]
        #expect(Self.configuration(roomInfo, members: [Self.member(Self.me), Self.member(Self.human)]).scope == .direct)

        // An assistant that has only been invited is nobody to answer.
        roomInfo.heroes = []
        roomInfo.joinedMembersCount = 1
        #expect(Self.configuration(roomInfo, members: [Self.member(Self.me), Self.member(Self.assistant, membership: .invite)]).scope == .direct)
    }

    @Test
    func theCallsOtherMembersAreTheJoinedOnesOnceMembersLoad() {
        let members = [Self.member(Self.me), Self.member(Self.assistant), Self.member(Self.human, membership: .leave)]
        #expect(NativeCallConfiguration.otherMemberIDs(members: members, ownUserID: Self.me, heroIDs: [Self.human], joinedMembersCount: 2) == [Self.assistant])
        #expect(NativeCallConfiguration.otherMemberIDs(members: [], ownUserID: Self.me, heroIDs: [Self.human], joinedMembersCount: 2) == [Self.human])
        // A partial list (the store's members, before the full load) is not the room's.
        #expect(NativeCallConfiguration.otherMemberIDs(members: [Self.member(Self.me)], ownUserID: Self.me, heroIDs: [Self.human], joinedMembersCount: 2) == [Self.human])
    }

    private nonisolated static let me = "@walkb:localhost"
    private nonisolated static let assistant = "@assistant-walkb:localhost"
    private nonisolated static let human = "@walkowner:localhost"
    private nonisolated static let humansAgent = "@assistant-walkowner:localhost"

    private static func hero(_ userID: String) -> RoomHero {
        RoomHero(userId: userID, displayName: nil, avatarUrl: nil, status: nil, call: nil)
    }

    private static func member(_ userID: String, membership: MembershipState = .join) -> RoomMemberProxyMock {
        RoomMemberProxyMock(with: .init(userID: userID, membership: membership))
    }

    /// A DM of two joined members without member hints.
    private static func dm() -> RoomInfoProxyMock {
        let roomInfo = RoomInfoProxyMock()
        roomInfo.isDirect = true
        roomInfo.isDM = true
        roomInfo.isSpace = false
        roomInfo.joinedMembersCount = 2
        roomInfo.activeServiceMembersCount = 0
        roomInfo.joinRule = .invite
        return roomInfo
    }

    private static func configuration(_ roomInfo: RoomInfoProxyMock, members: [RoomMemberProxyMock] = []) -> NativeCallConfiguration {
        NativeCallConfiguration(media: .audio, roomInfo: roomInfo, members: members, ownUserID: me)
    }

    /// ADR-0079 D3: every room is native; the room's shape only decides
    /// whether a FRESH call rings every phone or posts a silent notification.
    @Test
    func aFreshCallRingsSmallPrivateRoomsAndNotifiesTheRest() {
        #expect(NativeCallConfiguration.freshCallNotification(isDM: true, isSpace: false, isPrivate: true, joinedMembersCount: 2) == .ring)
        // A DM rings whatever else is true of it.
        #expect(NativeCallConfiguration.freshCallNotification(isDM: true, isSpace: false, isPrivate: nil, joinedMembersCount: 2) == .ring)
        #expect(NativeCallConfiguration.freshCallNotification(isDM: false, isSpace: false, isPrivate: true, joinedMembersCount: 8) == .ring)
        // Public: never ring every phone in the room.
        #expect(NativeCallConfiguration.freshCallNotification(isDM: false, isSpace: false, isPrivate: false, joinedMembersCount: 3) == .notification)
        // Unknown join rule reads as public.
        #expect(NativeCallConfiguration.freshCallNotification(isDM: false, isSpace: false, isPrivate: nil, joinedMembersCount: 3) == .notification)
        #expect(NativeCallConfiguration.freshCallNotification(isDM: false, isSpace: true, isPrivate: true, joinedMembersCount: 3) == .notification)
        #expect(NativeCallConfiguration.freshCallNotification(isDM: false, isSpace: false, isPrivate: true, joinedMembersCount: 9) == .notification)
    }

    @Test
    func aDirectTaggedRoomWithThreeMembersUsesGroupCallSemantics() {
        let roomInfo = RoomInfoProxyMock()
        roomInfo.isDirect = true
        roomInfo.isDM = false
        roomInfo.isSpace = false
        roomInfo.joinedMembersCount = 3
        roomInfo.activeServiceMembersCount = 0
        roomInfo.joinRule = .invite

        let configuration = Self.configuration(roomInfo)
        #expect(configuration.scope == .group)
        #expect(configuration.freshCallNotification == .ring)
    }

    @Test
    func theCallTileDescribesTheCallNotTheRoom() {
        // 1:1 call in a DM stays direct even though an idle agent is in the room.
        #expect(!ActiveCallTimelineItemView.isGroupPresentation(isDM: true, activeMemberCount: 2))
        // The assistant actually connected: 3 call participants is a group call.
        #expect(ActiveCallTimelineItemView.isGroupPresentation(isDM: true, activeMemberCount: 3))
        // Group rooms always use group presentation, whatever the turnout.
        #expect(ActiveCallTimelineItemView.isGroupPresentation(isDM: false, activeMemberCount: 1))
        // A ringing DM call with only the caller joined is still direct.
        #expect(!ActiveCallTimelineItemView.isGroupPresentation(isDM: true, activeMemberCount: 1))
    }

    /// Asks the LIVE routing rule, in the channel that hides the least, so
    /// the pin cannot pass against a seam that production no longer uses.
    private func excludedForOwnVoice(_ trackName: String, _ ownUserID: String) -> Bool {
        NativeCallListening.isTrackExcluded(trackName: trackName, channel: .everything, ownUserID: ownUserID)
    }

    @Test
    func aSpeakerNeverSubscribesToTheirOwnTranslationTrack() {
        let me = "@alice:example.org"
        #expect(excludedForOwnVoice("lt:en:@alice:example.org", me))
        #expect(excludedForOwnVoice("lt:uk:@alice:example.org", me))
        // Somebody else's translation stays audible.
        #expect(!excludedForOwnVoice("lt:en:@emmm:spiral.md", me))
        // Original microphones are untouched.
        #expect(!excludedForOwnVoice("microphone", me))
        // A user id that merely suffixes another's must not match.
        #expect(!excludedForOwnVoice("lt:en:@notalice:example.org", me))
    }

    @Test
    func serviceMembersDoNotCountTowardTheRingLimit() {
        let roomInfo = RoomInfoProxyMock()
        roomInfo.isDirect = false
        roomInfo.isDM = false
        roomInfo.isSpace = false
        roomInfo.joinedMembersCount = 9
        roomInfo.activeServiceMembersCount = 2
        roomInfo.joinRule = .invite

        #expect(Self.configuration(roomInfo).freshCallNotification == .ring)

        roomInfo.activeServiceMembersCount = 0
        #expect(Self.configuration(roomInfo).freshCallNotification == .notification)
    }

    @Test
    func encryptedMediaRequiresAnActiveMembershipAndKey() {
        let bob = MatrixRTCParticipant(userID: "@bob:matrix.org",
                                       deviceID: "BOB",
                                       identity: "opaque-bob-identity")
        let memberships = [bob.identity: bob]

        func authorized(memberships: [String: MatrixRTCParticipant],
                        keys: Set<String>,
                        encrypted: Bool) -> Bool {
            NativeCallStateDerivation.isMediaAuthorized(identity: bob.identity,
                                                        membershipsByIdentity: memberships,
                                                        identitiesWithKeys: keys,
                                                        isRoomEncrypted: encrypted)
        }

        // No membership: never authorized, encrypted or not.
        #expect(!authorized(memberships: [:], keys: [], encrypted: false))
        #expect(!authorized(memberships: [:], keys: [bob.identity], encrypted: true))
        // Membership alone is enough in an unencrypted room.
        #expect(authorized(memberships: memberships, keys: [], encrypted: false))
        // An encrypted room additionally needs the media key to have arrived.
        #expect(!authorized(memberships: memberships, keys: [], encrypted: true))
        #expect(authorized(memberships: memberships, keys: [bob.identity], encrypted: true))
    }

    @Test
    func anUnknownTransportIdentityIsNeverAuthorized() {
        let bob = MatrixRTCParticipant(userID: "@bob:matrix.org",
                                       deviceID: "BOB",
                                       identity: "opaque-bob-identity")
        // A key can arrive for an identity that holds no membership; it must
        // never authorize media on its own.
        let unknownIdentity = "unknown-livekit-identity"
        for encrypted in [false, true] {
            #expect(!NativeCallStateDerivation.isMediaAuthorized(identity: unknownIdentity,
                                                                 membershipsByIdentity: [bob.identity: bob],
                                                                 identitiesWithKeys: [unknownIdentity],
                                                                 isRoomEncrypted: encrypted))
        }
    }

    @Test
    func stoppingLeavesTheMatrixSession() async throws {
        let rtcSession = makeSession()
        let viewModel = makeViewModel(rtcSession: rtcSession, isRoomEncrypted: true)

        viewModel.start()
        try await waitForJoin(on: rtcSession)

        viewModel.stop()
        try await waitFor { rtcSession.leaveCalled }

        #expect(rtcSession.leaveCalled)
    }

    @Test
    func hangingUpDismissesTheScreen() {
        let rtcSession = makeSession()
        let viewModel = makeViewModel(rtcSession: rtcSession, isRoomEncrypted: true)

        var actions: [NativeCallScreenViewModelAction] = []
        let cancellable = viewModel.actions.sink { actions.append($0) }
        defer { cancellable.cancel() }

        viewModel.context.send(viewAction: .hangUp)

        #expect(actions.count == 1)
    }

    @Test
    func outgoingCallRingsBeforeTheTransportConnects() async {
        let rtcSession = makeSession()
        let session = makeNativeSession(rtcSession: rtcSession)
        let delegate = NativeCallSessionDelegateSpy()
        session.delegate = delegate

        await session.start()

        // Transport authorization fails in this environment, so the call ends —
        // but it must have rung first. Entering `ringing` only after the
        // transport connected left a window where a fast callee (the voice
        // agent answers in ~2s) joined while the state was still `connecting`,
        // so the answer callback found no `ringing` to promote and the call
        // rang at a peer who was already listening.
        let ringingIndex = delegate.states.firstIndex(of: .ringing)
        let endedIndex = delegate.states.firstIndex {
            if case .ended = $0 { true } else { false }
        }

        #expect(ringingIndex != nil)
        #expect(endedIndex != nil)

        if let ringingIndex, let endedIndex {
            #expect(ringingIndex < endedIndex)
        }
    }

    @Test
    func answeringAnIncomingCallNeverRings() async {
        let rtcSession = makeSession()
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: true,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .direct))
        let delegate = NativeCallSessionDelegateSpy()
        session.delegate = delegate

        await session.start()

        #expect(!delegate.states.contains(.ringing))
    }

    @Test
    func losingTheConnectionShowsTheOutcomeBeforeDismissing() async throws {
        let rtcSession = makeSession()
        let viewModel = makeViewModel(rtcSession: rtcSession, isRoomEncrypted: true)

        var actions: [NativeCallScreenViewModelAction] = []
        let cancellable = viewModel.actions.sink { actions.append($0) }
        defer { cancellable.cancel() }

        viewModel.nativeCallSession(makeNativeSession(rtcSession: rtcSession),
                                    didChangeState: .ended(reason: .connectionLost))

        #expect(viewModel.context.viewState.callState == .ended(status: UntranslatedL10n.screenNativeCallStatusConnectionLost))
        // The status stays visible before the screen goes away.
        #expect(actions.isEmpty)
        try await waitFor(attempts: 400) { !actions.isEmpty }
    }

    @Test
    func systemHangUpDismissesTheScreen() {
        let service = CallKitServiceMock(.init())
        let serviceActions = PassthroughSubject<CallKitServiceAction, Never>()
        service.actions = serviceActions.eraseToAnyPublisher()
        let viewModel = makeViewModel(rtcSession: makeSession(), isRoomEncrypted: true, callKitService: service)

        var actions: [NativeCallScreenViewModelAction] = []
        let cancellable = viewModel.actions.sink { actions.append($0) }
        defer { cancellable.cancel() }

        serviceActions.send(.endCall(roomID: "!room:matrix.org"))

        #expect(actions.count == 1)
    }

    @Test
    func theParticipantSnapshotIsMembershipDrivenWithRolesAndMediaState() {
        let updates = PassthroughSubject<MatrixRTCSessionUpdate, Never>()
        let rtcSession = makeSession()
        rtcSession.underlyingUpdates = updates.eraseToAnyPublisher()
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: true,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        serviceMembers: ["@agent:matrix.org"])

        let bob = MatrixRTCParticipant(userID: "@bob:matrix.org",
                                       deviceID: "BOB",
                                       identity: "bob-identity")
        let agent = MatrixRTCParticipant(userID: "@agent:matrix.org",
                                         deviceID: "AGENT",
                                         identity: "agent-identity")
        updates.send(.participantsChanged([bob, agent]))

        // A published membership is enough to appear in the snapshot — before
        // any transport exists the participant renders as connecting.
        let remotes = session.participants.filter { !$0.isLocal }
        #expect(remotes.count == 2)
        #expect(remotes.allSatisfy { $0.mediaState == .connecting })
        #expect(remotes.first { $0.userID == "@agent:matrix.org" }?.role == .agent)
        #expect(remotes.first { $0.userID == "@bob:matrix.org" }?.role == .human)
        #expect(session.participants.first?.isLocal == true)
        #expect(session.participants.first?.role == .human)

        // A media key alone doesn't connect anyone: without a transport the
        // participant stays in the connecting state.
        updates.send(.encryptionKeyReceived(.init(participantIdentity: "bob-identity",
                                                  index: 0,
                                                  key: Data(repeating: 1, count: 32))))
        #expect(session.participants.first { $0.userID == "@bob:matrix.org" }?.mediaState == .connecting)

        // Leaving removes the membership and with it the snapshot entry.
        updates.send(.participantsChanged([agent]))
        #expect(session.participants.filter { !$0.isLocal }.map(\.userID) == ["@agent:matrix.org"])
    }

    @Test
    func ourRotatedKeyMovesTheSendersToItsIndexAfterInstallingIt() {
        // Device day run 4 (2026-09-12): a rotation announced at a NEW ring
        // index is gapless only if the senders follow it — and only after the
        // key sits in that slot, or frames get tagged with an empty one.
        let updates = PassthroughSubject<MatrixRTCSessionUpdate, Never>()
        let rtcSession = makeSession()
        rtcSession.underlyingUpdates = updates.eraseToAnyPublisher()
        let transport = NativeCallTransportMock()
        transport.underlyingEvents = Empty().eraseToAnyPublisher()
        transport.localIdentity = "@alice:matrix.org:DEVICE"
        transport.underlyingIsLocalSpeaking = false
        transport.underlyingLocalConnectionQuality = .unknown
        transport.underlyingIsMicrophoneEnabled = true
        transport.underlyingIsCameraEnabled = false
        transport.remoteParticipants = []
        transport.remoteTracks = []
        transport.setSubscriptionsAuthorizedIdentitiesIsTrackExcludedClosure = { _, _ in true }
        var order = [String]()
        transport.setEncryptionKeyIndexIdentityClosure = { _, index, identity in order.append("key \(identity) @\(index)") }
        transport.setSenderKeyIndexClosure = { index in order.append("senders @\(index)") }

        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: true,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)
        defer { withExtendedLifetime(session) { } }

        updates.send(.ownEncryptionKeyChanged(.init(participantIdentity: "@alice:matrix.org:DEVICE", index: 3, key: Data(repeating: 7, count: 32))))
        #expect(order == ["key @alice:matrix.org:DEVICE @3", "senders @3"])

        // A peer's key never moves OUR senders.
        updates.send(.encryptionKeyReceived(.init(participantIdentity: "bob-identity",
                                                  index: 5,
                                                  key: Data(repeating: 1, count: 32))))
        #expect(order == ["key @alice:matrix.org:DEVICE @3", "senders @3", "key bob-identity @5"])
    }

    @Test
    func anAgentAttachedMidCallGetsItsBadgeWhenTheMemberHintsUpdate() {
        // Brief 0064 defect: the roster used the creation-time member-hints
        // snapshot, so an agent added via the Agent Center mid-call rendered
        // as a human. The live hints update must re-badge it.
        let updates = PassthroughSubject<MatrixRTCSessionUpdate, Never>()
        let rtcSession = makeSession()
        rtcSession.underlyingUpdates = updates.eraseToAnyPublisher()
        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        serviceMembers: [])

        let agent = MatrixRTCParticipant(userID: "@assistant:matrix.org",
                                         deviceID: "AGENT",
                                         identity: "agent-identity")
        updates.send(.participantsChanged([agent]))
        #expect(session.participants.first { $0.userID == "@assistant:matrix.org" }?.role == .human)

        session.updateServiceMembers(["@assistant:matrix.org"])
        #expect(session.participants.first { $0.userID == "@assistant:matrix.org" }?.role == .agent)
    }

    @Test
    func aRemoteMuteReachesTheRosterOnItsOwnEvent() {
        // Operator defect: muting on one device did not update the other
        // until the WATCHER toggled their own microphone. A mute publishes
        // no track and starts no speech, so it only reaches the roster if
        // its own transport event re-reads the snapshot (LiveKit's
        // `didUpdateIsMuted`, which the transport had no hook for).
        let updates = PassthroughSubject<MatrixRTCSessionUpdate, Never>()
        let rtcSession = makeSession()
        rtcSession.underlyingUpdates = updates.eraseToAnyPublisher()

        let transportEvents = PassthroughSubject<NativeCallTransportEvent, Never>()
        let transport = NativeCallTransportMock()
        transport.underlyingEvents = transportEvents.eraseToAnyPublisher()
        transport.localIdentity = "@alice:matrix.org:DEVICE"
        transport.underlyingIsLocalSpeaking = false
        transport.underlyingLocalConnectionQuality = .unknown
        transport.underlyingIsMicrophoneEnabled = true
        transport.underlyingIsCameraEnabled = false
        transport.remoteParticipants = [.init(identity: "@bob:matrix.org:BOB", isSpeaking: false, isAudioEnabled: true)]
        transport.remoteTracks = []
        transport.setSubscriptionsAuthorizedIdentitiesIsTrackExcludedClosure = { _, _ in true }
        transport.setEncryptionKeyIndexIdentityClosure = { _, _, _ in }

        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)

        updates.send(.participantsChanged([.init(userID: "@bob:matrix.org", deviceID: "BOB", identity: "@bob:matrix.org:BOB")]))
        #expect(session.participants.first { $0.userID == "@bob:matrix.org" }?.isAudioEnabled == true)

        // Bob mutes. The ONLY thing that happens is the mute event.
        transport.remoteParticipants = [.init(identity: "@bob:matrix.org:BOB", isSpeaking: false, isAudioEnabled: false)]
        transportEvents.send(.participantsUpdated)
        #expect(session.participants.first { $0.userID == "@bob:matrix.org" }?.isAudioEnabled == false)

        // And back — no local action in between.
        transport.remoteParticipants = [.init(identity: "@bob:matrix.org:BOB", isSpeaking: false, isAudioEnabled: true)]
        transportEvents.send(.participantsUpdated)
        #expect(session.participants.first { $0.userID == "@bob:matrix.org" }?.isAudioEnabled == true)
    }

    @Test
    func theListeningPickerDisappearsWhenTheDepartingAgentTakesItsTranslations() {
        // Brief 0063 Slice 4 defect: the produced-language union only
        // recomputed on subscribe/update events, so removing the agent
        // left a dead listening picker on screen.
        let updates = PassthroughSubject<MatrixRTCSessionUpdate, Never>()
        let rtcSession = makeSession()
        rtcSession.underlyingUpdates = updates.eraseToAnyPublisher()

        let transportEvents = PassthroughSubject<NativeCallTransportEvent, Never>()
        let transport = NativeCallTransportMock()
        transport.underlyingEvents = transportEvents.eraseToAnyPublisher()
        transport.localIdentity = "@alice:matrix.org:DEVICE"
        transport.underlyingIsLocalSpeaking = false
        transport.underlyingLocalConnectionQuality = .unknown
        transport.underlyingIsMicrophoneEnabled = true
        transport.underlyingIsCameraEnabled = false
        transport.remoteParticipants = [.init(identity: "agent-identity",
                                              isSpeaking: false,
                                              isAudioEnabled: true)]
        transport.remoteTracks = [.init(identity: "agent-identity",
                                        name: "lt:en:@bob:matrix.org",
                                        isSubscribed: true)]
        transport.setSubscriptionsAuthorizedIdentitiesIsTrackExcludedClosure = { _, _ in true }
        transport.setEncryptionKeyIndexIdentityClosure = { _, _, _ in }

        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)

        transportEvents.send(.participantsUpdated)
        #expect(session.listening.producedLanguages == ["en"])

        // The agent leaves: its publications vanish from the snapshot and
        // the disconnect event must recompute the union.
        transport.remoteParticipants = []
        transport.remoteTracks = []
        transportEvents.send(.participantDidDisconnect)
        #expect(session.listening.producedLanguages.isEmpty)
    }

    /// Brief 0066 rev. 2 — the DOCUMENT is the ducking order. With no lane
    /// published at all, a Live agent covering Bob marks him translated in
    /// the roster and sends the transport a duck for every device of his,
    /// synchronously; the listener's switch to the original voices lifts
    /// it the same way. The eyes and the ears agree, from the first word.
    @Test
    func aCoveringDocumentDucksTheSpeakerBeforeAnyLaneExists() {
        let updates = PassthroughSubject<MatrixRTCSessionUpdate, Never>()
        let rtcSession = makeSession()
        rtcSession.underlyingUpdates = updates.eraseToAnyPublisher()

        let transportEvents = PassthroughSubject<NativeCallTransportEvent, Never>()
        let transport = NativeCallTransportMock()
        transport.underlyingEvents = transportEvents.eraseToAnyPublisher()
        transport.localIdentity = "@alice:matrix.org:DEVICE"
        transport.underlyingIsLocalSpeaking = false
        transport.underlyingLocalConnectionQuality = .unknown
        transport.underlyingIsMicrophoneEnabled = true
        transport.underlyingIsCameraEnabled = false
        let booth = #"{"speaker_scope":"anyone","speaker_members":[],"target_languages":["en"]}"#
        let document = #"{"v":3,"agent":true,"lifecycle":"live","functions":[{"kind":"translation","active":true,"target_languages":["en"],"style":"simultaneous","booths":[\#(booth)]}]}"#
        transport.remoteParticipants = [.init(identity: "@bob:matrix.org:BOB", isSpeaking: false, isAudioEnabled: true),
                                        .init(identity: "@agent:matrix.org:AGENT", isSpeaking: false, isAudioEnabled: true,
                                              attributes: [SpiralAgentStateReader.attributeKey: document])]
        transport.remoteTracks = [.init(identity: "@bob:matrix.org:BOB", name: "", isSubscribed: true)]
        transport.setSubscriptionsAuthorizedIdentitiesIsTrackExcludedClosure = { _, _ in true }
        transport.setEncryptionKeyIndexIdentityClosure = { _, _, _ in }
        transport.setOriginalDuckingClosure = { _ in }

        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)
        session.setListeningChoice(.translation)

        let bob = MatrixRTCParticipant(userID: "@bob:matrix.org", deviceID: "BOB", identity: "@bob:matrix.org:BOB")
        let agent = MatrixRTCParticipant(userID: "@agent:matrix.org", deviceID: "AGENT", identity: "@agent:matrix.org:AGENT")
        updates.send(.participantsChanged([bob, agent]))
        transportEvents.send(.participantsUpdated)

        #expect(session.listening.channel == .everything)
        #expect(session.listening.translatedSpeakers == ["@bob:matrix.org": "en"])
        #expect(session.participants.first { $0.userID == "@bob:matrix.org" }?.isTranslated == true)
        #expect(session.participants.first { $0.userID == "@agent:matrix.org" }?.isTranslated == false)
        #expect(transport.setOriginalDuckingReceivedDucking?.identitiesBySpeaker == ["@bob:matrix.org": ["@bob:matrix.org:BOB"]])
        #expect(transport.setOriginalDuckingReceivedDucking?.floor == 0.15)

        // Original voices: nobody is translated or ducked any more.
        session.setListeningChoice(.original)
        #expect(session.listening.channel == .original)
        #expect(session.participants.allSatisfy { !$0.isTranslated })
        #expect(transport.setOriginalDuckingReceivedDucking?.identitiesBySpeaker.isEmpty == true)
    }

    @Test
    func theAgentStateDocumentIsTheLiveTranslationTruthPerAgent() {
        // Operator reports, both directions. (1) Disabling translation left
        // the picker/header ON because stale `lt:` publications outlive the
        // disable — the agent's `spiral.agent.state` document must win for
        // participants that publish one. (2) The controls API is
        // owner-gated, so a NON-OWNER has no REST truth at all; the state
        // document rides LiveKit attributes identically on every device,
        // and a participant without one keeps its tracks as the truth.
        let updates = PassthroughSubject<MatrixRTCSessionUpdate, Never>()
        let rtcSession = makeSession()
        rtcSession.underlyingUpdates = updates.eraseToAnyPublisher()

        let transportEvents = PassthroughSubject<NativeCallTransportEvent, Never>()
        let transport = NativeCallTransportMock()
        transport.underlyingEvents = transportEvents.eraseToAnyPublisher()
        transport.localIdentity = "@alice:matrix.org:DEVICE"
        transport.underlyingIsLocalSpeaking = false
        transport.underlyingLocalConnectionQuality = .unknown
        transport.underlyingIsMicrophoneEnabled = true
        transport.underlyingIsCameraEnabled = false
        transport.remoteParticipants = [.init(identity: "@agent:matrix.org:DEVICE", isSpeaking: false, isAudioEnabled: true),
                                        .init(identity: "@other-agent:matrix.org:DEVICE", isSpeaking: false, isAudioEnabled: true)]
        transport.remoteTracks = [.init(identity: "@agent:matrix.org:DEVICE",
                                        name: "lt:en:@bob:matrix.org",
                                        isSubscribed: true)]
        transport.setSubscriptionsAuthorizedIdentitiesIsTrackExcludedClosure = { _, _ in true }
        transport.setEncryptionKeyIndexIdentityClosure = { _, _, _ in }

        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)

        func agentDocument(languages: [String]?) -> [String: String] {
            guard let languages else { return [:] }
            let targets = languages.map { "\"\($0)\"" }.joined(separator: ",")
            let functions = languages.isEmpty
                ? "[]"
                : #"[{"kind":"translation","active":true,"target_languages":[\#(targets)],"style":"consecutive","booths":[{"speaker_scope":"anyone","speaker_members":[],"target_languages":[\#(targets)]}]}]"#
            return [SpiralAgentStateReader.attributeKey: #"{"v":4,"agent":true,"lifecycle":"live","functions":\#(functions)}"#]
        }
        func setAgentAttributes(_ agent: [String: String], other: [String: String] = [:]) {
            transport.remoteParticipants = [.init(identity: "@agent:matrix.org:DEVICE", isSpeaking: false, isAudioEnabled: true, attributes: agent),
                                            .init(identity: "@other-agent:matrix.org:DEVICE", isSpeaking: false, isAudioEnabled: true, attributes: other)]
            transportEvents.send(.participantsUpdated)
        }

        // No state document (its publish did not land): the track snapshot
        // drives the picker.
        transportEvents.send(.participantsUpdated)
        #expect(session.listening.producedLanguages == ["en"])

        // The document says translation is OFF: the picker empties even
        // though the stale publication is still on the SFU.
        setAgentAttributes(agentDocument(languages: []))
        #expect(session.listening.producedLanguages.isEmpty)

        // The document says Ukrainian: it wins over the English-only track
        // snapshot for the agent that published it.
        setAgentAttributes(agentDocument(languages: ["uk"]))
        #expect(session.listening.producedLanguages == ["uk"])

        // Two agents, one document: the documented agent contributes its
        // languages, the undocumented one its tracks.
        setAgentAttributes([:], other: agentDocument(languages: ["uk"]))
        #expect(session.listening.producedLanguages == ["en", "uk"])

        // Malformed document: fail-soft back to the tracks.
        setAgentAttributes([SpiralAgentStateReader.attributeKey: "not json"])
        #expect(session.listening.producedLanguages == ["en"])
    }

    @Test
    func aTransportPeerWaitsForKeysUntilTheirMediaKeyArrives() {
        let updates = PassthroughSubject<MatrixRTCSessionUpdate, Never>()
        let rtcSession = makeSession()
        rtcSession.underlyingUpdates = updates.eraseToAnyPublisher()

        let transport = NativeCallTransportMock()
        transport.underlyingEvents = Empty().eraseToAnyPublisher()
        transport.localIdentity = "@alice:matrix.org:DEVICE"
        transport.underlyingIsLocalSpeaking = false
        transport.underlyingLocalConnectionQuality = .unknown
        transport.underlyingIsMicrophoneEnabled = true
        transport.underlyingIsCameraEnabled = false
        transport.remoteParticipants = [.init(identity: "bob-identity",
                                              isSpeaking: false,
                                              isAudioEnabled: true)]
        transport.setSubscriptionsAuthorizedIdentitiesIsTrackExcludedClosure = { _, _ in true }
        transport.setEncryptionKeyIndexIdentityClosure = { _, _, _ in }

        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: true,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)

        let bob = MatrixRTCParticipant(userID: "@bob:matrix.org",
                                       deviceID: "BOB",
                                       identity: "bob-identity")
        updates.send(.participantsChanged([bob]))

        // The transport is up but the room is encrypted and no key arrived:
        // nothing bob sends can be decrypted yet.
        #expect(session.participants.first { !$0.isLocal }?.mediaState == .waitingForKeys)

        updates.send(.encryptionKeyReceived(.init(participantIdentity: "bob-identity",
                                                  index: 0,
                                                  key: Data(repeating: 1, count: 32))))

        #expect(session.participants.first { !$0.isLocal }?.mediaState == .connected)
        #expect(transport.setEncryptionKeyIndexIdentityCalled)
    }

    @Test
    func recordingIsDictaphoneNotAToggle() {
        // Live: armed and not stopped.
        let live = NativeAgentCenterArtifact(isEnabled: true, revision: 1, delivery: .pending, isStopped: false)
        #expect(live.isLive)
        // Stopped keeps `isEnabled` true on purpose — the captured part still
        // gets published. A toggle bound to `isEnabled` can never turn off;
        // `isLive` is what the UI must render and act on.
        let stopped = NativeAgentCenterArtifact(isEnabled: true, revision: 2, delivery: .pending, isStopped: true)
        #expect(!stopped.isLive)
        #expect(stopped.isEnabled)
        let off = NativeAgentCenterArtifact(isEnabled: false, revision: 0, delivery: .notArmed, isStopped: false)
        #expect(!off.isLive)
    }

    // MARK: - Phase 2 (G3): member profile names

    /// Matrix profile names feed the Agent Center's foreign rows; a member
    /// list update lands in the view state without any REST involvement.
    @Test
    func memberProfilesReachTheViewState() async throws {
        let profiles = CurrentValueSubject<[String: NativeCallMemberProfile], Never>([:])
        let viewModel = makeViewModel(rtcSession: makeSession(),
                                      isRoomEncrypted: true,
                                      memberProfiles: profiles.eraseToAnyPublisher())

        profiles.send(["@assistant-marta:spiral.md": .init(displayName: "Marta's Assistant")])

        try await waitFor {
            viewModel.context.viewState.memberProfiles["@assistant-marta:spiral.md"]?.displayName == "Marta's Assistant"
        }
    }

    @Test
    func roomNameAndAvatarStayLiveDuringTheCall() async throws {
        let initialAvatar = RoomAvatar.room(id: "!room:matrix.org", name: "Before", avatarURL: nil)
        let updatedAvatar = RoomAvatar.room(id: "!room:matrix.org", name: "After", avatarURL: .mockMXCAvatar)
        let presentation = CurrentValueSubject<NativeCallRoomPresentation, Never>(.init(name: "Before", avatar: initialAvatar))
        let viewModel = makeViewModel(rtcSession: makeSession(),
                                      isRoomEncrypted: true,
                                      roomPresentation: presentation.eraseToAnyPublisher())

        presentation.send(.init(name: "After", avatar: updatedAvatar))

        try await waitFor {
            viewModel.context.viewState.roomName == "After"
                && viewModel.context.viewState.roomAvatar == updatedAvatar
        }
    }

    // MARK: - Helpers

    private func makeSession() -> MatrixRTCSessionMock {
        let rtcSession = MatrixRTCSessionMock()
        rtcSession.underlyingOwnIdentity = "@alice:matrix.org:DEVICE"
        rtcSession.underlyingUpdates = Empty().eraseToAnyPublisher()
        rtcSession.joinEncryptMediaNotificationMediaReturnValue = .success(())
        rtcSession.setMediaReturnValue = .success(())
        rtcSession.rtcNotificationEventIDReturnValue = "$ring:matrix.org"
        // Transport authorization is expected to fail in the test environment;
        // what matters here is whether it is attempted at all.
        rtcSession.transportCredentialsReturnValue = .failure(.roomInvalid)
        rtcSession.leaveReturnValue = .success(())
        rtcSession.membershipsReturnValue = .success([.init(userID: "@bob:matrix.org", deviceID: "BOB", identity: "@bob:matrix.org:BOB")])
        return rtcSession
    }

    private func makeNativeSession(rtcSession: MatrixRTCSessionMock,
                                   isRoomEncrypted: Bool = true,
                                   media: NativeCallMedia = .audio,
                                   scope: NativeCallScope = .direct) -> NativeCallSession {
        NativeCallSession(rtcSession: rtcSession,
                          isRoomEncrypted: isRoomEncrypted,
                          notifyRoom: true,
                          configuration: .init(media: media, scope: scope))
    }

    /// A transport that connects, publishes and reports nothing of its own —
    /// the neutral background the microphone and teardown tests act against.
    private func makeTransportMock() -> NativeCallTransportMock {
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

    /// Start and teardown bounds small enough for a test to wait them out — the
    /// shipped ones are seconds, sized for a slow network rather than a wedge.
    private func makeBoundedSession(rtcSession: MatrixRTCSessionMock,
                                    transport: NativeCallTransportProtocol) -> NativeCallSession {
        NativeCallSession(rtcSession: rtcSession,
                          isRoomEncrypted: false,
                          notifyRoom: false,
                          configuration: .init(media: .audio, scope: .direct),
                          transport: transport,
                          joinTimeout: .milliseconds(50),
                          credentialsTimeout: .milliseconds(50),
                          transportConnectTimeout: .milliseconds(50),
                          mediaPublishTimeout: .milliseconds(50),
                          leaveTimeout: .milliseconds(50),
                          transportDisconnectTimeout: .milliseconds(50))
    }

    private func makeViewModel(rtcSession: MatrixRTCSessionMock,
                               isRoomEncrypted: Bool,
                               notifyRoom: Bool = true,
                               isVideoCall: Bool = false,
                               callKitService: CallKitServiceProtocol = CallKitServiceMock(.init()),
                               transport: NativeCallTransportProtocol? = nil,
                               appMediator: AppMediatorProtocol = AppMediatorMock(.init()),
                               haptics: NativeCallHaptics = .none,
                               memberProfiles: AnyPublisher<[String: NativeCallMemberProfile], Never> = Empty().eraseToAnyPublisher(),
                               roomPresentation: AnyPublisher<NativeCallRoomPresentation, Never> = Empty().eraseToAnyPublisher()) -> NativeCallScreenViewModel {
        NativeCallScreenViewModel(session: NativeCallSession(rtcSession: rtcSession,
                                                             isRoomEncrypted: isRoomEncrypted,
                                                             notifyRoom: notifyRoom,
                                                             configuration: .init(media: isVideoCall ? .video : .audio, scope: .direct),
                                                             transport: transport),
                                  callKitService: callKitService,
                                  agentCenter: NativeAgentCenterController(agentPlatformService: nil,
                                                                           roomID: "!room:matrix.org",
                                                                           roomMemberMxids: { [] },
                                                                           inviteAgent: { _ in false }),
                                  appMediator: appMediator,
                                  haptics: haptics,
                                  isVideoCall: isVideoCall,
                                  roomID: "!room:matrix.org",
                                  roomName: "Native call",
                                  memberProfiles: memberProfiles,
                                  roomPresentation: roomPresentation)
    }

    /// A transport that refuses a subscription walk must be walked again:
    /// recording the plan as applied over a failed UNsubscribe keeps
    /// playing media the policy revoked (fail-closed needs the retry).
    @Test
    func aFailedSubscriptionWalkIsRetriedUntilTheTransportAccepts() async throws {
        let rtcSession = makeSession()
        let updates = PassthroughSubject<MatrixRTCSessionUpdate, Never>()
        rtcSession.underlyingUpdates = updates.eraseToAnyPublisher()

        let transport = NativeCallTransportMock()
        transport.underlyingEvents = Empty().eraseToAnyPublisher()
        transport.localIdentity = "@alice:matrix.org:DEVICE"
        transport.underlyingIsLocalSpeaking = false
        transport.underlyingLocalConnectionQuality = .unknown
        transport.underlyingIsMicrophoneEnabled = true
        transport.underlyingIsCameraEnabled = false
        transport.remoteParticipants = [.init(identity: "@bob:matrix.org:BOB", isSpeaking: false, isAudioEnabled: true)]
        transport.remoteTracks = []
        transport.setEncryptionKeyIndexIdentityClosure = { _, _, _ in }
        // The FIRST walk fails, every later one succeeds.
        transport.setSubscriptionsAuthorizedIdentitiesIsTrackExcludedClosure = { [weak transport] _, _ in
            await MainActor.run { (transport?.setSubscriptionsAuthorizedIdentitiesIsTrackExcludedCallsCount ?? 0) > 1 }
        }

        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)

        updates.send(.participantsChanged([.init(userID: "@bob:matrix.org", deviceID: "BOB", identity: "@bob:matrix.org:BOB")]))

        try await waitFor(attempts: 400) { transport.setSubscriptionsAuthorizedIdentitiesIsTrackExcludedCallsCount >= 2 }
        // Brief 0066: the ducking order rides EVERY walk, the refused one
        // included — gating it on `applied` held a covered microphone at
        // unity under a speaking lane for the whole backoff.
        #expect(transport.setOriginalDuckingCallsCount >= 2)
        withExtendedLifetime(session) { }
    }

    private func waitForJoin(on rtcSession: MatrixRTCSessionMock) async throws {
        try await waitFor { rtcSession.joinEncryptMediaNotificationMediaCalled }
    }

    private func waitFor(attempts: Int = 200, _ condition: @escaping () -> Bool) async throws {
        for _ in 0..<attempts {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }

        Issue.record("Timed out waiting for the expected state")
    }
}

/// Records the session's state transitions in order so tests can assert on the
/// sequence, not just the final value.
@MainActor
private final class NativeCallSessionDelegateSpy: NativeCallSessionDelegate {
    private(set) var states: [NativeCallSessionState] = []
    private(set) var ringNotificationIDs: [String] = []
    private(set) var activeVideoStates: [Bool] = []
    private(set) var agentStateChanges = 0
    private(set) var agentClaims: [NativeCallAgentClaims] = []

    func nativeCallSession(_ session: NativeCallSession, didChangeState state: NativeCallSessionState) {
        states.append(state)
    }

    func nativeCallSession(_ session: NativeCallSession, didChangeVideoTiles tiles: [NativeCallVideoTile]) { }

    func nativeCallSession(_ session: NativeCallSession,
                           didChangeActiveVideo hasActiveVideo: Bool,
                           isSpeakerEnabled: Bool) {
        activeVideoStates.append(hasActiveVideo)
    }

    func nativeCallSession(_ session: NativeCallSession, didChangeParticipants participants: [NativeCallParticipant]) { }

    func nativeCallSession(_ session: NativeCallSession, didSendRingNotification eventID: String) {
        ringNotificationIDs.append(eventID)
    }

    func nativeCallSession(_ session: NativeCallSession, didChangeListening listening: NativeCallListeningState) { }

    func nativeCallSession(_ session: NativeCallSession, didChangeConnectionQuality quality: NativeCallConnectionQuality) { }

    func nativeCallSessionDidChangeAgentState(_ session: NativeCallSession) {
        agentStateChanges += 1
    }

    func nativeCallSession(_ session: NativeCallSession, didChangeAgentClaims claims: NativeCallAgentClaims) {
        agentClaims.append(claims)
    }
}

struct MatrixRTCSessionProxyTests {
    @Test
    func silentAudioJoinAdvertisesItsIntent() async throws {
        let session = MatrixRtcSessionSpy()
        let proxy = MatrixRTCSessionProxy(session: session)

        let result = await proxy.join(encryptMedia: true, notification: nil, media: .audio)

        _ = try result.get()
        let configuration = try #require(session.joinConfiguration)
        #expect(configuration.callIntent == .audio)
        if configuration.notificationType != nil {
            Issue.record("A silent join must not notify the room again")
        }
    }

    @Test
    func mediaIntentCanChangeAfterJoining() async throws {
        let session = MatrixRtcSessionSpy()
        let proxy = MatrixRTCSessionProxy(session: session)

        _ = try await proxy.setMedia(.video).get()

        #expect(session.updatedCallIntent == .video)
    }
}

private final class MatrixRtcSessionSpy: MatrixRustSDK.MatrixRtcSessionProtocol, @unchecked Sendable {
    var joinConfiguration: MatrixRtcJoinConfiguration?
    var updatedCallIntent: MatrixRtcCallIntent?

    func isJoined() async -> Bool {
        false
    }

    func join(configuration: MatrixRtcJoinConfiguration) async throws {
        joinConfiguration = configuration
    }

    func updateCallIntent(callIntent: MatrixRtcCallIntent) async throws {
        updatedCallIntent = callIntent
    }

    func leave() async throws { }

    func memberships() async throws -> [MatrixRtcMembership] {
        []
    }

    func ownIdentity() -> String {
        "@alice:example.org:DEVICE"
    }

    func rtcNotificationEventId() async -> String? {
        nil
    }

    func subscribe(listener: MatrixRtcSessionListener) -> TaskHandle {
        TaskHandleSpy()
    }

    func transportCredentials() async throws -> MatrixRtcTransportCredentials {
        .init(url: "wss://rtc.example.org", token: "token", identity: ownIdentity())
    }
}

private final nonisolated class TaskHandleSpy: TaskHandle, @unchecked Sendable {
    required init(unsafeFromHandle handle: UInt64) {
        super.init(unsafeFromHandle: handle)
    }

    init() {
        super.init(noHandle: .init())
    }

    override func cancel() { }
}

// MARK: - Lifecycle regressions (pre-merge audit, 2026-08-19)

extension NativeCallScreenViewModelTests {
    /// `@CancellableTask` cancels on assignment, and the timeout bodies call
    /// `stop` themselves — clearing the handle from inside its own task
    /// cancelled that task, so the busy cadence was cut off within
    /// microseconds and the Matrix leave ran under cancellation.
    @Test
    func anUnansweredTimeoutTearsDownWithoutCancellingItself() async throws {
        let rtcSession = makeSession()
        // The call has to reach `ringing` for the timeout to be the thing that
        // ends it, so the transport handshake must succeed here.
        rtcSession.transportCredentialsReturnValue = .success(.init(url: "https://sfu.example.com",
                                                                    token: "token",
                                                                    identity: "@alice:matrix.org:DEVICE"))
        let transport = NativeCallTransportMock()
        transport.underlyingEvents = Empty().eraseToAnyPublisher()
        transport.localIdentity = "@alice:matrix.org:DEVICE"
        transport.underlyingIsLocalSpeaking = false
        transport.underlyingLocalConnectionQuality = .unknown
        transport.underlyingIsMicrophoneEnabled = true
        transport.underlyingIsCameraEnabled = false
        transport.setSubscriptionsAuthorizedIdentitiesIsTrackExcludedClosure = { _, _ in true }

        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: true,
                                        configuration: .init(media: .audio, scope: .direct),
                                        transport: transport,
                                        unansweredRingDuration: .milliseconds(1))

        await session.start()
        try await Task.sleep(for: .seconds(3))

        // The teardown ran to completion: leaving is what the peer observes,
        // and it must not be skipped by a cancelled task.
        #expect(session.state == .ended(reason: .unanswered))
        #expect(rtcSession.leaveCallsCount >= 1)
    }

    /// A late `didReconnect` must not resurrect a call that already ended,
    /// and must never promote a ringing call on the peer's behalf.
    @Test
    func aLateReconnectNeitherResurrectsNorAnswersTheCall() async {
        let rtcSession = makeSession()
        let transportEvents = PassthroughSubject<NativeCallTransportEvent, Never>()
        let transport = NativeCallTransportMock()
        transport.underlyingEvents = transportEvents.eraseToAnyPublisher()
        transport.localIdentity = "@alice:matrix.org:DEVICE"
        transport.underlyingIsLocalSpeaking = false
        transport.underlyingLocalConnectionQuality = .unknown
        transport.underlyingIsMicrophoneEnabled = true
        transport.underlyingIsCameraEnabled = false
        transport.setSubscriptionsAuthorizedIdentitiesIsTrackExcludedClosure = { _, _ in true }

        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: true,
                                        configuration: .init(media: .audio, scope: .direct),
                                        transport: transport)

        await session.stop(reason: .userHungUp)
        #expect(session.state == .ended(reason: .userHungUp))

        transportEvents.send(.didReconnect)
        #expect(session.state == .ended(reason: .userHungUp), "an ended call must stay ended")
    }

    /// Every `start` failure must release the CallKit audio preparation:
    /// `prepareForCallKit` disables LiveKit's automatic configuration
    /// process-wide, so a leaked one silences every later call.
    @Test
    func aFailedStartLeavesTheMatrixSessionAndReleasesAudio() async {
        let rtcSession = makeSession()
        rtcSession.joinEncryptMediaNotificationMediaReturnValue = .failure(.roomInvalid)
        let transport = NativeCallTransportMock()
        transport.underlyingEvents = Empty().eraseToAnyPublisher()
        transport.localIdentity = "@alice:matrix.org:DEVICE"
        transport.underlyingIsLocalSpeaking = false
        transport.underlyingLocalConnectionQuality = .unknown
        transport.underlyingIsMicrophoneEnabled = true
        transport.underlyingIsCameraEnabled = false
        transport.setSubscriptionsAuthorizedIdentitiesIsTrackExcludedClosure = { _, _ in true }

        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: true,
                                        configuration: .init(media: .audio, scope: .direct),
                                        transport: transport)
        await session.start()

        guard case .ended(.failed) = session.state else {
            Issue.record("a failed join must end the call, got \(session.state)")
            return
        }
        // The join failed, so there is nothing connected to disconnect — but
        // the Matrix session must still be left rather than abandoned.
        #expect(rtcSession.leaveCallsCount == 1)
    }

    // MARK: - CallKit mute results

    /// A mute the media engine REFUSES has to reach CallKit as a failure.
    /// Fulfilling the action regardless left the system call UI showing
    /// "muted" over a microphone that was still publishing.
    @Test
    func aRefusedCallKitMuteAnswersWithFailure() async throws {
        let rtcSession = makeSession()
        let transport = makeTransportMock()
        transport.setMicrophoneEnabledClosure = { _ in
            throw NativeCallTransportError.microphoneUnavailable("the device is busy")
        }

        let serviceActions = PassthroughSubject<CallKitServiceAction, Never>()
        let callKitService = CallKitServiceMock(.init())
        callKitService.actions = serviceActions.eraseToAnyPublisher()

        let viewModel = makeViewModel(rtcSession: rtcSession,
                                      isRoomEncrypted: false,
                                      callKitService: callKitService,
                                      transport: transport)

        var outcomes: [Bool] = []
        serviceActions.send(.setAudioEnabled(false,
                                             roomID: "!room:matrix.org",
                                             reply: .init { outcomes.append($0) }))

        try await waitFor { !outcomes.isEmpty }
        #expect(outcomes == [false])
        // ...and the in-app control still says what the engine does.
        #expect(viewModel.context.viewState.isMicrophoneEnabled)
    }

    @Test
    func anAcceptedCallKitMuteAnswersWithSuccess() async throws {
        let rtcSession = makeSession()
        let transport = makeTransportMock()
        transport.setMicrophoneEnabledClosure = { enabled in
            transport.underlyingIsMicrophoneEnabled = enabled
        }

        let serviceActions = PassthroughSubject<CallKitServiceAction, Never>()
        let callKitService = CallKitServiceMock(.init())
        callKitService.actions = serviceActions.eraseToAnyPublisher()

        let viewModel = makeViewModel(rtcSession: rtcSession,
                                      isRoomEncrypted: false,
                                      callKitService: callKitService,
                                      transport: transport)

        var outcomes: [Bool] = []
        serviceActions.send(.setAudioEnabled(false,
                                             roomID: "!room:matrix.org",
                                             reply: .init { outcomes.append($0) }))

        try await waitFor { !outcomes.isEmpty }
        #expect(outcomes == [true])
        #expect(!viewModel.context.viewState.isMicrophoneEnabled)
    }

    /// The in-app button follows the same rule: a refused mute must leave the
    /// control showing a live microphone, never a muted one.
    @Test
    func aRefusedInAppMuteLeavesTheControlShowingALiveMicrophone() async throws {
        let rtcSession = makeSession()
        let transport = makeTransportMock()
        transport.setMicrophoneEnabledClosure = { _ in
            throw NativeCallTransportError.microphoneUnavailable("the device is busy")
        }

        let viewModel = makeViewModel(rtcSession: rtcSession, isRoomEncrypted: false, transport: transport)

        viewModel.context.send(viewAction: .toggleMicrophone)

        try await waitFor { transport.setMicrophoneEnabledCalled }
        #expect(viewModel.context.viewState.isMicrophoneEnabled)
    }

    /// Audit 2026-09-05 (P2): the in-app button goes through CallKit when
    /// CallKit will carry it — the change then comes back as
    /// `.setAudioEnabled` — so the system UI never shows a state the
    /// microphone does not have. The screen must not ALSO apply it: that
    /// would be two writes racing for one microphone.
    @Test
    func anInAppMuteCallKitAcceptsIsNotAppliedTwice() async throws {
        let rtcSession = makeSession()
        let transport = makeTransportMock()
        let callKitService = CallKitServiceMock(.init())
        callKitService.requestAudioEnabledRoomIDReturnValue = true
        let viewModel = makeViewModel(rtcSession: rtcSession,
                                      isRoomEncrypted: false,
                                      callKitService: callKitService,
                                      transport: transport)

        viewModel.context.send(viewAction: .toggleMicrophone)

        try await waitFor { callKitService.requestAudioEnabledRoomIDCalled }
        let request = try #require(callKitService.requestAudioEnabledRoomIDReceivedArguments)
        #expect(request.enabled == false, "the button asked for a mute")
        #expect(request.roomID == "!room:matrix.org")
        try await Task.sleep(for: .milliseconds(50))
        #expect(!transport.setMicrophoneEnabledCalled,
                "CallKit carries the change; it arrives through the action, not from the button")
    }

    /// When CallKit will not carry it (no live CallKit call, a refused
    /// transaction, the simulator), the button still mutes — directly.
    @Test
    func anInAppMuteCallKitDeclinesIsAppliedDirectly() async throws {
        let rtcSession = makeSession()
        let transport = makeTransportMock()
        transport.setMicrophoneEnabledClosure = { enabled in
            transport.underlyingIsMicrophoneEnabled = enabled
        }
        let callKitService = CallKitServiceMock(.init())
        callKitService.requestAudioEnabledRoomIDReturnValue = false
        let viewModel = makeViewModel(rtcSession: rtcSession,
                                      isRoomEncrypted: false,
                                      callKitService: callKitService,
                                      transport: transport)

        viewModel.context.send(viewAction: .toggleMicrophone)

        try await waitFor { transport.setMicrophoneEnabledCalled }
        #expect(transport.setMicrophoneEnabledReceivedEnabled == false)
        #expect(!viewModel.context.viewState.isMicrophoneEnabled)
    }

    // MARK: - Haptics (Brief 0068 Slice 3)

    /// One tap on connect, one on end — and reconnecting does not tap again.
    @Test
    func theCallTapsOnceOnConnectAndOnceOnEnd() {
        var connects = 0
        var ends = 0
        let rtcSession = makeSession()
        let viewModel = makeViewModel(rtcSession: rtcSession,
                                      isRoomEncrypted: false,
                                      haptics: NativeCallHaptics(connected: { connects += 1 }, ended: { ends += 1 }))
        let session = makeNativeSession(rtcSession: rtcSession)

        viewModel.nativeCallSession(session, didChangeState: .connected)
        viewModel.nativeCallSession(session, didChangeState: .reconnecting)
        viewModel.nativeCallSession(session, didChangeState: .connected)
        #expect(connects == 1)
        #expect(ends == 0)

        viewModel.nativeCallSession(session, didChangeState: .ended(reason: .userHungUp))
        #expect(ends == 1)
    }

    // MARK: - Call waiting (Brief 0068 Slice 2)

    /// An outgoing call still ringing cannot be held — its ringback would
    /// keep the engine parked and the other call silent. Being held while
    /// ringing means the user answered somebody else: the ring ends.
    @Test
    func beingHeldWhileRingingEndsTheOutgoingRing() async throws {
        let rtcSession = makeSession()
        let serviceActions = PassthroughSubject<CallKitServiceAction, Never>()
        let callKitService = CallKitServiceMock(.init())
        callKitService.actions = serviceActions.eraseToAnyPublisher()
        let viewModel = makeViewModel(rtcSession: rtcSession, isRoomEncrypted: false, callKitService: callKitService)
        let session = makeNativeSession(rtcSession: rtcSession)
        viewModel.nativeCallSession(session, didChangeState: .ringing)

        var dismissed = false
        let cancellable = viewModel.actions.sink { if case .dismiss = $0 { dismissed = true } }
        serviceActions.send(.setCallHeld(true, roomID: "!room:matrix.org"))
        try await waitFor { dismissed }
        _ = cancellable
    }

    /// The active screen names the parked call; the parked screen never
    /// shows itself as "held".
    @Test
    func theHeldCallPillNamesTheOtherCallOnly() async throws {
        let held = CurrentValueSubject<CallKitHeldCall?, Never>(nil)
        let callKitService = CallKitServiceMock(.init())
        callKitService.heldCallPublisher = held.asCurrentValuePublisher()
        let active = makeViewModel(rtcSession: makeSession(), isRoomEncrypted: false, callKitService: callKitService)

        held.send(CallKitHeldCall(roomID: "!other:matrix.org", displayName: "Other"))
        try await waitFor { active.context.viewState.heldCall?.displayName == "Other" }

        // The parked screen's own room in the held slot: nothing to show.
        held.send(CallKitHeldCall(roomID: "!room:matrix.org", displayName: "Me"))
        try await waitFor { active.context.viewState.heldCall == nil }

        active.context.send(viewAction: .swapCalls)
        try await waitFor { callKitService.swapCallsCalled }
    }

    // MARK: - Idle timer (screen stays awake while video is live)

    /// 2026-09-06: a video call dimmed and locked the phone on the system
    /// timeout, and iOS then stopped the camera. The WebView stack had kept
    /// the screen awake as a side effect; the native one must do it on
    /// purpose — and let go on every exit.
    @Test
    func aVideoCallHoldsTheIdleTimerAndReleasesItWhenVideoStops() {
        let appMediator = AppMediatorMock(.init())
        let rtcSession = makeSession()
        let viewModel = makeViewModel(rtcSession: rtcSession,
                                      isRoomEncrypted: false,
                                      isVideoCall: true,
                                      appMediator: appMediator)
        let session = makeNativeSession(rtcSession: rtcSession)

        // An outgoing video call holds the screen from its connecting preview.
        #expect(appMediator.setIdleTimerDisabledReceivedInvocations == [true])

        // All cameras dark → audio stage → the screen may sleep again.
        viewModel.nativeCallSession(session, didChangeActiveVideo: false, isSpeakerEnabled: true)
        #expect(appMediator.setIdleTimerDisabledReceivedInvocations == [true, false])

        // A camera returns → held again; a repeat report changes nothing.
        viewModel.nativeCallSession(session, didChangeActiveVideo: true, isSpeakerEnabled: true)
        viewModel.nativeCallSession(session, didChangeActiveVideo: true, isSpeakerEnabled: true)
        #expect(appMediator.setIdleTimerDisabledReceivedInvocations == [true, false, true])
    }

    @Test
    func anAudioCallNeverHoldsTheIdleTimer() {
        let appMediator = AppMediatorMock(.init())
        let rtcSession = makeSession()
        let viewModel = makeViewModel(rtcSession: rtcSession, isRoomEncrypted: false, appMediator: appMediator)
        let session = makeNativeSession(rtcSession: rtcSession)
        viewModel.nativeCallSession(session, didChangeState: .connected)

        #expect(appMediator.setIdleTimerDisabledReceivedInvocations.isEmpty,
                "an audio call dims like the Phone app; CallKit keeps it alive")
    }

    /// Every exit releases the flag: the ended state, `stop()`, and the
    /// view model going away. A flag left standing is a screen that never
    /// sleeps after the call.
    @Test
    func theIdleTimerIsReleasedOnEveryExit() {
        let appMediator = AppMediatorMock(.init())
        let rtcSession = makeSession()
        let session = makeNativeSession(rtcSession: rtcSession)

        var viewModel: NativeCallScreenViewModel? = makeViewModel(rtcSession: rtcSession,
                                                                  isRoomEncrypted: false,
                                                                  isVideoCall: true,
                                                                  appMediator: appMediator)
        viewModel?.nativeCallSession(session, didChangeState: .ended(reason: .userHungUp))
        #expect(appMediator.setIdleTimerDisabledReceivedInvocations.last == false, "ended releases")

        viewModel = makeViewModel(rtcSession: rtcSession,
                                  isRoomEncrypted: false,
                                  isVideoCall: true,
                                  appMediator: appMediator)
        #expect(appMediator.setIdleTimerDisabledReceivedInvocations.last == true)
        viewModel?.stop()
        #expect(appMediator.setIdleTimerDisabledReceivedInvocations.last == false, "stop releases")

        viewModel = makeViewModel(rtcSession: rtcSession,
                                  isRoomEncrypted: false,
                                  isVideoCall: true,
                                  appMediator: appMediator)
        #expect(appMediator.setIdleTimerDisabledReceivedInvocations.last == true)
        viewModel = nil
        #expect(appMediator.setIdleTimerDisabledReceivedInvocations.last == false, "deinit releases")
    }

    // MARK: - Bounded teardown

    /// `stop` used to await the Matrix leave with no bound. One wedged leave
    /// left `isStopping` true and the state short of `.ended` forever: the
    /// screen never dismissed, the CallKit call stayed live and no further
    /// call could be started.
    /// Audit wave 8 — a leave that FAILS is as bad for peers as one that
    /// wedges, and it used to be invisible.
    ///
    /// `leave()` returned `Void` and swallowed its error, and the bound around
    /// it reports false only on a TIMEOUT — so a fast failure read as a clean
    /// hang-up. The membership then stood for its whole expiry while every
    /// peer kept rendering this device in a call it had left, and a group call
    /// whose last human left never ended for the agents still in it.
    @Test
    func aFailedMatrixLeaveStillEndsTheCall() async {
        let rtcSession = makeSession()
        rtcSession.leaveReturnValue = .failure(.roomInvalid)

        let session = makeBoundedSession(rtcSession: rtcSession, transport: makeTransportMock())

        await session.stop(reason: .userHungUp)

        // The call must still end locally: the user hung up, and refusing to
        // let go of the screen because the server said no is worse than the
        // standing membership.
        guard case .ended = session.state else {
            Issue.record("a failed leave must not strand the call: \(session.state)")
            return
        }
        #expect(rtcSession.leaveCallsCount == 1)
    }

    @Test
    func aWedgedMatrixLeaveStillEndsTheCall() async {
        let rtcSession = makeSession()
        rtcSession.leaveClosure = {
            try? await Task.sleep(for: .seconds(30))
            return .success(())
        }

        let session = makeBoundedSession(rtcSession: rtcSession, transport: makeTransportMock())

        await session.stop(reason: .userHungUp)

        #expect(session.state == .ended(reason: .userHungUp))
    }

    /// The same for the transport half, which runs after the leave — a wedge
    /// there stranded the call just as completely.
    @Test
    func aWedgedTransportDisconnectStillEndsTheCall() async {
        let rtcSession = makeSession()
        rtcSession.transportCredentialsReturnValue = .success(.init(url: "https://sfu.example.com",
                                                                    token: "token",
                                                                    identity: "@alice:matrix.org:DEVICE"))
        let transport = makeTransportMock()
        transport.disconnectClosure = { try? await Task.sleep(for: .seconds(30)) }

        let session = makeBoundedSession(rtcSession: rtcSession, transport: transport)

        await session.start()
        await session.stop(reason: .userHungUp)

        #expect(session.state == .ended(reason: .userHungUp))
        #expect(rtcSession.leaveCallsCount == 1)
    }

    /// `failStart` carries the same risk: a wedged leave there left the screen
    /// on "connecting" with no alert, no dismissal and no way out.
    @Test
    func aWedgedMatrixLeaveStillFailsTheStart() async {
        let rtcSession = makeSession()
        rtcSession.joinEncryptMediaNotificationMediaReturnValue = .failure(.roomInvalid)
        rtcSession.leaveClosure = {
            try? await Task.sleep(for: .seconds(30))
            return .success(())
        }

        let session = makeBoundedSession(rtcSession: rtcSession, transport: makeTransportMock())

        await session.start()

        guard case .ended(.failed) = session.state else {
            Issue.record("a wedged leave must still fail the start, got \(session.state)")
            return
        }
    }

    // MARK: - Bounded start

    // Bounding teardown alone was not enough: `failStart` is only reachable
    // once the start's own external awaits have returned, so a wedge in any of
    // them left the screen on "connecting" forever — no alert, no dismissal, no
    // way out. Each step below now fails the call the ordinary way instead.

    /// The MatrixRTC join: a state-event round trip through the SDK.
    @Test
    func aWedgedJoinFailsTheStartInsteadOfHangingOnConnecting() async {
        let rtcSession = makeSession()
        rtcSession.joinEncryptMediaNotificationMediaClosure = { _, _, _ in
            try? await Task.sleep(for: .seconds(30))
            return .success(())
        }

        let session = makeBoundedSession(rtcSession: rtcSession, transport: makeTransportMock())

        await session.start()

        #expect(session.state == .ended(reason: .failed(.couldNotJoin)))
    }

    /// The SFU authorization round trip.
    @Test
    func aWedgedCredentialsRequestFailsTheStart() async {
        let rtcSession = makeSession()
        rtcSession.transportCredentialsClosure = {
            try? await Task.sleep(for: .seconds(30))
            return .failure(.roomInvalid)
        }

        let session = makeBoundedSession(rtcSession: rtcSession, transport: makeTransportMock())

        await session.start()

        #expect(session.state == .ended(reason: .failed(.serverUnreachable)))
    }

    /// Reaching the SFU: signalling, then ICE and DTLS.
    @Test
    func aWedgedTransportConnectFailsTheStart() async {
        let rtcSession = makeSession()
        rtcSession.transportCredentialsReturnValue = .success(.init(url: "https://sfu.example.com",
                                                                    token: "token",
                                                                    identity: "@alice:matrix.org:DEVICE"))
        let transport = makeTransportMock()
        transport.connectUrlTokenClosure = { _, _ in try? await Task.sleep(for: .seconds(30)) }

        let session = makeBoundedSession(rtcSession: rtcSession, transport: transport)

        await session.start()

        #expect(session.state == .ended(reason: .failed(.couldNotConnect)))
    }

    /// Publishing the microphone. The transport is connected by now, so the
    /// failure path also has to disconnect it — a room left connected is a
    /// ghost membership on the SFU.
    @Test
    func aWedgedMicrophonePublishFailsTheStartAndDisconnects() async {
        let rtcSession = makeSession()
        rtcSession.transportCredentialsReturnValue = .success(.init(url: "https://sfu.example.com",
                                                                    token: "token",
                                                                    identity: "@alice:matrix.org:DEVICE"))
        let transport = makeTransportMock()
        transport.setMicrophoneEnabledClosure = { _ in try? await Task.sleep(for: .seconds(30)) }

        let session = makeBoundedSession(rtcSession: rtcSession, transport: transport)

        await session.start()

        #expect(session.state == .ended(reason: .failed(.couldNotConnect)))
        #expect(transport.disconnectCalled)
        #expect(rtcSession.leaveCallsCount == 1)
    }

    /// A start step that wedges past the user's patience must not re-end the
    /// call they already hung up: the reason on screen belongs to whoever ended
    /// it first.
    @Test
    func aStartFailureLandingAfterTheUserHungUpLeavesTheEndReasonAlone() async {
        let rtcSession = makeSession()
        rtcSession.joinEncryptMediaNotificationMediaClosure = { _, _, _ in
            try? await Task.sleep(for: .seconds(30))
            return .success(())
        }

        let session = makeBoundedSession(rtcSession: rtcSession, transport: makeTransportMock())

        async let started: Void = session.start()
        await session.stop(reason: .userHungUp)
        await started

        #expect(session.state == .ended(reason: .userHungUp))
    }
}

// MARK: - Subscription plan convergence (audit B8)

extension NativeCallScreenViewModelTests {
    /// A plan arriving while the previous one is being applied used to cancel
    /// the in-flight walk, while the session had ALREADY recorded that walk as
    /// applied — so the transport kept half the old subscriptions and the
    /// guard skipped every correction afterwards. An unsubscribe that never
    /// happens keeps media audible that the listener asked to mute, so the
    /// worker must converge on the newest plan instead.
    @Test
    func rapidPlanChangesConvergeOnTheNewestPlan() async throws {
        let updates = PassthroughSubject<MatrixRTCSessionUpdate, Never>()
        let transportEvents = PassthroughSubject<NativeCallTransportEvent, Never>()
        let rtcSession = makeSession()
        rtcSession.underlyingUpdates = updates.eraseToAnyPublisher()

        let transport = NativeCallTransportMock()
        transport.underlyingEvents = transportEvents.eraseToAnyPublisher()
        transport.localIdentity = "@alice:matrix.org:DEVICE"
        transport.underlyingIsLocalSpeaking = false
        transport.underlyingLocalConnectionQuality = .unknown
        transport.underlyingIsMicrophoneEnabled = true
        transport.underlyingIsCameraEnabled = false
        transport.setEncryptionKeyIndexIdentityClosure = { _, _, _ in }

        // Every application is slow enough for the next plan to land mid-walk.
        let applied = RecordingBox<[Set<String>]>([])
        transport.setSubscriptionsAuthorizedIdentitiesIsTrackExcludedClosure = { identities, _ in
            try? await Task.sleep(for: .milliseconds(20))
            applied.value.append(identities)
            return true
        }

        let session = NativeCallSession(rtcSession: rtcSession,
                                        isRoomEncrypted: false,
                                        notifyRoom: false,
                                        configuration: .init(media: .audio, scope: .group),
                                        transport: transport)

        // Three plans in quick succession: one peer, then two, then three.
        // Media authorization needs the membership, so both sides grow.
        for count in 1...3 {
            updates.send(.participantsChanged((1...count).map {
                .init(userID: "@peer\($0):matrix.org", deviceID: "D\($0)", identity: "@peer\($0):matrix.org:D\($0)")
            }))
            transport.remoteParticipants = (1...count).map {
                .init(identity: "@peer\($0):matrix.org:D\($0)", isSpeaking: false, isAudioEnabled: true)
            }
            transportEvents.send(.participantsUpdated)
        }

        try await Task.sleep(for: .milliseconds(400))

        // Whatever the intermediate walks were, the LAST application must be
        // the newest plan — the transport is never left on a stale one.
        let last = try #require(applied.value.last)
        #expect(last.count == 3, "the worker must converge on the newest plan, got \(last)")
    }
}

/// Minimal box so a `@Sendable` transport closure can record what it saw.
private final class RecordingBox<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) {
        self.value = value
    }
}
