//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import MatrixRustSDK
@testable import Spiral
import SwiftUI
import Testing

@MainActor
struct TimelineMediaPreviewViewModelTests {
    var viewModel: TimelineMediaPreviewViewModel!
    var context: TimelineMediaPreviewViewModel.Context {
        viewModel.context
    }
    
    var mediaProvider: MediaProviderMock!
    var photoLibraryManager: PhotoLibraryManagerMock!
    var timelineController: TimelineControllerMock!
    var timelineViewModel: TimelineViewModel! // AGENT-PLATFORM: the rows behind the viewer
    var userIndicatorController: UserIndicatorControllerMock! // AGENT-PLATFORM: what the viewer says
    
    @Test
    mutating func loadingItem() async throws {
        // Given a fresh view model.
        setupViewModel()
        #expect(context.viewState.currentItem == .media(context.viewState.dataSource.previewItems[0]))
        #expect(context.viewState.currentItemActions != nil)
        
        // When it opens, it loads the item it opened on.
        try await loadInitialItem()
        
        // Then the view model should load the item and update its view state.
        #expect(mediaProvider.loadFileFromSourceFilenameCallsCount == 1)
        #expect(context.viewState.currentItem == .media(context.viewState.dataSource.previewItems[0]))
        #expect(context.viewState.currentItemActions != nil)
    }
    
    @Test
    mutating func loadingItemFailure() async {
        // Given a view model whose media fails to load.
        setupViewModel(loadFails: true)
        let mediaItem = context.viewState.dataSource.previewItems[0]
        #expect(context.viewState.currentItem == .media(mediaItem))
        
        // When it opens.
        await waitUntil { mediaItem.downloadError != nil }
        
        // Then the failure should be reflected in the item.
        #expect(mediaProvider.loadFileFromSourceFilenameCalled)
        #expect(mediaItem.downloadError != nil)
        #expect(mediaItem.fileHandle == nil)
    }
    
    @Test
    mutating func swipingBetweenItems() async throws {
        // Given a view model with a loaded item.
        try await loadingItem()
        let items = context.viewState.dataSource.previewItems
        
        // When swiping to another item.
        context.send(viewAction: .pageChanged(.media(items[1].id)))
        await waitUntil { items[1].fileHandle != nil }
        
        // Then the view model should load the item and update its view state.
        #expect(mediaProvider.loadFileFromSourceFilenameCallsCount == 2)
        #expect(context.viewState.currentItem == .media(items[1]))
        #expect(context.viewState.dataSource.position == .init(number: 2, count: 3))
        
        // When swiping back to the first item.
        context.send(viewAction: .pageChanged(.media(items[0].id)))
        await waitUntil { context.viewState.currentItem == .media(items[0]) }
        
        // Then the view model should not need to load the item, but should still update its view state.
        #expect(mediaProvider.loadFileFromSourceFilenameCallsCount == 2)
        #expect(context.viewState.dataSource.position == .init(number: 1, count: 3))
    }
    
    @Test
    mutating func tappingAThumbnail() async throws {
        // Given a view model with a loaded item.
        try await loadingItem()
        let items = context.viewState.dataSource.previewItems
        
        // When tapping the last thumbnail.
        let deferred = deferFulfillment(context.viewState.pagerDriver) { $0 == .media(items[2].id) }
        context.send(viewAction: .showPage(.media(items[2].id)))
        
        // Then the pager is told to show it, and it becomes the current item.
        try await deferred.fulfill()
        await waitUntil { items[2].fileHandle != nil }
        #expect(context.viewState.currentItem == .media(items[2]))
        #expect(context.viewState.dataSource.position == .init(number: 3, count: 3))
    }
    
    @Test
    mutating func prefetchingTheNeighbours() async throws {
        // Given a viewer opened on the video, between a photo and a file.
        setupViewModel(initialItemIndex: 1)
        let items = context.viewState.dataSource.previewItems
        await waitUntil { items[1].fileHandle != nil }
        #expect(mediaProvider.loadFileFromSourceFilenameCallsCount == 1)
        
        // When the pager asks for the pages a swipe either way reaches.
        let deferred = deferFulfillment(context.viewState.mediaDidLoad) { $0 == items[0].id }
        context.send(viewAction: .prefetch([.media(items[0].id), .media(items[2].id)]))
        try await deferred.fulfill()
        
        // Then the photo's file is downloaded ahead, the file waits to be opened, and the video stays current.
        #expect(items[0].fileHandle != nil)
        #expect(items[2].fileHandle == nil)
        #expect(mediaProvider.loadFileFromSourceFilenameCallsCount == 2)
        #expect(context.viewState.currentItem == .media(items[1]))
        
        // When the user then swipes onto the photo, it isn't downloaded again.
        context.send(viewAction: .pageChanged(.media(items[0].id)))
        await waitUntil { context.viewState.currentItem == .media(items[0]) }
        #expect(mediaProvider.loadFileFromSourceFilenameCallsCount == 2)
    }
    
