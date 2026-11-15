//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SwiftUI

/// The head of a full-screen step on the identity path, as on identity confirmation and the invitation sheet
/// (Brief 0083, decisions 308 and 313): a small icon, a large title and an optional sentence, all leading. It takes
/// the place of Element's centred icon tile and title.
public struct SpiralDialogHeader<Title: View>: View {
    private let icon: KeyPath<CompoundIcons, Image>
    private let tone: SpiralDialogTone
    private let message: String?
    private let title: Title

    /// A header whose title is a view of its own, for a title that carries its own modifiers, such as an
    /// identifier or accessibility focus. The header gives it its font, colour and header trait.
    public init(icon: KeyPath<CompoundIcons, Image>, tone: SpiralDialogTone = .accent, message: String? = nil, @ViewBuilder title: () -> Title) {
        self.icon = icon
        self.tone = tone
        self.message = message
        self.title = title()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CompoundIcon(icon, size: .custom(32), relativeTo: .compound.headingLG)
                .foregroundStyle(iconColor)
                .padding(.bottom, CompoundDesignTokens.space3X)
                .accessibilityHidden(true)

            title
                .font(.compound.headingLGBold)
                .foregroundStyle(.compound.textPrimary)
                .accessibilityAddTraits(.isHeader)

            if let message {
                Text(message)
                    .font(.compound.bodyLG)
                    .foregroundStyle(.compound.textSecondary)
                    .padding(.top, CompoundDesignTokens.space2X)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iconColor: Color {
        switch tone {
        case .accent: .compound.iconAccentPrimary
        case .success: .compound.iconSuccessPrimary
        case .critical: .compound.iconCriticalPrimary
        }
    }
}

public extension SpiralDialogHeader where Title == Text {
    init(icon: KeyPath<CompoundIcons, Image>, tone: SpiralDialogTone = .accent, title: String, message: String? = nil) {
        self.init(icon: icon, tone: tone, message: message) {
            Text(title)
        }
    }
}

/// What the colour of a `SpiralDialogHeader`'s icon says.
public enum SpiralDialogTone {
    /// A step on the way.
    case accent
    /// The step worked.
    case success
    /// The step failed, or what follows can't be undone.
    case critical
}
