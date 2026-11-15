//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): the shadow's picture: how it stretches, what it's cached by, and what's in it.
//

@testable import Spiral
import SpiralTokens
import SwiftUI
import Testing

@MainActor
struct ChatShadowTextureTests {
    private nonisolated static let scales: [CGFloat] = [1, 2, 3]
    
    // MARK: - Nine-slice geometry
    
    @Test(arguments: scales)
    func exactlyOnePixelStretches(displayScale: CGFloat) {
        for shape in shapes(displayScale: displayScale) {
            let texture = texture(shape, displayScale: displayScale)
            let pixel = 1 / displayScale
            
            #expect(isSame(texture.capInsets.leading + pixel + texture.capInsets.trailing, texture.image.size.width))
            #expect(isSame(texture.capInsets.top + pixel + texture.capInsets.bottom, texture.image.size.height))
        }
    }
    
    @Test(arguments: scales)
    func theImageIsInTheDisplaysPixels(displayScale: CGFloat) throws {
        for shape in shapes(displayScale: displayScale) {
            let image = texture(shape, displayScale: displayScale).image
            let cgImage = try #require(image.cgImage)
            
            #expect(image.scale == displayScale)
            #expect(CGFloat(cgImage.width) == (image.size.width * displayScale).rounded())
            #expect(CGFloat(cgImage.height) == (image.size.height * displayScale).rounded())
        }
    }
    
    @Test(arguments: scales)
    func everyCapIsOnAWholePixel(displayScale: CGFloat) {
        for shape in shapes(displayScale: displayScale) {
            let insets = texture(shape, displayScale: displayScale).capInsets
            
            for inset in [insets.top, insets.leading, insets.bottom, insets.trailing] {
                #expect(isSame(inset * displayScale, (inset * displayScale).rounded()))
            }
        }
    }
    
    @Test
    func theImageReachesPastTheViewByItsOverhangAlone() {
        let shape = ChatShadowTexture.Shape(cornerRadius: SpiralRadius.bubble, displayScale: 3)
        let texture = texture(shape, displayScale: 3)
        
        #expect(isSame(texture.image.size.width, shape.width + texture.overhang.leading + texture.overhang.trailing))
        #expect(isSame(texture.image.size.height, shape.height + texture.overhang.top + texture.overhang.bottom))
    }
    
    @Test
    func theShadowFallsAndReachesEvenlyToTheSides() {
        let overhang = texture(.init(cornerRadius: SpiralRadius.bubble, displayScale: 3), rowClearance: 100, displayScale: 3).overhang
        
        #expect(overhang.top == ChatShadowTexture.reach - ChatShadowTexture.offset)
        #expect(overhang.bottom == ChatShadowTexture.reach + ChatShadowTexture.offset)
        #expect(overhang.leading == overhang.trailing)
    }
    
    @Test(arguments: [CGFloat(0), 1, 5, 8, 9])
    func aShadowRisesNoFurtherThanItsRow(rowClearance: CGFloat) {
        let texture = texture(.init(cornerRadius: SpiralRadius.bubble, displayScale: 3), rowClearance: rowClearance, displayScale: 3)
        
        #expect(texture.overhang.top == rowClearance)
    }
    
    @Test
    func aLineOfTextIsNoShorterThanItsTexture() {
        // SwiftUI grows a resizable image to its caps, so a texture any taller would hang past a short bubble.
        #expect(ChatShadowTexture.Shape(cornerRadius: SpiralRadius.bubble, displayScale: 3).height <= 36.34)
        #expect(ChatShadowTexture.Shape(cornerRadius: SpiralRadius.callBubble, displayScale: 3).height <= 54.34)
    }
    
    @Test
    func aCornerFitsInsideItsCaps() {
        for radius in [SpiralRadius.bubble, SpiralRadius.callBubble] {
            let shape = ChatShadowTexture.Shape(cornerRadius: radius, displayScale: 3)
            
            #expect(shape.height >= 2 * radius)
            #expect(shape.width >= 3 * radius)
        }
    }
    
    // MARK: - Capsules
    
