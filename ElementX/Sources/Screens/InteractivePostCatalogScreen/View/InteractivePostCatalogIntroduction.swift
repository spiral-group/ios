//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (question 412, introduction C): the catalogue's first opening says what an
// interactive post is before anything is chosen — nobody has seen one anywhere yet. Apple's
// welcome sheet: a fan of three real posts with the Peek looking over them, the name, one line,
// three things they do, and the way on. Once, then straight to the catalogue.
//

import Compound
import SFSafeSymbols
import SpiralTokens
import SwiftUI

struct InteractivePostCatalogIntroduction: View {
    let context: InteractivePostCatalogScreenViewModel.Context

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                InteractivePostCatalogIntroductionFan(stills: context.viewState.introductionTemplateIDs.map { context.viewState.catalogueStills[$0] })
                    .padding(.top, 4)
                VStack(spacing: 6) {
                    InteractivePostCatalogTitle(text: UntranslatedL10n.screenInteractiveCatalogIntroTitle)
                        .font(.compound.headingXLBold)
                        .foregroundStyle(.compound.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(UntranslatedL10n.screenInteractiveCatalogIntroLine)
                        .font(.compound.bodyLG)
                        .foregroundStyle(.spiral.chatBackgroundTextSecondary)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 28)
                VStack(alignment: .leading, spacing: 18) {
                    feature(.person2, tint: .compound.iconAccentPrimary,
                            UntranslatedL10n.screenInteractiveCatalogIntroTogetherTitle, UntranslatedL10n.screenInteractiveCatalogIntroTogetherDetail)
                    feature(.eyeSlash, tint: .compound.textDecorative4,
                            UntranslatedL10n.screenInteractiveCatalogIntroSealedTitle, UntranslatedL10n.screenInteractiveCatalogIntroSealedDetail)
                    feature(.sparkles, tint: .compound.iconSuccessPrimary,
                            UntranslatedL10n.screenInteractiveCatalogIntroAgentTitle, UntranslatedL10n.screenInteractiveCatalogIntroAgentDetail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 28)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button { context.send(viewAction: .finishIntroduction) } label: {
                Text(UntranslatedL10n.screenInteractiveCatalogIntroAction)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.compound(.primary))
            .padding(.horizontal, InteractivePostCatalogCardMetrics.screenMargin)
            .padding(.bottom, 12)
            .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.introductionDone)
        }
    }

    /// One of the three things a post does, its symbol in a tinted rounded square, as Apple's welcome sheets draw them.
    /// The square is a tile of the chat's, so the symbol reads on it over any part of the background (question 412).
    private func feature(_ symbol: SFSymbol, tint: Color, _ title: String, _ detail: String) -> some View {
        let tile = RoundedRectangle(cornerRadius: SpiralRadius.block, style: .continuous)
        return HStack(alignment: .center, spacing: 14) {
            Image(systemSymbol: symbol)
                .font(.compound.headingSMSemibold)
                .foregroundStyle(tint)
                // Decorative and in a 44 pt tile: past xxxLarge the symbol would outgrow it (DEBT § 412 catalogue G).
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.14), in: tile)
                .background(Color.spiral.chatBackgroundSurface, in: tile)
                .chatElevation(cornerRadius: SpiralRadius.block)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(.compound.textPrimary)
                Text(detail)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.spiral.chatBackgroundTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Three real posts fanned out: one upright in the middle, two behind it tilted, the Peek looking over the middle one.
private struct InteractivePostCatalogIntroductionFan: View {
    /// Left, middle, right; nil until a still has come, drawn at its size all the same.
    let stills: [UIImage?]

    private let side: CGFloat = 150
    private let sideBehind: CGFloat = 132

    var body: some View {
        ZStack {
            card(stills[safe: 0] ?? nil, side: sideBehind)
                .rotationEffect(.degrees(-12))
                .offset(x: -88, y: 14)
            card(stills[safe: 2] ?? nil, side: sideBehind)
                .rotationEffect(.degrees(12))
                .offset(x: 88, y: 14)
            card(stills[safe: 1] ?? nil, side: side)
                .background(alignment: .top) {
                    // Behind the middle post: only its head shows over the top edge.
                    Image(asset: Asset.spiralPeekFill)
                        .font(.compound.headingXLBold)
                        .foregroundStyle(.compound.iconAccentPrimary)
                        .offset(y: -30)
                }
        }
        .frame(height: side + 40)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func card(_ image: UIImage?, side: CGFloat) -> some View {
        InteractivePostCatalogStill(image: image)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: SpiralRadius.bubble, style: .continuous))
            .chatElevation(cornerRadius: SpiralRadius.bubble)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
