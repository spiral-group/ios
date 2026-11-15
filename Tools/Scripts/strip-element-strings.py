#!/usr/bin/env python3
#
# Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
#
# AGENT-PLATFORM (Brief 0083 L1b, decision 302): keeps Element's name out of
# the string tables Spiral ships, without editing upstream's
# Localizable.strings (an upstream sync rewrites it; an edit would conflict).
#
# Each upstream key that names Element is reviewed once and listed below:
# - STRIPPED: no Spiral screen shows it (most have no call site: their
#   Element-only feature was removed), or a `*_spiral` key in
#   Untranslated.strings replaced it at the call site. A Release build
#   removes it from every .lproj of the built app.
# - KEPT: names Element on purpose (the legal attribution).
#
#   strip-element-strings.py check <Localizations dir> [--warn]
#       Fails (or, with --warn, warns) when an en key names Element and is in
#       neither list: an upstream sync brought a new one, so decide which list
#       it joins, or give it a `*_spiral` override first if Spiral shows it.
#   strip-element-strings.py strip <built .app> <Localizations dir>
#       Runs `check`, removes STRIPPED keys from the app's tables, and fails if
#       a key or value there still names Element.
#
# The app target runs `strip` for Release and `check --warn` for Debug, so
# previews and snapshots keep upstream's text for screens Spiral never shows.

import json
import pathlib
import plistlib
import re
import subprocess
import sys

STRIPPED = {
    # Android only; no iOS call site.
    "call_invalid_audio_device_bluetooth_devices_disabled",
    # The Element Call base URL setting went with the Element Call widget (Brief 0067).
    "screen_advanced_settings_element_call_base_url",
    "screen_advanced_settings_element_call_base_url_description",
    "screen_advanced_settings_element_call_base_url_validation_error",
    # No call site: the "Element Pro required" alert went with Element Pro's check
    # (Brief 0083 L1b part 2).
    "screen_change_server_error_element_pro_required_action_ios",
    "screen_change_server_error_element_pro_required_message",
    "screen_change_server_error_element_pro_required_title",
    # No call site: Element Classic's account import and its backup instructions
    # were removed (Brief 0083 L1b part 2).
    "screen_missing_key_backup_open_element_classic",
    "screen_missing_key_backup_step_1",
    "screen_onboarding_welcome_title",
    # Replaced by Untranslated.strings' screen_notification_settings_sound_spiral_*.
    "screen_notification_settings_sound_element_default",
    "screen_notification_settings_sound_element_fade",
    # Replaced by screen_room_timeline_legacy_call_spiral.
    "screen_room_timeline_legacy_call",
    # No call site.
    "screen_server_confirmation_message_login_element_dot_io",
}
KEPT = {
    # Settings > About: what Spiral is built on (AGPL attribution).
    "screen_legal_information_based_on_element_spiral",
}

# In English, "Element" as a word is the brand; the welcome pun is lowercase.
NAMES_ELEMENT_IN_EN = re.compile(r"(?<![A-Za-z])Element(?![a-z])|(?i:element\.io|in your element)")
# In any language: unambiguous brand tokens (German and Uzbek use the word "Element" for an item).
NAMES_ELEMENT_ANYWHERE = re.compile(r"ElementX|Element (X|Call|Pro|Classic)|(?i:element\.io)")
KEY_NAMES_ELEMENT = re.compile(r"(?i)element")


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "check":
        check(pathlib.Path(sys.argv[2]), warn="--warn" in sys.argv[3:])
    elif len(sys.argv) == 4 and sys.argv[1] == "strip":
        localizations = pathlib.Path(sys.argv[3])
        check(localizations, warn=False)
        strip(pathlib.Path(sys.argv[2]))
    else:
        sys.exit("usage: strip-element-strings.py check <Localizations dir> [--warn] | strip <built .app> <Localizations dir>")


def check(localizations, warn):
    en = {}
    for table in sorted((localizations / "en.lproj").glob("*.strings*")):
        en.update(read_table(table))
    if not en:
        sys.exit(f"error: strip-element-strings.py: no en.lproj tables in {localizations}")
    named ={key for key, value in en.items() if KEY_NAMES_ELEMENT.search(key) or NAMES_ELEMENT_IN_EN.search(text_of(value))}
    unreviewed = sorted(named - STRIPPED - KEPT)
    for key in sorted(STRIPPED - en.keys()):
        print(f"warning: strip-element-strings.py: {key} is no longer in en.lproj; remove it from STRIPPED")
    if unreviewed:
        level = "warning" if warn else "error"
        for key in unreviewed:
            print(f"{level}: strip-element-strings.py: en.lproj's {key} names Element and is not reviewed: "
                  f"give it a *_spiral override if Spiral shows it, then list it in STRIPPED (or KEPT)")
        if not warn:
            sys.exit(1)


def strip(app):
    lprojs = sorted(app.glob("*.lproj"))
    if not lprojs:
        sys.exit(f"error: strip-element-strings.py: no .lproj in {app}")
    removed = 0
    problems = []
    for lproj in lprojs:
        for path in sorted(lproj.glob("*.strings*")):
            table = read_table(path)
            kept = {key: value for key, value in table.items() if key not in STRIPPED}
            if len(kept) != len(table):
                removed += len(table) - len(kept)
                path.write_bytes(plistlib.dumps(kept, fmt=plistlib.FMT_BINARY))
            for key, value in kept.items():
                if key in KEPT:
                    continue
                text = text_of(value)
                english = lproj.stem in ("en", "en-US") and NAMES_ELEMENT_IN_EN.search(text)
                if KEY_NAMES_ELEMENT.search(key) or NAMES_ELEMENT_ANYWHERE.search(text) or english:
                    problems.append(f"{lproj.name}/{path.name}: {key}")
    for problem in problems:
        print(f"error: strip-element-strings.py: the built app still names Element in {problem}")
    if problems:
        sys.exit(1)
    print(f"strip-element-strings.py: removed {removed} entries from {len(lprojs)} .lproj folders; none names Element now")


def read_table(path):
    """A .strings or .stringsdict table in any format plutil reads (text, XML or binary)."""
    converted = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(path)], capture_output=True, check=True)
    return json.loads(converted.stdout)


def text_of(value):
    """A string's text, or every text of a plural entry."""
    return value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)


if __name__ == "__main__":
    main()
