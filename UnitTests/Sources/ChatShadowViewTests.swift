//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): the shadow as SwiftUI lays it out and as it comes out on screen, next to a real layer's
// shadow at the same values.
//

@testable import Spiral
import SpiralTokens
import SwiftUI
import Testing

@MainActor
struct ChatShadowViewTests {
    // MARK: - Layout
    
    @Test
    func theShadowKeepsToItsBubbleThroughAnAnimation() async throws {
        let model = Model()
        let hosted = try Hosted(AnimatedBubble(model: model))
        let shadow = try #require(hosted.shadowLayers.first)
        let bubble = try #require(hosted.fillLayers.first)
        let spill = shadow.frame.height - bubble.frame.height
        
        model.isTall = true
        
        var heights = Set<CGFloat>()
        let end = Date().addingTimeInterval(0.5)
        while Date() < end {
            // SwiftUI hands these two to Core Animation, so it's what's on screen that moves.
            let shadowNow = (shadow.presentation() ?? shadow).frame
            let bubbleNow = (bubble.presentation() ?? bubble).frame
            heights.insert(bubbleNow.height)
            // Read here they can be a frame apart, as SwiftUI updates them off this thread: 2.5 pt at this speed. Detached is tens.
            #expect(abs(shadowNow.height - bubbleNow.height - spill) < 3)
            #expect(abs(shadowNow.midX - bubbleNow.midX) < 1)
            try await Task.sleep(for: .milliseconds(8))
        }
        #expect(heights.count > 5)
    }
    
    @Test
    func itReachesPastTheViewOnEverySide() throws {
        let hosted = try Hosted(Color.white.frame(width: 200, height: 60).chatElevation(cornerRadius: SpiralRadius.bubble).onBackground())
        let shadow = try #require(hosted.shadowLayers.first)
        let bubble = try #require(hosted.fillLayers.first)
        
        #expect(abs(bubble.frame.minX - shadow.frame.minX - ChatShadowTexture.reach) < 0.01)
        #expect(abs(shadow.frame.maxX - bubble.frame.maxX - ChatShadowTexture.reach) < 0.01)
        #expect(abs(shadow.frame.maxY - bubble.frame.maxY - ChatShadowTexture.reach - ChatShadowTexture.offset) < 0.01)
        #expect(abs(bubble.frame.minY - shadow.frame.minY - 8) < 0.01)
    }
    
    @Test
    func rightToLeftLaysItOutTheSame() throws {
        let hosted = try Hosted(Color.white.frame(width: 200, height: 60)
            .chatElevation(cornerRadius: SpiralRadius.bubble)
            .onBackground()
            .environment(\.layoutDirection, .rightToLeft))
        let shadow = try #require(hosted.shadowLayers.first)
        let bubble = try #require(hosted.fillLayers.first)
        
        #expect(abs(shadow.frame.midX - bubble.frame.midX) < 0.01)
    }
    
    @Test
    func theDateBadgeHasTheRoomsShadowOnItsBackground() throws {
        let hosted = try Hosted(FloatingDateBadge(dateText: "Today").onBackground())
        hosted.controller.view.backgroundColor = .white
        
        #expect(hosted.shadowLayers.count == 1)
        #expect(hosted.liveShadows == 0)
    }
    
    @Test
    func theDateBadgeKeepsAShadowOnThePlainCanvas() throws {
        // It's the canvas's own colour: Reduce Transparency and Increase Contrast would lose it without this.
        let hosted = try Hosted(FloatingDateBadge(dateText: "Today"))
        hosted.controller.view.backgroundColor = .white
        
        #expect(hosted.shadowLayers.isEmpty)
        #expect(hosted.liveShadows > 0)
    }
    
    @Test
    func aChipIsMeasuredWhateverItsHeight() throws {
        for height in [CGFloat(20), 34, 58, 120] {
            let hosted = try Hosted(Color.white.frame(width: 300, height: height).chatElevation().onBackground())
            let shadow = try #require(hosted.shadowLayers.first)
            
            #expect(abs(shadow.frame.height - height - 8 - ChatShadowTexture.reach - ChatShadowTexture.offset) < 0.01)
        }
    }
    
    @Test
    func thePlainCanvasHasNoShadow() throws {
        // Reduce Transparency and Increase Contrast take the picture away, and it with them.
        let hosted = try Hosted(Color.white.frame(width: 200, height: 60).chatElevation(cornerRadius: SpiralRadius.bubble))
        
        #expect(hosted.shadowLayers.isEmpty)
    }
    
