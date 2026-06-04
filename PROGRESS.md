# Progress

## Current status
Phase 0 complete and verified on hardware (Apple M1, iMac21,1, 16 GB, macOS 15.7.3). MobileCLIP-S2 image encoder exported to Core ML, benchmarked across compute units, and checked for correctness against the PyTorch reference.

## Phase checklist
- [x] Phase 0 — MobileCLIP-S2 to Core ML conversion + embedding benchmark
- [ ] Phase 1 — Capture spine + zero-retention proof
- [ ] Phase 2 — On-device OCR + semantic retrieval
- [ ] Phase 3 — Privacy red-team + defense
- [ ] Phase 4 — Benchmarks + visualizer + storytelling

## Measured numbers (Phase 0)
Model: MobileCLIP-S2 image encoder, Core ML `mlprogram`, FP16, 512-d L2-normalized output, 256×256 input. Size: 68.71 MB. Latency = `coremltools` `predict()` wall-clock (15 warm-up + 200 runs), includes Python/Core ML call overhead.

| Compute unit | Median (ms) | p95 (ms) | Throughput (img/s) |
|---|---|---|---|
| ANE  | 3.00  | 3.30  | 329 |
| GPU  | 18.77 | 19.82 | 53  |
| CPU  | 28.77 | 29.45 | 35  |
| ALL  | 2.98  | 3.31  | 330 |

Correctness:
- Core ML vs PyTorch reference: cosine 0.9965 (FP16), max abs diff 0.0145.
- CLIP zero-shot on the canonical two-cats image: correct caption at +0.312 cosine / 100% softmax.

## Known issues / open threads
- Pure-ANE latency from Xcode's Performance report is still TBD — it needs the Xcode GUI; the 3.00 ms figure is `predict()` wall-clock and is an upper bound on compute.
- `requirements.txt` pins `torch==2.7.0` (Core ML Tools 9.0's tested version); MobileCLIP declares `torch>=2.8.0`, so `pip` prints a benign dependency-conflict warning. Inference/zero-shot verified identical on 2.7.0.
- Core ML Tools 9.0 cannot convert the S2 graph via TorchScript tracing (`aten::Int` cast crash); we convert via the `torch.export` frontend with `run_decompositions({})`.
- The published S2 checkpoint is already reparameterized; `reparameterize_model` is intentionally not called (it errors on the fused modules).
- The `origin` remote embeds a GitHub PAT in its URL (in `.git/config`). Recommend rotating it and switching to `gh auth` + credential helper with a tokenless remote.

## Next action
Phase 1 — ScreenCaptureKit capture loop → perceptual-hash scene-change gate → Core ML MobileCLIP embedding → store vector + timestamp; release/zero the pixel buffer immediately and never write a frame. Build the zero-retention proof: monitor the process with `fs_usage` and assert zero image bytes written. Report per-processed-frame end-to-end latency, scene-change skip rate, and vectors stored.