    @Test
    func chipsOfAHeightShareATextureHoweverWide() {
        let scale: CGFloat = 3
        let short = texture(.init(capsuleOf: CGSize(width: 90, height: 22), displayScale: scale), displayScale: scale)
        let long = texture(.init(capsuleOf: CGSize(width: 300, height: 22), displayScale: scale), displayScale: scale)
        
        #expect(short.image === long.image)
    }
    
    @Test
    func aChipsHeightTakesItsOwnTexture() {
        let scale: CGFloat = 3
        // Dynamic Type's sizes and a second line of text.
        let heights: [CGFloat] = [20.333, 22, 26.667, 34, 58, 76.333]
        let images = heights.map { texture(.init(capsuleOf: CGSize(width: 300, height: $0), displayScale: scale), displayScale: scale).image }
        
        #expect(Set(images.map(ObjectIdentifier.init)).count == heights.count)
    }
    
    @Test
    func aCapsuleIsRoundedByHalfItsShorterSide() {
        #expect(ChatShadowTexture.Shape(capsuleOf: CGSize(width: 200, height: 40), displayScale: 2).cornerRadius == 20)
        #expect(ChatShadowTexture.Shape(capsuleOf: CGSize(width: 40, height: 200), displayScale: 2).cornerRadius == 20)
    }
    
    @Test
    func aCapsuleKeepsItsHeightAndStretchesAlong() {
        let shape = ChatShadowTexture.Shape(capsuleOf: CGSize(width: 300, height: 22), displayScale: 2)
        
        #expect(shape.height == 22)
        #expect(shape.width == 22 + 4 * ChatShadowTexture.sigma)
    }
    
    @Test
    func aChipTooShortToStretchIsDrawnExactly() {
        let shape = ChatShadowTexture.Shape(capsuleOf: CGSize(width: 30, height: 22), displayScale: 2)
        
        #expect(shape.width == 30)
        #expect(shape.height == 22)
    }
    
    @Test
    func aCapsuleIsMeasuredInPixels() {
        let shape = ChatShadowTexture.Shape(capsuleOf: CGSize(width: 300, height: 20.34), displayScale: 3)
        
        #expect(isSame(shape.height * 3, 61))
    }
    
    @Test
    func anEmptyCapsuleDrawsNothingAndDoesNotFail() {
        let texture = texture(.init(capsuleOf: .zero, displayScale: 3), displayScale: 3)
        
        #expect(texture.image.size.width > 0)
    }
    
    // MARK: - Cache
    
    @Test
    func theSameKeyIsTheSamePicture() {
        let shape = ChatShadowTexture.Shape(cornerRadius: SpiralRadius.bubble, displayScale: 3)
        
        #expect(texture(shape, displayScale: 3).image === texture(shape, displayScale: 3).image)
    }
    
    @Test
    func eachThemeHasItsOwnPicture() {
        let shape = ChatShadowTexture.Shape(cornerRadius: SpiralRadius.bubble, displayScale: 3)
        
        #expect(texture(shape, colorScheme: .light, displayScale: 3).image !== texture(shape, colorScheme: .dark, displayScale: 3).image)
    }
    
    @Test
    func eachDisplayScaleHasItsOwnPicture() {
        // The same shape in points, as a window moving to another screen would ask for it.
        let shape = ChatShadowTexture.Shape(capsuleOf: CGSize(width: 300, height: 22), displayScale: 2)
        
        #expect(texture(shape, displayScale: 2).image !== texture(shape, displayScale: 3).image)
        #expect(texture(shape, displayScale: 3).image.scale == 3)
    }
    
    @Test
    func eachCornerFamilyHasItsOwnPicture() {
        let images = [0, SpiralRadius.bubble, SpiralRadius.callBubble].map { texture(.init(cornerRadius: $0, displayScale: 3), displayScale: 3).image }
        
        #expect(Set(images.map(ObjectIdentifier.init)).count == 3)
    }
    
    @Test
    func eachRowClearanceHasItsOwnPicture() {
        let shape = ChatShadowTexture.Shape(cornerRadius: SpiralRadius.bubble, displayScale: 3)
        
        #expect(texture(shape, rowClearance: 1, displayScale: 3).image !== texture(shape, rowClearance: 9, displayScale: 3).image)
    }
    
