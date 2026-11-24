//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct GalleryRoomTimelineView: View {
    @Environment(\.timelineContext) private var context
    let timelineItem: GalleryRoomTimelineItem
    
    private var hasMediaCaption: Bool {
        timelineItem.content.caption?.isBlank == false
    }
    
    private var usesListLayout: Bool {
        timelineItem.usesListLayout
    }
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            // AGENT-PLATFORM (question 413): an album reaches the bubble's edges, and its caption keeps the inset, as a photo's does.
            VStack(alignment: .leading, spacing: usesListLayout ? 8 : 0) {
                if usesListLayout {
                    GalleryListView(items: timelineItem.content.items,
                                    mediaProvider: context?.mediaProvider,
                                    contentScannerService: context?.contentScannerService,
                                    onItemTap: tap)
                } else {
                    GalleryGridView(items: timelineItem.content.items,
                                    // AGENT-PLATFORM (1.0.3): under a caption the time sits below the grid, not in a tile.
                                    hasCaption: hasMediaCaption,
                                    mediaProvider: context?.mediaProvider,
                                    contentScannerService: context?.contentScannerService,
                                    onItemTap: tap)
                        // AGENT-PLATFORM (question 413): the album reads as one element, and each picture opens from its actions.
                        .accessibilityHidden(true)
                }
                
                if hasMediaCaption {
                    if usesListLayout {
                        GalleryDivider()
                    }
                    caption
                        .pictureCaptionInsets(isActive: !usesListLayout) // AGENT-PLATFORM (Brief 0083)
                        .accessibilityHidden(true) // Announced when entering the gallery, so not a stop of its own.
                }
            }
            .frame(width: usesListLayout ? GalleryListView.width : nil, alignment: .leading)
        }
    }
    
    @ViewBuilder
    private var caption: some View {
        if let attributedCaption = timelineItem.content.formattedCaption {
            FormattedBodyText(attributedString: attributedCaption,
                              trailingReservedSize: timelineItem.trailingReservedSize,
                              boostFontSize: timelineItem.shouldBoost)
        } else if let caption = timelineItem.content.caption {
            FormattedBodyText(text: caption,
                              trailingReservedSize: timelineItem.trailingReservedSize,
                              boostFontSize: timelineItem.shouldBoost)
        }
    }
    
    private func tap(index: Int) {
        context?.send(viewAction: .galleryItemTapped(.init(timelineItemID: timelineItem.id, mediaIndex: index)))
    }
}

extension GalleryRoomTimelineItem {
    /// List layout when any item is non-visual (file/audio); a grid reads badly for documents.
    var usesListLayout: Bool {
        content.items.contains { !$0.isImage && !$0.isVideo }
    }
}

// MARK: - Previews

struct GalleryRoomTimelineView_Previews: PreviewProvider, TestablePreview {
    static let viewModel = TimelineViewModel.mock
    
    // Fixed sources keyed by the mock scanner below. Safe is loadable (real thumbnail); others just need a distinct URL.
    nonisolated static let safeSource = ImageInfoProxy.mockImage.source
    // swiftlint:disable force_try
    nonisolated static let unsafeSource = try! MediaSourceProxy(url: .mockMXCUnsafe, mimeType: "image/jpeg")
    nonisolated static let scanningSource = try! MediaSourceProxy(url: .mockMXCScanning, mimeType: "image/jpeg")
    // swiftlint:enable force_try
    
    static let mixedScanViewModel = TimelineViewModel.mock(contentScannerService: ContentScannerServiceMock(.init { source in
        switch source.url {
        case .mockMXCUnsafe: false
        case .mockMXCScanning: nil
        default: true
        }
    }))
    
    static var previews: some View {
        makeView(makeItem(itemCount: 1), viewModel).previewDisplayName("1 image")
        makeView(makeItem(itemCount: 2), viewModel).previewDisplayName("2 images")
        makeView(makeItem(itemCount: 3), viewModel).previewDisplayName("3 images")
        makeView(makeItem(itemCount: 4), viewModel).previewDisplayName("4 images")
        makeView(makeItem(itemCount: 5), viewModel).previewDisplayName("5 images")
        makeView(makeItem(itemCount: 9, caption: "A trip to remember 🌅"), viewModel).previewDisplayName("6+ images with caption")
        // AGENT-PLATFORM (1.0.3): a narrow video tile keeps its chip inside, without the length when that doesn't fit.
        makeView(makeItem(itemCount: 9), viewModel)
            .dynamicTypeSize(.accessibility3)
            .previewDisplayName("6+ images at an accessibility size")
        // AGENT-PLATFORM (question 413): an own album, blue under its caption.
        makeView(makeItem(itemCount: 3, caption: "Waterfalls from the trip", isOutgoing: true), viewModel).previewDisplayName("Own album with caption")
        makeView(makeMixedScanItem(), mixedScanViewModel).previewDisplayName("Mixed content scan")
        makeView(makeFileListItem(caption: "Quarterly reports"), viewModel).previewDisplayName("File list")
        // AGENT-PLATFORM (Brief 0083): its rows draw on the own bubble's blue fill.
        makeView(makeFileListItem(caption: "Quarterly reports", isOutgoing: true), viewModel).previewDisplayName("Own file list")
        makeView(makeMixedScanFileListItem(), mixedScanViewModel).previewDisplayName("Mixed content scan (files)")
    }
    
