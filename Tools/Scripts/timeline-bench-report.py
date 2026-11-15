#!/usr/bin/env python3
#
# Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
#
# AGENT-PLATFORM (Brief 0083, question 359 item 16): reads the timeline benchmark's results. run-timeline-bench.sh calls it.
#
#   timeline-bench-report.py merge <folder of runs> <result.json> --label … --runs … --commit … --simulator … --configuration … --load …
#   timeline-bench-report.py show <result.json>
#   timeline-bench-report.py compare <before.json> <after.json> [--all]
#
# Every metric is a median over the runs, with its range. Lower is better for all of them apart from the frame rate and
# the counts of what was measured, which `compare` leaves out of its verdict.

import argparse
import datetime
import glob
import json
import os
import platform
import statistics
import subprocess
import sys

UPDATE_SIZES = (100, 300, 500)
SCROLL_PASSES = ("up1", "down1", "up2", "down2", "paginated")
# What a change has to be judged on: the CPU numbers, as a simulator can't price the GPU.
HEADLINES = (
    [f"update.{rows}.{kind}.build_cpu_ms_p50" for rows in UPDATE_SIZES for kind in ("append", "change")]
    + [f"update.{rows}.{kind}.total_cpu_ms_p50" for rows in UPDATE_SIZES for kind in ("append", "change")]
    + [f"update.{rows}.burst.main_cpu_ms" for rows in UPDATE_SIZES]
    + [f"update.{rows}.burst_paced.main_cpu_ms" for rows in UPDATE_SIZES]
    + [f"scroll.{name}.{metric}" for name in SCROLL_PASSES
       for metric in ("frame_cpu_ms_p50", "frame_cpu_ms_p95", "frame_cpu_ms_p99", "frames_over_8ms_pct", "frames_over_16ms_pct", "hitch_ratio_ms_per_s", "longest_frame_ms", "dropped_frames", "jumps")]
    + ["open.cold.first_rows_cpu_ms", "open.cold.first_frame_ms", "open.cold.settled_cpu_ms", "open.warm.first_rows_cpu_ms", "open.warm.first_frame_ms"]
    + ["messages.row_bodies", "messages.rows_rerendered", "messages.styler_bodies", "messages.main_cpu_ms"]
    + ["reaction.add.row_bodies", "reaction.add.rows_rerendered", "reaction.add.styler_bodies", "reaction.add.total_cpu_ms"]
    + ["post.drawn_ms_median", "post.longest_frame_ms_median", "post.jump_frame_ms_median", "post.start_frame_ms_median", "post.start_frame_ms_max", "post.main_cpu_ms_median"]
    + [f"postscroll.{name}.{metric}" for name in ("up", "down") for metric in ("frame_cpu_ms_p95", "frame_cpu_ms_p99", "hitch_ratio_ms_per_s", "longest_frame_ms", "dropped_frames")]
    + ["memory.peak_mb", "memory.after_idle_mb"]
)
# Counts of what happened rather than costs: a change here is a fact, not a verdict.
NEUTRAL_SUFFIXES = (".frames", ".duration_s", ".refresh_hz", ".count", ".size_count", ".visible_rows", ".cells_made")


def merge(args):
    runs = {}
    infos = {}
    for path in sorted(glob.glob(os.path.join(args.folder, "*.json"))):
        with open(path, encoding="utf-8") as file:
            result = json.load(file)
        infos[result["info"]["scenario"]] = result["info"]
        for name, value in result["metrics"].items():
            runs.setdefault(name, []).append(value)

    metrics = {name: {"median": statistics.median(values), "min": min(values), "max": max(values), "runs": values} for name, values in sorted(runs.items())}
    info = next(iter(infos.values()), {})
    result = {
        "schema": 1,
        "label": args.label,
        "runs": args.runs,
        "commit": args.commit,
        "date": datetime.datetime.now().isoformat(timespec="seconds"),
        "simulator": args.simulator,
        "configuration": args.configuration,
        "host": host_name(),
        "load": args.load.replace("{", "").replace("}", "").strip(),
        "info": info,
        "metrics": metrics,
    }
    with open(args.output, "w", encoding="utf-8") as file:
        json.dump(result, file, indent=1, sort_keys=True, ensure_ascii=False)


