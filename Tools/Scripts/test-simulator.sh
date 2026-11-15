#!/bin/bash
#
# Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
#
# AGENT-PLATFORM: the one simulator set-up behind run-unit-tests.sh,
# run-preview-tests.sh, run-ui-tests.sh and run-accessibility-tests.sh.
# Sourced, not run:
#
#   source Tools/Scripts/test-simulator.sh   # after cd to the repo root
#   prepare_test_simulator "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME"   # sets UDID
#
# It finds or creates the named simulator, refuses one of that name on
# another runtime, waits out a boot or shutdown already in flight, boots
# it, and pins language, locale and keyboards to en-US on every run. A
# simulator it has just created is rebooted once after that, so its first
# test run already starts in English with the right keyboards.
#
# SPIRAL_TEST_SIM_SUFFIX (e.g. "-dm") is appended to the simulator's name,
# so lanes testing in parallel worktrees don't share a simulator. A test run
# on a simulator another run is using fails or hangs.

prepare_test_simulator() {
    local name="$1${SPIRAL_TEST_SIM_SUFFIX:-}" device_type=$2 runtime=$3
    local created=false
    SIM_NAME=$name  # the callers' later messages name the simulator actually used

    UDID=$(xcrun simctl list devices | grep -F "$name (" | grep -oE '[0-9A-F-]{36}' | head -1 || true)

    if [ -z "$UDID" ]; then
        echo "Creating $name ($device_type, $runtime)…"
        UDID=$(xcrun simctl create "$name" "$device_type" "$runtime")
        created=true
    fi

    # A simulator of this name on another runtime is somebody else's; never run on it.
    local actual_runtime
    actual_runtime=$(plutil -extract runtime raw "$HOME/Library/Developer/CoreSimulator/Devices/$UDID/device.plist")
    if [ "$actual_runtime" != "$runtime" ]; then
        echo "❌ $name ($UDID) is on $actual_runtime, not $runtime." >&2
        exit 1
    fi

    boot_test_simulator
    pin_test_simulator_to_english

    if [ "$created" = true ]; then
        # Language and keyboards are read at boot; a fresh device booted
        # before they were written would run its first tests in the host's.
        xcrun simctl shutdown "$UDID"
        boot_test_simulator
    fi
}

boot_test_simulator() {
    local state
    for _ in $(seq 1 60); do
        state=$(test_simulator_state)
        case "$state" in
            Booting|"Shutting Down"|Creating) sleep 2 ;;
            *) break ;;
        esac
    done

    case "$state" in
        Booted) ;;
        Shutdown) xcrun simctl boot "$UDID" ;;
        *)
            echo "❌ $UDID is stuck in state \"$state\"." >&2
            exit 1
            ;;
    esac

    # Returns once the device has finished booting, not just started.
    xcrun simctl bootstatus "$UDID" > /dev/null
}

test_simulator_state() {
    xcrun simctl list devices | grep "$UDID" | sed -E 's/.*\(([^()]*)\)[[:space:]]*$/\1/'
}

# A simulator that was ever used by hand may have picked up the host's
# language or keyboards (ru/uk on the operator's Mac): without this every
# assertion and snapshot with text in it is a false failure — and, when
# recording, a false RE-RECORD.
pin_test_simulator_to_english() {
    xcrun simctl spawn "$UDID" defaults write .GlobalPreferences AppleLanguages -array en-US
    xcrun simctl spawn "$UDID" defaults write .GlobalPreferences AppleLocale -string en_US
    xcrun simctl spawn "$UDID" defaults write .GlobalPreferences AppleKeyboards -array \
        "en_US@sw=QWERTY;hw=Automatic" "emoji@sw=Emoji"
    xcrun simctl spawn "$UDID" defaults write com.apple.Preferences KeyboardContinuousPathEnabled -bool false
}
