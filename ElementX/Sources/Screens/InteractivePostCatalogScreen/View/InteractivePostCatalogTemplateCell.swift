//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (question 412 concept G, card A «Бульбашка», question 376): a
// catalogue card is one block shaped like an incoming message — the room's own
// bubble surface and corners — holding the template's still (drawn once at
// `catalog:pack`, light, with sample names), its name and one line. It reads as
// "this goes into the chat as a message", and the text no longer floats on Mist.
// A still holds no web view, so the catalogue starts nothing however it is
// scrolled; a tap opens the post's page, where the template itself runs.
//

import Compound
import SpiralTokens
import SwiftUI

enum InteractivePostCatalogCardMetrics {
    static let spacing: CGFloat = 12
    /// The still's inset inside its bubble, and the corners that keep it concentric.
    static let stillInset: CGFloat = 6
    static let stillRadius: CGFloat = SpiralRadius.bubble - stillInset
    static let screenMargin: CGFloat = 16
    private static let widestShelfCard: CGFloat = 170
    /// How many cards a shelf shows, the last one cut: a thumb knows there is more.
    private static let cardsPerShelf: CGFloat = 2.35

    static func shelfSide(in width: CGFloat) -> CGFloat {
        min(widestShelfCard, ((width - screenMargin - 2 * spacing) / cardsPerShelf).rounded(.down))
    }

    static func gridSide(in width: CGFloat) -> CGFloat {
        ((width - 2 * screenMargin - spacing) / 2).rounded(.down)
    }
}

struct InteractivePostCatalogTemplateCell: View {
    let template: SpiralAppTemplate
    let side: CGFloat
    let still: UIImage?
    /// The catalogue names it new (question 412): a small badge on the still.
    var isNew = false
    let open: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                InteractivePostCatalogStill(image: still)
                    .frame(width: stillSide, height: stillSide)
                    .overlay(alignment: .topLeading) {
                        if isNew {
                            InteractivePostCatalogNewBadge()
                                .padding(6)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: InteractivePostCatalogCardMetrics.stillRadius, style: .continuous))
                // Every card as tall as two lines of each, so a shelf never changes height as it scrolls,
                // with the line straight under the name.
                ZStack(alignment: .topLeading) {
                    text(title: String(repeating: "\n", count: titleLineLimit - 1), description: "\n")
                        .hidden()
                    text(title: template.localizedTitle, description: template.localizedDescription)
                }
                .padding(.horizontal, 6)
            }
            .padding(InteractivePostCatalogCardMetrics.stillInset)
            .padding(.bottom, 4)
            .frame(width: side, alignment: .topLeading)
            .background(Color.spiral.chatBackgroundSurface, in: RoundedRectangle(cornerRadius: SpiralRadius.bubble, style: .continuous))
            .chatElevation(cornerRadius: SpiralRadius.bubble)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isNew ? UntranslatedL10n.a11yInteractiveCatalogNew(template.localizedTitle) : template.localizedTitle)
        .accessibilityHint(template.localizedDescription)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.card(template.id))
    }

    private var stillSide: CGFloat {
        side - 2 * InteractivePostCatalogCardMetrics.stillInset
    }

    /// A name takes up to 4 lines at accessibility sizes, where 2 cut most of them; the description stays at 2, read
    /// whole as the card's hint.
    private var titleLineLimit: Int {
        dynamicTypeSize.isAccessibilitySize ? 4 : 2
    }

    private func text(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.compound.bodyMDSemibold)
                .foregroundStyle(.compound.textPrimary)
                .lineLimit(titleLineLimit)
            Text(description)
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
                .lineLimit(2)
        }
        .multilineTextAlignment(.leading)
    }
}

/// A post that isn't running: what it last looked like, or the catalogue's
/// still, or a quiet grey and glyph when there is neither.
struct InteractivePostCatalogStill: View {
    let image: UIImage?

    var body: some View {
        Color.compound.bgSubtleSecondary
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    CompoundIcon(\.extensions, size: .medium, relativeTo: .compound.bodyMDSemibold)
                        .foregroundStyle(.compound.iconTertiary)
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// «New» on a card's still: the post's scene stays the colour, the badge a quiet white label.
struct InteractivePostCatalogNewBadge: View {
    var body: some View {
        Text(UntranslatedL10n.screenInteractiveCatalogNewBadge)
            .font(.compound.bodyXSSemibold)
            .foregroundStyle(.compound.textActionAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.spiral.chatBackgroundSurface, in: .capsule)
            .chatElevation()
            .accessibilityHidden(true)
    }
}

/// A card of the catalogue's «New» slider (question 412): a new template, its still,
/// «NEW», its name and line, and «Try it», which opens its page.
struct InteractivePostCatalogNewCard: View {
    let template: SpiralAppTemplate
    let still: UIImage?
    /// A finger went down on the card, or lifted: the slider holds still under it.
    var pressChanged: (Bool) -> Void = { _ in }
    let open: () -> Void

    private let side: CGFloat = 104
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 14) {
                InteractivePostCatalogStill(image: still)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: SpiralRadius.bubble, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(UntranslatedL10n.screenInteractiveCatalogNewBadge)
                        .textCase(.uppercase)
                        .font(.compound.bodyXSSemibold)
                        .tracking(0.6)
                        .foregroundStyle(.compound.textActionAccent)
                    Text(template.localizedTitle)
                        .font(.compound.bodyLGSemibold)
                        .foregroundStyle(.compound.textPrimary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                    Text(template.localizedDescription)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                        .lineLimit(2)
                    HStack(spacing: 2) {
                        Text(UntranslatedL10n.screenInteractiveCatalogTry)
                        CompoundIcon(\.chevronRight, size: .xSmall, relativeTo: .compound.bodyMDSemibold)
                            .flipsForRightToLeftLayoutDirection(true)
                    }
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(.compound.textActionAccent)
                    .padding(.top, 2)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // As tall as the slider's tallest card, so the slider never changes height between them.
            .frame(maxHeight: .infinity)
            .padding(10)
            .background(Color.spiral.chatBackgroundSurface, in: RoundedRectangle(cornerRadius: SpiralRadius.listCard, style: .continuous))
            .chatElevation(cornerRadius: SpiralRadius.listCard)
            .contentShape(.rect)
        }
        .buttonStyle(InteractivePostCatalogPressReportingButtonStyle(pressChanged: pressChanged))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UntranslatedL10n.a11yInteractiveCatalogNew(template.localizedTitle))
        .accessibilityHint(template.localizedDescription)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.newCard)
    }
}

/// A plain button that says when a finger goes down on it and when it lifts.
private struct InteractivePostCatalogPressReportingButtonStyle: ButtonStyle {
    let pressChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .onChange(of: configuration.isPressed) { _, isPressed in pressChanged(isPressed) }
    }
}
