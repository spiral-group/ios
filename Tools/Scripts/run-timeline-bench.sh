#!/bin/bash
#
# Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
#
# AGENT-PLATFORM (Brief 0083, question 359 item 16): the chat timeline's benchmark.
#
# Builds the app with SPIRAL_TIMELINE_BENCH, which turns the launch into the harness in
# ElementX/Sources/UITests/TimelineBench: the real room screen over a fixed fixture, no network. No project file sets the
# flag, so none of this reaches a Debug, Release or Staging build made any other way. The build is Release's: -O, whole
# module, no DEBUG, as the numbers of an unoptimised build say little.
#
# Usage:
#   Tools/Scripts/run-timeline-bench.sh run [--label name] [--runs n] [--scenarios a,b] [--no-build] [--speed pts] [--out file.json]
#   Tools/Scripts/run-timeline-bench.sh show <result.json>
#   Tools/Scripts/run-timeline-bench.sh compare <before.json> <after.json>
#   Tools/Scripts/run-timeline-bench.sh trace <template> [--seconds n] [--scenario soak] [--out dir] [--no-build]
#   Tools/Scripts/run-timeline-bench.sh shutdown
#
# Scenarios: open, update, scroll, pagination, messages, reaction, post, postscroll, each its own launch. `run` takes the median of the runs.
#
# Results land in TIMELINE_BENCH_RESULTS (default ~/Library/Application Support/Spiral/timeline-bench), outside the repo.
# Export SPIRAL_TEST_SIM_SUFFIX and SPIRAL_DERIVED_DATA for a lane's slot, e.g. "-s3" and
# ~/Library/Developer/Xcode/DerivedData-spiral/slot-3.

set -euo pipefail
cd "$(dirname "$0")/../.."

# The bench uninstalls the app and shuts its simulator down, so it never takes the shared one, nor a build folder of the app's.
case "${1:-}" in
    run|trace|shutdown)
        if [ -z "${SPIRAL_TEST_SIM_SUFFIX:-}" ] || [ -z "${SPIRAL_DERIVED_DATA:-}" ]; then
            echo "Set SPIRAL_TEST_SIM_SUFFIX and SPIRAL_DERIVED_DATA to the slot's, as in the README." >&2
            exit 64
        fi
        ;;
esac

SIM_BASE_NAME="Spiral-UnitTests-en-27"
SIM_NAME="$SIM_BASE_NAME${SPIRAL_TEST_SIM_SUFFIX:-}"
DEVICE_TYPE="iPhone 17 Pro"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-0"
BUNDLE_ID="com.veruslogistics.messenger"

DERIVED_DATA="${SPIRAL_DERIVED_DATA:-$PWD/.build-sim}"
CONFIGURATION="${TIMELINE_BENCH_CONFIGURATION:-Release}"
RESULTS="${TIMELINE_BENCH_RESULTS:-$HOME/Library/Application Support/Spiral/timeline-bench}"
APP="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphonesimulator/Spiral.app"
ALL_SCENARIOS="open,update,scroll,pagination,messages,reaction,post,postscroll"
SCENARIO_TIMEOUT=${TIMELINE_BENCH_TIMEOUT:-240}

source Tools/Scripts/test-simulator.sh

# A booted simulator holds gigabytes, so it only runs for as long as a measurement does: a build doesn't need it, and it
# goes down however the run ends.
boot_simulator() {
    trap shutdown_simulator EXIT
    prepare_test_simulator "$SIM_BASE_NAME" "$DEVICE_TYPE" "$RUNTIME"
}

find_simulator() {
    UDID=$(xcrun simctl list devices | grep -F "$SIM_NAME (" | grep -oE '[0-9A-F-]{36}' | head -1 || true)
    [ -n "$UDID" ] || boot_simulator
}

build_app() {
    local log
    log=$(mktemp -t spiral-timeline-bench)
    echo "Building $CONFIGURATION with SPIRAL_TIMELINE_BENCH (log: $log)…"
    # ONLY_ACTIVE_ARCH: Release builds both simulator slices otherwise, and MatrixRustSDK has no x86_64 one.
    # dwarf: the symbol table is enough for a profiler, and a dSYM of this binary takes minutes.
    if ! xcodebuild build \
        -project ElementX.xcodeproj \
        -scheme ElementX \
        -configuration "$CONFIGURATION" \
        -destination "platform=iOS Simulator,id=$UDID" \
        -derivedDataPath "$DERIVED_DATA" \
        -skipPackagePluginValidation \
        -skipMacroValidation \
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) SPIRAL_TIMELINE_BENCH' \
        ONLY_ACTIVE_ARCH=YES \
        DEBUG_INFORMATION_FORMAT=dwarf > "$log" 2>&1; then
        grep -E "error:|BUILD FAILED" "$log" | sort -u | head -30 >&2
        echo "❌ The build failed: $log" >&2
        exit 1
    fi
    rm -f "$log"
}

install_app() {
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1 || true
    xcrun simctl uninstall "$UDID" "$BUNDLE_ID" > /dev/null 2>&1 || true
    xcrun simctl install "$UDID" "$APP"
}