    // MARK: - Traits
    
    @Test
    func aChangeOfDisplayScaleTakesPicturesOfThatScale() async throws {
        let hosted = try Hosted(Color.white.frame(width: 200, height: 60).chatElevation(cornerRadius: SpiralRadius.bubble).onBackground())
        
        hosted.controller.traitOverrides.displayScale = 2
        try await Task.sleep(for: .milliseconds(100))
        #expect(hosted.shadowLayers.first?.contentsScale == 2)
        
        hosted.controller.traitOverrides.displayScale = 3
        try await Task.sleep(for: .milliseconds(100))
        #expect(hosted.shadowLayers.first?.contentsScale == 3)
    }
    
    @Test
    func aChangeOfThemeTakesItsPicture() async throws {
        let hosted = try Hosted(Color.white.frame(width: 200, height: 60).chatElevation(cornerRadius: SpiralRadius.bubble).onBackground())
        hosted.controller.view.backgroundColor = .white
        
        hosted.window.overrideUserInterfaceStyle = .light
        try await Task.sleep(for: .milliseconds(100))
        let light = try hosted.colourUnderTheBubble()
        hosted.window.overrideUserInterfaceStyle = .dark
        try await Task.sleep(for: .milliseconds(100))
        let dark = try hosted.colourUnderTheBubble()
        
        #expect(light.blue > light.red + 4) // Blue over white.
        #expect(dark.red < 250)
        #expect(dark.blue == dark.red) // Black over white.
    }
    
    // MARK: - Against a layer's shadow
    
    /// What the nine-slice has to cover: one line, more lines and pictures, the cards, and chips at the sizes they come in.
    private static let shapes = [
        ComparedShape("bubble, one line", width: 90, height: 36.333, cornerRadius: SpiralRadius.bubble),
        ComparedShape("bubble, one line, long", width: 240, height: 36.333, cornerRadius: SpiralRadius.bubble),
        ComparedShape("bubble, two lines", width: 340, height: 56.667, cornerRadius: SpiralRadius.bubble),
        ComparedShape("bubble, four lines", width: 340, height: 97, cornerRadius: SpiralRadius.bubble),
        ComparedShape("picture", width: 280, height: 210, cornerRadius: SpiralRadius.bubble),
        ComparedShape("tall picture", width: 240, height: 420, cornerRadius: SpiralRadius.bubble),
        ComparedShape("card", width: 240, height: 56, cornerRadius: SpiralRadius.callBubble),
        ComparedShape("tall card", width: 340, height: 140, cornerRadius: SpiralRadius.callBubble),
        ComparedShape("upgrade card", width: 360, height: 120, cornerRadius: 0),
        ComparedShape("chip, New", width: 38, height: 20.333),
        ComparedShape("chip, a date", width: 90, height: 20.333),
        ComparedShape("chip, a state", width: 300, height: 20.333),
        ComparedShape("chip, two lines", width: 300, height: 34),
        ComparedShape("chip, AX3", width: 180, height: 44),
        ComparedShape("chip, AX3, two lines", width: 300, height: 78),
        ComparedShape("chip, tall", width: 90, height: 240)
    ]
    
    @Test(.timeLimit(.minutes(1)), arguments: [ColorScheme.light, .dark])
    func theTextureMatchesALayersShadow(colorScheme: ColorScheme) throws {
        let scale = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first).screen.scale
        var worst = Difference()
        
        for shape in Self.shapes {
            let reference = try LayerShadowRender(size: shape.size, cornerRadius: shape.cornerRadius, colorScheme: colorScheme)
            let texture = try TextureShadowRender(size: shape.size, cornerRadius: shape.cornerRadius, colorScheme: colorScheme)
            
            let reach = CGRect(origin: renderFrame.origin, size: shape.size).insetBy(dx: -30, dy: -30)
            let difference = try Difference(reference.pixels,
                                            texture.pixels,
                                            shape: reference.shapePixels,
                                            around: reach.applying(CGAffineTransform(scaleX: scale, y: scale)))
            // swiftlint:disable:next print_deprecation - the numbers belong in the test's log, where a reader of the run finds them
            print("ChatShadowPixels \(colorScheme) \(shape.name) \(Int(shape.size.width))x\(Int(shape.size.height)): \(difference)")
            worst.keepWorst(of: difference)
        }
        
