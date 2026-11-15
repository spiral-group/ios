//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SpiralTokens
import SwiftUI

/// A card of rows on a screen's canvas, as identity confirmation's methods (Brief 0083, decisions 308 and 313):
/// Spiral's grey fill and the list card's radius. Compound's `ListRow` needs a `List`, which paints white rows and
/// can't sit among a screen's other content. Its rows are `SpiralCardRow`s, or content of the screen's own.
public struct SpiralCard<Content: View>: View {
    /// What the card sits on.
    public enum Surface {
        /// A screen's canvas: the card is grey.
        case canvas
        /// A grouped sheet's `bgSubtleSecondaryLevel0`, as a message's menu: the card is white in light and
        /// #1C1C1E in dark, iOS's grouped list. Red text keeps 4.5:1 on it in dark, where the grey is 3.99:1.
        case groupedSheet
    }

    private let surface: Surface
    private let content: Content

    public init(on surface: Surface = .canvas, @ViewBuilder content: () -> Content) {
        self.surface = surface
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: shape)
        .clipShape(shape)
    }

    private var fill: Color {
        switch surface {
        case .canvas: .compound.bgSubtleSecondary
        case .groupedSheet: .compound.bgSubtlePrimary
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SpiralRadius.listCard, style: .continuous)
    }
}

/// A row of a `SpiralCard`: an optional icon, the row's own content, and a separator under the content when
/// another row follows, at Compound's row padding. As a button's label it takes `.buttonStyle(.spiralCardRow)`.
public struct SpiralCardRow<Content: View>: View {
    private let icon: KeyPath<CompoundIcons, Image>?
    private let iconColor: Color
    private let showsSeparator: Bool
    private let content: Content

    public init(icon: KeyPath<CompoundIcons, Image>? = nil,
                iconColor: Color = .compound.iconAccentPrimary,
                showsSeparator: Bool = false,
                @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.iconColor = iconColor
        self.showsSeparator = showsSeparator
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: ListRowPadding.labelIconSpacing) {
            if let icon {
                CompoundIcon(icon)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, CompoundDesignTokens.space4X)
                .padding(.vertical, CompoundDesignTokens.space3X)
                .frame(minHeight: CompoundDesignTokens.space16X)
                .overlay(alignment: .bottom) {
                    if showsSeparator {
                        SpiralCardSeparator(leadingInset: 0)
                    }
                }
        }
        .padding(.leading, CompoundDesignTokens.space4X)
        .contentShape(Rectangle())
    }
}

/// The hairline between two rows of a `SpiralCard`, inset from the leading edge to where the row's text starts,
/// as iOS's lists inset theirs.
public struct SpiralCardSeparator: View {
    private let leadingInset: CGFloat

    public init(leadingInset: CGFloat = CompoundDesignTokens.space4X) {
        self.leadingInset = leadingInset
    }

    public var body: some View {
        Divider()
            .overlay(Color.compound.borderInteractiveSecondary)
            .padding(.leading, leadingInset)
    }
}

public extension ButtonStyle where Self == SpiralCardRowButtonStyle {
    /// A row of a `SpiralCard` that is a button: the row darkens while pressed.
    static var spiralCardRow: SpiralCardRowButtonStyle {
        SpiralCardRowButtonStyle()
    }
}

public struct SpiralCardRowButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.compound.bgActionSecondaryPressed : .clear)
    }
}
