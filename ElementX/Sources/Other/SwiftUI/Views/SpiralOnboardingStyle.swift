//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (1.0.3 onboarding): what the person's first minute shares — the start screen's blue, the welcome's
// pearl, the capsules Compound has no kind for, and the tinted icon tile of a benefit or a next step. Ported from the
// onboarding lab (`lab/1.0.3-onboarding`) the operator picked from on 2026-11-19 and 2026-11-20.
//

import Compound
import SpiralTokens
import SwiftUI

// MARK: - Fields

extension ShapeStyle where Self == LinearGradient {
    /// The 1.0.2 App Store look, `#6C9BF4 → #2E62DE`; deeper in dark, and deeper still with Increase Contrast.
    static var onboardingBlue: LinearGradient {
        LinearGradient(colors: [Asset.Colors.onboardingBlueTop.swiftUIColor, Asset.Colors.onboardingBlueBottom.swiftUIColor],
                       startPoint: .top,
                       endPoint: .bottom)
    }

    /// The welcome's pearl, `#F4F8FE → #DCE8FB`; a night blue in dark.
    static var onboardingPearl: LinearGradient {
        LinearGradient(colors: [Asset.Colors.onboardingPearlTop.swiftUIColor, Asset.Colors.onboardingPearlBottom.swiftUIColor],
                       startPoint: .top,
                       endPoint: .bottom)
    }
}

// MARK: - Capsules

/// The capsules drawn on the blue and the pearl, at the size of Compound's large button.
struct OnboardingCapsuleButtonStyle: ButtonStyle {
    enum Kind {
        /// White on the blue in the field's ink: the one main action.
        case white
        /// A frosted white on the blue: the second action.
        case frosted
        /// The pearl's quiet button: a card-coloured capsule.
        case pearl
    }

    let kind: Kind

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.compound.bodyLGSemibold)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, CompoundDesignTokens.space5X)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(background, in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.2, bounce: 0), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .white: Asset.Colors.onboardingBlueInk.swiftUIColor
        case .frosted: .white
        case .pearl: .compound.textPrimary
        }
    }

    private var background: Color {
        switch kind {
        case .white: .white
        case .frosted: .white.opacity(0.2)
        case .pearl: Asset.Colors.onboardingPearlCard.swiftUIColor
        }
    }
}

extension ButtonStyle where Self == OnboardingCapsuleButtonStyle {
    static func onboarding(_ kind: OnboardingCapsuleButtonStyle.Kind) -> OnboardingCapsuleButtonStyle {
        .init(kind: kind)
    }
}

// MARK: - Icon tile

/// A rounded tile with an icon in the accent, as a benefit or a next-step row has. It grows with the text.
struct OnboardingIconTile: View {
    enum Symbol {
        case compound(KeyPath<CompoundIcons, Image>)
        /// For what Compound has no icon for (games).
        case system(String)
    }
    
    let symbol: Symbol
    
    @ScaledMetric(relativeTo: .body) private var side = 40
    
    var body: some View {
        icon
            .foregroundStyle(.compound.iconAccentPrimary)
            .frame(width: side, height: side)
            // The accent's own faint tint: Compound's subtle fills are white on the light canvas and the pearl's cards.
            .background(Color.compound.iconAccentPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: SpiralRadius.block, style: .continuous))
            .accessibilityHidden(true)
    }
    
    @ViewBuilder
    private var icon: some View {
        switch symbol {
        case .compound(let keyPath):
            CompoundIcon(keyPath, size: .medium, relativeTo: .compound.bodyLG)
        case .system(let name):
            Image(systemName: name)
                .font(.compound.bodyLG)
        }
    }
}

// MARK: - Spark in a halo

/// The art block of a permission screen: Spark under a soft accent halo, two rings breathing out from it, and an
/// optional badge by Spark's raised hand (the notifications' bell). `scale` shrinks it for a screen with more to read.
struct OnboardingSparkHalo: View {
    let image: ImageAsset
    var badge: KeyPath<CompoundIcons, Image>?
    var scale: CGFloat = 1
    
    @State private var isBreathing = false
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.compound.iconAccentPrimary.opacity(0.22), .clear],
                                     center: .center,
                                     startRadius: 10,
                                     endRadius: 120))
                .frame(width: 240, height: 240)
            
            ForEach(0..<2, id: \.self) { ring in
                Circle()
                    .strokeBorder(Color.compound.iconAccentPrimary.opacity(0.18), lineWidth: 1)
                    .frame(width: 170 + CGFloat(ring) * 50, height: 170 + CGFloat(ring) * 50)
                    .scaleEffect(isBreathing ? 1.04 : 0.98)
                    .opacity(isBreathing ? 0.6 : 1)
            }
            
            Image(asset: image)
                .resizable()
                .scaledToFit()
                .frame(width: 210, height: 210)
            
            if let badge {
                Circle()
                    .fill(.compound.iconAccentPrimary)
                    .frame(width: 44, height: 44)
                    .overlay {
                        CompoundIcon(badge, size: .medium, relativeTo: .compound.bodyLG)
                            .foregroundStyle(.compound.iconOnSolidPrimary)
                    }
                    .shadow(color: .compound.iconAccentPrimary.opacity(0.35), radius: 8, y: 3)
                    .offset(x: 70, y: -66)
            }
        }
        .scaleEffect(scale)
        .frame(height: 230 * scale)
        .onAppear {
            guard !reduceMotion, !ProcessInfo.isRunningTests else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
        .accessibilityHidden(true)
    }
}