    @Test
    mutating func largeVideosAreNotPrefetched() async {
        // Given a viewer opened on the photo, next to a video larger than the prefetch limit.
        setupViewModel(initialItemIndex: 0)
        let items = context.viewState.dataSource.previewItems
        await waitUntil { items[0].fileHandle != nil }
        
        // When the pager asks for the video ahead of a swipe.
        context.send(viewAction: .prefetch([.media(items[1].id)]))
        await waitUntil { items[1].fileHandle != nil }
        
        // Then it waits until the video is shown.
        #expect(items[1].fileHandle == nil)
        #expect(mediaProvider.loadFileFromSourceFilenameCallsCount == 1)
    }
    
    @Test
    mutating func togglingTheChrome() {
        // Given a fresh view model, whose bars show.
        setupViewModel()
        #expect(!context.isChromeHidden)
        
        // When tapping the media, the bars hide; tapping again shows them.
        context.send(viewAction: .toggleChrome)
        #expect(context.isChromeHidden)
        context.send(viewAction: .toggleChrome)
        #expect(!context.isChromeHidden)
    }
    
    @Test
    mutating func loadingMoreItems() async throws {
        // Given a view model with a loaded item.
        try await loadingItem()
        
        // When swiping to the loading page at the start and there are more media items to load.
        timelineController.update(paginationState: .init(backward: .idle, forward: .endReached))
        context.send(viewAction: .pageChanged(.loading(.backwards)))
        await waitUntil { timelineController.paginateBackwardsRequestSizeCallsCount > 0 }
        
        // Then there should no longer be a media preview and instead of loading any media, a pagination request should be made.
        #expect(mediaProvider.loadFileFromSourceFilenameCallsCount == 1)
        #expect(context.viewState.currentItem == .loading(.paginatingBackwards))
        #expect(context.viewState.dataSource.position == nil)
        #expect(timelineController.paginateBackwardsRequestSizeCallsCount > 0)
    }
    
    // AGENT-PLATFORM (1.0.3): the browser behind keeps its toast back, so a failed swipe to older media is told here.
    @Test
    mutating func aFailedPageIsTold() async throws {
        try await loadingItem()
        timelineController.paginateBackwardsRequestSizeClosure = { _ in .failure(.generic) }
        
        timelineController.update(paginationState: .init(backward: .idle, forward: .endReached))
        context.send(viewAction: .pageChanged(.loading(.backwards)))
        await waitUntil { userIndicatorController.submitIndicatorDelayReceivedInvocations.contains { $0.indicator.title == L10n.errorFailedLoadingMessages } }
        
        #expect(userIndicatorController.submitIndicatorDelayReceivedInvocations.contains { $0.indicator.title == L10n.errorFailedLoadingMessages })
        #expect(context.viewState.currentItem == .loading(.paginatingBackwards))
    }
    
    @Test
    mutating func pagination() async throws {
        // Given a view model with a loaded item.
        try await loadingItem()
        #expect(context.viewState.dataSource.previewItems.count == 3)
        
        // When more items are added via a back pagination.
        let deferred = deferFulfillment(context.viewState.dataSource.previewItemsPaginationPublisher) { _ in true }
        let viewUpdate = deferFulfillment(context.objectWillChange) { _ in true } // The strip and the count redraw.
        timelineController.setupBackPagination(responses: [makeItems()])
        _ = await timelineController.paginateBackwards(requestSize: 20)
        try await deferred.fulfill()
        try await viewUpdate.fulfill()
        await waitUntil { context.viewState.dataSource.previewItems.count == 6 }
        
        // Then the current item is now further along, without being reloaded.
        #expect(context.viewState.dataSource.previewItems.count == 6)
        #expect(context.viewState.currentItem == .media(context.viewState.dataSource.previewItems[3]))
        #expect(context.viewState.dataSource.position == .init(number: 4, count: 6))
        #expect(mediaProvider.loadFileFromSourceFilenameCallsCount == 1)
    }
    
