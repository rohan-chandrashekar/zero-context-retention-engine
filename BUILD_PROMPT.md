You are building a macOS portfolio project called the "Zero-Retention Context Engine."
It is the flagship project for my Apple internship application (AIML and Software
Engineering tracks). It must survive scrutiny from a senior Apple ML engineer in a
technical interview.

THE NON-NEGOTIABLE RULE: every performance number must be genuinely measured on this
machine. Never fabricate, estimate, extrapolate, or round up a metric. If a number
cannot be measured yet, write "TBD" and state why. The credibility of the numbers IS
the product. A wrong-but-impressive number is a failure; a modest-but-real number is a
success.

WHAT IT DOES
An on-device engine that watches the screen, understands it, and keeps the meaning
without keeping the pixels. Frames are embedded on the Apple Neural Engine and discarded
in memory; only mathematical vectors (plus OCR text and timestamps) are retained. The
privacy claim is then adversarially verified, not merely asserted. This is the
"anti-Recall" thesis: Microsoft Recall stored screenshots; this stores only
irreversible-enough vectors, and proves it.

HARD CONSTRAINTS
- Target Apple Silicon, macOS 14+. Confirm with `sw_vers`, `swift --version`, `uname -m`.
- Core engine: Swift, as a Swift Package Manager executable target (fast `swift run`
  iteration, no Xcode project needed for the engine itself).
- Capture: ScreenCaptureKit. It needs Screen Recording permission; on first run, instruct
  me to enable it in System Settings > Privacy & Security > Screen Recording, then re-run.
- Image embedding: Apple's MobileCLIP image encoder exported to Core ML (.mlpackage),
  running on the Neural Engine.
- OCR: Apple's Vision framework (VNRecognizeTextRequest), on-device.
- ML red-team and analysis: Python (torch, coremltools, numpy).
- Vector store: keep it simple. SQLite or an append-only file; brute-force cosine
  similarity is fine at this scale. Do NOT add a heavyweight vector database.
- PRIVACY INVARIANT: raw frames (CMSampleBuffer / pixel buffers) must never be written to
  disk and must be released/overwritten in memory immediately after embedding. Only
  vectors, OCR text, and timestamps persist. You must be able to prove this (see Phase 1).

ENGINEERING STANDARDS
- Write complete, runnable files. No inline code comments anywhere; use clear names and put
  explanation in commit messages and README prose, not in the code.
- Use clearly-flagged placeholder values for anything not provided (names, IDs, paths).
- Communicate directly. If I suggest something wrong, slow, or that won't survive interview
  scrutiny, push back and explain rather than agreeing.
- Git: one commit per completed phase with a clear message. Maintain a .gitignore excluding
  the venv, model checkpoints, .mlpackage, build artifacts, and the vector store.
- Maintain three living docs, updated at the end of EVERY phase: README.md (numbers-first,
  results tables filled with real measured values), RESUME_BULLETS.md (interview-defensible
  bullets using only measured numbers), PROGRESS.md (done / next / known issues).
- The repo may already contain Phase 0 scripts (scripts/export_coreml.py,
  scripts/bench_coreml.py) and a README from earlier setup. Review and reuse/repair what
  exists instead of blindly recreating it.

ITERATIVE PROTOCOL (IMPORTANT)
Build ONE phase at a time; do not skip ahead. At the end of each phase you MUST:
(1) run the phase's verification steps, (2) update README.md, RESUME_BULLETS.md, and
PROGRESS.md with the real results, (3) commit, (4) STOP and give me a short summary --
what you built, the measured numbers, anything that didn't work, and what the next phase
will do -- then WAIT for me to reply "go" before starting the next phase. Only ask me
questions when genuinely blocked; otherwise make reasonable defaults and note them.

PHASES

Phase 0 -- Toolchain + Core ML model
Convert MobileCLIP-S2 to a Core ML .mlpackage and benchmark embedding latency and model
size on this machine, across compute units (ANE vs GPU vs CPU). Install mobileclip from
github.com/apple/ml-mobileclip, fetch the S2 checkpoint per that repo. Verify the image
input resolution matches the variant's preprocess transform (likely 256x256) -- if first
embeddings look semantically random, this is the usual cause.
Done when: .mlpackage exists; benchmark prints median/p95 latency, size, throughput for ANE;
README embedding table filled with real numbers; also run Xcode's Performance report on the
.mlpackage for the authoritative ANE latency.

Phase 1 -- Capture spine + zero-retention proof
ScreenCaptureKit capture loop -> perceptual-hash scene-change gate (skip near-duplicate
frames) -> Core ML MobileCLIP embedding -> store vector + timestamp; release/zero the pixel
buffer immediately; never write a frame.
Verify (the proof): while running, monitor the process for file writes (e.g. `fs_usage`
filtered to the process, plus watching the output dir) and assert zero image files are
created; log bytes-to-disk for frames = 0. Run during a few minutes of real browsing/coding
and report: per-processed-frame end-to-end latency, scene-change gate hit rate (% frames
skipped), vectors stored, and image bytes written (must be 0).

Phase 2 -- On-device OCR + semantic retrieval
Add Vision OCR to each processed frame (store recognized text with the vector, still no
image). Export the MobileCLIP text encoder too, and build a query CLI: embed a text query
and return the top-k past moments by cosine similarity.
Done when: "when was I looking at X" returns correct timestamped hits; report retrieval
precision on a small hand-labeled set.

Phase 3 -- Privacy red-team + defense (THE DIFFERENTIATOR)
Attack your own vector store, then defend it. Attacks in Python: (a) semantic leakage --
score stored image vectors against a candidate-text vocabulary via CLIP alignment to recover
what was on screen (e.g. "bank login page", "medical record"); (b) feature inversion -- train
a small decoder mapping embedding -> image and show approximate reconstructions. Defense:
apply vector quantization / PCA dimensionality reduction / calibrated DP noise to the stored
vectors and show attack fidelity collapses while legitimate retrieval (Phase 2) stays above a
usable threshold.
Done when: a before/after table of reconstruction fidelity (top-1 semantic recovery rate, and
SSIM or LPIPS for inversion) vs retained retrieval accuracy -- all real measured numbers.

Phase 4 -- Benchmarks + visualizer + storytelling
(a) Cross-variant benchmark table (S0/S1/S2/B); if other Macs are available, cross-generation
(M1/M2/M4) ANE latency. (b) A screen-recordable visualizer with three panels: the memory
buffer being wiped each cycle, a t-SNE/PCA concept map growing as you browse, and the
attacker's failed reconstruction after the defense. (c) Finalize README, RESUME_BULLETS.md,
and a DEMO.md containing a tight LinkedIn post plus a 30-60s video script.
Visualizer may be SwiftUI or a small local web app reading the vector store.

Start now with Phase 0: confirm toolchain and hardware, set up the repo, review any existing
Phase 0 scripts, then do the conversion and benchmark. Report the real numbers and stop.
