#!/usr/bin/env bash
# Measures Otter against the performance budget (T14, ARCHITECTURE §9) and prints the table for
# context/docs/PERF.md.
#
#   scripts/perf.sh                  # build, then measure
#   scripts/perf.sh --app path/to/Otter.app
#   scripts/perf.sh --launch-only    # just cold launch → hotkey; shows nothing
#
# The build is Release with OTTER_TEST_HOOKS added, so the test hooks are there but the code is
# what ships. It's ad-hoc signed, without Hardened Runtime (see below). It records Otter's
# signposts with `log stream` while:
#   1. launching 10 times with `--otter-bench launch`, which quits once the hotkey is registered;
#   2. running `--otter-bench full` (App/TestHooks/BenchRunner.swift): the panel shows and hides
#      30 times, takes 100 notes with ⌘↩, 100 more go straight to a folder and a vault, then Otter
#      sits idle for a minute while memory and wakeups are measured. About 2½ minutes.
# During step 2 the panel keeps taking keyboard focus: don't type, and leave the pointer alone.
#
# Never touches your own notes or settings: everything is under a new temporary folder. A running
# Otter can stay running, though its ⌥Space then won't reach this one (the bench doesn't need it).
set -euo pipefail

usage() {
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
    exit 64
}

APP=""
LAUNCH_ONLY=false
while (( $# )); do
    case "$1" in
        --app) APP="$2"; shift 2 ;;
        --launch-only) LAUNCH_ONLY=true; shift ;;
        *) usage ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
step() { printf '\n==> %s\n' "$*" >&2; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

if [[ -z "$APP" ]]; then
    step "Building Otter (Release with OTTER_TEST_HOOKS)"
    xcodebuild -project "$ROOT/Otter.xcodeproj" -scheme Otter -configuration Release \
        -derivedDataPath "$ROOT/build/DerivedData-perf" \
        -clonedSourcePackagesDirPath "$ROOT/build/SourcePackages" build \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
        SWIFT_ACTIVE_COMPILATION_CONDITIONS=OTTER_TEST_HOOKS -quiet \
        ENABLE_HARDENED_RUNTIME=NO
    # Without a Developer ID, Hardened Runtime's library validation refuses Sparkle.framework,
    # which keeps its own Team ID; an ad-hoc signature can't match it.
    APP="$ROOT/build/DerivedData-perf/Build/Products/Release/Otter.app"
fi
BIN="$APP/Contents/MacOS/Otter"
[[ -x "$BIN" ]] || fail "no Otter binary in $APP"

DIR="$(mktemp -d "${TMPDIR:-/tmp}/otter-perf.XXXXXX")"
LOG_PID=""
trap '[[ -n "$LOG_PID" ]] && kill "$LOG_PID" 2>/dev/null || true' EXIT
/usr/bin/log stream --signpost --style ndjson \
    --predicate 'subsystem == "io.github.elizabeth-ling.otter" AND category == "PointsOfInterest"' \
    >"$DIR/signposts.ndjson" 2>/dev/null &
LOG_PID=$!
sleep 1

step "Launching 10 times"
for _ in $(seq 10); do
    "$BIN" --otter-bench launch --otter-dir "$DIR" >>"$DIR/otter.log" 2>&1 || fail "a launch failed; see $DIR/otter.log"
    sleep 1
done

if $LAUNCH_ONLY; then
    # In launch order. The first is the first run of this binary, which macOS checks first.
    ls -tr "$DIR"/results/launch-*.json | xargs cat | grep -oE '[0-9]+\.[0-9]' | tr '\n' ' '
    echo
    exit 0
fi

step "Running the bench (about 2½ minutes; don't type)"
"$BIN" --otter-bench full --otter-dir "$DIR" >>"$DIR/otter.log" 2>&1 &
BENCH_PID=$!
for (( waited = 0; waited < 400; waited++ )); do
    kill -0 "$BENCH_PID" 2>/dev/null || break
    sleep 1
done
if kill -0 "$BENCH_PID" 2>/dev/null; then
    kill -9 "$BENCH_PID"
    fail "the bench didn't finish in 400 s; see $DIR/otter.log"
fi
wait "$BENCH_PID" || fail "the bench failed; see $DIR/otter.log"
sleep 1
kill "$LOG_PID"
LOG_PID=""

step "Results ($DIR)"
python3 "$ROOT/scripts/perf_report.py" "$DIR"
