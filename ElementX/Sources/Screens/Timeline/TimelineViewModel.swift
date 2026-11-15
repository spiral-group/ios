//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Algorithms
import Combine
import MatrixRustSDK
import OrderedCollections
import SwiftUI

typealias TimelineViewModelType = StateStoreViewModel<TimelineViewState, TimelineViewAction>

/// Stops a room's apps when the timeline that owned them goes away.
///
/// Not private so a test can drop one and watch the apps go: the wiring is one
/// line in the view model, and the moment it describes had no coverage at all
/// until this existed.
///
/// AGENT-PLATFORM (Brief 0066, step 7.8). A web view is far too expensive to
/// let its lifetime depend on who happens to release the last reference. It was
/// measured (2026-09-15): leaving a room with three posts running deallocated
/// the view model but NOT the registry, and three `WKWebView`s plus their
/// WebContent processes stayed alive — three visits to one room left nine. The
/// app's own footprint showed almost none of it, because WebKit's cost lives in
/// other processes.
///
/// This is an object rather than a `deinit` on the view model because the base
/// class's `deinit` is MainActor-isolated and cannot be overridden with a
/// nonisolated one. Its only job is to die at the right moment, which it does
/// even when the registry itself is still held by something else — and stopping
/// the apps is what actually matters, not freeing the bookkeeping around them.
final class SpiralAppTeardown {
    private let registry: SpiralAppHostRegistry

    init(registry: SpiralAppHostRegistry) {
        self.registry = registry
    }

    deinit {
        // Hops to the main actor because the registry is isolated to it. The
        // capture keeps the registry alive until the hop lands, which is the
        // point: something has to be there to take the apps down.
        let registry = registry
        Task { @MainActor in registry.releaseAll() }
    }
}

// AGENT-PLATFORM: the Interactive Post and agent hooks push the upstream class over the 1000-line cap.
// swiftlint:disable:next type_body_length
class TimelineViewModel: TimelineViewModelType, TimelineViewModelProtocol {
    private enum Constants {
        static let paginationEventLimit: UInt16 = 20
        static let openingPaginationEventLimit: UInt16 = 100
        static let openingPageLimit = 5
        static let openingLoadingIndicatorDelay = Duration.milliseconds(500)
        static let detachedTimelineSize: UInt16 = 100
        static let focusTimelineToastIndicatorID = "RoomScreenFocusTimelineToastIndicator"
        static let toastErrorID = "RoomScreenToastError"
        static let selectionLimitIndicatorID = "RoomScreenSelectionLimitIndicator"
    }
    
    // AGENT-PLATFORM (Brief 0066): `TimelineViewModel+InteractiveDraft` is
    // an extension in its own file — the class is at SwiftLint's body limit
    // — and a file-level extension cannot see `private`.
    let roomProxy: JoinedRoomProxyProtocol
    let timelineController: TimelineControllerProtocol
    let userSession: UserSessionProtocol
    private let mediaPlayerProvider: MediaPlayerProviderProtocol
    let userIndicatorController: UserIndicatorControllerProtocol
    private let appMediator: AppMediatorProtocol
    private let userSettings: UserSettings
    private let analyticsService: AnalyticsServiceProtocol
    private let emojiProvider: EmojiProviderProtocol
    
    private let timelineInteractionHandler: TimelineInteractionHandler
    
    private let composerFocusedSubject = PassthroughSubject<Bool, Never>()
    
    let actionsSubject: PassthroughSubject<TimelineViewModelAction, Never> = .init()
    var actions: AnyPublisher<TimelineViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    private var currentUserProxy: RoomMemberProxyProtocol?
    
    private var paginateBackwardsTask: Task<Void, Never>?
    private var paginateForwardsTask: Task<Void, Never>?
    
    /// Takes this room's apps down when the timeline goes. See its own doc.
    private var spiralAppTeardown: SpiralAppTeardown?
    
    // AGENT-PLATFORM (Brief 0083, question 359): what "New" and the scroll button's dot go by.
    private var seenRows: TimelineSeenRows
    /// When the chat opened or the app last became active.
    private var cameBackAt = Date.now
    /// You've left the chat, so going to the background has no visit left to end.
    private var hasStopped = false
    /// The unread may reach further back than the loaded rows, as the chat opened with some or a limited sync left a gap. Writing ends that.
    private var opensWithUnread: Bool
    /// You wrote since these rows loaded, or read to the end once the app gave up on what's above, which ends what `m.fully_read` waits for.
    private var mayPassUnloadedRows = false
    /// The app went looking for the first unread and gave up, so the newest row reads the chat to the end, as in any chat, and
    /// the count can't stick on rows it couldn't reach. The operator's call. A limited sync's gap isn't this: it holds, as the
    /// next opening can still reach it.
    private var hasGivenUpLoadingRows = false
    /// The event `m.fully_read` was last requested for. One request each: a failed one waits for the next new row, or for leaving.
    private var fullyReadRequestEventID: String?
    /// When the event `m.fully_read` names was sent, known once one that isn't loaded has been looked up.
    private var fullyReadDate: Date?
    /// The event last looked up. One lookup each.
    private var fullyReadLookupEventID: String?
    /// That lookup failed, which says nothing of where the event is: a network fails as readily as an event goes for good.
    private var hasFullyReadLookupFailed = false
    
    // AGENT-PLATFORM (Brief 0083, question 363): how long a chat will wait for the first unread before opening at the end.
    private var openingPagesLeft = Constants.openingPageLimit
    private var openingTimeLimitTask: Task<Void, Never>?
    var openingTimeLimit = Duration.seconds(4)

    init(roomProxy: JoinedRoomProxyProtocol,
         focussedEventID: String? = nil,
         timelineController: TimelineControllerProtocol,
         userSession: UserSessionProtocol,
         mediaPlayerProvider: MediaPlayerProviderProtocol,
         userIndicatorController: UserIndicatorControllerProtocol,
         appMediator: AppMediatorProtocol,
         analyticsService: AnalyticsServiceProtocol,
         emojiProvider: EmojiProviderProtocol,
         linkMetadataProvider: LinkMetadataProviderProtocol,
         timelineControllerFactory: TimelineControllerFactoryProtocol) {
        self.roomProxy = roomProxy
        self.timelineController = timelineController
        self.userSession = userSession
        self.mediaPlayerProvider = mediaPlayerProvider
        userSettings = userSession.userSettings
        self.analyticsService = analyticsService
        self.userIndicatorController = userIndicatorController
        self.appMediator = appMediator
        self.emojiProvider = emojiProvider
        seenRows = TimelineSeenRows(ownUserID: roomProxy.ownUserID)
        opensWithUnread = roomProxy.infoPublisher.value.unreadMessagesCount > 0
        
        let voiceMessageRecorder = VoiceMessageRecorder(audioRecorder: AudioRecorder(), mediaPlayerProvider: mediaPlayerProvider)
        
        timelineInteractionHandler = TimelineInteractionHandler(roomProxy: roomProxy,
                                                                timelineController: timelineController,
                                                                userSession: userSession,
                                                                mediaPlayerProvider: mediaPlayerProvider,
                                                                voiceMessageRecorder: voiceMessageRecorder,
                                                                userIndicatorController: userIndicatorController,
                                                                appMediator: appMediator,
                                                                analyticsService: analyticsService,
                                                                emojiProvider: emojiProvider,
                                                                linkMetadataProvider: linkMetadataProvider,
                                                                timelineControllerFactory: timelineControllerFactory)
        
        let hideTimelineMedia = switch userSession.clientProxy.timelineMediaVisibilityPublisher.value {
        case .always:
            false
        case .privateOnly:
            !(roomProxy.infoPublisher.value.isPrivate ?? true)
        case .never:
            true
        }
        super.init(initialViewState: TimelineViewState(timelineKind: timelineController.timelineKind,
                                                       allowedGalleryItemTypes: timelineController.allowedGalleryItemTypes,
                                                       roomID: roomProxy.id,
                                                       isDM: roomProxy.infoPublisher.value.isDM,
                                                       timelineState: TimelineState(focussedEvent: focussedEventID.map { .init(eventID: $0, appearance: .immediate) }),
                                                       ownUserID: roomProxy.ownUserID,
                                                       hideTimelineMedia: hideTimelineMedia,
                                                       isViewSourceEnabled: userSettings.app.viewSourceEnabled,
                                                       areThreadsEnabled: userSettings.app.threadsEnabled,
                                                       linkPreviewsEnabled: userSettings.app.linkPreviewsEnabled,
                                                       jumpToReadMarkerEnabled: userSettings.app.jumpToReadMarkerEnabled,
                                                       hasPredecessor: roomProxy.predecessorRoom != nil,
                                                       pinnedEventIDs: roomProxy.infoPublisher.value.pinnedEventIDs,
                                                       emojiProvider: emojiProvider,
                                                       linkMetadataProvider: hideTimelineMedia ? nil : linkMetadataProvider,
                                                       mapTilerConfiguration: userSettings.app.mapTilerConfiguration.publisher.value,
                                                       bindings: .init(reactionsCollapsed: [:])),
                   mediaProvider: userSession.mediaProvider,
                   contentScannerService: userSession.contentScannerService)
        
        if focussedEventID != nil {
            // The timeline controller will start loading a detached timeline.
            showFocusLoadingIndicator()
        }
        
        setupSubscriptions()
        setupRowContextSubscription()
        setupDirectRoomSubscriptionsIfNeeded()
        
        // AGENT-PLATFORM (Brief 0066, step 7.4): one registry per timeline, so
        // apps belong to the room they are in rather than to the app. Sharing
        // one across rooms would let posts nobody is looking at hold web views.
        //
        // Leaving the room stops them — through `SpiralAppTeardown` below, not
        // through this registry being freed, which it measurably was not
        // (§5.25). The hosts are unbound: the registry's pool binds each one
        // to a post's session per mount.
        state.spiralAppHosts = SpiralAppHostRegistry(artifacts: .init(mediaLoader: userSession.clientProxy.mediaLoader),
                                                     roomProxy: roomProxy,
                                                     mediaProvider: userSession.mediaProvider) {
            SpiralAppWebViewHost()
        }

        if let registry = state.spiralAppHosts {
            spiralAppTeardown = SpiralAppTeardown(registry: registry)
            // AGENT-PLATFORM (§ 5.87): a post's refused action asks the user — only where this
            // timeline's coordinator shows the resolve sheet; pinned events and
            // media drop the action, and a question nobody sees would hold every
            // later move for ever.
            switch timelineController.timelineKind {
            case .live, .detached, .thread:
                registry.sendRefusals = SpiralAppSendRefusals(roomProxy: roomProxy) { [weak self] failure, resolver in
                    self?.actionsSubject.send(.displayResolveSendFailure(failure: failure, resolver: resolver))
                }
            case .pinned, .media:
                break
            }
        }

        state.audioPlayerStateProvider = { [weak self] itemID -> AudioPlayerState? in
            guard let self else {
                return nil
            }
            
            return self.timelineInteractionHandler.audioPlayerState(for: itemID)
        }
        
        state.pillContextUpdater = { [weak self] pillContext in
            self?.pillContextUpdater(pillContext)
        }
        
        state.roomNameForIDResolver = { [weak self] roomID in
            self?.userSession.clientProxy.roomSummaryForIdentifier(roomID)?.name
        }
        
        state.roomNameForAliasResolver = { [weak self] alias in
            self?.userSession.clientProxy.roomSummaryForAlias(alias)?.name
        }
        
        installSpiralMembersResolver()
        installSpiralDisplayNameResolver() // AGENT-PLATFORM (decision 38)
        installSpiralAIConsentResolver() // AGENT-PLATFORM (decision 150)
        
        state.timelineState.paginationState = timelineController.paginationState
        // AGENT-PLATFORM (Brief 0083, question 363): where the chat opens hangs on `m.fully_read`, and a link's target comes first.
        state.timelineState.opening = focussedEventID == nil && state.timelineKind == .live ? .undecided : .settled
        updateRoomInfo(roomProxy.infoPublisher.value)
        buildTimelineViews(timelineItems: timelineController.timelineItems)
        
        updateMembers(roomProxy.membersPublisher.value)
        
        // Note: beware if we get to e.g. restore a reply / edit,
        // maybe we are tracking a non-needed first initial state
        trackComposerMode(.default)
    }
    
