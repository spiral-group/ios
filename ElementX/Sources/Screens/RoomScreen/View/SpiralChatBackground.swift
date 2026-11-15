//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359, item 8): the background of a room, its threads and its pinned messages: "Mist",
// layered hills in the brand's blues, across the whole screen. It stands still behind the timeline.
//

import Compound
import SpiralTokens
import SwiftUI

extension EnvironmentValues {
    /// Whether the timeline sits on the background, so what draws on the canvas needs a surface of its own.
    @Entry var isChatBackgroundDrawn = false
}

enum SpiralChatBackgroundPolicy {
    /// A picture under text is what Reduce Transparency and Increase Contrast take away, so both fall back to the canvas.
    static func isDrawn(reduceTransparency: Bool, contrast: ColorSchemeContrast) -> Bool {
        !reduceTransparency && contrast == .standard
    }
}

extension View {
    /// The room's background behind the view: the picture, or the plain canvas.
    func chatBackground() -> some View {
        modifier(ChatBackgroundModifier())
    }
    
    /// Says whether the picture is drawn to a view outside `chatBackground()`, such as what sits in the composer's bar.
    func onChatBackground() -> some View {
        modifier(OnChatBackgroundModifier())
    }
    
    /// A surface for a line that sits straight on the canvas, such as the date, when the canvas is the picture.
    func chatBackgroundChip() -> some View {
        modifier(ChatBackgroundChipModifier())
    }
    
    /// The same for a tile with a layout of its own, such as an ended call.
    func chatBackgroundCard(cornerRadius: CGFloat) -> some View {
        modifier(ChatBackgroundCardModifier(cornerRadius: cornerRadius))
    }
    
    /// The one shadow of what lies on the background (question 359), under a rounded rectangle of the view's own size, or a capsule.
    /// - Parameter rowClearance: how far above the view its row ends, which is as far as the shadow rises. No row leaves less than
    ///   this above a chip.
    func chatElevation(cornerRadius: CGFloat? = nil, rowClearance: CGFloat = 8) -> some View {
        modifier(ChatElevationModifier(cornerRadius: cornerRadius, rowClearance: rowClearance))
    }
}

private struct ChatBackgroundModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    
    private var isDrawn: Bool {
        SpiralChatBackgroundPolicy.isDrawn(reduceTransparency: reduceTransparency, contrast: contrast)
    }
    
    func body(content: Content) -> some View {
        content
            .environment(\.isChatBackgroundDrawn, isDrawn)
            .background {
                if isDrawn {
                    SpiralChatBackground()
                        .ignoresSafeArea()
                } else {
                    Color.compound.bgCanvasDefault
                        .ignoresSafeArea()
                }
            }
    }
}

private struct OnChatBackgroundModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    
    func body(content: Content) -> some View {
        content.environment(\.isChatBackgroundDrawn, SpiralChatBackgroundPolicy.isDrawn(reduceTransparency: reduceTransparency, contrast: contrast))
    }
}

private struct ChatBackgroundChipModifier: ViewModifier {
    @Environment(\.isChatBackgroundDrawn) private var isChatBackgroundDrawn
    
    func body(content: Content) -> some View {
        if isChatBackgroundDrawn {
            content
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(.spiral.chatBackgroundSurface, in: .capsule)
                .chatElevation()
        } else {
            content
        }
    }
}

private struct ChatBackgroundCardModifier: ViewModifier {
    @Environment(\.isChatBackgroundDrawn) private var isChatBackgroundDrawn
    
    let cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        content.background {
            if isChatBackgroundDrawn {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.spiral.chatBackgroundSurface)
            }
        }
        .chatElevation(cornerRadius: cornerRadius)
    }
}

private struct ChatElevationModifier: ViewModifier {
    @Environment(\.isChatBackgroundDrawn) private var isChatBackgroundDrawn
    
    let cornerRadius: CGFloat?
    let rowClearance: CGFloat
    
    func body(content: Content) -> some View {
        content.background {
            if isChatBackgroundDrawn {
                ChatShadow(cornerRadius: cornerRadius, rowClearance: rowClearance)
            }
        }
    }
}

/// The shadow's picture, laid out with the view it's under and past its edges, so that it moves as the view does.
private struct ChatShadow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    
    let cornerRadius: CGFloat?
    let rowClearance: CGFloat
    
    var body: some View {
        Group {
            if let cornerRadius {
                image(of: .init(cornerRadius: cornerRadius, displayScale: displayScale))
            } else {
                GeometryReader { geometry in
                    image(of: .init(capsuleOf: geometry.size, displayScale: displayScale))
                }
            }
        }
        .allowsHitTesting(false) // It reaches past the view, whose touches are its own.
        .accessibilityHidden(true)
    }
    
    private func image(of shape: ChatShadowTexture.Shape) -> some View {
        let texture = ChatShadowTexture.texture(for: .init(shape: shape,
                                                           rowClearance: rowClearance,
                                                           colorScheme: colorScheme,
                                                           displayScale: displayScale))
        return Image(uiImage: texture.image)
            .resizable(capInsets: texture.capInsets)
            .padding(EdgeInsets(top: -texture.overhang.top,
                                leading: -texture.overhang.leading,
                                bottom: -texture.overhang.bottom,
                                trailing: -texture.overhang.trailing))
    }
}

/// A picture per theme, drawn opaque, so nothing lies under it. It takes no input and sits behind the timeline, so nothing that
/// changes in the room redraws it, and the keyboard leaves it alone: `chatBackground()` lays it out past every safe area, the
/// keyboard's too.
struct SpiralChatBackground: View {
    var body: some View {
        GeometryReader { geometry in
            let frame = ChatBackgroundLayout.pictureFrame(in: geometry.size)
            Image(asset: Asset.Images.chatBackground)
                .resizable()
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
        }
        .clipped()
        .environment(\.layoutDirection, .leftToRight) // The picture isn't mirrored right to left.
        .accessibilityHidden(true)
    }
}

/// Covers the screen without stretching. What's over is cropped from the sides and the top, as the hills are at the bottom.
enum ChatBackgroundLayout {
    /// The picture's shape, the one of the largest iPhone, in the pixels of `chat-background.imageset`.
    static let pictureSize = CGSize(width: 1320, height: 2868)
    
    static func pictureFrame(in size: CGSize) -> CGRect {
        let scale = max(size.width / pictureSize.width, size.height / pictureSize.height)
        let width = pictureSize.width * scale
        let height = pictureSize.height * scale
        return CGRect(x: (size.width - width) / 2, y: size.height - height, width: width, height: height)
    }
}
