# Progress

## Current status
Phase 0 complete and verified on hardware (Apple M1, iMac21,1, 16 GB, macOS 15.7.3). MobileCLIP-S2 image encoder exported to Core ML, benchmarked across compute units, and checked for correctness against the PyTorch reference.

Phase 1 complete and verified by a live capture run on **Apple M5 (MacBook Pro, Mac17,2, 16 GB, macOS 26.5.1)** — a different machine/chip from the Phase 0 M1, by design (the M1 was a non-admin ASU lab Mac that could not grant Screen Recording TCC). The Core ML model was re-exported and re-verified on the M5 (cosine 0.996560 vs PyTorch, identical to the M1 export). The Swift engine (`swift build -c release` clean, no warnings) runs the ScreenCaptureKit -> scene-gate -> ANE-embed -> store loop, overwriting each pixel buffer in RAM and never writing a frame. A 210 s real-browsing session was captured while `fs_usage` traced the process; per-frame latency, scene-gate skip rate, vectors stored, and the zero-retention proof are all measured and recorded below.

Phase 2 is **code complete and builds clean** (`swift build -c release`, no warnings) on an **Intel Mac (x86_64, macOS 26.5.1, Swift 6.3.2)** — the development machine for this and later phases. Per the agreed plan, the entire project is built and correctness-tested on the Intel Mac, and every machine-dependent number (latency, throughput) is measured once on the M5 at the end so the friend's laptop is borrowed only once. The engine now adds Vision OCR per kept frame, captures at native resolution and downscales to 256×256 (vImage) for the embedder, and writes an index-aligned JSONL text sidecar beside the unchanged fixed-stride vector store. The MobileCLIP text encoder export + a retrieval CLI + a precision harness are written. **No Phase 2 number has been measured yet** (the Python ML env / a labeled capture / the M5 run are still pending); nothing is recorded as measured until it is.

## Phase checklist
- [x] Phase 0 — MobileCLIP-S2 to Core ML conversion + embedding benchmark
- [x] Phase 1 — Capture spine + zero-retention proof (measured on Apple M5; live run + fs_usage proof done)
- [ ] Phase 2 — On-device OCR + semantic retrieval (code complete + builds clean on Intel; export verify + retrieval precision + latency all pending measurement)
- [ ] Phase 3 — Privacy red-team + defense (code complete; machine-independent math self-tested on Intel; attack/defense fidelity numbers pending the M5 run)
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

## Phase 2 — code complete, measurement pending

Pipeline change (interview-defensible): OCR on a 256×256 thumbnail of a whole display reads nothing, so capture now runs at the display's **native pixel resolution** (`CGDisplayCopyDisplayMode` pixel size, optional `--capture-max-long-edge` cap), OCR runs on that legible frame, and a vImage (Accelerate) downscale to 256×256 feeds the embedder. The scene-gate hash runs on the 256×256 derivative (same semantics as Phase 1). Both the native frame and the 256 derivative are `memset` to zero before release, so the privacy invariant is unchanged — the change is to the compute path only, which is why the Phase 1 latency is not comparable and is re-measured.

Store layout (decided + documented): the vector store is untouched — same fixed-stride `8-byte float64 timestamp + 512 float32` binary, so brute-force cosine stays mmap-friendly and the zero-retention write-size proof still holds. OCR text is written to a **parallel JSONL sidecar** (`vectorstore/text.jsonl`, one `{"i","t","text"}` object per line), aligned to the vector store by record index (read before the vector append) and by timestamp (the same `Date().timeIntervalSince1970` passed to both writers). Variable-length text never perturbs the fixed-stride vector file. The sidecar writes are small text appends (far below one raw frame), so `scripts/proof_zero_retention.sh` still passes unmodified; OCR text is retained *by design* (the point of Phase 2) — the invariant is specifically about raw pixels.

Retrieval: `scripts/export_coreml.py --encoder text` exports the MobileCLIP text encoder to Core ML via the same `torch.export` + `run_decompositions({})` path as the image encoder (external int32 token input, cast to long inside the wrapper for the embedding lookup; 77-token context). `scripts/query.py` embeds a text query and returns top-k moments (timestamp + OCR snippet); `scripts/dump_store.py` lists every moment for labeling; `scripts/eval_retrieval.py` computes top-1 / precision@k / MRR against a hand-labeled `vectorstore/labels.json`; `scripts/verify_text_coreml.py` checks Core ML vs PyTorch cosine. `scripts/retrieval_common.py` holds the shared store/text loaders and query embedding.

