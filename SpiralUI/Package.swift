// swift-tools-version: 6.2
//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// SpiralUI: Spiral's own design-system package (Brief 0083 phase 3, decision 293).
//
// SpiralTokens holds the tokens Compound has no slot for: `Color.spiral.*` and
// `SpiralRadius.*`. Its one file, `Generated/SpiralTokens.swift`, is written by
// agent-brand-assets' `tokens/generators/gen-spiral-ios.mjs` from
// `tokens/spiral.json`; change the source there, never the file. The target
// depends on nothing, so compound-ios, reworked in place, imports it as well
// as the app. Spiral's shared components build on Compound, so they live in
// a package of their own, SpiralComponents: a target here would make this
// package and compound-ios depend on each other.

import PackageDescription

let package = Package(
    name: "SpiralUI",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "SpiralTokens", targets: ["SpiralTokens"])
    ],
    targets: [
        .target(name: "SpiralTokens")
    ]
)
