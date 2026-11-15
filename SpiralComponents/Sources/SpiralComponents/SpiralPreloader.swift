//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SwiftUI

public extension EnvironmentValues {
    /// How long a `SpiralPreloader` waits before it shows. A preview of a loading state sets `.zero`,
    /// so that its snapshot shows what a slow load shows.
    @Entry var spiralPreloaderDelay: Duration = .milliseconds(250)

    /// Whether a `SpiralPreloader`'s placeholders shimmer. The app turns it off while it runs tests, as upstream
    /// turns off its own shimmer: an animation that repeats for ever never settles for a snapshot or an audit.
    @Entry var spiralPreloaderShimmers = true
}

/// Spiral's loading element (decision 330): grey placeholders in the shape of the content that will
/// appear, under a quiet shimmer.
///
/// Its content is the placeholders: real views with placeholder data, which SwiftUI redacts
/// (`.redacted(reason: .placeholder)`), or `SpiralPlaceholderRows` and `SpiralPlaceholderLines` where
/// there is no view to redact. It shows after a short delay, so a quick load shows nothing; Reduce
/// Motion stops the shimmer, and so do tests (`spiralPreloaderShimmers`); VoiceOver reads it as one
/// element, `label`, and never the shapes.
public struct SpiralPreloader<Content: View>: View {
    @Environment(\.spiralPreloaderDelay) private var delay
    @Environment(\.spiralPreloaderShimmers) private var shimmers
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasWaited = false

    private let label: String
    private let content: Content

    /// - Parameters:
    ///   - label: What VoiceOver reads for the whole preloader: `L10n.commonLoading`.
    ///   - content: The placeholders, in the layout of the content that will replace them.
    public init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    public var body: some View {
        placeholders
            .redacted(reason: .placeholder)
            .disabled(true)
            .opacity(hasWaited || delay == .zero ? 1 : 0)
            .accessibilityHidden(true)
            // One element, not the shapes. Its label is never drawn, so it sits on a point of its own: a `ProgressView`
            // keeps its own frame, and over the shapes the audit measured "Loading…" against them at 1.2–1.9:1.
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel(label)
            }
            .task {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                hasWaited = true
            }
    }

    @ViewBuilder
    private var placeholders: some View {
        if reduceMotion || !shimmers {
            content
        } else {
            content.modifier(SpiralShimmer())
        }
    }
}

public extension View {
    /// One slot of a page that already has its shape: while `isLoading`, this view, given placeholder data, stands in its
    /// own place as a `SpiralPreloader`, so the value fills the slot and nothing around it moves.
    ///
    /// - Parameters:
    ///   - isLoading: Whether the value is still unknown.
    ///   - label: What VoiceOver reads for the slot: `L10n.commonLoading`.
    func spiralLoadingSlot(_ isLoading: Bool, label: String) -> some View {
        modifier(SpiralLoadingSlot(isLoading: isLoading, label: label))
    }
}

private struct SpiralLoadingSlot: ViewModifier {
    let isLoading: Bool
    let label: String

    func body(content: Content) -> some View {
        if isLoading {
            SpiralPreloader(label: label) {
                content
            }
        } else {
            content
        }
    }
}

/// A slow highlight that sweeps across the placeholders now and then, dimming them a little under it.
private struct SpiralShimmer: ViewModifier {
    @State private var isSweeping = false

    func body(content: Content) -> some View {
        content
            .mask {
                // A mask: only the colours' opacity counts. Before and after a sweep the band is outside
                // the view, so a snapshot shows the placeholders evenly.
                LinearGradient(stops: [.init(color: .black, location: 0.35),
                                       .init(color: .black.opacity(0.6), location: 0.5),
                                       .init(color: .black, location: 0.65)],
                               startPoint: UnitPoint(x: isSweeping ? 1 : -1, y: 0.5),
                               endPoint: UnitPoint(x: isSweeping ? 2 : 0, y: 0.5))
            }
            .onAppear {
                withAnimation(.linear(duration: 1.6).delay(0.6).repeatForever(autoreverses: false)) {
                    isSweeping = true
                }
            }
    }
}
