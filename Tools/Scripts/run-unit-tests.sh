#!/bin/bash
# AGENT-PLATFORM: reproducible full-UnitTests gate.
#
# Upstream string assertions (DateTests, RoomEventStringBuilderTests, the
# demote* alert-button lookups, UTType descriptions…) assume an ENGLISH
# simulator. Fresh simulators inherit the host macOS language (ru on the
# operator's Mac), so this script finds-or-creates a dedicated en-locale
# simulator named "Spiral-UnitTests-en-27" (iOS 27.0) and runs the whole
# UnitTests scheme on it. BUILDING.md § Tests says what the tests need.
#
# Usage: Tools/Scripts/run-unit-tests.sh [extra xcodebuild args…]
#   e.g. Tools/Scripts/run-unit-tests.sh -only-testing:UnitTests/DateTests

set -euo pipefail
cd "$(dirname "$0")/../.."

# iOS 27.0 since the Element X 1.0.2 sync: upstream's expected sizes in
# MediaUploadingPreprocessorTests are iOS 27's transcoder output. Branches
# still on 26.5 keep their own "Spiral-UnitTests-en".
SIM_NAME="Spiral-UnitTests-en-27"
DEVICE_TYPE="iPhone 17 Pro"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-0"

source Tools/Scripts/test-simulator.sh
prepare_test_simulator "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME"

echo "Running UnitTests on $SIM_NAME ($UDID)…"
LOG=$(mktemp -t spiral-unittests)

set +e
xcodebuild test \
    -project ElementX.xcodeproj \
    -scheme UnitTests \
    -destination "platform=iOS Simulator,id=$UDID" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    -collect-test-diagnostics never \
    "$@" 2>&1 | tee "$LOG" | grep -E '✘ Test [a-zA-Z_]+\(\) recorded|Test run with|\*\* TEST' | sort -u
STATUS=${PIPESTATUS[0]}
set -e

echo
echo "Full log: $LOG"
if [ "$STATUS" -ne 0 ]; then
    echo "❌ UnitTests FAILED (xcodebuild exit $STATUS)"
else
    echo "✅ UnitTests PASSED"
fi
exit "$STATUS"
