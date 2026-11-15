//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): what the timeline keeps to draw its rows faster.
//

import SwiftUI

/// Everything here can be made again, so it all goes when the system asks for memory.
enum TimelineCaches {
    static func purge() {
        SpiralAgentMarkdown.purge()
        TimelineTimes.purge()
        TrailingReservedSizes.purge()
        MessageTextView.pool.purge()
    }
}
