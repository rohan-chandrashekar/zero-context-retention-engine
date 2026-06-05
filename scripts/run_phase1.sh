#!/usr/bin/env bash
set -uo pipefail

DURATION="${1:-180}"
FPS="${2:-2}"
THRESHOLD="${3:-5}"

BIN=".build/release/zre"
RUN_LOG="/tmp/zre_run.log"
PROOF_LOG="/tmp/zre_proof.log"

if [[ ! -x "$BIN" ]]; then
    echo "engine not built. run: swift build -c release" >&2
    exit 1
fi

: > "$RUN_LOG"
"$BIN" --duration $((DURATION + 30)) --fps "$FPS" --scene-threshold "$THRESHOLD" > "$RUN_LOG" 2>&1 &
ENGINE_PID=$!

sleep 2
if ! kill -0 "$ENGINE_PID" 2>/dev/null; then
    echo "the engine exited within 2 s. this almost always means Screen Recording is not granted" >&2
    echo "to the app hosting this terminal. grant it, relaunch that app, and re-run. engine output:" >&2
    echo "---" >&2
    cat "$RUN_LOG" >&2
    exit 1
fi

echo "engine running as pid ${ENGINE_PID}"
echo "browse / scroll / switch apps normally for the next ${DURATION} s while it captures."
echo "you will be prompted for your password to run the fs_usage proof as root."
echo

sudo bash scripts/proof_zero_retention.sh "$ENGINE_PID" "$DURATION" 2>&1 | tee "$PROOF_LOG"

kill -INT "$ENGINE_PID" 2>/dev/null || true
wait "$ENGINE_PID" 2>/dev/null || true

echo
echo "=== engine run summary (full log: ${RUN_LOG}) ==="
tail -n 18 "$RUN_LOG"
echo
echo "logs written: ${RUN_LOG} | ${PROOF_LOG} | /tmp/zre_fs_usage_${ENGINE_PID}.log"
