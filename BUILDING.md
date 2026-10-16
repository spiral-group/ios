# Building Spiral for iOS from source

Spiral is a fork of [Element X iOS](https://github.com/element-hq/element-x-ios).
The app is built from this repository alone. Clone
`https://github.com/spiral-group/ios` and check out the tag `SOURCES.md`
names for the release you are building.

Spiral's other components are Swift packages that Xcode fetches by URL at
the exact versions `project.yml` and `compound-ios/Package.swift` pin (a
tag's version, without a leading `v`), all from `https://github.com/spiral-group`:

| Package | Tag | What it is |
|---|---|---|
| `matrix-rust-components-swift` | `26.07.28-spiral.31` | the Matrix SDK's Swift bindings; the release carries `MatrixSDKFFI.xcframework.zip`, built from `matrix-rust-sdk` at the commit its `PROVENANCE.json` names |
| `client-sdk-swift` | `2.16.0-spiral.1` | the LiveKit client |
| `compound-design-tokens` | `v10.2.3-spiral.1` | design tokens and icons, read by `compound-ios` |
| `spiral-app-shell` | `1.0.1` | the Interactive Posts runtime |

Git LFS holds the media files the tests use (`DevelopmentAssets/Media`):
run `git lfs install` before cloning this repository, or `git lfs pull`
after. In Spiral's own repository LFS also holds the tests' reference
images: the `__Snapshots__` folders of `PreviewTests`, `UITests` and
`compound-ios/Tests/CompoundTests`, about 3,100 images for 1.0.1. The
published source leaves all of those images out, Element's included; the
test code that uses them stays.

## Requirements

- macOS with Xcode 27.0 (27A266a), the version Spiral 1.0.1 is built with.
- Homebrew. `swift run tools setup-project` uses it: the command points
  git at the repository's hooks (`.githooks`), installs `xcodegen`,
  `swiftgen`, `swiftformat`, `git-lfs`, `sourcery`, `mint`, `pkl`,
  `swift-outdated`, `localazy` and `periphery` with Homebrew, installs
  `locheck` with mint, and runs `xcodegen`.
- Optionally `swiftlint` (`brew install swiftlint`), which `setup-project`
  does not install. The build runs it when it is there, and only warns
  when it is not.
- Of those tools, the build itself needs only `xcodegen`. It runs SwiftGen,
  Sourcery, SwiftLint and SwiftFormat when they are installed and warns
  when they are not, since their output is committed. The rest are
  Element's tools for working on the project, and `setup-project`
  installs `swift-outdated` and `localazy` from third-party taps. To build
  without them, run `git config core.hooksPath .githooks` and `xcodegen`
  in place of `swift run tools setup-project`.

## Build

```sh
cd ios
swift run tools setup-project
xcodebuild -project ElementX.xcodeproj -scheme ElementX \
  -destination "generic/platform=iOS Simulator" build
```

The first build resolves the packages, which downloads the SDK framework
from the `matrix-rust-components-swift` release; SwiftPM checks it against
the checksum in that tag's `Package.swift`.

A device build needs your own signing team and bundle identifier in
`app.yml`; the published source carries Spiral's.

## Building the components from source too

Each pinned package keeps its sibling path as a comment (`# path: ../…` in
`project.yml`, `// .package(path: …)` in `compound-ios/Package.swift`).
To build one from source, clone it next to this repository at the tag
above, swap the comment for the `url:` lines, and run `xcodegen`.

- **The SDK framework.** Clone `matrix-rust-sdk` (at the commit the
  components tag's `PROVENANCE.json` names) and
  `matrix-rust-components-swift` side by side. You need Rust at least the
  `rust-version` in `matrix-rust-sdk/Cargo.toml` (1.93 for 1.0.1) with
  `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`.
  Then:

  ```sh
  cd matrix-rust-components-swift/Tools/Release
  swift run release --custom-version <version from ../../Package.swift> --local-only
  ```

  The `matrix-rust-sdk` checkout must have no local changes. The tool
  builds it for the device and both simulators, puts
  `MatrixSDKFFI.xcframework` and its zip beside `Package.swift`, and the
  manifest then uses the framework instead of the release download. It
  also rewrites `Sources/MatrixRustSDK`, which comes out unchanged, and
  `PROVENANCE.json`, which then names your checkout and your zip's
  checksum. The build remaps the paths it embeds, so the framework names
  no directory of yours. On a recent Mac it takes about five minutes and
  leaves about 6 GB in `matrix-rust-sdk/target`.
- **The Interactive Posts runtime.** With Node.js and pnpm at the versions
  in `spiral-app-shell/package.json`:

  ```sh
  cd spiral-app-shell
  pnpm install --frozen-lockfile
  pnpm build:ios
  ```

  This rebuilds `ios/Sources/dist`, which is committed, so `git status`
  stays clean when the build matches the release.

## Tests

Run the tests through the scripts, not plain `xcodebuild test`:

```sh
Tools/Scripts/run-unit-tests.sh
Tools/Scripts/run-preview-tests.sh
```

Every suite assumes an English simulator, and a new simulator takes the
Mac's language, so the scripts create their own, set to English.

Both scripts create their simulators on the **iOS 26.5** simulator runtime,
and the preview tests stop with a crash on any other iOS version. Install
the runtime from Xcode > Settings > Components, or with
`xcodebuild -downloadPlatform iOS -buildVersion 26.5`.

The preview tests compare each screen with a recorded snapshot, and the
UI tests and Compound's tests compare with recorded images too. The unit
tests need none. Those images are not part of the published source, so in this tree
such a test has nothing to compare against: a run records a new image and
reports the test as failed. The preview tests also need an iPhone SE
(3rd generation) and stop with a crash on any other device.
