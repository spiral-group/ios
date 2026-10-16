// swift-tools-version: 5.10
//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AgentPlatformClient — local Swift Package providing typed REST
// bindings against the Matrix AI Agent Platform backend (`/api/v1/*`).
//
// Skeleton landed in agent-x-ios Session 145 alongside backend
// R3.3 endpoint completion. Bindings are generated from the
// `openapi.yaml` checked into `Sources/AgentPlatformClient/`.
//
// Refresh the spec with `Tools/Scripts/refresh-openapi.sh`
// (curls `/openapi.json` from the live homeserver) or by
// copying directly from the backend repo:
//
//   cp ~/Projects/matrix-agent-platform/target/openapi/openapi.yaml \
//      libraries/agentplatform-client/Sources/AgentPlatformClient/openapi.yaml
//
// Integration into the Xcode project:
//
//   1. Add this package to `project.yml::packages:` as a local path:
//
//      packages:
//        AgentPlatformClient:
//          path: libraries/agentplatform-client
//
//   2. Run `xcodegen generate`.
//   3. Add `AgentPlatformClient` as a dependency of the ElementX
//      target.
//
// Until step 1 lands, this package is **standalone** — operator
// can build/test it with `cd libraries/agentplatform-client &&
// swift build` without touching the Xcode project.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "AgentPlatformClient",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "AgentPlatformClient",
            targets: ["AgentPlatformClient"]
        ),
    ],
    dependencies: [
        // swift-openapi-generator drives compile-time generation
        // of typed Swift bindings from `openapi.yaml`. Pin to a
        // stable major; the generator's public API is stable on
        // 1.x.
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.4.0"),
        // Runtime types (Configuration, ClientTransport, etc.) the
        // generated `Client` depends on.
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.6.0"),
        // URLSession-backed `ClientTransport` impl. We layer our
        // bearer-token injection on top via a middleware so the
        // generated `Client` stays vanilla.
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "AgentPlatformClient",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ],
            // The OpenAPI generator plugin reads `openapi.yaml`
            // from the target's source directory and emits
            // `Types.swift` + `Client.swift` at build time.
            // Generated sources land in the build directory only;
            // they're not committed.
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
        .testTarget(
            name: "AgentPlatformClientTests",
            dependencies: ["AgentPlatformClient"]
        ),
    ]
)
