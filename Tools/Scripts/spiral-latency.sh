#!/bin/bash
# AGENT-PLATFORM (Brief 0066, § 5.42): ours, not upstream.
# Step 6.14 — price the road an action travels, from the log both ends keep.
#
# The spike has owed this table since 2026-09-14 and every transport argument
# made since has been guesswork without it. Run it after drawing on one
# simulator while the other has the same post on screen.
#
#   ./Tools/Scripts/spiral-latency.sh <sender-udid> <peer-udid>
#
# Two simulators on one Mac share a clock, which is the only reason an
# action can carry the moment it left and have the peer price it alone. On
# real devices apart, these numbers also carry whatever the clocks disagree
# by, and must be read as such.

set -euo pipefail

logfor() {
  local dir
  dir=$(ls -d "$HOME"/Library/Developer/CoreSimulator/Devices/"$1"/data/Containers/Shared/AppGroup/*/Library/Logs/com.veruslogistics.messenger 2>/dev/null | head -1)
  [ -n "$dir" ] || { echo "no log directory for $1" >&2; exit 1; }
  ls -t "$dir"/console.*.log | head -2 | tr '\n' ' '
}

SENDER_LOGS=$(logfor "${1:?sender udid}")
PEER_LOGS=$(logfor "${2:?peer udid}")

python3 - "$SENDER_LOGS" "$PEER_LOGS" <<'PY'
import re, sys, statistics as st

def grab(paths, kind):
    out = []
    for path in paths.split():
        try:
            with open(path, errors="ignore") as handle:
                for line in handle:
                    found = re.search(r"\[spiral-lat\] " + kind + r"[^\n]*?ms=(-?\d+)", line)
                    if found:
                        out.append(int(found.group(1)))
        except FileNotFoundError:
            pass
    return out

def sendtimes(paths):
    stamps = []
    for path in paths.split():
        try:
            with open(path, errors="ignore") as handle:
                for line in handle:
                    if "[spiral-lat] send" in line:
                        found = re.match(r"(\d+)-(\d+)-(\d+)T(\d+):(\d+):([\d.]+)Z", line)
                        if found:
                            h, m, s = int(found.group(4)), int(found.group(5)), float(found.group(6))
                            stamps.append(h * 3600 + m * 60 + s)
        except FileNotFoundError:
            pass
    return sorted(stamps)

def show(label, values):
    if not values:
        print(f"{label:<34} —  (no samples)")
        return
    values = sorted(values)
    p50 = st.median(values)
    p95 = values[min(len(values) - 1, int(round(0.95 * (len(values) - 1))))]
    print(f"{label:<34} n={len(values):<4} p50={p50:>6.0f} ms   p95={p95:>6.0f} ms   max={values[-1]:>6.0f} ms")

sender, peer = sys.argv[1], sys.argv[2]

print("\nACTION → PEER, as measured. Milliseconds.\n")
show("send: encrypt + HTTP to server", grab(sender, "send"))
show("peer: sent → event in hand", grab(peer, "arrive"))
show("peer: sent → folded snapshot", grab(peer, "fold"))
show("self: sent → own snapshot back", grab(sender, "fold"))

gaps = [b - a for a, b in zip(sendtimes(sender), sendtimes(sender)[1:]) if 0 < b - a < 5]
if gaps:
    print()
    show("gap between consecutive sends", [g * 1000 for g in gaps])
    print("\n  A gap at or just above 300 ms is the coalescing window holding a\n"
          "  continuous drag; a longer one is the hand pausing, not the code.")
print()
PY
