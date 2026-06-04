# Résumé bullets — Zero-Retention Context Engine

Interview-defensible. Every number is measured on the build machine (**Apple M1, iMac21,1, 16 GB, macOS 15.7.3**) — no estimates or round-ups. Bullets are added phase by phase as real results land.

## Phase 0 — On-device embedding model

- Exported Apple's **MobileCLIP-S2** image encoder to a **68.7 MB FP16 Core ML** model and benchmarked it on the **Apple Neural Engine** at a measured **3.00 ms median** embedding latency (3.30 ms p95, ~329 images/s) — **~9.6× faster than CPU** and **~6.3× faster than GPU** on the same M1.
- Validated the export rather than trusting it: **0.9965 cosine** agreement with the PyTorch reference at FP16, plus a CLIP zero-shot check confirming correct 256×256 / `[0,1]` preprocessing (caught that MobileCLIP omits the standard OpenAI CLIP normalization).
- Debugged the Core ML conversion to a reproducible state: routed around a Core ML Tools 9.0 TorchScript-frontend crash by converting through the `torch.export` path, pinned to the converter's tested PyTorch version, and confirmed the published checkpoint ships pre-reparameterized (single-branch inference graph).

## Phase 1 — _pending_
## Phase 2 — _pending_
## Phase 3 — _pending_
## Phase 4 — _pending_
