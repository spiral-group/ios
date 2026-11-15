//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

// AGENT-PLATFORM (Brief 0083, question 413): the pages of Spiral's own viewer, which replaced QuickLook. Without
// QuickLook's fixed item count there is no padding: a page asks for its neighbours, and a loading page stands
// where more of the timeline can still be fetched.
/// The media a viewer pages through, staying in step with the timeline as it paginates.
class TimelineMediaPreviewDataSource {
    /// All of the items in the timeline that can be previewed, oldest first.
    private(set) var previewItems: [TimelineMediaPreviewItem.Media]
    /// Sends when items were added at either end, an item's ID changed, or the timeline reached an end, so the pager
    /// can rebuild its pages.
    let previewItemsPaginationPublisher = PassthroughSubject<Void, Never>()
    
    /// The media item that is currently being previewed.
    private(set) var currentItem: TimelineMediaPreviewItem
    
    /// Reaching the end of the timeline removes the loading page there, so a change
    /// needs to be published too, not only the arrival of new items.
    var paginationState: TimelinePaginationState {
        didSet {
            guard paginationState != oldValue else { return }
            previewItemsPaginationPublisher.send()
        }
    }
    
    /// The old IDs of media whose ID changed, such as a local echo once sent, to their new ones.
    private var renamedIDs: [MediaPreviewItemID: MediaPreviewItemID] = [:]
    /// The gallery attachments to include, so that a gallery only contributes the media being browsed.
    private let allowedGalleryItemTypes: [TimelineAllowedGalleryItemType]?
    
    /// Builds a data source spanning every previewable attachment in the timeline, paginating
    /// as the user swipes past the loaded range. Used when tapping a standalone media message.
    init(itemViewStates: [RoomTimelineItemViewState],
         initialItem: EventBasedMessageTimelineItemProtocol,
         paginationState: TimelinePaginationState,
         allowedGalleryItemTypes: [TimelineAllowedGalleryItemType]? = nil) {
        self.allowedGalleryItemTypes = allowedGalleryItemTypes
        
        previewItems = itemViewStates.flatMap { $0.previewableMedia(allowedGalleryItemTypes: allowedGalleryItemTypes) }
        
        let initialPreviewID = TimelineMediaPreviewItem.Media(timelineItem: initialItem).id
        if let initialItemArrayIndex = previewItems.firstIndex(where: { $0.id == initialPreviewID }) {
            currentItem = .media(previewItems[initialItemArrayIndex])
        } else {
            // The timeline hasn't loaded the initial item yet, so replace the whatever was loaded with
            // the item the user wants to preview.
            previewItems = [.init(timelineItem: initialItem)]
            currentItem = .media(previewItems[0])
        }
        
        self.paginationState = paginationState
    }
    
    /// Builds a data source scoped to a single gallery's previewable attachments.
    /// Used when the user taps a tile inside a gallery message — paging is local to that
    /// gallery and there's no timeline pagination to drive.
    init(galleryItem: GalleryRoomTimelineItem,
         initialIndex: Int) {
        allowedGalleryItemTypes = nil // All of the gallery's attachments are shown.
        
        let media = galleryItem.content.items.map { item in
            TimelineMediaPreviewItem.Media(galleryParent: galleryItem, item: item)
        }
        
        if media.indices.contains(initialIndex) {
            // We set the entire gallery here up front.
            previewItems = media
            currentItem = .media(media[initialIndex])
        } else {
            // Fall back to a synthetic placeholder for empty galleries — shouldn't happen in practice.
            previewItems = [.init(timelineItem: galleryItem)]
            currentItem = .media(previewItems[0])
        }
        
        // And we disable any use of the timeline by configuring the data source as though everything has paginated.
        paginationState = .init(backward: .endReached, forward: .endReached)
    }
    
    func updateCurrentItem(_ item: TimelineMediaPreviewItem) {
        currentItem = item
    }
    
