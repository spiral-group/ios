//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
import MatrixRustSDK
import OrderedCollections
import SwiftUI

typealias RoomScreenViewModelType = StateStoreViewModel<RoomScreenViewState, RoomScreenViewAction>

class RoomScreenViewModel: RoomScreenViewModelType, RoomScreenViewModelProtocol {
    private let clientProxy: ClientProxyProtocol
    private let roomProxy: JoinedRoomProxyProtocol
    private let userSettings: UserSettings
    // AGENT-PLATFORM (Brief 0072, ADR-0083): the DM recipient's presence while
    // this screen is open; observed on open, released in `stop()`.
    private let presenceObserverService: PresenceObserverServiceProtocol?
    private let agentsStore: AgentsStore?
    private var dmPresenceObservation: PresenceObservation?
    private let analyticsService: AnalyticsServiceProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    // AGENT-PLATFORM: optional — nil when no orchestrator is configured
    // (Brief 0036). Drives the in-chat active-tools banner.
    private let agentPlatformService: (any AgentPlatformServiceProtocol)?
    /// AGENT-PLATFORM (Brief 0044): the REST snapshot of the room's active
    /// tools, read once at room open. Seeds the banner so a tool armed long
    /// ago (whose `com.spiral.tools` event has scrolled out of the live
    /// timeline window) still shows. The timeline is authoritative for any
    /// agent it mentions; the seed only fills in agents the timeline window
    /// says nothing about. Empty until the snapshot resolves.
    private var restSeedEvents: [SpiralToolsStateReader.ParsedEvent] = []
    
    private var initialSelectedPinnedEventID: String?
    private let pinnedEventStringBuilder: RoomEventStringBuilder
    
    private var identityPinningViolations = [String: RoomMemberProxyProtocol]()
    private var identityVerificationViolations = [String: RoomMemberProxyProtocol]()
    
    private let actionsSubject: PassthroughSubject<RoomScreenViewModelAction, Never> = .init()
    var actions: AnyPublisher<RoomScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    private var pinnedEventsTimelineItemProvider: TimelineItemProviderProtocol? {
        didSet {
            guard let pinnedEventsTimelineItemProvider else {
                return
            }
            
            buildPinnedEventContents(timelineItems: pinnedEventsTimelineItemProvider.itemProxies)
            pinnedEventsTimelineItemProvider.updatePublisher
                // When pinning or unpinning an item, the timeline might return empty for a short while, so we need to debounce it to prevent weird UI behaviours like the banner disappearing
                .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
                .sink { [weak self] updatedItems, _ in
                    guard let self else { return }
                    buildPinnedEventContents(timelineItems: updatedItems)
                }
                .store(in: &cancellables)
        }
    }
    
