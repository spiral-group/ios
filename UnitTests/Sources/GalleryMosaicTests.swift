//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: tests for GalleryMosaic (question 413).
//

import CoreGraphics
@testable import Spiral
import Testing

/// AGENT-PLATFORM (question 413): how an album's tiles split into rows by their pictures' shapes.
struct GalleryMosaicTests {
    private static let landscape: CGFloat = 3 / 2
    private static let wide: CGFloat = 16 / 9
    private static let portrait: CGFloat = 3 / 4
    private static let square: CGFloat = 1
    private static let width: CGFloat = 330
    
    @Test
    func twoWidePicturesAreStacked() {
        #expect(mosaic([Self.wide, Self.wide]).rowCounts == [1, 1])
    }
    
    @Test
    func twoPortraitsSitSideBySide() {
        #expect(mosaic([Self.portrait, Self.portrait]).rowCounts == [2])
    }
    
    @Test
    func twoSquaresSitSideBySide() {
        #expect(mosaic([Self.square, Self.square]).rowCounts == [2])
    }
    
    @Test
    func aLandscapeAndAPortraitShareARowInTheirProportions() throws {
        let mosaic = mosaic([Self.landscape, Self.portrait])
        #expect(mosaic.rowCounts == [2])
        let frames = mosaic.frames
        try #require(frames.count == 2)
        #expect(frames[0].width > frames[1].width * 1.9, "The landscape tile is twice as wide as the portrait one.")
        #expect(frames[0].height == frames[1].height)
    }
    
    @Test
    func threeLandscapesGoAsALargeTileOverTwo() {
        #expect(mosaic([Self.landscape, Self.landscape, Self.landscape]).rowCounts == [1, 2])
    }
    
    @Test
    func threePortraitsShareOneRow() {
        #expect(mosaic([Self.portrait, Self.portrait, Self.portrait]).rowCounts == [3])
    }
    
    @Test
    func twoPortraitsOverALandscapeKeepTheLandscapeBelow() {
        #expect(mosaic([Self.portrait, Self.portrait, Self.landscape]).rowCounts == [2, 1])
    }
    
    @Test
    func fourLandscapesGoAsALargeTileOverThree() {
        #expect(mosaic([Self.landscape, Self.landscape, Self.landscape, Self.landscape]).rowCounts == [1, 3])
    }
    
    @Test
    func fourSquaresGoAsTwoByTwo() {
        #expect(mosaic([Self.square, Self.square, Self.square, Self.square]).rowCounts == [2, 2])
    }
    
    @Test
    func fiveMixedPicturesGoAsTwoOverThree() {
        #expect(mosaic([Self.portrait, Self.landscape, Self.square, Self.portrait, Self.wide]).rowCounts == [2, 3])
    }
    
    @Test
    func sixPicturesShowFiveTiles() {
        let mosaic = mosaic(Array(repeating: Self.landscape, count: 6))
        #expect(mosaic.frames.count == GalleryMosaic.maxVisibleTiles)
        #expect(mosaic.rowCounts == [2, 3])
    }
    
    @Test
    func unknownShapesAreSquares() {
        #expect(mosaic([nil, nil, nil]) == mosaic([Self.square, Self.square, Self.square]))
    }
    
    @Test(arguments: 1...6)
    func tilesFillTheWidthWithoutOverlapping(itemCount: Int) {
        let shapes = [Self.landscape, Self.portrait, Self.square, Self.wide, Self.portrait, Self.landscape]
        let mosaic = mosaic(Array(shapes.prefix(itemCount)))
        let rows = Dictionary(grouping: mosaic.frames, by: \.minY).sorted { $0.key < $1.key }.map(\.value)
        
        #expect(rows.map(\.count) == mosaic.rowCounts)
        for row in rows {
            #expect(row.first?.minX == 0)
            #expect(row.last?.maxX == Self.width, "Each row reaches the album's edge.")
            for (left, right) in zip(row, row.dropFirst()) {
                #expect(right.minX - left.maxX == GalleryMosaic.spacing)
            }
        }
        for (upper, lower) in zip(rows, rows.dropFirst()) {
            #expect((lower.first?.minY ?? 0) - (upper.first?.maxY ?? 0) == GalleryMosaic.spacing)
        }
        #expect(mosaic.size == CGSize(width: Self.width, height: mosaic.frames.map(\.maxY).max() ?? 0))
    }
    
    @Test
    func overflowCountsTheLastTileAndTheRest() {
        #expect(GalleryMosaic.overflowCount(itemCount: 1) == 0)
        #expect(GalleryMosaic.overflowCount(itemCount: 5) == 0)
        #expect(GalleryMosaic.overflowCount(itemCount: 6) == 2)
        #expect(GalleryMosaic.overflowCount(itemCount: 10) == 6)
    }
    
    @Test
    func anEmptyAlbumHasNoTiles() {
        let mosaic = mosaic([])
        #expect(mosaic.frames.isEmpty)
        #expect(mosaic.size == .zero)
    }
    
    // MARK: - Helpers
    
    private func mosaic(_ aspectRatios: [CGFloat?]) -> GalleryMosaic {
        GalleryMosaic(aspectRatios: aspectRatios, width: Self.width)
    }
}
