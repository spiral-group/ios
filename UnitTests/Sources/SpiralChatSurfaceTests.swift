//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Spiral
import SwiftUI
import Testing

struct SpiralChatSurfaceTests {
    @Test
    func aPersonKeepsTheirHue() {
        // Fixed values: a hash that changed between launches or devices would give a person another colour.
        #expect(SenderHue(userID: "@helena:spiral.md") == .green)
        #expect(SenderHue(userID: "@jacob:spiral.md") == .teal)
        #expect(SenderHue(userID: "@marcus:spiral.md") == .magenta)
    }
    
    @Test
    func everyHueIsReached() {
        let hues = Set((0..<200).map { SenderHue(userID: "@person-\($0):spiral.md") })
        #expect(hues.count == SenderHue.allCases.count)
    }
    
    @Test
    func theBackgroundFallsBackToTheCanvas() {
        #expect(SpiralChatBackgroundPolicy.isDrawn(reduceTransparency: false, contrast: .standard))
        #expect(!SpiralChatBackgroundPolicy.isDrawn(reduceTransparency: true, contrast: .standard))
        #expect(!SpiralChatBackgroundPolicy.isDrawn(reduceTransparency: false, contrast: .increased))
    }
    
    /// A phone in both orientations, the smallest and the largest iPhone, and an iPad both ways.
    @Test(arguments: [CGSize(width: 375, height: 667), CGSize(width: 402, height: 874), CGSize(width: 440, height: 956),
                      CGSize(width: 874, height: 402), CGSize(width: 1032, height: 1376), CGSize(width: 1376, height: 1032)])
    func thePictureCoversTheScreenUnstretched(size: CGSize) {
        let picture = ChatBackgroundLayout.pictureFrame(in: size)
        
        #expect(picture.minX <= 0.001 && picture.minY <= 0.001)
        #expect(picture.maxX >= size.width - 0.001 && picture.maxY >= size.height - 0.001)
        #expect(abs(picture.width / picture.height - ChatBackgroundLayout.pictureSize.width / ChatBackgroundLayout.pictureSize.height) < 0.001)
    }
    
    @Test(arguments: [CGSize(width: 375, height: 667), CGSize(width: 874, height: 402), CGSize(width: 1032, height: 1376)])
    func aCropKeepsTheHillsAtTheBottomAndTheMiddleOfTheWidth(size: CGSize) {
        let picture = ChatBackgroundLayout.pictureFrame(in: size)
        
        #expect(abs(picture.maxY - size.height) < 0.001)
        #expect(abs(picture.midX - size.width / 2) < 0.001)
    }
    
    @Test
    func theLargestIPhoneShowsThePictureWhole() {
        let size = CGSize(width: 440, height: 956)
        let picture = ChatBackgroundLayout.pictureFrame(in: size)
        
        #expect(abs(picture.width - size.width) < 0.1 && abs(picture.height - size.height) < 0.1)
    }
}
