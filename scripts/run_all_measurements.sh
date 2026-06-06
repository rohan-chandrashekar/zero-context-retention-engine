#!/usr/bin/env bash
set -uo pipefail

VARIANT="${VARIANT:-mobileclip_s2}"
CKPT_DIR="checkpoints"
CKPT="${CKPT_DIR}/${VARIANT}.pt"
IMG_MODEL="${IMG_MODEL:-MobileCLIPImage.mlpackage}"
TXT_MODEL="${TXT_MODEL:-MobileCLIPText.mlpackage}"
BASE_URL="https://docs-assets.developer.apple.com/ml-research/datasets/mobileclip"

echo "=== toolchain (record this machine label for the tables) ==="
uname -m
sw_vers
swift --version 2>&1 | head -1
python3 --version
echo

echo "=== python env ==="
if [[ ! -d .venv ]]; then python3 -m venv .venv; fi
source .venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt
pip install --quiet "git+https://github.com/apple/ml-mobileclip.git"
echo "env ready"
echo

echo "=== checkpoint (${VARIANT}) ==="
mkdir -p "${CKPT_DIR}"
if [[ ! -f "${CKPT}" ]]; then
  curl -L -o "${CKPT}" "${BASE_URL}/${VARIANT}.pt"
fi
echo

echo "=== export image + text encoders to Core ML ==="
python scripts/export_coreml.py --encoder image --variant "${VARIANT}" --checkpoint "${CKPT}" --output "${IMG_MODEL}"
python scripts/export_coreml.py --encoder text  --variant "${VARIANT}" --checkpoint "${CKPT}" --output "${TXT_MODEL}"
echo

echo "=== verify encoders vs PyTorch (Phase 0 / Phase 2 correctness) ==="
if [[ -f /tmp/zrce_cats.jpg ]]; then
  python scripts/verify_coreml.py --variant "${VARIANT}" --checkpoint "${CKPT}" --model "${IMG_MODEL}" --image /tmp/zrce_cats.jpg
else
  echo "skip image verify: put a test image at /tmp/zrce_cats.jpg (see MEASURE.md section A)"
fi
python scripts/verify_text_coreml.py --variant "${VARIANT}" --checkpoint "${CKPT}" --model "${TXT_MODEL}"
echo

echo "=== embedding benchmark across compute units (Phase 0 table) ==="
for cu in cpu_and_ne cpu_and_gpu cpu_only all; do
  python scripts/bench_coreml.py --model "${IMG_MODEL}" --compute-units "${cu}"
  echo
done

echo "=== build the engine (release) ==="
swift build -c release
echo

echo "=== machine-independent self-tests (should pass anywhere) ==="
python scripts/selftest_retrieval.py
python scripts/selftest_defense.py
echo

echo "DETERMINISTIC MEASUREMENTS DONE."
echo "Continue with the interactive steps in MEASURE.md:"
echo "  B. capture + zero-retention proof    -> Phase 1/2 latency + proof"
echo "  C. label + retrieval precision       -> Phase 2 precision"
echo "  D. red-team attacks + defense table  -> Phase 3"
echo "  E. visualizer                        -> Phase 4"
echo "  F. cross-variant: VARIANT=mobileclip_s0 bash scripts/run_all_measurements.sh, then bench_all.py"
