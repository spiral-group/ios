//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftState
import SwiftUI
import UserNotifications

enum RoomFlowCoordinatorAction: Equatable {
    case presentCallScreen(roomProxy: JoinedRoomProxyProtocol, isVoiceCall: Bool)
    case presentAIConsentSettings // AGENT-PLATFORM (decision 150)
    /// The Agents tab, where the person's agent is or will be (question 412).
    case presentAgentsTab
    case verifyUser(userID: String)
    /// The requested room was actually a space. The room flow has been dismissed
    /// and a space flow should be started to continue.
    case continueWithSpaceFlow(SpaceRoomListProxyProtocol)
    case finished
    
    static func == (lhs: RoomFlowCoordinatorAction, rhs: RoomFlowCoordinatorAction) -> Bool {
        switch (lhs, rhs) {
        case (.presentCallScreen(let lhsRoomProxy, let lhsIsVoiceCall), .presentCallScreen(let rhsRoomProxy, let rhsIsVoiceCall)):
            lhsRoomProxy.id == rhsRoomProxy.id && lhsIsVoiceCall == rhsIsVoiceCall
        case (.finished, .finished), (.presentAgentsTab, .presentAgentsTab):
            true
        default:
            false
        }
    }
}

/// A value that represents where the room flow will be started.
enum RoomFlowCoordinatorEntryPoint: Hashable {
    /// The flow will start by showing the room directly.
    case room
    /// The flow will start by showing the room, focussing on the supplied event ID.
    case eventID(String)
    /// The flow will start by showing a thread timeline, can only be triggered by notification taps,
    /// which means it can never be a used for child flows.
    case thread(rootEventID: String, focusEventID: String?)
    /// The flow will start by showing the room's details.
    case roomDetails
    /// An external media share request
    case share(ShareExtensionPayload)
    /// The flow to change the the owner of the room
    case transferOwnership
    /// AGENT-PLATFORM (decision 111): the room, then the post catalogue on
    /// the template a catalogue link named.
    case catalogTemplate(String)
    
    var isEventID: Bool {
        guard case .eventID = self else { return false }
        return true
    }
}

struct FocusEvent: Hashable {
    /// The event ID that the timeline should be focussed around
    let eventID: String
    /// if the focus is coming from the pinned timeline, this should also update the pin banner
    let shouldSetPin: Bool
}

enum InviteUsersFlow: Hashable {
    /// Invite people into the current room.
    case existingRoom
    /// Start a new room with the given invitee pre-selected and mandatory.
    case newRoom(mandatoryInvitee: UserProfile)
}

// swiftlint:disable:next type_body_length
class RoomFlowCoordinator: FlowCoordinatorProtocol {
    private let roomID: String
    private let isChildFlow: Bool
    private let navigationStackCoordinator: NavigationStackCoordinator
    private let flowParameters: CommonFlowParameters
    
    private var userSession: UserSessionProtocol {
        flowParameters.userSession
    }
    
    private var roomProxy: JoinedRoomProxyProtocol!
    
    private var roomScreenCoordinator: RoomScreenCoordinator?
    private var childThreadScreenCoordinators: [ThreadTimelineScreenCoordinator] = []
    private weak var joinRoomScreenCoordinator: JoinRoomScreenCoordinator?
    
    // periphery:ignore - used to avoid deallocation
    private var rolesAndPermissionsFlowCoordinator: RoomRolesAndPermissionsFlowCoordinator?
    // periphery:ignore - used to avoid deallocation
    private var pinnedEventsTimelineFlowCoordinator: PinnedEventsTimelineFlowCoordinator?
    // periphery:ignore - used to avoid deallocation
    private var mediaEventsTimelineFlowCoordinator: MediaEventsTimelineFlowCoordinator?
    private var childRoomFlowCoordinator: RoomFlowCoordinator?
    // periphery:ignore - retaining purpose
    private var spaceFlowCoordinator: SpaceFlowCoordinator?
    private var membersFlowCoordinator: RoomMembersFlowCoordinator?
    // AGENT-PLATFORM: the agent-tools child flow (Brief 0036).
    private var agentToolsFlowCoordinator: AgentToolsFlowCoordinator?
    // AGENT-PLATFORM (Brief 0083, question 359): one of the owner's rows of an agent's page.
    private(set) var agentRowFlowCoordinator: AgentRowFlowCoordinator? // AGENT-PLATFORM: read by the tests
    
    let stateMachine: StateMachine<State, Event> = .init(state: .initial) // AGENT-PLATFORM (Brief 0083): tests drive the details' Threads row through it.
    
    private var cancellables = Set<AnyCancellable>()
    /// The open catalogue's actions, which hold the screen and what it keeps.
    private var catalogueActions: AnyCancellable?
    
    private let actionsSubject: PassthroughSubject<RoomFlowCoordinatorAction, Never> = .init()
    var actions: AnyPublisher<RoomFlowCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    private var timelineController: TimelineControllerProtocol?
    
    init(roomID: String,
         isChildFlow: Bool,
         navigationStackCoordinator: NavigationStackCoordinator,
         flowParameters: CommonFlowParameters) {
        self.roomID = roomID
        self.isChildFlow = isChildFlow
        self.navigationStackCoordinator = navigationStackCoordinator
        self.flowParameters = flowParameters
        
        setupStateMachine()
    }
    
    // MARK: - FlowCoordinatorProtocol
    
    func start(animated: Bool) {
        fatalError("This flow coordinator expect a route")
    }
    
    // swiftlint:disable:next cyclomatic_complexity
    func handleAppRoute(_ appRoute: AppRoute, animated: Bool) {
        MXLog.info("Handling app route: \(appRoute)")
        
        guard stateMachine.state != .complete else {
            fatalError("This flow coordinator is `finished` ☠️")
        }
        
        switch appRoute {
        case .room(let roomID, let via):
            flowParameters.analytics.signpost.startTransaction(.openRoom)
            Task {
                await handleRoomRoute(roomID: roomID, via: via, animated: animated)
            }
        case .childRoom(let roomID, let via):
            if case .membersFlow = stateMachine.state, let membersFlowCoordinator {
                membersFlowCoordinator.handleAppRoute(appRoute, animated: animated)
            } else if case .presentingChild = stateMachine.state, let childRoomFlowCoordinator {
                childRoomFlowCoordinator.handleAppRoute(appRoute, animated: animated)
            } else if roomID != roomProxy.id {
                stateMachine.tryEvent(.startChildFlow(roomID: roomID, via: via, entryPoint: .room), userInfo: EventUserInfo(animated: animated))
            } else {
                MXLog.info("Ignoring presentation of the same room as a child of this one.")
            }
        case .roomDetails(let roomID):
            guard roomID == self.roomID else { fatalError("Navigation route doesn't belong to this room flow.") }
            
            Task {
                if roomProxy == nil {
                    guard case let .joined(roomProxy) = await userSession.clientProxy.roomForIdentifier(roomID) else {
                        return
                    }
                    
                    await storeAndSubscribeToRoomProxy(roomProxy)
                }
                
                stateMachine.tryEvent(.presentRoomDetails, userInfo: EventUserInfo(animated: animated))
            }
        case .roomMemberDetails(let userID):
            // Always assume this will be presented on the child, external permalinks to a user aren't for a room member.
            if case .membersFlow = stateMachine.state, let membersFlowCoordinator {
                membersFlowCoordinator.handleAppRoute(.roomMemberDetails(userID: userID), animated: animated)
            } else if case .presentingChild = stateMachine.state, let childRoomFlowCoordinator {
                childRoomFlowCoordinator.handleAppRoute(appRoute, animated: animated)
            } else {
                stateMachine.tryEvent(.startMembersFlow(entryPoint: .roomMember(userID: userID)), userInfo: EventUserInfo(animated: animated))
            }
        case .thread(let roomID, let threadRootEventID, let focusEventID):
            Task {
                let focusEvent: FocusEvent? = if let focusEventID {
                    .init(eventID: focusEventID, shouldSetPin: false)
                } else {
                    nil
                }
                await handleRoomRoute(roomID: roomID,
                                      via: [],
                                      presentationAction: .thread(rootEventID: threadRootEventID,
                                                                  focusEvent: focusEvent),
                                      animated: animated)
            }
        case .event(let eventID, let roomID, let via):
            Task {
                await handleRoomRoute(roomID: roomID,
                                      via: via,
                                      presentationAction: .eventFocus(.init(eventID: eventID, shouldSetPin: false)),
                                      animated: animated)
            }
        case .childEvent(let eventID, let roomID, let via):
            handleChildEventRoute(eventID: eventID, roomID: roomID, via: via, animated: animated)
        case .share(let payload):
            guard let roomID = payload.roomID, roomID == self.roomID else {
                fatalError("Navigation route doesn't belong to this room flow.")
            }
            
            Task {
                await handleRoomRoute(roomID: roomID,
                                      via: [],
                                      presentationAction: .share(payload),
                                      animated: animated)
            }
        // AGENT-PLATFORM (decision 111): the `.share` shape — the chats tab
        // asked which chat, and this is it.
        case .catalogTemplate(let templateID, let roomID?) where roomID == self.roomID:
            Task {
                await handleRoomRoute(roomID: roomID,
                                      via: [],
                                      presentationAction: .catalogTemplate(templateID),
                                      animated: animated)
            }
        case .catalogTemplate:
            break // AGENT-PLATFORM: without this room it is the chats tab's.
        case .roomAlias, .childRoomAlias, .eventOnRoomAlias, .childEventOnRoomAlias:
            break // These are converted to a room ID route one level above.
        // AGENT-PLATFORM (Brief 0083 L1b): no .accountProvisioningLink.
        case .oAuthCallback, .inviteLink, .roomList, .userProfile, .call, .settings, .chatBackupSettings, .search, .aiConsentSettings: // AGENT-PLATFORM: .inviteLink (Brief 0073), .aiConsentSettings (decision 150)
            break // These routes can't be handled.
        case .approvalDetail, .verificationDetail, .publicProfile:
            break // AGENT-PLATFORM: handled by AgentsTabFlowCoordinator, not here.
        case .feedPost, .feedNotices:
            break // AGENT-PLATFORM: feed (Brief 0082): handled by FeedTabFlowCoordinator.
        case .transferOwnership(let roomID):
            guard self.roomID == roomID else { fatalError("Navigation route doesn't belong to this room flow.") }
            
            Task {
                if roomProxy == nil {
                    guard case let .joined(roomProxy) = await userSession.clientProxy.roomForIdentifier(roomID) else {
                        return
                    }
                    
                    await storeAndSubscribeToRoomProxy(roomProxy)
                }
                
                stateMachine.tryEvent(.presentTransferOwnershipScreen)
            }
        }
    }
    
    private func handleChildEventRoute(eventID: String, roomID: String, via: [String], animated: Bool) {
        if case .membersFlow = stateMachine.state, let membersFlowCoordinator {
            membersFlowCoordinator.handleAppRoute(.childEvent(eventID: eventID, roomID: roomID, via: via), animated: animated)
        } else if case .presentingChild = stateMachine.state, let childRoomFlowCoordinator {
            childRoomFlowCoordinator.handleAppRoute(.childEvent(eventID: eventID, roomID: roomID, via: via), animated: animated)
        } else if roomID != roomProxy.id {
            stateMachine.tryEvent(.startChildFlow(roomID: roomID, via: via, entryPoint: .eventID(eventID)), userInfo: EventUserInfo(animated: animated))
        } else {
            showLoadingIndicator(delay: .seconds(0.5))
            Task {
                defer { hideLoadingIndicator() }
                switch await roomProxy.loadOrFetchEventDetails(for: eventID) {
                case .success(let event):
                    if userSession.userSettings.app.threadsEnabled, let threadRootEventID = event.threadRootEventId() {
                        if case .thread(threadRootEventID: threadRootEventID, _) = stateMachine.state, let threadCoordinator = childThreadScreenCoordinators.last {
                            threadCoordinator.focusOnEvent(eventID: eventID)
                        } else {
                            // If we are showing the room timeline, we want to focus the thread root.
                            if childThreadScreenCoordinators.isEmpty {
                                roomScreenCoordinator?.focusOnEvent(.init(eventID: threadRootEventID, shouldSetPin: false))
                            }
                            stateMachine.tryEvent(.presentThread(threadRootEventID: threadRootEventID, focusEventID: eventID))
                        }
                    } else if !childThreadScreenCoordinators.isEmpty {
                        // If we are showing a child thread and we are navigating to a non threaded event
                        // of the same room, we want to push the room on top of the thread.
                        stateMachine.tryEvent(.startChildFlow(roomID: roomID, via: via, entryPoint: .eventID(eventID)), userInfo: EventUserInfo(animated: animated))
                    } else {
                        roomScreenCoordinator?.focusOnEvent(.init(eventID: eventID, shouldSetPin: false))
                    }
                case .failure:
                    showErrorIndicator()
                }
            }
        }
    }
    
    private func presentTransferOwnershipScreen() {
        let parameters = RoomChangeRolesScreenCoordinatorParameters(mode: .owner,
                                                                    roomProxy: roomProxy,
                                                                    mediaProvider: userSession.mediaProvider,
                                                                    userIndicatorController: flowParameters.userIndicatorController,
                                                                    analytics: flowParameters.analytics)
        let stackCoordinator = NavigationStackCoordinator()
        let coordinator = RoomChangeRolesScreenCoordinator(parameters: parameters)
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .complete:
                navigationStackCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)
        
