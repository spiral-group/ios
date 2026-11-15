//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063): the meta line's live signal bars
// (`03`/`04`/`06`) — the transport's ConnectionQuality ladder, not a
// decoration. Three bars: excellent fills all, good two, poor one (in
// the critical hue), lost none.

import Compound
import SwiftUI

struct NativeCallSignalBars: View {
    let quality: NativeCallConnectionQuality

    private static let heights: [CGFloat] = [4, 7, 10]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(Self.heights.enumerated()), id: \.offset) { index, height in
                // swiftlint:disable:next spiral_raw_corner_radius - predates the rule
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < quality.filledBars
                        ? (quality.isPoor ? AnyShapeStyle(.compound.iconCriticalPrimary) : AnyShapeStyle(.secondary))
                        : AnyShapeStyle(.quaternary))
                    .frame(width: 3, height: height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UntranslatedL10n.a11yNativeCallSignal(quality.filledBars))
    }
}