Measured numbers (Phase 2): **all TBD — nothing measured yet.** Reasons and how to obtain each:
- Text-encoder export cosine vs PyTorch — TBD; **M5-bound** (see toolchain-ceiling issue below). Run `scripts/verify_text_coreml.py` there. Machine-independent in value. **Risk to watch:** the text tower's EOS pooling uses `argmax` over token ids; if Core ML Tools chokes on it (as TorchScript did on the image graph's `aten::Int`), the export step is where it will surface.
- Per-frame latency [downscale + hash + OCR + embed + store] and OCR latency — TBD; machine-dependent, measured on the M5.
- Retrieval top-1 / precision@5 / MRR — TBD; needs a real capture of known content + a hand-labeled `labels.json`. Machine-independent in value (CPU vectors == ANE vectors modulo FP16), but producing the vectors and query embeddings needs the model toolchain, which only runs on the M5 — so measured there.

The machine-independent retrieval *plumbing* (store binary round-trip, index alignment, cosine ranking) is verified now on Intel by `scripts/selftest_retrieval.py` (numpy-only, no torch/coremltools), so the format and ranking math are not left untested.

## Phase 3 — code complete, fidelity numbers pending

Attacks (Python, operate only on the vector store — the attacker never has an image):
- `attack_semantic_leakage.py` — scores each stored image vector against a candidate-text vocabulary (`leakage_vocab.txt`, sensitive labels like bank login / medical record / password manager) embedded with the Core ML text encoder; the top label is the recovered guess. Reports mean top-1 cosine and per-moment top-3 recovered labels (with the OCR text as a ground-truth hint).
- `attack_inversion.py` — trains a small ConvTranspose decoder on the attacker's own (image, embedding) pairs to map embedding -> 64×64 image, then inverts the stored embeddings; reports mean SSIM (scikit-image) clean vs under each defense. torch + skimage, so M5-run.

Defenses (`redteam_common.py`, applied by `defense.py`, swept by `eval_defense.py`): in-place 512-d vector maps so the store format and Phase 2 retrieval are unchanged — PCA low-rank reconstruction, scalar quantization (per-vector min/max), additive Gaussian noise (with an indicative Gaussian-mechanism ε via `gaussian_epsilon`; documented as indicative, not a formal (ε,δ)-DP guarantee). `eval_defense.py` prints the before/after table: leakage agreement-vs-undefended + attacker confidence against retained retrieval top-1 / precision@k, swept over none / pca / quantize / dpnoise.

Measured numbers (Phase 3): **all TBD.** They need the Core ML encoders run on real captured vectors (M5) plus, for leakage recovery rate and retrieval retention, a hand-labeled set. **No privacy outcome is assumed** — additive noise on L2-normalized embeddings only injects σ-scale noise into the cosine score, so it is an open empirical question whether any defense collapses attack fidelity while keeping retrieval usable; the eval reports the real curve. The machine-independent math (PCA/quantize/noise transforms, leakage scoring, metrics, store round-trip) is verified now on Intel by `selftest_defense.py` and `selftest_retrieval.py` (numpy-only, both passing).

