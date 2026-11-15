#!/bin/bash
# AGENT-PLATFORM: reproducible UITests gate (audit wave 8 close-out).
#
# The sibling of run-unit-tests.sh, and it exists for the same disease with
# one extra organ: the KEYBOARD. UITests screenshots include whatever
# keyboard the simulator shows, and a fresh simulator inherits the host
# macOS input sources — `testReportText`'s reference shipped recorded
# against a UKRAINIAN keyboard and could never match a clean en device.
# This script finds-or-creates "Spiral-UITests-en-27" (iPhone 17 on iOS
# 27.0 — both are hard-required by UITests/Sources/Application.swift's
# `checkEnvironments`) and pins language, locale AND keyboards to en-US
# before every run.
#
# Snapshot recording: Application.swift uses `record: .missing`, so a
# deleted reference re-records itself on the next run. Delete the stale
# file, run this twice — once to record, once to prove stability.
#
# Usage: Tools/Scripts/run-ui-tests.sh [extra xcodebuild args…]
#   e.g. Tools/Scripts/run-ui-tests.sh -only-testing:UITests/BugReportTests

set -euo pipefail
cd "$(dirname "$0")/../.."

# iOS 27.0 since the Element X 1.0.2 sync (Application.swift's
# `checkEnvironments` wants 27.0). Branches still on 26.5 keep their own
# "Spiral-UITests-en".
SIM_NAME="Spiral-UITests-en-27"
DEVICE_TYPE="iPhone 17"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-0"

source Tools/Scripts/test-simulator.sh
prepare_test_simulator "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME"

echo "Running UITests on $SIM_NAME ($UDID)…"
xcodebuild test \
    -project ElementX.xcodeproj \
    -scheme UITests \
    -destination "platform=iOS Simulator,id=$UDID" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    -collect-test-diagnostics never \
    "$@"
