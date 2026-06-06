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

ScreenCaptureKit captures the display directly downscaled to 256×256 BGRA on the GPU. Each frame passes an 8×8 average-hash scene-change gate (64-bit hash, Hamming-distance threshold) so near-identical frames skip the encoder. Frames that pass are embedded on the ANE via the Phase 0 Core ML model; only the 512-d vector and a timestamp are appended to an append-only binary store (`8-byte float64 timestamp + 512 float32`). The pixel buffer is never written to disk and is overwritten in RAM (`memset` to zero) before release.

Measured on **Apple M5 (MacBook Pro, Mac17,2, 16 GB, macOS 26.5.1)** — a different chip from the Phase 0 M1 above, so these numbers are **not** comparable to the Phase 0 table. A single 210 s capture session during real browsing/scrolling/app-switching; the `fs_usage` zero-retention proof traced the live process throughout.

| Metric | Value |
|---|---|
| Per-processed-frame latency — median / p95 / mean (ms) | **6.97 / 28.72 / 10.20** (n=43, hash + embed + store) |
| Scene-change gate skip rate (% of complete frames skipped) | **87.2 %** (292 of 335) |
| Frames complete / embedded / skipped | **335 / 43 / 292** |
| Vectors stored | **43** (store = 88,408 B = 43 × 2056, exact) |
| **Image bytes written to disk** | **0** (proven; see below) |

The per-frame number is the **whole processed-frame path** — the full-frame average hash, the Core ML embed, and the store append — not the bare encoder call, so it is not the same quantity as the Phase 0 `predict()` latency. The scene gate skipped ~7 of every 8 frames *during active use*, paying the encoder only when the screen actually changed.

**Zero-retention proof (measured, not asserted).** `fs_usage` traced every filesystem syscall of the live process. Across the run: no `open`/`read`/`write` ever referenced an image-file path, and the **largest single write was 2056 bytes — one vector record (8-byte timestamp + 512 float32), 127× smaller than a single raw 256×256×4 = 262,144-byte frame.** The complete write profile was 2056-byte vector records (fd 3), ≤43-byte text heartbeats to the engine's own log (fd 2), and 2-byte ScreenCaptureKit frame-ready wakeup tokens (fd 5). No frame, or any fraction of one approaching frame size, was ever written. The privacy invariant is thus a code-level guarantee (the pixel buffer has no write path and is `memset` to zero before release) *and* an observed property of the running process.

**Phase 1 run** (on your Mac, after granting Screen Recording to the app hosting your terminal):

```bash
swift build -c release
bash scripts/run_phase1.sh 180          # launches the engine + runs the fs_usage proof as root
# or drive the two halves manually:
.build/release/zre --duration 180 --fps 2 --scene-threshold 5
sudo bash scripts/proof_zero_retention.sh <pid> 180        # capture + analyze
sudo bash scripts/proof_zero_retention.sh --analyze <log>  # re-analyze an existing trace
```

The engine prints a live summary (frames complete/embedded/skipped, latency median/p95/mean). The proof traces the process with `fs_usage`, asserts no image-file paths, and runs a write-size test: it reports the largest write and confirms it is far below one raw frame.

### On-device OCR + semantic retrieval (Phase 2)

Each kept frame now also passes through Apple's **Vision** OCR (`VNRecognizeTextRequest`, on-device, no network), and the recognized text is stored next to the vector — still no image. A natural-language query is embedded with the **MobileCLIP text encoder** (exported to Core ML alongside the image encoder) and ranked against the stored image vectors by cosine similarity, so *"when was I looking at X"* returns timestamped moments.

**Resolution change (why the pipeline differs from Phase 1).** OCR needs legible text, which a 256×256 thumbnail of a whole display does not have. So Phase 2 captures at the display's **native resolution**, runs OCR on that frame, then downscales to 256×256 (vImage / Accelerate) for the embedder. Both the native frame and the 256×256 derivative are `memset` to zero in RAM and never written to disk — the privacy invariant is unchanged; only the per-frame compute path changed, so the Phase 1 latency above is not comparable and is re-measured here.

**Store layout.** Vectors stay in the Phase 1 fixed-stride binary store (`8-byte float64 timestamp + 512 float32`) so brute-force cosine search stays mmap-friendly and the zero-retention write-size proof still holds. OCR text goes in a **parallel JSONL sidecar** (`{"i": index, "t": timestamp, "text": ...}`), aligned to the vector store by record index and timestamp. Variable-length text never perturbs the fixed-stride vector file.

All Phase 2 numbers are **pending the single M5 measurement run** (per the build-here / measure-on-M5 plan); retrieval-quality numbers are machine-independent (CPU and ANE produce the same vectors modulo FP16) and will be measured on a hand-labeled capture.

| Metric | Value |
|---|---|
| Text encoder Core ML export — cosine vs PyTorch | _TBD — run `scripts/verify_text_coreml.py`_ |
| Per-frame latency [downscale + hash + OCR + embed + store], median / p95 / mean | _TBD (M5)_ |
| OCR latency (Vision, accurate), median / p95 / mean | _TBD (M5)_ |
| Retrieval top-1 accuracy / precision@5 / MRR (hand-labeled set) | _TBD (machine-independent; needs a labeled capture)_ |

