//
// Copyright 2026 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// A small floating circular button used by the timeline to jump to either the bottom (newest
/// item) or to the read marker (NEW banner). Optionally displays a presence dot.
struct TimelineScrollButton: View {
    enum Direction {
        case down
        case up
    }
    
    let direction: Direction
    let isHidden: Bool
    let showsBadge: Bool
    let onLongPress: (() -> Void)?
    /// On the button itself: on the view around it, it would leave an element behind while the button is hidden.
    let accessibilityIdentifier: String?
    let callback: () -> Void
    
    @ScaledMetric(relativeTo: .compound.headingLG) private var badgeDotSize: CGFloat = 12
    @GestureState private var isPressing = false
    /// Set when a long-press is recognized so the trailing touch-up doesn't also fire `callback()`.
    @State private var consumedByLongPress = false
    
    // AGENT-PLATFORM (Brief 0083): a 44 pt circle at the default text size, iOS's smallest target. Element's was 36.
    /// Padding around the chevron, balanced so the total circle stays 44pt at default text size.
    private let iconPadding: CGFloat = 10
    
    /// AGENT-PLATFORM (Brief 0083, question 359): the dot says this to VoiceOver too.
    var accessibilityValueText: String {
        showsBadge ? L10n.a11yNotificationsNewMessages : ""
    }
    
    /// Vertical offset that half-centers the badge dot on the circle's edge. Magnitude is half
    /// the dot's diameter so half sits inside the circle, half outside. Sign is applied at the
    /// call site based on direction.
    private var badgeOffsetMagnitude: CGFloat {
        badgeDotSize / 2
    }
    
    init(direction: Direction = .down,
         isHidden: Bool = false,
         showsBadge: Bool = false,
         onLongPress: (() -> Void)? = nil,
         accessibilityIdentifier: String? = nil,
         callback: @escaping () -> Void) {
        self.direction = direction
        self.isHidden = isHidden
        self.showsBadge = showsBadge
        self.onLongPress = onLongPress
        self.accessibilityIdentifier = accessibilityIdentifier
        self.callback = callback
    }
    
    var body: some View {
        if let onLongPress {
            buttonContent
                .scaleEffect(isPressing ? 1.05 : 1.0)
                .compositingGroup()
                .shadow(color: .black.opacity(isPressing ? 0.2 : 0), radius: isPressing ? 12 : 0)
                .animation(.spring(response: 0.7), value: isPressing)
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.5)
                    .updating($isPressing) { current, state, _ in state = current }
                    .onEnded { _ in
                        consumedByLongPress = true
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        onLongPress()
                    })
                .simultaneousGesture(DragGesture(minimumDistance: 0)
                    .onEnded { _ in
                        // Touch-up signal. Defer the clear so the Button's tap action — which
                        // also fires on touch-up when the release was on-button — reads the
                        // flag while it's still set and suppresses the unwanted callback.
                        Task { @MainActor in consumedByLongPress = false }
                    })
        } else {
            buttonContent
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, question 357): hidden, the button leaves the tree, as accessibility still listed it at
    // zero opacity; the hidden icon keeps its place for the button stacked above it.
    private var buttonContent: some View {
        ZStack {
            icon.hidden()
            if !isHidden {
                button
                    .transition(.opacity)
            }
        }
        .animation(.elementDefault, value: isHidden)
    }
    
    private var button: some View {
        Button {
            if consumedByLongPress {
                consumedByLongPress = false
                return
            }
            callback()
        } label: {
            ZStack(alignment: direction == .down ? .bottom : .top) {
                icon
                if showsBadge {
                    badge
                        .offset(y: direction == .down ? badgeOffsetMagnitude : -badgeOffsetMagnitude)
                }
            }
        }
        .accessibilityLabel(direction == .down ? L10n.a11yJumpToBottom : L10n.a11yJumpToUnread)
        .accessibilityValue(accessibilityValueText)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
    
    @ViewBuilder
    private var icon: some View {
        let chevron = CompoundIcon(direction == .down ? \.chevronDown : \.chevronUp,
                                   size: .medium,
                                   relativeTo: .compound.headingLG)
            .foregroundStyle(.compound.iconPrimary)
            .scaledPadding(iconPadding, relativeTo: .compound.headingLG)
        if #available(iOS 26, *) {
            // AGENT-PLATFORM (Brief 0083): the glass draws its own edge, as the bar's buttons do; no outline over it.
            chevron
                .glassEffect(.regular, in: Circle())
        } else {
            chevron
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(Color.compound.borderInteractiveSecondary, lineWidth: 1))
        }
    }
    
    private var badge: some View {
        Circle()
            .fill(Color.compound.iconAccentPrimary)
            .frame(width: badgeDotSize, height: badgeDotSize)
    }
}

struct TimelineScrollButton_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        VStack(spacing: 16) {
            TimelineScrollButton(direction: .down) { }
            TimelineScrollButton(direction: .down, showsBadge: true) { }
            TimelineScrollButton(direction: .up) { }
            TimelineScrollButton(direction: .up, showsBadge: true) { }
            TimelineScrollButton(direction: .up, isHidden: true, showsBadge: true) { }
        }
        .padding()
        .background(Color.compound.bgCanvasDefault)
        .previewLayout(.sizeThatFits)
    }
}