    @Test
    mutating func replyInARoom() async throws {
        // Given a viewer opened from a room, whose timeline can reply.
        var repliedItem: EventBasedMessageTimelineItemProtocol?
        setupViewModel(timelineKind: .media(.roomScreenLive)) { repliedItem = $0 }
        try await loadInitialItem()
        let mediaItem = context.viewState.dataSource.previewItems[0]
        #expect(context.viewState.canReplyToCurrentItem)
        
        // When replying to the photo.
        let deferred = deferFulfillment(viewModel.actions) { $0 == .dismiss }
        context.send(viewAction: .reply(mediaItem))
        
        // Then the viewer closes and the room's composer replies to it.
        try await deferred.fulfill()
        #expect(repliedItem?.id == mediaItem.timelineItem.id)
    }
    
    /// AGENT-PLATFORM (end-stage review, 2026-11-14): rows change in place, on the same view states. An upload sent
    /// while the viewer shows it goes by its event ID from then on, and can be replied to.
    @Test
    mutating func aSentUploadCanBeRepliedTo() async throws {
        // Given a viewer opened from a room on an upload still in flight: a local echo, which can't be replied to.
        let uniqueID = TimelineItemIdentifier.UniqueID(UUID().uuidString)
        func makeUpload(id: TimelineItemIdentifier.EventOrTransactionID) -> ImageRoomTimelineItem {
            ImageRoomTimelineItem(id: .event(uniqueID: uniqueID, eventOrTransactionID: id),
                                  timestamp: .mock,
                                  isOutgoing: true,
                                  isEditable: false,
                                  canBeRepliedTo: true,
                                  sender: .init(id: "Alice"),
                                  content: .init(filename: "upload.jpg", imageInfo: .mockImage, thumbnailInfo: nil, blurhash: nil))
        }
        var items: [RoomTimelineItemProtocol] = makeItems()
        items.append(makeUpload(id: .transactionID("t1")))
        setupViewModel(items: items, initialItemIndex: 3, timelineKind: .media(.roomScreenLive)) { _ in }
        #expect(!context.viewState.canReplyToCurrentItem)
        let rowBefore = try #require(timelineViewModel.context.viewState.timelineState.itemViewStates.last)
        
        // When the upload is sent and the timeline swaps its transaction ID for its event ID.
        items[3] = makeUpload(id: .eventID("$sent"))
        timelineController.timelineItems = items
        timelineController.callbacks.send(.updatedTimelineItems(timelineItems: items, isSwitchingTimelines: false))
        await waitUntil { context.viewState.canReplyToCurrentItem }
        
        // Then the row was updated in place, and the viewer follows it: the photo is current under its event ID and
        // can be replied to.
        #expect(timelineViewModel.context.viewState.timelineState.itemViewStates.last === rowBefore)
        #expect(context.viewState.canReplyToCurrentItem)
        #expect(context.viewState.currentItem.mediaItem?.id == .timelineItem(.eventID("$sent")))
        #expect(context.viewState.dataSource.previewItems.count == 4)
    }
    
    /// AGENT-PLATFORM (end-stage review, 2026-11-14): media deleted elsewhere, which turns its row into a removed
    /// message in place, leaves the viewer.
    @Test
    mutating func mediaDeletedElsewhereLeavesTheViewer() async throws {
        // Given a viewer on the photo, next to a video and a file.
        var items: [RoomTimelineItemProtocol] = makeItems()
        setupViewModel(items: items)
        let video = try #require(items[1] as? EventBasedMessageTimelineItemProtocol)
        #expect(context.viewState.dataSource.previewItems.count == 3)
        
        // When someone deletes the video.
        let pagesChanged = deferFulfillment(context.viewState.dataSource.previewItemsPaginationPublisher) { _ in true }
        items[1] = RedactedRoomTimelineItem(id: video.id, body: "Message removed", timestamp: .mock, isOutgoing: false,
                                            isEditable: false, canBeRepliedTo: false, sender: video.sender)
        timelineController.timelineItems = items
        timelineController.callbacks.send(.updatedTimelineItems(timelineItems: items, isSwitchingTimelines: false))
        try await pagesChanged.fulfill()
        
        // Then the pager is told and the video's page is gone; the photo stays current.
        let remaining = [items[0], items[2]].compactMap { $0 as? EventBasedMessageTimelineItemProtocol }
        #expect(context.viewState.dataSource.previewItems.map(\.id) == remaining.map { TimelineMediaPreviewItem.Media(timelineItem: $0).id })
        #expect(context.viewState.currentItem.mediaItem?.timelineItem.id == items[0].id)
    }
    
