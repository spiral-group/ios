#!/usr/bin/env bash
# AGENT-PLATFORM (Brief 0067): the checks an Xcode archive should pass before
# the operator presses Product > Archive. Spiral has no CI, no fastlane and
# (ADR-0005) no pushed artifacts, so "the archive builds against the tagged
# SDK" is something this script proves rather than something a remote
# guarantees: the local xcframework beside the components package must be
# the one whose checksum the tag recorded.
#
# Usage: Tools/Scripts/preflight-archive.sh        (from the iOS repo root)
set -euo pipefail

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPONENTS_DIR="$IOS_DIR/../matrix-rust-components-swift"
FAIL=0
ok()   { printf '  ✓ %s\n' "$1"; }
fail() { FAIL=1; printf '  ✗ %s\n' "$1"; }

echo "[1] iOS working tree"
if [[ -z "$(git -C "$IOS_DIR" status --porcelain)" ]]; then
  ok "clean at $(git -C "$IOS_DIR" rev-parse --short HEAD) ($(git -C "$IOS_DIR" branch --show-current))"
else
  fail "uncommitted changes — an archive must be reproducible from a commit"
fi

echo "[2] version + build number (project.yml is the source of truth)"
MARKETING="$(grep -E '^\s*MARKETING_VERSION:' "$IOS_DIR/project.yml" | awk '{print $2}')"
BUILD="$(grep -E '^\s*CURRENT_PROJECT_VERSION:' "$IOS_DIR/project.yml" | awk '{print $2}')"
PBX_BUILD="$(grep -E 'CURRENT_PROJECT_VERSION = [0-9]+;' "$IOS_DIR/ElementX.xcodeproj/project.pbxproj" | head -1 | grep -oE '[0-9]+' || true)"
if [[ "$BUILD" == "$PBX_BUILD" ]]; then
  ok "$MARKETING ($BUILD) — project.yml and the generated project agree"
else
  fail "project.yml says build $BUILD but the generated project says $PBX_BUILD — run xcodegen"
fi
echo "     (App Store Connect rejects a reused (version, build); bump with: swift run tools bump-build-number)"

echo "[3] secrets ship as nil"
if grep -qE ': String\? = "' "$IOS_DIR/Secrets/Secrets.swift"; then
  fail "Secrets/Secrets.swift carries a non-nil placeholder"
else
  ok "every Secrets entry is nil"
fi

