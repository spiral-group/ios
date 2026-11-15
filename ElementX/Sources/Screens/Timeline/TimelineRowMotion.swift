//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SwiftUI

/// AGENT-PLATFORM (Brief 0083, question 359): whether a row changing just now goes there smoothly. A row touched folds out or
/// takes a reaction, and the rows beside a new one regroup as it slides in. Anything else comes from the network, a quote loading
/// or someone's reaction, and moves nothing but what it must, at once.
final class TimelineRowMotion {
    private static let afterTouch: Duration = .seconds(1)
    private static let afterArrival: Duration = .milliseconds(400)
    
    private var deadline: ContinuousClock.Instant?
    
    var isAnimated: Bool {
        deadline.map { .now < $0 } ?? false
    }
    
    var animation: Animation? {
        isAnimated ? .elementDefault : nil
    }
    
    func noteTouch() {
        deadline = .now + Self.afterTouch
    }
    
    func noteArrival() {
        deadline = max(deadline ?? .now, .now + Self.afterArrival)
    }
    
    /// A drag starts with a touch, but it isn't one on a row.
    func noteDrag() {
        deadline = nil
    }
}

extension EnvironmentValues {
    @Entry var timelineRowMotion = TimelineRowMotion()
}
