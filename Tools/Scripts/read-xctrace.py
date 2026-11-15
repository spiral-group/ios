#!/usr/bin/env python3
#
# Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
#
# AGENT-PLATFORM (Brief 0083, question 359 item 16): reads an xctrace recording in one step. Exports what the trace holds
# and prints hitch counts and durations, hangs, the hottest symbols and, from a SwiftUI recording, what SwiftUI updated.
#
#   Tools/Scripts/read-xctrace.py <recording.trace> [--process Spiral] [--top 30] [--run 1] [--json out.json] [--template name] [--no-profile] [--keep-export dir]
#
# It takes any template: each section prints only when the trace has its table. `xctrace export` writes rows that point
# back at values defined in earlier rows ("id" and "ref"), so a row can't be read on its own; this resolves them as it streams.

import argparse
import collections
import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

# Frames every sample passes through. They say nothing about where the time went.
SCAFFOLDING = {"start", "main", "UIApplicationMain", "_UIApplicationMainPreparations", "GSEventRunModal", "CFRunLoopRunSpecific", "CFRunLoopRunSpecificWithOptions", "__CFRunLoopRun",
               "-[UIApplication _run]", "<Unknown>", "<deduplicated_symbol>", "__CFRunLoopDoObservers", "__CFRUNLOOP_IS_CALLING_OUT_TO_AN_OBSERVER_CALLBACK_FUNCTION__",
               "__CFRunLoopDoSource1", "__CFRunLoopDoSources0", "__CFRunLoopDoBlocks", "dyld3::start", "static App.main()", "$s7SwiftUI3AppPAAE4mainyyFZ"}


def xctrace(*arguments):
    return subprocess.run(["xcrun", "xctrace", *arguments], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True).stdout


