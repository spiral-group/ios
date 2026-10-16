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
