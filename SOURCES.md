# Corresponding source

The Spiral iOS app (`com.veruslogistics.messenger`) is built from the
sources below. Each row names the public repository and, once the release
is tagged, the exact commit; the build number goes in the heading.

**Licences.** The app is a fork of Element X iOS. Element's code, including
the Element files modified here, is licensed under the GNU Affero General
Public License v3.0 only. Spiral's own code is AGPL-3.0-or-later. The app
as a whole is distributed under AGPL-3.0-only. `NOTICE` says which code is
whose. The other components keep their own licences.

## Release: 1.0.3

The build number is the one App Store Connect shows for 1.0.3; Xcode sets it at upload, from this same tree.

| Component | What it is | Licence | Source | Commit |
|---|---|---|---|---|
| ios | the app, a fork of Element X iOS (this repository) | AGPL-3.0-only (Element's code), AGPL-3.0-or-later (Spiral's) | `https://github.com/spiral-group/ios`, tag `spiral/1.0.3` | the commit that tag names |
| matrix-rust-sdk | the Matrix client core, a fork of matrix-org/matrix-rust-sdk | Apache-2.0 | `https://github.com/spiral-group/matrix-rust-sdk`, branch `spiral/main` | `c79e5b81e4da5aee3453c12bff20e1a6c2c46c13` |
| matrix-rust-components-swift | Swift bindings for the above, a fork of element-hq/matrix-rust-components-swift; its release `26.10.29-spiral.7` carries the framework built from the commit above | Apache-2.0 | `https://github.com/spiral-group/matrix-rust-components-swift`, tag `26.10.29-spiral.7` | `f0849fcbf6d207212aae277b6f78facb510b5134` |
| client-sdk-swift | the LiveKit client, a fork of livekit/client-sdk-swift (unchanged since 1.0.1) | Apache-2.0 | `https://github.com/spiral-group/client-sdk-swift`, tag `2.16.0-spiral.1` | `d339ddaefbc0cd87ad9a41cece4121e3023e86cc` |
| compound-design-tokens | design tokens and icons, a fork of element-hq/compound-design-tokens (unchanged since 1.0.2) | AGPL-3.0-only | `https://github.com/spiral-group/compound-design-tokens`, tag `v11.3.1-spiral.4` | `8c97443840a680cd60b9b162363443667dd41757` |
| spiral-app-shell | the Interactive Posts runtime, Spiral's own (unchanged since 1.0.2) | AGPL-3.0-or-later | `https://github.com/spiral-group/spiral-app-shell`, tag `1.1.0` | `ed239fe28a7ab06066fcab160b452ab0e3e3cf0d` |
| synapse | the Matrix homeserver the app talks to, element-hq/synapse v1.165.0 with Spiral's five patches and its post guard module; not built into the app, published because users reach it over the network (AGPL-3.0 §13) | AGPL-3.0-only | `https://github.com/spiral-group/synapse`, branch `spiral/v1.165.0`, tag `v1.165.0-spiral.1` (the image the server runs) | the commit that tag names |

## Release: 1.0.2

The build number is the one App Store Connect shows for 1.0.2; Xcode sets it at upload, from this same tree.

