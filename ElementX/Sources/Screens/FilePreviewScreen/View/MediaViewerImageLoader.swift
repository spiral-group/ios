//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 413): photos decoded off the main thread for Spiral's own viewer, at the
// screen's size for paging and at full size once zoomed, so a swipe never waits on a decode.
//

import ImageIO
import SwiftUI

@MainActor
final class MediaViewerImageLoader {
    /// How far a photo is decoded: enough for the screen, or every pixel for zooming in.
    nonisolated enum Resolution: Hashable {
        case screen
        case full
    }

    private struct Key: Hashable {
        let url: URL
        let resolution: Resolution
    }

    private var cache: [Key: UIImage] = [:]
    private var decodes: [Key: Task<UIImage?, Never>] = [:]
    /// The longest side, in pixels, of a photo decoded for the screen.
    var screenPixels: CGFloat = 2048

    func cachedImage(for url: URL, resolution: Resolution) -> UIImage? {
        cache[Key(url: url, resolution: resolution)]
    }

    /// The best image decoded so far, full size first.
    func bestCachedImage(for url: URL) -> UIImage? {
        cachedImage(for: url, resolution: .full) ?? cachedImage(for: url, resolution: .screen)
    }

    /// Decodes the photo on a background thread, once, however many pages ask.
    func image(for url: URL, resolution: Resolution) async -> UIImage? {
        let key = Key(url: url, resolution: resolution)
        if let image = cache[key] {
            return image
        }
        let decode = decodes[key] ?? Task.detached(priority: .userInitiated) { [screenPixels] in
            Self.decode(url: url, maxPixels: resolution == .screen ? screenPixels : nil)
        }
        decodes[key] = decode
        let image = await decode.value
        decodes[key] = nil
        cache[key] = image
        return image
    }

    /// Forgets the photos far from the page on screen, keeping the ones a swipe can reach.
    func keepOnly(_ urls: Set<URL>) {
        cache = cache.filter { urls.contains($0.key.url) }
    }

    // MARK: Decoding

    /// Whether the file holds more than one frame, an animated GIF, which is left to Kingfisher to play.
    nonisolated static func isAnimated(url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    /// The photo, upright and decoded, no larger than `maxPixels` on its longest side (`nil` for every pixel).
    nonisolated static func decode(url: URL, maxPixels: CGFloat?) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? CGFloat ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? CGFloat ?? 0
        let longestSide = max(width, height)
        let limit = min(maxPixels ?? longestSide, longestSide)

        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceShouldCacheImmediately: true,
                                        kCGImageSourceThumbnailMaxPixelSize: max(1, limit)]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
