# run_prompt.md — paste this to Claude Code on the Apple Silicon Mac (M5 or M1)

You are running the Zero-Retention Context Engine's measurement session on this Apple Silicon Mac. All four phases are already built and committed; your job is to **measure the real numbers on this machine and record them into the living docs** — nothing else. Work through the steps in order. Stop at each 🧑 HUMAN STEP and wait for me before continuing.

## The one rule that matters

Every number you write must be genuinely produced by a command on THIS machine, in this session. **Never fabricate, estimate, extrapolate, or round up.** If a step fails or can't run, write `TBD` with the one-line reason and tell me — do not invent a plausible value. A modest real number is a success; a wrong impressive number is a failure. This is an Apple-interview portfolio project; the credibility of the numbers IS the product.

## Orientation (do first)

1. Read `CLAUDE.md`, `PROGRESS.md`, and `MEASURE.md` before doing anything.
2. Confirm the machine: run `uname -m` — it MUST be `arm64`. If it prints `x86_64`, STOP and tell me you're on the wrong (Intel) machine; the model toolchain won't run.
3. Capture this machine's exact label and use it on every number you record here:
   `sysctl -n machdep.cpu.brand_string hw.memsize; sw_vers; swift --version | head -1` and the model id from `system_profiler SPHardwareDataType | grep "Model Identifier"`. Format it like `Apple M5 (Mac17,2, 16 GB, macOS 26.5.1)`.

## Step A — deterministic measurements (one command)

Run `bash scripts/run_all_measurements.sh`. It sets up the venv, downloads the checkpoint, exports the image + text encoders, verifies both vs PyTorch, benchmarks across compute units, builds the engine, and runs the self-tests. From its output, record:

- **Phase 0 table** (README): model size + median/p95/throughput for ANE / GPU / CPU / ALL.
- **Image export cosine** vs PyTorch (expect ~0.9965).
- **Phase 2 text-encoder cosine** vs PyTorch. ⚠️ If `verify_text_coreml.py` errors, the text export hit the argmax-pooling risk noted in PROGRESS — STOP, tell me, and we fix the export before continuing. Do not proceed with a broken text encoder.

Provide a test image for the image-encoder check if missing: tell me to drop one at `/tmp/zrce_cats.jpg`, or skip that single cosine line and mark it TBD with the reason.

## Step B — capture + zero-retention proof (Phase 1/2 latency) 🧑 HUMAN STEP

1. Tell me to grant Screen Recording to this terminal app (System Settings → Privacy & Security → Screen Recording) if not already.
2. Tell me a concrete list of ~6 things to browse for ~210s so I can label them later (e.g. a code editor, a banking login page, a YouTube video, a terminal, an email inbox, a maps page). 
3. Start `.build/release/zre --duration 210 --fps 2 --scene-threshold 5`, print its pid, and tell me to browse that list now. If the engine exits within ~2s, that's a missing Screen-Recording grant — tell me to grant + relaunch.
4. In parallel, tell me to run `sudo bash scripts/proof_zero_retention.sh <pid> 210` in a second terminal (it needs my password), and paste you the output.
5. Record from the run summary: per-frame latency (median/p95/mean, the `downscale + hash + ocr + embed + store` path), **OCR latency**, scene-gate skip rate, vectors stored, chars recognized. Record from the proof: largest single write vs raw-frame size (must be far below a frame) and that zero image paths appeared. These fill the Phase 1 + Phase 2 latency rows (note Phase 1's old 6.97 ms is superseded by the Phase 2 pipeline).

## Step C — retrieval precision (Phase 2) 🧑 HUMAN STEP

1. Run `python scripts/dump_store.py` and show me the moments (idx, time, OCR snippet).
2. Draft `vectorstore/labels.json` from `scripts/labels.template.json`: propose, for each query, the record indices that truly match (use the OCR snippets), then ask me to confirm or correct before saving. The relevance judgement is mine, not yours.
3. Run `python scripts/query.py --query "..."` on a couple of my queries to show it works, then `python scripts/eval_retrieval.py --labels vectorstore/labels.json --k 5`.
4. Record top-1 / precision@5 / MRR into the Phase 2 retrieval row.

## Step D — privacy red-team + defense (Phase 3) 🧑 HUMAN STEP

1. Run `python scripts/attack_semantic_leakage.py --show 20` and show me what the attacker recovers from vectors alone.
2. Run `python scripts/eval_defense.py --labels vectorstore/labels.json --k 5` for the before/after leakage-vs-retrieval table.
3. Ask me to put ~50+ varied images in `attack_images/`, then run `python scripts/attack_inversion.py --images attack_images --epochs 300` for the SSIM before/after.
4. Record the Phase 3 table (leakage retained / inversion SSIM / retrieval precision retained). **Report the real trade-off** — if a defense does NOT separate leakage from retrieval, say so. Do not claim a clean collapse unless the numbers show it.

## Step E — visualizer (Phase 4)

Run `python scripts/export_viz.py`, then `python scripts/attack_inversion.py --images attack_images --dump viz`, then tell me to open the visualizer with `python3 -m http.server` → `http://localhost:8000/viz/` and screen-record the three panels.

## Step F — cross-variant / cross-generation benchmark (Phase 4)

Export the other variants and benchmark them, labeled with this machine:
```
for v in mobileclip_s0 mobileclip_s1 mobileclip_b; do
  VARIANT=$v IMG_MODEL=MobileCLIP_${v}_image.mlpackage bash scripts/run_all_measurements.sh
done
python scripts/bench_all.py --machine "<this machine label>" \
  --models MobileCLIP_mobileclip_s0_image.mlpackage MobileCLIP_mobileclip_s1_image.mlpackage \
           MobileCLIPImage.mlpackage MobileCLIP_mobileclip_b_image.mlpackage
```
Record the cross-variant table under this machine's label.

## Step G — write the numbers down, then save

1. Replace every `TBD` you measured in `README.md`, `RESUME_BULLETS.md`, and `PROGRESS.md` with the real value **plus this machine's label**. Check off the phases in PROGRESS only once their numbers are filled. Fill the bracketed placeholders in `DEMO.md`.
2. Re-run `python scripts/selftest_retrieval.py && python scripts/selftest_defense.py && swift build -c release` to confirm still green.
3. Commit after each phase's numbers land (don't wait until the end): `git add -A && git commit -m "Measured <phase> on <machine label>"`. Then `git push` (it will prompt for my GitHub PAT). Confirm with `git log origin/main --oneline -1`.

## If you are the SECOND Apple Silicon machine (e.g. the M1 after the M5)

Latency/throughput are machine-dependent — **add a new labeled column/row** for this machine in the Phase 0 and Phase 4 benchmark tables (Steps A and F); do NOT overwrite the other machine's numbers. Retrieval precision and Phase 3 fidelity are machine-**independent** (same vectors modulo FP16) — if they're already filled from the other machine, do NOT re-measure or overwrite them; just note they were measured once. So on a second machine, effectively only Steps A, B (optional), and F add value.