    func updatePreviewItems(itemViewStates: [RoomTimelineItemViewState]) {
        var hasRenamedItems = false
        let newItems: [TimelineMediaPreviewItem.Media] = itemViewStates
            .flatMap { $0.previewableMedia(allowedGalleryItemTypes: allowedGalleryItemTypes) }
            .map { newItem in
                // If an item already exists use that instead to preserve the file handle, download error etc.
                if let oldItem = previewItems.first(where: { $0.id == newItem.id || $0.isLocalEcho(of: newItem) }) {
                    oldItem.content = newItem.content
                    if oldItem.id != newItem.id {
                        // AGENT-PLATFORM (Brief 0083, question 413): a sent local echo's transaction ID → event ID.
                        // The pager holds pages by ID, so it's told, and can look the new ID up.
                        renamedIDs[oldItem.id] = newItem.id
                        hasRenamedItems = true
                        oldItem.id = newItem.id
                    }
                    return oldItem
                }
                
                return newItem
            }
        
        // AGENT-PLATFORM (end-stage review, 2026-11-14): media deleted elsewhere leaves the viewer. Its row is still in
        // the timeline, now without media; anything else missing is the timeline still loading, which is waited out.
        let newIDs = Set(newItems.map(\.id))
        let rowIDs = Set(itemViewStates.map(\.identifier.uniqueID))
        let remainingItems = previewItems.filter { newIDs.contains($0.id) || !rowIDs.contains($0.timelineItem.id.uniqueID) }
        let hasDeletedItems = remainingItems.count < previewItems.count
        
        guard !remainingItems.isEmpty, let range = newItems.map(\.id).firstRange(of: remainingItems.map(\.id)) else {
            // When the timeline is loading items from the store and the initial item is the only
            // preview in the array, we don't want to wipe it out, so if the existing items aren't
            // found within the new items then let's ignore the update for now. This comes with a
            // tradeoff that when a media gets redacted, no more previews will be added to the viewer.
            MXLog.info("Ignoring update: unable to find existing preview items range.")
            if hasRenamedItems {
                previewItemsPaginationPublisher.send()
            }
            return
        }
        
        let hasPaginated = range.lowerBound > 0 || range.upperBound < newItems.endIndex
        previewItems = newItems
        
        if hasPaginated || hasRenamedItems || hasDeletedItems {
            previewItemsPaginationPublisher.send()
        }
    }
    
    /// The ID media goes by now: a sent local echo's transaction ID gives way to its event ID.
    func currentID(for id: MediaPreviewItemID) -> MediaPreviewItemID {
        var id = id
        while let renamed = renamedIDs[id] {
            id = renamed
        }
        return id
    }
    
    // MARK: - Pages
    
    /// The index of the current media in ``previewItems``, or `nil` while a loading page is shown.
    var currentIndex: Int? {
        guard let mediaItem = currentItem.mediaItem else { return nil }
        return previewItems.firstIndex { $0 === mediaItem }
    }
    
    /// Where the current media sits among the loaded ones, for the viewer's «2 of 14». The count is of the
    /// media loaded so far, so it grows as the user pages towards older or newer media.
    var position: TimelineMediaPreviewPosition? {
        guard let currentIndex else { return nil }
        return .init(number: currentIndex + 1, count: previewItems.count)
    }
    
    /// The page for the current item.
    var currentPage: TimelineMediaPreviewPage {
        switch currentItem {
        case .media(let media): .media(media.id)
        case .contentScan(let scan): .media(scan.media.id)
        case .loading(.paginatingBackwards): .loading(.backwards)
        case .loading(.paginatingForwards): .loading(.forwards)
        }
    }
    
    func media(for id: MediaPreviewItemID) -> TimelineMediaPreviewItem.Media? {
        previewItems.first { $0.id == id }
    }
    
    /// Every page in order: a loading page where older media can still be fetched, the loaded media oldest first,
    /// and a loading page where newer media can still be fetched.
    var pages: [TimelineMediaPreviewPage] {
        var pages = previewItems.map { TimelineMediaPreviewPage.media($0.id) }
        if paginationState.backward != .endReached {
            pages.insert(.loading(.backwards), at: 0)
        }
        if paginationState.forward != .endReached {
            pages.append(.loading(.forwards))
        }
        return pages
    }
    
    /// The page to keep on screen once the pages have changed under it, so that new media never moves the one being
    /// looked at. A loading page gives way to the media that arrived next to `anchor`, the media the user came from,
    /// or back to `anchor` itself when that end of the timeline turned out to have nothing more. `nil` when the
    /// page is gone and there's nothing to stand in for it, such as deleted media.
    static func page(keeping page: TimelineMediaPreviewPage,
                     in pages: [TimelineMediaPreviewPage],
                     anchor: MediaPreviewItemID?) -> TimelineMediaPreviewPage? {
        guard case let .loading(direction) = page else {
            return pages.contains(page) ? page : nil
        }
        guard let anchor, let anchorIndex = pages.firstIndex(of: .media(anchor)) else {
            return pages.contains(page) ? page : nil
        }
        let nextIndex = direction == .backwards ? anchorIndex - 1 : anchorIndex + 1
        guard pages.indices.contains(nextIndex) else {
            return .media(anchor) // That end has been reached.
        }
        return pages[nextIndex]
    }
    
