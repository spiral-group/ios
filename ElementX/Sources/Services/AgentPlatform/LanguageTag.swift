//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// Language identifiers reach this app from three sources that disagree on
// separators: the backend catalog sends bare BCP 47 primary subtags ("uk"),
// LiveKit track names carry the same ("lt:uk:@bob:host"), and Apple's
// `Locale.current.identifier` is an ICU identifier with an UNDERSCORE
// ("uk_UA") — not BCP 47, despite reading like it.
//
// That mismatch shipped a defect: the auto listening channel compared
// "uk_ua" against "uk-" and never matched on ANY real device (a simulator
// set to a bare language matched, which is why tests and manual passes
// missed it), so auto silently fell through to the alphabetically first
// language. Comparing tags is therefore never a string equality — it goes
// through here.

import Foundation

nonisolated enum LanguageTag {
    /// The primary language subtag, lowercased: `uk_UA`, `uk-UA`, `UK` → `uk`.
    static func base(of identifier: String) -> String {
        let lowercased = identifier.lowercased()
        return lowercased
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
            .map(String.init) ?? lowercased
    }
}
