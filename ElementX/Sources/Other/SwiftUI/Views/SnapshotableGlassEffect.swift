//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

@available(iOS 26, *)
extension View {
    /// Similar to the `.glassProminent` button style, `.glassEffect` breaks our preview tests so this modifier provides a fallback.
    /// https://github.com/pointfreeco/swift-snapshot-testing/issues/1029#issuecomment-3366942138
    @ViewBuilder
    func snapshotableGlassEffect(_ glass: Glass, snapshotBackground: Color, in shape: some Shape) -> some View {
        if !ProcessInfo.isRunningUnitTests {
            glassEffect(glass, in: shape)
        } else {
            background(snapshotBackground, in: shape)
        }
    }
}

// AGENT-PLATFORM (Brief 0083, decision 346): Spiral's one floating surface.
extension View {
    /// Liquid Glass from iOS 26 and the regular material before it. Snapshots draw neither, which needs a window's
    /// backdrop, so they show a translucent stand-in.
    ///
    /// - Parameter snapshotBackground: That stand-in, where the surface has a look of its own to snapshot.
    func spiralGlass(in shape: some Shape, isInteractive: Bool = false, snapshotBackground: Color? = nil) -> some View {
        modifier(SpiralGlassSurface(shape: shape, isInteractive: isInteractive, snapshotBackground: snapshotBackground))
    }
}

private struct SpiralGlassSurface<SurfaceShape: Shape>: ViewModifier {
    let shape: SurfaceShape
    let isInteractive: Bool
    let snapshotBackground: Color?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    private var standIn: Color {
        snapshotBackground ?? (colorScheme == .dark ? Color.compound.iconPrimary.opacity(0.14) : Color.compound.bgCanvasDefault.opacity(0.6))
    }

    func body(content: Content) -> some View {
        if ProcessInfo.isRunningUnitTests {
            content.background(standIn, in: shape)
        } else if #available(iOS 26, *) {
            content.glassEffect(isInteractive ? .regular.interactive() : .regular, in: shape)
        } else {
            // A material has no edge of its own over a flat field: a hairline gives it one.
            content
                .background(.regularMaterial, in: shape)
                .overlay { shape.stroke(Color.compound.iconQuaternaryAlpha, lineWidth: 1 / displayScale) }
        }
    }
}

// AGENT-PLATFORM (Brief 0083, question 383): glass surfaces that sit together merge and morph as one.
/// `GlassEffectContainer` from iOS 26; before it, and in snapshots, the content as it is.
struct SpiralGlassGroup<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder let content: Content

    var body: some View {
        if !ProcessInfo.isRunningUnitTests, #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
