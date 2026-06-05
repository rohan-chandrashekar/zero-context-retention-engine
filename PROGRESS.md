# Progress

## Current status
Phase 0 complete and verified on hardware (Apple M1, iMac21,1, 16 GB, macOS 15.7.3). MobileCLIP-S2 image encoder exported to Core ML, benchmarked across compute units, and checked for correctness against the PyTorch reference.

Phase 1 complete and verified by a live capture run on **Apple M5 (MacBook Pro, Mac17,2, 16 GB, macOS 26.5.1)** — a different machine/chip from the Phase 0 M1, by design (the M1 was a non-admin ASU lab Mac that could not grant Screen Recording TCC). The Core ML model was re-exported and re-verified on the M5 (cosine 0.996560 vs PyTorch, identical to the M1 export). The Swift engine (`swift build -c release` clean, no warnings) runs the ScreenCaptureKit -> scene-gate -> ANE-embed -> store loop, overwriting each pixel buffer in RAM and never writing a frame. A 210 s real-browsing session was captured while `fs_usage` traced the process; per-frame latency, scene-gate skip rate, vectors stored, and the zero-retention proof are all measured and recorded below.

## Phase checklist
- [x] Phase 0 — MobileCLIP-S2 to Core ML conversion + embedding benchmark
- [x] Phase 1 — Capture spine + zero-retention proof (measured on Apple M5; live run + fs_usage proof done)
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
Machine: **Apple M5 (MacBook Pro, Mac17,2, 16 GB, macOS 26.5.1)**. Single 210 s capture during real browsing/scrolling/app-switching, display 0, ≤2 fps cap, scene threshold 5/64, pixel-buffer zeroing on. Not comparable to the Phase 0 M1 numbers (different chip).

| Metric | Value |
|---|---|
| Frames complete / embedded / skipped | 335 / 43 / 292 |
| Scene-gate skip rate | 87.2 % (292 of 335) |
| Per-frame latency [hash + embed + store] | median 6.97 ms, p95 28.72 ms, mean 10.20 ms (n=43) |
| Vectors stored | 43 (store = 88,408 B = 43 × 2056, exact) |
| Image bytes written | 0 (proven below) |

Zero-retention proof (`fs_usage` over the live process, re-analyzed with `scripts/proof_zero_retention.sh --analyze`): no `open`/`read`/`write` touched an image-file path; the largest single write in the entire trace was **2056 bytes = one vector record (8-byte float64 timestamp + 512 float32)**, which is **127× smaller** than one raw 256×256×4 = 262,144-byte frame. Full write profile: 2056-byte records (fd 3, ×42 captured — the 43rd append landed in the ~2 s before the trace started; the on-disk 88,408 B confirms all 43), ≤43-byte text heartbeats to the engine's own log (fd 2), and 2-byte ScreenCaptureKit frame-ready wakeup tokens (fd 5). No frame-sized write exists.

Latency note: the number is the full processed-frame path (full-frame average hash + Core ML embed + store append), not the bare encoder call, so it is intentionally larger than and not comparable to the Phase 0 `predict()` latency. The timer wraps only embedded frames; the ~per-frame hash-only cost of the 292 skipped frames is not included.

Proof-script hardening (this session): the prior `proof_zero_retention.sh` "writes confined to the vector store" check was misleading — `fs_usage` `write` lines carry only the file descriptor, not a path, so the path-based exclusion could never match and every legitimate vector-store write was false-flagged as REVIEW. Replaced it with a write-size test (largest write vs raw frame size) plus the image-path scan, and added an `--analyze <log>` mode so a captured trace can be re-checked without root or a re-run. The image-bytes-written claim is now a clean PASS from the tool itself, not a hand-wave over its output.

Honesty fix applied earlier (commit dfc927a): the run summary previously printed `image bytes written` from `Stats.imageBytesWritten`, a field nothing ever set — a hardcoded 0 dressed as a measurement, which violates the cardinal rule. Dropped the dead field; the summary now states 0 as a by-construction claim and points to the external `fs_usage` proof as the actual evidence.

