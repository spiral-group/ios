#!/bin/bash
#
# Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
#
# AGENT-PLATFORM (Brief 0083 L1c): reproducible AccessibilityTests gate.
#
# AccessibilityTests launch the app once per preview and run Xcode's
# accessibility audit on every state. Previews that conform to
# SpiralGatedPreview get Spiral's stricter audit, `contrast` and `textClipped`
# included, once in light and once in dark.
#
# The audit has no reference images, but what it finds depends on the text on
# screen, so it runs on its own locked-down en-US phone, the way the other
# scripts do: "Spiral-AccessibilityTests-en-27", an iPhone 17 on iOS 27.0
# (`Application.checkEnvironments` wants a phone).
#
# A run that executed no test fails: a typo in `-only-testing:` would
# otherwise report success.
#
# Usage: Tools/Scripts/run-accessibility-tests.sh [extra xcodebuild args…]
#   e.g. Tools/Scripts/run-accessibility-tests.sh -only-testing:AccessibilityTests/AccessibilityTests/testSpiralGatesFixture

set -euo pipefail
cd "$(dirname "$0")/../.."

SIM_NAME="Spiral-AccessibilityTests-en-27"
DEVICE_TYPE="iPhone 17"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-0"

source Tools/Scripts/test-simulator.sh
prepare_test_simulator "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME"

# AGENT-PLATFORM (Brief 0083): a preview that focuses a field is audited with
# the software keyboard up, the same on every run. Read at the app's launch,
# so no reboot is needed. Only this simulator: UI tests screenshot keyboards.
# - iOS 26+ minimises the keyboard below the screen (y 918) whenever
#   CoreSimulator reports a hardware keyboard, which nothing in the device
#   decides; the audit then saw no keyboard, sometimes for half an hour.
# - The predictive bar sits above the keyboard's frame (y 546-590), and its
#   unlabelled cells failed FeedComposerScreen's audit 2 runs of 3.
xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.preferences AutomaticMinimizationEnabled -bool false
xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.preferences KeyboardPrediction -bool false

echo "Running AccessibilityTests on $SIM_NAME ($UDID)…"
LOG=$(mktemp -t spiral-accessibilitytests)

set +e
xcodebuild test \
    -project ElementX.xcodeproj \
    -scheme AccessibilityTests \
    -destination "platform=iOS Simulator,id=$UDID" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    -collect-test-diagnostics never \
    "$@" 2>&1 | tee "$LOG" | grep -E "error: -\[|A11Y (ISSUE|HELD|BAR|EXEMPT)|Expected failure in|Executed [0-9]+ tests?|\*\* TEST"
STATUS=${PIPESTATUS[0]}
set -e

EXECUTED=$(grep -oE "Executed [0-9]+ tests?" "$LOG" | tail -1 | grep -oE "[0-9]+" || echo 0)

echo
echo "Full log: $LOG"
if [ "$STATUS" -ne 0 ]; then
    echo "❌ AccessibilityTests FAILED (xcodebuild exit $STATUS)"
elif [ "$EXECUTED" -eq 0 ]; then
    echo "❌ AccessibilityTests ran no test. Check the -only-testing: name."
    STATUS=1
else
    echo "✅ AccessibilityTests PASSED ($EXECUTED tests)"
fi
exit "$STATUS"
