//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: product areas a release leaves out while their code stays,
// compiled and tested. A constant, not a setting: nothing turns one on at run
// time, and turning one on is a one-line change that goes through review.

nonisolated enum SpiralFeatures {
    /// Companies and their role agents (sales, outreach, support): creating,
    /// editing and opening them, and the outreach queue. Off in 1.0.2 because
    /// the area is unfinished (question 396); a later reviewed release brings
    /// it back. Off, the Agents tab is the personal assistant alone, and a
    /// company space the server still lists is neither read nor shown.
    static let companySpaces = false
}
