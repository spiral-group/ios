//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
@testable import Spiral
import Testing

@MainActor
struct TimelineMediaPreviewDataSourceTests {
    var initialMediaItems: [EventBasedMessageTimelineItemProtocol]!
    var initialMediaViewStates: [RoomTimelineItemViewState]!
    let initialItemIndex = 2
    
    init() {
        initialMediaItems = newChunk()
        initialMediaViewStates = initialMediaItems.map { RoomTimelineItemViewState(item: $0, groupStyle: .single) }
    }
    
    @Test
    func initialItems() throws {
        try assertInitialDataSource()
    }
    
    @Test
    func timelinePreviewFlattensGalleries() throws {
        // Given a timeline containing an image, a gallery of 2 attachments and a gallery of 3, one of
        // which is a file that belongs in the other timeline.
        let image = ImageRoomTimelineItem(id: .randomEvent,
                                          timestamp: .mock,
                                          isOutgoing: false,
                                          isEditable: false,
                                          canBeRepliedTo: true,
                                          sender: .init(id: "Bob"),
                                          content: .init(filename: "image.jpg", imageInfo: .mockImage, thumbnailInfo: nil, blurhash: nil))
        let firstGalleryItems: [GalleryItem] = [.mockImage(index: 0), .mockVideo(index: 1)]
        let secondGalleryItems: [GalleryItem] = [.mockImage(index: 0), .mockFile(index: 1), .mockImage(index: 2)]
        let timelineItems: [RoomTimelineItemProtocol] = [image,
                                                         makeGallery(items: firstGalleryItems),
                                                         makeGallery(items: secondGalleryItems)]
        let itemViewStates = timelineItems.map { RoomTimelineItemViewState(item: $0, groupStyle: .single) }
        
        // When opening the preview from the image, which isn't part of a gallery.
        let dataSource = TimelineMediaPreviewDataSource(itemViewStates: itemViewStates,
                                                        initialItem: image,
                                                        paginationState: .initial,
                                                        allowedGalleryItemTypes: [.image, .video])
        
        // Then the galleries' visual attachments are browsable as though they were individual messages,
        // whilst the file is left to the timeline that shows those.
        let imageID = try #require(image.id.eventOrTransactionID)
        let expectedIDs: [MediaPreviewItemID] = [.timelineItem(imageID),
                                                 .galleryItem(firstGalleryItems[0].id),
                                                 .galleryItem(firstGalleryItems[1].id),
                                                 .galleryItem(secondGalleryItems[0].id),
                                                 .galleryItem(secondGalleryItems[2].id)]
        #expect(dataSource.previewItems.map(\.id) == expectedIDs)
        
        // …starting from the tapped image.
        #expect(dataSource.currentMediaItemID == .timelineItem(imageID))
    }
    
    @Test
    func galleryPreview() throws {
        // Given a gallery message whose attachments are a mix of media types.
        let items: [GalleryItem] = [.mockImage(index: 0), .mockFile(index: 1), .mockVideo(index: 2), .mockAudio(index: 3)]
        let gallery = makeGallery(items: items)
        
        // When opening the preview scoped to that gallery on the second attachment.
        let dataSource = TimelineMediaPreviewDataSource(galleryItem: gallery, initialIndex: 1)
        
        // Then it is self contained, holding every one of the attachments without filtering any of
        // them out and with no surrounding pagination…
        let expectedIDs: [MediaPreviewItemID] = items.map { .galleryItem($0.id) }
        #expect(dataSource.previewItems.map(\.id) == expectedIDs)
        #expect(dataSource.pages == expectedIDs.map(TimelineMediaPreviewPage.media))
        #expect(dataSource.position == .init(number: 2, count: 4))
        
        // …and the initial item is the tapped attachment.
        let media = try #require(dataSource.currentItem.mediaItem, "The current item should be a media item.")
        #expect(media.id == .galleryItem(items[1].id))
    }
    
