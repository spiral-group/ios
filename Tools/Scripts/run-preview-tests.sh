#!/bin/bash
# AGENT-PLATFORM: reproducible PreviewTests gate.
#
# Two things have to be true at once for a snapshot to match, and the tooling
# guarantees neither on its own:
#
#   1. The DEVICE must be an iPhone SE 3rd gen on iOS 27.0.
#      `PreviewTests.checkEnvironments` calls `fatalError` otherwise — which
#      surfaces as a macOS crash dialog with zero tests run, and reads like a
#      broken build rather than a wrong destination.
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
# Usage: Tools/Scripts/run-preview-tests.sh [--record] [--pre-glass] [extra xcodebuild args…]
#   e.g. Tools/Scripts/run-preview-tests.sh --record
#        Tools/Scripts/run-preview-tests.sh -only-testing:PreviewTests/PreviewTests
#        Tools/Scripts/run-preview-tests.sh --pre-glass
#
# --pre-glass (Brief 0083 L1c) is the iOS 18 lane. iOS 18.6 has no Liquid
# Glass, so it shows the look Spiral keeps for iOS 18.5 to 25. It runs only
# SpiralGatedPreviewTests, the previews that conform to SpiralGatedPreview, on
# "Spiral-PreviewTests-SE-18", against __Snapshots__/PreviewTests-preGlass.
# PreviewTests.checkEnvironments refuses upstream's suite on that OS.
#
# A run that executed no test fails: a typo in -only-testing:, or a lane with
# no opted-in preview, would otherwise report success.

set -euo pipefail
cd "$(dirname "$0")/../.."

# iOS 27.0 since the Element X 1.0.2 sync (upstream's `checkEnvironments`
# wants 27.0). Branches still on 26.5 keep their own "Spiral-PreviewTests-SE";
# this one is a separate simulator so neither run disturbs the other.
SIM_NAME="Spiral-PreviewTests-SE-27"
DEVICE_TYPE="iPhone SE (3rd generation)"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-0"

RECORD=false
PRE_GLASS=false
ONLY_TESTING=false
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --record) RECORD=true ;;
        --pre-glass) PRE_GLASS=true ;;
        -only-testing:*) ONLY_TESTING=true; ARGS+=("$arg") ;;
        *) ARGS+=("$arg") ;;
    esac
done

if [ "$PRE_GLASS" = true ]; then
    SIM_NAME="Spiral-PreviewTests-SE-18"
    RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-18-6"
    if [ "$ONLY_TESTING" = false ]; then
        ARGS+=("-only-testing:PreviewTests/SpiralGatedPreviewTests")
    fi
fi

source Tools/Scripts/test-simulator.sh
prepare_test_simulator "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME"

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

# The fewest tests any test plan configuration ran.
RAN=$(grep -oE "Test run with [0-9]+ tests?" "$LOG" | grep -oE "[0-9]+" | sort -n | head -1 || true)

echo
echo "Full log: $LOG"
if [ -z "$RAN" ] || [ "$RAN" -eq 0 ]; then
    echo "❌ PreviewTests ran no test (xcodebuild exit $STATUS): check the build, the -only-testing: names, or that a preview conforms to SpiralGatedPreview."
    [ "$STATUS" -ne 0 ] || STATUS=1
elif [ "$RECORD" = true ]; then
    echo "📸 Recorded. Check git status — a snapshot you did not mean to touch means the wrong simulator."
elif [ "$STATUS" -ne 0 ]; then
    echo "❌ PreviewTests FAILED (xcodebuild exit $STATUS)"
else
    echo "✅ PreviewTests PASSED"
fi
exit "$STATUS"
