//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

typealias TimelineMediaPreviewViewModelType = StateStoreViewModel<TimelineMediaPreviewViewState, TimelineMediaPreviewViewAction>

class TimelineMediaPreviewViewModel: TimelineMediaPreviewViewModelType {
    static let displayMessageForwardingDelay: TimeInterval = 1.0
    
    let instanceID = UUID()
    
    private let timelineViewModel: TimelineViewModelProtocol
    private let mediaProvider: MediaProviderProtocol
    private let photoLibraryManager: PhotoLibraryManagerProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    private let appMediator: AppMediatorProtocol
    /// Puts the composer behind the viewer into reply mode, for screens that have one.
    private let replyHandler: ((EventBasedMessageTimelineItemProtocol) -> Void)?
    
    private var contentScannerService: ContentScannerServiceProtocol? {
        timelineViewModel.context.contentScannerService
    }
    
    /// Downloads under way, so that a page reached while its file is loading ahead doesn't download it again.
    private var fileLoads: [MediaPreviewItemID: Task<Void, Never>] = [:]
    /// Videos larger than this are only downloaded once they are shown, never ahead.
    private static let videoPrefetchLimit: UInt = 25 * 1024 * 1024
    
    private let actionsSubject: PassthroughSubject<TimelineMediaPreviewViewModelAction, Never> = .init()
    var actions: AnyPublisher<TimelineMediaPreviewViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    /// Initialises a preview spanning the whole timeline's media, staying in sync with it as it paginates.
    init(initialItem: EventBasedMessageTimelineItemProtocol,
         timelineViewModel: TimelineViewModelProtocol,
         mediaProvider: MediaProviderProtocol,
         photoLibraryManager: PhotoLibraryManagerProtocol,
         userIndicatorController: UserIndicatorControllerProtocol,
         appMediator: AppMediatorProtocol,
         replyHandler: ((EventBasedMessageTimelineItemProtocol) -> Void)? = nil) {
        self.timelineViewModel = timelineViewModel
        self.mediaProvider = mediaProvider
        self.photoLibraryManager = photoLibraryManager
        self.userIndicatorController = userIndicatorController
        self.appMediator = appMediator
        self.replyHandler = replyHandler
        
        let timelineState = timelineViewModel.context.viewState.timelineState
        
        super.init(initialViewState: TimelineMediaPreviewViewState(dataSource: .init(itemViewStates: timelineState.itemViewStates,
                                                                                     initialItem: initialItem,
                                                                                     paginationState: timelineState.paginationState,
                                                                                     allowedGalleryItemTypes: timelineViewModel.context.viewState.allowedGalleryItemTypes)),
                   mediaProvider: mediaProvider)
        
        rebuildCurrentItemActions()
        Task { await updateCurrentItem(state.currentItem) }
        
        // AGENT-PLATFORM (end-stage review, 2026-11-14): only a change of either permission rebuilds the actions. Each
        // map used to send on every update of the timeline's state, and each rebuild refreshes the viewer's pages.
        timelineViewModel.context.$viewState
            .map { RedactPermissions(canRedactSelf: $0.canCurrentUserRedactSelf, canRedactOthers: $0.canCurrentUserRedactOthers) }
            .removeDuplicates()
            .dropFirst() // The actions were built above.
            .sink { [weak self] _ in
                self?.rebuildCurrentItemActions()
            }
            .store(in: &cancellables)
        
        // AGENT-PLATFORM (end-stage review, 2026-11-14): rows change in place on the same view state objects, which
        // compare by identity, so the rows themselves never looked changed: a sent upload kept its local echo (no
        // Reply) and media deleted elsewhere stayed. A new build of the rows is looked at, and only a change to the
        // media rows updates the viewer.
        timelineViewModel.context.$viewState
            .map(\.timelineState)
            .removeDuplicates { $0.buildID == $1.buildID }
            // The media rows' content is read as each build arrives: the rows themselves are the same objects later.
            .map { (rows: $0.itemViewStates, media: $0.itemViewStates.previewableMediaTypes) }
            .removeDuplicates { $0.media == $1.media }
            .map(\.rows)
            .dropFirst() // The data source was built from these rows.
            .sink { [weak self] itemViewStates in
                guard let self else { return }
                context.objectWillChange.send() // The data source is a reference type: the strip and the count need a manual update.
                state.dataSource.updatePreviewItems(itemViewStates: itemViewStates)
                rebuildCurrentItemActions() // A sent echo can now be replied to; deleted media is no longer current.
            }
            .store(in: &cancellables)
        
        timelineViewModel.context.$viewState.map(\.timelineState.paginationState)
            .removeDuplicates()
            .sink { [weak self] paginationState in
                guard let self else { return }
                context.objectWillChange.send()
                state.dataSource.paginationState = paginationState
                paginateIfNeeded()
            }
            .store(in: &cancellables)
        
        // AGENT-PLATFORM (1.0.3): Media and files says a failed page in place, under the viewer, and keeps its toast
        // back for that; over it, a swipe to older media would show its loading page with no word. The viewer says it.
        if timelineViewModel.context.viewState.timelineKind == .media(.mediaFilesScreen) {
            timelineViewModel.context.$viewState.map(\.timelineState.hasBackPaginationFailed)
                .removeDuplicates()
                .dropFirst()
                .filter { $0 }
                .sink { [weak self] _ in
                    self?.showPageFailedIndicator()
                }
                .store(in: &cancellables)
        }
    }
    
