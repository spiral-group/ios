//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import SwiftUI

// AGENT-PLATFORM (Brief 0083, phase 4, lane settings, decision 337): Spiral's grouped list, as iOS's Settings draw
// one. A list opts in with `spiralGroupedList()`; every other list keeps Compound's look, so upstream's lists don't
// move.

public extension EnvironmentValues {
    /// A row's background. Compound's is `bgCanvasDefaultLevel1`, #2C2C2E in dark.
    @Entry var listRowFill: Color = .compound.bgCanvasDefaultLevel1
    /// Whether a `ListRowLabel.default` row draws its icon as a plain grey glyph on every iOS version. Compound
    /// puts it on a grey tile before iOS 26.
    @Entry var listRowPlainIcons = false
}

public extension View {
    /// Styles a `Form` or `List` as Spiral's grouped list: Compound's inset list with iOS's grouped cards
    /// (`bgSubtlePrimary`, white and #1C1C1E, where a red title reads 5.67:1 and 4.87:1) and plain grey glyphs, as
    /// Messages' and Mail's settings draw them.
    func spiralGroupedList() -> some View {
        compoundList()
            .environment(\.listRowFill, .compound.bgSubtlePrimary)
            .environment(\.listRowPlainIcons, true)
    }
    
    /// Gives Compound's row style back to a view presented from inside a `spiralGroupedList()`, such as a sheet,
    /// which otherwise inherits the opt-in.
    func compoundListRowStyle() -> some View {
        environment(\.listRowFill, EnvironmentValues().listRowFill)
            .environment(\.listRowPlainIcons, EnvironmentValues().listRowPlainIcons)
    }
}
