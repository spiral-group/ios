#!/bin/bash
# AGENT-PLATFORM: reproducible PreviewTests gate.
#
# Two things have to be true at once for a snapshot to match, and the tooling
# guarantees neither on its own:
#
#   1. The DEVICE must be an iPhone SE 3rd gen. `PreviewTests.checkEnvironments`
#      calls `fatalError` otherwise — which surfaces as a macOS crash dialog
#      with zero tests run, and reads like a broken build rather than a wrong
#      destination.
#   2. The LOCALE must be English. Snapshots are pixels, and most of these have
#      text in them. Fresh simulators inherit the host macOS language (ru on the
#      operator's Mac), so a simulator created by anything that does not force
#      this will differ from every committed reference.
#
# `swift run tools ci preview-tests` satisfies (1) and not (2): it creates a
# simulator NAMED "iPhone SE (3rd generation)" if one does not exist, inheriting
# the host locale. With --record that rewrote 1064 snapshots in one run — all of
# them correct English references replaced with Russian ones. This script exists
# so that cannot happen again.
#
# Usage: Tools/Scripts/run-preview-tests.sh [--record] [extra xcodebuild args…]
#   e.g. Tools/Scripts/run-preview-tests.sh --record
#        Tools/Scripts/run-preview-tests.sh -only-testing:PreviewTests/PreviewTests

set -euo pipefail
cd "$(dirname "$0")/../.."

SIM_NAME="Spiral-PreviewTests-SE"
DEVICE_TYPE="iPhone SE (3rd generation)"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-26-5"

RECORD=false
ARGS=()
for arg in "$@"; do
    if [ "$arg" = "--record" ]; then
        RECORD=true
    else
        ARGS+=("$arg")
    fi
done

UDID=$(xcrun simctl list devices | grep "$SIM_NAME (" | grep -oE '[0-9A-F-]{36}' | head -1 || true)

if [ -z "$UDID" ]; then
    echo "Creating $SIM_NAME ($DEVICE_TYPE, $RUNTIME)…"
    UDID=$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME")
    xcrun simctl boot "$UDID"
    # Force English regardless of the host macOS language. Without this every
    # snapshot containing text is a false failure — and a false RE-RECORD.
    xcrun simctl spawn "$UDID" defaults write .GlobalPreferences AppleLanguages -array en-US
    xcrun simctl spawn "$UDID" defaults write .GlobalPreferences AppleLocale -string en_US
    xcrun simctl shutdown "$UDID"
fi

if [ "$RECORD" = true ]; then
    # Passed as an environment variable rather than by editing the test plan,
    # which is what `tools ci preview-tests --record` does — and it does not put
    # the plan back, so a forgotten flag silently re-records for ever after.
    #
    # The value must parse as a Swift `Bool`: `1` is accepted by the shell and
    # then silently does nothing.
    export TEST_RUNNER_RECORD_FAILURES=true
    echo "⚠️  RECORDING — every failing snapshot will be overwritten."
fi

echo "Running PreviewTests on $SIM_NAME ($UDID)…"
LOG=$(mktemp -t spiral-previewtests)

set +e
xcodebuild test \
    -project ElementX.xcodeproj \
    -scheme PreviewTests \
    -destination "platform=iOS Simulator,id=$UDID" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    -collect-test-diagnostics never \
    ${ARGS[@]+"${ARGS[@]}"} 2>&1 | tee "$LOG" | grep -E '✘ Test [a-zA-Z_]+\(\) recorded|Test run with|\*\* TEST' | sort -u
STATUS=${PIPESTATUS[0]}
set -e

echo
echo "Full log: $LOG"
if [ "$RECORD" = true ]; then
    echo "📸 Recorded. Check git status — a snapshot you did not mean to touch means the wrong simulator."
elif [ "$STATUS" -ne 0 ]; then
    echo "❌ PreviewTests FAILED (xcodebuild exit $STATUS)"
else
    echo "✅ PreviewTests PASSED"
fi
exit "$STATUS"