def host_name():
    try:
        return subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return platform.machine()


def load(path):
    with open(path, encoding="utf-8") as file:
        return json.load(file)


def cell(metrics, name, digits=2):
    metric = metrics.get(name)
    if metric is None:
        return "-"
    return f"{metric['median']:.{digits}f}"


def spread(metrics, name, digits=2):
    metric = metrics.get(name)
    if metric is None:
        return "-"
    return f"{metric['median']:.{digits}f} ({metric['min']:.{digits}f}–{metric['max']:.{digits}f})"


def table(headers, rows):
    widths = [max(len(str(row[index])) for row in [headers] + rows) for index in range(len(headers))]
    lines = ["  ".join(str(value).ljust(widths[index]) if index == 0 else str(value).rjust(widths[index]) for index, value in enumerate(row)).rstrip() for row in [headers] + rows]
    lines.insert(1, "  ".join("-" * width for width in widths))
    print("\n".join(lines))


def show(args):
    result = load(args.result)
    metrics = result["metrics"]
    print(f"{result['label']} · {result['commit']} · {result['date']} · {result['configuration']} on {result['simulator']} ({result['info'].get('model', '?')}, iOS {result['info'].get('os', '?')}) · {result['runs']} runs · load {result['load']}")
    if not result["info"].get("isOptimised", False):
        print("⚠️  An unoptimised build: these numbers aren't comparable with a Release one.")

    print("\nUpdates, ms of main-thread CPU (median of the runs)")
    rows = []
    for size in UPDATE_SIZES:
        for kind in ("append", "change"):
            prefix = f"update.{size}.{kind}"
            rows.append([f"{size} rows, {kind}", cell(metrics, f"{prefix}.build_cpu_ms_p50"), cell(metrics, f"{prefix}.build_cpu_ms_p95"),
                         cell(metrics, f"{prefix}.total_cpu_ms_p50"), cell(metrics, f"{prefix}.total_cpu_ms_p95")])
    table(["", "build p50", "build p95", "whole update p50", "whole update p95"], rows)

    print("\nBurst of 50 updates")
    rows = []
    for size in UPDATE_SIZES:
        for kind, label in (("burst", "at once"), ("burst_paced", "one a frame")):
            prefix = f"update.{size}.{kind}"
            rows.append([f"{size} rows, {label}", cell(metrics, f"{prefix}.build_cpu_ms_p50"), cell(metrics, f"{prefix}.build_cpu_ms_max"), cell(metrics, f"{prefix}.main_cpu_ms", 0),
                         cell(metrics, f"{prefix}.dropped_frames", 0), cell(metrics, f"{prefix}.longest_frame_ms", 0)])
    table(["", "build p50", "build max", "main CPU ms", "dropped", "longest ms"], rows)

    print("\nScroll at a fixed speed (first pass up builds the rows, the rest reuse them)")
    rows = []
    for name in SCROLL_PASSES:
        prefix = f"scroll.{name}"
        rows.append([name, cell(metrics, f"{prefix}.frame_cpu_ms_p50"), cell(metrics, f"{prefix}.frame_cpu_ms_p95"), cell(metrics, f"{prefix}.frame_cpu_ms_p99"), cell(metrics, f"{prefix}.frame_cpu_ms_max", 1),
                     cell(metrics, f"{prefix}.frames_over_8ms_pct", 1), cell(metrics, f"{prefix}.frames_over_16ms_pct", 1),
                     cell(metrics, f"{prefix}.hitch_ratio_ms_per_s", 1), cell(metrics, f"{prefix}.longest_frame_ms", 0), cell(metrics, f"{prefix}.dropped_frames", 0),
                     cell(metrics, f"{prefix}.jumps", 0), cell(metrics, f"{prefix}.largest_jump_pt", 1)])
    table(["pass", "cpu p50", "p95", "p99", "max", ">8ms %", ">16ms %", "hitch ms/s", "longest", "dropped", "jumps", "max pt"], rows)
    print()
    rows = []
    for name in SCROLL_PASSES:
        prefix = f"scroll.{name}"
        rows.append([name, cell(metrics, f"{prefix}.main_cpu_ms", 0), cell(metrics, f"{prefix}.rows_configured", 0), cell(metrics, f"{prefix}.rows_sized", 0), cell(metrics, f"{prefix}.nested_sizings", 0),
                     cell(metrics, f"{prefix}.row_bodies", 0), cell(metrics, f"{prefix}.styler_bodies", 0), cell(metrics, f"{prefix}.height_changes", 0)])
    table(["pass", "main CPU ms", "rows built", "sizings", "nested", "row bodies", "bubble bodies", "height changes"], rows)

    for prefix, title in (("rowcold", "Row kinds, first build, µs of main-thread CPU per row"), ("rowwarm", "Row kinds, later passes, µs of main-thread CPU per row")):
        kinds = sorted({".".join(name.split(".")[1:-1]) for name in metrics if name.startswith(prefix + ".")},
                       key=lambda kind: -metrics.get(f"{prefix}.{kind}.total_us_per_row", {"median": 0})["median"])
        if not kinds:
            continue
        print(f"\n{title}")
        rows = [[kind, cell(metrics, f"{prefix}.{kind}.count", 0), cell(metrics, f"{prefix}.{kind}.total_us_per_row", 0), cell(metrics, f"{prefix}.{kind}.configure_us_mean", 0),
                 cell(metrics, f"{prefix}.{kind}.first_size_us_mean", 0), cell(metrics, f"{prefix}.{kind}.size_us_mean", 0), cell(metrics, f"{prefix}.{kind}.size_us_p95", 0), cell(metrics, f"{prefix}.{kind}.layout_us_mean", 0)] for kind in kinds]
        table(["kind", "rows", "total", "configure", "first sizing", "size mean", "size p95", "layout"], rows)

    print("\nOpening the chat, ms")
    rows = [[label, cell(metrics, f"open.{name}.first_frame_ms", 0), cell(metrics, f"open.{name}.first_rows_ms", 0), cell(metrics, f"open.{name}.first_rows_cpu_ms", 0), cell(metrics, f"open.{name}.settled_ms", 0)] for label, name in (("cold", "cold"), ("warm", "warm"), ("warm, at the first unread", "unread"))]
    table(["", "first frame", "first rows, wall", "first rows, CPU", "settled, wall"], rows)

    print("\nWhat re-renders")
    rows = []
    for label, prefix in (("20 incoming messages", "messages"), ("reaction added", "reaction.add"), ("reaction removed", "reaction.remove")):
        rows.append([label, cell(metrics, f"{prefix}.row_bodies", 0), cell(metrics, f"{prefix}.rows_rerendered", 0), cell(metrics, f"{prefix}.styler_bodies", 0), cell(metrics, f"{prefix}.stylers_rerendered", 0),
                     cell(metrics, f"{prefix}.cells_configured", 0), cell(metrics, f"{prefix}.cells_sized", 0), cell(metrics, f"{prefix}.configuration_updates", 0)])
    table(["", "row bodies", "rows", "bubble bodies", "bubbles", "cells configured", "cells sized", "config updates"], rows)
    print(f"Rows on screen: {cell(metrics, 'reaction.visible_rows', 0)}")

    if "post.posts" in metrics:
        print("\nInteractive posts (real web views, stopping on each one)")
        print(f"{cell(metrics, 'post.drawn', 0)} of {cell(metrics, 'post.posts', 0)} drew · stop to drawn {cell(metrics, 'post.drawn_ms_median', 0)} ms, slowest {cell(metrics, 'post.drawn_ms_max', 0)} ms · "
              f"longest frame while one starts {cell(metrics, 'post.longest_frame_ms_median', 0)} ms, worst {cell(metrics, 'post.longest_frame_ms_max', 0)} ms · main CPU per post {cell(metrics, 'post.main_cpu_ms_median', 0)} ms")
        print(f"Of that frame: the jump's rows {cell(metrics, 'post.jump_frame_ms_median', 0)} ms · the post's own start {cell(metrics, 'post.start_frame_ms_median', 0)} ms, worst {cell(metrics, 'post.start_frame_ms_max', 0)} ms")
    
    if "postscroll.up.frames" in metrics:
        print("\nScrolling through running posts")
        rows = [[label, cell(metrics, f"postscroll.{name}.frame_cpu_ms_p95", 1), cell(metrics, f"postscroll.{name}.frame_cpu_ms_p99", 1), cell(metrics, f"postscroll.{name}.hitch_ratio_ms_per_s", 0),
                 cell(metrics, f"postscroll.{name}.longest_frame_ms", 0), cell(metrics, f"postscroll.{name}.dropped_frames", 0)] for label, name in (("up", "up"), ("down", "down"))]
        table(["pass", "frame CPU p95", "p99", "hitch ms/s", "longest frame", "dropped"], rows)
        print(f"Made while moving: web views {cell(metrics, 'postscroll.up.web_views_made', 0)} up, {cell(metrics, 'postscroll.down.web_views_made', 0)} down · mounts {cell(metrics, 'postscroll.up.mounts', 0)} up, {cell(metrics, 'postscroll.down.mounts', 0)} down")

    print("\nMemory, MB of footprint")
    print(f"open {cell(metrics, 'memory.open_mb', 0)} · peak in the scroll {cell(metrics, 'memory.peak_mb', 0)} · end of the scroll {cell(metrics, 'memory.end_of_scroll_mb', 0)} · after 3 s idle {cell(metrics, 'memory.after_idle_mb', 0)}")


