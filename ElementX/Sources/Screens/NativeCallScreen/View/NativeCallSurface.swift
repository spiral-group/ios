//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 383): the call's floating surfaces, Liquid Glass everywhere, over a live
// picture too (operator, 2026-11-08). Legibility is the system's own: the glass adapts to what is behind it and its
// words take the primary style, which glass makes vibrant (decision 346: system surfaces only, no tint, no blur, no
// shade of our own). Over a bright picture the white words measured 1.7-2.6:1 in the lab; the lab keeps the dark
// regular material beside it for comparison.

import Compound
import SwiftUI

extension EnvironmentValues {
    /// True on the video stage, where the call's surfaces float over a live picture.
    @Entry var nativeCallIsOverPicture = false
    /// The lab's comparison switch (question 383): the dark regular material over a picture instead of Liquid Glass.
    /// Never set by the call.
    @Entry var nativeCallPrefersMaterialOverPicture = false
}

extension View {
    /// Liquid Glass (the regular material before iOS 26), or over a picture the dark regular material.
    func nativeCallSurface(in shape: some Shape, isInteractive: Bool = false) -> some View {
        modifier(NativeCallSurface(shape: shape, isInteractive: isInteractive))
    }
}

private struct NativeCallSurface<SurfaceShape: Shape>: ViewModifier {
    let shape: SurfaceShape
    let isInteractive: Bool

    @Environment(\.nativeCallIsOverPicture) private var isOverPicture
    @Environment(\.nativeCallPrefersMaterialOverPicture) private var prefersMaterialOverPicture
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        if isOverPicture, prefersMaterialOverPicture {
            content
                .background(.regularMaterial, in: shape)
                .overlay { shape.stroke(Color.compound.iconQuaternaryAlpha, lineWidth: 1 / displayScale) }
                .environment(\.colorScheme, .dark)
        } else {
            content.spiralGlass(in: shape, isInteractive: isInteractive)
        }
    }
}
