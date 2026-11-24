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
    /// What an image depends on, so a tab renders each one once. Bold Text and Increase Contrast change the drawing as
    /// they change the bar's own symbols: a renderer sees neither unless it is given them.
    struct Appearance: Hashable {
        let isSelected: Bool
        let colorScheme: ColorScheme
        let colorSchemeContrast: ColorSchemeContrast
        let legibilityWeight: LegibilityWeight?
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

    /// The avatar after the person's profile changed. The photo drawn stays while its URL is the same, so a profile
    /// update that only touched the name, or nothing, doesn't flash the tab to the monogram; only a new URL loads one.
    static func updated(_ current: SpiralTabAvatar?, photoURL currentURL: URL?,
                        name: String?, contentID: String, newPhotoURL: URL?) -> (avatar: SpiralTabAvatar, loadsPhoto: Bool) {
        let isSamePhoto = currentURL == newPhotoURL && current != nil
        let avatar = SpiralTabAvatar(name: name, contentID: contentID, photo: isSamePhoto ? current?.photo : nil)
        return (avatar, !isSamePhoto && newPhotoURL != nil)
    }

    @MainActor
    func image(for appearance: Appearance) -> UIImage? {
        let renderer = ImageRenderer(content: content(isSelected: appearance.isSelected, isContrastIncreased: appearance.isContrastIncreased)
            .tabImageEnvironment(appearance))
        renderer.scale = appearance.displayScale
        return renderer.uiImage?.withRenderingMode(.alwaysOriginal)
    }

    fileprivate func content(isSelected: Bool, isContrastIncreased: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(isContrastIncreased ? .primary : Self.ringLevel, lineWidth: isSelected ? Self.selectedRingWidth : Self.ringWidth)

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

extension SpiralTabAvatar.Appearance {
    /// With Increase Contrast the lighter layer goes: the glyph colours have no contrast variant, and a renderer's
    /// environment doesn't carry the setting to a hierarchical symbol, so nothing else would change.
    var isContrastIncreased: Bool {
        colorSchemeContrast == .increased
    }
}

extension View {
    /// The environment a tab's image is drawn in, so its weight follows Bold Text as the bar's own symbols do.
    func tabImageEnvironment(_ appearance: SpiralTabAvatar.Appearance) -> some View {
        environment(\.colorScheme, appearance.colorScheme)
            .environment(\.legibilityWeight, appearance.legibilityWeight)
    }
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

/// The Settings tab's avatar kept in step with the person's profile. The photo drawn stays through updates with the
/// same URL, so the tab doesn't flash to the monogram; a load under way isn't started again; a failed one is tried
/// again on the next update, as the URL is only remembered once its photo is drawn.
final class SpiralTabAvatarLoader {
    private(set) var avatar: SpiralTabAvatar? {
        didSet {
            if avatar != oldValue { onChange(avatar) }
        }
    }

    private let loadPhoto: (URL) async -> UIImage?
    private let onChange: (SpiralTabAvatar?) -> Void
    /// The URL of the photo drawn; nil while the avatar is the monogram.
    private var drawnURL: URL?
    private var loadingURL: URL?
    private var loadTask: Task<Void, Never>?

    init(loadPhoto: @escaping (URL) async -> UIImage?, onChange: @escaping (SpiralTabAvatar?) -> Void) {
        self.loadPhoto = loadPhoto
        self.onChange = onChange
    }

    func update(name: String?, contentID: String, photoURL: URL?) {
        let update = SpiralTabAvatar.updated(avatar, photoURL: drawnURL, name: name, contentID: contentID, newPhotoURL: photoURL)
        if update.avatar.photo == nil {
            drawnURL = nil
        }
        avatar = update.avatar
        guard let photoURL else {
            loadTask?.cancel()
            loadingURL = nil
            return
        }
        guard update.loadsPhoto, loadingURL != photoURL else { return }
        loadTask?.cancel()
        loadingURL = photoURL
        loadTask = Task { [weak self, loadPhoto] in
            let photo = await loadPhoto(photoURL)
            guard let self, !Task.isCancelled else { return }
            loadingURL = nil
            guard let photo else { return }
            avatar?.photo = photo
            drawnURL = photoURL
        }
    }
}

struct SpiralTabAvatar_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static var previews: some View {
        HStack(spacing: CompoundDesignTokens.space4X) {
            SpiralTabAvatar(name: "Alice", contentID: "@alice:example.com").content(isSelected: false, isContrastIncreased: false)
            SpiralTabAvatar(name: "Alice", contentID: "@alice:example.com").content(isSelected: true, isContrastIncreased: false)
        }
        .padding(CompoundDesignTokens.space4X)
        .previewLayout(.sizeThatFits)
    }
}
