//
// Copyright 2026 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0063): the minimized call bar (`09 · Minimized call`).

import Compound
import SpiralTokens
import SwiftUI

/// G9 — the minimized call bar (`09 · Minimized call`), at the very top of the app: one centred line under the status
/// bar with the call's name, the live timer and REC, the green running up behind the status bar (decision 344). It
/// exists so a call — and a running recording — never drops out of sight; treat it as a disclosure surface, not chrome.
///
/// The wave across the bar is its live mark (question 383): no glyph before the name, whose small circle only repeated
/// the wave. The wave settles rather than disappears, so silence still looks like a call.
struct NativeCallBar: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context

    /// The words' width: the ribbon keeps out of it.
    @State private var textWidth: CGFloat = 0

    var body: some View {
        Button { context.send(viewAction: .expand) } label: {
            HStack(spacing: 8) {
                Text(context.viewState.roomName)
                    .lineLimit(1)

                // An ended call must not keep ticking (audit C8): the bar
                // outlives the full screen while minimized, and a live timer
                // on a dead call was the lie that made the failed-while-
                // minimized state look healthy.
                Group {
                    if case let .ended(status) = context.viewState.callState {
                        Text(status)
                    } else if let connectedAt = context.viewState.callConnectedAt {
                        Text(connectedAt, style: .timer)
                            .monospacedDigit()
                    }
                }
                .lineLimit(1)
                .layoutPriority(1)

                // Question 383: muted is a state you can talk into from the chat list without knowing.
                if !context.viewState.isMicrophoneEnabled, !isEnded {
                    Image(systemName: "mic.slash.fill")
                        .font(.compound.bodyXSSemibold)
                        .accessibilityLabel(UntranslatedL10n.a11yNativeCallParticipantMuted)
                }

                if context.viewState.isRecording {
                    Text(UntranslatedL10n.screenNativeCallRecordingBadge)
                        .font(.compound.bodyXSSemibold)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            .font(.compound.bodySMSemibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
            .background { NativeCallBarRibbon(textWidth: textWidth) }
            // The green runs up behind the status bar, the way the
            // system's own in-call bar does. It is the fill white reads on
            // in both themes (decision 307), not the success icon colour.
            .background(Color.spiral.successFill.ignoresSafeArea(edges: .top))
            .background(CallBarStatusBarAnchor())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UntranslatedL10n.a11yNativeCallBar(context.viewState.roomName))
        .accessibilityValue(context.viewState.isMicrophoneEnabled ? "" : UntranslatedL10n.a11yNativeCallParticipantMuted)
    }

    private var isEnded: Bool {
        if case .ended = context.viewState.callState { return true }
        return false
    }
}

// MARK: - Previews

struct NativeCallBar_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview { // AGENT-PLATFORM (Brief 0083): Spiral's gates
    static let viewModel = NativeCallScreen_Previews.makeAgentViewModel()

    static var previews: some View {
        NativeCallBar(context: viewModel.context)
            .previewDisplayName("Recording with agent")
    }
}
