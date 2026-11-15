//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, decision 300a, question 357): everything you send is blue, with white on it, and what draws
// on an own bubble reads one ink from the environment.
//

import Compound
import SpiralTokens
import SwiftUI

/// The colours of an own message's bubble (decision 300a).
enum OwnBubbleStyle {
    /// The own-bubble token: `#2E6BE6` in both themes, under which white reads 4.81:1.
    static var fill: Color {
        .spiral.ownBubble
    }

    /// Text, links, icons, the time and the ticks drawn on the fill.
    static var content: Color {
        .compound.textOnSolidPrimary
    }
}

/// Everything a view on an own bubble colours itself with. A bubble with no ink is an incoming one, or one that failed content
/// scanning, and its parts keep their own colours.
struct OwnBubbleInk: Equatable {
    /// The bubble's fill: none is a bubble drawn by its `outline` alone.
    var fill: Color?
    var outline: Color?
    var text: Color
    var secondaryText: Color
    var secondaryIcon: Color
    var link: Color
    var quoteFill: Color
    /// The disc behind a red status mark, where the fill alone would swallow it.
    var criticalMarkDisc: Color?
    /// The strongest thing on the bubble, what can be pressed: a file's badge, the play button, a poll's action.
    var strongFill: Color
    var onStrongFill: Color
    /// The voice message's speed, beside the play button.
    var chipFill: Color
    var onChipFill: Color
    var waveformPlayed: Color
    var waveformRest: Color
    var waveformCursor: Color
    /// A poll's bar, and the track under it. A bar that lost when the poll ended takes `pollLostBar`.
    var pollBar: Color
    var pollLostBar: Color
    var pollTrack: Color
    /// A poll's marks: the chosen answer and the winner's, and an answer not chosen.
    var pollMark: Color
    var pollIdleMark: Color
}

extension OwnBubbleInk {
    /// White on the blue fill, where what can be pressed is white with the fill's blue in it.
    static let solid = OwnBubbleInk(fill: OwnBubbleStyle.fill,
                                    text: OwnBubbleStyle.content,
                                    secondaryText: OwnBubbleStyle.content,
                                    secondaryIcon: OwnBubbleStyle.content,
                                    link: OwnBubbleStyle.content,
                                    // A white tint would leave white text under 4.5:1 (3.52:1 at 18 %), so it darkens the blue (6.22:1).
                                    quoteFill: .black.opacity(0.15),
                                    criticalMarkDisc: OwnBubbleStyle.content,
                                    strongFill: OwnBubbleStyle.content,
                                    onStrongFill: OwnBubbleStyle.fill,
                                    chipFill: .black.opacity(0.15), // White text on it reads 6.22:1, as on the quote.
                                    onChipFill: OwnBubbleStyle.content,
                                    waveformPlayed: OwnBubbleStyle.content,
                                    // No rest shade reaches 3:1 against both the blue fill and the played
                                    // white. 45 % splits it (2.16:1 to the fill, 2.22:1 to played), so the
                                    // played part reads apart from the rest; the cursor and the elapsed time
                                    // mark the position too (operator, 2026-11-13).
                                    waveformRest: OwnBubbleStyle.content.opacity(0.45),
                                    waveformCursor: OwnBubbleStyle.content,
                                    pollBar: OwnBubbleStyle.content,
                                    pollLostBar: OwnBubbleStyle.content.opacity(0.5),
                                    pollTrack: OwnBubbleStyle.content.opacity(0.25),
                                    pollMark: OwnBubbleStyle.content,
                                    pollIdleMark: OwnBubbleStyle.content.opacity(0.75))
    
    /// No fill, so a message that can't be shown doesn't weigh what a real one does: the bubble's outline, and grey text
    /// on the canvas. Only the parts of such a message are coloured.
    static let hollow = {
        var ink = OwnBubbleInk.solid
        ink.fill = nil
        ink.outline = OwnBubbleStyle.fill.opacity(0.45)
        ink.text = .compound.textSecondary
        ink.secondaryText = .compound.textSecondary
        ink.secondaryIcon = .compound.iconSecondary
        ink.criticalMarkDisc = nil
        return ink
    }()
}

extension EnvironmentValues {
    /// The ink of the own bubble a view draws on, if it draws on one.
    /// A part with its own background, such as a pill or a code block, keeps its colours.
    @Entry var ownBubbleInk: OwnBubbleInk?
}

/// What a part of a message colours itself with, on a neutral bubble and on an own one.
enum BubbleForeground {
    case primary
    case secondary
    case secondaryIcon
    case fixed(Color)
    
    fileprivate func color(on ink: OwnBubbleInk?) -> Color {
        switch self {
        case .primary: ink?.text ?? .compound.textPrimary
        case .secondary: ink?.secondaryText ?? .compound.textSecondary
        case .secondaryIcon: ink?.secondaryIcon ?? .compound.iconSecondary
        case .fixed(let color): color
        }
    }
}

extension View {
    /// Draws in the bubble's colour for this part.
    ///
    /// A modifier reads the environment where it is applied: an item view's own `@Environment` is read
    /// outside the bubble, since `TimelineStyler` builds the bubble around the item's content.
    func bubbleForegroundStyle(_ foreground: BubbleForeground) -> some View {
        modifier(BubbleForegroundStyleModifier(foreground: foreground))
    }
}

extension View {
    /// The inset of a caption under a picture that reaches the bubble's edges.
    @ViewBuilder
    func pictureCaptionInsets(isActive: Bool) -> some View {
        if isActive {
            padding(EdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8))
        } else {
            self
        }
    }
}

private struct BubbleForegroundStyleModifier: ViewModifier {
    @Environment(\.ownBubbleInk) private var ownBubbleInk

    let foreground: BubbleForeground

    func body(content: Content) -> some View {
        content.foregroundStyle(foreground.color(on: ownBubbleInk))
    }
}
