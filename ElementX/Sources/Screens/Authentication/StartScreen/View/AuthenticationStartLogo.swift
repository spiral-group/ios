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
/// AGENT-PLATFORM (ADR-0005 auth-screen pass): the asset itself is now the
/// generated START-SCREEN TILE — the twin of the operator-owned AppIcon
/// (accent-blue rounded tile + white glyph, emitted by gen-ios-assets.mjs
/// from the same brand master) — so the upstream brand chrome (white card,
/// circle shadows, hardcoded shadow colour) is gone; a single soft shadow
/// presents the tile like an app icon.
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
            .shadow(color: .black.opacity(hideBrandChrome ? 0 : 0.16),
                    radius: side / 10,
                    y: side / 20)
            .accessibilityHidden(true)
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
