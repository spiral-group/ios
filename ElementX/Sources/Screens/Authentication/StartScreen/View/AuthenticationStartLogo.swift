//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// The app's logo styled to fit on various launch pages.
///
/// AGENT-PLATFORM (ADR-0005 auth-screen pass): the asset is a light and dark
/// render of `AppIcon.icon` (gen-ios-assets.mjs, question 358), so the upstream
/// brand chrome (white card, circle shadows, hardcoded shadow colour) is gone;
/// a single soft shadow presents the tile like an app icon, around the edge
/// every drawing of the logo has (decision 370).
struct AuthenticationStartLogo: View {
    /// Set to specify a custom size for the Logo, otherwise the default size of 158pt will be used.
    var size: CGFloat?
    /// Set to `true` to skip the brand presentation (white-label provisioning).
    let hideBrandChrome: Bool
    /// Legacy upstream parameter (the gradient background is gone with the
    /// ADR-0005 flat canvas); kept so call sites stay untouched.
    let isOnGradient: Bool
    
    private let appLogoImage = Image(asset: Asset.Images.appLogo)
    
    private var side: CGFloat { size ?? 158 }
    
    var body: some View {
        appLogoImage
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .appLogoEdge(hasShadow: false)
            .shadow(color: .black.opacity(hideBrandChrome ? 0 : 0.16),
                    radius: side / 10,
                    y: side / 20)
            .accessibilityHidden(true)
    }
}

// AGENT-PLATFORM (Brief 0083, decision 370): the logo's character is white out to the tile's edge, so on a white page
// the tile lost its shape. What holds it: a hairline and a soft shadow in light, the line alone in dark.
extension View {
    /// For the tile drawn at any size. `hasShadow` is off where a larger shadow of its own already lies under it.
    func appLogoEdge(hasShadow: Bool = true) -> some View {
        modifier(AppLogoEdge(hasShadow: hasShadow))
    }
}

private struct AppLogoEdge: ViewModifier {
    let hasShadow: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .overlay {
                AppLogoTile().strokeBorder(colorScheme == .dark ? .white.opacity(0.16) : .black.opacity(0.12), lineWidth: 0.5)
            }
            // A blur of 5 is a radius of 2.5.
            .shadow(color: hasShadow && colorScheme == .light ? .black.opacity(0.14) : .clear, radius: 2.5, y: 1)
    }
}

/// The tile's outline. 26 % of its side is what fits the asset's own corner, to within a pixel at 474 px.
nonisolated private struct AppLogoTile: InsettableShape {
    var insetAmount: CGFloat = 0
    
    func path(in rect: CGRect) -> Path {
        let radius = 0.26 * min(rect.width, rect.height) - insetAmount
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .path(in: rect.insetBy(dx: insetAmount, dy: insetAmount))
    }
    
    func inset(by amount: CGFloat) -> Self {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

#Preview {
    VStack(spacing: 0) {
        HStack(spacing: 0) {
            AuthenticationStartLogo(hideBrandChrome: false, isOnGradient: false)
                .padding()
            AuthenticationStartLogo(hideBrandChrome: false, isOnGradient: true)
                .padding()
                .background {
                    AuthenticationStartScreenBackgroundImage().offset(y: 70)
                }
                .clipped()
        }
        .background(.compound.bgCanvasDefault)
        
        HStack(spacing: 0) {
            AuthenticationStartLogo(hideBrandChrome: false, isOnGradient: false)
                .padding()
            AuthenticationStartLogo(hideBrandChrome: false, isOnGradient: true)
                .padding()
                .background {
                    AuthenticationStartScreenBackgroundImage().offset(y: 70)
                }
                .clipped()
        }
        .background(.compound.bgCanvasDefault)
        .colorScheme(.dark)
        
        HStack(spacing: 0) {
            AuthenticationStartLogo(size: 54, hideBrandChrome: false, isOnGradient: false)
                .padding()
                .background(.compound.bgCanvasDefault)
            AuthenticationStartLogo(size: 54, hideBrandChrome: false, isOnGradient: false)
                .padding()
                .background(.compound.bgCanvasDefault)
                .colorScheme(.dark)
        }
        .padding(.top)
    }
}