        stackCoordinator.setRootCoordinator(coordinator)
        navigationStackCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissedTransferOwnershipScreen)
        }
    }
    
    private func handleRoomRoute(roomID: String, via: [String], presentationAction: PresentationAction? = nil, animated: Bool) async {
        guard roomID == self.roomID else { fatalError("Navigation route doesn't belong to this room flow.") }
        
        showLoadingIndicator(delay: .seconds(0.5))
        defer { hideLoadingIndicator() }
        
        guard let room = await userSession.clientProxy.roomForIdentifier(roomID) else {
            stateMachine.tryEvent(.presentJoinRoomScreen(via: via), userInfo: EventUserInfo(animated: animated))
            return
        }
        
        switch room {
        case .joined(let roomProxy):
            if roomProxy.infoPublisher.value.isSpace {
                switch await userSession.clientProxy.spaceService.spaceRoomList(spaceID: roomProxy.id) {
                case .success(let spaceRoomListProxy):
                    actionsSubject.send(.continueWithSpaceFlow(spaceRoomListProxy))
                case .failure:
                    showErrorIndicator()
                    stateMachine.tryEvent(.dismissFlow)
                }
            } else {
                await storeAndSubscribeToRoomProxy(roomProxy)
                
                guard case let .eventFocus(focusEvent) = presentationAction else {
                    // If is not a focus event just handle the presentation action directly in `presentRoom`
                    stateMachine.tryEvent(.presentRoom(presentationAction: presentationAction), userInfo: EventUserInfo(animated: animated))
                    return
                }
                
                // Otherwise check if the focussed event exists to handle a possible error or theaded event.
                switch await roomProxy.loadOrFetchEventDetails(for: focusEvent.eventID) {
                case .success(let event):
                    if userSession.userSettings.app.threadsEnabled, let threadRootEventID = event.threadRootEventId() {
                        stateMachine.tryEvent(.presentRoom(presentationAction: .thread(rootEventID: threadRootEventID,
                                                                                       focusEvent: .init(eventID: focusEvent.eventID,
                                                                                                         shouldSetPin: focusEvent.shouldSetPin))),
                                              userInfo: EventUserInfo(animated: animated))
                    } else {
                        stateMachine.tryEvent(.presentRoom(presentationAction: presentationAction), userInfo: EventUserInfo(animated: animated))
                    }
                case .failure:
                    showErrorIndicator()
                    stateMachine.tryEvent(.presentRoom(presentationAction: nil), userInfo: EventUserInfo(animated: animated))
                }
            }
        default:
            stateMachine.tryEvent(.presentJoinRoomScreen(via: via), userInfo: EventUserInfo(animated: animated))
        }
    }
    
    /// Returns to this room's timeline from a screen pushed over it, when `roomID` is this room. A room that is the
    /// stack's root is selected again by its route; a child flow's timeline is one of the stack's screens, so the
    /// screens above it go. Anything else isn't this flow's to show.
    /// - Returns: whether `roomID` is this room.
    func showTimeline(ifRoomID roomID: String) -> Bool {
        guard roomID == self.roomID else { return false }
        
        if isChildFlow, let roomScreenCoordinator {
            navigationStackCoordinator.pop(to: roomScreenCoordinator)
        } else {
            handleAppRoute(.room(roomID: roomID, via: []), animated: true)
        }
        return true
    }
    
    func clearRoute(animated: Bool) {
        guard stateMachine.state != .initial else {
            return
        }
        
        stateMachine.tryEvent(.dismissFlow, userInfo: EventUserInfo(animated: animated))
    }
    
    // MARK: - Private
    
    private func storeAndSubscribeToRoomProxy(_ roomProxy: JoinedRoomProxyProtocol) async {
        if let oldRoomProxy = self.roomProxy {
            if oldRoomProxy.id != roomProxy.id {
                fatalError("Trying to create different room proxies for the same flow coordinator")
            }
            
            MXLog.warning("Found an existing proxy, returning.")
            return
        }
        
        await roomProxy.subscribeForUpdates()
        
        // Make sure not to set this until after the subscription has succeeded, otherwise the
        // early return above could result in trying to access the room's timeline provider
        // before it has been set which triggers a fatal error.
        self.roomProxy = roomProxy
        
        // Subscribe to room info updates in order to detect rooms being left on other devices
        // and react accordingly by dismissing this flow coordinator.
        self.roomProxy.infoPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                
                if info.membership == .left || info.membership == .banned, stateMachine.state != .complete {
                    stateMachine.tryEvent(.dismissFlow)
                }
            }
            .store(in: &cancellables)
    }
    
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func setupStateMachine() {
        addRouteMapping(stateMachine: stateMachine)
        
        stateMachine.addAnyHandler(.any => .any) { [weak self] context in
            guard let self else { return }
            
            let animated = (context.userInfo as? EventUserInfo)?.animated ?? true
            
            switch (context.fromState, context.event, context.toState) {
            // Room
                
            case (_, .presentRoom(let presentationAction), .room):
                Task {
                    await self.presentRoom(fromState: context.fromState,
                                           presentationAction: presentationAction,
                                           animated: animated)
                }
            case (_, .dismissFlow, .complete):
                dismissFlow(animated: animated)
                
            case (.room, .presentPinnedEventsTimeline, .pinnedEventsTimeline):
                startPinnedEventsTimelineFlow()
                
            // Thread List
                
            case (.roomDetails, .presentThreadList, .threadList): // AGENT-PLATFORM (Brief 0083, decision 344): only the details' row opens it.
                Task { await self.presentThreadList(animated: animated) }
                
            // Thread
                
            case (_, .presentThread(let threadRootEventID, let focusEventID), .thread):
                Task { await self.presentThread(threadRootEventID: threadRootEventID, focusEventID: focusEventID, animated: animated) }
                
            // Thread + Room
                
            case (_, .startSpaceFlow, .spaceFlow):
                guard let spaceRoomListProxy = (context.userInfo as? EventUserInfo)?.spaceRoomListProxy else {
                    fatalError("The space room list proxy is required to present a space.")
                }
                startSpaceFlow(spaceRoomListProxy: spaceRoomListProxy, animated: animated)
            case (.spaceFlow, .finishedSpaceFlow, _):
                spaceFlowCoordinator = nil
                
            case (_, .presentReportContent, .reportContent(let itemID, let senderID, _)):
                presentReportContent(for: itemID, from: senderID)
                
            case (_, .presentMediaUploadPicker, .mediaUploadPicker(let mode, let caption, _)):
                guard let timelineController = (context.userInfo as? EventUserInfo)?.timelineController else {
                    fatalError("Missing required TimelineController")
                }
                presentMediaUploadPickerWithMode(mode, caption: caption, timelineController: timelineController, animated: animated)
                
            case (_, .presentEmojiPicker, .emojiPicker(let selectedEmojis, _)):
                guard let continuation = (context.userInfo as? EventUserInfo)?.emojiPickerContinuation else {
                    fatalError("Missing required emoji continuation")
                }
                presentEmojiPicker(selectedEmojis: selectedEmojis,
                                   emojiPickerContinuation: continuation,
                                   animated: animated)
                
            case (_, .presentMessageForwarding(let forwardingPayload), .messageForwarding):
                presentMessageForwarding(with: forwardingPayload)
                
            case (_, .presentMapNavigator(let mode), .mapNavigator):
                guard let timelineController = (context.userInfo as? EventUserInfo)?.timelineController else {
                    fatalError("Missing required TimelineController")
                }
                presentMapNavigator(interactionMode: mode, timelineController: timelineController, animated: animated)
                
            case (_, .presentPollForm(let mode), .pollForm):
                guard let timelineController = (context.userInfo as? EventUserInfo)?.timelineController else {
                    fatalError("Missing required TimelineController")
                }
                presentPollForm(mode: mode, timelineController: timelineController)
                
            case (_, .presentResolveSendFailure(let failure, let resolver), .resolveSendFailure): // AGENT-PLATFORM: § 5.87
                presentResolveSendFailure(failure: failure, resolver: resolver)
                
            // Room Details
                
            case (.initial, .presentRoomDetails, .roomDetails(let isRoot)),
                 (.room, .presentRoomDetails, .roomDetails(let isRoot)),
                 (.roomDetails, .presentRoomDetails, .roomDetails(let isRoot)):
                Task { await self.presentRoomDetails(isRoot: isRoot, animated: animated) }
                
            case (.roomDetails, .presentRoomDetailsEditScreen, .roomDetailsEditScreen):
                presentRoomDetailsEditScreen()
                
            case (.roomDetails, .presentNotificationSettingsScreen, .notificationSettings):
                presentNotificationSettingsScreen()
                
            case (.roomDetails, .presentPollsHistory, .pollsHistory):
                Task { await self.presentRoomPollsHistory(animated: animated) }
                
            case (.roomDetails, .presentPinnedEventsTimeline, .pinnedEventsTimeline):
                startPinnedEventsTimelineFlow()
                
            case (.roomDetails, .presentRolesAndPermissionsScreen, .rolesAndPermissions):
                presentRolesAndPermissionsScreen()
            case (.rolesAndPermissions, .dismissRolesAndPermissionsScreen, .roomDetails):
                rolesAndPermissionsFlowCoordinator = nil
                
            case (.roomDetails, .presentMediaEventsTimeline, .mediaEventsTimeline):
                Task { await self.startMediaEventsTimelineFlow() }
                
            case (.roomDetails, .presentSecurityAndPrivacyScreen, .securityAndPrivacy):
                presentSecurityAndPrivacyScreen()
                
            case (.securityAndPrivacy, .presentManageAuthorizedSpacesScreen, .manageAuthorizedSpacesScreen):
                guard let selection = (context.userInfo as? EventUserInfo)?.authorizedSpacesSelection else {
                    fatalError("Missing required AuthorizedSpacesSelection")
                }
                presentManageAuthorizedSpacesScreen(selection: selection)
                
            case (.roomDetails, .presentReportRoomScreen, .reportRoom):
                presentReportRoom()
                
            // Join room
                
            case (_, .presentJoinRoomScreen(let via), .joinRoomScreen):
                presentJoinRoomScreen(via: via, animated: true)
            case (_, .dismissJoinRoomScreen, .complete):
                dismissFlow(animated: animated)
            case (_, .joinedSpace, .complete):
                guard let spaceRoomListProxy = (context.userInfo as? EventUserInfo)?.spaceRoomListProxy else {
                    fatalError("The space room list proxy is required to present a space.")
                }
                dismissFlow(animated: animated, continuingWith: spaceRoomListProxy)
                
            case (.joinRoomScreen, .presentDeclineAndBlockScreen(let userID), .declineAndBlockScreen):
                presentDeclineAndBlockScreen(userID: userID)
                
            // Other
                
            case (_, .startMembersFlow(let entryPoint), .membersFlow):
                startMembersFlow(entryPoint: entryPoint, animated: animated)
            case (.membersFlow, .stopMembersFlow, _):
                membersFlowCoordinator = nil
                
            case (_, .startAgentToolsFlow, .agentToolsFlow):
                startAgentToolsFlow(animated: animated)
            case (.agentToolsFlow, .stopAgentToolsFlow, _):
                agentToolsFlowCoordinator = nil
                
            case (_, .startAgentRowFlow(let row, let card), .agentRowFlow): // AGENT-PLATFORM (Brief 0083, question 359)
                startAgentRowFlow(row: row, card: card, animated: animated)
            case (.agentRowFlow, .stopAgentRowFlow, _):
                agentRowFlowCoordinator = nil
                
            case (_, .startChildFlow(let roomID, let via, let entryPoint), .presentingChild):
                startChildFlow(for: roomID, via: via, entryPoint: entryPoint)
            case (.presentingChild, .dismissChildFlow, _):
                childRoomFlowCoordinator = nil
                
            case (_, .presentKnockRequestsListScreen, .knockRequestsList):
                presentKnockRequestsList()
                
            case (.notificationSettings, .presentGlobalNotificationSettingsScreen, .globalNotificationSettings):
                presentGlobalNotificationSettingsScreen()
                
            case (.pollsHistory, .presentPollForm(let mode), .pollsHistoryForm):
                guard let timelineController = (context.userInfo as? EventUserInfo)?.timelineController else {
                    fatalError("Missing required TimelineController")
                }
                presentPollForm(mode: mode, timelineController: timelineController)
                
            case (_, .presentMediaUploadPreview, .mediaUploadPreview(let mediaURLs, let caption, _)):
                guard let timelineController = (context.userInfo as? EventUserInfo)?.timelineController else {
                    fatalError("Missing required TimelineController")
                }
                
                presentMediaUploadPreviewScreen(for: mediaURLs, caption: caption, timelineController: timelineController, animated: animated)
                
            case (_, .presentInviteUsersScreen(let flow), .inviteUsersScreen):
                presentInviteUsersScreen(flow: flow)
                
            case (_, .presentTransferOwnershipScreen, .transferOwnershipScreen):
                presentTransferOwnershipScreen()
                
            default:
                break
            }
        }
        
        stateMachine.addAnyHandler(.any => .any) { context in
            if let event = context.event {
                MXLog.info("Transitioning from `\(context.fromState)` to `\(context.toState)` with event `\(event)`")
            } else {
                MXLog.info("Transitioning from \(context.fromState)` to `\(context.toState)`")
            }
        }
        
        stateMachine.addErrorHandler { context in
            if context.fromState == context.toState {
                MXLog.error("Failed transition from equal states: \(context.fromState)")
            } else {
                fatalError("Failed transition with context: \(context)")
            }
        }
    }
    
    /// Updates the navigation stack so it displays the timeline for the given room
    /// - Parameters:
    ///   - fromState: The state that asked for the room presentation.
    ///   - presentationAction: The action that should happen after the room is presented
    ///   - animated: whether it should animate the transition
    private func presentRoom(fromState: State,
                             presentationAction: PresentationAction?,
                             animated: Bool) async {
        // If any sheets are presented dismiss them, rely on their dismissal callbacks to transition the state machine
        // through the correct states before presenting the room
        navigationStackCoordinator.setSheetCoordinator(nil)
        
        // Handle selecting the same room again
        if !isChildFlow {
            // First unwind the navigation stack
            navigationStackCoordinator.popToRoot(animated: animated)
            
            // And then decide if the room actually needs to be presented again
            switch fromState {
            case .initial, .roomDetails(isRoot: true), .joinRoomScreen:
                break
            case _ where roomScreenCoordinator == nil: // AGENT-PLATFORM (Brief 0083): a screen over details at the root.
                break
            default:
                // The room is already on the stack, no need to present it again
                
                switch presentationAction {
                case .eventFocus(let focusedEvent):
                    roomScreenCoordinator?.focusOnEvent(focusedEvent)
                case .share(.mediaFiles(_, let mediaFiles)):
                    stateMachine.tryEvent(.presentMediaUploadPreview(mediaURLs: mediaFiles.map(\.url), caption: nil),
                                          userInfo: EventUserInfo(animated: animated, timelineController: timelineController))
                case .share(.text(_, let text)):
                    roomScreenCoordinator?.shareText(text)
                case .catalogTemplate(let templateID): // AGENT-PLATFORM (decision 111)
                    Task { await presentInteractivePostCatalogForLink(templateID: templateID) }
                case .thread(let rootEventID, let focusEvent):
                    if let focusEvent, let roomScreenCoordinator {
                        roomScreenCoordinator.focusOnEvent(.init(eventID: rootEventID, shouldSetPin: false))
                        // Since the root is not the message we want to show in the pinned banner, but the actual event
                        if focusEvent.shouldSetPin {
                            roomScreenCoordinator.setSelectedPin(eventID: focusEvent.eventID)
                        }
                    }
                    stateMachine.tryEvent(.presentThread(threadRootEventID: rootEventID, focusEventID: focusEvent?.eventID))
                case .none:
                    break
                }
                
                return
            }
        }
        
        // Flag the room as read on entering, the timeline will take care of the read receipts
        Task { await roomProxy.flagAsUnread(false) }
        
        flowParameters.analytics.trackViewRoom(isDM: roomProxy.infoPublisher.value.isDirect, isSpace: roomProxy.infoPublisher.value.isSpace)
        
        let coordinator = makeRoomScreenCoordinator(presentationAction: presentationAction, animated: animated)
        roomScreenCoordinator = coordinator
        
        if !isChildFlow {
            navigationStackCoordinator.setRootCoordinator(coordinator, animated: animated) { [weak self] in
                self?.stateMachine.tryEvent(.dismissFlow)
            }
        } else {
            if joinRoomScreenCoordinator != nil {
                navigationStackCoordinator.pop()
            }
            
            navigationStackCoordinator.push(coordinator, animated: animated) { [weak self] in
                self?.stateMachine.tryEvent(.dismissFlow)
            }
        }
        
        switch presentationAction {
        case .share(.mediaFiles(_, let mediaFiles)):
            stateMachine.tryEvent(.presentMediaUploadPreview(mediaURLs: mediaFiles.map(\.url), caption: nil),
                                  userInfo: EventUserInfo(animated: animated, timelineController: timelineController))
        case .thread(let rootEventID, let focusEvent):
            stateMachine.tryEvent(.presentThread(threadRootEventID: rootEventID, focusEventID: focusEvent?.eventID))
        case .catalogTemplate(let templateID): // AGENT-PLATFORM (decision 111)
            Task { await presentInteractivePostCatalogForLink(templateID: templateID) }
        case .share(.text), .eventFocus:
            break // These are both handled in the coordinator's init.
        case .none:
            break
        }
    }
    
    private func makeRoomScreenCoordinator(presentationAction: PresentationAction?, animated: Bool) -> RoomScreenCoordinator {
        let userID = userSession.clientProxy.userID
        let timelineItemFactory = RoomTimelineItemFactory(userID: userID,
                                                          attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                                          stateEventStringBuilder: RoomStateEventStringBuilder(userID: userID))
        let timelineController = flowParameters.timelineControllerFactory.buildTimelineController(roomProxy: roomProxy,
                                                                                                  initialFocussedEventID: presentationAction?.focusedEvent?.eventID,
                                                                                                  timelineItemFactory: timelineItemFactory,
                                                                                                  mediaProvider: userSession.mediaProvider)
        self.timelineController = timelineController
        
        let completionSuggestionService = CompletionSuggestionService(roomProxy: roomProxy,
                                                                      roomListPublisher: userSession.clientProxy.staticRoomSummaryProvider.roomListPublisher.eraseToAnyPublisher())
        let composerDraftService = ComposerDraftService(roomProxy: roomProxy,
                                                        timelineItemfactory: timelineItemFactory,
                                                        threadRootEventID: nil)
        
        let parameters = RoomScreenCoordinatorParameters(userSession: userSession,
                                                         roomProxy: roomProxy,
                                                         focussedEvent: presentationAction?.focusedEvent,
                                                         sharedText: presentationAction?.sharedText,
                                                         timelineController: timelineController,
                                                         mediaPlayerProvider: MediaPlayerProvider(),
                                                         emojiProvider: flowParameters.emojiProvider,
                                                         linkMetadataProvider: flowParameters.linkMetadataProvider,
                                                         completionSuggestionService: completionSuggestionService,
                                                         ongoingCallRoomIDPublisher: flowParameters.ongoingCallRoomIDPublisher,
                                                         appMediator: flowParameters.appMediator,
                                                         analytics: flowParameters.analytics,
                                                         composerDraftService: composerDraftService,
                                                         timelineControllerFactory: flowParameters.timelineControllerFactory,
                                                         userIndicatorController: flowParameters.userIndicatorController)
        
        let coordinator = RoomScreenCoordinator(parameters: parameters)
        coordinator.actions
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .presentRoomDetails:
                    stateMachine.tryEvent(.presentRoomDetails)
                case .presentReportContent(let itemID, let senderID):
                    stateMachine.tryEvent(.presentReportContent(itemID: itemID,
                                                                senderID: senderID))
                case .presentMediaUploadPicker(let mode, let caption):
                    stateMachine.tryEvent(.presentMediaUploadPicker(mode: mode, caption: caption),
                                          userInfo: EventUserInfo(animated: animated, timelineController: timelineController))
                case .presentMediaUploadPreviewScreen(let url, let caption):
                    stateMachine.tryEvent(.presentMediaUploadPreview(mediaURLs: url, caption: caption),
                                          userInfo: EventUserInfo(animated: animated, timelineController: timelineController))
                case .presentEmojiPicker(let selectedEmojis, let continuation):
                    stateMachine.tryEvent(.presentEmojiPicker(selectedEmojis: selectedEmojis),
                                          userInfo: EventUserInfo(animated: animated, emojiPickerContinuation: continuation))
                case .presentLocationPicker:
                    stateMachine.tryEvent(.presentMapNavigator(interactionMode: .picker(shouldShowLiveLocationOption: true)),
                                          userInfo: EventUserInfo(animated: animated, timelineController: timelineController))
                case .presentPollForm(let mode):
                    stateMachine.tryEvent(.presentPollForm(mode: mode),
                                          userInfo: EventUserInfo(animated: animated, timelineController: timelineController))
                case .presentLocationViewer(let location):
                    stateMachine.tryEvent(.presentMapNavigator(interactionMode: .viewStatic(location)),
                                          userInfo: EventUserInfo(animated: animated,
                                                                  timelineController: timelineController))
                case .presentLiveLocationViewer(let sender, let initialLiveLocationShare):
                    stateMachine.tryEvent(.presentMapNavigator(interactionMode: .viewLive(sender: sender, initialLiveLocationShare: initialLiveLocationShare)),
                                          userInfo: EventUserInfo(animated: animated, timelineController: timelineController))
                case .presentRoomMemberDetails(userID: let userID):
                    stateMachine.tryEvent(.startMembersFlow(entryPoint: .roomMember(userID: userID)))
                case .presentMessageForwarding(let forwardingPayload):
                    stateMachine.tryEvent(.presentMessageForwarding(forwardingPayload: forwardingPayload))
                case .presentCallScreen(let isVoiceCall):
                    actionsSubject.send(.presentCallScreen(roomProxy: roomProxy, isVoiceCall: isVoiceCall))
                case .presentAIConsentSettings: // AGENT-PLATFORM (decision 150)
                    actionsSubject.send(.presentAIConsentSettings)
                case .presentPinnedEventsTimeline:
                    stateMachine.tryEvent(.presentPinnedEventsTimeline)
                case .presentResolveSendFailure(failure: let failure, resolver: let resolver): // AGENT-PLATFORM: § 5.87
                    // A sheet that cannot be shown now (another is up) must
                    // still end the question, or a raw send waits for ever.
                    if !stateMachine.tryEvent(.presentResolveSendFailure(failure: failure,
                                                                         resolver: resolver)) {
                        resolver.finished()
                    }
                case .presentKnockRequestsList:
                    stateMachine.tryEvent(.presentKnockRequestsListScreen)
                case .presentThread(let threadRootEventID, let focussedEventID):
                    stateMachine.tryEvent(.presentThread(threadRootEventID: threadRootEventID, focusEventID: focussedEventID))
                case .presentRoom(let roomID, let via):
                    stateMachine.tryEvent(.startChildFlow(roomID: roomID,
                                                          via: via,
                                                          entryPoint: .room))
                case .presentAgentTools:
                    stateMachine.tryEvent(.startAgentToolsFlow)
                case .presentInteractivePostAgentPicker:
                    Task { await presentInteractivePostAgentPicker() }
                case .presentInteractivePostEditor(let eventID, let post, let title):
                    Task { await presentInteractivePostEditor(eventID: eventID, post: post, title: title) }
                }
            }
            .store(in: &cancellables)
        
        return coordinator
    }

    // MARK: - Agent tools (Brief 0036 / ADR-0048)

    /// AGENT-PLATFORM: start the agent-tools flow — the owner's surface for
    /// arming / reading / disabling an agent's per-room tools, reached from the
    /// composer "+" Agent item and the in-chat active-tools banner. Modelled on
    /// `startMembersFlow`: a child flow coordinator owns the multi-screen
    /// navigation + its own state machine; this only creates, subscribes to,
    /// starts and retains it. On `.finished` the parent restores its previous
    /// state and refreshes the banner (tools may have changed).
    private func startAgentToolsFlow(animated: Bool) {
        // AGENT-PLATFORM: the Agents store is there with the service (platform sync, decision 289).
        guard let agentPlatformService = userSession.agentPlatformService, let agentsStore = userSession.agentsStore else {
            MXLog.warning("RoomFlowCoordinator: no AgentPlatformService configured — cannot start agent-tools flow")
            showErrorIndicator()
            stateMachine.tryEvent(.stopAgentToolsFlow)
            return
        }

        let flowCoordinator = AgentToolsFlowCoordinator(roomID: roomID,
                                                        roomProxy: roomProxy,
                                                        agentPlatformService: agentPlatformService,
                                                        agentsStore: agentsStore,
                                                        navigationStackCoordinator: navigationStackCoordinator,
                                                        flowParameters: flowParameters)

        flowCoordinator.actions.sink { [weak self] action in
            self?.handle(action)
        }
        .store(in: &cancellables)

        flowCoordinator.start(animated: animated)
        agentToolsFlowCoordinator = flowCoordinator
    }
    
    func handle(_ action: AgentToolsFlowCoordinatorAction) {
        switch action {
        case .finished:
            roomScreenCoordinator?.refreshAgentToolsBanner()
            stateMachine.tryEvent(.stopAgentToolsFlow)
        case .presentProfile(let userID):
            // The state goes back first: the dismissal's `.finished` finds it so.
            stateMachine.tryEvent(.stopAgentToolsFlow)
            stateMachine.tryEvent(.startMembersFlow(entryPoint: .roomMember(userID: userID)))
        }
    }

    // AGENT-PLATFORM (Brief 0083, question 359)
    private func startAgentRowFlow(row: AgentPageRow, card: AgentSpaceAgentCard, animated: Bool) {
        guard let flowCoordinator = AgentRowFlowCoordinator(row: row,
                                                            card: card,
                                                            navigationStackCoordinator: navigationStackCoordinator,
                                                            flowParameters: flowParameters,
                                                            showOriginRoom: { [weak self] in self?.showTimeline(ifRoomID: $0) ?? false }) else {
            MXLog.warning("RoomFlowCoordinator: no agent platform: cannot open an agent's row")
            showErrorIndicator()
            stateMachine.tryEvent(.stopAgentRowFlow)
            return
        }
        
        flowCoordinator.actionsPublisher.sink { [weak self, weak flowCoordinator] action in
            guard let self else { return }
            switch action {
            case .finished:
                // The row's Message to this very chat routes to the room, which moves the state on before its screens
                // are popped; the flow is let go there too rather than held for the rest of the room's life.
                if !stateMachine.tryEvent(.stopAgentRowFlow), agentRowFlowCoordinator === flowCoordinator {
                    agentRowFlowCoordinator = nil
                }
            case .presentCallScreen(let roomProxy, let isVoiceCall):
                actionsSubject.send(.presentCallScreen(roomProxy: roomProxy, isVoiceCall: isVoiceCall))
            case .presentAIConsentSettings:
                actionsSubject.send(.presentAIConsentSettings)
            case .presentAgentsTab: // AGENT-PLATFORM (question 412)
                actionsSubject.send(.presentAgentsTab)
            case .verifyUser(let userID):
                actionsSubject.send(.verifyUser(userID: userID))
            }
        }
        .store(in: &cancellables)
        
        flowCoordinator.start(animated: animated)
        agentRowFlowCoordinator = flowCoordinator
    }

    private func presentThreadList(animated: Bool) async {
        let coordinator = RoomThreadListScreenCoordinator(parameters: .init(threadListServiceProxy: roomProxy.threadListService(),
                                                                            mediaProvider: userSession.mediaProvider))
        
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .presentThread(let threadRootEventID):
                stateMachine.tryEvent(.presentThread(threadRootEventID: threadRootEventID, focusEventID: nil))
            }
        }.store(in: &cancellables)
        
        navigationStackCoordinator.push(coordinator, animated: animated) { [weak self] in
            guard let self else { return }
            stateMachine.tryEvent(.dismissThreadList)
        }
    }
    
    private func presentThread(threadRootEventID: String, focusEventID: String?, animated: Bool) async {
        showLoadingIndicator()
        defer { hideLoadingIndicator() }
        
        let timelineItemFactory = RoomTimelineItemFactory(userID: userSession.clientProxy.userID,
                                                          attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                                          stateEventStringBuilder: RoomStateEventStringBuilder(userID: userSession.clientProxy.userID))
        
        guard case let .success(timelineController) = await flowParameters.timelineControllerFactory.buildThreadTimelineController(threadRootEventID: threadRootEventID,
                                                                                                                                   initialFocussedEventID: focusEventID,
                                                                                                                                   roomProxy: roomProxy,
                                                                                                                                   timelineItemFactory: timelineItemFactory,
                                                                                                                                   mediaProvider: userSession.mediaProvider) else {
            MXLog.error("Failed presenting media timeline")
            return
        }
        
        let completionSuggestionService = CompletionSuggestionService(roomProxy: roomProxy,
                                                                      roomListPublisher: userSession.clientProxy.staticRoomSummaryProvider.roomListPublisher.eraseToAnyPublisher())
        let composerDraftService = ComposerDraftService(roomProxy: roomProxy,
                                                        timelineItemfactory: timelineItemFactory,
                                                        threadRootEventID: threadRootEventID)
        
        let coordinator = ThreadTimelineScreenCoordinator(parameters: .init(userSession: userSession,
                                                                            roomProxy: roomProxy,
                                                                            focussedEventID: focusEventID,
                                                                            timelineController: timelineController,
                                                                            mediaPlayerProvider: MediaPlayerProvider(),
                                                                            emojiProvider: flowParameters.emojiProvider,
                                                                            linkMetadataProvider: flowParameters.linkMetadataProvider,
                                                                            completionSuggestionService: completionSuggestionService,
                                                                            appMediator: flowParameters.appMediator,
                                                                            analytics: flowParameters.analytics,
                                                                            composerDraftService: composerDraftService,
                                                                            timelineControllerFactory: flowParameters.timelineControllerFactory,
                                                                            userIndicatorController: flowParameters.userIndicatorController))
        
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .presentReportContent(let itemID, let senderID):
                stateMachine.tryEvent(.presentReportContent(itemID: itemID, senderID: senderID))
            case .presentMediaUploadPicker(let mode, let caption):
                stateMachine.tryEvent(.presentMediaUploadPicker(mode: mode, caption: caption),
                                      userInfo: EventUserInfo(animated: animated, timelineController: timelineController))
            case .presentMediaUploadPreviewScreen(let mediaURLs, let caption):
                stateMachine.tryEvent(.presentMediaUploadPreview(mediaURLs: mediaURLs, caption: caption),
                                      userInfo: EventUserInfo(animated: animated, timelineController: timelineController))
            case .presentLocationPicker:
                stateMachine.tryEvent(.presentMapNavigator(interactionMode: .picker(shouldShowLiveLocationOption: false)),
                                      userInfo: EventUserInfo(animated: animated, timelineController: timelineController))
            case .presentLiveLocationViewer(let sender, let initialLiveLocationShare):
                stateMachine.tryEvent(.presentMapNavigator(interactionMode: .viewLive(sender: sender, initialLiveLocationShare: initialLiveLocationShare)),
                                      userInfo: EventUserInfo(animated: animated, timelineController: timelineController))
            case .presentPollForm(let mode):
                stateMachine.tryEvent(.presentPollForm(mode: mode),
                                      userInfo: EventUserInfo(animated: animated, timelineController: timelineController))
            case .presentLocationViewer(let location):
                stateMachine.tryEvent(.presentMapNavigator(interactionMode: .viewStatic(location)),
                                      userInfo: EventUserInfo(animated: animated,
                                                              timelineController: timelineController))
            case .presentEmojiPicker(let selectedEmojis, let continuation):
                stateMachine.tryEvent(.presentEmojiPicker(selectedEmojis: selectedEmojis),
                                      userInfo: EventUserInfo(animated: animated, emojiPickerContinuation: continuation))
            case .presentRoomMemberDetails(let userID):
                stateMachine.tryEvent(.startMembersFlow(entryPoint: .roomMember(userID: userID)))
            case .presentMessageForwarding(let forwardingPayload):
                stateMachine.tryEvent(.presentMessageForwarding(forwardingPayload: forwardingPayload))
            case .presentResolveSendFailure(let failure, let resolver): // AGENT-PLATFORM: § 5.87
                if !stateMachine.tryEvent(.presentResolveSendFailure(failure: failure,
                                                                     resolver: resolver)) {
                    resolver.finished()
                }
            case .interactivePostPublished:
                // Published from an ordinary thread; the row's toast said so.
                break
            }
        }
        .store(in: &cancellables)
        
        navigationStackCoordinator.push(coordinator, animated: animated) { [weak self] in
            guard let self else { return }
            stateMachine.tryEvent(.dismissThread)
            childThreadScreenCoordinators.removeAll { $0 === coordinator }
        }
        
        childThreadScreenCoordinators.append(coordinator)
    }
    
    private func presentJoinRoomScreen(via: [String], animated: Bool) {
        let coordinator = JoinRoomScreenCoordinator(parameters: .init(source: .generic(roomID: roomID, via: via),
                                                                      userSession: userSession,
                                                                      userIndicatorController: flowParameters.userIndicatorController))
        
        joinRoomScreenCoordinator = coordinator
        
        coordinator.actionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .joined(.roomID(let roomID)):
                    Task { [weak self] in
                        guard let self else { return }
                        
                        if case let .joined(roomProxy) = await userSession.clientProxy.roomForIdentifier(roomID) {
                            await storeAndSubscribeToRoomProxy(roomProxy)
                            stateMachine.tryEvent(.presentRoom(presentationAction: nil), userInfo: EventUserInfo(animated: animated))
                            
                            flowParameters.analytics.trackJoinedRoom(isDM: roomProxy.infoPublisher.value.isDirect,
                                                                     isSpace: roomProxy.infoPublisher.value.isSpace,
                                                                     activeMemberCount: UInt(roomProxy.infoPublisher.value.activeMembersCount))
                        } else {
                            stateMachine.tryEvent(.dismissFlow, userInfo: EventUserInfo(animated: animated))
                        }
                    }
                case .joined(.space(let spaceRoomListProxy)):
                    stateMachine.tryEvent(.joinedSpace, userInfo: EventUserInfo(animated: true, spaceRoomListProxy: spaceRoomListProxy))
                case .cancelled:
                    stateMachine.tryEvent(.dismissJoinRoomScreen)
                case .presentDeclineAndBlock(let userID):
                    stateMachine.tryEvent(.presentDeclineAndBlockScreen(userID: userID))
                }
            }
            .store(in: &cancellables)
        
        if !isChildFlow {
            navigationStackCoordinator.setRootCoordinator(coordinator, animated: animated) { [weak self] in
                if self?.stateMachine.state == .joinRoomScreen {
                    self?.stateMachine.tryEvent(.dismissJoinRoomScreen)
                }
            }
        } else {
            navigationStackCoordinator.push(coordinator, animated: animated) { [weak self] in
                if self?.stateMachine.state == .joinRoomScreen {
                    self?.stateMachine.tryEvent(.dismissJoinRoomScreen)
                }
            }
        }
    }
    
    private func dismissFlow(animated: Bool, continuingWith spaceRoomListProxy: SpaceRoomListProxyProtocol? = nil) {
        childRoomFlowCoordinator?.clearRoute(animated: animated)
        
        if isChildFlow {
            // We don't support dismissing a child flow by itself, only the entire chain.
            MXLog.info("Leaving the rest of the navigation clean-up to the parent flow.")
            
            if joinRoomScreenCoordinator != nil {
                navigationStackCoordinator.pop()
            }
        } else {
            navigationStackCoordinator.popToRoot(animated: false)
            
            // Leave the root alone when it is about to be replaced by the space flow, otherwise when running on
            // iPhone the compact module diffs call the dismissal callback and we present a blank space flow 🙈
            if spaceRoomListProxy == nil {
                navigationStackCoordinator.setRootCoordinator(nil, animated: false)
                flowParameters.windowManager.closeSecondaryWindow(forType: .room(roomID: roomID))
            }
        }
        
        timelineController = nil
        
        if let spaceRoomListProxy {
            actionsSubject.send(.continueWithSpaceFlow(spaceRoomListProxy))
        } else {
            actionsSubject.send(.finished)
        }
    }
    
    private func presentRoomDetails(isRoot: Bool, animated: Bool) async {
        let params = RoomDetailsScreenCoordinatorParameters(roomProxy: roomProxy,
                                                            userSession: userSession,
                                                            analyticsService: flowParameters.analytics,
                                                            userIndicatorController: flowParameters.userIndicatorController,
                                                            notificationSettings: userSession.clientProxy.notificationSettings,
                                                            attributedStringBuilder: AttributedStringBuilder(mentionBuilder: PlainMentionBuilder()))
        let coordinator = RoomDetailsScreenCoordinator(parameters: params)
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .leftRoom:
                stateMachine.tryEvent(.dismissFlow)
            case .presentRoomMembersList:
                stateMachine.tryEvent(.startMembersFlow(entryPoint: .roomMembersList))
            case .presentAgents: // AGENT-PLATFORM (decision 192)
                stateMachine.tryEvent(.startAgentToolsFlow)
            case .presentRoomDetailsEditScreen:
                stateMachine.tryEvent(.presentRoomDetailsEditScreen)
            case .presentNotificationSettingsScreen:
                stateMachine.tryEvent(.presentNotificationSettingsScreen)
            case .presentInviteUsersScreen:
                stateMachine.tryEvent(.presentInviteUsersScreen(flow: .existingRoom))
            case .presentInviteToNewRoom(let mandatoryInvitee):
                stateMachine.tryEvent(.presentInviteUsersScreen(flow: .newRoom(mandatoryInvitee: mandatoryInvitee)))
            case .presentPollsHistory:
                stateMachine.tryEvent(.presentPollsHistory)
            case .presentRolesAndPermissionsScreen:
                stateMachine.tryEvent(.presentRolesAndPermissionsScreen)
            case .presentCall(isVoiceCall: let isVoiceCall):
                actionsSubject.send(.presentCallScreen(roomProxy: roomProxy, isVoiceCall: isVoiceCall))
            case .presentPinnedEventsTimeline:
                stateMachine.tryEvent(.presentPinnedEventsTimeline)
            case .presentKnockingRequestsListScreen:
                stateMachine.tryEvent(.presentKnockRequestsListScreen)
            case .presentMediaEventsTimeline:
                stateMachine.tryEvent(.presentMediaEventsTimeline)
            case .presentThreadList: // AGENT-PLATFORM (Brief 0083, decision 344)
                stateMachine.tryEvent(.presentThreadList)
            case .presentAgentRow(let row, let card): // AGENT-PLATFORM (Brief 0083, question 359)
                stateMachine.tryEvent(.startAgentRowFlow(row: row, card: card))
            case .presentSecurityAndPrivacyScreen:
                stateMachine.tryEvent(.presentSecurityAndPrivacyScreen)
            case .presentRecipientDetails(let userID):
                stateMachine.tryEvent(.startMembersFlow(entryPoint: .roomMember(userID: userID)))
            case .presentReportRoomScreen:
                stateMachine.tryEvent(.presentReportRoomScreen)
            case .transferOwnership:
                stateMachine.tryEvent(.presentTransferOwnershipScreen)
            }
        }
        .store(in: &cancellables)
        
        if isRoot {
            navigationStackCoordinator.setRootCoordinator(coordinator, animated: animated) { [weak self] in
                guard let self else { return }
                if stateMachine.state != .room { // The root has been replaced by a room
                    stateMachine.tryEvent(.dismissFlow)
                }
            }
        } else {
            navigationStackCoordinator.push(coordinator, animated: animated) { [weak self] in
                guard let self else { return }
                if case .roomDetails = stateMachine.state {
                    stateMachine.tryEvent(.dismissRoomDetails)
                }
            }
        }
    }
    
    private func presentKnockRequestsList() {
        let parameters = KnockRequestsListScreenCoordinatorParameters(roomProxy: roomProxy,
                                                                      mediaProvider: userSession.mediaProvider,
                                                                      userIndicatorController: flowParameters.userIndicatorController)
        let coordinator = KnockRequestsListScreenCoordinator(parameters: parameters)
        
        navigationStackCoordinator.push(coordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissKnockRequestsListScreen)
        }
    }
    
    private func presentRoomDetailsEditScreen() {
        let stackCoordinator = NavigationStackCoordinator()
        
        let roomDetailsEditParameters = RoomDetailsEditScreenCoordinatorParameters(roomProxy: roomProxy,
                                                                                   userSession: userSession,
                                                                                   mediaUploadingPreprocessor: MediaUploadingPreprocessor(userSettings: userSession.userSettings),
                                                                                   navigationStackCoordinator: stackCoordinator,
                                                                                   appMediator: flowParameters.appMediator,
                                                                                   userIndicatorController: flowParameters.userIndicatorController)
        let roomDetailsEditCoordinator = RoomDetailsEditScreenCoordinator(parameters: roomDetailsEditParameters)
        
        roomDetailsEditCoordinator.actions.sink { [weak self] action in
            switch action {
            case .dismiss:
                self?.navigationStackCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)
        
        stackCoordinator.setRootCoordinator(roomDetailsEditCoordinator)
        
        navigationStackCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissRoomDetailsEditScreen)
        }
    }
    
    // AGENT-PLATFORM (Brief 0066 step 6): "+" → Interactive post.
    //
    // Pick one of MY agents; in my DM with it, send the ROOT of a
    // generation thread — an ordinary text ("Interactive post for «X»")
    // carrying `com.spiral.interactive` OUTSIDE the text: the target room,
    // its name, its members. Then open that thread in a SHEET over this
    // room. The orchestrator recognises the key, not the prose: every
    // message in the thread goes straight to the generator, the draft
    // comes back into the thread with the target room on it, and
    // "Publish" on the draft's row posts it THERE and closes the sheet.
    // Like picking a video: choose, then send from where you were.
    private func presentInteractivePostAgentPicker() async {
        guard let agentPlatformService = userSession.agentPlatformService else {
            showErrorIndicator()
            return
        }

        let items: [AgentPickerItem]
        switch await InteractivePostAgentChoice(agentPlatformService.listMyPersonalAgents()) {
        case .agents(let agents):
            items = agents
        case .noAgents:
            flowParameters.userIndicatorController.submitIndicator(.init(id: "spiral-no-agents",
                                                                         type: .toast,
                                                                         title: UntranslatedL10n.screenRoomInteractivePostNoAgents))
            return
        case .readFailed:
            // AGENT-PLATFORM (agents-tab B11): a failed read is not "no agents"; «+» again retries.
            flowParameters.userIndicatorController.submitIndicator(.init(id: "spiral-no-agents",
                                                                         type: .toast,
                                                                         title: UntranslatedL10n.screenRoomInteractivePostAgentsFailure,
                                                                         icon: \.error))
            return
        }

        // A choice of one is not a choice: straight to the catalogue.
        if items.count == 1, let only = items.first {
            await presentInteractivePostCatalog(agents: [only])
            return
        }

        let coordinator = AgentPickerScreenCoordinator(parameters: .init(agents: items))

        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .selectAgent(let item):
                navigationStackCoordinator.setSheetCoordinator(nil)
                Task { await self.presentInteractivePostThread(with: item) }
            case .dismiss:
                navigationStackCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)

        let stackCoordinator = NavigationStackCoordinator()
        stackCoordinator.setRootCoordinator(coordinator)
        presentInteractivePostSheetCoordinator(stackCoordinator)
    }

    /// Every Interactive Post sheet goes up through here: the room's own
    /// posts stop while it covers them, and start again when the last of our
    /// sheets is gone (§ 5.80). A sheet replaced by the next one (picker →
    /// thread) is torn down first, so the check waits a turn of the loop.
    private func presentInteractivePostSheetCoordinator(_ stackCoordinator: NavigationStackCoordinator) {
        roomScreenCoordinator?.setInteractivePostsCovered(true)
        navigationStackCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.navigationStackCoordinator.sheetCoordinator == nil else { return }
                self.roomScreenCoordinator?.setInteractivePostsCovered(false)
                self.catalogueActions = nil
            }
        }
    }

    /// A catalogue link (decisions 111, 129): the catalogue on its template,
    /// for anyone. Browsing and Publish need no agent; the assistant's paths
    /// show only for someone who has one, and a failed read of the agents is
    /// not "no agents" — it only hides those paths. «+» keeps its own gate.
    private func presentInteractivePostCatalogForLink(templateID: String) async {
        let (agents, assistant) = await readAgentsForCatalogue()
        await presentInteractivePostCatalog(agents: agents, assistant: assistant, focusing: templateID)
    }

    /// The person's agents, and what the catalogue makes of them.
    private func readAgentsForCatalogue() async -> (agents: [AgentPickerItem], assistant: InteractivePostCatalogAssistant) {
        switch await userSession.agentPlatformService?.listMyPersonalAgents() {
        case .success(let view):
            let agents = view.agents.map { AgentPickerItem(agentID: $0.id, matrixUserID: $0.matrixUserID, displayName: $0.displayName, activeToolCount: 0) }
            let assistant: InteractivePostCatalogAssistant = if !agents.isEmpty {
                .available
            } else if view.provisioningStatus == .inProgress {
                .settingUp
            } else {
                .none
            }
            return (agents, assistant)
        case .failure(let error):
            MXLog.error("[SpiralApp] catalogue link without the agents: \(error)")
            return ([], .unknown)
        case nil:
            return ([], .unknown)
        }
    }

    /// The DM with each agent, where its generation threads are.
    private func directMessages(with agents: [AgentPickerItem]) async -> [JoinedRoomProxyProtocol] {
        let clientProxy = userSession.clientProxy
        var dms: [JoinedRoomProxyProtocol] = []
        for agent in agents {
            if case .success(let existing?) = clientProxy.directRoomForUserID(agent.matrixUserID),
               case .joined(let dm) = await clientProxy.roomForIdentifier(existing) {
                dms.append(dm)
            }
        }
        return dms
    }

    /// The catalogue: describe a new one, or pick one of yours — a
    /// generation thread in the DM with an agent — to change it or to
    /// publish it HERE, in the room it was opened in (§ 5.56). «+» opens it
    /// with its one agent; a catalogue link with all of them, or none.
    private func presentInteractivePostCatalog(agents: [AgentPickerItem],
                                               assistant: InteractivePostCatalogAssistant = .available,
                                               focusing templateID: String? = nil) async {
        // Read again in place by Retry, so every path below takes what is known now.
        let known = await CatalogueAgents(agents: agents, dms: directMessages(with: agents))

        let roomName = roomProxy.infoPublisher.value.displayName ?? roomProxy.id
        let room: JoinedRoomProxyProtocol = roomProxy
        let mediaProvider = userSession.mediaProvider
        let appSettings = userSession.userSettings.app
        let coordinator = InteractivePostCatalogScreenCoordinator(parameters: .init(roomName: roomName,
                                                                                    catalogURL: appSettings.interactiveCatalogURL,
                                                                                    dms: known.dms,
                                                                                    ownUserID: roomProxy.ownUserID,
                                                                                    initialTemplateID: templateID,
                                                                                    assistant: assistant,
                                                                                    hasSeenIntroduction: appSettings.hasSeenInteractivePostIntroduction,
                                                                                    introductionSeen: { appSettings.hasSeenInteractivePostIntroduction = true },
                                                                                    countPeople: {
                                                                                        await room.members().map { SpiralAppPostSession.people(in: $0).count }
                                                                                    },
                                                                                    loadMembers: {
                                                                                        await SpiralAppPostSession.membersPayload(room.members() ?? [], mediaProvider: mediaProvider)
                                                                                    }))
        let stackCoordinator = NavigationStackCoordinator()
        // Only ✕ closes it (question 412): a swipe down inside a post being tried closed the whole catalogue.
        stackCoordinator.isInteractiveDismissDisabled = true
        // Held alone, not with `cancellables`: it holds the screen, and the
        // pictures of what ran go with the sheet rather than with the room.
        catalogueActions = coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            // A thread opens ON the catalogue, not instead of it: «back» then
            // returns to the catalogue, as it did not when the catalogue was
            // closed first and the thread opened as its own sheet (operator,
            // 2026-09-25; § 5.61). Publishing closes the whole sheet.
            case .startNew(let description):
                chooseAgent(from: known.agents, onto: stackCoordinator) { [weak self] agent in
                    Task { await self?.presentInteractivePostThread(with: agent, describing: description, onto: stackCoordinator) }
                }
            case .openThread(let thread):
                guard let dm = known.dms.first(where: { $0.id == thread.dmRoomID }) else { return }
                let here = SpiralPublishRoom(id: roomProxy.id, name: roomName)
                Task {
                    await self.presentInteractivePostSheet(dm: dm,
                                                           threadRootEventID: thread.id,
                                                           targetRoomName: roomName,
                                                           publishRoom: here,
                                                           onto: stackCoordinator)
                }
            case .publishTemplate(let template):
                navigationStackCoordinator.setSheetCoordinator(nil)
                Task { await self.publishInteractiveTemplate(template, roomName: roomName) }
            case .changeTemplate(let template):
                chooseAgent(from: known.agents, onto: stackCoordinator) { [weak self] agent in
                    Task {
                        guard let self, let seed = await self.seed(of: template) else { return }
                        await self.presentInteractivePostThread(with: agent, seed: seed, onto: stackCoordinator)
                    }
                }
            case .showAgents:
                // The person's assistant appears on the Agents tab: the server sets it up, nothing in the app makes
                // one, so there is no "created" to come back here on (question 412).
                navigationStackCoordinator.setSheetCoordinator(nil)
                actionsSubject.send(.presentAgentsTab)
            case .retryAgents:
                // Only a link's catalogue can fail to read the agents (decision 129). It reads them again where it
                // is: closed for the read, the room showed bare and a sheet or a call in the gap was covered (B15).
                Task {
                    let (agents, assistant) = await self.readAgentsForCatalogue()
                    known.agents = agents
                    known.dms = await self.directMessages(with: agents)
                    coordinator.agentsRead(assistant, dms: known.dms)
                }
            case .showPost:
                stackCoordinator.push(coordinator.postCoordinator())
            case .showYours:
                stackCoordinator.push(coordinator.yoursCoordinator())
            case .cancel:
                navigationStackCoordinator.setSheetCoordinator(nil)
            }
        }
        
        // Not `coordinator.start()` here: `setRootCoordinator` starts it, and
        // started twice it subscribed twice, so every action ran twice — the
        // thread was pushed two deep and «back» took two taps (§ 5.63).
        stackCoordinator.setRootCoordinator(coordinator)
        presentInteractivePostSheetCoordinator(stackCoordinator)
    }

    /// The agent an assistant path of the catalogue runs with: the one, or —
    /// only once that path is chosen — the one picked on the catalogue's
    /// stack (decision 129: a ready template is shown before any question).
    private func chooseAgent(from agents: [AgentPickerItem],
                             onto stack: NavigationStackCoordinator,
                             then continuation: @escaping (AgentPickerItem) -> Void) {
        if agents.count == 1, let only = agents.first {
            continuation(only)
            return
        }
        guard !agents.isEmpty else { return } // The catalogue shows no assistant path then.

        // Back to the screen the picker was pushed from: the post page, Yours, or the catalogue.
        guard let below = stack.stackCoordinators.last ?? stack.rootCoordinator else { return }
        let picker = AgentPickerScreenCoordinator(parameters: .init(agents: agents))
        picker.actionsPublisher.sink { [weak stack] action in
            stack?.pop(to: below, animated: false)
            if case .selectAgent(let agent) = action {
                continuation(agent)
            }
        }
        .store(in: &cancellables)
        stack.push(picker)
    }

    /// The root's content: `body` for any client, the request for ours —
    /// with the app's language, which the thread speaks when the owner's
    /// words do not say («Уно, играем до 500 очков» has no letter only
    /// Russian has, and was answered in Ukrainian; § 5.60).
    static func interactivePostRequestContent(targetRoomID: String,
                                              targetRoomName: String,
                                              members: [(userID: String, name: String)],
                                              language: String = SpiralAppMount.appLanguage) -> [String: Any] {
        ["msgtype": "m.text",
         "body": UntranslatedL10n.screenRoomInteractivePostRequestBody(targetRoomName),
         "com.spiral.interactive": ["v": 1,
                                    "target_room_id": targetRoomID,
                                    "target_room_name": targetRoomName,
                                    "members": members.map { ["user_id": $0.userID, "name": $0.name] },
                                    "language": language]]
    }

    /// The owner's agent when there is exactly one — the one that made the
    /// post, then, and the one to change it with.
    private func onlyPersonalAgent() async -> AgentPickerItem? {
        guard let service = userSession.agentPlatformService,
              case .success(let view) = await service.listMyPersonalAgents(),
              view.agents.count == 1, let agent = view.agents.first else {
            return nil
        }
        return AgentPickerItem(agentID: agent.id, matrixUserID: agent.matrixUserID, displayName: agent.displayName, activeToolCount: 0)
    }

    /// Code a thread starts from, instead of words (§ 5.56).
    struct InteractiveSeed {
        let title: String
        let aspect: String
        let source: String
        /// What the agent asks beside Draft v1, when the template needs it.
        var asks: String?
    }

    private func seed(of template: SpiralAppTemplate) async -> InteractiveSeed? {
        showLoadingIndicator()
        defer { hideLoadingIndicator() }
        guard let source = await SpiralAppCatalog.source(of: template, from: flowParameters.userSession.userSettings.app.interactiveCatalogURL) else {
            showErrorIndicator()
            return nil
        }
        return InteractiveSeed(title: template.localizedTitle,
                               aspect: template.aspect,
                               source: source,
                               asks: template.localizedAsk)
    }

    /// A catalogue template into this room, as is: no agent, no model (§ 5.56).
    private func publishInteractiveTemplate(_ template: SpiralAppTemplate, roomName: String) async {
        showLoadingIndicator()
        defer { hideLoadingIndicator() }
        guard let files = await SpiralAppCatalog.files(of: template, from: flowParameters.userSession.userSettings.app.interactiveCatalogURL) else {
            showErrorIndicator()
            return
        }
        let room: JoinedRoomProxyProtocol = roomProxy
        let published = await SpiralAppPublisher.publish(template: files.manifestJSON,
                                                         source: files.module,
                                                         title: template.localizedTitle,
                                                         into: room,
                                                         clientProxy: userSession.clientProxy) { raw in
            await self.sendRaw(raw, into: room, over: self.navigationStackCoordinator)
        }
        switch published {
        case .success(let eventID):
            MXLog.info("[SpiralApp] published template \(template.id) into \(roomProxy.id) as \(eventID)")
            flowParameters.userIndicatorController.submitIndicator(.init(id: "spiral-published-into",
                                                                         type: .toast,
                                                                         title: UntranslatedL10n.screenRoomInteractiveDraftPublishedInto(roomName)))
            // The post lands at the bottom of the chat, as a sent message
            // does (§ 5.84); the sheet is already gone.
            roomScreenCoordinator?.scrollToBottom()
        case .failure(.send(.verifiedUser)):
            break // The user said «not now» on the resolve sheet (§ 5.87).
        case .failure(let error):
            MXLog.error("[SpiralApp] publishing template \(template.id) failed: \(error)")
            showErrorIndicator()
        }
    }

    /// `description`: what to make, in the person's words — what they searched the catalogue
    /// for and didn't find (question 412). It opens the thread as their first message.
    private func presentInteractivePostThread(with agent: AgentPickerItem,
                                              describing description: String? = nil,
                                              seed: InteractiveSeed? = nil,
                                              live: SpiralLivePost? = nil,
                                              onto stack: NavigationStackCoordinator? = nil) async {
        showLoadingIndicator()
        defer { hideLoadingIndicator() }

        let clientProxy = userSession.clientProxy
        let dmRoomID: String
        switch clientProxy.directRoomForUserID(agent.matrixUserID) {
        case .success(let existing?):
            dmRoomID = existing
        default:
            switch await clientProxy.createDirectRoom(with: agent.matrixUserID, expectedRoomName: agent.displayName) {
            case .success(let created):
                dmRoomID = created
            case .failure(let error):
                MXLog.error("[SpiralApp] could not open a DM with \(agent.matrixUserID): \(error)")
                showErrorIndicator()
                return
            }
        }
        guard case .joined(let dm) = await clientProxy.roomForIdentifier(dmRoomID) else {
            showErrorIndicator()
            return
        }

        // Members, not messages — the chat's text stays on the phone. And
        // people, not the agent: it is who the post is for (§ 5.64).
        let members = await (roomProxy.members() ?? [])
            .filter { $0.membership == .join && !SpiralAppPostSession.isAgent($0.userID) }
            .map { (userID: $0.userID, name: $0.disambiguatedDisplayName ?? $0.displayName ?? $0.userID) }
        let roomName = roomProxy.infoPublisher.value.displayName ?? roomProxy.id
        let content = Self.interactivePostRequestContent(targetRoomID: roomProxy.id, targetRoomName: roomName, members: members)
        guard let data = try? JSONSerialization.data(withJSONObject: content),
              let json = String(data: data, encoding: .utf8) else {
            showErrorIndicator()
            return
        }

        let rootEventID: String
        switch await sendRaw(json, into: dm, over: stack ?? navigationStackCoordinator) {
        case .success(let eventID):
            rootEventID = eventID
        case .failure(.verifiedUser):
            return // The user said «not now» on the resolve sheet (§ 5.87).
        case .failure:
            showErrorIndicator()
            return
        }

        // The live post first, then the code: a seed the agent has to repair
        // is then repaired knowing the post has been played (§ 5.55).
        let marker = live.flatMap { live in
            live.markerContent(action: "editing",
                               body: UntranslatedL10n.screenRoomInteractivePostMarkerEditing(seed?.title ?? "", live.roomName),
                               threadRootEventID: rootEventID)
        }
        let post = [marker, seed.flatMap { Self.seedContent($0, threadRootEventID: rootEventID) }].compactMap(\.self)
        let words = description.flatMap { Self.descriptionContent($0, threadRootEventID: rootEventID) }
        // A thread missing its code or the person's words would wait for nothing: say which, and what to do.
        let isPostSent = await Self.sendThreadOpeners(post, into: dm)
        let isWordsSent = await Self.sendThreadOpeners(words.map { [$0] } ?? [], into: dm)
        if let notice = Self.threadOpenerNotice(isPostSent: isPostSent, isWordsSent: isWordsSent) {
            flowParameters.userIndicatorController.submitIndicator(.init(title: notice))
        }

        await presentInteractivePostSheet(dm: dm, threadRootEventID: rootEventID, targetRoomName: roomName, onto: stack)
    }

    /// What the person is told when part of a thread's opening didn't go: the post (its code or the live post's marker)
    /// can only be started again from the post; their words can be typed again in the thread. Nil when all went.
    static func threadOpenerNotice(isPostSent: Bool, isWordsSent: Bool) -> String? {
        if !isPostSent {
            UntranslatedL10n.screenRoomInteractivePostCodeNotSent
        } else if !isWordsSent {
            UntranslatedL10n.screenRoomInteractivePostDescriptionNotSent
        } else {
            nil
        }
    }

    /// The thread's first messages after its root, in order. False when one didn't go: the thread still
    /// opens, with what did, and the caller tells the person.
    static func sendThreadOpeners(_ contents: [String], into dm: JoinedRoomProxyProtocol) async -> Bool {
        var isComplete = true
        for content in contents {
            if case .failure(let error) = await dm.sendSpiralRawEventReturningEventID(type: "m.room.message", content: content) {
                MXLog.error("[SpiralApp] a thread's opening message didn't send: \(error)")
                isComplete = false
            }
        }
        return isComplete
    }

    /// An Interactive Post's raw send (§ 5.87): when encryption refuses a
    /// verified user's devices or identity, the resolve sheet asks the user
    /// over `stack`, and the send is made again once they agree.
    private func sendRaw(_ content: String,
                         into room: JoinedRoomProxyProtocol,
                         over stack: NavigationStackCoordinator) async -> Result<String, RoomProxyError> {
        await RawSendResolution.send(roomProxy: room,
                                     present: { failure, resolver in
                                         // The modal spinner would sit over the sheet and take its taps.
                                         hideLoadingIndicator()
                                         presentResolveSendFailure(failure: failure, resolver: resolver, on: stack)
                                     },
                                     attempt: { await room.sendSpiralRawEventReturningEventID(type: "m.room.message", content: content) })
    }

    /// «📦 Starting from «…»» in the thread, carrying the code as
    /// `com.spiral.seed`: the agent answers it with that code as Draft v1.
    static func seedContent(_ seed: InteractiveSeed, threadRootEventID: String) -> String? {
        let content: [String: Any] = [
            "msgtype": "m.text",
            "body": "📦 " + UntranslatedL10n.screenRoomInteractivePostSeed(seed.title),
            "m.relates_to": ["rel_type": "m.thread",
                             "event_id": threadRootEventID,
                             "is_falling_back": true,
                             "m.in_reply_to": ["event_id": threadRootEventID]],
            "com.spiral.seed": ["title": seed.title, "aspect": seed.aspect, "source": seed.source]
                .merging(seed.asks.map { ["asks": $0] } ?? [:]) { first, _ in first }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: content) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The person's own words in the thread, as if typed there; nil when there are none.
    static func descriptionContent(_ description: String, threadRootEventID: String) -> String? {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let content: [String: Any] = [
            "msgtype": "m.text",
            "body": text,
            "m.relates_to": ["rel_type": "m.thread",
                             "event_id": threadRootEventID,
                             "is_falling_back": true,
                             "m.in_reply_to": ["event_id": threadRootEventID]]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: content) else { return nil }
        return String(bytes: data, encoding: .utf8)
    }

    /// «Change» on a published post: back to the thread it was made in (§ 5.55).
    ///
    /// The post's manifest names that thread (`origin`), inside what its
    /// digest covers. A note goes into the thread first — «📌 Changing …» with
    /// `com.spiral.live_post` — so the agent knows the post is live and keeps
    /// its state, and the thread's drafts offer to update THIS post in place.
    /// The code a thread about a published post starts from. The agent edits
    /// source, so a catalogue template published compiled (question 374)
    /// starts from the catalogue's source; one the catalogue no longer has,
    /// from the module it was published with, which is all there is. Nil
    /// when the catalogue couldn't be read.
    private func seedSource(of artifact: SpiralAppArtifact) async -> String? {
        let module = String(decoding: artifact.source, as: UTF8.self)
        guard artifact.manifest.isCompiled, artifact.manifest.appID.hasPrefix("tpl-") else {
            return module
        }
        let catalogURL = flowParameters.userSession.userSettings.app.interactiveCatalogURL
        switch await SpiralAppCatalog.resolve(String(artifact.manifest.appID.dropFirst(4)), from: catalogURL) {
        case .template(let template):
            return await SpiralAppCatalog.source(of: template, from: catalogURL)
        case .unknown, .needsNewerApp:
            return module
        case .unavailable:
            return nil
        }
    }

    private func presentInteractivePostEditor(eventID: String, post: SpiralAppPost, title: String) async {
        showLoadingIndicator()
        defer { hideLoadingIndicator() }

        let store = SpiralAppArtifactStore(mediaLoader: userSession.clientProxy.mediaLoader)
        guard case .success(let artifact) = await store.artifact(for: post) else {
            MXLog.error("[SpiralApp] could not load the artifact of \(eventID) to change it")
            showErrorIndicator()
            return
        }
        let roomName = roomProxy.infoPublisher.value.displayName ?? roomProxy.id
        let live = SpiralLivePost(roomID: roomProxy.id, eventID: eventID, roomName: roomName)
        guard let origin = artifact.manifest.origin else {
            // Made before it knew its thread: start one from its own code,
            // and its drafts update it all the same (§ 5.56).
            guard let agent = await onlyPersonalAgent() else {
                flowParameters.userIndicatorController.submitIndicator(.init(id: "spiral-no-origin",
                                                                             type: .toast,
                                                                             title: UntranslatedL10n.screenRoomInteractivePostNoOrigin))
                return
            }
            guard let source = await seedSource(of: artifact) else {
                showErrorIndicator()
                return
            }
            let seed = InteractiveSeed(title: title, aspect: artifact.manifest.aspect, source: source)
            await presentInteractivePostThread(with: agent, seed: seed, live: live)
            return
        }
        guard case .joined(let dm) = await userSession.clientProxy.roomForIdentifier(origin.roomID) else {
            MXLog.error("[SpiralApp] the thread of \(eventID) is in \(origin.roomID), which this user is not in")
            showErrorIndicator()
            return
        }

        if let marker = live.markerContent(action: "editing",
                                           body: UntranslatedL10n.screenRoomInteractivePostMarkerEditing(title, roomName),
                                           threadRootEventID: origin.threadRootEventID) {
            _ = await dm.sendSpiralRawEventReturningEventID(type: "m.room.message", content: marker)
        }

        await presentInteractivePostSheet(dm: dm, threadRootEventID: origin.threadRootEventID, targetRoomName: roomName)
    }

    /// The generation thread: pushed onto `stack` when the catalogue opened
    /// it, so «back» returns there; else in a sheet of its own over this room.
    private func presentInteractivePostSheet(dm: JoinedRoomProxyProtocol,
                                             threadRootEventID: String,
                                             targetRoomName: String,
                                             publishRoom: SpiralPublishRoom? = nil,
                                             onto stack: NavigationStackCoordinator? = nil) async {
        let timelineItemFactory = RoomTimelineItemFactory(userID: userSession.clientProxy.userID,
                                                          attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                                          stateEventStringBuilder: RoomStateEventStringBuilder(userID: userSession.clientProxy.userID))

        guard case let .success(timelineController) = await flowParameters.timelineControllerFactory.buildThreadTimelineController(threadRootEventID: threadRootEventID,
                                                                                                                                   initialFocussedEventID: nil,
                                                                                                                                   roomProxy: dm,
                                                                                                                                   timelineItemFactory: timelineItemFactory,
                                                                                                                                   mediaProvider: userSession.mediaProvider) else {
            MXLog.error("[SpiralApp] could not build the generation thread's timeline")
            showErrorIndicator()
            return
        }

        let completionSuggestionService = CompletionSuggestionService(roomProxy: dm,
                                                                      roomListPublisher: userSession.clientProxy.staticRoomSummaryProvider.roomListPublisher.eraseToAnyPublisher())
        let composerDraftService = ComposerDraftService(roomProxy: dm,
                                                        timelineItemfactory: timelineItemFactory,
                                                        threadRootEventID: threadRootEventID)

        let coordinator = ThreadTimelineScreenCoordinator(parameters: .init(userSession: userSession,
                                                                            roomProxy: dm,
                                                                            focussedEventID: nil,
                                                                            timelineController: timelineController,
                                                                            mediaPlayerProvider: MediaPlayerProvider(),
                                                                            emojiProvider: flowParameters.emojiProvider,
                                                                            linkMetadataProvider: flowParameters.linkMetadataProvider,
                                                                            completionSuggestionService: completionSuggestionService,
                                                                            appMediator: flowParameters.appMediator,
                                                                            analytics: flowParameters.analytics,
                                                                            composerDraftService: composerDraftService,
                                                                            timelineControllerFactory: flowParameters.timelineControllerFactory,
                                                                            userIndicatorController: flowParameters.userIndicatorController,
                                                                            spiralPublishRoom: publishRoom))

        // The stack the thread is shown on: the catalogue's, or a sheet of
        // its own.
        let host = stack ?? NavigationStackCoordinator()

        coordinator.actions.sink { [weak self, weak host] action in
            guard let self else { return }
            switch action {
            case .presentResolveSendFailure(let failure, let resolver):
                // § 5.87: a draft published raw, or a message of the
                // thread's own that the queue wedged — over the thread.
                guard let host else { return }
                presentResolveSendFailure(failure: failure, resolver: resolver, on: host)
            case .interactivePostPublished(let roomID):
                navigationStackCoordinator.setSheetCoordinator(nil)
                flowParameters.userIndicatorController.submitIndicator(.init(id: "spiral-published-into",
                                                                             type: .toast,
                                                                             title: UntranslatedL10n.screenRoomInteractiveDraftPublishedInto(targetRoomName)))
                // Published into THIS room: it lands at the bottom, as a
                // sent message does (§ 5.84).
                if roomID == roomProxy.id {
                    roomScreenCoordinator?.scrollToBottom()
                }
            case .presentRoomMemberDetails, .presentMessageForwarding, .presentReportContent, .presentEmojiPicker,
                 .presentMediaUploadPicker, .presentMediaUploadPreviewScreen, .presentLocationPicker, .presentLocationViewer,
                 .presentLiveLocationViewer, .presentPollForm:
                // The generation thread is for words and drafts; the rest of
                // a thread's surface is not offered from the sheet.
                MXLog.info("[SpiralApp] generation sheet ignores \(action)")
            }
        }
        .store(in: &cancellables)

        if stack != nil {
            host.push(coordinator)
        } else {
            host.setRootCoordinator(coordinator)
            presentInteractivePostSheetCoordinator(host)
        }
    }

    private func presentReportContent(for itemID: TimelineItemIdentifier, from senderID: String) {
        guard let eventID = itemID.eventID else {
            fatalError()
        }
        
        let stackCoordinator = NavigationStackCoordinator()
        let parameters = ReportContentScreenCoordinatorParameters(eventID: eventID,
                                                                  senderID: senderID,
                                                                  roomProxy: roomProxy,
                                                                  clientProxy: userSession.clientProxy,
                                                                  userIndicatorController: flowParameters.userIndicatorController)
        let coordinator = ReportContentScreenCoordinator(parameters: parameters)
        
        coordinator.actions
            .sink { [weak self] action in
                guard let self else { return }
                
                navigationStackCoordinator.setSheetCoordinator(nil)
                
                switch action {
                case .cancel:
                    break
                case .finish:
                    flowParameters.userIndicatorController.submitIndicator(UserIndicator(title: L10n.commonReportSubmitted, icon: \.check))
                }
            }
            .store(in: &cancellables)
        
        stackCoordinator.setRootCoordinator(coordinator)
        navigationStackCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissReportContent)
        }
    }
    
    private func presentMediaUploadPickerWithMode(_ mode: MediaPickerScreenMode,
                                                  caption: NSAttributedString,
                                                  timelineController: TimelineControllerProtocol,
                                                  animated: Bool) {
        let stackCoordinator = NavigationStackCoordinator()
        
        let mediaPickerCoordinator = MediaPickerScreenCoordinator(mode: mode,
                                                                  userIndicatorController: flowParameters.userIndicatorController,
                                                                  orientationManager: flowParameters.appMediator.windowManager) { [weak self] action in
            guard let self else {
                return
            }
            switch action {
            case .cancel:
                navigationStackCoordinator.setSheetCoordinator(nil)
            case .selectedMediaAtURLs(let urls):
                stateMachine.tryEvent(.presentMediaUploadPreview(mediaURLs: urls, caption: caption),
                                      userInfo: EventUserInfo(animated: animated, timelineController: timelineController))
            }
        }
        
        stackCoordinator.setRootCoordinator(mediaPickerCoordinator)
        
        navigationStackCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            if case .mediaUploadPicker = self?.stateMachine.state {
                self?.stateMachine.tryEvent(.dismissMediaUploadPicker)
            }
        }
    }
    
    private func presentMediaUploadPreviewScreen(for mediaURLs: [URL],
                                                 caption: NSAttributedString?,
                                                 timelineController: TimelineControllerProtocol,
                                                 animated: Bool) {
        let stackCoordinator = NavigationStackCoordinator()
        
        let title: String? = if mediaURLs.count == 1 {
            mediaURLs.first?.lastPathComponent
        } else {
            nil
        }
        
        let parameters = MediaUploadPreviewScreenCoordinatorParameters(mediaURLs: mediaURLs,
                                                                       caption: caption,
                                                                       title: title,
                                                                       mediaUploadingPreprocessor: MediaUploadingPreprocessor(userSettings: userSession.userSettings),
                                                                       timelineController: timelineController,
                                                                       clientProxy: userSession.clientProxy,
                                                                       userIndicatorController: flowParameters.userIndicatorController)
        
        let mediaUploadPreviewScreenCoordinator = MediaUploadPreviewScreenCoordinator(parameters: parameters)
        
        mediaUploadPreviewScreenCoordinator.actions
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .dismiss:
                    navigationStackCoordinator.setSheetCoordinator(nil)
                }
            }
            .store(in: &cancellables)
        
        stackCoordinator.setRootCoordinator(mediaUploadPreviewScreenCoordinator)
        
        navigationStackCoordinator.setSheetCoordinator(stackCoordinator, animated: animated) { [weak self] in
            self?.stateMachine.tryEvent(.dismissMediaUploadPreview)
        }
    }
    
    private func presentEmojiPicker(selectedEmojis: Set<String>,
                                    emojiPickerContinuation: EmojiPickerScreenContinuation,
                                    animated: Bool) {
        let params = EmojiPickerScreenCoordinatorParameters(mode: .reaction,
                                                            selectedEmojis: selectedEmojis,
                                                            emojiProvider: flowParameters.emojiProvider,
                                                            continuation: emojiPickerContinuation)
        let coordinator = EmojiPickerScreenCoordinator(parameters: params)
        
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .dismiss:
                navigationStackCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)
        
        navigationStackCoordinator.setSheetCoordinator(coordinator, animated: animated) { [weak self] in
            self?.stateMachine.tryEvent(.dismissEmojiPicker)
        }
    }
    
    private func presentMapNavigator(interactionMode: LocationSharingInteractionMode,
                                     timelineController: TimelineControllerProtocol,
                                     animated: Bool) {
        let stackCoordinator = NavigationStackCoordinator()
        
        let params = LocationSharingScreenCoordinatorParameters(interactionMode: interactionMode,
                                                                mapURLBuilder: userSession.userSettings.app.mapTilerConfiguration.publisher.value,
                                                                roomProxy: roomProxy,
                                                                timelineController: timelineController,
                                                                userSession: userSession,
                                                                appMediator: flowParameters.appMediator,
                                                                analytics: flowParameters.analytics,
                                                                userIndicatorController: flowParameters.userIndicatorController)
        let coordinator = LocationSharingScreenCoordinator(parameters: params)
        
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .close:
                self.navigationStackCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)
        
        stackCoordinator.setRootCoordinator(coordinator)
        
        navigationStackCoordinator.setSheetCoordinator(stackCoordinator, animated: animated) { [weak self] in
            self?.stateMachine.tryEvent(.dismissMapNavigator)
        }
    }
    
    private func presentPollForm(mode: PollFormMode, timelineController: TimelineControllerProtocol) {
        let stackCoordinator = NavigationStackCoordinator()
        let coordinator = PollFormScreenCoordinator(parameters: .init(mode: mode,
                                                                      timelineController: timelineController,
                                                                      analytics: flowParameters.analytics,
                                                                      userIndicatorController: flowParameters.userIndicatorController))
        stackCoordinator.setRootCoordinator(coordinator)
        
        coordinator.actions
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .close:
                    navigationStackCoordinator.setSheetCoordinator(nil)
                }
            }
            .store(in: &cancellables)
        
        navigationStackCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissPollForm)
        }
    }
    
    private func presentRoomPollsHistory(animated: Bool) async {
        let userID = userSession.clientProxy.userID
        
        let timelineItemFactory = RoomTimelineItemFactory(userID: userID,
                                                          attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                                          stateEventStringBuilder: RoomStateEventStringBuilder(userID: userID))
        
        let timelineController = flowParameters.timelineControllerFactory.buildTimelineController(roomProxy: roomProxy,
                                                                                                  initialFocussedEventID: nil,
                                                                                                  timelineItemFactory: timelineItemFactory,
                                                                                                  mediaProvider: userSession.mediaProvider)
        
        let parameters = RoomPollsHistoryScreenCoordinatorParameters(pollInteractionHandler: PollInteractionHandler(analyticsService: flowParameters.analytics,
                                                                                                                    timelineController: timelineController),
                                                                     timelineController: timelineController,
                                                                     userIndicatorController: flowParameters.userIndicatorController)
        let coordinator = RoomPollsHistoryScreenCoordinator(parameters: parameters)
        coordinator.actions
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .editPoll(let pollStartID, let poll):
                    stateMachine.tryEvent(.presentPollForm(mode: .edit(eventID: pollStartID, poll: poll)),
                                          userInfo: EventUserInfo(animated: animated, timelineController: timelineController))
                }
            }
            .store(in: &cancellables)
        
        navigationStackCoordinator.push(coordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissPollsHistory)
        }
    }
    
    private func presentMessageForwarding(with forwardingPayload: MessageForwardingPayload) {
        let roomSummaryProvider = userSession.clientProxy.alternateRoomSummaryProvider
        
        let stackCoordinator = NavigationStackCoordinator()
        
        let parameters = MessageForwardingScreenCoordinatorParameters(forwardingPayload: forwardingPayload,
                                                                      userSession: userSession,
                                                                      roomSummaryProvider: roomSummaryProvider,
                                                                      userIndicatorController: flowParameters.userIndicatorController)
        let coordinator = MessageForwardingScreenCoordinator(parameters: parameters)
        
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .dismiss:
                navigationStackCoordinator.setSheetCoordinator(nil)
            case .sent(let roomIDs):
                navigationStackCoordinator.setSheetCoordinator(nil)
                clearMessageSelection()
                processPostMessageForwardingTo(rooms: roomIDs)
            }
        }
        .store(in: &cancellables)
        
        stackCoordinator.setRootCoordinator(coordinator)
        
        navigationStackCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissMessageForwarding)
        }
    }
    
    /// Ends the message selection now that the forwarding has completed. Only one timeline can be selecting at a time.
    private func clearMessageSelection() {
        roomScreenCoordinator?.clearMessageSelection()
        childThreadScreenCoordinators.forEach { $0.clearMessageSelection() }
    }
    
    private func presentNotificationSettingsScreen() {
        let parameters = RoomNotificationSettingsScreenCoordinatorParameters(notificationSettingsProxy: userSession.clientProxy.notificationSettings,
                                                                             roomProxy: roomProxy,
                                                                             displayAsUserDefinedRoomSettings: false)
        
        let coordinator = RoomNotificationSettingsScreenCoordinator(parameters: parameters)
        coordinator.actions.sink { [weak self] actions in
            switch actions {
            case .presentGlobalNotificationSettingsScreen:
                self?.stateMachine.tryEvent(.presentGlobalNotificationSettingsScreen)
            }
        }
        .store(in: &cancellables)
        
        navigationStackCoordinator.push(coordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissNotificationSettingsScreen)
        }
    }
    
    private func presentGlobalNotificationSettingsScreen() {
        let stackCoordinator = NavigationStackCoordinator()
        let parameters = NotificationSettingsScreenCoordinatorParameters(navigationStackCoordinator: stackCoordinator,
                                                                         userSession: userSession,
                                                                         userNotificationCenter: UNUserNotificationCenter.current(),
                                                                         userIndicatorController: flowParameters.userIndicatorController,
                                                                         isModallyPresented: true)
        let coordinator = NotificationSettingsScreenCoordinator(parameters: parameters)
        coordinator.actions.sink { [weak self] action in
            switch action {
            case .close:
                self?.navigationStackCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)
        
        stackCoordinator.setRootCoordinator(coordinator)
        navigationStackCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissGlobalNotificationSettingsScreen)
        }
    }
    
    private func presentInviteUsersScreen(flow: InviteUsersFlow = .existingRoom) {
        let stackCoordinator = NavigationStackCoordinator()
        
        let roomType: InviteUsersScreenRoomType = switch flow {
        case .existingRoom: .existingRoom(roomProxy: roomProxy)
        case .newRoom(let mandatoryInvitee): .draft(mandatoryInvitees: [mandatoryInvitee])
        }
        
        let inviteParameters = InviteUsersScreenCoordinatorParameters(userSession: userSession,
                                                                      roomType: roomType,
                                                                      isSkippable: false,
                                                                      userDiscoveryService: UserDiscoveryService(clientProxy: userSession.clientProxy),
                                                                      userIndicatorController: flowParameters.userIndicatorController)
        
        let coordinator = InviteUsersScreenCoordinator(parameters: inviteParameters)
        stackCoordinator.setRootCoordinator(coordinator)
        
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .dismiss:
                navigationStackCoordinator.setSheetCoordinator(nil)
            case .openRoom(let roomID):
                guard case .newRoom = flow else { return }
                navigationStackCoordinator.setSheetCoordinator(nil)
                stateMachine.tryEvent(.startChildFlow(roomID: roomID, via: [], entryPoint: .room))
            }
        }
        .store(in: &cancellables)
        
        navigationStackCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissInviteUsersScreen)
        }
    }
    
    private func presentRolesAndPermissionsScreen() {
        let parameters = RoomRolesAndPermissionsFlowCoordinatorParameters(roomProxy: roomProxy,
                                                                          mediaProvider: userSession.mediaProvider,
                                                                          navigationStackCoordinator: navigationStackCoordinator,
                                                                          userIndicatorController: flowParameters.userIndicatorController,
                                                                          analytics: flowParameters.analytics)
        let coordinator = RoomRolesAndPermissionsFlowCoordinator(parameters: parameters)
        coordinator.actionsPublisher.sink { [weak self] action in
            switch action {
            case .complete:
                self?.stateMachine.tryEvent(.dismissRolesAndPermissionsScreen)
            }
        }
        .store(in: &cancellables)
        
        rolesAndPermissionsFlowCoordinator = coordinator
        coordinator.start()
    }
    
    // AGENT-PLATFORM (Brief 0066 § 5.87): takes the resolver (was a send
    // handle) and tells it when the sheet goes, so a raw send that waits on
    // the user's answer learns it was cancelled.
    private func presentResolveSendFailure(failure: TimelineItemSendFailure.VerifiedUser, resolver: VerifiedUserSendFailureResolver) {
        presentResolveSendFailure(failure: failure, resolver: resolver, on: navigationStackCoordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissResolveSendFailure)
        }
    }
    
    /// AGENT-PLATFORM (§ 5.87): the same sheet on any stack — the
    /// Interactive Post catalogue is a sheet of its own, and a failure that
    /// happens in it is shown over it, outside the room's state machine.
    private func presentResolveSendFailure(failure: TimelineItemSendFailure.VerifiedUser,
                                           resolver: VerifiedUserSendFailureResolver,
                                           on stack: NavigationStackCoordinator,
                                           dismissed: @escaping () -> Void = { }) {
        let coordinator = ResolveVerifiedUserSendFailureScreenCoordinator(parameters: .init(failure: failure,
                                                                                            resolver: resolver,
                                                                                            userIndicatorController: flowParameters.userIndicatorController))
        coordinator.actionsPublisher.sink { [weak stack] action in
            switch action {
            case .dismiss:
                stack?.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)
        
        stack.setSheetCoordinator(coordinator) {
            resolver.finished()
            dismissed()
        }
    }
    
    private func presentSecurityAndPrivacyScreen() {
        let coordinator = SecurityAndPrivacyScreenCoordinator(parameters: .init(roomProxy: roomProxy,
                                                                                userSession: userSession,
                                                                                userIndicatorController: flowParameters.userIndicatorController))
        
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .displayEditAddressScreen:
                presentEditAddressScreen()
            case .dismiss:
                navigationStackCoordinator.pop()
            case .displayManageAuthorizedSpacesScreen(let selection):
                stateMachine.tryEvent(.presentManageAuthorizedSpacesScreen, userInfo: EventUserInfo(animated: true, authorizedSpacesSelection: selection))
            }
        }
        .store(in: &cancellables)
        
        navigationStackCoordinator.push(coordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissSecurityAndPrivacyScreen)
        }
    }
    
    private func presentManageAuthorizedSpacesScreen(selection: AuthorizedSpacesSelection) {
        let navigationStack = NavigationStackCoordinator()
        let coordinator = ManageAuthorizedSpacesScreenCoordinator(parameters: .init(authorizedSpacesSelection: selection,
                                                                                    mediaProvider: flowParameters.userSession.mediaProvider))
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .dismiss:
                navigationStackCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)
        
        navigationStack.setRootCoordinator(coordinator)
        navigationStackCoordinator.setSheetCoordinator(navigationStack) { [weak self] in
            self?.stateMachine.tryEvent(.dismissedManageAuthorizedSpacesScreen)
        }
    }
    
    private func presentEditAddressScreen() {
        let stackCoordinator = NavigationStackCoordinator()
        let coordinator = EditRoomAddressScreenCoordinator(parameters: .init(roomProxy: roomProxy,
                                                                             clientProxy: userSession.clientProxy,
                                                                             userIndicatorController: flowParameters.userIndicatorController))
        
        coordinator.actionsPublisher.sink { [weak self] action in
            switch action {
            case .dismiss:
                self?.navigationStackCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)
        
        stackCoordinator.setRootCoordinator(coordinator)
        navigationStackCoordinator.setSheetCoordinator(stackCoordinator)
    }
    
    private func presentReportRoom() {
        let stackCoordinator = NavigationStackCoordinator()
        let coordinator = ReportRoomScreenCoordinator(parameters: .init(roomProxy: roomProxy,
                                                                        userIndicatorController: flowParameters.userIndicatorController))
        
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .dismiss(let shouldLeaveRoom):
                if shouldLeaveRoom {
                    stateMachine.tryEvent(.dismissFlow)
                }
                navigationStackCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)
        
        stackCoordinator.setRootCoordinator(coordinator)
        navigationStackCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissReportRoomScreen)
        }
    }
    
    private func presentDeclineAndBlockScreen(userID: String) {
        let stackCoordinator = NavigationStackCoordinator()
        let coordinator = DeclineAndBlockScreenCoordinator(parameters: .init(userID: userID,
                                                                             roomID: roomID,
                                                                             clientProxy: userSession.clientProxy,
                                                                             userIndicatorController: flowParameters.userIndicatorController))
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .dismiss(let hasDeclined):
                if hasDeclined {
                    stateMachine.tryEvent(.dismissFlow)
                }
                navigationStackCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)
        
        stackCoordinator.setRootCoordinator(coordinator)
        navigationStackCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissDeclineAndBlockScreen)
        }
    }
    
    private func processPostMessageForwardingTo(rooms roomIDs: [String]) {
        // Only open forwarding target room if single.
        guard roomIDs.count == 1, let roomID = roomIDs.last else {
            return
        }
        
        stateMachine.tryEvent(.startChildFlow(roomID: roomID, via: [], entryPoint: .room))
    }
    
    // MARK: - Other flows
    
    private func startChildFlow(for roomID: String, via: [String], entryPoint: RoomFlowCoordinatorEntryPoint) {
        let coordinator = RoomFlowCoordinator(roomID: roomID,
                                              isChildFlow: true,
                                              navigationStackCoordinator: navigationStackCoordinator,
                                              flowParameters: flowParameters)
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .presentCallScreen(let roomProxy, let isVoiceCall):
                actionsSubject.send(.presentCallScreen(roomProxy: roomProxy, isVoiceCall: isVoiceCall))
            case .presentAIConsentSettings: // AGENT-PLATFORM (decision 150)
                actionsSubject.send(.presentAIConsentSettings)
            case .presentAgentsTab: // AGENT-PLATFORM (question 412)
                actionsSubject.send(.presentAgentsTab)
            case .verifyUser(let userID):
                actionsSubject.send(.verifyUser(userID: userID))
            case .continueWithSpaceFlow(let spaceRoomListProxy):
                stateMachine.tryEvent(.startSpaceFlow, userInfo: EventUserInfo(animated: true, spaceRoomListProxy: spaceRoomListProxy))
            case .finished:
                stateMachine.tryEvent(.dismissChildFlow)
            }
        }
        .store(in: &cancellables)
        
        childRoomFlowCoordinator = coordinator
        switch entryPoint {
        case .room:
            coordinator.handleAppRoute(.room(roomID: roomID, via: via), animated: true)
        case .eventID(let eventID):
            coordinator.handleAppRoute(.event(eventID: eventID, roomID: roomID, via: via), animated: true)
        case .roomDetails:
            coordinator.handleAppRoute(.roomDetails(roomID: roomID), animated: true)
        case .share(let payload):
            coordinator.handleAppRoute(.share(payload), animated: true)
        case .transferOwnership:
            coordinator.handleAppRoute(.transferOwnership(roomID: roomID), animated: true)
        case .catalogTemplate(let templateID): // AGENT-PLATFORM (decision 111)
            coordinator.handleAppRoute(.catalogTemplate(templateID: templateID, roomID: roomID), animated: true)
        case .thread:
            fatalError("This entry point is not allowed for child flows")
        }
    }
    
    private func startPinnedEventsTimelineFlow() {
        let stackCoordinator = NavigationStackCoordinator()
        
        let flowCoordinator = PinnedEventsTimelineFlowCoordinator(roomProxy: roomProxy,
                                                                  navigationStackCoordinator: stackCoordinator,
                                                                  flowParameters: flowParameters)
        
        flowCoordinator.actionsPublisher.sink { [weak self] action in
            guard let self else {
                return
            }
            
            switch action {
            case .finished:
                navigationStackCoordinator.setSheetCoordinator(nil)
            case .displayUser(let userID):
                navigationStackCoordinator.setSheetCoordinator(nil)
                stateMachine.tryEvent(.startMembersFlow(entryPoint: .roomMember(userID: userID)))
            case .forwardedMessageToRooms(let roomIDs):
                navigationStackCoordinator.setSheetCoordinator(nil)
                processPostMessageForwardingTo(rooms: roomIDs)
            case .displayRoomScreenWithFocussedPin(let eventID, let threadRootEventID):
                navigationStackCoordinator.setSheetCoordinator(nil)
                if let threadRootEventID {
                    stateMachine.tryEvent(.presentRoom(presentationAction: .thread(rootEventID: threadRootEventID, focusEvent: .init(eventID: eventID, shouldSetPin: true))))
                } else {
                    stateMachine.tryEvent(.presentRoom(presentationAction: .eventFocus(.init(eventID: eventID, shouldSetPin: true))))
                }
            }
        }
        .store(in: &cancellables)
        
        pinnedEventsTimelineFlowCoordinator = flowCoordinator
        
        navigationStackCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissPinnedEventsTimeline)
        }
        
        flowCoordinator.start()
    }
    
    private func startMediaEventsTimelineFlow() async {
        let flowCoordinator = MediaEventsTimelineFlowCoordinator(roomProxy: roomProxy,
                                                                 navigationStackCoordinator: navigationStackCoordinator,
                                                                 flowParameters: flowParameters)
        
        flowCoordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .viewInRoomTimeline(let itemID):
                guard let eventID = itemID.eventID else {
                    MXLog.error("Unable to present room timeline for event \(itemID)")
                    
                    return
                }
                stateMachine.tryEvent(.presentRoom(presentationAction: .eventFocus(.init(eventID: eventID, shouldSetPin: false))),
                                      userInfo: EventUserInfo(animated: false)) // No animation so the timeline visible when the preview animates away.
            case .finished:
                stateMachine.tryEvent(.dismissMediaEventsTimeline)
            case .displayMessageForwarding(let forwardingPayload):
                stateMachine.tryEvent(.presentMessageForwarding(forwardingPayload: forwardingPayload))
            }
        }
        .store(in: &cancellables)
        
        mediaEventsTimelineFlowCoordinator = flowCoordinator
        
        flowCoordinator.start()
    }
    
    private func startSpaceFlow(spaceRoomListProxy: SpaceRoomListProxyProtocol, animated: Bool) {
        let coordinator = SpaceFlowCoordinator(entryPoint: .space(spaceRoomListProxy),
                                               spaceServiceProxy: userSession.clientProxy.spaceService,
                                               isChildFlow: true,
                                               navigationStackCoordinator: navigationStackCoordinator,
                                               flowParameters: flowParameters)
        coordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .presentCallScreen(let roomProxy, let isVoiceCall):
                    actionsSubject.send(.presentCallScreen(roomProxy: roomProxy, isVoiceCall: isVoiceCall))
                case .presentAIConsentSettings: // AGENT-PLATFORM (decision 150)
                    actionsSubject.send(.presentAIConsentSettings)
                case .presentAgentsTab: // AGENT-PLATFORM (question 412)
                    actionsSubject.send(.presentAgentsTab)
                case .verifyUser(let userID):
                    actionsSubject.send(.verifyUser(userID: userID))
                case .finished:
                    stateMachine.tryEvent(.finishedSpaceFlow)
                }
            }
            .store(in: &cancellables)
        
        spaceFlowCoordinator = coordinator
        
        coordinator.start(animated: animated)
    }
    
    private func startMembersFlow(entryPoint: RoomMembersFlowCoordinatorEntryPoint, animated: Bool) {
        let flowCoordinator = RoomMembersFlowCoordinator(entryPoint: entryPoint,
                                                         roomProxy: roomProxy,
                                                         navigationStackCoordinator: navigationStackCoordinator,
                                                         flowParameters: flowParameters,
                                                         showOriginRoom: { [weak self] in self?.showTimeline(ifRoomID: $0) ?? false })
        
        flowCoordinator.actions.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .finished:
                stateMachine.tryEvent(.stopMembersFlow)
            case .presentCallScreen(let roomProxy, let isVoiceCall):
                actionsSubject.send(.presentCallScreen(roomProxy: roomProxy, isVoiceCall: isVoiceCall))
            case .presentAIConsentSettings: // AGENT-PLATFORM (decision 150)
                actionsSubject.send(.presentAIConsentSettings)
            case .presentAgentsTab: // AGENT-PLATFORM (question 412)
                actionsSubject.send(.presentAgentsTab)
            case .verifyUser(let userID):
                actionsSubject.send(.verifyUser(userID: userID))
            }
        }
        .store(in: &cancellables)
        
        flowCoordinator.start(animated: animated)
        membersFlowCoordinator = flowCoordinator
    }
    
    private static let loadingIndicatorID = "\(RoomFlowCoordinator.self)-Loading"
    
    private func showLoadingIndicator(delay: Duration? = nil,
                                      title: String = L10n.commonLoading,
                                      message: String? = nil) {
        flowParameters.userIndicatorController.submitIndicator(.init(id: Self.loadingIndicatorID,
                                                                     type: .modal(progress: .indeterminate,
                                                                                  interactiveDismissDisabled: false,
                                                                                  allowsInteraction: false),
                                                                     title: title,
                                                                     message: message,
                                                                     persistent: true),
                                                               delay: delay)
    }
    
    private func hideLoadingIndicator() {
        flowParameters.userIndicatorController.retractIndicatorWithId(Self.loadingIndicatorID)
    }
    
    private func showErrorIndicator() {
        flowParameters.userIndicatorController.submitIndicator(.init(title: L10n.errorUnknown))
    }
}

/// AGENT-PLATFORM (1.0.3, B15): what an open catalogue knows of the person's agents, read again in place by its Retry.
private final class CatalogueAgents {
    var agents: [AgentPickerItem]
    var dms: [JoinedRoomProxyProtocol]
    
    init(agents: [AgentPickerItem], dms: [JoinedRoomProxyProtocol]) {
        self.agents = agents
        self.dms = dms
    }
}