    /// Initialises the preview scoped to a single gallery's attachments. The data source is
    /// built from the gallery's items directly and isn't kept in sync with the underlying
    /// timeline — gallery contents don't change without the event being replaced or redacted.
    init(galleryItem: GalleryRoomTimelineItem,
         initialIndex: Int,
         timelineViewModel: TimelineViewModelProtocol,
         mediaProvider: MediaProviderProtocol,
         photoLibraryManager: PhotoLibraryManagerProtocol,
         userIndicatorController: UserIndicatorControllerProtocol,
         appMediator: AppMediatorProtocol,
         replyHandler: ((EventBasedMessageTimelineItemProtocol) -> Void)? = nil) {
        self.timelineViewModel = timelineViewModel
        self.mediaProvider = mediaProvider
        self.photoLibraryManager = photoLibraryManager
        self.userIndicatorController = userIndicatorController
        self.appMediator = appMediator
        self.replyHandler = replyHandler
        
        super.init(initialViewState: TimelineMediaPreviewViewState(dataSource: .init(galleryItem: galleryItem,
                                                                                     initialIndex: initialIndex)),
                   mediaProvider: mediaProvider)
        
        rebuildCurrentItemActions()
        Task { await updateCurrentItem(state.currentItem) }
        
        timelineViewModel.context.$viewState.map(\.canCurrentUserRedactSelf)
            .merge(with: timelineViewModel.context.$viewState.map(\.canCurrentUserRedactOthers))
            .sink { [weak self] _ in self?.rebuildCurrentItemActions() }
            .store(in: &cancellables)
    }
    
    override func process(viewAction: TimelineMediaPreviewViewAction) {
        switch viewAction {
        case .pageChanged(let page):
            showPage(page)
        case .showPage(let page):
            state.pagerDriver.send(page)
            showPage(page)
        case .prefetch(let pages):
            prefetch(pages)
        case .toggleChrome:
            state.bindings.isChromeHidden.toggle()
        case .showItemDetails(let mediaItem):
            state.bindings.detailsItem = mediaItem
        case .menuAction(let action, let item):
            switch action {
            case .viewInRoomTimeline:
                state.bindings.detailsItem = nil
                actionsSubject.send(.viewInRoomTimeline(item.timelineItem.id))
            case .downloadMedia:
                Task { await saveItem(item) }
            case .redact:
                state.bindings.redactConfirmationItem = item
            case .forward(let itemID):
                Task { await forwardItem(itemID: itemID) }
            default:
                MXLog.error("Received unexpected action: \(action)")
            }
        case .redactConfirmation(let item, let reason):
            redactItem(item, reason: reason)
        case .reply(let item):
            reply(to: item)
        case .openFile(let item):
            guard let fileHandle = item.fileHandle else { return }
            state.bindings.quickLookItem = MediaPreviewItem(file: fileHandle, title: item.filename)
        }
    }
    
    private func showPage(_ page: TimelineMediaPreviewPage) {
        guard page != state.dataSource.currentPage else { return }
        
        let previewItem: TimelineMediaPreviewItem
        switch page {
        case .media(let id):
            guard let media = state.dataSource.media(for: id) else {
                MXLog.error("The pager showed media that isn't loaded.")
                return
            }
            previewItem = .media(media)
        case .loading(.backwards):
            previewItem = .loading(.paginatingBackwards)
        case .loading(.forwards):
            previewItem = .loading(.paginatingForwards)
        }
        
        Task { await updateCurrentItem(previewItem) }
    }
    
    private func forwardItem(itemID: TimelineItemIdentifier) async {
        guard let forwardingPayload = await timelineViewModel.makeForwardingPayload(for: [itemID]) else { return }
        state.bindings.detailsItem = nil
        actionsSubject.send(.displayMessageForwarding(forwardingPayload))
    }
    
