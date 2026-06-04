# Zero-Retention Context Engine

An on-device macOS context engine that watches the screen, understands it, and keeps the *meaning* without keeping the *pixels*. Frames are embedded on the Apple Neural Engine and discarded in memory; only mathematical vectors are retained. The privacy claim is then adversarially verified, not just asserted.

Built with Apple's own on-device stack: **ScreenCaptureKit**, **Vision** (on-device OCR), and **MobileCLIP** via **Core ML**.

## Results

Numbers are measured on Apple Silicon, not estimated. Filled in as each phase completes.

### Embedding (Phase 0)

| Variant | Precision | Compute Unit | Model Size (MB) | Median Latency (ms) | Throughput (/s) |
|---|---|---|---|---|---|
| MobileCLIP-S2 | FP16 | ANE | _tbd_ | _tbd_ | _tbd_ |
| MobileCLIP-S0 | FP16 | ANE | _tbd_ | _tbd_ | _tbd_ |

### Capture pipeline (Phase 1)

| Metric | Value |
|---|---|
| End-to-end per-processed-frame latency (ms) | _tbd_ |
| Scene-change gate hit rate (% frames skipped) | _tbd_ |
| Image bytes written to disk | 0 |

### Privacy red-team (Phase 3)

| Defense | Reconstruction fidelity (↓ better) | Retrieval accuracy retained (↑ better) |
|---|---|---|
| None (raw vectors) | _tbd_ | _tbd_ |
| + defense | _tbd_ | _tbd_ |

## Architecture

```
ScreenCaptureKit (capture)
  -> perceptual-hash scene-change gate (skip near-identical frames)
  -> Core ML MobileCLIP image encoder (ANE) -> 512-d vector
  -> Vision VNRecognizeTextRequest (on-device OCR) -> text
  -> vector + text stored; raw CMSampleBuffer never persisted, buffer overwritten
  -> semantic search over vectors
  -> [red-team] embedding-inversion attack + defense
```

## Phases

- **Phase 0** — MobileCLIP to Core ML conversion + embedding benchmark.
- **Phase 1** — Capture loop, scene-change gate, embedding, zero-retention buffer handling.
- **Phase 2** — On-device OCR + semantic retrieval.
- **Phase 3** — Embedding-inversion attack and defense (the differentiator).
- **Phase 4** — Cross-variant / cross-chip benchmarks + LinkedIn visualizer.

## Phase 0 setup

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
pip install git+https://github.com/apple/ml-mobileclip.git

# download a checkpoint into checkpoints/ from the apple/ml-mobileclip releases
python scripts/export_coreml.py --variant mobileclip_s2 --checkpoint checkpoints/mobileclip_s2.pt --output MobileCLIPImage.mlpackage
python scripts/bench_coreml.py --model MobileCLIPImage.mlpackage --compute-units all
```

For the authoritative ANE-only latency, open the generated `.mlpackage` in Xcode and run the Performance report against the Neural Engine.