def compare(args):
    before = load(args.before)
    after = load(args.after)
    print(f"before: {before['label']} {before['commit']} {before['date']}")
    print(f"after:  {after['label']} {after['commit']} {after['date']}")
    if before["configuration"] != after["configuration"] or before["simulator"] != after["simulator"]:
        print("⚠️  Different build configurations or simulators: this comparison means little.")

    names = sorted(set(before["metrics"]) & set(after["metrics"])) if args.all else [name for name in HEADLINES if name in before["metrics"] and name in after["metrics"]]
    rows = []
    better = worse = 0
    for name in names:
        old = before["metrics"][name]
        new = after["metrics"][name]
        change = (new["median"] - old["median"]) / old["median"] * 100 if old["median"] else 0
        # A median that moved inside the other run's range is noise.
        is_clear = new["min"] > old["max"] or new["max"] < old["min"]
        mark = ""
        if is_clear and not name.endswith(NEUTRAL_SUFFIXES):
            mark = "worse" if new["median"] > old["median"] else "better"
            better += mark == "better"
            worse += mark == "worse"
        rows.append([name, f"{old['median']:.2f}", f"{new['median']:.2f}", f"{change:+.1f}%", mark])
    table(["metric", "before", "after", "change", ""], rows)
    print(f"\n{better} clearly better, {worse} clearly worse, of {len(rows)}. Clear means the two runs' ranges don't overlap.")
    return 1 if worse else 0


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)

    merge_parser = commands.add_parser("merge")
    merge_parser.add_argument("folder")
    merge_parser.add_argument("output")
    for option in ("label", "runs", "commit", "simulator", "configuration", "load"):
        merge_parser.add_argument(f"--{option}", default="")

    show_parser = commands.add_parser("show")
    show_parser.add_argument("result")

    compare_parser = commands.add_parser("compare")
    compare_parser.add_argument("before")
    compare_parser.add_argument("after")
    compare_parser.add_argument("--all", action="store_true")

    args = parser.parse_args()
    if args.command == "merge":
        merge(args)
    elif args.command == "show":
        show(args)
    else:
        sys.exit(compare(args))


if __name__ == "__main__":
    main()