    /// The indices of the pages to load ahead of a swipe from `index`, nearest first.
    static func neighbourIndices(around index: Int, count: Int, radius: Int = 2) -> [Int] {
        guard radius > 0 else { return [] }
        return (1...radius)
            .flatMap { [index + $0, index - $0] }
            .filter { (0..<count).contains($0) }
    }
    
    /// The direction to fetch more media in, when the current page is a loading page or close to the
    /// edge of what has been loaded, so that the next swipe rarely lands on a loading page.
    func paginationDirectionNeeded(within distance: Int = 3) -> PaginationDirection? {
        switch currentItem {
        case .loading(.paginatingBackwards):
            return paginationState.backward == .idle ? .backwards : nil
        case .loading(.paginatingForwards):
            return paginationState.forward == .idle ? .forwards : nil
        case .media, .contentScan:
            guard let currentIndex else { return nil }
            if currentIndex < distance, paginationState.backward == .idle {
                return .backwards
            }
            if previewItems.count - 1 - currentIndex < distance, paginationState.forward == .idle {
                return .forwards
            }
            return nil
        }
    }
}

/// A page of the viewer: one media, or the loading page at an end of the loaded media.
nonisolated enum TimelineMediaPreviewPage: Hashable {
    case media(MediaPreviewItemID)
    case loading(PaginationDirection)
}

/// The current media's place among the loaded ones, counted from 1.
struct TimelineMediaPreviewPosition: Equatable {
    let number: Int
    let count: Int
}

// MARK: - TimelineMediaPreviewItem

enum TimelineMediaPreviewItem: Equatable {
    case media(Media)
    case contentScan(Scan)
    case loading(Loading)
    
    /// The media item this preview is for, regardless of its content scanning state.
    var mediaItem: Media? {
        switch self {
        case .media(let mediaItem): mediaItem
        case .contentScan(let scan): scan.media
        case .loading: nil
        }
    }
    
    /// A media item that is being processed by the content scanner, or that failed a scan
    /// and therefore must not be downloaded or previewed.
    struct Scan: Equatable {
        enum State: Equatable {
            case scanning
            case failure(ContentScanningFailure)
        }
        
        let media: Media
        let state: State
    }
    
    /// Wraps a media file and its details for the viewer.
    @Observable final class Media: Identifiable, Equatable {
        /// A standalone timeline message, or a single gallery attachment with its parent event.
        fileprivate enum Content {
            case timelineItem(EventBasedMessageTimelineItemProtocol)
            case galleryItem(parent: EventBasedMessageTimelineItemProtocol, item: GalleryItem)
        }
        
        fileprivate var content: Content
        
        /// The parent event, so menu actions (redact, reply, …) target the gallery as a whole.
        var timelineItem: EventBasedMessageTimelineItemProtocol {
            switch content {
            case .timelineItem(let timelineItem): timelineItem
            case .galleryItem(let parent, _): parent
            }
        }
        
        var fileHandle: MediaFileHandleProxy?
        
        /// The downloaded file, once ``fileHandle`` is loaded.
        var fileURL: URL? {
            fileHandle?.url
        }
        
        var downloadError: Error?
        
        /// A stable identifier that's unique per preview item, even for gallery attachments that would
        /// otherwise share their parent event's ID. Not stable for local echoes however, those will
        /// transition from transaction ID to event ID once sent.
        fileprivate(set) var id: MediaPreviewItemID
        
        /// Whether this is the local echo that `sentItem` is the remote echo of. Sending swaps the
        /// transaction ID for an event ID but the unique ID remains stable.
        fileprivate func isLocalEcho(of sentItem: Media) -> Bool {
            guard timelineItem.id.transactionID != nil, sentItem.timelineItem.id.eventID != nil,
                  timelineItem.id.uniqueID == sentItem.timelineItem.id.uniqueID else { return false }
            switch (content, sentItem.content) {
            case (.timelineItem, .timelineItem): return true
            case (.galleryItem(_, let item), .galleryItem(_, let sentGalleryItem)): return item.id.mediaIndex == sentGalleryItem.id.mediaIndex
            default: return false
            }
        }
        
        init(timelineItem: EventBasedMessageTimelineItemProtocol) {
            content = .timelineItem(timelineItem)
            id = MediaPreviewItemID(timelineItem: timelineItem)
        }
        
