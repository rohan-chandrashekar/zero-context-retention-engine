# Résumé bullets — Zero-Retention Context Engine

Interview-defensible. Every number is measured on real hardware — no estimates or round-ups. Two machines are used and each phase labels its own: **Phase 0 on Apple M1** (iMac21,1, 16 GB, macOS 15.7.3); **Phase 1 on Apple M5** (MacBook Pro Mac17,2, 16 GB, macOS 26.5.1). The two chips are different and their numbers are not compared directly. Bullets are added phase by phase as real results land.

## Phase 0 — On-device embedding model

- Exported Apple's **MobileCLIP-S2** image encoder to a **68.7 MB FP16 Core ML** model and benchmarked it on the **Apple Neural Engine** at a measured **3.00 ms median** embedding latency (3.30 ms p95, ~329 images/s) — **~9.6× faster than CPU** and **~6.3× faster than GPU** on the same M1.
- Validated the export rather than trusting it: **0.9965 cosine** agreement with the PyTorch reference at FP16, plus a CLIP zero-shot check confirming correct 256×256 / `[0,1]` preprocessing (caught that MobileCLIP omits the standard OpenAI CLIP normalization).
- Debugged the Core ML conversion to a reproducible state: routed around a Core ML Tools 9.0 TorchScript-frontend crash by converting through the `torch.export` path, pinned to the converter's tested PyTorch version, and confirmed the published checkpoint ships pre-reparameterized (single-branch inference graph).

## Phase 1 — Zero-retention capture spine (measured on Apple M5)

- Built a Swift / ScreenCaptureKit capture engine that embeds the screen on the Neural Engine and keeps only 512-d vectors plus timestamps — raw frames are never written to disk and the pixel buffer is overwritten in RAM (`memset`) before release, making the "anti-Recall" privacy invariant a code-level guarantee rather than a policy. Measured at **6.97 ms median** per processed frame (10.20 ms mean, n=43) for the full hash + ANE-embed + store path.
- Added an 8×8 average-hash scene-change gate that skips near-identical frames before the encoder runs: over a 210 s real-browsing session it **skipped 87.2% of frames** (292 of 335), so the encoder ran only on the ~1-in-8 frames where the screen actually changed.
- Proved the privacy claim adversarially rather than asserting it: an `fs_usage` syscall trace of the live process showed **zero image-file paths and a largest single write of 2056 bytes — one vector record, 127× smaller than a raw 262,144-byte frame** — so no frame, or any fraction near frame size, was ever written. The on-disk store (88,408 B) equals 43 × 2056 exactly, tying every byte on disk to a stored vector.
## Phase 2 — On-device OCR + semantic retrieval (code complete; numbers pending the M5 measurement run)

Engineering done (real); every number below is **TBD** until the single M5 run, and no number is written until measured (cardinal rule).

- Added Apple **Vision** on-device OCR to each kept frame and a parallel index-aligned text sidecar, so the engine retains recognized text beside each vector while still never writing a frame; resolved the OCR-vs-embed resolution conflict by capturing at native resolution for OCR and downscaling to 256×256 (vImage) for the encoder, with both buffers `memset` before release. _OCR latency: TBD (M5)._
- Exported the **MobileCLIP text encoder** to Core ML through the same `torch.export` path as the image encoder and built a natural-language retrieval CLI that ranks stored image vectors by cosine similarity (vectors pre-normalized, so cosine = dot product over the fixed-stride store). _Text-encoder export cosine vs PyTorch: TBD; retrieval top-1 / precision@5 / MRR on a hand-labeled set: TBD (machine-independent)._
- Made the Swift engine build cleanly cross-architecture (Intel + Apple Silicon) so development happens on one machine and the authoritative numbers are measured once on the Neural Engine machine.

## Phase 3 — Privacy red-team + defense (code complete; fidelity numbers pending the M5 run)

Engineering done (real); the machine-independent attack/defense math is verified by numpy-only self-tests (`selftest_defense.py`, `selftest_retrieval.py`). Every fidelity number is **TBD** until measured on real vectors on the M5, and no privacy outcome is assumed in advance.

- Built two attacks against the engine's own vector store, with no image available to the attacker: a **semantic-leakage** attack that recovers what was on screen by scoring stored image vectors against a sensitive-label vocabulary through the MobileCLIP text encoder, and a **feature-inversion** decoder that reconstructs a 64×64 image from a 512-d embedding (SSIM-scored). _Top-1 recovery and inversion SSIM: TBD (M5)._
- Implemented three in-place vector defenses — PCA low-rank, scalar quantization, and additive Gaussian (DP-style) noise with an indicative ε — and a before/after harness that measures attack-fidelity collapse against retained Phase 2 retrieval accuracy, so the privacy/utility trade-off is a measured curve, not a slogan. _Before/after table: TBD (M5)._

## Phase 4 — _pending_
