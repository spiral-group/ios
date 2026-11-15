# Scripts

## Create screen templates
New screen flows are currently using the MVVM-Coordinator pattern. Run [Tools/Scripts/createScreen.sh](Tools/Scripts/createScreen.sh) to create a new screen and all its required dependencies.

Usage:
```
./createScreen.sh Folder MyScreenName
```

After that run `xcodegen` to regenerate the project.  

`createScreen.sh` script will create:

- `Folder` within the `/ElementX/Sources/Screens/`. Files inside will be named `MyScreenNameXxx`.
- `MyScreenNameScreenUITests.swift` within `UITests/Sources`
- `MyScreenNameViewModelTests.swift` within `UnitTests/Sources/Unit`


## Acknowledgements

`ElementX/SupportingFiles/Settings.bundle` carries the licence of everything the app is built from (iOS Settings > Spiral > Acknowledgements, which Settings > About > Open source licenses in the app opens). It is generated, never edited by hand:

```
Tools/Scripts/generate-acknowledgements.py           # rewrite the bundle
Tools/Scripts/generate-acknowledgements.py --check   # exit 1 if it is stale
```

Re-run it after any change to `project.yml` packages, `Package.resolved`, or a sibling package (`../client-sdk-swift`, `../spiral-app-shell`, `../matrix-rust-components-swift`, `../compound-design-tokens`), and commit the result. `preflight-archive.sh` runs the check.

The list is the whole package graph: what `project.yml` declares, the local packages those reach, every pin in `Package.resolved`, the app itself and `matrix-rust-sdk` (built into `MatrixRustSDK`'s binary). Each entry is its licence files verbatim (`LICENSE*`, `LICENCE*`, `COPYING*`, `NOTICE*`), plus any a downloaded binary artifact carries (WebRTC's binary is BSD, its packaging repository MIT); a package with none says so. Remote licences are read from the SwiftPM checkouts of a build of this project, which must be at their pinned revisions — build or resolve the packages first, or pass `--source-packages <DerivedData>/SourcePackages`. Needs `xcodegen` and `swift`.

Upstream regenerates the same bundle with `swift-package-list` from its Renovate job; that tool cannot see this fork's local packages, so do not bring its output back on an upstream sync.

## Timeline benchmark

`run-timeline-bench.sh` measures the chat timeline: the real room screen and table over a fixed fixture of up to 500 rows, with no network. `run` builds with `SPIRAL_TIMELINE_BENCH`, runs each scenario a few times on the `Spiral-UnitTests-en-27` simulator and prints a table; `compare before.json after.json` says what moved. Results go outside the repo, to `~/Library/Application Support/Spiral/timeline-bench`. The flag is set by the script alone, so the harness in `ElementX/Sources/UITests/TimelineBench` is in no other build. `trace <template>` records the harness with `xctrace`, and `read-xctrace.py <recording.trace>` reads any recording in one step, the phone's too.

A simulator prices the CPU, not the GPU: read main-thread CPU and re-render counts as real, and hitches as relative. `Animation Hitches` and `SwiftUI` don't run on a simulator at all, so what the shadows and the glass cost has to come from a phone:

```
xcrun xctrace record --template 'Animation Hitches' --device <udid> --all-processes --time-limit 30s --no-prompt --output hitches.trace
Tools/Scripts/read-xctrace.py hitches.trace
```

`--all-processes`, because with Xcode 27.1 and iOS 27.2 `--attach` answers `Cannot find process`; the reader filters to Spiral. The recording takes minutes to save after the 30 s, so wait for `Output file saved as`, and check that `end-reason` says `Time limit reached`. A trace cut off before it saved fails `export` with `Document Missing Template Error`, though `read-xctrace.py <trace> --template <name>` can still import its raw capture, without symbols. Keep the `SwiftUI` template to a few seconds: with `--all-processes`, 30 s of it is 1.5 GB, and saving or importing that fills the Mac's memory (swap went to 38 GB in 7 minutes). Run nothing else beside a recording.
