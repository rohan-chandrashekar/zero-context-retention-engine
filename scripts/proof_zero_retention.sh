#!/usr/bin/env bash
set -uo pipefail

FRAME_BYTES=$((256 * 256 * 4))
RECORD_BYTES=$((8 + 512 * 4))
IMAGE_REGEX='\.(png|jpg|jpeg|tiff|tif|heic|heif|bmp|gif|raw|dng|cvpixelbuffer)([^a-z0-9]|$)'

analyze() {
    local log="$1"
    local failed=0

    echo "=== checking for image-file paths ==="
    local image_hits
    image_hits=$(grep -E -i "$IMAGE_REGEX" "$log" || true)
    if [[ -n "$image_hits" ]]; then
        echo "FAIL: image-file paths observed in the trace:"
        echo "$image_hits"
        failed=1
    else
        echo "PASS: no image-file path in any traced filesystem operation"
    fi
    echo

    echo "=== write-size analysis (a raw frame is ${FRAME_BYTES} bytes) ==="
    local sizes_dec
    sizes_dec=$(grep -E '\bwrite\b' "$log" | grep -oE 'B=0x[0-9a-fA-F]+' | sed 's/B=0x//' \
        | while read -r h; do [[ -n "$h" ]] && echo $((16#$h)); done)

    if [[ -z "$sizes_dec" ]]; then
        echo "no write() operations captured in this trace window"
    else
        local total max
        total=$(echo "$sizes_dec" | grep -c .)
        max=$(echo "$sizes_dec" | sort -rn | head -1)
        echo "write() operations captured : ${total}"
        echo "largest single write        : ${max} bytes"
        echo "raw frame size (256x256x4)  : ${FRAME_BYTES} bytes"
        if (( max < FRAME_BYTES )); then
            echo "PASS: the largest write is $(( FRAME_BYTES / max ))x smaller than one raw frame; no frame-sized write occurred"
        else
            echo "FAIL: a write at least as large as a raw frame occurred"
            failed=1
        fi
        echo
        echo "write-size histogram (bytes x count):"
        echo "$sizes_dec" | sort -n | uniq -c | awk '{printf "  %10s bytes  x %s\n", $2, $1}'
        echo
        echo "note: one vector-store record = ${RECORD_BYTES} bytes (8-byte float64 timestamp + 512 float32)"
    fi
    echo

    if (( failed == 0 )); then
        echo "PASS: zero image bytes written to disk (no image path, no frame-sized write)"
        return 0
    fi
    echo "FAIL: see findings above"
    return 1
}

if [[ "${1:-}" == "--analyze" ]]; then
    if [[ -z "${2:-}" || ! -f "${2:-}" ]]; then
        echo "usage: $0 --analyze <fs_usage-log>" >&2
        exit 2
    fi
    analyze "$2"
    exit $?
fi

if [[ $# -lt 1 ]]; then
    echo "usage: sudo bash $0 <pid> [seconds]   (capture + analyze)" >&2
    echo "       $0 --analyze <fs_usage-log>    (re-analyze an existing trace)" >&2
    exit 2
fi

PID="$1"
SECONDS_TO_TRACE="${2:-60}"
LOG="/tmp/zre_fs_usage_${PID}.log"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "fs_usage requires root; re-run with sudo" >&2
    exit 2
fi

echo "tracing filesystem syscalls for pid ${PID} for ${SECONDS_TO_TRACE} s -> ${LOG}"
fs_usage -w -f filesys "${PID}" > "${LOG}" 2>/dev/null &
TRACE_PID=$!
sleep "${SECONDS_TO_TRACE}"
kill "${TRACE_PID}" 2>/dev/null || true
wait "${TRACE_PID}" 2>/dev/null || true

echo
analyze "${LOG}"
exit $?
