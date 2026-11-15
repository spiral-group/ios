//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, batch P4-F, decision 346): the top of a Feed page: the system's soft scroll edge effect,
// as the room's, and a title that stays readable over what scrolls under it.
//

import Compound
import SwiftUI

extension View {
    /// The system's soft scroll edge effect under the bar. iOS 18 keeps its bar's material.
    @ViewBuilder func feedSoftTopEdge() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }

    /// The same at both ends of a post, where words would otherwise show through the comment field's glass.
    @ViewBuilder func feedSoftEdges() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: .vertical)
        } else {
            self
        }
    }

    /// The page's small centred title: plain at rest, as on Chats, and on glass once content has scrolled under it.
    ///
    /// - Parameter pill: What takes the title's place while it's there.
    func feedBarTitle(_ title: String, pill: FeedBarPill? = nil) -> some View {
        modifier(FeedBarTitleModifier(title: title, pill: pill))
    }
}

/// The new posts pill (decision 289): the words, the count for when they don't fit, and what a tap does.
struct FeedBarPill {
    let title: String
    let count: String
    let action: () -> Void
}

private struct FeedBarTitleModifier: ViewModifier {
    let title: String
    let pill: FeedBarPill?

    @State private var isOverContent = false

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { FeedBarTitle(title: title, isOverContent: isOverContent, pill: pill) }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > CompoundDesignTokens.space1X
            } action: { _, isOverContent in
                withAnimation(.easeOut(duration: 0.2)) { self.isOverContent = isOverContent }
            }
    }
}

struct FeedBarTitle: ToolbarContent {
    let title: String
    let isOverContent: Bool
    var pill: FeedBarPill?

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            FeedBarCentre(title: title, isOverContent: isOverContent, pill: pill)
        }
        .backportSharedBackgroundVisibility(.hidden)
    }
}

/// The title, or the pill in its place, each fading into the other.
private struct FeedBarCentre: View {
    let title: String
    let isOverContent: Bool
    let pill: FeedBarPill?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let pill {
                FeedBarPillButton(pill: pill)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
            } else {
                FeedBarTitleLabel(title: title, isOverContent: isOverContent)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.3, bounce: 0), value: pill?.title)
    }
}

/// The existing accent fill: `glassProminent` draws no glass in a principal toolbar item (tried on iOS 27), and 346 rules
/// out tinting it by hand. The words go down to the arrow and the count when the bar has no room for them; VoiceOver always
/// gets the words.
private struct FeedBarPillButton: View {
    let pill: FeedBarPill

    var body: some View {
        Button(action: pill.action) {
            ViewThatFits(in: .horizontal) {
                label(pill.title)
                label(pill.count)
            }
            .font(.compound.bodySMSemibold)
            .foregroundStyle(.compound.textOnSolidPrimary)
            .frame(minHeight: CompoundDesignTokens.space11X) // A 44 pt target around the capsule.
            .contentShape(.rect)
        }
        .buttonStyle(FeedPressButtonStyle())
        .accessibilityLabel(pill.title)
        .accessibilityIdentifier(A11yIdentifiers.feedScreen.newPostsPill)
    }

    private func label(_ text: String) -> some View {
        // Not a `Label`: a toolbar draws one as its icon alone.
        HStack(spacing: CompoundDesignTokens.space1_5X) {
            CompoundIcon(\.arrowUp, size: .xSmall, relativeTo: .compound.bodySMSemibold)
            Text(text)
                .lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, CompoundDesignTokens.space4X)
        .padding(.vertical, CompoundDesignTokens.space2X)
        .background(.compound.bgActionPrimaryRest, in: .capsule)
    }
}

/// iOS gives a principal item no shared glass of its own, so the label takes `glassEffect` itself (346), and `.identity`
/// at rest, which lets the glass form and melt with the transition. Before iOS 26 the bar is opaque and needs none.
private struct FeedBarTitleLabel: View {
    let title: String
    let isOverContent: Bool

    var body: some View {
        if #available(iOS 26, *) {
            label
                // The glass's own primary, which turns light or dark with what's under it.
                .foregroundStyle(.primary)
                .padding(.horizontal, CompoundDesignTokens.space4X)
                .frame(minHeight: CompoundDesignTokens.space11X)
                .glassEffect(isOverContent ? .regular : .identity, in: .capsule)
        } else {
            label
                .foregroundStyle(.compound.textPrimary)
        }
    }

    private var label: some View {
        Text(title)
            .font(.compound.bodyLGSemibold)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Answers on touch down, and settles on release.
struct FeedPressButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.2, bounce: 0), value: configuration.isPressed)
    }
}

/// A post's time, short enough to share the name's line. The system's own words in all 41 languages.
struct FeedShortTime: View {
    let date: Date

    var body: some View {
        Text(date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel(Text(date, format: .relative(presentation: .numeric, unitsStyle: .wide)))
    }
}

/// A row's title with its time: on one line, the time trailing; stacked, the time under the title, as Chats' rows are at
/// accessibility sizes, where the time beside it crushed the title to a letter a line.
struct FeedTitleAndTime<Title: View, Time: View>: View {
    let isStacked: Bool
    @ViewBuilder let title: Title
    @ViewBuilder let time: Time

    var body: some View {
        if isStacked {
            VStack(alignment: .leading, spacing: CompoundDesignTokens.space0_5X) {
                title
                time
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: CompoundDesignTokens.space2X) {
                title
                Spacer(minLength: 0)
                time
            }
        }
    }
}