        // swiftlint:disable:next print_deprecation - as above
        print("ChatShadowPixels \(colorScheme) worst of \(Self.shapes.count) shapes: \(worst)")
        #expect(worst.maxOutside <= 6)
        #expect(worst.rootMeanSquareOutside <= 1.5)
    }
}

// MARK: - Helpers

private struct ComparedShape {
    let name: String
    let size: CGSize
    let cornerRadius: CGFloat?
    
    init(_ name: String, width: CGFloat, height: CGFloat, cornerRadius: CGFloat? = nil) {
        self.name = name
        size = CGSize(width: width, height: height)
        self.cornerRadius = cornerRadius
    }
}

private extension View {
    func onBackground() -> some View {
        environment(\.isChatBackgroundDrawn, true)
    }
}

private final class Model: ObservableObject {
    @Published var isTall = false
}

private struct AnimatedBubble: View {
    @ObservedObject var model: Model
    
    var body: some View {
        Color.white
            .frame(width: 200, height: model.isTall ? 180 : 60)
            .chatElevation(cornerRadius: SpiralRadius.bubble)
            .onBackground()
            .animation(.linear(duration: 0.8), value: model.isTall)
    }
}

/// A SwiftUI view in a window of the scene, so that its layers exist as they do on screen.
@MainActor
private final class Hosted<Content: View> {
    let window: UIWindow
    let controller: UIHostingController<Content>
    
    var shadowLayers: [CALayer] {
        allLayers(of: window.layer).filter { $0.contents != nil && $0.contentsCenter != CGRect(x: 0, y: 0, width: 1, height: 1) }
    }
    
    /// A layer shadow you could see.
    var liveShadows: Int {
        allLayers(of: window.layer).count { $0.shadowOpacity > 0 && ($0.shadowColor?.alpha ?? 0) > 0 }
    }
    
    /// The view over the shadow, whose `Color` is a plain layer.
    var fillLayers: [CALayer] {
        allLayers(of: controller.view.layer).filter { $0.backgroundColor?.alpha == 1 && $0.frame.width < controller.view.bounds.width }
    }
    
    /// What 5 pt under the first bubble looks like, as the window's bytes have it.
    func colourUnderTheBubble() throws -> (red: Int, blue: Int) {
        let bubble = try #require(fillLayers.first)
        let frame = bubble.convert(bubble.bounds, to: window.layer)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let pixels = try WindowPixels(image)
        let index = (Int(frame.maxY + 5) * pixels.width + Int(frame.midX)) * 4
        return (Int(pixels.bytes[index]), Int(pixels.bytes[index + 2]))
    }
    
    init(_ content: Content) throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.windowLevel = .alert + 1
        window.isHidden = false
        controller = UIHostingController(rootView: content)
        window.rootViewController = controller
        window.layoutIfNeeded()
    }
    
    deinit {
        MainActor.assumeIsolated { [window] in window.isHidden = true }
    }
    
    private func allLayers(of layer: CALayer) -> [CALayer] {
        [layer] + (layer.sublayers ?? []).flatMap(allLayers)
    }
}

/// Bytes of a render of the window, RGBA.
private struct WindowPixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]
    
    init(_ image: UIImage) throws {
        let cgImage = try #require(image.cgImage)
        width = cgImage.width
        height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress,
                      width: cgImage.width,
                      height: cgImage.height,
                      bitsPerComponent: 8,
                      bytesPerRow: cgImage.width * 4,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        })
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        self.bytes = bytes
    }
}

/// How far a render lies from another, in levels of 255 of the worst channel: outside the shape, where a shadow shows.
private struct Difference: CustomStringConvertible {
    var maxOutside = 0
    var rootMeanSquareOutside = 0.0
    var maxInside = 0
    var pixelsOverOne = 0
    
    var description: String {
        String(format: "outside max %d rms %.2f, %d px over 1, inside max %d", maxOutside, rootMeanSquareOutside, pixelsOverOne, maxInside)
    }
    
    init() { }
    