Phase 1 design decisions (interview-defensible):
- Capture is downscaled to 256×256 by ScreenCaptureKit itself (GPU), matching the model input with zero extra resize code. This is an anisotropic resize of the whole display, chosen deliberately to preserve all on-screen content (menu bar, dock, edges) rather than center-cropping it away, since the goal is "what was on screen," not a centered subject.
- Scene gate is an 8×8 average hash (64-bit), Hamming-distance threshold default 5/64; first frame always counts as changed.
- Privacy: each pixel buffer is `memset` to zero in RAM after embedding (and on skip) before release; this is a demonstrable in-memory overwrite, not just dropping the reference. The store is fixed-stride binary (8-byte float64 timestamp + 512 float32) for mmap-friendly brute-force search in Phase 2.
- Vectors are already L2-normalized by the Phase 0 export wrapper, so Phase 2 cosine search is a dot product.

## Known issues / open threads
- Pure-ANE latency from Xcode's Performance report is still TBD — it needs the Xcode GUI; the 3.00 ms figure is `predict()` wall-clock and is an upper bound on compute. The M5 run machine has only the Command Line Tools (no full Xcode), so the Performance report can't be run there either; defer to a machine with Xcode.
- M5 toolchain (this session): the M5 has system Python 3.9.6, no Homebrew, Command Line Tools only, Swift 6.3.1. `setup.sh`'s `pip install git+ml-mobileclip` upgraded torch to 2.8.0 (mobileclip declares `torch>=2.8.0`); pinned back to `torch==2.7.0`/`torchvision==0.22.0` to keep Core ML Tools 9.0's tested combination, leaving the same benign dependency-conflict warning. The re-export verified identical to the M1 export (cosine 0.996560, max abs diff 0.014045). Swift 6.3's SDK added `MLMultiArrayDataType.int8`, which broke `Embedder.floatArray`'s exhaustive switch and reintroduced a build warning; added the `.int8` case so `swift build -c release` is warning-free again.
- Screen Recording TCC on the M5 took effect for the already-running Terminal.app **without** an app relaunch — the post-grant re-run captured immediately. This made it possible to drive the measured run from a second Terminal window while this Claude session (in the first window) stayed alive. (If a future machine requires the relaunch, run the capture from a different app bundle, e.g. VS Code's terminal, so the host of the agent session is not the app being restarted.)
- `requirements.txt` pins `torch==2.7.0` (Core ML Tools 9.0's tested version); MobileCLIP declares `torch>=2.8.0`, so `pip` prints a benign dependency-conflict warning. Inference/zero-shot verified identical on 2.7.0.
- Core ML Tools 9.0 cannot convert the S2 graph via TorchScript tracing (`aten::Int` cast crash); we convert via the `torch.export` frontend with `run_decompositions({})`.
- The published S2 checkpoint is already reparameterized; `reparameterize_model` is intentionally not called (it errors on the fused modules).
- After the lab-Mac wipe the `origin` remote is a clean tokenless HTTPS URL (`https://github.com/rohan-chandrashekar/zero-context-retention-engine.git`) and `gh` is not installed, so `git push` prompts for credentials. Use a GitHub Personal Access Token (classic, `repo` scope) as the password, or install `gh` and run `gh auth login`. (Supersedes the earlier note about a PAT embedded in the remote URL, which the wipe removed.)
- RESOLVED (this session): the benign heartbeat data race. `Stats` now guards the three frame counters and the latency array with an `NSLock` and exposes lock-safe accessors (`recordComplete`/`recordSkipped`/`recordEmbedded`, `framesComplete`/`Embedded`/`Skipped`, `latencyCount`); `FrameProcessor` and `Summary` use them. The 5 s `CaptureEngine` heartbeat no longer races the `zre.frames` queue. The measured run above was done on the hardened build. Lock contention at ≤2 fps is negligible and does not affect the latency numbers.

## Next action
Phase 2 — On-device OCR + semantic retrieval. Add Vision `VNRecognizeTextRequest` to each embedded frame (store recognized text alongside the vector + timestamp; still no image). Export the MobileCLIP **text** encoder to Core ML too, then build a query CLI: embed a text query and return the top-k past moments by cosine similarity (vectors are already L2-normalized, so cosine = dot product over the fixed-stride store). Done when "when was I looking at X" returns correct timestamped hits, with retrieval precision reported on a small hand-labeled set. Reuse the Phase 0 export path for the text encoder and the Phase 1 store format (`8-byte float64 timestamp + 512 float32`; OCR text needs a parallel/extended store layout — decide and document it).