    init(userSession: UserSessionProtocol,
         roomProxy: JoinedRoomProxyProtocol,
         initialSelectedPinnedEventID: String?,
         ongoingCallRoomIDPublisher: CurrentValuePublisher<String?, Never>,
         analyticsService: AnalyticsServiceProtocol,
         userIndicatorController: UserIndicatorControllerProtocol) {
        clientProxy = userSession.clientProxy
        presenceObserverService = userSession.presenceObserverService
        agentsStore = userSession.agentsStore
        self.roomProxy = roomProxy
        userSettings = userSession.userSettings
        self.analyticsService = analyticsService
        self.userIndicatorController = userIndicatorController
        agentPlatformService = userSession.agentPlatformService
        
        self.initialSelectedPinnedEventID = initialSelectedPinnedEventID
        pinnedEventStringBuilder = .pinnedEventStringBuilder(userID: roomProxy.ownUserID)
        
        let viewState = RoomScreenViewState(roomTitle: roomProxy.infoPublisher.value.displayNameOrID,
                                            roomAvatar: roomProxy.infoPublisher.value.avatar,
                                            isNativeCallingEnabled: userSettings.app.nativeCallEnabled,
                                            hasOngoingCall: roomProxy.infoPublisher.value.hasRoomCall,
                                            isDM: roomProxy.infoPublisher.value.isDM,
                                            hasSuccessor: roomProxy.infoPublisher.value.successor != nil,
                                            roomHistorySharingState: roomProxy.infoPublisher.value.historySharingState)
        super.init(initialViewState: userSession.userHooks.roomScreenHook.update(viewState),
                   mediaProvider: userSession.mediaProvider)
        
        updateRoomInfo(roomProxy.infoPublisher.value)
        setupSubscriptions(ongoingCallRoomIDPublisher: ongoingCallRoomIDPublisher)
        
        Task {
            await updateVerificationBadge()
        }

        // AGENT-PLATFORM (Brief 0044, ADR-0058): the all-participant tools
        // banner is HYBRID — a REST snapshot seed + live timeline deltas.
        //
        // The live timeline (`com.spiral.tools` state + `m.room.member` events,
        // read from each item's raw `debugInfo.originalJSON`) is the LIVE
        // source: one `updatePublisher` subscription covers arming/disabling a
        // tool, an agent leaving (its tools drop out), and an agent rejoining +
        // re-arming (its tools reappear the instant those events land). We do
        // NOT use `roomProxy.membersPublisher` — it isn't reactive to
        // mid-session membership changes (only refreshed on room entry /
        // member-list open), which left the banner stale after a leave→rejoin.
        //
        // But the live timeline is a SLIDING WINDOW: in a long chat a tool
        // armed long ago (with no change since) has its state event outside the
        // loaded window, so a timeline-only banner would be blank on open. So
        // we ALSO seed once from `GET /rooms/{room}/tools` — the authoritative
        // snapshot of every in-room agent's current tools. The timeline stays
        // authoritative for any agent it mentions; the seed only fills in
        // agents whose event scrolled out of the window. Snapshot is read once
        // on open (timeline keeps it live thereafter). See `SpiralToolsState
        // Reader.aggregate(rawEventJSONs:seed:)`.
        buildActiveToolsBanner(timelineItems: roomProxy.timeline.timelineItemProvider.itemProxies)
        roomProxy.timeline.timelineItemProvider.updatePublisher
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] updatedItems, _ in
                self?.buildActiveToolsBanner(timelineItems: updatedItems)
            }
            .store(in: &cancellables)
        seedActiveToolsBanner()
    }

    /// Read the REST snapshot once and rebuild the banner with it as the
    /// seed. Best-effort: a failed snapshot just leaves the banner
    /// timeline-only (its previous behaviour).
    private func seedActiveToolsBanner() {
        guard let agentPlatformService else { return }
        Task { [weak self] in
            guard let self else { return }
            guard case let .success(roomTools) = await agentPlatformService.fetchRoomTools(roomID: roomProxy.id) else {
                return
            }
            restSeedEvents = SpiralToolsStateReader.seedEvents(fromRoomTools: roomTools, seedTime: Date())
            buildActiveToolsBanner(timelineItems: roomProxy.timeline.timelineItemProvider.itemProxies)
        }
    }

    // MARK: - Agent tools banner (Brief 0044 / ADR-0058, hybrid seed + timeline)

    /// Aggregate the REST snapshot seed + the room timeline's
    /// `com.spiral.tools` events into ONE banner item per active tool. The
    /// seed (read once at open) covers tools whose event scrolled out of the
    /// live window; live timeline deltas override it by timestamp. Drops
    /// agents whose latest event cleared all tools or who have departed the
    /// room, then unrolls every remaining agent's tools so the banner tap
    /// rotates through each tool.
    private func buildActiveToolsBanner(timelineItems: [TimelineItemProxy]) {
        let rawJSONs: [String] = timelineItems.compactMap { item in
            guard case let .event(eventProxy) = item else { return nil }
            return eventProxy.debugInfo.originalJSON
        }
        // AGENT-PLATFORM (Brief 0066 § 5.89): `ownUserID` lets the agent-tools
        // fallback count, from this server's agents only.
        let entries = SpiralToolsStateReader.aggregate(rawEventJSONs: rawJSONs,
                                                       seed: restSeedEvents,
                                                       ownUserID: roomProxy.ownUserID)
        // Drop agents whose LATEST timeline membership is leave/ban — a
        // departed agent's stale `com.spiral.tools` event must not keep its
        // tools in the banner. Derived from the same timeline (see
        // `departedMemberIDs`), so a rejoining agent reappears the instant
        // its join event lands.
        let departed = SpiralToolsStateReader.departedMemberIDs(rawEventJSONs: rawJSONs)
        let liveEntries = SpiralToolsStateReader.filterDeparted(entries: entries, departedMemberIDs: departed)
        let items = SpiralToolsStateReader.flatten(entries: liveEntries).map { flat in
            BannerToolItem(id: flat.id,
                           title: toolTitle(for: flat.tool),
                           icon: ToolDisplayName.icon(forKind: flat.tool.kind),
                           agentMatrixUserID: flat.entry.agentMatrixUserID)
        }
        guard !items.isEmpty else {
            state.activeToolsBannerState = .loading
            return
        }
        state.activeToolsBannerState.setItems(items)
    }

    /// A compact, localized line for a single tool — its name only.
    /// Translate shows the target language ("Translating to English"); every
    /// other kind (including the call-artifact tools) shows its localized name
    /// via `ToolDisplayName`, so a call summary / recording tool never falls
    /// back to a raw "Call_summary" tag.
    private func toolTitle(for tool: ToolsBannerEntry.Tool) -> String {
        if tool.kind == "translate" || tool.kind == "live_translate",
           let language = tool.targetLanguage {
            return UntranslatedL10n.screenAgentToolsListTitleTranslate(TranslationLanguageDisplayName.localizedName(for: language))
        }
        return ToolDisplayName.name(forKind: tool.kind)
    }

    override func process(viewAction: RoomScreenViewAction) {
        switch viewAction {
        case .tappedPinnedEventsBanner:
            handleTappedPinnedEventsBanner()
        case .viewAllPins:
            analyticsService.trackInteraction(name: .PinnedMessageBannerViewAllButton)
            actionsSubject.send(.displayPinnedEventsTimeline)
        case .tappedActiveToolsBanner:
            actionsSubject.send(.displayAgentTools)
        case .rotateActiveToolsBanner:
            state.activeToolsBannerState.rotate()
        case .displayRoomDetails:
            actionsSubject.send(.displayRoomDetails)
        case .displayCall(let isVoiceCall):
            actionsSubject.send(.displayCall(isVoiceCall: isVoiceCall))
            actionsSubject.send(.removeComposerFocus)
            analyticsService.trackInteraction(name: .MobileRoomCallButton)
        case .footerViewAction(let action):
            switch action {
            case .resolvePinViolation(let userID):
                Task { await resolveIdentityPinningViolation(userID) }
            case .resolveVerificationViolation(let userID):
                Task { await resolveIdentityVerificationViolation(userID) }
            }
        case .acceptKnock(let eventID):
            Task { await acceptKnock(eventID: eventID) }
        case .dismissKnockRequests:
            Task { await markAllKnocksAsSeen() }
        case .viewKnockRequests:
            actionsSubject.send(.displayKnockRequests)
        case .displaySuccessorRoom:
            guard let successorID = roomProxy.infoPublisher.value.successor?.roomId else { return }
            let serverNames = roomProxy.knownServerNames(maxCount: 50) // Limit to the same number used by ClientProxy.resolveRoomAlias(_:)
            actionsSubject.send(.displayRoom(roomID: successorID, via: Array(serverNames)))
        case .tappedStopLiveLocation:
            actionsSubject.send(.stopLiveLocationSharing)
        case .tappedOpenLiveLocation:
            actionsSubject.send(.displayLiveLocation)
        }
    }
    
    func stop() {
        // AGENT-PLATFORM (Brief 0072, ADR-0083)
        dmPresenceObservation = nil
        // Work around QLPreviewController dismissal issues, see the InteractiveQuickLookModifier.
        state.bindings.mediaPreviewViewModel = nil
    }
    
    func timelineHasScrolled(direction: ScrollDirection) {
        state.lastScrollDirection = direction
    }
    
    func setSelectedPinnedEventID(_ eventID: String) {
        state.pinnedEventsBannerState.setSelectedPinnedEventID(eventID)
    }

    // AGENT-PLATFORM: re-pull the active tools so the banner reflects an
    // arm / edit / disable from the agent-tools sheet (Brief 0036 F2).
    func refreshAgentToolsBanner() {
        // Brief 0044: banner is timeline-driven; nothing to refetch here.
    }
    
    func displayMediaPreview(_ mediaPreviewViewModel: TimelineMediaPreviewViewModel) {
        mediaPreviewViewModel.actions.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .dismiss:
                state.bindings.mediaPreviewViewModel = nil
            case .displayMessageForwarding(let forwardingPayload):
                state.bindings.mediaPreviewViewModel = nil
                // We need a small delay because we need to wait for the media preview to be fully dismissed.
                DispatchQueue.main.asyncAfter(deadline: .now() + TimelineMediaPreviewViewModel.displayMessageForwardingDelay) {
                    self.actionsSubject.send(.displayMessageForwarding(forwardingPayload))
                }
            case .viewInRoomTimeline:
                fatalError("\(action) should not be visible on a room preview.")
            }
        }
        .store(in: &cancellables)
        
        state.bindings.mediaPreviewViewModel = mediaPreviewViewModel
    }
    
    // MARK: - Private
    
    private func setupSubscriptions(ongoingCallRoomIDPublisher: CurrentValuePublisher<String?, Never>) {
        userSettings.account.liveLocationSharingSessionsByRoomIDPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessionsByRoomID in
                guard let self else { return }
                state.isSharingLiveLocation = sessionsByRoomID.keys.contains(roomProxy.id)
            }
            .store(in: &cancellables)
        
        roomProxy.infoPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] roomInfo in
                self?.updateRoomInfo(roomInfo)
            }
            .store(in: &cancellables)
        
        let identityStatusChangesPublisher = roomProxy.identityStatusChangesPublisher.receive(on: DispatchQueue.main)
        
        Task { [weak self] in
            for await changes in identityStatusChangesPublisher.values {
                guard !Task.isCancelled else {
                    return
                }
                
                await self?.processIdentityStatusChanges(changes)
                await self?.updateVerificationBadge()
            }
        }
        .store(in: &cancellables)
        
        clientProxy.homeserverReachabilityPublisher
            .filter { $0 == .reachable }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupPinnedEventsTimelineItemProviderIfNeeded()
            }
            .store(in: &cancellables)
        
        ongoingCallRoomIDPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ongoingCallRoomID in
                guard let self else { return }
                state.isParticipatingInOngoingCall = ongoingCallRoomID == roomProxy.id
            }
            .store(in: &cancellables)
        
        roomProxy.knockRequestsStatePublisher
            // We only care about unseen requests
            .map { knockRequestsState in
                guard case let .loaded(requests) = knockRequestsState else {
                    return []
                }
                
                return requests
                    .filter { !$0.isSeen }
                    .map(KnockRequestInfo.init)
            }
            // If the requests have the same event ids we can discard the output
            .removeDuplicates { Set($0.map(\.eventID)) == Set($1.map(\.eventID)) }
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .weakAssign(to: \.state.unseenKnockRequests, on: self)
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.roomProxy.timeline.retryDecryption(sessionIDs: nil)
            }
            .store(in: &cancellables)
    }
    
    private func processIdentityStatusChanges(_ changes: [IdentityStatusChange]) async {
        for change in changes {
            switch change.changedTo {
            case .pinViolation:
                guard case let .success(member) = await roomProxy.getMember(userID: change.userId) else {
                    MXLog.error("Failed retrieving room member for identity status change: \(change)")
                    continue
                }
                
                identityPinningViolations[change.userId] = member
            case .verificationViolation:
                guard case let .success(member) = await roomProxy.getMember(userID: change.userId) else {
                    MXLog.error("Failed retrieving room member for identity status change: \(change)")
                    continue
                }
                
                identityVerificationViolations[change.userId] = member
            default:
                identityVerificationViolations[change.userId] = nil
                identityPinningViolations[change.userId] = nil
            }
        }
        
        if let member = identityVerificationViolations.values.first {
            state.footerDetails = .verificationViolation(member: member,
                                                         learnMoreURL: userSettings.app.identityPinningViolationDetailsURL)
        } else if let member = identityPinningViolations.values.first {
            state.footerDetails = .pinViolation(member: member,
                                                learnMoreURL: userSettings.app.identityPinningViolationDetailsURL)
        } else {
            state.footerDetails = nil
        }
    }
    
    private func updateVerificationBadge() async {
        // The DM's person, as presence reads it: an agent added to the DM is a member too.
        guard roomProxy.infoPublisher.value.isDM,
              let dmUserID = roomProxy.infoPublisher.value.dmUserID,
              case let .success(userIdentity) = await clientProxy.userIdentity(for: dmUserID, fallBackToServer: true) else {
            state.dmRecipientDetails.verification = .notVerified
            return
        }
        
        guard let userIdentity else {
            MXLog.failure("User identity should be known at this point")
            state.dmRecipientDetails.verification = .notVerified
            return
        }
        
        state.dmRecipientDetails.verification = userIdentity.verificationState
    }
    
    private func resolveIdentityPinningViolation(_ userID: String) async {
        defer {
            hideLoadingIndicator()
        }
        
        showLoadingIndicator()
        
        if case .failure = await clientProxy.pinUserIdentity(userID) {
            state.bindings.alertInfo = .init(id: .unknown, title: L10n.commonError)
        }
    }
    
    private func resolveIdentityVerificationViolation(_ userID: String) async {
        defer {
            hideLoadingIndicator()
        }
        
        showLoadingIndicator()
        
        if case .failure = await clientProxy.withdrawUserIdentityVerification(userID) {
            state.bindings.alertInfo = .init(id: .unknown, title: L10n.commonError)
        }
    }
    
    private func buildPinnedEventContents(timelineItems: [TimelineItemProxy]) {
        var pinnedEventContents = OrderedDictionary<String, AttributedString>()
        
        for item in timelineItems {
            // Only remote events are pinned
            if case let .event(event) = item,
               let eventID = event.id.eventID {
                pinnedEventContents.updateValue(pinnedEventStringBuilder.buildAttributedString(for: event) ?? AttributedString(L10n.commonUnsupportedEvent),
                                                forKey: eventID)
            }
        }
        
        state.pinnedEventsBannerState.setPinnedEventContents(pinnedEventContents)
        
        // If it's the first time we are setting the pinned events, we should select the initial event if available.
        if let initialSelectedPinnedEventID {
            state.pinnedEventsBannerState.setSelectedPinnedEventID(initialSelectedPinnedEventID)
            self.initialSelectedPinnedEventID = nil
        }
    }
    
    // AGENT-PLATFORM (Brief 0072, ADR-0083): follow the DM's other person.
    private func observeDMPresence(_ dmUserID: String?) {
        guard dmUserID != dmPresenceObservation?.userID else { return }
        dmPresenceObservation = nil
        state.dmRecipientDetails.presence = nil
        dmPresenceObservation = PresenceObservation(userID: dmUserID,
                                                    ownUserID: roomProxy.ownUserID,
                                                    service: presenceObserverService,
                                                    agentsStore: agentsStore) { [weak self] presence in
            self?.state.dmRecipientDetails.presence = presence
        }
    }
    
    private func updateRoomInfo(_ roomInfo: RoomInfoProxyProtocol) {
        state.roomTitle = roomInfo.displayNameOrID
        state.roomAvatar = roomInfo.avatar
        state.dmRecipientDetails.statusEmoji = roomInfo.statusEmoji
        observeDMPresence(roomInfo.dmUserID)
        // AGENT-PLATFORM (Brief 0083, question 392): no count yet is no line, never «0 members».
        state.memberCount = roomInfo.isDM || roomInfo.joinedMembersCount < 1 ? nil : roomInfo.joinedMembersCount
        state.hasOngoingCall = roomInfo.hasRoomCall
        state.activeRoomCallIntent = roomInfo.activeRoomCallIntent
        state.hasSuccessor = roomInfo.successor != nil
        state.isDM = roomInfo.isDM
        // AGENT-PLATFORM (Brief 0063/0067): every non-DM room offers a voice call (ADR-0079 D3).
        state.canStartGroupVoiceCall = !roomInfo.isDM
        
        let pinnedEventIDs = roomInfo.pinnedEventIDs
        // Only update the loading state of the banner
        if state.pinnedEventsBannerState.isLoading {
            state.pinnedEventsBannerState = .loading(numbersOfEvents: pinnedEventIDs.count)
        }
        
        switch (roomInfo.isDM, roomInfo.joinRule) {
        case (false, .knock), (false, .knockRestricted):
            state.isKnockableRoom = true
        default:
            state.isKnockableRoom = false
        }
        
        if let powerLevels = roomInfo.powerLevels {
            state.canSendMessage = powerLevels.canOwnUser(sendMessage: .roomMessage)
            state.canJoinCall = powerLevels.canOwnUserJoinCall()
            state.canAcceptKnocks = powerLevels.canOwnUserInvite()
            state.canDeclineKnocks = powerLevels.canOwnUserKick()
            state.canBan = powerLevels.canOwnUserBan()
        }
        
        state.roomHistorySharingState = roomInfo.historySharingState
    }
    
    private func setupPinnedEventsTimelineItemProviderIfNeeded() {
        guard pinnedEventsTimelineItemProvider == nil else {
            return
        }
        
        Task {
            guard case let .success(pinnedEventsTimeline) = await roomProxy.pinnedEventsTimeline() else {
                return
            }
            
            if pinnedEventsTimelineItemProvider == nil {
                pinnedEventsTimelineItemProvider = pinnedEventsTimeline.timelineItemProvider
            }
        }
    }
    
    private func acceptKnock(eventID: String) async {
        guard case let .loaded(requests) = roomProxy.knockRequestsStatePublisher.value,
              let request = requests.first(where: { $0.eventID == eventID }) else {
            return
        }
        
        state.handledEventIDs.insert(eventID)
        switch await request.accept() {
        case .success:
            break
        case .failure:
            userIndicatorController.submitIndicator(.init(id: Self.errorIndicatorIdentifier, type: .toast, title: L10n.errorUnknown))
            state.handledEventIDs.remove(eventID)
        }
    }
    
    private func markAllKnocksAsSeen() async {
        guard case let .loaded(requests) = roomProxy.knockRequestsStatePublisher.value else {
            return
        }
        state.handledEventIDs.formUnion(Set(requests.map(\.eventID)))
        
        let failedIDs = await withTaskGroup(of: (String, Result<Void, KnockRequestProxyError>).self) { group in
            for request in requests {
                group.addTask {
                    await (request.eventID, request.markAsSeen())
                }
            }
            
            var failedIDs = [String]()
            for await result in group where result.1.isFailure {
                failedIDs.append(result.0)
            }
            return failedIDs
        }
        state.handledEventIDs.subtract(failedIDs)
    }
    
    private func handleTappedPinnedEventsBanner() {
        analyticsService.trackInteraction(name: .PinnedMessageBannerClick)
        if let eventID = state.pinnedEventsBannerState.selectedPinnedEventID {
            Task {
                switch await roomProxy.loadOrFetchEventDetails(for: eventID) {
                case .success(let event):
                    if userSettings.app.threadsEnabled,
                       let threadRootEventID = event.threadRootEventId() {
                        actionsSubject.send(.focusEvent(eventID: threadRootEventID))
                        actionsSubject.send(.displayThread(threadRootEventID: threadRootEventID, focussedEventID: eventID))
                    } else {
                        actionsSubject.send(.focusEvent(eventID: eventID))
                    }
                case .failure:
                    userIndicatorController.submitIndicator(.init(title: L10n.errorUnknown))
                }
            }
        }
        state.pinnedEventsBannerState.previousPin()
    }
    
    // MARK: Loading indicators
    
    private static let loadingIndicatorIdentifier = "\(RoomScreenViewModel.self)-Loading"
    private static let errorIndicatorIdentifier = "\(RoomScreenViewModel.self)-Error"
    
    private func showLoadingIndicator() {
        userIndicatorController.submitIndicator(.init(id: Self.loadingIndicatorIdentifier, type: .toast, title: L10n.commonLoading))
    }
    
    private func hideLoadingIndicator() {
        userIndicatorController.retractIndicatorWithId(Self.loadingIndicatorIdentifier)
    }
}

extension RoomScreenViewModel {
    static func mock(roomProxyMock: JoinedRoomProxyMock,
                     userSession: UserSessionProtocol = UserSessionMock(.init())) -> RoomScreenViewModel {
        RoomScreenViewModel(userSession: userSession,
                            roomProxy: roomProxyMock,
                            initialSelectedPinnedEventID: nil,
                            ongoingCallRoomIDPublisher: .init(.init(nil)),
                            analyticsService: AnalyticsServiceMock(.init()),
                            userIndicatorController: UserIndicatorControllerMock())
    }
}

private extension KnockRequestInfo {
    init(from proxy: KnockRequestProxyProtocol) {
        self.init(displayName: proxy.displayName,
                  avatarURL: proxy.avatarURL,
                  userID: proxy.userID,
                  reason: proxy.reason,
                  eventID: proxy.eventID)
    }
}
