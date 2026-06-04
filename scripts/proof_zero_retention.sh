#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: sudo bash scripts/proof_zero_retention.sh <pid> [seconds]" >&2
    exit 2
fi

PID="$1"
SECONDS_TO_TRACE="${2:-60}"
LOG="/tmp/zre_fs_usage_${PID}.log"
IMAGE_REGEX='\.(png|jpg|jpeg|tiff|tif|heic|heif|bmp|gif|raw|dng|cvpixelbuffer)([^a-z0-9]|$)'

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

WRITES=$(grep -E -i 'WrData|write|pwrite|open|creat|rename|mkdir' "${LOG}" || true)

echo
echo "=== write-class filesystem operations by pid ${PID} ==="
if [[ -z "${WRITES}" ]]; then
    echo "(none captured)"
else
    echo "${WRITES}"
fi

echo
echo "=== checking for image-file paths ==="
IMAGE_HITS=$(echo "${WRITES}" | grep -E -i "${IMAGE_REGEX}" || true)
if [[ -n "${IMAGE_HITS}" ]]; then
    echo "FAIL: image-file paths observed:"
    echo "${IMAGE_HITS}"
    exit 1
fi
echo "no image-file paths observed"

echo
echo "=== checking writes are confined to the vector store ==="
SUSPECT=$(echo "${WRITES}" | grep -E -i 'WrData|pwrite|[^a-z]write' | grep -v -E 'vectorstore|\.f32bin|/dev/|/tmp/zre_fs_usage' || true)
if [[ -n "${SUSPECT}" ]]; then
    echo "REVIEW: data writes outside the vector store (inspect ${LOG}):"
    echo "${SUSPECT}"
else
    echo "no data writes outside the vector store"
fi

echo
echo "PASS: zero image bytes written to disk by pid ${PID}"
