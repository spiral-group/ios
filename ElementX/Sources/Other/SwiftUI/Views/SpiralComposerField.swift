//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SwiftUI

// AGENT-PLATFORM (Brief 0083): Spiral's one composer field, drawn as Messages draws its own. The room's composer
// (`MessageComposer`, and its voice message recorder and preview), a post's comments (`FeedCommentComposer`) and a
// media caption (`MediaUploadPreviewScreen`) type into it: a capsule at one line that keeps its ends as it grows, a
// header above the text for a reply or an edit, and the field's action (send, the microphone) inside its trailing end.

extension View {
    /// Draws the view as the content of Spiral's composer field.
    ///
    /// - Parameters:
    ///   - header: Shown above the content, such as the message being replied to: a ``SpiralComposerHeader``.
    ///   - trailing: The field's action, inside its trailing end and level with the last line. Size it with
    ///     ``spiralComposerAction()``.
    ///   - insetsContent: Whether the content is text, inset to sit centred on one line. A row of controls, such as
    ///     a voice message's player, passes `false`: it is centred in the field, its leading control near the end.
    func messageComposerStyle(header: some View = EmptyView(),
                              trailing: some View = EmptyView(),
                              insetsContent: Bool = true) -> some View {
        modifier(SpiralComposerFieldModifier(header: header, trailing: trailing, insetsContent: insetsContent))
    }

    /// Sizes a glyph as the composer field's action, 36 pt with Liquid Glass and 32 pt before it, tapped in 44 pt: the
    /// target reaches into the field's inset round it, and the look stays the glyph's size.
    func spiralComposerAction() -> some View {
        let hitPadding = (CompoundDesignTokens.space11X - SpiralComposerMetrics.actionSize) / 2
        return scaledFrame(size: SpiralComposerMetrics.actionSize, relativeTo: .compound.headingLG)
            .padding(hitPadding)
            .contentShape(.rect)
            .padding(-hitPadding)
    }

    /// The bar a composer sits on: the canvas with Liquid Glass, and iOS 18's bar material under a divider before it.
    ///
    /// - Parameter scrollsUnder: Whether a timeline scrolls under the bar (decision 334): with Liquid Glass the bar
    ///   is then clear, the glass composer over the timeline.
    func spiralComposerBar(scrollsUnder: Bool = false) -> some View {
        background {
            if Compound.supportsGlass {
                if !scrollsUnder {
                    Color.compound.bgCanvasDefault.ignoresSafeArea()
                }
            } else {
                Rectangle()
                    .fill(.bar)
                    .overlay(alignment: .top) { Divider() }
                    .ignoresSafeArea()
            }
        }
    }
}

// AGENT-PLATFORM (Brief 0083, decision 334): with Liquid Glass a timeline scrolls under its composer, as Messages'
// does. Before it the composer stays an inset on iOS 18's opaque bar.
extension View {
    /// Places a timeline's composer at the bottom: a clear bar with Liquid Glass, an inset before
    /// it. With Liquid Glass the timeline learns the bar's height
    /// (`timelineComposerBarHeight`), as a hosted table isn't told about a SwiftUI bar's part of the safe area.
    /// - Parameter floating: What floats just above the bar, over the timeline. It lives here as a system bar takes
    ///   no touch outside its own bounds: drawn from inside the bar it would show, and the touch would reach the timeline.
    func timelineComposerBar(@ViewBuilder content: () -> some View,
                             @ViewBuilder floating: () -> some View) -> some View {
        modifier(TimelineComposerBarModifier(bar: content(), floating: floating()))
    }
    
    /// Lets a timeline run under its composer's bar with Liquid Glass. Its table takes the bar's height as an inset.
    @ViewBuilder
    func timelineUnderComposerBar() -> some View {
        if Compound.supportsGlass {
            ignoresSafeArea(.container, edges: .bottom)
        } else {
            self
        }
    }
}

// AGENT-PLATFORM (Brief 0083, decision 344): the room's header is transparent as its composer's bar is, the timeline
// scrolling under the glass capsule and buttons. Before Liquid Glass it's iOS 18's opaque bar.
extension View {
    /// Lets a timeline run under its header with Liquid Glass, the system's scroll edge effect blurring it there. Its
    /// table takes the safe area's top as an inset, so the oldest message clears the header at rest. Off, the timeline
    /// stops at the header: VoiceOver stacks the banners in an inset the table isn't told about. One view either way:
    /// a branch here would rebuild the table when VoiceOver toggles and lose the scroll position.
    func timelineUnderHeader(isEnabled: Bool) -> some View {
        ignoresSafeArea(.container, edges: Compound.supportsGlass && isEnabled ? .top : [])
    }
    
    /// The bar behind a timeline's header: clear with Liquid Glass, the canvas before it. The system's bar lets the picture
    /// through, and the accent on it reads 2.83:1.
    @ViewBuilder
    func timelineHeaderBackground() -> some View {
        if Compound.supportsGlass {
            self
        } else {
            toolbarBackground(Color.compound.bgCanvasDefault, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar) // Fix the toolbar's background.
        }
    }
}

extension EnvironmentValues {
    /// The height of the composer's bar a timeline runs under, with Liquid Glass; zero before it.
    @Entry var timelineComposerBarHeight: CGFloat = 0
    /// The height of the block floating under a room's header; zero without one.
    @Entry var timelineHeaderBlockHeight: CGFloat = 0
}

private struct TimelineComposerBarModifier<Bar: View, Floating: View>: ViewModifier {
    let bar: Bar
    let floating: Floating
    @State private var barHeight: CGFloat = 0
    
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .environment(\.timelineComposerBarHeight, barHeight)
                .overlay(alignment: .bottom) { floating }
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    bar.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
                }
        } else {
            content
                .overlay(alignment: .bottom) { floating }
                .safeAreaInset(edge: .bottom, spacing: 0) { bar }
        }
    }
}

