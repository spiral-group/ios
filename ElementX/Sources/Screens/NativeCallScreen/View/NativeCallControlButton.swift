//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063): the dock's circular control.

import Compound
import SwiftUI

/// One circular dock control, `56pt` as `C/CallControl` draws it after
/// the unified-call update: white with a soft shadow on the audio canvas,
/// glass over video, brand accent for the agent, critical for hang-up —
/// each with its caption underneath (`Agent · Mute · Video · Sound · End`).
struct NativeCallControlButton: View {
    enum Style {
        case audio
        /// The control's state is ON (muted mic, active speaker): inverted,
        /// the way the system call UI marks an engaged toggle.
        case audioEngaged
        case video
        case videoEngaged
        case accent
        case critical
    }

    let systemName: String
    let title: String
    let style: Style
    let titleColor: Color
    let accessibilityLabel: String
    var accessibilityHint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                circle

                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint ?? "")
    }

    @ViewBuilder
    private var circle: some View {
        let icon = Image(systemName: systemName)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(foreground)
            .frame(width: 56, height: 56)

        switch style {
        case .video:
            // Glass over the picture (`06`/`07`) — the canvas shows
            // through the control instead of a flat wash.
            icon.background(.ultraThinMaterial, in: Circle())
        case .audio:
            icon
                .background(Color(.secondarySystemGroupedBackground), in: Circle())
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        default:
            icon.background(background, in: Circle())
        }
    }

    private var foreground: AnyShapeStyle {
        switch style {
        case .audio: AnyShapeStyle(.primary)
        case .audioEngaged: AnyShapeStyle(Color(.systemBackground))
        case .video: AnyShapeStyle(.white)
        case .videoEngaged: AnyShapeStyle(.black)
        case .accent, .critical: AnyShapeStyle(.white)
        }
    }

    private var background: AnyShapeStyle {
        switch style {
        case .audioEngaged: AnyShapeStyle(Color(.label))
        case .videoEngaged: AnyShapeStyle(.white)
        // The BRAND accent (blue) — the compound `bgAccent*` family stays
        // green in this build (see the agent slot's wash note).
        case .accent: AnyShapeStyle(Color.compound.iconAccentPrimary)
        case .critical: AnyShapeStyle(Color.compound.bgCriticalPrimary)
        default: AnyShapeStyle(.clear)
        }
    }
}
