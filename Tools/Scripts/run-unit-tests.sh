#!/bin/bash
# AGENT-PLATFORM: reproducible full-UnitTests gate.
#
# Upstream string assertions (DateTests, RoomEventStringBuilderTests, the
# demote* alert-button lookups, UTType descriptions…) assume an ENGLISH
# simulator. Fresh simulators inherit the host macOS language (ru on the
# operator's Mac), so this script finds-or-creates a dedicated en-locale
# simulator named "Spiral-UnitTests-en" and runs the whole UnitTests scheme
# on it. BUILDING.md § Tests says what the tests need.
#
# Usage: Tools/Scripts/run-unit-tests.sh [extra xcodebuild args…]
#   e.g. Tools/Scripts/run-unit-tests.sh -only-testing:UnitTests/DateTests

set -euo pipefail
cd "$(dirname "$0")/../.."

SIM_NAME="Spiral-UnitTests-en"
DEVICE_TYPE="iPhone 17 Pro"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-26-5"

UDID=$(xcrun simctl list devices | grep "$SIM_NAME (" | grep -oE '[0-9A-F-]{36}' | head -1 || true)

if [ -z "$UDID" ]; then
    echo "Creating $SIM_NAME ($DEVICE_TYPE, $RUNTIME)…"
    UDID=$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME")
    xcrun simctl boot "$UDID"
    # Force English regardless of the host macOS language.
    xcrun simctl spawn "$UDID" defaults write .GlobalPreferences AppleLanguages -array en-US
    xcrun simctl spawn "$UDID" defaults write .GlobalPreferences AppleLocale -string en_US
    xcrun simctl shutdown "$UDID"
fi

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
