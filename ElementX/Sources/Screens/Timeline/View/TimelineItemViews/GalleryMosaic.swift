//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: an album's mosaic layout (question 413), Spiral's own code.
//

import SwiftUI

/// AGENT-PLATFORM (question 413): an album's tiles, laid out in rows by their pictures' shapes, as Telegram does.
///
/// Every way of splitting the tiles into rows of one to three is scored, and the best one wins. A row is as tall as its
/// pictures need to fill the width without cropping, and the score prefers an album about as tall as it is wide, a
/// row that needs no cropping, no more than two rows, and no row with more tiles than the row below it.
nonisolated struct GalleryMosaic: Equatable {
    /// The most tiles an album shows. The last one says how many more there are.
    static let maxVisibleTiles = 5
    /// The gap between two tiles.
    static let spacing: CGFloat = 2
    
    /// The number the last tile shows over its picture when an album has more items than tiles: that item and the
    /// ones not shown. Zero when every item has a tile.
    static func overflowCount(itemCount: Int) -> Int {
        itemCount > maxVisibleTiles ? itemCount - maxVisibleTiles + 1 : 0
    }

    /// Each visible tile's frame, in order, in the album's own space.
    let frames: [CGRect]
    /// The number of tiles in each row, top to bottom.
    let rowCounts: [Int]
    /// The album's size.
    let size: CGSize

    /// - Parameters:
    ///   - aspectRatios: Each item's width over its height, or `nil` when it isn't known. Items past
    ///     ``maxVisibleTiles`` are left out.
    ///   - width: The album's width.
    init(aspectRatios: [CGFloat?], width: CGFloat, spacing: CGFloat = Self.spacing) {
        let ratios = aspectRatios.prefix(Self.maxVisibleTiles).map(Self.clampedRatio)
        guard !ratios.isEmpty, width > 0 else {
            frames = []
            rowCounts = []
            size = .zero
            return
        }

        let candidates = Self.rowSplits(tileCount: ratios.count).map { Candidate(rowCounts: $0, ratios: ratios, spacing: spacing / width) }
        // `min(by:)` keeps the first of equal scores, so the order of the splits settles a tie.
        guard let best = candidates.min(by: { $0.cost < $1.cost }) else {
            frames = []
            rowCounts = []
            size = .zero
            return
        }

        rowCounts = best.rowCounts
        frames = best.frames(ratios: ratios, width: width, spacing: spacing)
        size = CGSize(width: width, height: (frames.map(\.maxY).max() ?? 0).rounded(.up))
    }

    // MARK: - Private

    /// A picture's shape is kept between a 3:4 portrait and a 7:4 landscape, so that no tile in a row of three is a sliver.
    private static let ratioRange: ClosedRange<CGFloat> = 0.75...1.75

    private static func clampedRatio(_ ratio: CGFloat?) -> CGFloat {
        guard let ratio, ratio.isFinite, ratio > 0 else { return 1 }
        return min(max(ratio, ratioRange.lowerBound), ratioRange.upperBound)
    }

    /// Every split of the tiles into one to three rows of one to three tiles, fewer rows first.
    private static func rowSplits(tileCount: Int) -> [[Int]] {
        func splits(_ remaining: Int, rows: Int) -> [[Int]] {
            guard remaining > 0 else { return [[]] }
            guard rows > 0 else { return [] }
            return (1...min(3, remaining)).flatMap { first in
                splits(remaining - first, rows: rows - 1).map { [first] + $0 }
            }
        }

        return (1...3).flatMap { rows in splits(tileCount, rows: rows).filter { $0.count == rows } }
    }

    /// One way of splitting the tiles into rows, measured with the album's width as 1.
    private struct Candidate {
        let rowCounts: [Int]
        /// Each row's height, cropping its pictures where the row would be too tall or too short.
        let rowHeights: [CGFloat]
        let cost: CGFloat

        /// The album's height it aims for: as tall as it is wide.
        private static let targetHeight: CGFloat = 1
        /// What a third row costs, so that five landscape pictures go as two rows rather than three.
        private static let extraRowCost: CGFloat = 0.15
        /// What a row with more tiles than the row below it costs: the big pictures go on top.
        private static let topHeavyCost: CGFloat = 0.25

        init(rowCounts: [Int], ratios: [CGFloat], spacing: CGFloat) {
            self.rowCounts = rowCounts

            var heights: [CGFloat] = []
            var cropping: CGFloat = 0
            var start = 0
            for count in rowCounts {
                let rowRatios = ratios[start..<(start + count)]
                let natural = (1 - spacing * CGFloat(count - 1)) / rowRatios.reduce(0, +)
                let range = Self.rowHeightRange(tileCount: count, albumTileCount: ratios.count)
                let height = min(max(natural, range.lowerBound), range.upperBound)
                cropping += abs(natural - height)
                heights.append(height)
                start += count
            }
            rowHeights = heights

            let totalHeight = heights.reduce(0, +) + spacing * CGFloat(rowCounts.count - 1)
            let isTopHeavy = zip(rowCounts, rowCounts.dropFirst()).contains { $0 > $1 }
            cost = abs(totalHeight - Self.targetHeight)
                + cropping
                + Self.extraRowCost * CGFloat(max(0, rowCounts.count - 2))
                + (isTopHeavy ? Self.topHeavyCost : 0)
        }

        /// An album of one is at most square. Otherwise a row is at most three quarters of the width tall, and a row of
        /// several at least a little under a fifth.
        private static func rowHeightRange(tileCount: Int, albumTileCount: Int) -> ClosedRange<CGFloat> {
            if albumTileCount == 1 {
                return 0.5...1
            }
            return tileCount == 1 ? 0.5...0.75 : 0.18...0.75
        }

        /// The tiles' frames for an album of the given width: each row filled edge to edge, its tiles in their pictures' proportions.
        func frames(ratios: [CGFloat], width: CGFloat, spacing: CGFloat) -> [CGRect] {
            var frames: [CGRect] = []
            var y: CGFloat = 0
            var start = 0
            for (count, height) in zip(rowCounts, rowHeights) {
                let rowRatios = ratios[start..<(start + count)]
                let rowHeight = (height * width).rounded()
                let available = width - spacing * CGFloat(count - 1)
                let ratioSum = rowRatios.reduce(0, +)
                var x: CGFloat = 0
                for (offset, ratio) in rowRatios.enumerated() {
                    // The last tile takes what's left, so that rounding never leaves a gap at the row's end.
                    let tileWidth = offset == count - 1 ? width - x : (available * ratio / ratioSum).rounded()
                    frames.append(CGRect(x: x, y: y, width: tileWidth, height: rowHeight))
                    x += tileWidth + spacing
                }
                y += rowHeight + spacing
                start += count
            }
            return frames
        }
    }
}

/// Places an album's tiles where ``GalleryMosaic`` puts them, as wide as it's offered.
nonisolated struct GalleryMosaicLayout: Layout {
    let aspectRatios: [CGFloat?]

    /// The width when nothing is proposed, the tallest a single picture in the timeline gets (`TimelineMediaFrame.maxMediaHeight`).
    private static let idealWidth: CGFloat = 300

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        mosaic(width: proposal.width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let mosaic = mosaic(width: bounds.width)
        for (subview, frame) in zip(subviews, mosaic.frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func mosaic(width: CGFloat?) -> GalleryMosaic {
        let width = width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? Self.idealWidth
        return GalleryMosaic(aspectRatios: aspectRatios, width: width)
    }
}

extension GalleryItem {
    /// The picture's width over its height, when its size is known.
    var aspectRatio: CGFloat? {
        guard let size, size.width > 0, size.height > 0 else { return nil }
        return size.width / size.height
    }
}