    // MARK: - Public
    
    override func process(viewAction: TimelineViewAction) {
        switch viewAction {
        case .itemAppeared(let id):
            Task { await timelineController.processItemAppearance(id) }
        case .itemDisappeared(let id):
            Task { await timelineController.processItemDisappearance(id) }
        case .mediaTapped(let id):
            Task { await handleMediaTapped(with: id) }
        case .galleryItemTapped(let galleryItemID):
            Task { await handleMediaTapped(with: galleryItemID.timelineItemID, galleryIndex: galleryItemID.mediaIndex) }
        case .itemSendInfoTapped(let itemID):
            handleItemSendInfoTapped(itemID: itemID)
        case .publishInteractiveDraft(let itemID):
            Task { await publishInteractiveDraft(itemID: itemID) }
        case .publishInteractiveDraftAsNew(let itemID):
            Task { await publishInteractiveDraft(itemID: itemID, asNew: true) }
        case .toggleReaction(let emoji, let itemID):
            emojiProvider.markEmojiAsFrequentlyUsed(emoji)
            
            guard case let .event(_, eventOrTransactionID) = itemID else {
                fatalError()
            }
            
            Task { await timelineController.toggleReaction(emoji, to: eventOrTransactionID) }
        case .sendReadReceiptIfNeeded(let lastVisibleItemID):
            Task { await sendReadReceiptIfNeeded(for: lastVisibleItemID) }
        case .paginateBackwards:
            paginateBackwards()
        case .paginateForwards:
            paginateForwards()
        case .scrollToBottom:
            scrollToBottom()
        case .scrollToFirstItemForCurrentDate:
            state.timelineState.scrollToFirstItemForDatePublisher.send()
        case .scrollToReadMarker:
            Task { await scrollToReadMarker() }
        case .markAllAsRead:
            state.bindings.hasNewMessagesAtBottom = false
            Task {
                _ = await roomProxy.markAsRead(receiptType: .fullyRead)
                // Clear locally so the jump-to-unread button hides without waiting
                // for the SDK to push a refreshed RoomInfo. Doing this after the
                // await means any stale RoomInfo update racing the mark-as-read
                // call has already landed and can't overwrite this clear.
                state.timelineState.fullyReadEventID = nil
            }
        case .displayTimelineItemMenu(let itemID):
            timelineInteractionHandler.displayTimelineItemActionMenu(for: itemID)
        case .handleTimelineItemMenuAction(let itemID, .forward) where state.canSelectMessages:
            startSelection(itemID: itemID)
        case .handleTimelineItemMenuAction(let itemID, let action):
            timelineInteractionHandler.handleTimelineItemMenuAction(action, itemID: itemID)
        case .redactConfirmed(let itemID, let reason):
            state.bindings.redactConfirmationInfo = nil
            // A blank reason is no reason at all, so don't send one.
            timelineInteractionHandler.redact(itemID, reason: reason?.isBlank == false ? reason : nil)
        case .toggleMessageSelection(let itemID):
            toggleSelection(itemID: itemID)
        case .clearMessageSelection:
            clearMessageSelection()
        case .forwardMessageSelection:
            forwardSelection()
        case .tappedOnSenderDetails(let sender):
            handleTappedOnSenderDetails(sender: sender)
        case .displayEmojiPicker(let itemID):
            timelineInteractionHandler.displayEmojiPicker(for: itemID)
        case .displayReactionSummary(let itemID, let key):
            displayReactionSummary(for: itemID, selectedKey: key)
        case .displayThread(let itemID):
            actionsSubject.send(.displayThread(itemID: itemID))
        case .handlePasteOrDrop(let providers):
            timelineInteractionHandler.handlePasteOrDrop(providers)
        case .handlePollAction(let pollAction):
            handlePollAction(pollAction)
        case .handleAudioPlayerAction(let audioPlayerAction):
            handleAudioPlayerAction(audioPlayerAction)
        case .stopLiveLocationSharing(let id):
            state.stoppedLiveLocationIDs.insert(id)
            Task { await stopLiveLocationSharing() }
        case .focusOnEventID(let eventID):
            Task { await focusOnEvent(eventID: eventID) }
        case .focusLive:
            focusLive()
        case .scrolledToFocussedItem:
            didScrollToFocussedItem()
        case .scrolledAwayFromFocussedItem:
            didScrollAwayFromFocussedItem()
        case .hasSettledOpening(let isAwayFromEnd):
            Task { didSettleOpening(isAwayFromEnd: isAwayFromEnd) } // The table is in the middle of a view update.
        case .hasSwitchedTimeline:
            Task { state.timelineState.isSwitchingTimelines = false }
        case let .hasScrolled(direction):
            actionsSubject.send(.hasScrolled(direction: direction))
        case .displayPredecessorRoom:
            guard let predecessorID = roomProxy.predecessorRoom?.roomId else {
                fatalError("Predecessor room should exist if this action is triggered.")
            }
            let serverNames = roomProxy.knownServerNames(maxCount: 50) // Limit to the same number used by ClientProxy.resolveRoomAlias(_:)
            actionsSubject.send(.displayRoom(roomID: predecessorID, via: Array(serverNames)))
        case .joinActiveCall(let isVoiceCall):
            actionsSubject.send(.presentCallScreen(isVoiceCall: isVoiceCall))
        case .openAIConsentSettings: // AGENT-PLATFORM (decision 150)
            actionsSubject.send(.displayAIConsentSettings)
        }
    }
    
    func process(composerAction: ComposerToolbarViewModelAction) {
        switch composerAction {
        case .sendMessage(let message, let html, let mode, let intentionalMentions):
            Task {
                await sendCurrentMessage(message,
                                         html: html,
                                         mode: mode,
                                         intentionalMentions: intentionalMentions)
            }
        case .editLastMessage:
            editLastMessage()
        case .attach(let attachment):
            attach(attachment)
        case .presentAgentTools, .presentInteractivePostAgentPicker:
            // AGENT-PLATFORM: handled by RoomScreenCoordinator (routed to the
            // flow, not the timeline) — never reaches here in practice.
            break
        case .handlePasteOrDrop(let providers):
            timelineInteractionHandler.handlePasteOrDrop(providers)
        case .composerModeChanged(mode: let mode):
            trackComposerMode(mode)
        case .composerFocusedChanged(isFocused: let isFocused):
            composerFocusedSubject.send(isFocused)
        case .voiceMessage(let voiceMessageAction):
            processVoiceMessageAction(voiceMessageAction)
        case .contentChanged(let isEmpty):
            guard userSettings.account.sharePresence else {
                return
            }
            
            Task {
                await roomProxy.sendTypingNotification(isTyping: !isEmpty)
            }
        }
    }
    
    func focusOnEvent(eventID: String) async {
        // AGENT-PLATFORM (Brief 0083, question 363): the target comes first.
        if state.timelineState.opening != .settled {
            settleOpening()
        }
        
        if state.timelineState.hasLoadedItem(with: eventID) {
            state.timelineState.focussedEvent = .init(eventID: eventID, appearance: .animated)
            return
        }
        
        showFocusLoadingIndicator()
        defer {
            hideFocusLoadingIndicator()
        }
        
        switch await timelineController.focusOnEvent(eventID, timelineSize: Constants.detachedTimelineSize) {
        case .success:
            state.timelineState.focussedEvent = .init(eventID: eventID, appearance: .immediate)
        case .failure(let error):
            MXLog.error("Failed to focus on event \(eventID)")
            
            if case .eventNotFound = error {
                displayErrorToast(L10n.errorMessageNotFound)
            } else {
                displayErrorToast(L10n.commonFailed)
            }
        }
    }
    