    static func makeView(_ item: GalleryRoomTimelineItem, _ viewModel: TimelineViewModel) -> some View {
        GalleryRoomTimelineView(timelineItem: item)
            .padding(20)
            .environmentObject(viewModel.context)
            .environment(\.timelineContext, viewModel.context)
    }
    
    // AGENT-PLATFORM (question 413): landscape, portrait and square pictures, so the mosaic lays out by their shapes.
    private static let shapes: [(width: UInt64, height: UInt64)] = [(1920, 1280), (1080, 1440), (1200, 1200)]
    
    private static func makeItem(itemCount: Int, caption: String? = nil, isOutgoing: Bool = false) -> GalleryRoomTimelineItem {
        let items: [GalleryItem] = (0..<itemCount).map { index in
            let shape = shapes[index % shapes.count]
            return index.isMultiple(of: 3)
                ? .mockVideo(index: index, filename: "clip-\(index).mp4")
                : .mockImage(index: index, filename: "image-\(index).jpg", width: shape.width, height: shape.height)
        }
        
        return GalleryRoomTimelineItem(id: .randomEvent,
                                       timestamp: .mock,
                                       isOutgoing: isOutgoing,
                                       isEditable: false,
                                       canBeRepliedTo: true,
                                       sender: .init(id: "Bob"),
                                       content: .init(body: "Gallery (\(itemCount) items)",
                                                      caption: caption,
                                                      items: items),
                                       properties: .init())
    }
    
    private static func makeMixedScanItem() -> GalleryRoomTimelineItem {
        // >maxVisible items with the overflow tile (index 4) unsafe, to show "+N" over a failed scan.
        let sources = [safeSource, unsafeSource, scanningSource, safeSource, unsafeSource, safeSource, safeSource]
        let items: [GalleryItem] = sources.enumerated().map { index, source in
            .mockImage(index: index, filename: "image-\(index).jpg", source: source, thumbnailSource: source)
        }
        
        return GalleryRoomTimelineItem(id: .randomEvent,
                                       timestamp: .mock,
                                       isOutgoing: false,
                                       isEditable: false,
                                       canBeRepliedTo: true,
                                       sender: .init(id: "Bob"),
                                       content: .init(body: "Gallery (\(sources.count) items)",
                                                      caption: "Mixed scan states",
                                                      items: items),
                                       properties: .init())
    }
    
    private static func makeFileListItem(caption: String?, isOutgoing: Bool = false) -> GalleryRoomTimelineItem { // AGENT-PLATFORM (Brief 0083)
        let items: [GalleryItem] = [
            .mockImage(index: 0, filename: "photo.jpg"),
            .mockFile(index: 1, filename: "report.pdf"),
            .mockAudio(index: 2, filename: "meeting.m4a")
        ]
        
        return GalleryRoomTimelineItem(id: .randomEvent,
                                       timestamp: .mock,
                                       isOutgoing: isOutgoing, // AGENT-PLATFORM (Brief 0083)
                                       isEditable: false,
                                       canBeRepliedTo: true,
                                       sender: .init(id: "Bob"),
                                       content: .init(body: "Mixed gallery",
                                                      caption: caption,
                                                      items: items),
                                       properties: .init())
    }
    
    private static func makeMixedScanFileListItem() -> GalleryRoomTimelineItem {
        // Safe/unsafe/scanning rows via the mixed-scan sources.
        let items: [GalleryItem] = [
            .mockFile(index: 0, filename: "report.zip", source: safeSource, contentType: .zip),
            .mockFile(index: 1, filename: "contract.pdf", source: unsafeSource),
            .mockAudio(index: 2, filename: "meeting.m4a", source: scanningSource)
        ]
        
        return GalleryRoomTimelineItem(id: .randomEvent,
                                       timestamp: .mock,
                                       isOutgoing: false,
                                       isEditable: false,
                                       canBeRepliedTo: true,
                                       sender: .init(id: "Bob"),
                                       content: .init(body: "Files",
                                                      caption: "Mixed scan states",
                                                      items: items),
                                       properties: .init())
    }
}
