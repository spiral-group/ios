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
        // Upstream pin is: element-hq/compound-design-tokens exact 10.2.3.
        .package(url: "https://github.com/spiral-group/compound-design-tokens", exact: "10.2.3-spiral.1"),
        // .package(path: "../../compound-design-tokens"),
        .package(url: "https://github.com/siteline/SwiftUI-Introspect", from: "26.0.1"),
        .package(url: "https://github.com/SFSafeSymbols/SFSafeSymbols", from: "7.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.3")
    ],
    targets: [
        .target(
            name: "Compound",
            dependencies: [
                .product(name: "CompoundDesignTokens", package: "compound-design-tokens"),
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