    func stopLiveLocationSharing() async {
        await userSession.liveLocationService.stopLiveLocation(roomID: roomProxy.id)
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 363): a page on its way keeps this view model alive after you've left, and the
    /// table can outlast this on its way off screen. So the opening stops here rather than with them, or its toast stays
    /// over the chat list, and a page landing now could open the way for the receipts of rows you never saw.
    func stop() {
        hasStopped = true
        if state.timelineState.opening != .settled {
            settleOpening(at: .abandoned)
        }
        markSeenRowsAsRead()
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 359): going to the background ends the visit, as leaving does (the operator,
    /// 2026-11-12). The receipts go now, while the app still runs, so a launch after iOS ends it finds no "New" above what
    /// you read and answered. "New" from before goes in the same pass, unseen, so coming back shows nothing jump: what
    /// arrived meanwhile is marked afresh, and the SDK's own marker, once `m.fully_read` reaches it, lands in the same place.
    /// Only the room's live timeline, and only once the chat has opened: an opening still on its way carries on. Internal for
    /// the tests, which call it rather than post the notification every live view model in the process would hear.
    func endVisit() {
        guard !hasStopped, appMediator.appState != .active, state.timelineKind == .live, state.timelineState.opening == .settled else {
            return
        }
        
        seenRows.endVisit()
        markSeenRowsAsRead()
        if tracksSeenRows {
            buildTimelineViews(timelineItems: timelineController.timelineItems)
        }
    }
    
    // MARK: - Private
    
    /// AGENT-PLATFORM (Brief 0083, question 359): when a visit starts again, and when it ends without leaving the chat
    /// (the operator, 2026-11-12, «Так, як вихід»).
    private func setupAppStateSubscriptions() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.cameBackAt = .now
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.endVisit()
            }
            .store(in: &cancellables)
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 364): both receipts name the newest row you've seen, so "New" is where you stopped
    /// next time and the room list counts what you left. Each is sent by event, never as "the latest", which could pass rows
    /// that were never loaded. Having seen nothing new sends nothing. The room's own read state is the live timeline's, so
    /// this doesn't apply to any other kind.
    private func markSeenRowsAsRead() {
        guard state.timelineKind == .live, let seenRow = seenRows.newestSeenRow else { return }
        
        let isLive = state.timelineState.isLive
        let fullyReadEventID = isFullyReadHeld ? nil : fullyReadTarget
        if let fullyReadEventID {
            fullyReadRequestEventID = fullyReadEventID
        }
        Task { [roomProxy, timelineController] in
            if isLive {
                await timelineController.sendReadReceipt(for: seenRow)
            }
            // This is the one request that ends a visit, so a failed one is tried once more.
            if let fullyReadEventID, case .failure = await roomProxy.timeline.sendReadReceipt(for: fullyReadEventID, type: .fullyRead) {
                _ = await roomProxy.timeline.sendReadReceipt(for: fullyReadEventID, type: .fullyRead)
            }
        }
    }
    
    private func handleTappedOnSenderDetails(sender: TimelineItemSender) {
        let memberDetails: ManageRoomMemberDetails = if let memberProxy = roomProxy.membersPublisher.value.first(where: { $0.userID == sender.id }) {
            .memberDetails(roomMember: .init(withProxy: memberProxy))
        } else {
            .loadingMemberDetails(sender: sender)
        }
        
        let viewModel = ManageRoomMemberSheetViewModel(memberDetails: memberDetails,
                                                       permissions: .init(canKick: state.canCurrentUserKick,
                                                                          canBan: state.canCurrentUserBan,
                                                                          ownPowerLevel: currentUserProxy?.powerLevel ?? .init(value: 0)),
                                                       roomProxy: roomProxy,
                                                       userIndicatorController: userIndicatorController,
                                                       analyticsService: analyticsService,
                                                       mediaProvider: userSession.mediaProvider)
        
        viewModel.actions.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .dismiss(let shouldShowDetails):
                state.bindings.manageMemberViewModel = nil
                if shouldShowDetails {
                    actionsSubject.send(.displaySenderDetails(userID: sender.id))
                }
            }
        }
        .store(in: &cancellables)
        state.bindings.manageMemberViewModel = viewModel
    }
    
    private func focusLive() {
        timelineController.focusLive()
    }
    
    // AGENT-PLATFORM (Brief 0083, question 359): a loaded message never leaves the live timeline, so the highlight
    // would stay until the chat is left. A newer focus still on its way keeps its highlight.
    private func didScrollAwayFromFocussedItem() {
        guard state.timelineState.focussedEvent?.appearance == .hasAppeared else { return }
        state.timelineState.focussedEvent = nil
    }
    
    private func didScrollToFocussedItem() {
        if var focussedEvent = state.timelineState.focussedEvent {
            focussedEvent.appearance = .hasAppeared
            state.timelineState.focussedEvent = focussedEvent
            hideFocusLoadingIndicator()
            analyticsService.signpost.finishTransaction(.notificationToMessage)
        }
    }
    
    private func editLastMessage() {
        guard let item = timelineController.timelineItems.reversed().first(where: {
            guard let item = $0 as? EventBasedMessageTimelineItemProtocol else {
                return false
            }
            
            return item.sender.id == roomProxy.ownUserID && item.isEditable
        }) else {
            return
        }
        
        timelineInteractionHandler.handleTimelineItemMenuAction(.edit, itemID: item.id)
    }
    
    private func attach(_ attachment: ComposerAttachmentType) {
        switch attachment {
        case .camera:
            guard appMediator.isCameraAvailable else {
                MXLog.info("Camera unavailable, not presenting the picker.")
                displayErrorToast(L10n.errorCameraUnavailable)
                return
            }
            actionsSubject.send(.displayCameraPicker)
        case .photoLibrary:
            actionsSubject.send(.displayMediaPicker)
        case .file:
            actionsSubject.send(.displayDocumentPicker)
        case .location:
            actionsSubject.send(.displayLocationPicker)
        case .poll:
            actionsSubject.send(.displayNewPollForm)
        }
    }
    
    private func handlePollAction(_ action: TimelineViewPollAction) {
        switch action {
        case let .sendResponse(pollStartID, answerIDs):
            timelineInteractionHandler.sendPollResponse(pollStartID: pollStartID, answerIDs: answerIDs)
        case let .end(pollStartID):
            displayAlert(.pollEndConfirmation(pollStartID))
        case .edit(let eventID, let poll):
            actionsSubject.send(.displayEditPollForm(eventID: eventID, poll: poll))
        }
    }
    
    private func handleAudioPlayerAction(_ action: TimelineAudioPlayerAction) {
        switch action {
        case .playPause(let itemID):
            Task { await timelineInteractionHandler.playPauseAudio(for: itemID) }
        case .seek(let itemID, let progress):
            Task { await timelineInteractionHandler.seekAudio(for: itemID, progress: progress) }
        case .changePlaybackSpeed(let itemID):
            timelineInteractionHandler.changePlaybackSpeed(for: itemID)
        }
    }
    
    private func processVoiceMessageAction(_ action: ComposerToolbarVoiceMessageAction) {
        switch action {
        case .startRecording:
            Task {
                await mediaPlayerProvider.detachAllStates(except: nil)
                await timelineInteractionHandler.startRecordingVoiceMessage()
            }
        case .stopRecording:
            Task { await timelineInteractionHandler.stopRecordingVoiceMessage() }
        case .cancelRecording:
            Task { await timelineInteractionHandler.cancelRecordingVoiceMessage() }
        case .deleteRecording:
            Task { await timelineInteractionHandler.deleteCurrentVoiceMessage() }
        case .send:
            Task { await timelineInteractionHandler.sendCurrentVoiceMessage() }
        case .startPlayback:
            Task { await timelineInteractionHandler.startPlayingRecordedVoiceMessage() }
        case .pausePlayback:
            timelineInteractionHandler.pausePlayingRecordedVoiceMessage()
        case .seekPlayback(let progress):
            Task { await timelineInteractionHandler.seekRecordedVoiceMessage(to: progress) }
        case .scrubPlayback(let scrubbing):
            Task { await timelineInteractionHandler.scrubVoiceMessagePlayback(scrubbing: scrubbing) }
        }
    }
    
    private func updateMembers(_ members: [RoomMemberProxyProtocol]) {
        let memberStates = members.reduce(into: [String: RoomMemberState]()) { dictionary, member in
            dictionary[member.userID] = RoomMemberState(displayName: member.displayName,
                                                        avatarURL: member.avatarURL,
                                                        status: member.status)
            if member.userID == roomProxy.ownUserID {
                currentUserProxy = member
            }
        }
        // AGENT-PLATFORM (Brief 0083, question 359): the quotes redraw with their mentions when this moves.
        if state.members != memberStates {
            state.members = memberStates
        }
    }
    
    private func updateRoomInfo(_ roomInfo: RoomInfoProxyProtocol) {
        updateState(\.pinnedEventIDs, to: roomInfo.pinnedEventIDs)
        updateState(\.isDM, to: roomInfo.isDM)
        if state.timelineState.fullyReadEventID != roomInfo.fullyReadEventID {
            state.timelineState.fullyReadEventID = roomInfo.fullyReadEventID
            fullyReadDate = nil
            hasFullyReadLookupFailed = false
            updateFullyReadLocation()
        }
        updateReadOwnItems(dmUserID: roomInfo.dmUserID)
        
        if let powerLevels = roomInfo.powerLevels {
            updateState(\.canCurrentUserSendMessage, to: powerLevels.canOwnUser(sendMessage: .roomMessage))
            updateState(\.canCurrentUserRedactOthers, to: powerLevels.canOwnUserRedactOther())
            updateState(\.canCurrentUserRedactSelf, to: powerLevels.canOwnUserRedactOwn())
            updateState(\.canCurrentUserPin, to: powerLevels.canOwnUserPinOrUnpin())
            updateState(\.canCurrentUserKick, to: powerLevels.canOwnUserKick())
            updateState(\.canCurrentUserBan, to: powerLevels.canOwnUserBan())
        }
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 359): any write to the state redraws the room around the timeline, equal or not.
    private func updateState<Value: Equatable>(_ keyPath: WritableKeyPath<TimelineViewState, Value>, to value: Value) {
        if state[keyPath: keyPath] != value {
            state[keyPath: keyPath] = value
        }
    }
    
    private func setupSubscriptions() {
        timelineController.callbacks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] callback in
                guard let self else { return }
                
                switch callback {
                case .updatedTimelineItems(let updatedItems, let isSwitchingTimelines):
                    buildTimelineViews(timelineItems: updatedItems, isSwitchingTimelines: isSwitchingTimelines)
                    reconcileSelection(with: updatedItems, isSwitchingTimelines: isSwitchingTimelines)
                    
                    if !updatedItems.isEmpty {
                        analyticsService.signpost.finishTransaction(.openRoom)
                    }
                case .paginationState(let paginationState):
                    if state.timelineState.paginationState != paginationState {
                        state.timelineState.paginationState = paginationState
                        if paginationState.backward == .endReached {
                            hasReachedTimelineStart()
                        }
                    }
                case .isLive(let isLive):
                    if state.timelineState.isLive != isLive {
                        state.timelineState.isLive = isLive
                        // AGENT-PLATFORM (Brief 0083, question 359): a detached timeline has no dot, and coming back lands at the end.
                        state.bindings.hasNewMessagesAtBottom = false
                        
                        // Remove the event highlight *only* when transitioning from non-live to live.
                        if isLive, state.timelineState.focussedEvent != nil {
                            state.timelineState.focussedEvent = nil
                        }
                    }
                case .messageSentOrEdited:
                    actionsSubject.send(.composer(action: .clear))
                }
            }
            .store(in: &cancellables)
        
        setupAppStateSubscriptions() // AGENT-PLATFORM (Brief 0083, question 359)
        
        roomProxy.infoPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] roomInfo in
                self?.updateRoomInfo(roomInfo)
            }
            .store(in: &cancellables)
        
        setupUserSettingsSubscriptions()
        
        roomProxy.membersPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateMembers($0) }
            .store(in: &cancellables)
        
        roomProxy.typingMembersPublisher
            .receive(on: DispatchQueue.main)
            .filter { [weak self] _ in self?.userSettings.account.sharePresence ?? false }
            .sink { [weak self] in self?.updateState(\.typingMembers, to: $0) } // AGENT-PLATFORM (Brief 0083, question 359)
            .store(in: &cancellables)
        
        timelineInteractionHandler.actions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .composer(let action):
                    actionsSubject.send(.composer(action: action))
                case .displayAudioRecorderPermissionError:
                    displayAlert(.audioRecodingPermissionError)
                case .displayErrorToast(let title):
                    displayErrorToast(title)
                case .displayEmojiPicker(let selectedEmojis, let continuation):
                    actionsSubject.send(.displayEmojiPicker(selectedEmojis: selectedEmojis, continuation: continuation))
                case .displayMessageForwarding(let itemID):
                    Task { await self.forwardMessage(itemID: itemID) }
                case .displayEditPollForm(let eventID, let poll):
                    actionsSubject.send(.displayEditPollForm(eventID: eventID, poll: poll))
                case .displayReportContent(let itemID, let senderID):
                    actionsSubject.send(.displayReportContent(itemID: itemID, senderID: senderID))
                case .displayMediaUploadPreviewScreen(let mediaURLs):
                    actionsSubject.send(.displayMediaUploadPreviewScreen(mediaURLs: mediaURLs))
                case .showActionMenu(let actionMenuInfo):
                    if case .media(.mediaFilesScreen) = timelineController.timelineKind,
                       let item = actionMenuInfo.item as? EventBasedMessageTimelineItemProtocol {
                        actionsSubject.send(.displayMediaDetails(item: item))
                    } else {
                        self.state.bindings.actionMenuInfo = actionMenuInfo
                    }
                case .showRedactConfirmation(let itemID):
                    state.bindings.redactConfirmationInfo = .init(id: itemID)
                case .showDebugInfo(let debugInfo):
                    state.bindings.debugInfo = debugInfo
                case .showReadReceipts(let itemID):
                    displayReadReceipts(for: itemID)
                case .showDraftCode(let code):
                    state.bindings.draftCode = code
                case .editInteractivePost(let eventID, let post, let title):
                    actionsSubject.send(.editInteractivePost(eventID: eventID, post: post, title: title))
                case .viewInRoomTimeline(let eventID):
                    Task { await self.viewInRoomTimeline(eventID: eventID) }
                case .displayThread(let itemID):
                    actionsSubject.send(.displayThread(itemID: itemID))
                case .showTranslation(let text):
                    self.state.bindings.textToBeTranslated = text
                    self.state.bindings.showTranslation = true
                }
            }
            .store(in: &cancellables)
    }
    
    func viewInRoomTimeline(eventID: String) async {
        switch await roomProxy.loadOrFetchEventDetails(for: eventID) {
        case .success(let event):
            let threadRootEventID: String? = if userSettings.app.threadsEnabled {
                event.threadRootEventId()
            } else {
                nil
            }
            actionsSubject.send(.viewInRoomTimeline(eventID: eventID, threadRootEventID: threadRootEventID))
        case .failure:
            userIndicatorController.submitIndicator(.init(title: L10n.errorUnknown))
        }
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 359): a change to the state reaches the rows it's for, in the same update.
    private func setupRowContextSubscription() {
        context.$viewState
            .map(TimelineRowContextInputs.init)
            .removeDuplicates()
            .sink { [weak self] inputs in
                self?.updateRowContexts(inputs)
            }
            .store(in: &cancellables)
    }
    
    private func setupUserSettingsSubscriptions() {
        userSettings.account.sharePresencePublisher
            .weakAssign(to: \.state.showReadReceipts, on: self)
            .store(in: &cancellables)
        
        userSettings.app.viewSourceEnabledPublisher
            .weakAssign(to: \.state.isViewSourceEnabled, on: self)
            .store(in: &cancellables)
        
        userSettings.app.threadsEnabledPublisher
            .weakAssign(to: \.state.areThreadsEnabled, on: self)
            .store(in: &cancellables)
        
        userSettings.app.jumpToReadMarkerEnabledPublisher
            .weakAssign(to: \.state.jumpToReadMarkerEnabled, on: self)
            .store(in: &cancellables)
        
        userSession.clientProxy.timelineMediaVisibilityPublisher
            .removeDuplicates()
            .flatMap { [weak self] timelineMediaVisibility -> AnyPublisher<Bool, Never> in
                switch timelineMediaVisibility {
                case .always:
                    return Just(false).eraseToAnyPublisher()
                case .never:
                    return Just(true).eraseToAnyPublisher()
                case .privateOnly:
                    guard let self else { return Just(false).eraseToAnyPublisher() }
                    return roomProxy.infoPublisher
                        .map { !($0.isPrivate ?? false) }
                        .removeDuplicates()
                        .eraseToAnyPublisher()
                }
            }
            .receive(on: DispatchQueue.main)
            .weakAssign(to: \.state.hideTimelineMedia, on: self)
            .store(in: &cancellables)
    }
    
    private func setupDirectRoomSubscriptionsIfNeeded() {
        guard roomProxy.infoPublisher.value.isDirect else {
            return
        }
        
        let shouldShowInviteAlert = composerFocusedSubject
            .removeDuplicates()
            .map { [weak self] isFocused in
                guard let self else { return false }
                
                return isFocused && self.roomProxy.infoPublisher.value.isUserAloneInDirectRoom
            }
            // We want to show the alert just once, so we are taking the first "true" emitted
            .first { $0 }
        
        shouldShowInviteAlert
            .sink { [weak self] _ in
                self?.displayAlert(.inviteAgain)
            }
            .store(in: &cancellables)
    }
    
    private func paginateBackwards() {
        guard paginateBackwardsTask == nil else {
            return
        }
        
        paginateBackwardsTask = Task { [weak self] in
            guard let self else {
                return
            }
            
            let isOpening = state.timelineState.opening == .loadingRows
            let result = await timelineController.paginateBackwards(requestSize: isOpening ? Constants.openingPaginationEventLimit : Constants.paginationEventLimit)
            // AGENT-PLATFORM (Brief 0083, question 363): the app went looking on its own, so nothing you asked for failed.
            if case .failure = result, !isOpening {
                displayErrorToast(L10n.errorFailedLoadingMessages)
            }
            paginateBackwardsTask = nil
            continueLoadingRows(after: result)
        }
    }
    
    private func paginateForwards() {
        guard paginateForwardsTask == nil else {
            return
        }
        
        paginateForwardsTask = Task { [weak self] in
            guard let self else {
                return
            }
            
            switch await timelineController.paginateForwards(requestSize: Constants.paginationEventLimit) {
            case .failure:
                displayErrorToast(L10n.errorFailedLoadingMessages)
            default:
                break
            }
            
            if state.timelineState.paginationState.forward == .endReached {
                focusLive()
            }
            
            paginateForwardsTask = nil
        }
    }
    
    private func scrollToBottom() {
        if state.timelineState.isLive {
            state.timelineState.scrollToBottomPublisher.send(())
        } else {
            focusLive()
        }
    }
    
    private func scrollToReadMarker() async {
        // Primary: SDK has materialised the virtual ReadMarker. Smooth in-window scroll.
        if let readMarkerID = state.timelineState.readMarkerUniqueID {
            state.timelineState.scrollToReadMarkerPublisher.send(readMarkerID)
            return
        }
        
        // Fallback: mirror the same-room permalink flow exactly
        // (RoomFlowCoordinator.handleChildEventRoute lines 223-258): pre-fetch the
        // event first to prime the SDK's event cache, then focus on it via the
        // same focusOnEvent path permalinks use.
        guard let fullyReadEventID = state.timelineState.fullyReadEventID else { return }
        
        switch await roomProxy.loadOrFetchEventDetails(for: fullyReadEventID) {
        case .success:
            await focusOnEvent(eventID: fullyReadEventID)
        case .failure:
            displayErrorToast(L10n.errorMessageNotFound)
        }
    }
    
    func sendReadReceiptIfNeeded(for lastVisibleItemID: TimelineItemIdentifier) async {
        guard appMediator.appState == .active, state.timelineState.opening == .settled else { return }
        
        // AGENT-PLATFORM (Brief 0083, question 364): the read receipt follows what you've seen, as `m.fully_read` does.
        if tracksSeenRows {
            if hasGivenUpLoadingRows, seenRows.isNewestRow(lastVisibleItemID) {
                allowPassingUnloadedRows()
            }
            guard !isUnreadAboveLoadedRows, !isFocusAheadOfUnread else { return }
            seenRows.noteOnScreen(lastVisibleItemID)
        }
        
        await timelineController.sendReadReceipt(for: lastVisibleItemID)
        await moveFullyReadIfNeeded()
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 359): at the end with nothing marked "New", the SDK's marker comes along, so
    /// that a row arriving later finds it in the right place. Not with "New" showing, as this would take it away. By event
    /// rather than `markAsRead`, which could land on a reaction, an event with no item for the SDK to place its marker after.
    /// Never a public receipt, whatever the read receipt setting: `m.fully_read` is the account's own, as on leaving the chat.
    /// This runs after the receipt's round trip, so it asks again whether the app is still active.
    private func moveFullyReadIfNeeded() async {
        guard appMediator.appState == .active,
              state.timelineKind == .live,
              state.isAtBottomAndLive,
              !isNewShowing,
              !isFullyReadHeld,
              let eventID = fullyReadTarget,
              eventID != fullyReadRequestEventID else {
            return
        }
        
        fullyReadRequestEventID = eventID
        _ = await roomProxy.timeline.sendReadReceipt(for: eventID, type: .fullyRead)
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 359): with `m.fully_read` on an event above the loaded rows, moving it to the
    /// newest row would pass all that lies between, on every device, unread. So it waits until they're loaded, you write, or
    /// the app gives up on them. This goes by the rows and not by the unread count, which is stale on a cold start and leaves
    /// out Spiral's own rows.
    private var isFullyReadHeld: Bool {
        guard let eventID = state.timelineState.fullyReadEventID, !state.timelineState.isFullyReadWithoutRow else { return false }
        return !mayPassUnloadedRows && seenRows.hasRows && !seenRows.hasRow(eventID: eventID)
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 359): "New" above the loaded rows counts, as it's still there to scroll up to.
    private var isNewShowing: Bool {
        state.timelineState.readMarkerUniqueID != nil || isUnreadAboveLoadedRows
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 363): rows that were never on screen lie above the loaded ones. Neither receipt
    /// may pass them, so the room stays unread until they're loaded, you write, or the app gives up on them.
    private var isUnreadAboveLoadedRows: Bool {
        opensWithUnread && state.timelineState.isReadMarkerAboveLoadedRows
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 364): a push or a link landed below "New", and what lies between wasn't read.
    private var isFocusAheadOfUnread: Bool {
        state.timelineState.focussedEvent != nil && state.timelineState.readMarkerUniqueID != nil && !state.bindings.isReadMarkerVisible
    }
    
    private var fullyReadTarget: String? {
        seenRows.fullyReadTarget(from: state.timelineState.fullyReadEventID, sentAt: fullyReadDate)
    }
    
    /// Only the room's live timeline has seen rows: threads, pinned and detached timelines stay as they were.
    private var tracksSeenRows: Bool {
        state.timelineKind == .live && state.timelineState.isLive
    }
    
    private func handleMediaTapped(with itemID: TimelineItemIdentifier, galleryIndex: Int? = nil) async {
        // Building the media timeline takes ~100ms from the event cache, however its possible that
        // a focussed timeline may hit /context so we need to show a spinner when it's actually slow.
        let spinner = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            state.showLoading = true
        }
        let action = await timelineInteractionHandler.processItemTap(itemID)
        spinner.cancel()
        
        switch action {
        case .displayMediaPreview(let item, let timelineViewModelKind):
            actionsSubject.send(.composer(action: .removeFocus)) // Hide the keyboard otherwise a big white space is sometimes shown when dismissing the preview.
            
            let mediaPreviewViewModel = makeMediaPreviewViewModel(item: item, timelineViewModelKind: timelineViewModelKind)
            actionsSubject.send(.displayMediaPreview(mediaPreviewViewModel))
        case .displayGalleryPreview(let galleryItem, let timelineViewModelKind):
            actionsSubject.send(.composer(action: .removeFocus))
            
            let mediaPreviewViewModel = makeGalleryPreviewViewModel(galleryItem: galleryItem,
                                                                    timelineViewModelKind: timelineViewModelKind,
                                                                    initialIndex: galleryIndex ?? 0)
            actionsSubject.send(.displayMediaPreview(mediaPreviewViewModel))
        case .displayLocation(let location):
            actionsSubject.send(.displayLocation(location))
        case .displayLiveLocation(let sender, let initialLiveLocationShare):
            actionsSubject.send(.displayLiveLocation(sender: sender, initialLiveLocationShare: initialLiveLocationShare))
        case .none:
            break
        }
        state.showLoading = false
    }
    
    private func handleItemSendInfoTapped(itemID: TimelineItemIdentifier) {
        guard let timelineItem = timelineController.timelineItems.firstUsingStableID(itemID) else {
            MXLog.warning("Couldn't find timeline item.")
            return
        }
        
        guard let eventTimelineItem = timelineItem as? EventBasedTimelineItemProtocol else {
            fatalError("Only events can have send info.")
        }
        
        if case let .sendingFailed(.unknown(reason)) = eventTimelineItem.properties.deliveryStatus {
            // A missing target only costs the retry/remove actions, the reason is still worth showing.
            displayAlert(.sendingFailed(reason: reason, itemID: itemID, target: timelineController.pendingSendTarget(for: itemID)))
        } else if case let .sendingFailed(.verifiedUser(failure)) = eventTimelineItem.properties.deliveryStatus {
            guard let sendHandle = timelineController.sendHandle(for: itemID) else {
                MXLog.error("Cannot find send handle for \(itemID).")
                return
            }
            
            actionsSubject.send(.displayResolveSendFailure(failure: failure,
                                                           resolver: .sendQueue(sendHandle: sendHandle, roomProxy: roomProxy))) // AGENT-PLATFORM: § 5.87
            
        } else if let forwarderMessage = eventTimelineItem.properties.encryptionForwarder?.message {
            displayAlert(.encryptionForwarder(forwarderMessage))
        } else if let authenticityMessage = eventTimelineItem.properties.encryptionAuthenticity?.message {
            displayAlert(.encryptionAuthenticity(authenticityMessage))
        }
    }
    
    private func retrySending(_ itemID: TimelineItemIdentifier, target: SendTarget) {
        Task { await timelineController.retrySend(itemID, target: target) }
    }
    
    private func abortSending(_ itemID: TimelineItemIdentifier, target: SendTarget) {
        Task { await timelineController.abortSend(itemID, target: target) }
    }
    
    private func slashCommand(message: String) -> SlashCommand? {
        for command in SlashCommand.allCases where message.starts(with: command.rawValue) {
            return command
        }
        return nil
    }
    
    private func handleJoinCommand(message: String) async {
        guard let alias = String(message.dropFirst(SlashCommand.join.rawValue.count))
            .components(separatedBy: .whitespacesAndNewlines)
            .first,
            case let .success(resolvedAlias) = await userSession.clientProxy.resolveRoomAlias(alias) else {
            return
        }
        
        actionsSubject.send(.displayRoom(roomID: resolvedAlias.roomId, via: resolvedAlias.servers))
    }
    
    private func sendCurrentMessage(_ message: String, html: String?, mode: ComposerMode, intentionalMentions: IntentionalMentions) async {
        guard !message.isEmpty else {
            fatalError("This message should never be empty")
        }
        
        switch mode {
        case .reply(let eventID, _, _):
            await timelineController.sendMessage(message,
                                                 html: html,
                                                 inReplyToEventID: eventID,
                                                 intentionalMentions: intentionalMentions)
        case .edit(let originalEventOrTransactionID, .default):
            await timelineController.edit(originalEventOrTransactionID,
                                          message: message,
                                          html: html,
                                          intentionalMentions: intentionalMentions)
        case .edit(let originalEventOrTransactionID, .addCaption),
             .edit(let originalEventOrTransactionID, .editCaption):
            await timelineController.editCaption(originalEventOrTransactionID,
                                                 message: message,
                                                 html: html,
                                                 intentionalMentions: intentionalMentions)
        case .default:
            switch slashCommand(message: message) {
            case .join:
                await handleJoinCommand(message: message)
            case .none:
                await timelineController.sendMessage(message,
                                                     html: html,
                                                     inReplyToEventID: nil,
                                                     intentionalMentions: intentionalMentions)
            }
        case .recordVoiceMessage, .previewVoiceMessage:
            MXLog.error("Ignoring sendCurrentMessage with invalid composer mode: \(mode)")
            return
        }
        
        scrollToBottom()
    }
    
    private func trackComposerMode(_ mode: ComposerMode) {
        var isEdit = false
        var isReply = false
        switch mode {
        case .edit:
            isEdit = true
        case .reply:
            isReply = true
        default:
            break
        }
        
        analyticsService.trackComposer(inThread: false, isEditing: isEdit, isReply: isReply, startsThread: nil)
    }
    
    private func makeMediaPreviewViewModel(item: EventBasedMessageTimelineItemProtocol,
                                           timelineViewModelKind: TimelineControllerAction.TimelineViewModelKind) -> TimelineMediaPreviewViewModel {
        TimelineMediaPreviewViewModel(initialItem: item,
                                      timelineViewModel: timelineViewModel(for: timelineViewModelKind),
                                      mediaProvider: userSession.mediaProvider,
                                      photoLibraryManager: PhotoLibraryManager(),
                                      userIndicatorController: userIndicatorController,
                                      appMediator: appMediator,
                                      replyHandler: mediaPreviewReplyHandler)
    }
    
    private func makeGalleryPreviewViewModel(galleryItem: GalleryRoomTimelineItem,
                                             timelineViewModelKind: TimelineControllerAction.TimelineViewModelKind,
                                             initialIndex: Int) -> TimelineMediaPreviewViewModel {
        TimelineMediaPreviewViewModel(galleryItem: galleryItem,
                                      initialIndex: initialIndex,
                                      timelineViewModel: timelineViewModel(for: timelineViewModelKind),
                                      mediaProvider: userSession.mediaProvider,
                                      photoLibraryManager: PhotoLibraryManager(),
                                      userIndicatorController: userIndicatorController,
                                      appMediator: appMediator,
                                      replyHandler: mediaPreviewReplyHandler)
    }
    
    // AGENT-PLATFORM (Brief 0083, question 413): the viewer's Reply puts this timeline's composer into reply mode.
    /// Only timelines shown above a composer can reply; the pinned and media-files screens have none.
    private var mediaPreviewReplyHandler: ((EventBasedMessageTimelineItemProtocol) -> Void)? {
        switch state.timelineKind {
        case .live, .detached, .thread:
            { [weak self] item in self?.timelineInteractionHandler.reply(to: item) }
        case .pinned, .media:
            nil
        }
    }
    
    private func timelineViewModel(for kind: TimelineControllerAction.TimelineViewModelKind) -> TimelineViewModel {
        switch kind {
        case .active: self
        case .new(let newViewModel): newViewModel
        }
    }
    
    // MARK: - Timeline Item Building
    
    private func buildTimelineViews(timelineItems: [RoomTimelineItemProtocol], isSwitchingTimelines: Bool = false) {
        let signpost = TimelineSignposts.beginInterval("Build views", count: timelineItems.count) // AGENT-PLATFORM (Brief 0083, question 359)
        defer { TimelineSignposts.endInterval("Build views", signpost) }
        
        let timelineItems = applySeenRows(to: timelineItems, isSwitchingTimelines: isSwitchingTimelines)
        var timelineItemsDictionary = OrderedDictionary<TimelineItemIdentifier.UniqueID, RoomTimelineItemViewState>()
        
        updateSpiralLivePost(timelineItems) // AGENT-PLATFORM (§ 5.55)
        updateReadProgress() // AGENT-PLATFORM (Brief 0083, question 359): before the rows, which take their ticks from it.
        
        // AGENT-PLATFORM (Brief 0083, question 359): read once, as `state` is a copy of the whole view state.
        let currentRows = state.timelineState.itemsDictionary
        let rowContextInputs = TimelineRowContextInputs(state)
        let isPinnedTimeline = state.timelineKind == .pinned
        var hasChangedRows = false
        
        if !isSwitchingTimelines, let newestRow = currentRows.keys.last, timelineItems.last?.id.uniqueID != newestRow {
            state.rowMotion.noteArrival() // Before the rows, which regroup as the new one slides in.
        }
        
        func updateViewState(item: RoomTimelineItemProtocol, groupStyle: TimelineGroupStyle) -> RoomTimelineItemViewState {
            let rowContext = rowContextInputs.rowContext(for: item.id)
            guard let viewState = currentRows[item.id.uniqueID] else {
                return RoomTimelineItemViewState(item: item, groupStyle: groupStyle, rowContext: rowContext)
            }
            if viewState.update(item: item, groupStyle: groupStyle) {
                hasChangedRows = true
            }
            viewState.update(rowContext: rowContext)
            return viewState
        }
        
        timelineItems.filter { $0 is RedactedRoomTimelineItem }.forEach { timelineItem in
            // Stops the audio player when a voice message is redacted.
            guard let playerState = mediaPlayerProvider.playerState(for: .timelineItemIdentifier(timelineItem.id)) else {
                return
            }
            
            Task { @MainActor in
                playerState.detachAudioPlayer()
                mediaPlayerProvider.unregister(audioPlayerState: playerState)
            }
        }
        
        let itemsGroupedByTimelineDisplayStyle = timelineItems.chunked { current, next in
            canGroupItem(timelineItem: current, with: next)
        }
        
        for itemGroup in itemsGroupedByTimelineDisplayStyle {
            guard !itemGroup.isEmpty else {
                MXLog.error("Found empty item group")
                continue
            }
            
            if itemGroup.count == 1 {
                if let firstItem = itemGroup.first {
                    timelineItemsDictionary.updateValue(updateViewState(item: firstItem, groupStyle: .single),
                                                        forKey: firstItem.id.uniqueID)
                }
            } else {
                for (index, item) in itemGroup.enumerated() {
                    if index == 0 {
                        timelineItemsDictionary.updateValue(updateViewState(item: item, groupStyle: isPinnedTimeline ? .single : .first),
                                                            forKey: item.id.uniqueID)
                    } else if index == itemGroup.count - 1 {
                        timelineItemsDictionary.updateValue(updateViewState(item: item, groupStyle: isPinnedTimeline ? .single : .last),
                                                            forKey: item.id.uniqueID)
                    } else {
                        timelineItemsDictionary.updateValue(updateViewState(item: item, groupStyle: isPinnedTimeline ? .single : .middle),
                                                            forKey: item.id.uniqueID)
                    }
                }
            }
        }
        
        if isSwitchingTimelines {
            state.timelineState.isSwitchingTimelines = true
        }
        
        // AGENT-PLATFORM (Brief 0083, question 359): most builds change a row or two, and many change nothing, as a build runs
        // for everything the SDK reports. Whatever's written here redraws the room around the timeline.
        if hasChangedRows || timelineItemsDictionary.keys != currentRows.keys {
            var timelineState = state.timelineState
            timelineState.itemsDictionary = timelineItemsDictionary
            timelineState.recomputeReadMarkerUniqueID()
            state.timelineState = timelineState
        }
        updateOpening()
    }
    
    // AGENT-PLATFORM (Brief 0083, question 359): the room's read progress changes far less often than the timeline does.
    private func updateReadProgress() {
        let readProgress = timelineController.readProgress
        if state.timelineState.readProgress != readProgress {
            state.timelineState.readProgress = readProgress
        }
        updateReadOwnItems(dmUserID: roomProxy.infoPublisher.value.dmUserID)
    }
    
    // AGENT-PLATFORM (Brief 0083, question 357): once per update, so a row only looks itself up.
    private func updateReadOwnItems(dmUserID: String?) {
        let ownUserID = roomProxy.ownUserID
        let readOwnItemIDs = state.timelineState.readProgress.readOwnMessages { userID in
            TimelineReadProgress.isCounted(userID, ownUserID: ownUserID, dmUserID: dmUserID)
        }
        if state.timelineState.readOwnItemIDs != readOwnItemIDs {
            state.timelineState.readOwnItemIDs = readOwnItemIDs
        }
    }
    
    private func updateRowContexts(_ inputs: TimelineRowContextInputs) {
        for viewState in state.timelineState.itemViewStates {
            viewState.update(rowContext: inputs.rowContext(for: viewState.identifier))
        }
    }
    
    private func canGroupItem(timelineItem: RoomTimelineItemProtocol, with otherTimelineItem: RoomTimelineItemProtocol) -> Bool {
        if timelineItem is CollapsibleTimelineItem || otherTimelineItem is CollapsibleTimelineItem {
            return false
        }
        
        guard let eventTimelineItem = timelineItem as? EventBasedTimelineItemProtocol,
              let otherEventTimelineItem = otherTimelineItem as? EventBasedTimelineItemProtocol else {
            return false
        }
        
        // State events aren't rendered as messages so shouldn't be grouped.
        if eventTimelineItem is StateRoomTimelineItem || otherEventTimelineItem is StateRoomTimelineItem {
            return false
        }
        
        return eventTimelineItem.sender == otherEventTimelineItem.sender
            && eventTimelineItem.properties.reactions.isEmpty // Reactions break the grouping.
            && otherEventTimelineItem.timestamp.timeIntervalSince(eventTimelineItem.timestamp) < 5 * 60 // As does the passage of time.
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 359): the room's live timeline only. Threads, pinned and detached timelines stay as they were.
    private func applySeenRows(to timelineItems: [RoomTimelineItemProtocol], isSwitchingTimelines: Bool) -> [RoomTimelineItemProtocol] {
        guard tracksSeenRows else { return timelineItems }
        
        let moment = TimelineSeenRows.Moment(isAtEnd: state.bindings.isScrolledToBottom,
                                             isWatching: state.bindings.isScrolledToBottom && appMediator.appState == .active,
                                             cameBackAt: cameBackAt,
                                             isNewShowing: isNewShowing)
        let arrivals = seenRows.noteArrivals(in: timelineItems,
                                             isSwitchingTimelines: isSwitchingTimelines || state.timelineState.isSwitchingTimelines,
                                             moment: moment)
        
        if arrivals.hasOwnRow {
            allowPassingUnloadedRows()
        }
        if arrivals.isTimelineReplaced {
            mayPassUnloadedRows = false
            opensWithUnread = true
            hasGivenUpLoadingRows = false
        }
        if arrivals.hasRowFromOthers, !state.bindings.isScrolledToBottom {
            state.bindings.hasNewMessagesAtBottom = true
        }
        
        updateFullyReadLocation()
        let items = seenRows.placingReadMarker(in: timelineItems, afterRowLessEventSentAt: state.timelineState.isFullyReadWithoutRow ? fullyReadDate : nil)
        
        // AGENT-PLATFORM (Brief 0083, question 363): you came back to the chat as you left it, at the end. The table would run
        // past what arrived meanwhile, so that opens as a chat with unread does. A "New" from before stays where it is.
        if let firstRowMissed = arrivals.firstRowMissedAtEnd, !arrivals.hasOwnRow, state.timelineState.opening == .settled {
            let readMarkerID = items.first { $0 is ReadMarkerRoomTimelineItem }?.id.uniqueID
            state.timelineState.opening = .atRow(moment.isNewShowing ? firstRowMissed : readMarkerID ?? firstRowMissed)
        }
        
        return items
    }
    
    private func allowPassingUnloadedRows() {
        opensWithUnread = false
        mayPassUnloadedRows = true
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 364): a `m.fully_read` that isn't loaded is either above the rows, or on an event
    /// that has none. Only when it was sent can tell them apart, and until then it's above, the side that passes nothing.
    /// At the timeline's start nothing's left above to pass, so a failed lookup counts there and nowhere else: the event is
    /// from before you joined, or purged, and it would hold this chat's receipts for good.
    private func updateFullyReadLocation() {
        guard tracksSeenRows, seenRows.hasRows, let eventID = state.timelineState.fullyReadEventID, !seenRows.hasRow(eventID: eventID) else {
            updateState(\.timelineState.isFullyReadWithoutRow, to: false)
            return
        }
        
        let hasReachedStart = state.timelineState.paginationState.backward == .endReached
        if let fullyReadDate {
            updateState(\.timelineState.isFullyReadWithoutRow, to: seenRows.isEventAmongRows(sentAt: fullyReadDate, hasReachedStart: hasReachedStart))
            return
        }
        
        updateState(\.timelineState.isFullyReadWithoutRow, to: hasReachedStart && hasFullyReadLookupFailed)
        if eventID != fullyReadLookupEventID {
            fullyReadLookupEventID = eventID
            Task { await lookUpFullyRead(eventID: eventID) }
        }
    }
    
    private func lookUpFullyRead(eventID: String) async {
        let result = await roomProxy.loadOrFetchEventDetails(for: eventID)
        guard state.timelineState.fullyReadEventID == eventID else { return }
        
        switch result {
        case .success(let event):
            fullyReadDate = Date(timeIntervalSince1970: TimeInterval(event.timestamp()) / 1000)
        case .failure:
            hasFullyReadLookupFailed = true
        }
        buildTimelineViews(timelineItems: timelineController.timelineItems)
    }
    
    /// A lookup that's still running has this to come, in its own build, and the chat waits for it to open.
    private func hasReachedTimelineStart() {
        if tracksSeenRows, fullyReadDate != nil || hasFullyReadLookupFailed {
            buildTimelineViews(timelineItems: timelineController.timelineItems)
        }
    }
    
    // MARK: - Opening at the first unread
    
    /// AGENT-PLATFORM (Brief 0083, question 363): "New" is where the chat opens. With the unread above the loaded rows, the rows
    /// come first. This goes by the rows, and leaves the count only to say whether to go looking.
    private func updateOpening() {
        switch state.timelineState.opening {
        case .undecided where seenRows.hasRows, .loadingRows:
            if let readMarkerID = state.timelineState.readMarkerUniqueID {
                settleOpening(at: .atRow(readMarkerID))
            } else if isUnreadAboveLoadedRows {
                startLoadingRows()
            } else {
                settleOpening()
            }
        default:
            break
        }
    }
    
    private func startLoadingRows() {
        guard state.timelineState.opening != .loadingRows else { return }
        
        state.timelineState.opening = .loadingRows
        paginateBackwards()
        
        openingTimeLimitTask = Task { [weak self, openingTimeLimit] in
            try? await Task.sleep(for: Constants.openingLoadingIndicatorDelay)
            guard !Task.isCancelled else { return }
            self?.showFocusLoadingIndicator()
            
            try? await Task.sleep(for: openingTimeLimit)
            guard !Task.isCancelled else { return }
            self?.giveUpLoadingRows()
        }
    }
    
    /// One more page, while there's a reason to go on. Giving up opens the chat at the end, and the newest row there reads it.
    private func continueLoadingRows(after result: Result<Void, TimelineControllerError>) {
        guard state.timelineState.opening == .loadingRows, state.timelineState.paginationState.backward != .endReached else { return }
        
        openingPagesLeft -= 1
        if case .success = result, openingPagesLeft > 0 {
            paginateBackwards()
        } else {
            giveUpLoadingRows()
        }
    }
    
    private func didSettleOpening(isAwayFromEnd: Bool) {
        guard case .atRow = state.timelineState.opening else { return }
        
        state.timelineState.opening = .settled
        if isAwayFromEnd {
            state.bindings.hasNewMessagesAtBottom = true
        }
    }
    
    private func giveUpLoadingRows() {
        guard state.timelineState.opening == .loadingRows else { return }
        
        MXLog.info("Opening \(roomProxy.id) at the end, as the first unread wasn't reached with \(openingPagesLeft) pages left")
        hasGivenUpLoadingRows = true
        settleOpening()
    }
    
    private func settleOpening(at opening: TimelineState.Opening = .settled) {
        openingTimeLimitTask?.cancel()
        openingTimeLimitTask = nil
        hideFocusLoadingIndicator()
        state.timelineState.opening = opening
    }
    
    // MARK: - Direct chats logics
    
    private let inviteLoadingIndicatorID = UUID().uuidString
    
    private func inviteOtherDMUserBack() {
        guard roomProxy.infoPublisher.value.isUserAloneInDirectRoom else {
            displayAlert(.unknown)
            return
        }
        
        Task {
            userIndicatorController.submitIndicator(.init(id: inviteLoadingIndicatorID, type: .toast, title: L10n.commonLoading))
            defer {
                userIndicatorController.retractIndicatorWithId(inviteLoadingIndicatorID)
            }
            
            guard
                let members = await roomProxy.members(),
                members.count == 2,
                let otherPerson = members.first(where: { $0.userID != roomProxy.ownUserID && $0.membership == .leave })
            else {
                displayAlert(.unknown)
                return
            }
            
            switch await roomProxy.invite(userID: otherPerson.userID) {
            case .success:
                break
            case .failure:
                displayAlert(.unableToInvite)
            }
        }
    }
    
    // MARK: - Reactions
    
    private func displayReactionSummary(for itemID: TimelineItemIdentifier, selectedKey: String) {
        guard let timelineItem = timelineController.timelineItems.firstUsingStableID(itemID),
              let eventTimelineItem = timelineItem as? EventBasedTimelineItemProtocol else {
            return
        }
        
        state.bindings.reactionSummaryInfo = .init(reactions: eventTimelineItem.properties.reactions, selectedKey: selectedKey)
    }
    
    // MARK: - Read Receipts
    
    private func displayReadReceipts(for itemID: TimelineItemIdentifier) {
        // A rename doesn't reach `state.members` by itself, and the sheet reads names from it.
        Task { await roomProxy.updateMembers() }
        // AGENT-PLATFORM (Brief 0083, question 357): everyone who reached this message, not only whose receipt sits on it.
        state.bindings.readReceiptsSummaryInfo = .init(orderedReceipts: state.timelineState.readProgress.readers(of: itemID.uniqueID), id: itemID)
    }
    
    // MARK: Pills
    
    private func pillContextUpdater(_ pillContext: PillContext) {
        switch pillContext.data.type {
        case let .user(id):
            let isOwnMention = id == state.ownUserID
            if let profile = state.members[id] {
                pillContext.viewState = .mention(isOwnMention: isOwnMention,
                                                 displayText: PillUtilities.userPillDisplayText(username: profile.displayName, userID: id),
                                                 statusEmoji: profile.status.displayed?.emoji)
            } else {
                pillContext.viewState = .mention(isOwnMention: isOwnMention, displayText: id, statusEmoji: nil)
                pillContext.cancellable = context.$viewState
                    .compactMap { $0.members[id] }
                    .sink { [weak pillContext] profile in
                        guard let pillContext else {
                            return
                        }
                        pillContext.viewState = .mention(isOwnMention: isOwnMention,
                                                         displayText: PillUtilities.userPillDisplayText(username: profile.displayName, userID: id),
                                                         statusEmoji: profile.status.displayed?.emoji)
                        pillContext.cancellable = nil
                    }
            }
        case .allUsers:
            pillContext.viewState = .mention(isOwnMention: true, displayText: PillUtilities.atRoom, statusEmoji: nil)
        case .event(let room):
            let pillViewState: PillViewState
            switch room {
            case .roomAlias(let alias):
                let roomSummary = userSession.clientProxy.roomSummaryForAlias(alias)
                pillViewState = .reference(displayText: PillUtilities.eventPillDisplayText(roomName: roomSummary?.name, rawRoomText: alias))
            case .roomID(let id):
                let roomSummary = userSession.clientProxy.roomSummaryForIdentifier(id)
                pillViewState = .reference(displayText: PillUtilities.eventPillDisplayText(roomName: roomSummary?.name, rawRoomText: id))
            }
            pillContext.viewState = pillViewState
        case .roomAlias(let alias):
            let roomSummary = userSession.clientProxy.roomSummaryForAlias(alias)
            pillContext.viewState = .reference(displayText: PillUtilities.roomPillDisplayText(roomName: roomSummary?.name, rawRoomText: alias))
        case .roomID(let id):
            let roomSummary = userSession.clientProxy.roomSummaryForIdentifier(id)
            pillContext.viewState = .reference(displayText: PillUtilities.roomPillDisplayText(roomName: roomSummary?.name, rawRoomText: id))
        }
    }
    
    // MARK: - User Indicators
    
    private func showFocusLoadingIndicator() {
        userIndicatorController.submitIndicator(UserIndicator(id: Constants.focusTimelineToastIndicatorID,
                                                              type: .toast(progress: .indeterminate),
                                                              title: L10n.commonLoading,
                                                              persistent: true))
    }
    
    private func hideFocusLoadingIndicator() {
        userIndicatorController.retractIndicatorWithId(Constants.focusTimelineToastIndicatorID)
    }
    
    private func displayAlert(_ type: TimelineAlertInfoType) {
        switch type {
        case .audioRecodingPermissionError:
            state.bindings.alertInfo = .init(id: type,
                                             title: L10n.dialogPermissionMicrophoneTitleIos(InfoPlistReader.main.bundleDisplayName),
                                             message: L10n.dialogPermissionMicrophoneDescriptionIos,
                                             primaryButton: .init(title: L10n.commonSettings) { [weak self] in self?.appMediator.openAppSettings() },
                                             secondaryButton: .init(title: L10n.actionNotNow, role: .cancel, action: nil))
        case .pollEndConfirmation(let pollStartID):
            state.bindings.alertInfo = .init(id: type,
                                             title: L10n.actionEndPoll,
                                             message: L10n.commonPollEndConfirmation,
                                             primaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil),
                                             secondaryButton: .init(title: L10n.actionOk) { self.timelineInteractionHandler.endPoll(pollStartID: pollStartID) })
        case .sendingFailed(let reason, let itemID, let target):
            state.bindings.alertInfo = .init(id: type,
                                             title: L10n.commonSendingFailed,
                                             message: reason,
                                             primaryButton: .init(title: target == nil ? L10n.actionOk : L10n.actionCancel, role: .cancel, action: nil),
                                             verticalButtons: target.map { target in
                                                 [.init(title: L10n.actionRetry) { [weak self] in self?.retrySending(itemID, target: target) },
                                                  .init(title: target == .event ? L10n.actionRemoveMessage : L10n.actionDiscard, role: .destructive) { [weak self] in
                                                      self?.abortSending(itemID, target: target)
                                                  }]
                                             })
        case .encryptionAuthenticity(let message):
            state.bindings.alertInfo = .init(id: type,
                                             title: message,
                                             primaryButton: .init(title: L10n.actionOk, action: nil))
        case .encryptionForwarder(let message):
            state.bindings.alertInfo = .init(id: type,
                                             title: message,
                                             primaryButton: .init(title: L10n.actionOk, action: nil),
                                             secondaryButton: .init(title: L10n.actionLearnMore) { [weak self] in
                                                 guard let self else { return }
                                                 appMediator.open(userSettings.app.historySharingDetailsURL)
                                             })
        case .inviteAgain:
            state.bindings.alertInfo = .init(id: .inviteAgain,
                                             title: L10n.screenRoomInviteAgainAlertTitle,
                                             message: L10n.screenRoomInviteAgainAlertMessage,
                                             primaryButton: .init(title: L10n.actionInvite) { [weak self] in self?.inviteOtherDMUserBack() },
                                             secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
        case .unableToInvite:
            state.bindings.alertInfo = .init(id: .unableToInvite,
                                             title: L10n.commonUnableToInviteTitle,
                                             message: L10n.commonUnableToInviteMessage)
        case .unknown:
            state.bindings.alertInfo = .init(id: .unknown, title: L10n.commonError)
        }
    }
    
    private func displayErrorToast(_ title: String) {
        userIndicatorController.submitIndicator(UserIndicator(id: Constants.toastErrorID,
                                                              type: .toast,
                                                              title: title,
                                                              icon: \.close))
    }
}