    /// AGENT-PLATFORM (end-stage review, 2026-11-14): a change to a row with no media leaves the viewer alone.
    @Test
    mutating func aChangeToARowWithoutMediaLeavesTheViewerAlone() async throws {
        // Given a viewer over three media, with a text message among them.
        let text = TextRoomTimelineItem(id: .randomEvent, timestamp: .mock, isOutgoing: false, isEditable: false, canBeRepliedTo: true,
                                        sender: .init(id: "Bob"), content: .init(body: "Hi"))
        var items: [RoomTimelineItemProtocol] = makeItems()
        items.insert(text, at: 1)
        setupViewModel(items: items)
        try await loadInitialItem()
        try await Task.sleep(for: .milliseconds(100)) // The load's own refresh has gone.
        
        // When the text message is edited in place.
        let noViewUpdate = deferFailure(context.objectWillChange, timeout: .seconds(1)) { _ in true }
        items[1] = TextRoomTimelineItem(id: text.id, timestamp: .mock, isOutgoing: false, isEditable: false, canBeRepliedTo: true,
                                        sender: .init(id: "Bob"), content: .init(body: "Hello"))
        timelineController.timelineItems = items
        timelineController.callbacks.send(.updatedTimelineItems(timelineItems: items, isSwitchingTimelines: false))
        
        // Then the viewer doesn't refresh.
        try await noViewUpdate.fulfill()
    }
    
    @Test
    mutating func noReplyWithoutAComposer() {
        // Given a viewer opened from the room's media files, with no composer behind it.
        setupViewModel()
        
        // Then the viewer offers no reply.
        #expect(!context.viewState.canReplyToCurrentItem)
    }
    
    @Test
    mutating func viewInRoomTimeline() async throws {
        // Given a view model with a loaded item.
        try await loadingItem()
        
        // When choosing to view the current item in the timeline.
        guard case let .media(mediaItem) = context.viewState.currentItem else {
            Issue.record("There should be a current item.")
            return
        }
        
        let deferred = deferFulfillment(viewModel.actions) { $0 == .viewInRoomTimeline(mediaItem.timelineItem.id) }
        context.send(viewAction: .menuAction(.viewInRoomTimeline, item: mediaItem))
        
        // Then the action should be sent upwards to make this happen.
        try await deferred.fulfill()
    }
    
    @Test
    mutating func redactConfirmation() async throws {
        // Given a view model with a loaded item.
        try await loadingItem()
        #expect(context.redactConfirmationItem == nil)
        #expect(!timelineController.redactReasonCalled)
        guard case let .media(mediaItem) = context.viewState.currentItem else {
            Issue.record("There should be a current item.")
            return
        }
        
        // When choosing to show the item details.
        context.send(viewAction: .showItemDetails(mediaItem))
        
        // Then the details sheet should be presented.
        #expect(context.detailsItem == mediaItem)
        
        // When choosing to redact the item.
        context.send(viewAction: .menuAction(.redact(isMedia: true), item: mediaItem))
        
        // Then the confirmation sheet should be presented.
        #expect(context.redactConfirmationItem == mediaItem)
        #expect(!timelineController.redactReasonCalled)
        
        // When confirming the redaction.
        let deferred = deferFulfillment(viewModel.actions) { $0 == .dismiss }
        
        // The redaction runs in an unstructured task, so wait for the call rather than asserting after the dismiss.
        await waitForConfirmation { confirmation in
            timelineController.redactReasonClosure = { _, _ in confirmation() }
            context.send(viewAction: .redactConfirmation(item: mediaItem, reason: "Wrong file"))
        }
        
        // Then the item should be redacted with the reason and the view should be dismissed.
        #expect(timelineController.redactReasonReceivedArguments?.reason == "Wrong file")
        try await deferred.fulfill()
        #expect(context.detailsItem == nil)
    }
    
    @Test
    mutating func saveImage() async throws {
        // Given a view model with a loaded image.
        try await loadingItem()
        guard case let .media(mediaItem) = context.viewState.currentItem else {
            Issue.record("There should be a current item")
            return
        }
        #expect(mediaItem.contentType == "JPEG image")
        
        // When choosing to save the image.
        context.send(viewAction: .menuAction(.downloadMedia, item: mediaItem))
        try await Task.sleep(for: .seconds(0.5))
        
        // Then the image should be saved as a photo to the user's photo library.
        #expect(photoLibraryManager.addResourceAtCalled)
        #expect(photoLibraryManager.addResourceAtReceivedArguments?.type == .photo)
        #expect(photoLibraryManager.addResourceAtReceivedArguments?.url == mediaItem.fileHandle?.url)
    }
    
