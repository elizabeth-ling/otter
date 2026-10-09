#!/usr/bin/env python3
"""Turns a `scripts/perf.sh` run into the table in context/docs/PERF.md (T14).

    scripts/perf_report.py DIR

DIR holds signposts.ndjson (`log stream --signpost --style ndjson`), results/bench.json and
results/launch-*.json. Prints Markdown.
"""

import json
import pathlib
import statistics
import sys
from datetime import datetime


def percentile(values, p):
    """Nearest-rank percentile."""
    ordered = sorted(values)
    rank = max(1, round(p / 100 * len(ordered) + 0.5 - 1e-9))
    return ordered[min(rank, len(ordered)) - 1]


def summary(values):
    if not values:
        return "no samples"
    return (
        f"p50 {percentile(values, 50):.1f} · p95 {percentile(values, 95):.1f} · "
        f"max {max(values):.1f} ms (n={len(values)})"
    )


def signpost_intervals(path):
    """Interval durations in ms by name, and by (name, message) for intervals with a message."""
    open_intervals = {}
    by_name, by_message = {}, {}
    for line in path.read_text().splitlines():
        if not line.startswith("{"):
            continue
        event = json.loads(line)
        if event.get("eventType") != "signpostEvent":
            continue
        key = (event["processID"], event["signpostName"], event["signpostID"])
        time = datetime.strptime(event["timestamp"], "%Y-%m-%d %H:%M:%S.%f%z")
        if event["signpostType"] == "begin":
            open_intervals[key] = (time, event.get("eventMessage", ""))
        elif event["signpostType"] == "end" and key in open_intervals:
            began, message = open_intervals.pop(key)
            ms = (time - began).total_seconds() * 1000
            by_name.setdefault(event["signpostName"], []).append(ms)
            by_message.setdefault((event["signpostName"], message), []).append(ms)
    return by_name, by_message


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    directory = pathlib.Path(sys.argv[1])
    bench = json.loads((directory / "results/bench.json").read_text())
    launches = [
        json.loads(p.read_text())["hotkeyReadyMs"]
        for p in sorted((directory / "results").glob("launch-*.json"))
    ]
    by_name, by_message = signpost_intervals(directory / "signposts.ndjson")
    names = json.loads((directory / "results/destinations.json").read_text()) if (directory / "results/destinations.json").exists() else {}

    print("| Interval | Budget | Result |")
    print("|---|---|---|")
    print(f"| Cold launch → hotkey registered | < 300 ms | {summary(launches)} |")
    print(f"| Hotkey → panel key (signpost) | p95 < 100 ms (target 50) | {summary(by_name.get('hotkey→visible', []))} |")
    print(f"| ⌘↩ → panel hidden (signpost) | < 50 ms | {summary(by_name.get('submit→hidden', []))} |")
    for (name, message), values in sorted(by_message.items()):
        if name == "enqueue→delivered":
            label = names.get(message, message)
            print(f"| Enqueue → delivered, {label} (signpost) | p95 < 50 ms | {summary(values)} |")
    footprint = bench.get("footprintAfterCapturesMB")
    print(f"| Idle memory after {bench['captures']} captures | < 40 MB | {footprint:.1f} MB |" if footprint else "| Idle memory | < 40 MB | not measured |")
    idle = bench.get("idleWakeupsPerSecond")
    interrupt = bench.get("interruptWakeupsPerSecond")
    print(f"| Idle wakeups/s over {bench['idleSeconds']} s | ~0 | {idle:.2f} idle, {interrupt:.2f} interrupt |" if idle is not None else "| Idle wakeups | ~0 | not measured |")

    print()
    print("Measured in-process by the bench (a cross-check; it polls every 1 ms):")
    print()
    print(f"- First show → key: {bench.get('firstShowToKeyMs', 0):.1f} ms")
    print(f"- Show → key: {summary(bench.get('showToKeyMs', []))}")
    print(f"- ⌘↩ → hide starts: {summary(bench.get('submitToHideMs', []))}")
    print(f"- ⌘↩ → panel no longer key (after the fade): {summary(bench.get('submitToResignKeyMs', []))}")
    for name, values in sorted(bench.get("submitToDeliveredMs", {}).items()):
        print(f"- Submit → delivered, {name}, including the outbox write: {summary(values)}")
    restyle = by_name.get("restyle", [])
    if restyle:
        print(f"- Restyle passes: {summary(restyle)}")


if __name__ == "__main__":
    main()