// MARK: - Message forwarding

extension TimelineViewModel {
    func makeForwardingPayload(for itemIDs: [TimelineItemIdentifier]) async -> MessageForwardingPayload? {
        var ids = [TimelineItemIdentifier]()
        var contents = [RoomMessageEventContentWithoutRelation]()
        for itemID in itemIDs {
            guard let content = await timelineController.messageEventContent(for: itemID) else { continue }
            ids.append(itemID)
            contents.append(content)
        }
        
        guard !contents.isEmpty else { return nil }
        return .init(ids: ids, roomID: roomProxy.id, contents: contents)
    }
    
    private func forwardMessage(itemID: TimelineItemIdentifier) async {
        guard let forwardingPayload = await makeForwardingPayload(for: [itemID]) else { return }
        actionsSubject.send(.displayMessageForwarding(forwardingPayload: forwardingPayload))
    }
}

// MARK: - Selection

extension TimelineViewModel {
    private func startSelection(itemID: TimelineItemIdentifier) {
        guard let eventID = selectableEventID(for: itemID) else { return }
        
        // The composer is collapsed while selecting, so don't leave the microphone open behind it.
        Task { await timelineInteractionHandler.stopRecordingVoiceMessageIfNeeded() }
        actionsSubject.send(.composer(action: .removeFocus))
        
        guard !state.messageSelection.isAtLimit || state.messageSelection.selectedEventIDs.contains(eventID) else {
            showSelectionLimitToast()
            return
        }
        
        state.messageSelection.isActive = true
        state.messageSelection.selectedEventIDs.insert(eventID)
    }
    