**Run it:**

```bash
# 1. export the text encoder (mirrors the Phase 0 image export, torch.export frontend)
python scripts/export_coreml.py --encoder text --output MobileCLIPText.mlpackage
python scripts/verify_text_coreml.py --model MobileCLIPText.mlpackage   # cosine vs PyTorch

# 2. capture with OCR on (native-res capture, 256x256 embed)
.build/release/zre --duration 180 --fps 2 --scene-threshold 5         # --no-ocr to skip OCR

# 3. ask "when was I looking at X"
python scripts/query.py --query "a code editor with Swift source" --k 5
python scripts/dump_store.py        # list every stored moment (idx, time, OCR snippet) for labeling

# 4. measure retrieval precision on a hand-labeled set
#    copy scripts/labels.template.json -> vectorstore/labels.json, fill in the relevant
#    record indices (from dump_store.py) for each query, then:
python scripts/eval_retrieval.py --labels vectorstore/labels.json --k 5
```

### Privacy red-team + defense (Phase 3 — the differentiator)

The privacy claim is attacked, then defended, with real measured numbers. Two attacks run against the stored vectors (no image is ever available to the attacker):

- **Semantic leakage** (`scripts/attack_semantic_leakage.py`): each stored image vector is scored against a candidate-text vocabulary (`scripts/leakage_vocab.txt` — "a bank login page", "a medical record", "a password manager", …) embedded with the MobileCLIP text encoder. The top-scoring label is the attacker's recovered guess of what was on screen. Fidelity is reported as the attacker's mean top-1 cosine and, under defense, how much of the recovered label set survives.
- **Feature inversion** (`scripts/attack_inversion.py`): a small decoder is trained on the attacker's own (image, embedding) pairs to map a 512-d embedding back to a 64×64 image, then used to reconstruct the stored embeddings. Fidelity is mean **SSIM** vs the originals.

Defenses (`scripts/defense.py`, swept by `scripts/eval_defense.py`) transform the stored 512-d vectors in place, keeping the store format so Phase 2 retrieval still runs: **PCA** low-rank reconstruction, scalar **quantization**, and additive **Gaussian (DP-style) noise**. The eval reports attack fidelity collapse *against* retained retrieval accuracy — a defense is only good if it pushes the attack down while holding legitimate retrieval up.

The machine-independent math (defenses, leakage scoring, retrieval-retention, store round-trip) is verified now by `scripts/selftest_defense.py` and `scripts/selftest_retrieval.py` (numpy-only). All *fidelity numbers* are **TBD** — they require running the MobileCLIP encoders on real captured vectors, which only runs on Apple Silicon (the M5), and a hand-labeled set. **No outcome is asserted in advance:** whether additive noise can separate leakage from retrieval, or whether PCA/quantization do it better, is reported from the measured run, not assumed.

| Defense | Leakage: top-1 label retained vs undefended (↓ better) | Inversion SSIM (↓ better) | Retrieval precision@5 retained (↑ better) |
|---|---|---|---|
| None (raw vectors) | _TBD (M5)_ | _TBD (M5)_ | _TBD (M5)_ |
| PCA (k=64) | _TBD (M5)_ | _TBD (M5)_ | _TBD (M5)_ |
| Quantize (4-bit) | _TBD (M5)_ | _TBD (M5)_ | _TBD (M5)_ |
| Gaussian noise (σ sweep) | _TBD (M5)_ | _TBD (M5)_ | _TBD (M5)_ |

```bash
python scripts/attack_semantic_leakage.py --show 20          # what the attacker recovers from vectors alone
python scripts/attack_inversion.py --images attack_images    # train inversion decoder, report SSIM
python scripts/eval_defense.py --labels vectorstore/labels.json   # before/after leakage vs retrieval table
python scripts/selftest_defense.py                           # numpy-only: defenses + scoring math (runs anywhere)
```

### Cross-variant benchmark + visualizer (Phase 4)

A cross-variant benchmark (`scripts/bench_all.py`) times the MobileCLIP **S0 / S1 / S2 / B** image encoders across ANE / GPU / CPU and emits a markdown table; if another Mac generation is available, the same script run there adds a machine column. A small local web visualizer (`viz/index.html`, fed by `scripts/export_viz.py`) shows three screen-recordable panels: the pixel buffer being wiped each cycle, a PCA concept map of the stored vectors growing as you browse, and the attacker's reconstruction collapsing after the defense. `DEMO.md` holds the LinkedIn post and the 30–60 s video script.

| Variant | Model size (MB) | ANE median (ms) | Throughput (img/s) |
|---|---|---|---|
| MobileCLIP-S0 | _TBD (M5)_ | _TBD (M5)_ | _TBD (M5)_ |
| MobileCLIP-S1 | _TBD (M5)_ | _TBD (M5)_ | _TBD (M5)_ |
| MobileCLIP-S2 | _TBD (M5)_ | _TBD (M5)_ | _TBD (M5)_ |
| MobileCLIP-B | _TBD (M5)_ | _TBD (M5)_ | _TBD (M5)_ |

All Phase 4 latency/size numbers come from the single M5 run (see `MEASURE.md` section F). The visualizer and benchmark code are complete; the PCA projection and table emitter are verified machine-independently.

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