    @Test
    mutating func saveImageWithoutAuthorization() async throws {
        // Given a view model with a loaded image where the user has denied access to the photo library.
        setupViewModel(photoLibraryAuthorizationDenied: true)
        try await loadInitialItem()
        guard case let .media(mediaItem) = context.viewState.currentItem else {
            Issue.record("There should be a current item")
            return
        }
        #expect(mediaItem.contentType == "JPEG image")
        
        // When choosing to save the image.
        context.send(viewAction: .menuAction(.downloadMedia, item: mediaItem))
        await waitUntil { context.alertInfo != nil }
        
        // Then the user should be prompted to allow access.
        #expect(context.alertInfo != nil)
        #expect(photoLibraryManager.addResourceAtCalled)
    }
    
    @Test
    mutating func saveVideo() async throws {
        // Given a view model with a loaded video.
        setupViewModel(initialItemIndex: 1)
        try await loadInitialItem()
        guard case let .media(mediaItem) = context.viewState.currentItem else {
            Issue.record("There should be a current item")
            return
        }
        #expect(mediaItem.contentType == "MPEG-4 movie")
        
        // When choosing to save the video.
        context.send(viewAction: .menuAction(.downloadMedia, item: mediaItem))
        try await Task.sleep(for: .seconds(0.5))
        
        // Then the video should be saved as a video in the user's photo library.
        #expect(photoLibraryManager.addResourceAtCalled)
        #expect(photoLibraryManager.addResourceAtReceivedArguments?.type == .video)
        #expect(photoLibraryManager.addResourceAtReceivedArguments?.url == mediaItem.fileHandle?.url)
    }
    
    @Test
    mutating func saveFile() async throws {
        // Given a view model with a loaded file.
        setupViewModel(initialItemIndex: 2)
        try await loadInitialItem()
        guard case let .media(mediaItem) = context.viewState.currentItem else {
            Issue.record("There should be a current item")
            return
        }
        #expect(mediaItem.contentType == "PDF document")
        
        // When choosing to save the file.
        context.send(viewAction: .menuAction(.downloadMedia, item: mediaItem))
        await waitUntil { context.exportFile != nil }
        
        // Then the binding should be set for the user to export the file to their specified location.
        #expect(!photoLibraryManager.addResourceAtCalled)
        #expect(context.exportFile?.url == mediaItem.fileHandle?.url)
    }
    
    @Test
    mutating func safeItem() async throws {
        // Given a view model with a content scanner that reports the media as safe.
        setupViewModel(contentScannerService: ContentScannerServiceMock(.init(scanResult: true)))
        
        // When the viewer opens on it.
        try await loadInitialItem()
        
        // Then the media should be downloaded as usual.
        guard case .media = context.viewState.currentItem else {
            Issue.record("The item should be previewable")
            return
        }
        #expect(mediaProvider.loadFileFromSourceFilenameCalled)
    }
    
    @Test
    mutating func unsafeItem() async {
        // Given a view model with a content scanner that reports the media as unsafe.
        setupViewModel(contentScannerService: ContentScannerServiceMock(.init(scanResult: false)))
        guard case let .media(mediaItem) = context.viewState.currentItem else {
            Issue.record("There should be a current item")
            return
        }
        
        // When the viewer opens on it.
        await waitUntil { context.viewState.currentItem == .contentScan(.init(media: mediaItem, state: .failure(.notSafe))) }
        
        // Then the media must not be downloaded and the failure should be reflected in the current item.
        #expect(!mediaProvider.loadFileFromSourceFilenameCalled)
        #expect(context.viewState.currentItem == .contentScan(.init(media: mediaItem, state: .failure(.notSafe))))
        #expect(mediaItem.fileHandle == nil)
    }
    
