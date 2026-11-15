//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import MatrixRustSDK
import SwiftUI

// AGENT-PLATFORM (Brief 0063)

struct NativeCallScreenCoordinatorParameters {
    let roomProxy: JoinedRoomProxyProtocol
    let callKitService: CallKitServiceProtocol
    /// Absent when the platform is not configured; the Agent Center then
    /// reports itself unavailable instead of offering actions that must fail.
    let agentPlatformService: AgentPlatformServiceProtocol?
    /// The session's Agents tab, which an edit made from the call shows at once (S5).
    let agentsStore: AgentsStore?
    let isRoomEncrypted: Bool
    let notifyRoom: Bool
    /// Answering a ring rather than joining a running call.
    let isAnswer: Bool
    let configuration: NativeCallConfiguration
    /// Slice 5 — camera authorisation is asked for here rather than deep in
    /// the media engine, where a denial is invisible to the user.
    let appMediator: AppMediatorProtocol
    /// Avatars on the call screen and in the Agent Center. Optional so
    /// previews and tests can run without a media stack.
    let mediaProvider: MediaProviderProtocol?
}

enum NativeCallScreenCoordinatorAction {
    /// The call is finished and the screen is done with.
    case dismiss
    /// G13 — the user left the screen; the call continues behind the bar.
    case minimize
    /// G9 — the bar was tapped; the screen returns.
    case expand
    /// The assistant's "…" menu asked for its profile: the call goes to its bar and the profile opens (question 401).
    case showProfile(userID: String)
    /// The system PiP window took over; the overlay should minimize.
    /// There is deliberately no "stopped" counterpart — the window
    /// closing must not resurrect the screen; only an explicit restore
    /// (mapped to `.expand`) does.
    case pictureInPictureStarted
}

/// `SelfMinimizingOverlayCoordinator` (G9): the screen renders its own call
/// bar when the overlay minimizes — hiding a running call (and recording)
/// entirely is a disclosure regression.
final class NativeCallScreenCoordinator: CoordinatorProtocol, SelfMinimizingOverlayCoordinator {
    private let roomProxy: JoinedRoomProxyProtocol
    private let configuration: NativeCallConfiguration

    /// The room this call lives in. The flow coordinator needs it to tell
    /// "return to this call" apart from "replace it with a call in another
    /// room" — `ongoingCallRoomID` cannot answer that during `.connecting`,
    /// when it is not yet published (audit C6).
    var callRoomID: String {
        roomProxy.id
    }

    /// The CallKit call this screen ends: a teardown on its behalf is scoped
    /// to it, not to the room (follow-up N1).
    var callKitID: UUID? {
        viewModel?.callKitID
    }

    var hasCallEnded: Bool {
        viewModel?.hasCallEnded ?? true
    }

    /// An answer of this room returning to this screen (see the view model).
    func bind(toCallKitID callKitID: UUID) {
        viewModel?.bind(toCallKitID: callKitID)
    }

    private let viewModel: NativeCallScreenViewModelProtocol?
    private let actionsSubject: PassthroughSubject<NativeCallScreenCoordinatorAction, Never> = .init()
    private var cancellables = Set<AnyCancellable>()
    private var declineListenerHandle: TaskHandle?
    /// Kept so the view can be handed the renderer; the session owns the
    /// transport that draws.
    private var videoRenderer: NativeCallVideoRendering?
    /// Same arrangement for the agent block's wave amplitude.
    private var voiceLevelReader: NativeCallVoiceLevelReading?
    /// The system PiP session for this call, built once the renderer exists.
    private var pictureInPicture: NativeCallPictureInPictureController?
    