| Component | What it is | Licence | Source | Commit |
|---|---|---|---|---|
| ios | the app, a fork of Element X iOS (this repository) | AGPL-3.0-only (Element's code), AGPL-3.0-or-later (Spiral's) | `https://github.com/spiral-group/ios`, tag `spiral/1.0.2` | the commit that tag names |
| matrix-rust-sdk | the Matrix client core, a fork of matrix-org/matrix-rust-sdk | Apache-2.0 | `https://github.com/spiral-group/matrix-rust-sdk`, tag `spiral/1.0.2` | `0f66125800a61f241be046528fae0324a893e0df` |
| matrix-rust-components-swift | Swift bindings for the above, a fork of element-hq/matrix-rust-components-swift; its release `26.10.29-spiral.6` carries the framework built from the commit above | Apache-2.0 | `https://github.com/spiral-group/matrix-rust-components-swift`, tag `26.10.29-spiral.6` | `f4e10e0fc45e21a3150f2f4a498f5af56f1e876e` |
| client-sdk-swift | the LiveKit client, a fork of livekit/client-sdk-swift (unchanged since 1.0.1) | Apache-2.0 | `https://github.com/spiral-group/client-sdk-swift`, tag `2.16.0-spiral.1` | `d339ddaefbc0cd87ad9a41cece4121e3023e86cc` |
| compound-design-tokens | design tokens and icons, a fork of element-hq/compound-design-tokens | AGPL-3.0-only | `https://github.com/spiral-group/compound-design-tokens`, tag `v11.3.1-spiral.4` | `8c97443840a680cd60b9b162363443667dd41757` |
| spiral-app-shell | the Interactive Posts runtime, Spiral's own | AGPL-3.0-or-later | `https://github.com/spiral-group/spiral-app-shell`, tag `1.1.0` | `ed239fe28a7ab06066fcab160b452ab0e3e3cf0d` |
| synapse | the Matrix homeserver the app talks to, element-hq/synapse v1.158.0 with Spiral's six patches and its post guard module; not built into the app, published because users reach it over the network (AGPL-3.0 §13) | AGPL-3.0-only | `https://github.com/spiral-group/synapse`, branch `spiral/v1.158.0`, tag `v1.158.0-spiral.8` (the image the server runs) | the commit that tag names |

## Release: 1.0.1 (build 5)

| Component | What it is | Licence | Source | Commit |
|---|---|---|---|---|
| ios | the app, a fork of Element X iOS (this repository) | AGPL-3.0-only (Element's code), AGPL-3.0-or-later (Spiral's) | `https://github.com/spiral-group/ios`, tag `spiral/1.0.1` | the commit that tag names |
| matrix-rust-sdk | the Matrix client core, a fork of matrix-org/matrix-rust-sdk | Apache-2.0 | `https://github.com/spiral-group/matrix-rust-sdk`, tag `spiral/1.0.1` | `0e55cfc0f9f5882bf926b6faa8497a1a9e263b4b` |
| matrix-rust-components-swift | Swift bindings for the above, a fork of element-hq/matrix-rust-components-swift; its release `26.07.28-spiral.31` carries the framework built from the commit above | Apache-2.0 | `https://github.com/spiral-group/matrix-rust-components-swift`, tag `26.07.28-spiral.31` | `3c9f169e12da72b1bc83b53a54ec9cf2d89765c2` |
| client-sdk-swift | the LiveKit client, a fork of livekit/client-sdk-swift | Apache-2.0 | `https://github.com/spiral-group/client-sdk-swift`, tag `2.16.0-spiral.1` | `d339ddaefbc0cd87ad9a41cece4121e3023e86cc` |
| compound-design-tokens | design tokens and icons, a fork of element-hq/compound-design-tokens | AGPL-3.0-only | `https://github.com/spiral-group/compound-design-tokens`, tag `v10.2.3-spiral.1` | `1c33f3f27e1a6feb51ed87c5e681ef62e2d0bcb8` |
| spiral-app-shell | the Interactive Posts runtime, Spiral's own | AGPL-3.0-or-later | `https://github.com/spiral-group/spiral-app-shell`, tag `1.0.1` | `0f177261cbec5f170caa8a57ace78bb2f0e57e1f` |
| synapse | the Matrix homeserver the app talks to, element-hq/synapse v1.158.0 with Spiral's four patches; not built into the app, published because users reach it over the network (AGPL-3.0 §13) | AGPL-3.0-only | `https://github.com/spiral-group/synapse`, branch `spiral/v1.158.0`, tag `v1.158.0-spiral.4` (the image the server runs) | `1fea613863a0a810126b06c9f962080aa308763c` |

Each release takes the Spiral packages in its table by URL at those tags, and the Swift
packages fetched unchanged from their upstreams too; all are pinned in
`ElementX.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
of the tagged commit. Settings > About > Open source licenses in the app
lists every package with its licence.

## The server

The app talks to Spiral's Matrix homeserver, which runs Synapse
(element-hq/synapse, AGPL-3.0-only) with Spiral's patches. Users reach it
over the network, so its source is offered too (AGPL-3.0 §13):
`https://github.com/spiral-group/synapse`. The `synapse` row
of the latest release above names the branch and the tag the server runs;
a server upgrade adds them here, so this section stays current for every
app build that links to it.

How to build from these: `BUILDING.md`.

To ask for the source of a build you received, write to
support@spiral.md.
