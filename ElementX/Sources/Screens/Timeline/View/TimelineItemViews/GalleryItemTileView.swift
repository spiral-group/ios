//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct GalleryItemTileView: View {
    let item: GalleryItem
    /// The item's position within the gallery, announced instead of its filename.
    let position: Int
    let mediaProvider: MediaProviderProtocol?
    let contentScannerService: ContentScannerServiceProtocol?
    let overflowCount: Int
    /// AGENT-PLATFORM (1.0.3): whether the time's chip sits in this tile's corner, which an album without a caption puts there.
    let sharesCornerWithTime: Bool
    let onTap: () -> Void
    
    private var accessibilityLabel: String {
        if overflowCount > 0 {
            L10n.a11yGalleryMoreMedia(overflowCount)
        } else if item.isVideo {
            L10n.a11yGalleryVideo(position)
        } else if item.isImage {
            L10n.a11yGalleryImage(position)
        } else {
            L10n.a11yGalleryAttachment(position)
        }
    }
    
    var body: some View {
        // Overflow above the scanner: shows on any scan state, survives content updates.
        ZStack {
            // containerShowsFailure: false keeps an unsafe tile local, not the whole bubble.
            ContentScanningView(contentScannerService: contentScannerService,
                                mediaSource: item.mediaSource,
                                thumbnailSource: item.thumbnailSource,
                                containerShowsFailure: false) {
                // Clear base so the image fills/clips to the grid's tile size, not its own.
                Color.clear
                    .overlay { content }
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        if item.isVideo {
                            // AGENT-PLATFORM (1.0.3): at accessibility sizes the length leaves a narrow tile, so the
                            // chip keeps only its glyph there, and a tile never shows a chip past its edge.
                            ViewThatFits(in: .horizontal) {
                                MediaVideoBadge(duration: item.duration)
                                MediaVideoBadge(duration: nil)
                            }
                        }
                    }
                    .clipped()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel)
            } scanningContent: {
                ScanningMediaEventsTimelineView()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.a11yGalleryScanning(position))
            } unsafeContent: { failure in
                UnsafeMediaEventsTimelineView(failure: failure)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.a11yGalleryFailedScan(position))
            }
            
            if overflowCount > 0 {
                overflowOverlay
            }
        }
        // Tappable in every scan state, so that an unsafe item can't hide the rest of the gallery.
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        // One element per tile, labelled by whichever state is on show.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
    
    @ViewBuilder
    private var content: some View {
        if let source = item.thumbnailSource ?? item.mediaSource {
            LoadableImage(mediaSource: source,
                          mediaType: .timelineItem(uniqueID: item.id.timelineItemID.uniqueID),
                          blurhash: item.blurhash,
                          size: item.size,
                          mediaProvider: mediaProvider) { imageView in
                imageView
                    .scaledToFill()
            } placeholder: {
                placeholder
            }
        } else {
            iconFallback
        }
    }
    
    private var placeholder: some View {
        Color.compound.bgSubtleSecondary.opacity(0.9)
    }
    
    private var iconFallback: some View {
        ZStack {
            Color.compound.bgSubtleSecondary
            CompoundIcon(item.isAudio ? \.audio : \.attachment)
                .foregroundStyle(.compound.iconPrimary)
        }
    }
    
    // AGENT-PLATFORM (question 413): the last tile dims its picture under the count, as Telegram does. A photo is the
    // same in either appearance, so the dimming and the count are too.
    private var overflowOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
            Text("+\(overflowCount)")
                .font(.compound.headingLGBold)
                .foregroundStyle(.white)
                // AGENT-PLATFORM (1.0.3): above the time's chip, which sits in this tile's corner when there's no caption; centred otherwise.
                .padding(.bottom, sharesCornerWithTime ? 20 : 0)
        }
        .allowsHitTesting(false) // Let the tap fall through to the tile below.
        .accessibilityHidden(true) // The count is already announced by the tile's label.
    }
}
