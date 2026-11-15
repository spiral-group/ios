//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063): the draggable corner video tile (G14).

import Compound
import SpiralTokens
import SwiftUI

/// G14 — the corner tile: draggable to any corner, a tap swaps who is large (decision 341: never the camera; that is
/// the Camera button's alone). The corner is view-local state — it is a hand position, not a fact about the call.
/// It usually holds a video tile; on the assistant's page, once your picture is large, it holds the assistant.
struct NativeCallDraggableTile<Content: View>: View {
    /// Held by the screen, so the tile keeps its corner when a swap puts something else in it.
    @Binding var corner: Alignment
    /// Swaps the pictures; nil when there is nothing to swap with.
    var onSwap: (() -> Void)?
    @ViewBuilder let content: Content

    @GestureState private var dragOffset: CGSize = .zero
    @Environment(\.layoutDirection) private var layoutDirection

    static var tileSize: CGSize {
        CGSize(width: 104, height: 156)
    }

    var body: some View {
        GeometryReader { geometry in
            content
                .frame(width: Self.tileSize.width, height: Self.tileSize.height)
                .contentShape(.rect)
                .offset(dragOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner)
                .padding(16)
                .onTapGesture { onSwap?() }
                .gesture(DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        corner = NativeCallCornerTile.nearestCorner(from: corner,
                                                                    translation: value.predictedEndTranslation,
                                                                    in: geometry.size,
                                                                    tileSize: Self.tileSize,
                                                                    isRightToLeft: layoutDirection == .rightToLeft)
                    })
                .animation(.spring(duration: 0.3), value: corner)
                .accessibilityAddTraits(onSwap != nil ? .isButton : [])
                .accessibilityAction(named: UntranslatedL10n.a11yNativeCallSwapVideo) { onSwap?() }
        }
    }
}

extension NativeCallDraggableTile where Content == NativeCallVideoTileView {
    /// A video tile in the corner.
    init(tile: NativeCallVideoTile,
         renderer: NativeCallVideoRendering?,
         displayName: String? = nil,
         profile: NativeCallMemberProfile? = nil,
         mediaProvider: MediaProviderProtocol? = nil,
         corner: Binding<Alignment>,
         onSwap: (() -> Void)?) {
        _corner = corner
        self.onSwap = onSwap
        content = NativeCallVideoTileView(tile: tile,
                                          renderer: renderer,
                                          displayName: displayName,
                                          profile: profile,
                                          mediaProvider: mediaProvider,
                                          avatarSize: SpiralAvatarSize.medium,
                                          cornerRadius: SpiralRadius.bubble)
    }
}

enum NativeCallCornerTile {
    /// Where a corner tile lands: the corner nearest to where the drag was headed, from the corner it started in. A drag
    /// is measured on screen, while trailing is the right in left-to-right and the left in right-to-left.
    static func nearestCorner(from corner: Alignment, translation: CGSize, in size: CGSize, tileSize: CGSize, isRightToLeft: Bool) -> Alignment {
        let isTrailing = corner == .topTrailing || corner == .bottomTrailing
        let isOnRight = isTrailing != isRightToLeft
        let startX: CGFloat = isOnRight ? size.width - tileSize.width : 0
        let startY: CGFloat = corner == .bottomLeading || corner == .bottomTrailing ? size.height - tileSize.height : 0
        let endsOnRight = startX + translation.width + tileSize.width / 2 > size.width / 2
        let endsAtBottom = startY + translation.height + tileSize.height / 2 > size.height / 2
        switch (endsOnRight != isRightToLeft, endsAtBottom) {
        case (true, false): return .topTrailing
        case (false, false): return .topLeading
        case (true, true): return .bottomTrailing
        case (false, true): return .bottomLeading
        }
    }
}