## Known issues / open threads
- Pure-ANE latency from Xcode's Performance report is still TBD — it needs the Xcode GUI; the 3.00 ms figure is `predict()` wall-clock and is an upper bound on compute. The M5 run machine has only the Command Line Tools (no full Xcode), so the Performance report can't be run there either; defer to a machine with Xcode.
- M5 toolchain (this session): the M5 has system Python 3.9.6, no Homebrew, Command Line Tools only, Swift 6.3.1. `setup.sh`'s `pip install git+ml-mobileclip` upgraded torch to 2.8.0 (mobileclip declares `torch>=2.8.0`); pinned back to `torch==2.7.0`/`torchvision==0.22.0` to keep Core ML Tools 9.0's tested combination, leaving the same benign dependency-conflict warning. The re-export verified identical to the M1 export (cosine 0.996560, max abs diff 0.014045). Swift 6.3's SDK added `MLMultiArrayDataType.int8`, which broke `Embedder.floatArray`'s exhaustive switch and reintroduced a build warning; added the `.int8` case so `swift build -c release` is warning-free again.
- Screen Recording TCC on the M5 took effect for the already-running Terminal.app **without** an app relaunch — the post-grant re-run captured immediately. This made it possible to drive the measured run from a second Terminal window while this Claude session (in the first window) stayed alive. (If a future machine requires the relaunch, run the capture from a different app bundle, e.g. VS Code's terminal, so the host of the agent session is not the app being restarted.)
- `requirements.txt` pins `torch==2.7.0` (Core ML Tools 9.0's tested version); MobileCLIP declares `torch>=2.8.0`, so `pip` prints a benign dependency-conflict warning. Inference/zero-shot verified identical on 2.7.0.
- Core ML Tools 9.0 cannot convert the S2 graph via TorchScript tracing (`aten::Int` cast crash); we convert via the `torch.export` frontend with `run_decompositions({})`.
- The published S2 checkpoint is already reparameterized; `reparameterize_model` is intentionally not called (it errors on the fused modules).
- After the lab-Mac wipe the `origin` remote is a clean tokenless HTTPS URL (`https://github.com/rohan-chandrashekar/zero-context-retention-engine.git`) and `gh` is not installed, so `git push` prompts for credentials. Use a GitHub Personal Access Token (classic, `repo` scope) as the password, or install `gh` and run `gh auth login`. (Supersedes the earlier note about a PAT embedded in the remote URL, which the wipe removed.)
- Intel toolchain ceiling (defines the Intel/M5 split): the development machine is now an **Intel Mac (x86_64)**. PyTorch stopped publishing x86_64 macOS wheels after **torch 2.2.2**, so the canonical pins (`torch==2.7.0` + Core ML Tools 9, and `mobileclip` which itself requires `torch>=2.8`) **cannot be installed on Intel at all**, on any Python version. Consequence: Core ML *export* and any check that *loads a `.mlpackage` or runs MobileCLIP* (image/text encoder verify, real-vector capture, retrieval precision on real data, Phase 3 attack fidelity on real vectors) are **M5-bound** — they need the model toolchain, which only runs on Apple Silicon here. Intel is used to build all code and to verify machine-and-toolchain-independent logic with synthetic-data self-tests. `requirements.txt` is left at the canonical Apple-Silicon pins on purpose (do NOT downgrade it to fit Intel); a fragile non-canonical Intel torch env was deliberately not built, since the M5 re-exports with the real toolchain anyway. The single M5 run captures every model-dependent number via the turn-key measurement script.
- Cross-architecture build (this session): the engine is now built on an Intel Mac. `Embedder.floatArray`'s `.float16` branch referenced the `Float16` *type*, which is Apple-Silicon-only in the Swift stdlib and fails to compile on x86_64 (`'Float16' is unavailable in macOS`). Fixed by guarding only the `Float16`-typed body with `#if arch(arm64)` and reading those elements through the `MLMultiArray` `NSNumber` subscript on Intel (the `.float16` case stays present so the switch is exhaustive on both arches). In practice the model's embedding output is float32, so this branch rarely runs; the arm64 path (M5) is unchanged. This is purely an enabler for build-on-Intel / measure-on-M5.
- Capture resolution / latency comparability (Phase 2): because capture moved from a fixed 256×256 (Phase 1) to native-res + vImage downscale, the per-frame latency path changed (it now also includes the resize and OCR). The Phase 1 M5 latency (6.97 ms median) is therefore NOT comparable to Phase 2 and must be re-measured on the M5 with the Phase 2 build. On very large displays (5K/6K) consider `--capture-max-long-edge` to bound OCR + resize cost; the M5 laptop panel is small enough that native is fine.
- RESOLVED (this session): the benign heartbeat data race. `Stats` now guards the three frame counters and the latency array with an `NSLock` and exposes lock-safe accessors (`recordComplete`/`recordSkipped`/`recordEmbedded`, `framesComplete`/`Embedded`/`Skipped`, `latencyCount`); `FrameProcessor` and `Summary` use them. The 5 s `CaptureEngine` heartbeat no longer races the `zre.frames` queue. The measured run above was done on the hardened build. Lock contention at ≤2 fps is negligible and does not affect the latency numbers.

## Next action
Phase 2 is code complete on Intel; it still needs its numbers before it can be checked off. Two routes (the second is the agreed default):
1. Optional correctness pass on the Intel Mac (recommended before trusting the code): `bash setup.sh`, download the S2 checkpoint, then `python scripts/export_coreml.py --encoder text` + `python scripts/verify_text_coreml.py` (machine-independent cosine check that de-risks the argmax-pooling conversion), then a short `swift run`/`.build/release/zre` capture of known content (grant Screen Recording first), `python scripts/query.py`, and `python scripts/eval_retrieval.py` against a hand-labeled `vectorstore/labels.json`. Retrieval precision measured here is valid anywhere.
2. The single M5 run: rebuild + re-export on the M5, repeat the capture/query/eval there, and record the machine-dependent latency (per-frame, OCR) plus the (machine-independent) retrieval precision. Fill README / RESUME_BULLETS / this file with the measured numbers, then check Phase 2 done.

After Phase 2's numbers land: Phase 3 — privacy red-team + defense (Python: semantic-leakage scoring of stored image vectors against a candidate-text vocabulary, and a feature-inversion decoder; then defend with quantization / PCA / DP noise and show attack fidelity collapses while Phase 2 retrieval stays usable). Phase 3 reuses `retrieval_common.py` and the Core ML text encoder built here.