    private func reply(to item: TimelineMediaPreviewItem.Media) {
        guard state.canReplyToCurrentItem, let replyHandler else { return }
        actionsSubject.send(.dismiss)
        replyHandler(item.timelineItem)
    }
    
    private func updateCurrentItem(_ previewItem: TimelineMediaPreviewItem) async {
        if case let .media(item) = previewItem {
            item.downloadError = nil // Clear any existing error so that the download is retried.
        }
        setCurrentItem(previewItem)
        paginateIfNeeded()
        
        guard case let .media(mediaItem) = previewItem else { return }
        // A download started ahead of the swipe is waited for rather than repeated.
        if let running = fileLoads[mediaItem.id] {
            await running.value
        }
        guard mediaItem.fileHandle == nil else { return }
        await loadFile(for: mediaItem, isCurrent: true)
    }
    
    /// Downloads the files of the media on `pages`, quietly: a failure here is retried when the page is reached.
    private func prefetch(_ pages: [TimelineMediaPreviewPage]) {
        for page in pages {
            guard case let .media(id) = page, let mediaItem = state.dataSource.media(for: id),
                  mediaItem.fileHandle == nil, fileLoads[id] == nil else {
                continue
            }
            switch mediaItem.kind {
            case .image:
                break
            case .video:
                guard let fileSize = mediaItem.fileSize, fileSize <= Self.videoPrefetchLimit else { continue }
            case .audio, .file:
                continue
            }
            Task { await loadFile(for: mediaItem, isCurrent: false) }
        }
    }
    
    /// Downloads a media's file after the content scanner, if there is one, has found it safe. Only the current
    /// item shows the scan's progress and a failure.
    private func loadFile(for mediaItem: TimelineMediaPreviewItem.Media, isCurrent: Bool) async {
        let task = Task {
            guard let source = mediaItem.mediaSource,
                  await checkSourceIsSafeIfNeeded(for: mediaItem, source: source, reflectsScan: isCurrent) else {
                return
            }
            
            switch await mediaProvider.loadFileFromSource(source, filename: mediaItem.filename) {
            case .success(let handle):
                mediaItem.fileHandle = handle
            case .failure(let error):
                MXLog.error("Failed loading media: \(error)")
                if isCurrent {
                    mediaItem.downloadError = error
                }
            }
            context.objectWillChange.send() // The item is a reference type so the bars need a manual update.
            state.mediaDidLoad.send(mediaItem.id)
        }
        fileLoads[mediaItem.id] = task
        await task.value
        fileLoads[mediaItem.id] = nil
    }
    
    /// Scans the media when a content scanner is configured, returning whether it's safe to be downloaded
    /// and previewed. For the current item the scan's progress and outcome show in the current item. Both the
    /// media and its thumbnail are scanned as either being downloaded through the scanner can flag the media.
    private func checkSourceIsSafeIfNeeded(for mediaItem: TimelineMediaPreviewItem.Media,
                                           source: MediaSourceProxy,
                                           reflectsScan: Bool) async -> Bool {
        guard let contentScannerService else { return true }
        
        let sources = [source, mediaItem.thumbnailMediaSource].compactMap { $0 }
        
        // Only reflect the scanning state when there's no cached verdict, so that
        // scanned items don't flash the scanning indicator when they're revisited.
        if reflectsScan, contentScannerService.scanResultFromSources(sources) == nil {
            setCurrentItem(.contentScan(.init(media: mediaItem, state: .scanning)))
        }
        
        let isSafe: Bool
        let outcome: TimelineMediaPreviewItem
        switch await contentScannerService.loadScanResultFromSources(sources) {
        case .success(true):
            (isSafe, outcome) = (true, .media(mediaItem))
        case .success(false):
            (isSafe, outcome) = (false, .contentScan(.init(media: mediaItem, state: .failure(.notSafe))))
        case .failure:
            (isSafe, outcome) = (false, .contentScan(.init(media: mediaItem, state: .failure(.notFound))))
        }
        if reflectsScan {
            finishScan(with: outcome, for: mediaItem)
        }
        return isSafe
    }
    
    /// Reflects the outcome of a scan in the current item, unless the user has already swiped on to another item.
    private func finishScan(with previewItem: TimelineMediaPreviewItem, for mediaItem: TimelineMediaPreviewItem.Media) {
        guard state.currentItem.mediaItem === mediaItem else { return }
        setCurrentItem(previewItem)
    }
    
    private func setCurrentItem(_ previewItem: TimelineMediaPreviewItem) {
        context.objectWillChange.send() // The data source is a reference type so the view needs a manual update.
        state.dataSource.updateCurrentItem(previewItem)
        rebuildCurrentItemActions()
    }
    