echo "[4] SDK bindings: the pinned release, or a local framework == tagged artifact"
# Decision 203: the app takes the components package by URL and exact
# version, and SwiftPM checks the release zip against the checksum in that
# tag's Package.swift. With the sibling path swapped back in (cross-repo
# work), the local checks below apply instead.
COMPONENTS_VERSION="$(awk '/^  MatrixRustSDK:/{f=1;next} f&&/^  [A-Za-z]/{f=0} f&&/^    exactVersion:/{print $2}' "$IOS_DIR/project.yml")"
if [[ -n "$COMPONENTS_VERSION" ]]; then
  RESOLVED="$IOS_DIR/ElementX.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  PIN_VERSION="$(python3 -c "import json,sys
pins=json.load(open(sys.argv[1]))['pins']
print(next((p['state'].get('version','') for p in pins if p['identity']=='matrix-rust-components-swift'),''))" "$RESOLVED" 2>/dev/null || true)"
  # SwiftPM records the version without leading zeros (26.07.28 → 26.7.28).
  normalise() { sed -E 's/(^|\.)0+([0-9])/\1\2/g' <<< "$1"; }
  [[ "$(normalise "$PIN_VERSION")" == "$(normalise "$COMPONENTS_VERSION")" ]] \
    && ok "project.yml and Package.resolved pin matrix-rust-components-swift $COMPONENTS_VERSION" \
    || fail "project.yml says $COMPONENTS_VERSION but Package.resolved pins '${PIN_VERSION:-nothing}' — resolve the packages"
  PKG_VERSION="$COMPONENTS_VERSION"
  [[ -d "$COMPONENTS_DIR" ]] \
    && echo "     (note: a sibling $COMPONENTS_DIR exists but is not used while project.yml pins by URL)"
else
  PROV="$COMPONENTS_DIR/PROVENANCE.json"
  if [[ ! -f "$PROV" ]]; then
    fail "no $PROV — the sibling components checkout is missing"
  else
    PROV_VERSION="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['packageVersion'])" "$PROV")"
    PROV_SHA="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['artifactSHA256'])" "$PROV")"
    PROV_SRC="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['sourceCommit'])" "$PROV")"
    PKG_VERSION="$(grep -E '^let version = ' "$COMPONENTS_DIR/Package.swift" | sed -E 's/.*"([^"]+)".*/\1/')"
    PKG_SHA="$(grep -E '^let checksum = ' "$COMPONENTS_DIR/Package.swift" | sed -E 's/.*"([^"]+)".*/\1/')"
    [[ "$PROV_VERSION" == "$PKG_VERSION" && "$PROV_SHA" == "$PKG_SHA" ]] \
      && ok "PROVENANCE and Package.swift agree on $PKG_VERSION / ${PKG_SHA:0:12}…" \
      || fail "PROVENANCE ($PROV_VERSION/${PROV_SHA:0:12}) and Package.swift ($PKG_VERSION/${PKG_SHA:0:12}) disagree"
    ZIP="$COMPONENTS_DIR/MatrixSDKFFI.xcframework.zip"
    if [[ -f "$ZIP" ]]; then
      ZIP_SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
      [[ "$ZIP_SHA" == "$PROV_SHA" ]] \
        && ok "MatrixSDKFFI.xcframework.zip sha256 matches the tag" \
        || fail "MatrixSDKFFI.xcframework.zip sha256 ${ZIP_SHA:0:12}… ≠ PROVENANCE ${PROV_SHA:0:12}… — rebuild with the release tool"
    else
      fail "no MatrixSDKFFI.xcframework.zip beside the package — the local framework has no checksummed twin"
    fi
    [[ -d "$COMPONENTS_DIR/MatrixSDKFFI.xcframework" ]] \
      && ok "local MatrixSDKFFI.xcframework present (Package.swift selects it over the remote URL)" \
      || fail "no local MatrixSDKFFI.xcframework — Package.swift would fall back to a remote URL nothing serves (ADR-0005)"
    # The tag may sit one merge behind HEAD (releases are cut on a feature
    # branch and merged --no-ff); what must be identical is the TREE.
    TAG_TREE="$(git -C "$COMPONENTS_DIR" rev-parse "$PKG_VERSION^{tree}" 2>/dev/null || true)"
    HEAD_TREE="$(git -C "$COMPONENTS_DIR" rev-parse 'HEAD^{tree}')"
    if [[ -z "$TAG_TREE" ]]; then
      fail "components has no tag $PKG_VERSION"
    elif [[ "$TAG_TREE" == "$HEAD_TREE" ]]; then
      ok "components HEAD has the $PKG_VERSION tag's tree; SDK source $PROV_SRC"
    else
      fail "components HEAD's tree differs from the $PKG_VERSION tag — the package is not what the tag says"
    fi
    SDK_DIR="$IOS_DIR/../matrix-rust-sdk"
    if [[ -d "$SDK_DIR/.git" ]]; then
      if git -C "$SDK_DIR" merge-base --is-ancestor "$PROV_SRC" HEAD 2>/dev/null; then
        ok "SDK checkout contains the source commit the artifact was built from"
      else
        fail "SDK checkout does not contain $PROV_SRC"
      fi
    fi
  fi

fi

echo "[5] entitlements carry no developer-mode associated domain"
if grep -hE 'mode=developer' "$IOS_DIR/ElementX/SupportingFiles/target.yml" "$IOS_DIR/ElementX/SupportingFiles/"*.entitlements 2>/dev/null | grep -vqE '^\s*#'; then
  fail "applinks:…?mode=developer is back — App Store Connect rejects it (Brief 0060 gate)"
else
  ok "no ?mode=developer applink"
fi

echo "[6] acknowledgements match the package graph (Brief 0078)"
if ACK="$(python3 "$IOS_DIR/Tools/Scripts/generate-acknowledgements.py" --check 2>&1)"; then
  ok "${ACK#generate-acknowledgements: }"
else
  fail "Settings.bundle acknowledgements are stale or could not be checked:"
  printf '%s\n' "$ACK" | sed 's/^/       /'
fi

echo "[7] NOTICE has no placeholder left (decision 54)"
# NOTICE ships twice: at the repository root, and inside the app through the
# acknowledgements in Settings.bundle. A draft's "to be filled in" must reach
# neither.
PLACEHOLDERS="$(grep -rlF "to be filled in" "$IOS_DIR/NOTICE" "$IOS_DIR/ElementX/SupportingFiles/Settings.bundle" 2>/dev/null || true)"
if [[ ! -f "$IOS_DIR/NOTICE" ]]; then
  fail "no NOTICE at the repository root: the holder and the source offer go unstated"
elif [[ -z "$PLACEHOLDERS" ]]; then
  ok "NOTICE and the acknowledgements name the holder"
else
  fail "a NOTICE placeholder is still there:"
  printf '%s\n' "$PLACEHOLDERS" | sed "s|^$IOS_DIR/|       |"
fi

echo "[8] every file says whose code it is (NOTICE, decision 86)"
# Files Spiral made from Element's code (Tools/Scripts/element-derived-files.txt,
# reviewed) keep Element's header and add "Modified <year> by the Spiral
# authors." (AGPL-3.0 §5(a)); every other Swift file carries Element's header
# or Spiral's, never both. Generated files and third-party "Copyright (c)"
# headers are exempt.
#   (a) a listed file has Element's header and the Modified line, and a file
#       with both is listed;
#   (b) a file added since Element's base (ELEMENT_BASE) with Element's
#       header is listed: a Spiral file never borrows Element's header
#       without saying it was modified;
#   (c) no file mixes a Spiral copyright line with Element's copyright or
#       SPDX line (e.g. a Spiral header followed by Element's SPDX).
# The Element X release the fork last merged (release/26.10.8 since the 1.0.2
# sync; it was 26.08.1's f31207583). Files Element added up to it are
# Element's, and Spiral's changes in them are marked AGENT-PLATFORM (NOTICE).
ELEMENT_BASE="27cdd980d"
DERIVED_LIST="$IOS_DIR/Tools/Scripts/element-derived-files.txt"
ELEMENT_RE='^// Copyright .*(Element Creations|New Vector)'
SPIRAL_RE='^// Copyright [0-9]{4} the Spiral authors\. AGPL-3\.0-or-later\.$'
SPIRAL_ANY_RE='^// Copyright .*the Spiral authors'
MODIFIED_RE='^// Modified [0-9]{4} by the Spiral authors\.$'
SPDX_RE='^// SPDX-License-Identifier:'
CHECKED=('ElementX/*.swift' 'NSE/*.swift' 'UnitTests/*.swift' 'PreviewTests/*.swift' 'UITests/*.swift' 'libraries/*.swift' 'SpiralUI/*.swift' 'SpiralComponents/*.swift' 'ShareExtension/*.swift' 'IntegrationTests/*.swift')
HEADER_FAULTS=""
LISTED="$(mktemp)"; ADDED="$(mktemp)"
trap 'rm -f "$LISTED" "$ADDED"' EXIT
if [[ ! -f "$DERIVED_LIST" ]]; then
  HEADER_FAULTS+="Tools/Scripts/element-derived-files.txt is missing"$'\n'
else
  while IFS= read -r file; do
    file="${file%%#*}"; file="${file%"${file##*[![:space:]]}"}"
    [[ -z "$file" ]] && continue
    printf '%s\n' "$file" >> "$LISTED"
    if [[ ! -f "$IOS_DIR/$file" ]]; then
      HEADER_FAULTS+="$file: listed but missing"$'\n'
    else
      HEAD="$(head -12 "$IOS_DIR/$file")"
      if ! grep -qE "$ELEMENT_RE" <<< "$HEAD" || ! grep -qE "$MODIFIED_RE" <<< "$HEAD"; then
        HEADER_FAULTS+="$file: listed as made from Element's code, needs Element's header and the Modified line"$'\n'
      elif [[ "$(grep -cE "$SPDX_RE" <<< "$HEAD")" != 1 ]]; then
        HEADER_FAULTS+="$file: needs Element's SPDX line exactly once"$'\n'
      fi
    fi
  done < "$DERIVED_LIST"
fi
if git -C "$IOS_DIR" cat-file -e "$ELEMENT_BASE^{commit}" 2>/dev/null; then
  git -C "$IOS_DIR" diff --no-renames --diff-filter=A --name-only "$ELEMENT_BASE" -- "${CHECKED[@]}" > "$ADDED"
else
  HEADER_FAULTS+="Element's base commit $ELEMENT_BASE is not in this clone; check (b) cannot run"$'\n'
fi
while IFS= read -r file; do
  [[ "$file" == */Generated/* ]] && continue
  HEAD="$(head -12 "$IOS_DIR/$file")"
  grep -q "Generated using" <<< "$HEAD" && continue
  grep -qE "Copyright \(c\) [0-9]{4} " <<< "$HEAD" && continue
  HAS_ELEMENT=0; HAS_SPIRAL=0; HAS_MODIFIED=0; IS_LISTED=0
  grep -qE "$ELEMENT_RE" <<< "$HEAD" && HAS_ELEMENT=1
  grep -qE "$SPIRAL_ANY_RE" <<< "$HEAD" && HAS_SPIRAL=1
  grep -qE "$MODIFIED_RE" <<< "$HEAD" && HAS_MODIFIED=1
  grep -qFx "$file" "$LISTED" && IS_LISTED=1
  if [[ $HAS_SPIRAL -eq 1 ]] && { [[ $HAS_ELEMENT -eq 1 ]] || grep -qE "$SPDX_RE" <<< "$HEAD"; }; then
    HEADER_FAULTS+="$file: mixes Spiral's copyright line with Element's copyright or SPDX line"$'\n'
  elif [[ $HAS_ELEMENT -eq 0 ]] && ! grep -qE "$SPIRAL_RE" <<< "$HEAD"; then
    HEADER_FAULTS+="$file: neither Element's header nor Spiral's"$'\n'
  elif [[ $HAS_ELEMENT -eq 1 && $HAS_MODIFIED -eq 1 && $IS_LISTED -eq 0 ]]; then
    HEADER_FAULTS+="$file: has Element's header and the Modified line, but is not in element-derived-files.txt"$'\n'
  elif [[ $HAS_ELEMENT -eq 1 && $IS_LISTED -eq 0 ]] && grep -qFx "$file" "$ADDED"; then
    HEADER_FAULTS+="$file: added since $ELEMENT_BASE with Element's header, but is not in element-derived-files.txt"$'\n'
  fi
done < <(git -C "$IOS_DIR" ls-files -- "${CHECKED[@]}")
if [[ -z "$HEADER_FAULTS" ]]; then
  ok "every listed file is Element's and marked modified; every added file with Element's header is listed; no file has both headers"
else
  fail "file headers that misstate whose code it is (NOTICE):"
  printf '%s' "$HEADER_FAULTS" | sed 's/^/       /'
fi

echo
if [[ $FAIL -eq 0 ]]; then
  echo "preflight-archive: ready ✅  ($MARKETING ($BUILD), SDK $PKG_VERSION)"
else
  echo "preflight-archive: NOT ready ✗"
  exit 1
fi