    /// Over what the shadow can reach, in the shape's frame given in pixels, as the rest of the window is the same white in both.
    init(_ first: WindowPixels, _ second: WindowPixels, shape: WindowPixels, around frame: CGRect) throws {
        var sum = 0.0
        var count = 0
        let rows = max(Int(frame.minY), 0)..<min(Int(frame.maxY), first.height)
        let columns = max(Int(frame.minX), 0)..<min(Int(frame.maxX), first.width)
        for y in rows {
            for x in columns {
                let index = (y * first.width + x) * 4
                let difference = max(abs(Int(first.bytes[index]) - Int(second.bytes[index])),
                                     abs(Int(first.bytes[index + 1]) - Int(second.bytes[index + 1])),
                                     abs(Int(first.bytes[index + 2]) - Int(second.bytes[index + 2])))
                let coverage = shape.bytes[index]
                if coverage == 255 { // The mask's white background: nothing of the shape here.
                    maxOutside = max(maxOutside, difference)
                    sum += Double(difference * difference)
                    count += 1
                    if difference > 1 {
                        pixelsOverOne += 1
                    }
                } else if coverage == 0 {
                    maxInside = max(maxInside, difference)
                }
            }
        }
        rootMeanSquareOutside = (sum / Double(max(count, 1))).squareRoot()
    }
    
    mutating func keepWorst(of other: Difference) {
        maxOutside = max(maxOutside, other.maxOutside)
        rootMeanSquareOutside = max(rootMeanSquareOutside, other.rootMeanSquareOutside)
        maxInside = max(maxInside, other.maxInside)
        pixelsOverOne = max(pixelsOverOne, other.pixelsOverOne)
    }
}

private let renderFrame = CGRect(x: 30, y: 200, width: 0, height: 0)

/// A window of plain white with something on it, rendered as the screen would show it: white is where a shadow has most contrast.
@MainActor
private func renderWindow(_ configure: (UIWindow, UIView) throws -> Void) throws -> WindowPixels {
    let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    window.frame = scene.screen.bounds
    window.windowLevel = .alert + 1
    let root = UIViewController()
    root.view.backgroundColor = .white
    window.rootViewController = root
    window.isHidden = false
    try configure(window, root.view)
    window.layoutIfNeeded()
    
    let format = UIGraphicsImageRendererFormat()
    format.scale = scene.screen.scale
    format.opaque = true
    format.preferredRange = .standard
    let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    window.isHidden = true
    return try WindowPixels(image)
}

private func cornerRadius(_ cornerRadius: CGFloat?, of size: CGSize) -> CGFloat {
    cornerRadius ?? min(size.width, size.height) / 2
}

/// What `ChatShadow` was: a layer's shadow from an explicit path, here at the design's level 2.
@MainActor
private struct LayerShadowRender {
    let pixels: WindowPixels
    /// The shape in black on white, which says what a shadow is visible on.
    let shapePixels: WindowPixels
    
    init(size: CGSize, cornerRadius radius: CGFloat?, colorScheme: ColorScheme) throws {
        let frame = CGRect(origin: renderFrame.origin, size: size)
        let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: cornerRadius(radius, of: size)).cgPath
        pixels = try renderWindow { _, root in
            let view = UIView(frame: frame)
            view.layer.shadowColor = UIColor(Color.spiral.chatShadow)
                .resolvedColor(with: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light))
                .cgColor
            view.layer.shadowOpacity = Float(ChatShadowTexture.opacity)
            view.layer.shadowOffset = CGSize(width: 0, height: ChatShadowTexture.offset)
            view.layer.shadowRadius = ChatShadowTexture.sigma
            view.layer.shadowPath = path
            root.addSubview(view)
        }
        shapePixels = try renderWindow { _, root in
            let view = UIView(frame: frame)
            let shape = CAShapeLayer()
            shape.path = path
            shape.fillColor = UIColor.black.cgColor
            view.layer.addSublayer(shape)
            root.addSubview(view)
        }
    }
}

/// The same with the real thing, in a hosting controller.
@MainActor
private struct TextureShadowRender {
    let pixels: WindowPixels
    
    init(size: CGSize, cornerRadius radius: CGFloat?, colorScheme: ColorScheme) throws {
        pixels = try renderWindow { _, root in
            let content = Color.clear
                .frame(width: size.width, height: size.height)
                .chatElevation(cornerRadius: radius, rowClearance: 100) // A row's edge has nothing to do with this.
                .onBackground()
                .environment(\.colorScheme, colorScheme)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: renderFrame.minX, y: renderFrame.minY)
            let controller = UIHostingController(rootView: content)
            controller.safeAreaRegions = []
            controller.view.backgroundColor = .clear
            controller.view.frame = root.bounds
            root.addSubview(controller.view)
            controller.view.layoutIfNeeded()
        }
    }
}
