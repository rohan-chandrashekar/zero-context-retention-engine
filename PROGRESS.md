# Progress

## Current status
Phase 0 complete and verified on hardware (Apple M1, iMac21,1, 16 GB, macOS 15.7.3). MobileCLIP-S2 image encoder exported to Core ML, benchmarked across compute units, and checked for correctness against the PyTorch reference.

Phase 1 code complete and verified to build/load; measured run numbers are TBD pending an interactive GUI session (see below). The Swift engine (`swift build` clean, no warnings) compiles the Core ML model, opens the append-only vector store, and runs the ScreenCaptureKit -> scene-gate -> ANE-embed -> store loop, overwriting each pixel buffer in RAM and never writing a frame. Under Claude's non-interactive shell the run stops at `SCStreamError -3801` (Screen Recording TCC declined) via the engine's graceful permission path — the model-load and store-open paths execute first, so those are confirmed working.

## Phase checklist
- [x] Phase 0 — MobileCLIP-S2 to Core ML conversion + embedding benchmark
- [~] Phase 1 — Capture spine + zero-retention proof (code done + builds; measured run TBD on GUI session)
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

## Measured numbers (Phase 1)
TBD. The capture loop needs Screen Recording (TCC) permission. On the ASU lab iMac this is admin-gated — the account is non-admin (the System Settings toggle demands a separate administrator username + password), so neither the manual toggle nor the headless build process Claude runs can grant it. Decision (2026-06-04): run the live ScreenCaptureKit path on a personal/friend's Apple Silicon Mac where the user has admin, and label that machine in the docs (it will differ from the Phase 0 iMac M1; the two are on different chips and must not be compared directly). Then fill: per-processed-frame latency (median/p95/mean), scene-gate skip rate, frames complete/embedded/skipped, vectors stored, and image bytes written (must read 0, cross-checked with `scripts/proof_zero_retention.sh`).

Honesty fix applied (commit dfc927a): the run summary previously printed `image bytes written` from `Stats.imageBytesWritten`, a field nothing ever set — a hardcoded 0 dressed as a measurement, which violates the cardinal rule. Dropped the dead field; the summary now states 0 as a by-construction claim and points to the external `fs_usage` proof as the actual evidence. The latency line is relabeled "per-frame latency [hash + embed + store]" to match what is timed.

Phase 1 design decisions (interview-defensible):
- Capture is downscaled to 256×256 by ScreenCaptureKit itself (GPU), matching the model input with zero extra resize code. This is an anisotropic resize of the whole display, chosen deliberately to preserve all on-screen content (menu bar, dock, edges) rather than center-cropping it away, since the goal is "what was on screen," not a centered subject.
- Scene gate is an 8×8 average hash (64-bit), Hamming-distance threshold default 5/64; first frame always counts as changed.
- Privacy: each pixel buffer is `memset` to zero in RAM after embedding (and on skip) before release; this is a demonstrable in-memory overwrite, not just dropping the reference. The store is fixed-stride binary (8-byte float64 timestamp + 512 float32) for mmap-friendly brute-force search in Phase 2.
- Vectors are already L2-normalized by the Phase 0 export wrapper, so Phase 2 cosine search is a dot product.

## Known issues / open threads
- Pure-ANE latency from Xcode's Performance report is still TBD — it needs the Xcode GUI; the 3.00 ms figure is `predict()` wall-clock and is an upper bound on compute.
- `requirements.txt` pins `torch==2.7.0` (Core ML Tools 9.0's tested version); MobileCLIP declares `torch>=2.8.0`, so `pip` prints a benign dependency-conflict warning. Inference/zero-shot verified identical on 2.7.0.
- Core ML Tools 9.0 cannot convert the S2 graph via TorchScript tracing (`aten::Int` cast crash); we convert via the `torch.export` frontend with `run_decompositions({})`.
- The published S2 checkpoint is already reparameterized; `reparameterize_model` is intentionally not called (it errors on the fused modules).
- The `origin` remote embeds a GitHub PAT in its URL (in `.git/config`). Recommend rotating it and switching to `gh auth` + credential helper with a tokenless remote.
- Benign data race on the live heartbeat: `CaptureEngine`'s main loop reads `processor.stats` counters every 5 s while the `zre.frames` dispatch queue writes them. The final summary is safe (read after `stopCapture()` returns, no callbacks in flight); only the live heartbeat reads race, on monotonic `Int` counters used for logging. Thread Sanitizer would flag it. Harden with a lock or atomics before this is interview-facing; left untouched for now to avoid perturbing the engine right before the measured run.

## Next action
Phase 1 — ScreenCaptureKit capture loop → perceptual-hash scene-change gate → Core ML MobileCLIP embedding → store vector + timestamp; release/zero the pixel buffer immediately and never write a frame. Build the zero-retention proof: monitor the process with `fs_usage` and assert zero image bytes written. Report per-processed-frame end-to-end latency, scene-change skip rate, and vectors stored.
