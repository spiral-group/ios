//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063, audit A7-8): the group grid, sized from the
// space it actually has.
//
// The first grid derived tile height from tile WIDTH (a fixed 3:4 aspect
// on width-divided columns), which reads fine on a phone and overflows on
// an iPad: ~980pt of width made 3:4 tiles ~430pt tall, three rows of them
// ~1300pt — captions into the dock, last row clipped. A ScrollView was
// tried and reverted (wave 7): scrolling a CALL hides participants, which
// is worse than smaller tiles. The honest fix is here: both axes are
// inputs, and every tile is always fully on screen.

import Foundation
import SwiftUI

/// The grid as a synchronous `Layout`: sizing happens in the same pass as
/// placement, so there is no GeometryReader zero-size first frame — which
/// the full snapshot suite caught as a nondeterministic EMPTY grid (the
/// one-shot capture raced the second layout pass that production quietly
/// gets for free).
struct NativeCallGrid: Layout {
    let spacing: Double
    /// The vertical band the call chrome owns (header above, controls
    /// below) — subtracted from the proposal, mirroring the old padding.
    let topInset: Double
    let bottomInset: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let layout = NativeCallGridLayout.compute(tileCount: subviews.count,
                                                  availableWidth: bounds.width - 24,
                                                  availableHeight: bounds.height - topInset - bottomInset,
                                                  spacing: spacing)
        guard layout.tileWidth > 0 else { return }

        // Top-aligned inside the chrome band, exactly like the old grid.
        let originY = bounds.minY + topInset

        for (index, subview) in subviews.enumerated() {
            let row = index / layout.columns
            let column = index % layout.columns
            // The LAST row may be short; center it like every messenger does.
            let tilesInRow = min(layout.columns, subviews.count - row * layout.columns)
            let rowWidth = Double(tilesInRow) * layout.tileWidth + Double(tilesInRow - 1) * spacing
            let rowOriginX = bounds.minX + (bounds.width - rowWidth) / 2
            let x = rowOriginX + Double(column) * (layout.tileWidth + spacing)
            let y = originY + Double(row) * (layout.tileHeight + spacing)
            subview.place(at: CGPoint(x: x, y: y),
                          proposal: ProposedViewSize(width: layout.tileWidth, height: layout.tileHeight))
        }
    }
}

nonisolated enum NativeCallGridLayout {
    struct Layout: Equatable {
        let columns: Int
        let tileWidth: Double
        let tileHeight: Double
    }

    /// The tallest aspect a tile prefers (width : height = 3 : 4). A
    /// height-starved cell produces a SHORTER tile instead of overflowing
    /// — wider than 3:4 is fine, taller never is.
    private static let preferredAspect = 3.0 / 4.0

    /// Past this many tiles a fourth column may score better than three
    /// tall rows of strips; below it, four columns only shrink faces
    /// (Brief 0067 — rooms above eight are native now, ADR-0079 D3).
    private static let fourColumnThreshold = 9

    /// Pick the column count (1...3, or 1...4 for large rooms) and tile
    /// size such that every tile fits the available rect: the tile fills
    /// its cell's width and its height is capped by BOTH the cell's height
    /// and the preferred aspect. Chooses the column count with the largest
    /// face area.
    static func compute(tileCount: Int, availableWidth: Double, availableHeight: Double, spacing: Double) -> Layout {
        guard tileCount > 0, availableWidth > 0, availableHeight > 0 else {
            return Layout(columns: 1, tileWidth: 0, tileHeight: 0)
        }

        let maximumColumns = tileCount >= fourColumnThreshold ? 4 : 3
        var best = Layout(columns: 1, tileWidth: 0, tileHeight: 0)
        var bestScore = -1.0
        for columns in 1...min(maximumColumns, tileCount) {
            let rows = (tileCount + columns - 1) / columns
            let cellWidth = (availableWidth - Double(columns - 1) * spacing) / Double(columns)
            let cellHeight = (availableHeight - Double(rows - 1) * spacing) / Double(rows)
            guard cellWidth > 0, cellHeight > 0 else { continue }

            let tileWidth = cellWidth
            let tileHeight = min(cellHeight, cellWidth / preferredAspect)

            // Scored by the 3:4 box INSCRIBED in the tile — the face, not
            // the strip. Raw area preferred one column of ultra-wide
            // letterboxes on a phone (caught by the first test run): a
            // 369×139 strip out-areas a 180×240 portrait while showing
            // less of anyone.
            let faceWidth = min(tileWidth, tileHeight * preferredAspect)
            let faceHeight = min(tileHeight, tileWidth / preferredAspect)
            let score = faceWidth * faceHeight

            if score > bestScore {
                bestScore = score
                best = Layout(columns: columns, tileWidth: tileWidth, tileHeight: tileHeight)
            }
        }
        return best
    }
}