    private func toggleSelection(itemID: TimelineItemIdentifier) {
        guard state.messageSelection.isActive, let eventID = selectableEventID(for: itemID) else { return }
        
        if state.messageSelection.selectedEventIDs.contains(eventID) {
            state.messageSelection.selectedEventIDs.remove(eventID)
        } else if state.messageSelection.isAtLimit {
            showSelectionLimitToast()
        } else {
            state.messageSelection.selectedEventIDs.insert(eventID)
        }
    }
    
    /// Drops selected items that are no longer selectable (e.g. redacted), or the whole selection
    /// when the timeline is swapped, so the selection always refers to items that are on screen.
    private func reconcileSelection(with timelineItems: [RoomTimelineItemProtocol], isSwitchingTimelines: Bool) {
        guard state.messageSelection.isActive else { return }
        
        if isSwitchingTimelines {
            state.messageSelection.end()
            return
        }
        
        let forwardableEventIDs = timelineItems.forwardableItems.compactMap(\.id.eventID)
        state.messageSelection.selectedEventIDs.formIntersection(forwardableEventIDs)
    }
    
    /// Ends the selection, either from the close button or once the selected messages have been forwarded.
    func clearMessageSelection() {
        state.messageSelection.end()
    }
    
    /// Forwards the selection in timeline order, which is unrelated to the order the messages were selected in.
    /// The selection is kept until the forwarding completes, so cancelling the picker returns to it.
    private func forwardSelection() {
        let itemIDs = timelineController.timelineItems.selectedItems(state.messageSelection.selectedEventIDs).map(\.id)
        
        Task {
            guard let forwardingPayload = await makeForwardingPayload(for: itemIDs) else {
                displayErrorToast(L10n.errorUnknown)
                return
            }
            actionsSubject.send(.displayMessageForwarding(forwardingPayload: forwardingPayload))
        }
    }
    