    @Test
    func galleryPreviewIncludesNonPreviewableItems() throws {
        // Given a gallery whose first attachment is an unknown type (the viewer shows it as a file it can't open).
        let items: [GalleryItem] = [
            .other(id: .mock(0), filename: "unknown.bin"),
            .mockImage(index: 1, filename: "image-1.jpg"),
            .mockImage(index: 2, filename: "image-2.jpg")
        ]
        let gallery = GalleryRoomTimelineItem(id: .randomEvent,
                                              timestamp: .mock,
                                              isOutgoing: false,
                                              isEditable: false,
                                              canBeRepliedTo: true,
                                              sender: .init(id: "Bob"),
                                              content: .init(body: "Gallery", caption: nil, items: items),
                                              properties: .init())
        
        // When tapping the first image (index 1 in the full items array).
        let dataSource = TimelineMediaPreviewDataSource(galleryItem: gallery, initialIndex: 1)
        
        // Then every attachment is kept — indices line up 1:1 — and the unknown item has no media source.
        #expect(dataSource.previewItems.count == 3)
        #expect(dataSource.previewItems[0].id == .galleryItem(items[0].id))
        #expect(dataSource.previewItems[0].mediaSource == nil)
        let media = try #require(dataSource.currentItem.mediaItem, "The current item should be a media item.")
        #expect(media.id == .galleryItem(items[1].id))
    }
    
    @Test
    func currentUpdateItem() {
        // Given a data source built with the initial items.
        let dataSource = TimelineMediaPreviewDataSource(itemViewStates: initialMediaViewStates,
                                                        initialItem: initialMediaItems[initialItemIndex],
                                                        paginationState: .initial)
        
        // When a different item is displayed.
        let previewItem = dataSource.previewItems[1]
        dataSource.updateCurrentItem(.media(previewItem))
        
        // Then the data source should reflect the change of item.
        #expect(dataSource.currentMediaItemID == previewItem.id, "The displayed item should be the new item.")
        #expect(dataSource.currentPage == .media(previewItem.id))
        
        // When a loading page is displayed.
        dataSource.updateCurrentItem(.loading(.paginatingBackwards))
        
        // Then the data source should show a loading item, with no position.
        #expect(dataSource.currentItem == .loading(.paginatingBackwards), "The displayed item should be the loading item.")
        #expect(dataSource.currentPage == .loading(.backwards))
        #expect(dataSource.position == nil)
    }
    
    @Test
    func pagesAroundTheLoadedMedia() async throws {
        // Given a data source whose timeline can load more in both directions.
        let dataSource = TimelineMediaPreviewDataSource(itemViewStates: initialMediaViewStates,
                                                        initialItem: initialMediaItems[initialItemIndex],
                                                        paginationState: .init(backward: .idle, forward: .idle))
        let mediaPages = dataSource.previewItems.map { TimelineMediaPreviewPage.media($0.id) }
        
        // Then the pages are the media in order, between a loading page at each end.
        #expect(dataSource.pages == [.loading(.backwards)] + mediaPages + [.loading(.forwards)])
        
        // When the timeline reaches both of its ends.
        let deferred = deferFulfillment(dataSource.previewItemsPaginationPublisher) { _ in true }
        dataSource.paginationState = .init(backward: .endReached, forward: .endReached)
        try await deferred.fulfill()
        
        // Then there is nothing to swipe to past the first and the last media.
        #expect(dataSource.pages == mediaPages)
    }
    
    @Test
    func olderMediaKeepsTheCurrentPage() {
        // Given the pages on screen while the user looks at the second media.
        let first = TimelineMediaPreviewPage.media(.timelineItem(.eventID("$1")))
        let second = TimelineMediaPreviewPage.media(.timelineItem(.eventID("$2")))
        let older = TimelineMediaPreviewPage.media(.timelineItem(.eventID("$0")))
        
        // When older media arrives in front of it.
        let pages: [TimelineMediaPreviewPage] = [.loading(.backwards), older, first, second, .loading(.forwards)]
        
        // Then the same media stays on screen, at its new index.
        let kept = TimelineMediaPreviewDataSource.page(keeping: second, in: pages, anchor: .timelineItem(.eventID("$2")))
        #expect(kept == second)
        #expect(pages.firstIndex { $0 == kept } == 3)
    }
    
