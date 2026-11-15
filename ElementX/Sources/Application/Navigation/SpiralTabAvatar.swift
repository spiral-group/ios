//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SpiralTokens
import SwiftUI

/// The person's avatar as a tab's image (Brief 0083 phase 4, lane chats-shell, decision 349). A tab bar draws images only,
/// never a view, so the avatar is rendered to an image that keeps its own colours.
///
/// A ring always goes round it, clear of the photo so it shows on any photo, in the lighter layer of the other tabs'
/// glyphs (question 399): the accent's when selected, the grey's at rest. It is thicker when selected, which is the only
/// sign of selection besides the colour on a bar without Liquid Glass's lens.
struct SpiralTabAvatar: Equatable {
    /// What an image depends on, so a tab renders each one once.
    struct Appearance: Hashable {
        let isSelected: Bool
        let colorScheme: ColorScheme
        let displayScale: CGFloat
    }

    /// The image's diameter, the ring's outer edge: the other tabs' glyphs read about this tall (question 399).
    private static let diameter: CGFloat = 26
    /// The ring's width at rest and selected (question 399: 1.5 times decision 349's).
    private static let ringWidth: CGFloat = 2.25
    private static let selectedRingWidth: CGFloat = 3
    /// The gap between the selected ring and the photo.
    private static let ringGap: CGFloat = 1
    private static let photoDiameter = diameter - 2 * (selectedRingWidth + ringGap)

    let name: String?
    let contentID: String
    /// The person's photo, once it has loaded. Without one the avatar is the monogram (decision 328).
    var photo: UIImage?

    @MainActor
    func image(for appearance: Appearance) -> UIImage? {
        let renderer = ImageRenderer(content: content(isSelected: appearance.isSelected)
            .environment(\.colorScheme, appearance.colorScheme))
        renderer.scale = appearance.displayScale
        return renderer.uiImage?.withRenderingMode(.alwaysOriginal)
    }

    fileprivate func content(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Self.ringLevel, lineWidth: isSelected ? Self.selectedRingWidth : Self.ringWidth)

            artwork
                .frame(width: Self.photoDiameter, height: Self.photoDiameter)
                .clipShape(.circle)
        }
        .foregroundStyle(SpiralTabGlyph.color(isSelected: isSelected))
        .frame(width: Self.diameter, height: Self.diameter)
    }

    @ViewBuilder
    private var artwork: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
        } else {
            PlaceholderAvatarImage(name: name, contentID: contentID)
        }
    }

    /// The glyphs are drawn hierarchically (decision 386), and the ring takes their lighter layer in both states (question
    /// 399): the Peek's tail, light blue when selected and grey at rest, resolved from the same foreground as the glyphs.
    private static let ringLevel = HierarchicalShapeStyle.secondary
}

/// The colour the tab bar draws a tab's glyph in: selected in the window's tint, unselected as the bar draws it, the label
/// colour on Liquid Glass and grey before (decision 386). Spiral's glyphs and the person's ring are drawn in it.
enum SpiralTabGlyph {
    static func color(isSelected: Bool) -> Color {
        if isSelected {
            .compound.textActionAccent
        } else if #available(iOS 26, *) {
            .compound.textPrimary
        } else {
            .compound.iconSecondary
        }
    }
}

struct SpiralTabAvatar_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static var previews: some View {
        HStack(spacing: CompoundDesignTokens.space4X) {
            SpiralTabAvatar(name: "Alice", contentID: "@alice:example.com").content(isSelected: false)
            SpiralTabAvatar(name: "Alice", contentID: "@alice:example.com").content(isSelected: true)
        }
        .padding(CompoundDesignTokens.space4X)
        .previewLayout(.sizeThatFits)
    }
}
