//
// Copyright 2026 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0063): the minimized call bar (`09 · Minimized call`).

import Compound
import SwiftUI

/// G9 — the minimized call bar (`09 · Minimized call`): a green pill under
/// the status bar carrying the call's name, the live timer, the agent slot
/// and REC. It exists so a call — and a running recording — never drops out
/// of sight; treat it as a disclosure surface, not chrome. Everything
/// outside the pill is empty space, so the chat underneath stays tappable.
///
/// The wave is ALWAYS the bar's mark, at rest as much as in speech: swapping
/// it for a static glyph when nobody spoke made the bar read as an icon and
/// hid the one thing it is here to prove — that the call is still live. The
/// wave settles rather than disappears, so silence still looks like a call.
/// The subtitle stays a plain "tap to return": it used to narrate
/// "agent interpreting", which restated in words what the wave already
/// shows.
struct NativeCallBar: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context

    var body: some View {
        Button { context.send(viewAction: .expand) } label: {
            HStack(spacing: 8) {
                NativeCallVoiceWave(userID: nil, scale: .badge, slot: .onGreen)

                VStack(alignment: .leading, spacing: 0) {
                    Text(context.viewState.roomName)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)

                    Text(UntranslatedL10n.screenNativeCallBarReturn)
                        .font(.caption2)
                        .opacity(0.85)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if context.viewState.isRecording {
                    Text(UntranslatedL10n.screenNativeCallRecordingBadge)
                        .font(.caption2.weight(.bold))
                }

                // An ended call must not keep ticking (audit C8): the bar
                // outlives the full screen while minimized, and a live timer
                // on a dead call was the lie that made the failed-while-
                // minimized state look healthy.
                if case let .ended(status) = context.viewState.callState {
                    Text(status)
                        .font(.footnote.weight(.semibold))
                } else if let connectedAt = context.viewState.callConnectedAt {
                    Text(connectedAt, style: .timer)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            // The green runs up behind the status bar, the way the
            // system's own in-call bar does.
            .background(Color.compound.iconSuccessPrimary.ignoresSafeArea(edges: .top))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UntranslatedL10n.a11yNativeCallBar(context.viewState.roomName))
    }
}

// MARK: - Previews

struct NativeCallBar_Previews: PreviewProvider, TestablePreview {
    static let viewModel = NativeCallScreen_Previews.makeAgentViewModel()

    static var previews: some View {
        NativeCallBar(context: viewModel.context)
            .previewDisplayName("Recording with agent")
    }
}
