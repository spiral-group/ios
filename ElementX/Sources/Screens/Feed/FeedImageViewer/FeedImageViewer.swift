//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). A feed image opened full size in
// QuickLook (`interactiveQuickLook`, as the profile screen's avatar). The
// timeline's media viewer needs a room timeline, which a post does not have.
//

import Foundation

enum FeedImageViewer {
    /// The full-size file of one of a post's images, or `nil` when it could not be loaded.
    static func previewItem(for media: FeedPostCardModel.Media, title: String?, mediaProvider: MediaProviderProtocol) async -> MediaPreviewItem? {
        guard let source = media.source else { return nil }
        switch await mediaProvider.loadFileFromSource(source, filename: nil) {
        case .success(let file):
            return MediaPreviewItem(file: file, title: title)
        case .failure(let error):
            MXLog.error("Failed to load a feed image: \(error)")
            return nil
        }
    }
}
