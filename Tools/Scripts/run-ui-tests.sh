#!/bin/bash
# AGENT-PLATFORM: reproducible UITests gate (audit wave 8 close-out).
#
# The sibling of run-unit-tests.sh, and it exists for the same disease with
# one extra organ: the KEYBOARD. UITests screenshots include whatever
# keyboard the simulator shows, and a fresh simulator inherits the host
# macOS input sources — `testReportText`'s reference shipped recorded
# against a UKRAINIAN keyboard and could never match a clean en device.
# This script finds-or-creates "Spiral-UITests-en" (iPhone 17 — the model
# is hard-required by UITests/Sources/Application.swift's deviceName
# assumptions) and pins language, locale AND keyboards to en-US before
# every run.
#
# Snapshot recording: Application.swift uses `record: .missing`, so a
# deleted reference re-records itself on the next run. Delete the stale
# file, run this twice — once to record, once to prove stability.
#
# Usage: Tools/Scripts/run-ui-tests.sh [extra xcodebuild args…]
#   e.g. Tools/Scripts/run-ui-tests.sh -only-testing:UITests/BugReportTests

set -euo pipefail
cd "$(dirname "$0")/../.."

SIM_NAME="Spiral-UITests-en"
DEVICE_TYPE="iPhone 17"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-26-5"

UDID=$(xcrun simctl list devices | grep "$SIM_NAME (" | grep -oE '[0-9A-F-]{36}' | head -1 || true)

if [ -z "$UDID" ]; then
    echo "Creating $SIM_NAME ($DEVICE_TYPE, $RUNTIME)…"
    UDID=$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME")
fi

STATE=$(xcrun simctl list devices | grep "$UDID" | grep -oE '\((Booted|Shutdown)\)' | tr -d '()')
if [ "$STATE" != "Booted" ]; then
    xcrun simctl boot "$UDID"
fi

# Pin the input world on EVERY run, not just at creation — a simulator that
# was ever used interactively may have picked up the host's keyboards.
xcrun simctl spawn "$UDID" defaults write .GlobalPreferences AppleLanguages -array en-US
xcrun simctl spawn "$UDID" defaults write .GlobalPreferences AppleLocale -string en_US
xcrun simctl spawn "$UDID" defaults write .GlobalPreferences AppleKeyboards -array \
    "en_US@sw=QWERTY;hw=Automatic" "emoji@sw=Emoji"
xcrun simctl spawn "$UDID" defaults write com.apple.Preferences KeyboardContinuousPathEnabled -bool false

echo "Running UITests on $SIM_NAME ($UDID)…"
xcodebuild test \
    -project ElementX.xcodeproj \
    -scheme UITests \
    -destination "platform=iOS Simulator,id=$UDID" \
    -collect-test-diagnostics never \
    "$@"