    @Test
    func theCacheHasALimit() {
        let first = ChatShadowTexture.Shape(capsuleOf: CGSize(width: 300, height: 500), displayScale: 3)
        let image = texture(first, displayScale: 3).image
        
        for height in 1...100 {
            _ = texture(.init(capsuleOf: CGSize(width: 300, height: 100 + CGFloat(height)), displayScale: 3), displayScale: 3)
        }
        
        #expect(texture(first, displayScale: 3).image !== image)
    }
    
    // MARK: - Pixels
    
    @Test(arguments: [(ColorScheme.light, 0x16, 0x3F, 0xA8), (.dark, 0, 0, 0)])
    func theMiddleIsTheTokensColourAtTheDesignsOpacity(colorScheme: ColorScheme, red: Int, green: Int, blue: Int) throws {
        let texture = texture(.init(cornerRadius: SpiralRadius.bubble, displayScale: 3), colorScheme: colorScheme, displayScale: 3)
        let pixels = try Pixels(texture.image)
        
        let middle = pixels.colour(x: pixels.width / 2, y: pixels.height / 2)
        
        #expect(abs(middle.alpha - 0.2 * 255) <= 1.5)
        // Premultiplied into 51 levels, so a channel can only come back near what it was.
        #expect(abs(middle.red - Double(red)) <= 5)
        #expect(abs(middle.green - Double(green)) <= 5)
        #expect(abs(middle.blue - Double(blue)) <= 5)
    }
    
    @Test
    func itMirrorsToItself() throws {
        // Right to left flips a bubble's side, and nothing in here may tell.
        let shape = ChatShadowTexture.Shape(cornerRadius: SpiralRadius.bubble, displayScale: 3)
        let pixels = try Pixels(texture(shape, displayScale: 3).image)
        
        for y in stride(from: 0, to: pixels.height, by: 7) {
            for x in 0..<(pixels.width / 2) {
                #expect(abs(pixels.alpha(x: x, y: y) - pixels.alpha(x: pixels.width - 1 - x, y: y)) <= 1)
            }
        }
    }
    
    @Test
    func theShadowFadesOutBeforeItsPictureEnds() throws {
        let shape = ChatShadowTexture.Shape(cornerRadius: SpiralRadius.bubble, displayScale: 3)
        let pixels = try Pixels(texture(shape, rowClearance: 100, displayScale: 3).image)
        
        for x in 0..<pixels.width {
            #expect(pixels.alpha(x: x, y: 0) <= 1)
            #expect(pixels.alpha(x: x, y: pixels.height - 1) <= 1)
        }
        for y in 0..<pixels.height {
            #expect(pixels.alpha(x: 0, y: y) <= 1)
            #expect(pixels.alpha(x: pixels.width - 1, y: y) <= 1)
        }
    }
    
    @Test(arguments: [CGFloat(1), 5, 8, 9])
    func aShadowItsRowStopsShortFadesRatherThanEndsInALine(rowClearance: CGFloat) throws {
        let shape = ChatShadowTexture.Shape(cornerRadius: SpiralRadius.bubble, displayScale: 3)
        let pixels = try Pixels(texture(shape, rowClearance: rowClearance, displayScale: 3).image)
        
        for x in 0..<pixels.width {
            #expect(pixels.alpha(x: x, y: 0) <= 1)
        }
    }
    
    @Test
    func theFadeLeavesAShadowAloneBelowIt() throws {
        let shape = ChatShadowTexture.Shape(cornerRadius: SpiralRadius.bubble, displayScale: 3)
        let grouped = texture(shape, rowClearance: 1, displayScale: 3)
        let whole = texture(shape, rowClearance: 100, displayScale: 3)
        let groupedPixels = try Pixels(grouped.image)
        let wholePixels = try Pixels(whole.image)
        
        // Counted up from the bottom of each, as their tops are cut differently.
        for fromBottom in 1...Int((shape.height / 2 + grouped.overhang.bottom) * 3) {
            #expect(groupedPixels.alpha(x: 30, y: groupedPixels.height - fromBottom) == wholePixels.alpha(x: 30, y: wholePixels.height - fromBottom))
        }
    }
    
