# Corresponding source

The Spiral iOS app (`com.veruslogistics.messenger`) is built from the
sources below. Each row names the public repository and, once the release
is tagged, the exact commit; the build number goes in the heading.

**Licences.** The app is a fork of Element X iOS. Element's code, including
the Element files modified here, is licensed under the GNU Affero General
Public License v3.0 only. Spiral's own code is AGPL-3.0-or-later. The app
as a whole is distributed under AGPL-3.0-only. `NOTICE` says which code is
whose. The other components keep their own licences.

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

The app takes the Spiral packages above by URL at those tags, and the Swift
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