    /// The event ID of the item, when it is part of this timeline and can be forwarded.
    private func selectableEventID(for itemID: TimelineItemIdentifier) -> String? {
        guard let item = timelineController.timelineItems.firstUsingStableID(itemID) as? EventBasedTimelineItemProtocol,
              item.isForwardable else {
            return nil
        }
        return item.id.eventID
    }
    
    private func showSelectionLimitToast() {
        userIndicatorController.submitIndicator(UserIndicator(id: Constants.selectionLimitIndicatorID,
                                                              type: .toast,
                                                              title: L10n.screenRoomMaximumMessagesSelected,
                                                              icon: \.info))
    }
}

// MARK: - Mocks

extension TimelineViewModel {
    static let mock = mock(timelineKind: .live)
    
    static func mock(timelineKind: TimelineKind = .live,
                     timelineController: TimelineControllerMock? = nil,
                     hasPredecessor: Bool = false,
                     contentScannerService: ContentScannerServiceProtocol? = nil) -> TimelineViewModel {
        let clientProxyMock = ClientProxyMock(.init())
        clientProxyMock.roomSummaryForAliasReturnValue = .mock(id: "!room:matrix.org", name: "Room")
        clientProxyMock.roomSummaryForIdentifierReturnValue = .mock(id: "!room:matrix.org", name: "Room", canonicalAlias: "#room:matrix.org")
        let roomProxy = JoinedRoomProxyMock(.init(name: "Preview room", predecessor: hasPredecessor ? .init(roomId: UUID().uuidString) : nil))
        
        return TimelineViewModel(roomProxy: roomProxy,
                                 focussedEventID: nil,
                                 timelineController: timelineController ?? TimelineControllerMock(.init(timelineKind: timelineKind)),
                                 userSession: UserSessionMock(.init(clientProxy: clientProxyMock, contentScannerService: contentScannerService)),
                                 mediaPlayerProvider: MediaPlayerProviderMock(),
                                 userIndicatorController: UserIndicatorControllerMock(),
                                 appMediator: AppMediatorMock(.init()),
                                 analyticsService: AnalyticsServiceMock(.init()),
                                 emojiProvider: EmojiProvider(userSettings: .mock()),
                                 linkMetadataProvider: LinkMetadataProvider(),
                                 timelineControllerFactory: TimelineControllerFactoryMock(.init()))
    }
}

extension EnvironmentValues {
    /// Used to access and inject the room context without observing it
    @Entry var timelineContext: TimelineViewModel.Context?
    /// An event ID which will be non-nil when a timeline item should show as focussed.
    @Entry var focussedEventID: String?
}

private enum SlashCommand: String, CaseIterable {
    case join = "/join "
}
