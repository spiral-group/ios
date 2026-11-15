//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import SwiftUI

// AGENT-PLATFORM (Brief 0083 L1c): the one opt-in to Spiral's stricter gates.
// It doesn't refine `TestablePreview`: upstream's Sourcery templates take every
// type based on that protocol for a preview, this protocol included.

/// A preview whose screen must pass Spiral's stricter gates. Conform next to `TestablePreview`:
///
///     struct FooScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview
///
/// - AccessibilityTests audit it with `contrast` and `textClipped` too, in light and in dark.
/// - PreviewTests snapshot it in dark, at the AX3 text size and right to left besides upstream's light one.
/// - `run-preview-tests.sh --pre-glass` snapshots it on iOS 18.6, which has no Liquid Glass.
///
/// How to opt a screen in: `docs/project/CODEBASE/07-build-and-codegen.md`.
protocol SpiralGatedPreview: PreviewProvider { }
