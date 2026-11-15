//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082, concept A of the pinned post). Latest's
// pinned post on a card of its own: a faint accent tint and outline, "Pinned"
// inside it, and the text cut to a few lines with "Read more".
//

import Compound
import SpiralTokens
import SwiftUI

/// "Pinned" with its pin, in the accent, at the top of the pinned card.
struct FeedPinnedLabel: View {
    var body: some View {
        HStack(spacing: CompoundDesignTokens.space1X) {
            CompoundIcon(\.pinSolid, size: .xSmall, relativeTo: .compound.bodySMSemibold)
                .accessibilityHidden(true)
            Text(UntranslatedL10n.screenFeedPinnedLabel)
        }
        .font(.compound.bodySMSemibold)
        .foregroundStyle(.compound.textActionAccent)
    }
}

/// A post's text cut to `lineLimit` lines, with "Read more" under it only when something was cut. The tap on the
/// link is the card's own: it opens the post.
///
/// One layout pass measures the whole text against the cut one, so the link is there from the first frame and the card
/// never grows by a line after it appears.
struct FeedClampedText: View {
    let text: AttributedString
    let lineLimit: Int

    var body: some View {
        FeedClampLayout(spacing: CompoundDesignTokens.space1X) {
            FeedCardText(text: text)
                .hidden()
            FeedCardText(text: text)
                .lineLimit(lineLimit)
            Text(UntranslatedL10n.screenFeedReadMore)
                .font(.compound.bodyLGSemibold)
                .foregroundStyle(.compound.textActionAccent)
                .fixedSize(horizontal: false, vertical: true)
                // Proposed nothing, the link takes nothing and shows nothing.
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .accessibilityHidden(true)
        }
    }
}

/// Lays out the whole text (hidden, measured only), the cut text, and the link: the link goes under the cut text when the
/// whole one is taller, and gets no room otherwise.
struct FeedClampLayout: Layout {
    let spacing: CGFloat

    /// A rounding error is not a cut line.
    static func isCut(wholeHeight: CGFloat, cutHeight: CGFloat) -> Bool {
        wholeHeight - cutHeight > 0.5
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = measure(width: proposal.width, subviews: subviews)
        let width = proposal.width ?? max(sizes.cut.width, sizes.link?.width ?? 0)
        guard let link = sizes.link else { return CGSize(width: width, height: sizes.cut.height) }
        return CGSize(width: width, height: sizes.cut.height + spacing + link.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let width = ProposedViewSize(width: bounds.width, height: nil)
        let sizes = measure(width: bounds.width, subviews: subviews)
        subviews[0].place(at: bounds.origin, proposal: width)
        subviews[1].place(at: bounds.origin, proposal: width)
        if let link = sizes.link {
            subviews[2].place(at: CGPoint(x: bounds.minX, y: bounds.minY + sizes.cut.height + spacing),
                              proposal: ProposedViewSize(width: bounds.width, height: link.height))
        } else {
            subviews[2].place(at: bounds.origin, proposal: .zero)
        }
    }

    private func measure(width: CGFloat?, subviews: Subviews) -> (cut: CGSize, link: CGSize?) {
        guard subviews.count == 3 else { return (.zero, nil) }
        let proposal = ProposedViewSize(width: width, height: nil)
        let whole = subviews[0].sizeThatFits(proposal)
        let cut = subviews[1].sizeThatFits(proposal)
        let link = Self.isCut(wholeHeight: whole.height, cutHeight: cut.height) ? subviews[2].sizeThatFits(proposal) : nil
        return (cut, link)
    }
}

extension View {
    /// The pinned post's card: a faint accent tint inside a thin accent outline, its corners those of Spiral's cards.
    @ViewBuilder
    func feedPinnedCard(_ isOn: Bool = true) -> some View {
        if isOn {
            background(Color.compound.bgAccentSelected.opacity(FeedPinnedCardTint.fill), in: .rect(cornerRadius: SpiralRadius.listCard))
                .overlay {
                    RoundedRectangle(cornerRadius: SpiralRadius.listCard, style: .continuous)
                        .strokeBorder(Color.compound.borderAccentSubtle.opacity(FeedPinnedCardTint.outline), lineWidth: 1)
                }
        } else {
            self
        }
    }
}

/// How much of the accent tokens the card takes: the operator's "very faint" (concept A). Light, the fill is about 5 %
/// of the accent over white and the secondary text keeps 4.6:1 on it.
private enum FeedPinnedCardTint {
    static let fill = 0.5
    static let outline = 0.5
}