        init?(roomTimelineItemViewState: RoomTimelineItemViewState) {
            let timelineItem: EventBasedMessageTimelineItemProtocol
            switch roomTimelineItemViewState.type {
            case .audio(let audioRoomTimelineItem):
                timelineItem = audioRoomTimelineItem
            case .file(let fileRoomTimelineItem):
                timelineItem = fileRoomTimelineItem
            case .image(let imageRoomTimelineItem):
                timelineItem = imageRoomTimelineItem
            case .video(let videoRoomTimelineItem):
                timelineItem = videoRoomTimelineItem
            default:
                return nil
            }
            content = .timelineItem(timelineItem)
            id = MediaPreviewItemID(timelineItem: timelineItem)
        }
        
        /// Wraps a single attachment of a gallery message. `.other` items have no media source,
        /// so the viewer shows them as a file that can't be opened.
        init(galleryParent: GalleryRoomTimelineItem, item: GalleryItem) {
            content = .galleryItem(parent: galleryParent, item: item)
            id = .galleryItem(item.id)
        }
        
        static func == (lhs: Media, rhs: Media) -> Bool {
            lhs === rhs
        }
        
        // MARK: Event details
        
        var sender: TimelineItemSender {
            timelineItem.sender
        }
        
        var timestamp: Date {
            timelineItem.timestamp
        }
        
        // MARK: Media details
        
        /// The kind of media, used to decide how it should be shown and saved.
        enum Kind { case image, video, audio, file }
        
        var kind: Kind {
            switch content {
            case .galleryItem(_, let item):
                switch item {
                case .image: .image
                case .video: .video
                case .audio: .audio
                case .file, .other: .file
                }
            case .timelineItem(let timelineItem):
                switch timelineItem {
                case is ImageRoomTimelineItem: .image
                case is VideoRoomTimelineItem: .video
                case is AudioRoomTimelineItem: .audio
                default: .file
                }
            }
        }
        
        var mediaSource: MediaSourceProxy? {
            switch content {
            case .galleryItem(_, let item):
                item.mediaSource
            case .timelineItem(let timelineItem):
                switch timelineItem {
                case let audioItem as AudioRoomTimelineItem: audioItem.content.source
                case let fileItem as FileRoomTimelineItem: fileItem.content.source
                case let imageItem as ImageRoomTimelineItem: imageItem.content.imageInfo.source
                case let videoItem as VideoRoomTimelineItem: videoItem.content.videoInfo.source
                default: nil
                }
            }
        }
        
        var thumbnailMediaSource: MediaSourceProxy? {
            switch content {
            case .galleryItem(_, let item):
                item.thumbnailSource
            case .timelineItem(let timelineItem):
                switch timelineItem {
                case let fileItem as FileRoomTimelineItem: fileItem.content.thumbnailSource
                case let imageItem as ImageRoomTimelineItem: imageItem.content.thumbnailInfo?.source
                case let videoItem as VideoRoomTimelineItem: videoItem.content.thumbnailInfo?.source
                default: nil
                }
            }
        }
        
        var filename: String? {
            switch content {
            case .galleryItem(_, let item):
                item.filename
            case .timelineItem(let timelineItem):
                switch timelineItem {
                case let audioItem as AudioRoomTimelineItem: audioItem.content.filename
                case let fileItem as FileRoomTimelineItem: fileItem.content.filename
                case let imageItem as ImageRoomTimelineItem: imageItem.content.filename
                case let videoItem as VideoRoomTimelineItem: videoItem.content.filename
                default: nil
                }
            }
        }
        
        var fileSize: UInt? {
            fileURL.flatMap { try? FileManager.default.sizeForItem(at: $0) } ?? expectedFileSize
        }
        
        private var expectedFileSize: UInt? {
            switch content {
            case .galleryItem(_, let item):
                item.fileSize
            case .timelineItem(let timelineItem):
                switch timelineItem {
                case let audioItem as AudioRoomTimelineItem: audioItem.content.fileSize
                case let fileItem as FileRoomTimelineItem: fileItem.content.fileSize
                case let imageItem as ImageRoomTimelineItem: imageItem.content.imageInfo.fileSize
                case let videoItem as VideoRoomTimelineItem: videoItem.content.videoInfo.fileSize
                default: nil
                }
            }
        }
        
        var hasCaption: Bool {
            // No need to special-case gallery items here, captions live on the gallery event itself
            timelineItem.hasMediaCaption
        }
        
        var caption: String? {
            timelineItem.mediaCaption
        }
        
