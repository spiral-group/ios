//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 413): how a video tile says it is one, in a chat's album and in
// "Media and files" alike: a chip in its corner, in the style of the time's chip on a photo.
//

import Compound
import SwiftUI

struct MediaVideoBadge: View {
    /// The video's length, when the event says.
    let duration: TimeInterval?

    var body: some View {
        HStack(spacing: 2) {
            CompoundIcon(\.playSolid, size: .xSmall, relativeTo: .compound.bodyXSSemibold)
            if let duration {
                Text(formatted(duration: duration))
                    .lineLimit(1)
            }
        }
        .font(.compound.bodyXSSemibold)
        .foregroundStyle(.compound.textPrimary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.compound.bgSubtleSecondary, in: .capsule)
        .padding(6)
    }

    private func formatted(duration: TimeInterval) -> String {
        let duration = Duration.seconds(duration)
        let pattern: Duration.TimeFormatStyle.Pattern = duration >= .seconds(3600) ? .hourMinuteSecond : .minuteSecond
        return duration.formatted(.time(pattern: pattern))
    }
}
