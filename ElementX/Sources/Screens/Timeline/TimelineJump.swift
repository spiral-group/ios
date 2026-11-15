//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

/// AGENT-PLATFORM (Brief 0083, question 359): an animated scroll configures every row it passes, which held the chat on the
/// way to the far end. A long jump cuts to a little short of its target and animates the rest. A short one stays as it was.
enum TimelineJump {
    /// Rows further than this are too far to scroll through.
    static let longestScroll = 24
    /// How far short of its target a long jump lands.
    static let finalRun = 8
    
    /// The row to cut to before animating to `target`, if it's that far from what's on screen.
    static func cutRow(from visibleRows: ClosedRange<Int>, to target: Int) -> Int? {
        if target > visibleRows.upperBound + longestScroll {
            return target - finalRun
        }
        if target < visibleRows.lowerBound - longestScroll {
            return target + finalRun
        }
        return nil
    }
}
