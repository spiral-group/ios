// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Compound",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "Compound", targets: ["Compound"])
    ],
    dependencies: [
        // AGENT-PLATFORM: Spiral brand tokens come from the recoloured fork,
        // spiral-group/compound-design-tokens (Brief 0032, decision 203). The
        // fork is generated from Spiral's colour tokens — never hand-edited.
        // Upstream pin is: element-hq/compound-design-tokens exact 11.3.1.
        .package(url: "https://github.com/spiral-group/compound-design-tokens", exact: "11.3.1-spiral.4"),
        // .package(path: "../../compound-design-tokens"),
        // AGENT-PLATFORM (Brief 0083 phase 3, decision 293): Spiral's own tokens, for what the fork
        // has no token for (the list row's counter fill, decision 307). Generated, never hand-edited.
        .package(path: "../SpiralUI"),
        .package(url: "https://github.com/siteline/SwiftUI-Introspect", exact: "27.1.0"),
        .package(url: "https://github.com/SFSafeSymbols/SFSafeSymbols", exact: "7.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.6")
    ],
    targets: [
        .target(
            name: "Compound",
            dependencies: [
                .product(name: "CompoundDesignTokens", package: "compound-design-tokens"),
                .product(name: "SpiralTokens", package: "SpiralUI"), // AGENT-PLATFORM (Brief 0083)
                .product(name: "SwiftUIIntrospect", package: "SwiftUI-Introspect"),
                .product(name: "SFSafeSymbols", package: "SFSafeSymbols")
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        ),
        .testTarget(
            name: "CompoundTests",
            dependencies: [
                "Compound",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            exclude: [
                "__Snapshots__"
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        )
    ]
)