        var formattedCaption: AttributedString? {
            timelineItem.formattedMediaCaption
        }
        
        var contentType: String? {
            switch content {
            case .galleryItem(_, let item):
                item.contentType?.localizedDescription
            case .timelineItem(let timelineItem):
                switch timelineItem {
                case let audioItem as AudioRoomTimelineItem: audioItem.content.contentType?.localizedDescription
                case let fileItem as FileRoomTimelineItem: fileItem.content.contentType?.localizedDescription
                case let imageItem as ImageRoomTimelineItem: imageItem.content.contentType?.localizedDescription
                case let videoItem as VideoRoomTimelineItem: videoItem.content.contentType?.localizedDescription
                default: nil
                }
            }
        }
        
        /// The media's width over its height when the event says, so a placeholder takes the final size.
        var aspectRatio: CGFloat? {
            switch content {
            case .galleryItem(_, .image(_, let content)):
                content.imageInfo.aspectRatio
            case .galleryItem(_, .video(_, let content)):
                content.videoInfo.aspectRatio
            case .timelineItem(let timelineItem):
                switch timelineItem {
                case let imageItem as ImageRoomTimelineItem: imageItem.content.imageInfo.aspectRatio
                case let videoItem as VideoRoomTimelineItem: videoItem.content.videoInfo.aspectRatio
                default: nil
                }
            default:
                nil
            }
        }
        
        /// What the chat's bubble drew for this media, with the same source and size it asked for, so the viewer can
        /// show it straight away, usually from memory, while the file loads.
        var bubbleImage: (source: MediaSourceProxy, size: CGSize?)? {
            switch content {
            case .galleryItem(_, let item):
                let source = item.isVideo ? item.thumbnailSource : item.thumbnailSource ?? item.mediaSource
                return source.map { ($0, item.size) }
            case .timelineItem(let timelineItem):
                switch timelineItem {
                case let imageItem as ImageRoomTimelineItem:
                    if imageItem.content.contentType == .gif {
                        return (imageItem.content.imageInfo.source, imageItem.content.imageInfo.size)
                    }
                    let info = imageItem.content.thumbnailInfo ?? imageItem.content.imageInfo
                    return (info.source, info.size)
                case let videoItem as VideoRoomTimelineItem:
                    return videoItem.content.thumbnailInfo.map { ($0.source, $0.size) }
                default:
                    return nil
                }
            }
        }
        
        var blurhash: String? {
            switch content {
            case .galleryItem(_, let item):
                item.blurhash
            case .timelineItem(let timelineItem):
                switch timelineItem {
                case let imageItem as ImageRoomTimelineItem: imageItem.content.blurhash
                case let videoItem as VideoRoomTimelineItem: videoItem.content.blurhash
                default: nil
                }
            }
        }
    }
    
    /// The loading page at an end of the loaded media, while more is fetched.
    enum Loading: Hashable {
        case paginatingBackwards
        case paginatingForwards
    }
}

private extension RoomTimelineItemViewState {
    /// The media of this item that can be previewed, flattening a gallery message into its individual
    /// attachments so that they can be browsed alongside the timeline's other media.
    /// - Parameter allowedGalleryItemTypes: Restricts a gallery's attachments to the media being
    ///   browsed, as the SDK can only filter the gallery event as a whole.
    /// AGENT-PLATFORM (end-stage review, 2026-11-14): the rows a viewer can show media of, which is all a change to the
    /// timeline needs to be compared by: a reaction, edit or send on one of them changes its type.
    var isPreviewableMediaRow: Bool {
        switch type {
        case .audio, .file, .image, .video, .gallery: true
        default: false
        }
    }
    
    func previewableMedia(allowedGalleryItemTypes: [TimelineAllowedGalleryItemType]?) -> [TimelineMediaPreviewItem.Media] {
        guard case .gallery(let galleryItem) = type else {
            return [TimelineMediaPreviewItem.Media(roomTimelineItemViewState: self)].compactMap { $0 }
        }
        
        return galleryItem.content.items(matching: allowedGalleryItemTypes).map {
            TimelineMediaPreviewItem.Media(galleryParent: galleryItem, item: $0.item)
        }
    }
}

extension [RoomTimelineItemViewState] {
    /// AGENT-PLATFORM (end-stage review, 2026-11-14): the media rows' content, in order, for telling whether a new build
    /// of the timeline's rows changed anything a viewer shows.
    var previewableMediaTypes: [RoomTimelineItemType] {
        filter(\.isPreviewableMediaRow).map(\.type)
    }
}