    @Test
    mutating func failedScanItem() async {
        // Given a view model with a content scanner that fails to scan the media.
        let contentScannerService = ContentScannerServiceMock()
        contentScannerService.loadScanResultFromSourceClosure = { _ in .failure(.failedScanning) }
        setupViewModel(contentScannerService: contentScannerService)
        guard case let .media(mediaItem) = context.viewState.currentItem else {
            Issue.record("There should be a current item")
            return
        }
        
        // When the viewer opens on it.
        await waitUntil { context.viewState.currentItem == .contentScan(.init(media: mediaItem, state: .failure(.notFound))) }
        
        // Then the media must not be downloaded and the failure should be reflected in the current item.
        #expect(!mediaProvider.loadFileFromSourceFilenameCalled)
        #expect(context.viewState.currentItem == .contentScan(.init(media: mediaItem, state: .failure(.notFound))))
        #expect(mediaItem.fileHandle == nil)
    }
    
    // MARK: - Helpers
    
    /// The viewer loads the item it opens on by itself.
    private func loadInitialItem() async throws {
        let mediaItem = try #require(context.viewState.dataSource.currentItem.mediaItem)
        await waitUntil { mediaItem.fileHandle != nil }
        #expect(mediaItem.fileHandle != nil, "The initial item should load.")
    }
    
    /// Polls for up to 2 s: the view model loads in unstructured tasks.
    private func waitUntil(_ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(2)
        while !condition(), Date() < end {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
    
    private mutating func setupViewModel(items: [RoomTimelineItemProtocol]? = nil,
                                         initialItemIndex: Int = 0,
                                         timelineKind: TimelineKind = .media(.mediaFilesScreen),
                                         loadFails: Bool = false,
                                         photoLibraryAuthorizationDenied: Bool = false,
                                         contentScannerService: ContentScannerServiceProtocol? = nil,
                                         replyHandler: ((EventBasedMessageTimelineItemProtocol) -> Void)? = nil) {
        let initialItems: [RoomTimelineItemProtocol] = items ?? makeItems()
        timelineController = TimelineControllerMock(.init(timelineKind: timelineKind, timelineItems: initialItems))
        
        mediaProvider = MediaProviderMock(.init())
        if loadFails {
            mediaProvider.loadFileFromSourceFilenameClosure = { _, _ in .failure(.failedRetrievingFile) }
        }
        photoLibraryManager = PhotoLibraryManagerMock(.init(authorizationDenied: photoLibraryAuthorizationDenied))
        
        guard let initialItem = initialItems[initialItemIndex] as? EventBasedMessageTimelineItemProtocol else {
            fatalError("The viewer opens on a message's media.")
        }
        userIndicatorController = UserIndicatorControllerMock()
        timelineViewModel = TimelineViewModel.mock(timelineKind: timelineKind,
                                                   timelineController: timelineController,
                                                   contentScannerService: contentScannerService)
        viewModel = TimelineMediaPreviewViewModel(initialItem: initialItem,
                                                  timelineViewModel: timelineViewModel,
                                                  mediaProvider: mediaProvider,
                                                  photoLibraryManager: photoLibraryManager,
                                                  userIndicatorController: userIndicatorController,
                                                  appMediator: AppMediatorMock(),
                                                  replyHandler: replyHandler)
    }
    
    private func makeItems() -> [EventBasedMessageTimelineItemProtocol] {
        [
            ImageRoomTimelineItem(id: .randomEvent,
                                  timestamp: .mock,
                                  isOutgoing: false,
                                  isEditable: false,
                                  canBeRepliedTo: true,
                                  sender: .init(id: "", displayName: "Sally Sanderson"),
                                  content: .init(filename: "Amazing image.jpeg",
                                                 caption: "A caption goes right here.",
                                                 imageInfo: .mockImage,
                                                 thumbnailInfo: .mockThumbnail,
                                                 contentType: .jpeg)),
            VideoRoomTimelineItem(id: .randomEvent,
                                  timestamp: .mock,
                                  isOutgoing: false,
                                  isEditable: false,
                                  canBeRepliedTo: true,
                                  sender: .init(id: ""),
                                  content: .init(filename: "Super video.mp4",
                                                 videoInfo: .mockVideo,
                                                 thumbnailInfo: .mockThumbnail,
                                                 contentType: .mpeg4Movie)),
            FileRoomTimelineItem(id: .randomEvent,
                                 timestamp: .mock,
                                 isOutgoing: false,
                                 isEditable: false,
                                 canBeRepliedTo: true,
                                 sender: .init(id: ""),
                                 content: .init(filename: "Important file.pdf",
                                                source: try? .init(url: .mockMXCFile, mimeType: "document/pdf"),
                                                fileSize: 2453,
                                                thumbnailSource: nil,
                                                contentType: .pdf))
        ]
    }
}