    @Test
    func loadingPageGivesWayToTheMediaThatArrived() {
        let anchorID = MediaPreviewItemID.timelineItem(.eventID("$1"))
        let anchor = TimelineMediaPreviewPage.media(anchorID)
        let older = TimelineMediaPreviewPage.media(.timelineItem(.eventID("$0")))
        let newer = TimelineMediaPreviewPage.media(.timelineItem(.eventID("$2")))
        
        // While older media is still loading, the loading page stays.
        #expect(TimelineMediaPreviewDataSource.page(keeping: .loading(.backwards),
                                                    in: [.loading(.backwards), anchor],
                                                    anchor: anchorID) == .loading(.backwards))
        // Once it has arrived, the user lands on the media right before the one they came from.
        #expect(TimelineMediaPreviewDataSource.page(keeping: .loading(.backwards),
                                                    in: [.loading(.backwards), older, anchor],
                                                    anchor: anchorID) == older)
        // The same going forwards.
        #expect(TimelineMediaPreviewDataSource.page(keeping: .loading(.forwards),
                                                    in: [anchor, newer, .loading(.forwards)],
                                                    anchor: anchorID) == newer)
        // When the timeline turned out to have nothing more, back to the media they came from.
        #expect(TimelineMediaPreviewDataSource.page(keeping: .loading(.backwards),
                                                    in: [anchor, newer],
                                                    anchor: anchorID) == anchor)
        // Media that is gone, such as deleted, has nothing to stand in for it.
        #expect(TimelineMediaPreviewDataSource.page(keeping: older, in: [anchor, newer], anchor: anchorID) == nil)
    }
    
    @Test
    func neighbourPrefetchIndices() {
        // Two pages either way, nearest first…
        #expect(TimelineMediaPreviewDataSource.neighbourIndices(around: 5, count: 10) == [6, 4, 7, 3])
        // …only the ones that exist at the ends…
        #expect(TimelineMediaPreviewDataSource.neighbourIndices(around: 0, count: 10) == [1, 2])
        #expect(TimelineMediaPreviewDataSource.neighbourIndices(around: 9, count: 10) == [8, 7])
        #expect(TimelineMediaPreviewDataSource.neighbourIndices(around: 0, count: 1).isEmpty)
        // …and as far as asked.
        #expect(TimelineMediaPreviewDataSource.neighbourIndices(around: 5, count: 10, radius: 1) == [6, 4])
    }
    
    @Test
    func positionCountsTheLoadedMedia() async throws {
        // Given a data source showing the third of its media.
        let dataSource = try assertInitialDataSource()
        let count = initialMediaViewStates.count
        #expect(dataSource.position == .init(number: initialItemIndex + 1, count: count))
        
        // When older media loads in front of it.
        let deferred = deferFulfillment(dataSource.previewItemsPaginationPublisher) { _ in true }
        let olderMedia = newChunk().map { RoomTimelineItemViewState(item: $0, groupStyle: .single) }
        dataSource.updatePreviewItems(itemViewStates: olderMedia + initialMediaViewStates)
        try await deferred.fulfill()
        
        // Then the same media is shown, now further along the larger count.
        #expect(dataSource.currentMediaItemID == initialMediaItems[initialItemIndex].previewID)
        #expect(dataSource.position == .init(number: olderMedia.count + initialItemIndex + 1, count: olderMedia.count + count))
    }
    
    @Test
    func paginatesAheadOfTheEdge() {
        // Given a data source on its first media, whose timeline can load more in both directions.
        let dataSource = TimelineMediaPreviewDataSource(itemViewStates: initialMediaViewStates,
                                                        initialItem: initialMediaItems[0],
                                                        paginationState: .init(backward: .idle, forward: .idle))
        
        // Then it asks for older media before the user reaches a loading page.
        #expect(dataSource.paginationDirectionNeeded(within: 1) == .backwards)
        
        // When the user is in the middle, nothing is needed.
        dataSource.updateCurrentItem(.media(dataSource.previewItems[2]))
        #expect(dataSource.paginationDirectionNeeded(within: 1) == nil)
        
        // When the user is on the last media, newer media is asked for.
        dataSource.updateCurrentItem(.media(dataSource.previewItems[dataSource.previewItems.count - 1]))
        #expect(dataSource.paginationDirectionNeeded(within: 1) == .forwards)
        
        // When a pagination is already under way, nothing more is asked for.
        dataSource.paginationState = .init(backward: .idle, forward: .paginating)
        #expect(dataSource.paginationDirectionNeeded(within: 1) == nil)
        
        // When the user reaches the loading page at the start, older media is asked for.
        dataSource.updateCurrentItem(.loading(.paginatingBackwards))
        #expect(dataSource.paginationDirectionNeeded(within: 1) == .backwards)
    }
    
    @Test
    func updatedItems() async throws {
        // Given a data source built with the initial items.
        let dataSource = try assertInitialDataSource()
        
        // When one of the items changes but no pagination has occurred.
        let deferred = deferFailure(dataSource.previewItemsPaginationPublisher, timeout: .seconds(1)) { _ in true }
        dataSource.updatePreviewItems(itemViewStates: initialMediaViewStates)
        
        // Then no pagination should be detected and none of the data should have changed.
        try await deferred.fulfill()
        
        #expect(dataSource.currentMediaItemID == initialMediaItems[initialItemIndex].previewID, "The current item should not change.")
        #expect(dataSource.previewItems.count == initialMediaViewStates.count, "The number of items should not change.")
    }
    
    @Test
    func pagination() async throws {
        // Given a data source built with the initial items.
        let dataSource = try assertInitialDataSource()
        
        // When more items are loaded in a back pagination.
        var deferred = deferFulfillment(dataSource.previewItemsPaginationPublisher) { _ in true }
        let backPaginationChunk = newChunk().map { RoomTimelineItemViewState(item: $0, groupStyle: .single) }
        var newViewStates = backPaginationChunk + initialMediaViewStates
        dataSource.updatePreviewItems(itemViewStates: newViewStates)
        
        // Then the new items should be added but the current item should not change.
        try await deferred.fulfill()
        #expect(dataSource.previewItems.count == newViewStates.count, "The new items should be added.")
        #expect(dataSource.currentMediaItemID == initialMediaItems[initialItemIndex].previewID, "The current item should not change.")
        
        // When more items are loaded in a forward pagination or sync.
        deferred = deferFulfillment(dataSource.previewItemsPaginationPublisher) { _ in true }
        let forwardPaginationChunk = newChunk().map { RoomTimelineItemViewState(item: $0, groupStyle: .single) }
        newViewStates += forwardPaginationChunk
        dataSource.updatePreviewItems(itemViewStates: newViewStates)
        
        // Then the new items should be added but the current item should not change.
        try await deferred.fulfill()
        #expect(dataSource.previewItems.count == newViewStates.count, "The new items should be added.")
        #expect(dataSource.currentMediaItemID == initialMediaItems[initialItemIndex].previewID, "The current item should not change.")
    }
    
    @Test
    func emptyTimeline() async throws {
        // Given a data source built with no timeline items loaded.
        let initialItem = initialMediaItems[initialItemIndex]
        let dataSource = TimelineMediaPreviewDataSource(itemViewStates: [],
                                                        initialItem: initialItem,
                                                        paginationState: .initial)
        
        // Then the viewer should always show the initial item.
        #expect(dataSource.previewItems.count == 1, "The initial item should be in the preview items array.")
        #expect(dataSource.currentMediaItemID == initialItem.previewID, "The current item should be the initial item.")
        #expect(dataSource.position == .init(number: 1, count: 1))
        
        // When the timeline loads the initial items.
        let deferred = deferFulfillment(dataSource.previewItemsPaginationPublisher) { _ in true }
        let loadedItems = initialMediaItems.map { RoomTimelineItemViewState(item: $0, groupStyle: .single) }
        dataSource.updatePreviewItems(itemViewStates: loadedItems)
        try await deferred.fulfill()
        
        // Then the viewer should still show the initial item with the other items loaded around it.
        #expect(dataSource.previewItems.count == initialMediaViewStates.count, "The preview items should now be loaded.")
        #expect(dataSource.currentMediaItemID == initialItem.previewID, "The current item should not change.")
        #expect(dataSource.position == .init(number: initialItemIndex + 1, count: initialMediaViewStates.count))
    }
    
    @Test
    func timelineUpdateWithoutInitialItem() async throws {
        // Given a data source built with no timeline items loaded.
        let initialItem = initialMediaItems[initialItemIndex]
        let dataSource = TimelineMediaPreviewDataSource(itemViewStates: [],
                                                        initialItem: initialItem,
                                                        paginationState: .initial)
        #expect(dataSource.previewItems.count == 1, "The initial item should be in the preview items array.")
        
        // When the timeline loads more items but still doesn't include the initial item.
        let failure = deferFailure(dataSource.previewItemsPaginationPublisher, timeout: .seconds(1)) { _ in true }
        let loadedItems = newChunk().map { RoomTimelineItemViewState(item: $0, groupStyle: .single) }
        dataSource.updatePreviewItems(itemViewStates: loadedItems)
        try await failure.fulfill()
        
        // Then the viewer shouldn't update the available preview items.
        #expect(dataSource.previewItems.count == 1, "No new items should have been added to the array.")
        #expect(dataSource.currentMediaItemID == initialItem.previewID, "The current item not change.")
    }
    
    // MARK: Helpers
    
    private func makeGallery(items: [GalleryItem]) -> GalleryRoomTimelineItem {
        .init(id: .randomEvent,
              timestamp: .mock,
              isOutgoing: false,
              isEditable: false,
              canBeRepliedTo: true,
              sender: .init(id: "Bob"),
              content: .init(body: "Gallery", caption: nil, items: items),
              properties: .init())
    }
    
    func newChunk() -> [EventBasedMessageTimelineItemProtocol] {
        TimelineFixtures.mediaChunk
            .compactMap { $0 as? EventBasedMessageTimelineItemProtocol }
            .filter(\.supportsMediaCaption) // Voice messages can't be previewed (and don't support captions).
            .filter { !($0 is GalleryRoomTimelineItem) } // Galleries are previewed through their own data source.
    }
    
    @Test
    func sentLocalEchoKeepsItsPage() async throws {
        // Given a viewer opened on an upload in flight: a local echo with a transaction ID.
        let uniqueID = TimelineItemIdentifier.UniqueID(UUID().uuidString)
        func makeUpload(id: TimelineItemIdentifier.EventOrTransactionID) -> ImageRoomTimelineItem {
            ImageRoomTimelineItem(id: .event(uniqueID: uniqueID, eventOrTransactionID: id),
                                  timestamp: .mock,
                                  isOutgoing: true,
                                  isEditable: false,
                                  canBeRepliedTo: false,
                                  sender: .init(id: "Alice"),
                                  content: .init(filename: "upload.jpg", imageInfo: .mockImage, thumbnailInfo: nil, blurhash: nil))
        }
        let localEcho = makeUpload(id: .transactionID("t1"))
        var items = newChunk()
        items.append(localEcho)
        let dataSource = TimelineMediaPreviewDataSource(itemViewStates: items.map { RoomTimelineItemViewState(item: $0, groupStyle: .single) },
                                                        initialItem: localEcho,
                                                        paginationState: .initial)
        let page = try #require(dataSource.currentItem.mediaItem)
        #expect(page.id == .timelineItem(.transactionID("t1")))
        
        let pagesBefore = dataSource.pages
        
        // When the upload completes and the timeline swaps the echo's transaction ID for its event ID.
        items[items.count - 1] = makeUpload(id: .eventID("$e1"))
        let deferred = deferFulfillment(dataSource.previewItemsPaginationPublisher) { _ in true }
        dataSource.updatePreviewItems(itemViewStates: items.map { RoomTimelineItemViewState(item: $0, groupStyle: .single) })
        try await deferred.fulfill()
        
        // Then the pager is told, and the page it holds under the old ID is found under the new one, still showing
        // the same media (its file came from the local media cache).
        let oldID = MediaPreviewItemID.timelineItem(.transactionID("t1"))
        let newID = MediaPreviewItemID.timelineItem(.eventID("$e1"))
        #expect(pagesBefore.contains(.media(oldID)))
        #expect(dataSource.currentID(for: oldID) == newID)
        let kept = TimelineMediaPreviewDataSource.page(keeping: .media(dataSource.currentID(for: oldID)), in: dataSource.pages, anchor: newID)
        #expect(kept == .media(newID))
        #expect(dataSource.media(for: newID) === page)
        #expect(dataSource.currentItem.mediaItem === page)
        #expect(dataSource.previewItems.count == items.count)
    }
    
    @discardableResult
    private func assertInitialDataSource() throws -> TimelineMediaPreviewDataSource {
        // Given a data source built with the initial items.
        let dataSource = TimelineMediaPreviewDataSource(itemViewStates: initialMediaViewStates,
                                                        initialItem: initialMediaItems[initialItemIndex],
                                                        paginationState: .initial)
        
        // Then the data source should be showing the initial item.
        #expect(dataSource.currentMediaItemID == initialMediaItems[initialItemIndex].previewID, "The current item should be the initial item.")
        #expect(dataSource.currentIndex == initialItemIndex)
        #expect(dataSource.previewItems.count == initialMediaViewStates.count, "The initial count of preview items should be correct.")
        
        return dataSource
    }
}

private extension TimelineMediaPreviewDataSource {
    var currentMediaItemID: MediaPreviewItemID? {
        currentItem.mediaItem?.id
    }
}

private extension EventBasedMessageTimelineItemProtocol {
    /// Test helper that derives the same preview ID used by `TimelineMediaPreviewItem.Media` —
    /// avoids reaching into the private encoding from the tests.
    var previewID: MediaPreviewItemID {
        TimelineMediaPreviewItem.Media(timelineItem: self).id
    }
}
