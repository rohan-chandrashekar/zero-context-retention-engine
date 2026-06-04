#!/usr/bin/env bash
set -euo pipefail

python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
pip install "git+https://github.com/apple/ml-mobileclip.git"

mkdir -p checkpoints

echo ""
echo "Environment ready."
echo "Next: place the MobileCLIP-S2 checkpoint in checkpoints/ (see github.com/apple/ml-mobileclip), then run:"
echo "  python scripts/export_coreml.py --variant mobileclip_s2 --checkpoint checkpoints/mobileclip_s2.pt --output MobileCLIPImage.mlpackage"
echo "  python scripts/bench_coreml.py --model MobileCLIPImage.mlpackage --compute-units all"
echo ""
echo "Once the Swift package exists, build the engine with: swift build"