enum SpiralComposerMetrics {
    /// The field's height at one line of text, before Dynamic Type: 44 pt with Liquid Glass, as the buttons beside it
    /// are, and 40 pt before it.
    static var fieldHeight: CGFloat {
        Compound.supportsGlass ? CompoundDesignTokens.space11X : CompoundDesignTokens.space10X
    }

    /// The field's action, inset by the same space all round so it is concentric with the field's end.
    static var actionSize: CGFloat {
        Compound.supportsGlass ? CompoundDesignTokens.space9X : CompoundDesignTokens.space8X
    }

    static let actionInset = CompoundDesignTokens.space1X
    
    /// One line of the composer's text, `bodyLG`, at the default text size.
    static let lineHeight: CGFloat = 22

    /// A placeholder's colour in every composer field: `textDisabled` read 2.21:1, and iOS's own placeholder less than 3:1.
    static var placeholder: Color {
        .compound.textSecondary
    }
    
    /// A chat's composer: its glass takes the blue of the picture under it, where grey reads 3.5:1 in light and 3.76:1 in dark.
    static var chatPlaceholder: Color {
        Compound.supportsGlass ? .compound.textPrimary.opacity(0.75) : placeholder
    }
}

/// A composer field's header, such as the message being replied to: the timeline's quote, a translucent block without
/// an outline, inset from the field's edges as its action is and concentric with its corners, with the close button
/// inside it.
struct SpiralComposerHeader<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var fieldHeight = SpiralComposerMetrics.fieldHeight
    
    let closeLabel: String
    let close: () -> Void
    @ViewBuilder let content: Content
    
    /// About 6 % ink on the grey field, a little more in dark where the field is darker.
    private var fill: Color {
        .compound.textPrimary.opacity(colorScheme == .dark ? 0.1 : 0.06)
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: CompoundDesignTokens.space2X) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            
            SpiralComposerHeaderCloseButton(action: close)
                .accessibilityLabel(closeLabel)
        }
        .padding(.leading, CompoundDesignTokens.space3X)
        .padding(.trailing, CompoundDesignTokens.space2X)
        .padding(.vertical, CompoundDesignTokens.space2X)
        .background(fill, in: RoundedRectangle(cornerRadius: fieldHeight / 2 - SpiralComposerMetrics.actionInset,
                                               style: .continuous))
        .padding([.top, .horizontal], SpiralComposerMetrics.actionInset)
    }
}

/// A header's close button: the glyph's look, with a 44 pt target that doesn't take the header's room.
private struct SpiralComposerHeaderCloseButton: View {
    let action: () -> Void
    
    private let targetPadding = (CompoundDesignTokens.space11X - CompoundDesignTokens.space5X) / 2
    
    var body: some View {
        Button(action: action) {
            CompoundIcon(\.close, size: .small, relativeTo: .compound.bodySMSemibold)
                .foregroundStyle(.compound.iconSecondary)
                .padding(targetPadding)
                .contentShape(Rectangle())
        }
        .padding(-targetPadding)
    }
}

/// A capsule at the field's one-line height that keeps the radius of its ends as the field grows taller.
nonisolated struct SpiralComposerFieldShape: InsettableShape {
    let endRadius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        return RoundedRectangle(cornerRadius: min(endRadius - insetAmount, insetRect.height / 2), style: .continuous)
            .path(in: insetRect)
    }

    func inset(by amount: CGFloat) -> Self {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

private struct SpiralComposerFieldModifier<Header: View, Trailing: View>: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var height = SpiralComposerMetrics.fieldHeight

    let header: Header
    let trailing: Trailing
    let insetsContent: Bool

    private var hasTrailing: Bool {
        Trailing.self != EmptyView.self
    }

    private var shape: SpiralComposerFieldShape {
        SpiralComposerFieldShape(endRadius: height / 2)
    }

    /// Centres one line of text in the field.
    private var textInset: CGFloat {
        insetsContent ? (SpiralComposerMetrics.fieldHeight - SpiralComposerMetrics.lineHeight) / 2 : 0
    }

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if isEnabled {
                field(content)
                    .snapshotableGlassEffect(.regular.interactive(),
                                             snapshotBackground: .compound.bgSubtleSecondary,
                                             in: shape)
            } else {
                // Spiral's bgSubtlePrimary is the canvas white in light mode: disabled is the enabled field's grey
                // without the glass, its placeholder and action drawn in textDisabled.
                field(content)
                    .background(.compound.bgSubtleSecondary, in: shape)
            }
        } else {
            // The storyboard's iOS 18 composer (RP-ios18): white on the bar, under a hairline.
            field(content)
                .background {
                    shape.fill(.compound.bgCanvasDefault)
                    shape.strokeBorder(.compound.borderInteractiveSecondary, lineWidth: 0.5)
                }
        }
    }

    private func field(_ content: Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            HStack(alignment: .bottom, spacing: CompoundDesignTokens.space1X) {
                content
                    .tint(.compound.iconAccentTertiary)
                    .scaledPadding(.vertical, textInset, relativeTo: .compound.bodyLG)
                    .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)

                // The inset grows with the text, so a large action stays clear of the field's end.
                trailing
                    .scaledPadding(SpiralComposerMetrics.actionInset, relativeTo: .compound.bodyLG)
            }
            .padding(.leading, insetsContent ? CompoundDesignTokens.space4X : CompoundDesignTokens.space2X)
            .padding(.trailing, hasTrailing ? 0 : CompoundDesignTokens.space4X)
        }
        .clipShape(shape)
    }
}
