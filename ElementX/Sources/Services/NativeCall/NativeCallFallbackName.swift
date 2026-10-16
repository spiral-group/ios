//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063): THE one cosmetic MXID → name rule
// ("@assistant-alice:host" → "Assistant Alice"). Every call surface that
// has no profile to show goes through here, so no two surfaces can name
// the same identity differently. Cosmetic only — a profile name always
// wins.

import Foundation

nonisolated enum NativeCallFallbackName {
    static func make(mxid: String) -> String {
        let localpart = mxid.dropFirst().prefix { $0 != ":" }
        guard !localpart.isEmpty else { return mxid }
        return localpart
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
