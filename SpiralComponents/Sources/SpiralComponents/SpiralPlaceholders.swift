//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SFSafeSymbols
import SwiftUI

/// List rows' stand-ins for a `SpiralPreloader`, where there's no row to redact: a leading circle (an
/// avatar or an icon), a title and an optional second line, at Compound's row padding, with dividers.
public struct SpiralPlaceholderRows: View {
    /// What leads each row.
    public enum Leading {
        /// Nothing: text only.
        case none
        /// An icon's circle, as in a list row with an icon.
        case icon
        /// An avatar's circle of this size, in points: a step of `SpiralAvatarSize`.
        case avatar(CGFloat)
    }

    // Lengths in characters, cycled so that the rows don't read as one stamp.
    private static let titleLengths = [18, 13, 21, 15]
    private static let subtitleLengths = [27, 20, 31, 23]

    @ScaledMetric(relativeTo: .body) private var iconSize = 24

    private let count: Int
    private let leading: Leading
    private let hasSubtitle: Bool

    public init(count: Int, leading: Leading = .none, hasSubtitle: Bool = true) {
        self.count = count
        self.leading = leading
        self.hasSubtitle = hasSubtitle
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                row(index)
                if index < count - 1 {
                    Divider()
                        .padding(.leading, ListRowPadding.horizontal)
                }
            }
        }
    }

    private func row(_ index: Int) -> some View {
        HStack(spacing: CompoundDesignTokens.space3X) {
            switch leading {
            case .none:
                EmptyView()
            case .icon:
                PlaceholderCircle(size: iconSize)
            case .avatar(let size):
                PlaceholderCircle(size: size)
            }

            VStack(alignment: .leading, spacing: CompoundDesignTokens.space1X) {
                PlaceholderLine(characters: Self.titleLengths[index % Self.titleLengths.count], font: .compound.bodyLG)
                if hasSubtitle {
                    PlaceholderLine(characters: Self.subtitleLengths[index % Self.subtitleLengths.count], font: .compound.bodyMD)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(ListRowPadding.insets)
    }
}

/// A paragraph's stand-in for a `SpiralPreloader`: full lines, then a shorter one.
public struct SpiralPlaceholderLines: View {
    private let count: Int

    public init(count: Int) {
        self.count = count
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space2X) {
            ForEach(0..<count, id: \.self) { index in
                // A full line is cut at the edge; the last one stops short.
                PlaceholderLine(characters: index == count - 1 ? 18 : 60, font: .compound.bodyLG)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A switch's stand-in for a `SpiralPreloader`, for a setting whose value isn't known: a plain capsule, which reads as
/// neither on nor off, as a redacted `Toggle` might not. It takes the place a `ListRow`'s `.toggle` gives its switch.
public struct SpiralPlaceholderToggle: View {
    public init() { }

    public var body: some View {
        // The hidden switch gives the capsule the system's size on each iOS.
        Toggle("", isOn: .constant(false))
            .toggleStyle(.compound)
            .labelsHidden()
            .hidden()
            .overlay {
                Image(systemSymbol: .capsuleFill)
                    .resizable()
                    .clipShape(Capsule())
            }
            .padding(.vertical, -10) // As `ListRow`: a switch doesn't set the row's height.
    }
}

/// A line of text that redaction draws as a bar, the way it draws Chats' rows. Its digits are never
/// shown and never read: a `SpiralPreloader` redacts them and stands one "Loading…" in for VoiceOver.
private struct PlaceholderLine: View {
    let characters: Int
    let font: Font

    var body: some View {
        Text(verbatim: String(repeating: "0", count: characters))
            .font(font)
            .lineLimit(1)
    }
}

/// A circle that redaction draws in its placeholder grey, the way it draws an avatar.
private struct PlaceholderCircle: View {
    let size: CGFloat

    var body: some View {
        Image(systemSymbol: .circleFill)
            .resizable()
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}
