//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SFSafeSymbols
import SpiralTokens
import SwiftUI

/// What a screen shows when it has nothing to show: nothing yet, no search results, nothing found, or a
/// load that failed. The system's `ContentUnavailableView` in Compound's type and colours: an SF Symbol,
/// a title, an optional message and an optional action.
///
/// In a list it takes a section of its own, so that it scrolls with the list at large text sizes:
///
///     Section {
///         SpiralEmptyState(symbol: .bell, title: title, message: message)
///             .listRowBackground(Color.clear)
///     }
///
/// As a whole screen's content it goes in `centredInScrollView()`.
public struct SpiralEmptyState: View {
    /// The one button an empty state offers, Compound's primary.
    public struct Action {
        let title: String
        let perform: () -> Void

        public init(_ title: String, perform: @escaping () -> Void) {
            self.title = title
            self.perform = perform
        }
    }

    /// How much room the state takes.
    public enum Size {
        /// The state is what the screen or the list is about.
        case regular
        /// The state is one part of a populated screen: a headline and a small symbol.
        case compact
    }

    private let symbol: SFSymbol
    private let title: String
    private let message: String?
    private let action: Action?
    private let size: Size
    private let isOnChatBackground: Bool

    /// - Parameter isOnChatBackground: the state sits straight on the room's background picture (Mist), where Compound's
    ///   greys read 3.5:1 at its darkest; the symbol and the message take the picture's own quiet ink instead.
    public init(symbol: SFSymbol, title: String, message: String? = nil, action: Action? = nil, size: Size = .regular,
                isOnChatBackground: Bool = false) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.action = action
        self.size = size
        self.isOnChatBackground = isOnChatBackground
    }

    private var symbolColour: Color {
        isOnChatBackground ? .spiral.chatBackgroundTextSecondary : .compound.iconSecondary
    }

    public var body: some View {
        switch size {
        case .regular:
            regular
        case .compact:
            compact
        }
    }

    private var regular: some View {
        ContentUnavailableView {
            Label {
                Text(title)
                    .font(.compound.headingMDBold)
                    .foregroundStyle(.compound.textPrimary)
            } icon: {
                Image(systemSymbol: symbol)
                    .foregroundStyle(symbolColour)
            }
        } description: {
            if let message {
                messageText(message)
            }
        } actions: {
            actionButton
                // Without a message the system leaves 8 pt under the title, which ties the button to it.
                .padding(.top, message == nil ? CompoundDesignTokens.space2X : 0)
        }
    }

    /// `ContentUnavailableView` sizes its symbol and its spacing for a whole screen, whatever the font.
    private var compact: some View {
        VStack(spacing: CompoundDesignTokens.space2X) {
            Image(systemSymbol: symbol)
                .font(.compound.headingMD)
                .foregroundStyle(symbolColour)
                .accessibilityHidden(true)

            VStack(spacing: CompoundDesignTokens.space1X) {
                Text(title)
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(.compound.textPrimary)

                if let message {
                    messageText(message)
                }
            }

            actionButton
                .padding(.top, CompoundDesignTokens.space1X)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(CompoundDesignTokens.space6X)
    }

    private func messageText(_ message: String) -> some View {
        // The system's secondary grey reads 3.3:1 on a grouped list's background in light; this is 4.7:1.
        Text(message)
            .font(.compound.bodyMD)
            .foregroundStyle(isOnChatBackground ? .spiral.chatBackgroundTextSecondary : .compound.textSecondary)
    }

    @ViewBuilder
    private var actionButton: some View {
        if let action {
            Button(action.title, action: action.perform)
                .buttonStyle(.compound(.primary, size: .medium))
        }
    }
}

public extension View {
    /// A whole screen's empty state: centred while it fits, and scrolling when it doesn't, so that at
    /// the largest text sizes its action never ends up under a tab bar.
    func centredInScrollView() -> some View {
        GeometryReader { geometry in
            ScrollView {
                frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