# Runs one scenario in a new process and copies its result to $2.
launch_scenario() {
    local scenario=$1 output=$2 extra=${3:-}
    local container result

    container=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
    result="$container/Documents/timeline-bench-$scenario.json"
    rm -f "$result"

    # shellcheck disable=SC2086 # `extra` is a list of VAR=value pairs.
    env SIMCTL_CHILD_TIMELINE_BENCH_SCENARIO="$scenario" $extra \
        xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" > /dev/null

    local waited=0
    until [ -s "$result" ]; do
        sleep 1
        waited=$((waited + 1))
        if [ "$waited" -ge "$SCENARIO_TIMEOUT" ]; then
            xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1 || true
            echo "❌ Scenario $scenario gave no result in $SCENARIO_TIMEOUT s." >&2
            return 1
        fi
    done
    sleep 1 # The file is written in one go, and the process leaves right after.
    cp "$result" "$output"
}

run_bench() {
    local label="" runs=3 scenarios="$ALL_SCENARIOS" should_build=true speed="" output=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --label) label=$2; shift 2 ;;
            --runs) runs=$2; shift 2 ;;
            --scenarios) scenarios=$2; shift 2 ;;
            --speed) speed=$2; shift 2 ;;
            --out) output=$2; shift 2 ;;
            --no-build) should_build=false; shift ;;
            *) echo "Unknown option $1" >&2; exit 2 ;;
        esac
    done

    if [ "$should_build" = true ]; then
        find_simulator
        build_app
    fi
    boot_simulator
    install_app

    local commit stamp work extra=""
    commit=$(git rev-parse --short HEAD)
    [ -n "$(git status --porcelain -- ElementX compound-ios SpiralUI SpiralComponents)" ] && commit="$commit+dirty"
    stamp=$(date +%Y%m%d-%H%M%S)
    label=${label:-$commit}
    output=${output:-$RESULTS/$stamp-$label.json}
    work=$(mktemp -d -t spiral-timeline-bench)
    [ -n "$speed" ] && extra="SIMCTL_CHILD_TIMELINE_BENCH_SPEED=$speed"
    mkdir -p "$(dirname "$output")"

    local run scenario load_before
    load_before=$(sysctl -n vm.loadavg)
    for run in $(seq 1 "$runs"); do
        for scenario in ${scenarios//,/ }; do
            echo "[$run/$runs] $scenario"
            launch_scenario "$scenario" "$work/$scenario-$run.json" "$extra"
        done
    done

    python3 Tools/Scripts/timeline-bench-report.py merge "$work" "$output" \
        --label "$label" --runs "$runs" --commit "$commit" --simulator "$SIM_NAME" --configuration "$CONFIGURATION" --load "$load_before → $(sysctl -n vm.loadavg)"
    rm -rf "$work"
    echo
    python3 Tools/Scripts/timeline-bench-report.py show "$output"
    echo
    echo "Results: $output"
}

# Records a template against the harness while it scrolls.
trace_bench() {
    local template=$1 seconds=30 scenario=soak should_build=true output="$RESULTS/traces"
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --seconds) seconds=$2; shift 2 ;;
            --scenario) scenario=$2; shift 2 ;;
            --out) output=$2; shift 2 ;;
            --no-build) should_build=false; shift ;;
            *) echo "Unknown option $1" >&2; exit 2 ;;
        esac
    done

    if [ "$should_build" = true ]; then
        find_simulator
        build_app
    fi
    boot_simulator
    install_app
    mkdir -p "$output"

    local trace pid
    trace="$output/$(date +%Y%m%d-%H%M%S)-${template// /-}-$scenario.trace"
    pid=$(env SIMCTL_CHILD_TIMELINE_BENCH_SCENARIO="$scenario" SIMCTL_CHILD_TIMELINE_BENCH_SECONDS=$((seconds + 8)) \
        xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" | awk '{ print $NF }')
    sleep 3 # Past the launch, so the trace holds the scrolling.

    xcrun xctrace record --template "$template" --device "$UDID" --attach "$pid" --time-limit "${seconds}s" --output "$trace" --no-prompt
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1 || true
    echo "Trace: $trace"
    python3 Tools/Scripts/read-xctrace.py "$trace" --process Spiral
}

shutdown_simulator() {
    local udid
    udid=$(xcrun simctl list devices | grep -F "$SIM_NAME (" | grep -oE '[0-9A-F-]{36}' | head -1 || true)
    [ -n "$udid" ] && xcrun simctl shutdown "$udid" > /dev/null 2>&1 || true
    echo "$SIM_NAME is shut down."
}

case "${1:-}" in
    run) shift; run_bench "$@" ;;
    show) shift; python3 Tools/Scripts/timeline-bench-report.py show "$@" ;;
    compare) shift; python3 Tools/Scripts/timeline-bench-report.py compare "$@" ;;
    trace) shift; trace_bench "$@" ;;
    shutdown) shutdown_simulator ;;
    *) sed -n '/^# Usage:/,/^# Scenarios:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
