//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): the one shadow of what lies on the room's background, as a picture. A layer's shadow
// is blurred again whenever its path is set, and SwiftUI moves a hosted view on every tick of an animation. This is blurred once
// per theme and shape, stretched by its centre pixel, and laid out by SwiftUI like the bubble it's under.
//

import SpiralTokens
import SwiftUI

struct ChatShadowTexture {
    /// The design's blur of 12 as a Gaussian's σ, which is what a layer calls its shadow's radius.
    static let sigma: CGFloat = 6
    static let offset: CGFloat = 3
    static let opacity: CGFloat = 0.2
    /// How far past a shape the shadow can be seen. Further out it's under half a level of 8 bits.
    static let reach = sigma * 2.5
    
    /// What a texture is made for: everything that changes its pixels.
    struct Key: Hashable {
        let shape: Shape
        /// How far above the shape its row ends, which is as far as the shadow rises. A newer row lies on an older one, so what
        /// rose past the edge would land on the older bubble.
        let rowClearance: CGFloat
        let colorScheme: ColorScheme
        let displayScale: CGFloat
    }
    
    /// A rounded rectangle at the size the texture stretches from, in whole pixels.
    struct Shape: Hashable {
        let cornerRadius: CGFloat
        let width: CGFloat
        let height: CGFloat
        
        /// SwiftUI grows a picture to its caps and never squeezes them, so it can be no taller than the shortest view it's under:
        /// a line of text, 36 pt in a bubble of radius 16 and 54 in a card of 24. The taller the better for what stretches, as
        /// a tall view's long sides are their shadow at the picture's middle, which short corners still weaken.
        init(cornerRadius: CGFloat, displayScale: CGFloat) {
            self.cornerRadius = cornerRadius
            width = 2 * max(cornerRadius * 1.5, ChatShadowTexture.reach) + 1 / displayScale
            height = 2 * max(cornerRadius * 1.125, ChatShadowTexture.reach) + 1 / displayScale
        }
        
        /// A capsule's ends follow its size, so it takes its own height. Its shadow stops changing along a side 4σ past its
        /// ends, which a shorter one doesn't reach: that one is exact, and there are few.
        init(capsuleOf size: CGSize, displayScale: CGFloat) {
            let fullWidth = max((size.width * displayScale).rounded(), 1) / displayScale
            let fullHeight = max((size.height * displayScale).rounded(), 1) / displayScale
            cornerRadius = min(fullWidth, fullHeight) / 2
            width = min(fullWidth, fullHeight + 4 * ChatShadowTexture.sigma)
            height = min(fullHeight, fullWidth + 4 * ChatShadowTexture.sigma)
        }
    }
    
    let image: UIImage
    /// What's left of the image in each direction once the 1 px that stretches is taken out of it.
    let capInsets: EdgeInsets
    /// How far the image reaches past the view it's under.
    let overhang: EdgeInsets
    
    private static var cache = [Key: ChatShadowTexture]()
    /// A chip takes a texture for each height it comes in, which is a handful. This keeps a session of odd sizes from growing for ever.
    private static let cacheLimit = 64
    
    static func texture(for key: Key) -> ChatShadowTexture {
        if let texture = cache[key] {
            return texture
        }
        
        if cache.count >= cacheLimit {
            cache.removeAll()
        }
        let texture = ChatShadowTexture(key: key)
        cache[key] = texture
        return texture
    }
    
    private init(key: Key) {
        let shape = key.shape
        let overhang = EdgeInsets(top: min(Self.reach - Self.offset, key.rowClearance),
                                  leading: Self.reach,
                                  bottom: Self.reach + Self.offset,
                                  trailing: Self.reach)
        let onePixel = 1 / key.displayScale
        let leadingHalf = ((shape.width - onePixel) / 2 * key.displayScale).rounded(.down) / key.displayScale
        let topHalf = ((shape.height - onePixel) / 2 * key.displayScale).rounded(.down) / key.displayScale
        
        self.overhang = overhang
        capInsets = EdgeInsets(top: overhang.top + topHalf,
                               leading: overhang.leading + leadingHalf,
                               bottom: overhang.bottom + shape.height - onePixel - topHalf,
                               trailing: overhang.trailing + shape.width - onePixel - leadingHalf)
        image = Self.render(shape, overhang: overhang, colorScheme: key.colorScheme, displayScale: key.displayScale)
    }
    
    private static func render(_ shape: Shape, overhang: EdgeInsets, colorScheme: ColorScheme, displayScale: CGFloat) -> UIImage {
        // Whole pixels again: the renderer rounds up, and a sum of thirds of a point can come to a hair over one.
        let size = CGSize(width: ((overhang.leading + shape.width + overhang.trailing) * displayScale).rounded() / displayScale,
                          height: ((overhang.top + shape.height + overhang.bottom) * displayScale).rounded() / displayScale)
        let color = UIColor(Color.spiral.chatShadow)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light))
            .withAlphaComponent(opacity)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = displayScale
        format.opaque = false
        format.preferredRange = .standard
        
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cgContext = context.cgContext
            // Only the shadow is wanted, so the shape stands outside the picture and casts it in. The offsets take the context's
            // scale. A blur of 12.5 is what a layer's radius of 6 measures: Core Graphics' runs short of twice its σ.
            let frame = CGRect(x: overhang.leading - size.width, y: overhang.top, width: shape.width, height: shape.height)
            cgContext.setShadow(offset: CGSize(width: size.width, height: offset), blur: 12.5, color: color.cgColor)
            cgContext.addPath(UIBezierPath(roundedRect: frame, cornerRadius: shape.cornerRadius).cgPath)
            cgContext.fillPath()
            
            fadeOut(cgContext, overHeight: reach - offset - overhang.top)
        }
    }
    
    /// Where its row stops a shadow short it fades out, the longer the more it's cut, as a straight cut draws a line along the row's
    /// edge. In a group most of that is under the bubble, and what shows is softer corners.
    private static func fadeOut(_ context: CGContext, overHeight height: CGFloat) {
        guard height > 0,
              let gradient = CGGradient(colorsSpace: nil,
                                        colors: [UIColor.black.cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray,
                                        locations: nil) else {
            return
        }
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setBlendMode(.destinationOut)
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
    }
}