    var actions: AnyPublisher<NativeCallScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: NativeCallScreenCoordinatorParameters) {
        roomProxy = parameters.roomProxy
        configuration = parameters.configuration
        
        switch parameters.roomProxy.matrixRTCSession() {
        case .success(let rtcSession):
            let roomProxy = parameters.roomProxy
            // Every external source of truth feeds the session as a
            // PUBLISHER; the session's derivation reacts to any change.
            // The live translation truth needs no publisher here: it rides
            // the agent's `spiral.agent.state` participant attributes
            // (ADR-0071 D8) inside the transport snapshot, identically on
            // every device.
            let session = NativeCallSession(rtcSession: rtcSession,
                                            isRoomEncrypted: parameters.isRoomEncrypted,
                                            notifyRoom: parameters.notifyRoom,
                                            isAnswer: parameters.isAnswer,
                                            configuration: parameters.configuration,
                                            serviceMembers: roomProxy.infoPublisher.value.serviceMembers,
                                            serviceMembersPublisher: roomProxy.infoPublisher
                                                .map(\.serviceMembers)
                                                .removeDuplicates()
                                                .eraseToAnyPublisher())

            let agentCenter = NativeAgentCenterController(agentPlatformService: parameters.agentPlatformService,
                                                          roomID: roomProxy.id,
                                                          roomMemberMxids: {
                                                              let members = await roomProxy.members() ?? roomProxy.membersPublisher.value
                                                              return Set(members
                                                                  .filter { $0.membership == .join || $0.membership == .invite }
                                                                  .map(\.userID))
                                                          },
                                                          inviteAgent: { mxid in
                                                              if case .failure(let error) = await roomProxy.invite(userID: mxid) {
                                                                  MXLog.warning("Agent center: agent invite failed: \(error)")
                                                                  return false
                                                              }
                                                              return true
                                                          },
                                                          canKick: {
                                                              roomProxy.infoPublisher.value.powerLevels?.canOwnUserKick() ?? false
                                                          },
                                                          kickAgent: { mxid in
                                                              // D6: the moderator's own client removes the assistant (ADR-0082). One
                                                              // already out of the room is removed (bug S2): no error for a second tap.
                                                              if case .failure(let error) = await roomProxy.removeFromRoom(mxid) {
                                                                  MXLog.warning("Agent center: removing \(mxid) from the chat failed: \(error)")
                                                                  return false
                                                              }
                                                              return true
                                                          },
                                                          // ADR-0094: the catalog and the tool from the platform, the
                                                          // languages from this call's memberships.
                                                          translationPort: parameters.agentPlatformService.map {
                                                              NativeCallTranslationPort(service: $0, memberships: session)
                                                          },
                                                          agentEdited: { [weak agentsStore = parameters.agentsStore] readModel in
                                                              agentsStore?.agentEdited(readModel)
                                                          })

            videoRenderer = session.videoRenderer
            voiceLevelReader = session.voiceLevelReader
            pictureInPicture = NativeCallPictureInPictureController(renderer: session.videoRenderer)
            // Phase 2 — member profiles (names + avatars) for the call
            // screens. The member list is already being fetched for the
            // candidate filter above, so this publisher fills without its
            // own request.
            let memberProfiles = roomProxy.membersPublisher
                .map { members in
                    Dictionary(members.map { member in
                        (member.userID, NativeCallMemberProfile(displayName: member.disambiguatedDisplayName,
                                                                avatarURL: member.avatarURL))
                    }) { first, _ in first }
                }
                .removeDuplicates()
                .eraseToAnyPublisher()
            let roomPresentation = roomProxy.infoPublisher
                .map { info in
                    NativeCallRoomPresentation(name: info.displayName ?? "", avatar: info.avatar)
                }
                .removeDuplicates()
                .eraseToAnyPublisher()
            let roomInfo = parameters.roomProxy.infoPublisher.value

            viewModel = NativeCallScreenViewModel(session: session,
                                                  callKitService: parameters.callKitService,
                                                  agentCenter: agentCenter,
                                                  appMediator: parameters.appMediator,
                                                  mediaProvider: parameters.mediaProvider,
                                                  isVideoCall: parameters.configuration.media == .video,
                                                  roomID: parameters.roomProxy.id,
                                                  roomName: roomInfo.displayName ?? "",
                                                  scope: parameters.configuration.scope,
                                                  roomAvatar: roomInfo.avatar,
                                                  memberProfiles: memberProfiles,
                                                  roomPresentation: roomPresentation)

        case .failure(let error):
            // Without a session there is no call to present; the flow
            // coordinator dismisses immediately instead of showing an empty
            // screen that can never connect. The CallKit session is torn
            // down too (audit W6-6-2): on the answer path it was already
            // claimed and reported, and a bare dismissal left a phantom
            // system call plus a held activation-audio claim behind.
            MXLog.error("Cannot start a native call: \(error)")
            parameters.callKitService.tearDownCallSession(forRoomID: parameters.roomProxy.id)
            viewModel = nil
        }
    }
    
    /// Brief 0068 Slice 2: a parked call screen. `NavigationTabCoordinator`
    /// tears down (`stop()`s) the overlay it replaces and `start()`s the one
    /// it presents; a call that is merely parked behind another must
    /// survive the first and not re-run the second — a second `start()`
    /// would re-join the room and take a second audio claim.
    var isParked = false
    private var hasStarted = false

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        guard let viewModel else {
            actionsSubject.send(.dismiss)
            return
        }
        
        viewModel.actions
            .sink { [weak self] action in
                switch action {
                case .dismiss:
                    self?.actionsSubject.send(.dismiss)
                case .minimize:
                    self?.actionsSubject.send(.minimize)
                case .expand:
                    self?.actionsSubject.send(.expand)
                case .showProfile(let userID):
                    self?.actionsSubject.send(.showProfile(userID: userID))
                case .didSendRingNotification(let eventID):
                    if self?.configuration.scope == .direct {
                        self?.observeDeclineEvents(rtcNotificationEventID: eventID)
                    }
                }
            }
            .store(in: &cancellables)
        
        pictureInPicture?.actions
            .sink { [weak self] action in
                switch action {
                case .started:
                    self?.actionsSubject.send(.pictureInPictureStarted)
                case .restoreRequested:
                    // The window's restore button means "take me back to the
                    // call" — the same request the call bar makes.
                    self?.actionsSubject.send(.expand)
                }
            }
            .store(in: &cancellables)
        
        viewModel.start()
    }
    
    func stop() {
        if isParked {
            // Parked, not over: the screen leaves, the call stays. Only the
            // floating window comes down — it belongs to the screen.
            pictureInPicture?.stopForFullScreenReturn()
            return
        }
        declineListenerHandle?.cancel()
        declineListenerHandle = nil
        // The floating window must not outlive the call it belongs to.
        pictureInPicture?.invalidate()
        viewModel?.stop()
    }
    
    /// Starts system PiP on demand — the notification-navigation path, where
    /// the app stays foreground but the call screen has to get out of the way.
    func startPictureInPicture() {
        pictureInPicture?.start()
    }
    
    /// Takes the floating window down because the full screen is returning
    /// by a route that is not the window's own restore button.
    func stopPictureInPictureForFullScreenReturn() {
        pictureInPicture?.stopForFullScreenReturn()
    }
    
    /// A direct-call MSC4310 decline means the callee refused this ring. Group
    /// declines are per invitee and never terminate the conference.
    private func observeDeclineEvents(rtcNotificationEventID: String) {
        let ownUserID = roomProxy.ownUserID
        let listener: CallDeclineListener = SDKListener.onMainActor { [weak self] senderID in
            guard senderID != ownUserID else { return }
            
            MXLog.info("The callee declined the call")
            self?.viewModel?.remoteDeclined()
        }
        
        guard case let .success(handle) = roomProxy.subscribeToCallDeclineEvents(rtcNotificationEventID: rtcNotificationEventID,
                                                                                 listener: listener) else {
            MXLog.error("Unable to observe decline events for the outgoing call")
            return
        }
        
        declineListenerHandle = handle
        MXLog.info("Watching for declines of ring notification \(rtcNotificationEventID)")
    }
    
    func toPresentable() -> AnyView {
        guard let viewModel else { return AnyView(EmptyView()) }
        return AnyView(NativeCallScreen(context: viewModel.context,
                                        videoRenderer: videoRenderer,
                                        voiceLevels: voiceLevelReader,
                                        pictureInPicture: pictureInPicture))
    }
}
