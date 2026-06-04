# Résumé bullets — Zero-Retention Context Engine

Interview-defensible. Every number is measured on the build machine (**Apple M1, iMac21,1, 16 GB, macOS 15.7.3**) — no estimates or round-ups. Bullets are added phase by phase as real results land.

## Phase 0 — On-device embedding model

- Exported Apple's **MobileCLIP-S2** image encoder to a **68.7 MB FP16 Core ML** model and benchmarked it on the **Apple Neural Engine** at a measured **3.00 ms median** embedding latency (3.30 ms p95, ~329 images/s) — **~9.6× faster than CPU** and **~6.3× faster than GPU** on the same M1.
- Validated the export rather than trusting it: **0.9965 cosine** agreement with the PyTorch reference at FP16, plus a CLIP zero-shot check confirming correct 256×256 / `[0,1]` preprocessing (caught that MobileCLIP omits the standard OpenAI CLIP normalization).
- Debugged the Core ML conversion to a reproducible state: routed around a Core ML Tools 9.0 TorchScript-frontend crash by converting through the `torch.export` path, pinned to the converter's tested PyTorch version, and confirmed the published checkpoint ships pre-reparameterized (single-branch inference graph).

## Phase 1 — Zero-retention capture spine

- Built a Swift / ScreenCaptureKit capture engine that embeds the screen on the Neural Engine and keeps only 512-d vectors plus timestamps — raw frames are never written to disk and the pixel buffer is overwritten in RAM (`memset`) before release, making the "anti-Recall" privacy invariant a code-level guarantee rather than a policy.
- Added an 8×8 average-hash scene-change gate that skips near-identical frames before the encoder runs, so embedding cost is paid only when the screen actually changes _(measured skip rate / latency: TBD — pending an interactive-session run; the loop needs Screen Recording TCC permission a headless process cannot hold)_.
- Designed an adversarial proof of the privacy claim: an `fs_usage` syscall trace of the live process that asserts zero image-file writes and confines all data writes to the append-only vector store _(image bytes written: 0 by construction; end-to-end run numbers TBD)_.
## Phase 2 — _pending_
## Phase 3 — _pending_
## Phase 4 — _pending_
