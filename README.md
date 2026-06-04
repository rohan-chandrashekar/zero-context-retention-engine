# Zero-Retention Context Engine

An on-device macOS context engine that watches the screen, understands it, and keeps the *meaning* without keeping the *pixels*. Frames are embedded on the Apple Neural Engine and discarded in memory; only mathematical vectors are retained. The privacy claim is then adversarially verified, not just asserted.

Built with Apple's own on-device stack: **ScreenCaptureKit**, **Vision** (on-device OCR), and **MobileCLIP** via **Core ML**.

## Results

Numbers are measured on Apple Silicon, not estimated. Filled in as each phase completes.

### Embedding — MobileCLIP-S2 image encoder (Phase 0)

Measured on **Apple M1 (iMac21,1, 16 GB, macOS 15.7.3)**. Exported to a Core ML `mlprogram`, FP16, 512-d L2-normalized output, 256×256 input. Latency is `coremltools` `predict()` wall-clock time (15 warm-up + 200 timed runs); it includes Python ↔ Core ML call overhead, so it is an **upper bound** on pure compute. Xcode's Performance report gives the authoritative pure-ANE time (TBD — requires the Xcode GUI on this machine).

| Compute unit | Model size (MB) | Median latency (ms) | p95 (ms) | Throughput (img/s) |
|---|---|---|---|---|
| Apple Neural Engine | 68.71 | 3.00 | 3.30 | 329 |
| GPU | 68.71 | 18.77 | 19.82 | 53 |
| CPU | 68.71 | 28.77 | 29.45 | 35 |
| Core ML auto ("ALL") | 68.71 | 2.98 | 3.31 | 330 |

ANE is **~9.6× faster than CPU** and **~6.3× faster than GPU** on the same chip; Core ML's automatic placement matches the ANE path, confirming the encoder actually runs on the Neural Engine (a silent CPU fallback would read ~29 ms).

**Export correctness (verified, not assumed):**
- Core ML vs PyTorch reference on a real image: cosine similarity **0.9965** at FP16 (max abs element diff 0.0145), output L2-normalized, 512-d.
- CLIP zero-shot sanity: the canonical two-cats image scores the caption *"two cats lying on a couch"* at +0.312 cosine (100% softmax) over distractors — confirms correct resolution and `[0,1]` preprocessing (MobileCLIP omits the OpenAI CLIP mean/std normalization).

Cross-variant (S0/S1/B) and cross-chip (M1/M2/M4) comparisons are deferred to Phase 4.

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

mkdir -p checkpoints
curl -L -o checkpoints/mobileclip_s2.pt \
  https://docs-assets.developer.apple.com/ml-research/datasets/mobileclip/mobileclip_s2.pt

python scripts/export_coreml.py --variant mobileclip_s2 --checkpoint checkpoints/mobileclip_s2.pt --output MobileCLIPImage.mlpackage
python scripts/verify_coreml.py --model MobileCLIPImage.mlpackage   # cosine vs PyTorch reference
for cu in cpu_and_ne cpu_and_gpu cpu_only all; do
  python scripts/bench_coreml.py --model MobileCLIPImage.mlpackage --compute-units $cu
done
```

Toolchain notes (so the conversion reproduces):
- `requirements.txt` pins `torch==2.7.0` / `torchvision==0.22.0`, the most recent pair Core ML Tools 9.0 is tested against. MobileCLIP declares `torch>=2.8.0`; that pin is conservative — inference and zero-shot are bit-for-bit unaffected on 2.7.0 in our checks, so the resulting pip dependency warning is benign.
- `export_coreml.py` converts through the `torch.export` frontend (`run_decompositions({})`), not TorchScript tracing. The TorchScript path crashes in Core ML Tools 9.0 on an `aten::Int` cast inside the S2 graph.
- The published S2 checkpoint already ships reparameterized (single-branch inference graph), so `reparameterize_model` is intentionally **not** called — it assumes train-time weights and would error on the fused modules.
- For the authoritative ANE-only latency, open `MobileCLIPImage.mlpackage` in Xcode and run the Performance report against the Neural Engine.
