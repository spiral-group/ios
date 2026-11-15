//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// AGENT-PLATFORM (question 413): an album's pictures as a mosaic by their shapes, the width of a photo in the timeline.
/// The bubble rounds its corners, and a 2 pt gap parts the tiles.
struct GalleryGridView: View {
    let items: [GalleryItem]
    let mediaProvider: MediaProviderProtocol?
    let contentScannerService: ContentScannerServiceProtocol?
    let onItemTap: (Int) -> Void
    
    private var visibleCount: Int {
        min(items.count, GalleryMosaic.maxVisibleTiles)
    }
    
    var body: some View {
        GalleryMosaicLayout(aspectRatios: items.prefix(visibleCount).map(\.aspectRatio)) {
            ForEach(0..<visibleCount, id: \.self) { index in
                tile(at: index)
            }
        }
    }
    
    private func tile(at index: Int) -> some View {
        let isLastVisible = index == visibleCount - 1
        let overflowCount = GalleryMosaic.overflowCount(itemCount: items.count)
        return GalleryItemTileView(item: items[index],
                                   position: index + 1,
                                   mediaProvider: mediaProvider,
                                   contentScannerService: contentScannerService,
                                   overflowCount: overflowCount > 0 && isLastVisible ? overflowCount : 0) {
            onItemTap(index)
        }
        // A scanning or unsafe tile fills its place in the mosaic too.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