    private func paginateIfNeeded() {
        switch state.dataSource.paginationDirectionNeeded() {
        case .backwards:
            timelineViewModel.context.send(viewAction: .paginateBackwards)
        case .forwards:
            timelineViewModel.context.send(viewAction: .paginateForwards)
        case nil:
            break
        }
    }
    
    private struct RedactPermissions: Equatable {
        let canRedactSelf: Bool
        let canRedactOthers: Bool
    }
    
    private func rebuildCurrentItemActions() {
        let timelineContext = timelineViewModel.context
        state.currentItemActions = state.currentItem.mediaItem.flatMap { mediaItem in
            TimelineItemMenuActionProvider(timelineItem: mediaItem.timelineItem,
                                           canCurrentUserSendMessage: timelineContext.viewState.canCurrentUserSendMessage,
                                           canCurrentUserRedactSelf: timelineContext.viewState.canCurrentUserRedactSelf,
                                           canCurrentUserRedactOthers: timelineContext.viewState.canCurrentUserRedactOthers,
                                           canCurrentUserPin: timelineContext.viewState.canCurrentUserPin,
                                           pinnedEventIDs: timelineContext.viewState.pinnedEventIDs,
                                           isViewSourceEnabled: timelineContext.viewState.isViewSourceEnabled,
                                           areThreadsEnabled: timelineContext.viewState.areThreadsEnabled,
                                           timelineKind: timelineContext.viewState.timelineKind,
                                           emojiProvider: timelineContext.viewState.emojiProvider)
                .makeActions()
        }
        
        state.canReplyToCurrentItem = if replyHandler != nil, let mediaItem = state.currentItem.mediaItem {
            mediaItem.timelineItem.canBeRepliedTo && mediaItem.timelineItem.id.eventID != nil && timelineContext.viewState.canCurrentUserSendMessage
        } else {
            false
        }
    }
    
    private func saveItem(_ mediaItem: TimelineMediaPreviewItem.Media) async {
        guard let fileURL = mediaItem.fileURL else {
            MXLog.error("Unable to save an item without a URL, the button shouldn't be visible.")
            return
        }
        
        // Dismiss the details sheet (nicer flow for images/video but _required_ in order to select a file directory).
        state.bindings.detailsItem = nil
        
        do {
            switch mediaItem.kind {
            case .file, .audio:
                state.bindings.exportFile = .init(url: fileURL)
                return // Don't show the indicator.
            case .image:
                try await photoLibraryManager.addResource(.photo, at: fileURL).get()
            case .video:
                try await photoLibraryManager.addResource(.video, at: fileURL).get()
            }
            
            showSavedIndicator()
        } catch PhotoLibraryManagerError.notAuthorized {
            MXLog.error("Not authorised to save item to photo library")
            showAuthorizationRequiredAlert()
        } catch {
            MXLog.error("Failed saving item: \(error)")
            showErrorIndicator()
        }
    }
    
    private func redactItem(_ item: TimelineMediaPreviewItem.Media, reason: String) {
        timelineViewModel.context.send(viewAction: .redactConfirmed(itemID: item.timelineItem.id, reason: reason))
        state.bindings.redactConfirmationItem = nil
        state.bindings.detailsItem = nil
        actionsSubject.send(.dismiss)
        showRedactedIndicator()
    }
    
    // MARK: - Indicators
    
    private func showRedactedIndicator() {
        userIndicatorController.submitIndicator(UserIndicator(id: statusIndicatorID,
                                                              type: .toast,
                                                              title: L10n.commonFileDeleted,
                                                              icon: \.check))
    }
    
    private func showSavedIndicator() {
        userIndicatorController.submitIndicator(UserIndicator(id: statusIndicatorID,
                                                              type: .toast,
                                                              title: L10n.commonFileSaved,
                                                              icon: \.check))
    }
    
    private func showErrorIndicator() {
        userIndicatorController.submitIndicator(UserIndicator(id: statusIndicatorID,
                                                              type: .toast,
                                                              title: L10n.errorUnknown,
                                                              icon: \.close))
    }
    
    private func showPageFailedIndicator() {
        userIndicatorController.submitIndicator(UserIndicator(id: statusIndicatorID,
                                                              type: .toast,
                                                              title: L10n.errorFailedLoadingMessages,
                                                              icon: \.close))
    }
    
    private func showAuthorizationRequiredAlert() {
        state.bindings.alertInfo = .init(id: UUID(),
                                         title: L10n.dialogPermissionPhotoLibraryTitleIos(InfoPlistReader.main.bundleDisplayName),
                                         primaryButton: .init(title: L10n.commonSettings) { [appMediator] in appMediator.openAppSettings() },
                                         secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
    }
    
    private var statusIndicatorID: String {
        "\(Self.self)-Status"
    }
}
