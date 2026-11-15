// swift-tools-version: 6.2
//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// SpiralComponents: Spiral's own shared components (Brief 0083 phase 3, decision 293), built on
// Compound and Spiral's tokens: the empty state and the preloader first, then the agent card, the
// call buttons and the minimised call. A package of its own rather than a target in SpiralUI:
// compound-ios depends on SpiralUI for SpiralTokens, so a SpiralUI target that imported Compound
// would make the two packages depend on each other. SwiftPM 6.2 accepts that while no target
// depends on itself, but either package's build, and compound-ios's tests, would then resolve both.
// Here the dependencies run one way: SpiralComponents → Compound → SpiralTokens.

import PackageDescription

let package = Package(
    name: "SpiralComponents",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "SpiralComponents", targets: ["SpiralComponents"])
    ],
    dependencies: [
        .package(path: "../compound-ios"),
        .package(path: "../SpiralUI"),
        // The version compound-ios pins: a bump there moves this one too (UPSTREAM_SYNC.md).
        .package(url: "https://github.com/SFSafeSymbols/SFSafeSymbols", exact: "7.0.0")
    ],
    targets: [
        .target(
            name: "SpiralComponents",
            dependencies: [
                .product(name: "Compound", package: "compound-ios"),
                .product(name: "SpiralTokens", package: "SpiralUI"),
                .product(name: "SFSafeSymbols", package: "SFSafeSymbols")
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        )
    ]
)
