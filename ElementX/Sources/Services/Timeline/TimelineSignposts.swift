//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359 item 16): where a timeline update's time goes, for Instruments and `xctrace`.
//

import OSLog

/// The coarse stages of a timeline update as intervals, so that a trace can say what an update cost. They carry counts, never
/// IDs or content, and cost next to nothing with nobody recording. What's counted per row is for tests, in debug builds alone.
nonisolated enum TimelineSignposts {
    private static let signposter = OSSignposter(subsystem: InfoPlistReader.main.baseBundleIdentifier, category: "Timeline")
    
    static func beginInterval(_ name: StaticString, count: Int) -> OSSignpostIntervalState {
        signposter.beginInterval(name, id: signposter.makeSignpostID(), "\(count, privacy: .public)")
    }
    
    static func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }
    
    #if DEBUG
    enum Body {
        case row
        case styler
    }
    
    /// How many times each row's body ran, for the tests that say which rows an update reaches.
    @MainActor static var bodyCounts = [Body: [TimelineItemIdentifier.UniqueID: Int]]()
    /// How many rows were compared, for the tests that say an update doesn't go through them all.
    @MainActor static var rowComparisons = 0
    
    @MainActor
    static func noteBody(_ body: Body, of uniqueID: TimelineItemIdentifier.UniqueID) {
        bodyCounts[body, default: [:]][uniqueID, default: 0] += 1
    }
    #endif
}
