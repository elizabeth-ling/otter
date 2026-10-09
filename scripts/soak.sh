#!/usr/bin/env bash
# The reliability soak test (T14): Otter submits synthetic captures (`--otter-soak`, see
# App/TestHooks/SoakRunner.swift) while this script `kill -9`s it at random and relaunches it. Then
# every capture the outbox acknowledged must be in a destination at least once.
#
#   scripts/soak.sh                  # 1,000 captures, killed until they're all delivered (20 kills at least)
#   scripts/soak.sh -n 200 -k 5      # a quick run
#   scripts/soak.sh --app path/to/Otter.app
#
# Options:
#   -n COUNT        captures to submit (default 1000)
#   -k KILLS        kills, at least (default 20); the run is killed until it finishes, up to 10× this
#   --interval MS   pause between captures (default 30), which sets how long submitting takes
#   --app PATH      a Debug build (or any build with OTTER_TEST_HOOKS); otherwise one is built
#   --dir DIR       where the run's files go (default: a new temporary folder, kept afterwards)
#
# Never touches your own notes or settings: everything is under DIR. Exits 1 if a capture was lost.
set -euo pipefail

usage() {
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
    exit 64
}

COUNT=1000
KILLS=20
INTERVAL=30
APP=""
DIR=""
while (( $# )); do
    case "$1" in
        -n) COUNT="$2"; shift 2 ;;
        -k) KILLS="$2"; shift 2 ;;
        --interval) INTERVAL="$2"; shift 2 ;;
        --app) APP="$2"; shift 2 ;;
        --dir) DIR="$2"; shift 2 ;;
        *) usage ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
step() { printf '\n==> %s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

if [[ -z "$APP" ]]; then
    step "Building Otter (Debug)"
    xcodebuild -project "$ROOT/Otter.xcodeproj" -scheme Otter -configuration Debug \
        -derivedDataPath "$ROOT/build/DerivedData" build \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= -quiet
    APP="$ROOT/build/DerivedData/Build/Products/Debug/Otter.app"
fi
BIN="$APP/Contents/MacOS/Otter"
[[ -x "$BIN" ]] || fail "no Otter binary in $APP"

DIR="${DIR:-$(mktemp -d "${TMPDIR:-/tmp}/otter-soak.XXXXXX")}"
[[ -z "$(ls -A "$DIR" 2>/dev/null)" ]] || fail "$DIR isn't empty; each run needs a new folder"
mkdir -p "$DIR"
DONE="$DIR/soak/done"
ACKED="$DIR/soak/acknowledged.txt"
LOG="$DIR/otter.log"

PID=""
launch() {
    "$BIN" --otter-soak "$COUNT" --otter-soak-interval "$INTERVAL" --otter-dir "$DIR" >>"$LOG" 2>&1 &
    PID=$!
}
acked() { [[ -f "$ACKED" ]] && wc -l <"$ACKED" | tr -d ' ' || echo 0; }
trap '[[ -n "$PID" ]] && kill -9 "$PID" 2>/dev/null || true' EXIT

step "Soaking $COUNT captures in $DIR"
kills=0
while (( kills < KILLS * 10 )) && [[ ! -e "$DONE" ]]; do
    launch
    # 0.2–2 s: sometimes mid-launch, mostly mid-submit, now and then mid-delivery.
    ms=$(( RANDOM % 1800 + 200 ))
    sleep "$(printf '%d.%03d' $(( ms / 1000 )) $(( ms % 1000 )))"
    # A run that already quit is a zombie until `wait`, and `kill` would still succeed on it.
    if [[ ! -e "$DONE" ]] && kill -9 "$PID" 2>/dev/null; then
        wait "$PID" 2>/dev/null || true
        kills=$(( kills + 1 ))
        printf '  kill %2d after %4d ms: %s acknowledged\n' "$kills" "$ms" "$(acked)"
    else
        wait "$PID" 2>/dev/null || true
    fi
done

if [[ ! -e "$DONE" ]]; then
    step "Letting the last run finish"
    launch
    for (( waited = 0; waited < 600; waited++ )); do
        kill -0 "$PID" 2>/dev/null || break
        sleep 1
    done
    kill -0 "$PID" 2>/dev/null && fail "the last run didn't finish in 10 minutes; see $LOG"
    wait "$PID" || fail "the last run failed; see $LOG"
fi
PID=""
[[ -e "$DONE" ]] || fail "the soak didn't finish; see $LOG"

step "Checking every acknowledged capture was delivered"
# Hidden files are a destination's temp files, never a delivered note.
grep -rhoE --exclude='.*' 'otter-soak:[0-9A-F-]{36}' "$DIR/destinations" "$DIR/Documents" \
    | sed 's/^otter-soak://' | sort | uniq -c | awk '{ print $2, $1 }' >"$DIR/found.txt"
cut -d' ' -f1 "$ACKED" | sort -u >"$DIR/acknowledged-sorted.txt"
cut -d' ' -f1 "$DIR/found.txt" >"$DIR/found-ids.txt"

acknowledged=$(wc -l <"$DIR/acknowledged-sorted.txt" | tr -d ' ')
lost=$(comm -23 "$DIR/acknowledged-sorted.txt" "$DIR/found-ids.txt" | tee "$DIR/lost.txt" | wc -l | tr -d ' ')
unacknowledged=$(comm -13 "$DIR/acknowledged-sorted.txt" "$DIR/found-ids.txt" | wc -l | tr -d ' ')
duplicates=$(awk '$2 > 1 { extra += $2 - 1 } END { print extra + 0 }' "$DIR/found.txt")
attachments_acked=$(awk '{ total += $2 } END { print total + 0 }' "$ACKED")
# Each soak attachment is random bytes, so a retry reuses its copy rather than adding one.
attachments_found=$(find "$DIR/destinations" "$DIR/Documents" -path '*/attachments/*' -type f ! -name '.*' | wc -l | tr -d ' ')
pending=$(find "$DIR/Application Support/outbox" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')

cat <<EOF
  kills                     $kills
  acknowledged              $acknowledged
  lost                      $lost
  duplicate copies          $duplicates
  delivered, never acked    $unacknowledged   (killed between the outbox write and the ack)
  attachments               $attachments_found of $attachments_acked
  left in the outbox        $pending
  files                     $DIR
EOF

(( kills >= KILLS )) || fail "only $kills kills: the run finished first; raise --interval"
(( acknowledged == COUNT )) || fail "$acknowledged of $COUNT captures were acknowledged"
(( lost == 0 )) || fail "$lost captures lost; their IDs are in $DIR/lost.txt"
(( attachments_found >= attachments_acked )) || fail "$(( attachments_acked - attachments_found )) attachments missing"
(( pending == 0 )) || fail "$pending captures still in the outbox"
echo "0 lost."