def readable(trace, template, folder):
    """A recording that was cut off holds only the raw capture, which `export` refuses with "Document Missing Template
    Error". The capture is whole, though: importing it with the template it was recorded with gives a trace, without symbols."""
    try:
        xctrace("export", "--input", trace, "--toc")
        return trace
    except subprocess.CalledProcessError:
        captures = glob.glob(os.path.join(glob.escape(trace), "Trace*.run", "Attachments", "*.atrc"))
        if not captures:
            raise
    
    # Measured: a 1.5 GB capture under the SwiftUI template took 30 GB of memory in 7 minutes and hadn't finished.
    if template == "SwiftUI" and os.path.getsize(captures[0]) > 500 * 1024 * 1024:
        sys.exit("This capture is too large to import with the SwiftUI template: it would fill the Mac's memory. Use --template 'Animation Hitches' for its hitch tables.")
    
    print(f"Unfinished recording: importing its raw capture with the {template} template.")
    imported = os.path.join(folder, "imported.trace")
    subprocess.run(["xcrun", "xctrace", "import", "--input", captures[0], "--template", template, "--output", imported],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    return imported


def contents(trace, run):
    """The tables of a run, by schema, each with its attributes."""
    toc = ET.fromstring(xctrace("export", "--input", trace, "--toc"))
    run_element = next((element for element in toc.iter("run") if element.get("number") == str(run)), None)
    if run_element is None:
        sys.exit(f"The trace has no run {run}.")

    summary = {}
    info = run_element.find("info/summary")
    if info is not None:
        summary = {child.tag: (child.text or "").strip() for child in info}
    target = run_element.find("info/target")
    if target is not None:
        device = target.find("device")
        process = target.find("process")
        if device is not None:
            summary["device"] = f"{device.get('name', '?')} ({device.get('model', '?')}, {device.get('platform', '?')} {device.get('os-version', '?')})"
        if process is not None:
            summary["process"] = f"{process.get('name', '?')} ({process.get('pid', '?')})"

    tables = collections.OrderedDict()
    for table in run_element.iterfind("data/table"):
        tables.setdefault(table.get("schema"), []).append(dict(table.attrib))
    return summary, tables


def export_table(trace, run, schema, folder):
    path = os.path.join(folder, f"{schema}.xml")
    subprocess.run(["xcrun", "xctrace", "export", "--input", trace, "--output", path,
                    "--xpath", f'/trace-toc/run[@number="{run}"]/data/table[@schema="{schema}"]'],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    return path


def rows(path):
    """Streams a table: each row as {column: (text, fmt, element)}, with `ref`s resolved."""
    columns = []
    values = {}
    node = None
    for event, element in ET.iterparse(path, events=("start", "end")):
        if event == "start":
            if element.tag == "node":
                node = element
        elif element.tag == "mnemonic":
            columns.append(element.text)
        elif element.tag == "row":
            row = {}
            for index, child in enumerate(element):
                if index >= len(columns):
                    break
                row[columns[index]] = resolve(child, values)
            yield row
            node.remove(element) # A long recording has millions of rows, and an element stays in its parent until it's taken out.


def resolve(element, values):
    identifier = element.get("id")
    reference = element.get("ref")
    if reference is not None:
        return values.get(reference, ("", "", None))
    remember(element, values)
    return values[identifier] if identifier else (element.text or "", element.get("fmt", ""), element)


def remember(element, values):
    """Keeps every value a later row may point at, nested ones included."""
    for child in element:
        remember(child, values)
    identifier = element.get("id")
    if identifier is not None:
        if element.tag in ("backtrace", "tagged-backtrace"):
            values[identifier] = ("", "", backtrace_frames(element, values))
        elif element.tag == "frame":
            binary = element.find("binary")
            if binary is not None and binary.get("ref") is not None:
                binary_name = values.get(binary.get("ref"), ("", "", None))[0]
            else:
                binary_name = binary.get("name", "") if binary is not None else ""
            values[identifier] = (element.get("name", "<Unknown>"), binary_name, None)
        elif element.tag == "binary":
            values[identifier] = (element.get("name", ""), "", None)
        else:
            values[identifier] = (element.text or "", element.get("fmt", ""), None)


def backtrace_frames(element, values):
    """Innermost first, as (symbol, binary)."""
    frames = []
    for frame in element.iter("frame"):
        reference = frame.get("ref")
        key = reference if reference is not None else frame.get("id")
        value = values.get(key)
        if value is not None:
            frames.append((value[0], value[1]))
    return frames


def milliseconds(value):
    try:
        return float(value) / 1_000_000
    except (TypeError, ValueError):
        return 0.0


def time_profile(path, process, top):
    self_time = collections.Counter()
    inclusive = collections.Counter()
    own = collections.Counter()
    binaries = collections.Counter()
    threads = collections.Counter()
    total = 0.0
    main_total = 0.0

    for row in rows(path):
        thread = row.get("thread", ("", "", None))[1]
        if process and process not in thread and process not in row.get("process", ("", "", None))[1]:
            continue
        weight = milliseconds(row.get("weight", ("0",))[0])
        total += weight
        threads[thread] += weight
        if "Main Thread" not in thread:
            continue

        main_total += weight
        stack = row.get("stack", ("", "", None))[2]
        if not isinstance(stack, list) or not stack:
            continue
        self_time[stack[0][0]] += weight
        binaries[stack[0][1]] += weight
        for symbol in {symbol for symbol, _ in stack}:
            inclusive[symbol] += weight
        for symbol in {symbol for symbol, binary in stack if binary == process}:
            own[symbol] += weight

    return {
        "total_ms": total,
        "main_thread_ms": main_total,
        "threads": threads.most_common(6),
        "self": self_time.most_common(top),
        "inclusive": [(symbol, weight) for symbol, weight in inclusive.most_common(top * 3) if symbol not in SCAFFOLDING][:top],
        "own": [(symbol, weight) for symbol, weight in own.most_common(top * 3) if symbol not in SCAFFOLDING][:top],
        "binaries": binaries.most_common(10),
    }


def print_time_profile(profile):
    main = profile["main_thread_ms"]
    print(f"\nTime profile: {profile['total_ms'] / 1000:.1f} s of samples, {main / 1000:.1f} s on the main thread")
    for title, key in (("Hottest on the main thread, self time", "self"), ("Hottest on the main thread, with callees", "inclusive"), ("The app's own code, with callees", "own")):
        if not profile[key]:
            continue
        print(f"\n{title}")
        for symbol, weight in profile[key]:
            print(f"  {weight:9.0f} ms {weight / main * 100 if main else 0:5.1f}%  {symbol[:110]}")
    print("\nMain thread's self time by binary")
    for binary, weight in profile["binaries"]:
        print(f"  {weight:9.0f} ms {weight / main * 100 if main else 0:5.1f}%  {binary or '?'}")


def durations(values):
    values = sorted(values)
    if not values:
        return {"count": 0, "total_ms": 0, "mean_ms": 0, "p95_ms": 0, "longest_ms": 0}
    return {"count": len(values), "total_ms": sum(values), "mean_ms": sum(values) / len(values),
            "p95_ms": values[min(len(values) - 1, round((len(values) - 1) * 0.95))], "longest_ms": values[-1]}


def hitches(path, process, seconds):
    """A row is a frame that came late: `duration` is how late, `narrative-description` what the system blames."""
    all_hitches = []
    by_cause = collections.defaultdict(list)
    other_processes = 0
    for row in rows(path):
        where = row.get("process", ("", "", None))[1]
        if process and where and process not in where:
            other_processes += 1
            continue
        duration = milliseconds(row.get("duration", ("0",))[0])
        cause = row.get("narrative-description", ("", "", None))
        all_hitches.append(duration)
        by_cause[(cause[1] or cause[0] or "no cause given")[:80]].append(duration)
    
    summary = durations(all_hitches)
    summary["ratio_ms_per_s"] = summary["total_ms"] / seconds if seconds else 0
    summary["other_processes"] = other_processes
    summary["by_cause"] = {cause: durations(values) for cause, values in sorted(by_cause.items(), key=lambda item: -sum(item[1]))}
    return summary


def print_hitches(summary):
    print(f"\nHitches: {summary['count']}, {summary['total_ms']:.0f} ms in all, {summary['ratio_ms_per_s']:.1f} ms/s, mean {summary['mean_ms']:.1f} ms, p95 {summary['p95_ms']:.1f} ms, longest {summary['longest_ms']:.1f} ms"
          f" ({summary['other_processes']} in other processes, left out)")
    for cause, values in list(summary["by_cause"].items())[:8]:
        print(f"  {values['count']:5d}  {values['total_ms']:8.0f} ms  longest {values['longest_ms']:6.1f} ms  {cause}")


def renders(path):
    """The render server's work per frame. `offscreen-passes` is what shadows, blurs and glass cost it."""
    values = []
    passes = []
    for row in rows(path):
        values.append(milliseconds(row.get("duration", ("0",))[0]))
        try:
            passes.append(int(row.get("offscreen-passes", ("0",))[0] or 0))
        except ValueError:
            pass
    summary = durations(values)
    summary["offscreen_passes_mean"] = sum(passes) / len(passes) if passes else 0
    summary["offscreen_passes_max"] = max(passes, default=0)
    return summary


def intervals(path, process):
    values = []
    for row in rows(path):
        where = row.get("process", ("", "", None))[1]
        if process and where and process not in where:
            continue
        values.append(milliseconds(row.get("duration", ("0",))[0]))
    return durations(values)


def swiftui_updates(path, process, top):
    """Every update SwiftUI did, by kind and by view: a view's body is one kind, among layout, actions and the rest."""
    by_kind = collections.defaultdict(lambda: [0, 0.0])
    by_view = collections.defaultdict(lambda: [0, 0.0, 0])
    for row in rows(path):
        where = row.get("process", ("", "", None))[1]
        if process and where and process not in where:
            continue
        duration = milliseconds(row.get("duration", ("0",))[0])
        kind = row.get("update-type", ("", "", None))
        kind = kind[1] or kind[0] or "?"
        by_kind[kind][0] += 1
        by_kind[kind][1] += duration
        
        name = row.get("view-name", ("", "", None))
        description = row.get("description", ("", "", None))
        view = (name[1] or name[0] or description[1] or description[0] or "?")[:90]
        by_view[(kind, view)][0] += 1
        by_view[(kind, view)][1] += duration
        try:
            by_view[(kind, view)][2] += int(row.get("allocations", ("0",))[0] or 0)
        except ValueError:
            pass
    
    views = sorted(by_view.items(), key=lambda item: -item[1][1])[:top]
    return {"by_kind": {kind: {"count": values[0], "total_ms": values[1]} for kind, values in sorted(by_kind.items(), key=lambda item: -item[1][1])},
            "views": [{"kind": key[0], "view": key[1], "count": values[0], "total_ms": values[1], "allocations": values[2]} for key, values in views]}


def print_swiftui_updates(updates):
    print("\nSwiftUI updates by kind")
    for kind, values in updates["by_kind"].items():
        print(f"  {values['count']:8d} × {values['total_ms']:9.1f} ms  {kind}")
    print("\nSwiftUI updates by view")
    for view in updates["views"]:
        print(f"  {view['count']:8d} × {view['total_ms']:9.1f} ms  {view['allocations']:8d} allocations  {view['view']}  ({view['kind']})")


def main():
    parser = argparse.ArgumentParser(description="Reads an xctrace recording.")
    parser.add_argument("trace")
    parser.add_argument("--process", default="Spiral", help="Only this process. Empty for all.")
    parser.add_argument("--top", type=int, default=30)
    parser.add_argument("--run", type=int, default=1)
    parser.add_argument("--json", help="Also write the numbers to this file.")
    parser.add_argument("--keep-export", help="Keep the exported XML in this folder.")
    parser.add_argument("--template", default="Animation Hitches", help="What an unfinished recording was recorded with.")
    parser.add_argument("--tables", action="store_true", help="List what the trace holds and stop.")
    parser.add_argument("--no-profile", action="store_true", help="Leave out the hot symbols: exporting them from a long SwiftUI recording takes the longest.")
    args = parser.parse_args()
    
    folder = args.keep_export or tempfile.mkdtemp(prefix="read-xctrace-")
    os.makedirs(folder, exist_ok=True)
    try:
        read(args, folder)
    finally:
        if not args.keep_export:
            shutil.rmtree(folder, ignore_errors=True)


def read(args, folder):
    trace = readable(args.trace, args.template, folder)
    summary, tables = contents(trace, args.run)
    if args.tables:
        print(json.dumps(summary, indent=1, ensure_ascii=False))
        for schema, instances in tables.items():
            print(schema, {key: value for key, value in instances[0].items() if key != "schema"})
        return
    
    print(args.trace)
    print(" · ".join(f"{key}: {value}" for key, value in summary.items() if key in ("device", "process", "template-name", "duration", "end-reason")))
    seconds = float(summary.get("duration", 0) or 0)
    results = {"trace": args.trace, "summary": summary, "tables": list(tables)}
    
    if "hitches" in tables:
        results["hitches"] = hitches(export_table(trace, args.run, "hitches", folder), args.process, seconds)
        print_hitches(results["hitches"])
    
    if "hitches-updates" in tables:
        results["hitches-updates"] = intervals(export_table(trace, args.run, "hitches-updates", folder), args.process)
        updates = results["hitches-updates"]
        print(f"\nThe app's commits (hitches-updates): {updates['count']}, mean {updates['mean_ms']:.1f} ms, p95 {updates['p95_ms']:.1f} ms, longest {updates['longest_ms']:.1f} ms")
    
    if "hitches-renders" in tables:
        results["hitches-renders"] = renders(export_table(trace, args.run, "hitches-renders", folder))
        render = results["hitches-renders"]
        print(f"The render server (hitches-renders, every app on screen): {render['count']}, mean {render['mean_ms']:.1f} ms, p95 {render['p95_ms']:.1f} ms, longest {render['longest_ms']:.1f} ms, "
              f"offscreen passes mean {render['offscreen_passes_mean']:.1f}, most {render['offscreen_passes_max']}")
    
    if "hitches-gpu" in tables:
        results["hitches-gpu"] = intervals(export_table(trace, args.run, "hitches-gpu", folder), "")
        gpu = results["hitches-gpu"]
        print(f"The GPU (hitches-gpu): {gpu['count']}, mean {gpu['mean_ms']:.1f} ms, p95 {gpu['p95_ms']:.1f} ms, longest {gpu['longest_ms']:.1f} ms")
    
    if "potential-hangs" in tables:
        results["hangs"] = intervals(export_table(trace, args.run, "potential-hangs", folder), args.process)
        print(f"\nHangs (potential-hangs): {results['hangs']['count']}, {results['hangs']['total_ms']:.0f} ms in all, longest {results['hangs']['longest_ms']:.0f} ms")
    
    if "swiftui-updates" in tables:
        results["swiftui-updates"] = swiftui_updates(export_table(trace, args.run, "swiftui-updates", folder), args.process, args.top)
        print_swiftui_updates(results["swiftui-updates"])
    
    if "time-profile" in tables and not args.no_profile:
        results["time-profile"] = time_profile(export_table(trace, args.run, "time-profile", folder), args.process, args.top)
        print_time_profile(results["time-profile"])
    
    if args.json:
        with open(args.json, "w", encoding="utf-8") as file:
            json.dump(results, file, indent=1, ensure_ascii=False)


if __name__ == "__main__":
    main()
