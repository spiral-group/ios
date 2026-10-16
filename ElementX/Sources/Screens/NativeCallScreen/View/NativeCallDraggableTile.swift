//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063): the draggable corner video tile (G14).

import Compound
import SwiftUI

/// G14 — the corner video tile: draggable to any corner, tap swaps who is
/// large. The corner is view-local state — it is a hand position, not a
/// fact about the call.
struct NativeCallDraggableTile: View {
    let tile: NativeCallVideoTile
    let renderer: NativeCallVideoRendering?
    var displayName: String?
    var profile: NativeCallMemberProfile?
    var mediaProvider: MediaProviderProtocol?
    var onTap: (() -> Void)?
    var onDoubleTap: (() -> Void)?

    @State private var corner: Alignment = .topTrailing
    @GestureState private var dragOffset: CGSize = .zero

    private static let tileSize = CGSize(width: 104, height: 156)

    var body: some View {
        GeometryReader { geometry in
            NativeCallVideoTileView(tile: tile,
                                    renderer: renderer,
                                    displayName: displayName,
                                    profile: profile,
                                    mediaProvider: mediaProvider,
                                    avatarSize: 44)
                .frame(width: Self.tileSize.width, height: Self.tileSize.height)
                .offset(dragOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner)
                .padding(16)
                // The double-tap recognizer must be installed FIRST so a
                // single tap waits for it to fail instead of firing twice.
                .onTapGesture(count: 2) { onDoubleTap?() }
                .onTapGesture { onTap?() }
                .gesture(DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        corner = Self.nearestCorner(from: corner,
                                                    translation: value.predictedEndTranslation,
                                                    in: geometry.size)
                    })
                .animation(.spring(duration: 0.3), value: corner)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(onTap != nil ? UntranslatedL10n.a11yNativeCallSwapVideo : UntranslatedL10n.a11yNativeCallSwitchCamera)
        }
    }

    /// Where the tile lands: the corner nearest to where the drag was
    /// headed, from the corner it started in.
    static func nearestCorner(from corner: Alignment, translation: CGSize, in size: CGSize) -> Alignment {
        let startX: CGFloat = corner == .topTrailing || corner == .bottomTrailing ? size.width - tileSize.width : 0
        let startY: CGFloat = corner == .bottomLeading || corner == .bottomTrailing ? size.height - tileSize.height : 0
        let endX = startX + translation.width + tileSize.width / 2
        let endY = startY + translation.height + tileSize.height / 2
        switch (endX > size.width / 2, endY > size.height / 2) {
        case (true, false): return .topTrailing
        case (false, false): return .topLeading
        case (true, true): return .bottomTrailing
        case (false, true): return .bottomLeading
        }
    }
}