    @Test(arguments: scales)
    func aLongEdgeFallsOffLikeAGaussian(displayScale: CGFloat) throws {
        // The rounded rectangle of 0 has straight sides at any scale.
        let shape = ChatShadowTexture.Shape(cornerRadius: 0, displayScale: displayScale)
        let texture = texture(shape, rowClearance: 100, displayScale: displayScale)
        let pixels = try Pixels(texture.image)
        let middle = pixels.height / 2
        
        for distance in stride(from: CGFloat(-8), through: 12, by: 2) {
            let x = Int(((texture.overhang.leading - distance) * displayScale).rounded(.down))
            let expected = ChatShadowTexture.opacity * 255 * gaussianTail(distance / ChatShadowTexture.sigma)
            
            #expect(abs(pixels.alpha(x: x, y: middle) - expected) <= 2.5, "at \(distance) pt")
        }
    }
    
    @Test
    func theShadowIsThereUnderTheShapeToo() throws {
        // An own bubble's surface is 85 % on the background, so the shadow shows through it as a layer's did.
        let shape = ChatShadowTexture.Shape(cornerRadius: SpiralRadius.bubble, displayScale: 3)
        let texture = texture(shape, displayScale: 3)
        let pixels = try Pixels(texture.image)
        
        let justInside = Int((texture.overhang.top + shape.height / 2) * 3)
        
        #expect(pixels.alpha(x: pixels.width / 2, y: justInside) > 40)
    }
    
    // MARK: - Helpers
    
    private func shapes(displayScale: CGFloat) -> [ChatShadowTexture.Shape] {
        [0, SpiralRadius.bubble, SpiralRadius.callBubble].map { .init(cornerRadius: $0, displayScale: displayScale) } +
            [CGSize(width: 90, height: 22), CGSize(width: 30, height: 22), CGSize(width: 200, height: 57), CGSize(width: 60, height: 180)]
            .map { .init(capsuleOf: $0, displayScale: displayScale) }
    }
    
    private func texture(_ shape: ChatShadowTexture.Shape,
                         rowClearance: CGFloat = 8,
                         colorScheme: ColorScheme = .light,
                         displayScale: CGFloat) -> ChatShadowTexture {
        .texture(for: .init(shape: shape, rowClearance: rowClearance, colorScheme: colorScheme, displayScale: displayScale))
    }
    
    private func isSame(_ first: CGFloat, _ second: CGFloat) -> Bool {
        abs(first - second) < 0.001
    }
    
    /// How much of a Gaussian's weight lies past `z` of its σ.
    private func gaussianTail(_ z: CGFloat) -> CGFloat {
        erfc(z / 2.0.squareRoot()) / 2
    }
}

/// An image's pixels, premultiplied as a layer takes them.
private struct Pixels {
    struct Colour {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }
    
    let width: Int
    let height: Int
    private let bytes: [UInt8]
    
    init(_ image: UIImage) throws {
        let cgImage = try #require(image.cgImage)
        width = cgImage.width
        height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress,
                      width: cgImage.width,
                      height: cgImage.height,
                      bitsPerComponent: 8,
                      bytesPerRow: cgImage.width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, // swiftlint:disable:this force_unwrapping
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        })
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        self.bytes = bytes
    }
    
    func alpha(x: Int, y: Int) -> CGFloat {
        CGFloat(bytes[(y * width + x) * 4 + 3])
    }
    
    func colour(x: Int, y: Int) -> Colour {
        let index = (y * width + x) * 4
        let alpha = Double(bytes[index + 3])
        guard alpha > 0 else { return Colour(red: 0, green: 0, blue: 0, alpha: 0) }
        return Colour(red: Double(bytes[index]) * 255 / alpha,
                      green: Double(bytes[index + 1]) * 255 / alpha,
                      blue: Double(bytes[index + 2]) * 255 / alpha,
                      alpha: alpha)
    }
}
