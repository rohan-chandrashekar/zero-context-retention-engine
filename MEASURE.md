# MEASURE.md — the single Apple-Silicon (M5) measurement session

Everything was built and correctness-tested on an Intel Mac. The model toolchain (`torch` 2.7 / Core ML Tools 9 / `mobileclip`) only runs on Apple Silicon, so every machine-dependent number is captured here, once. Follow A → F in order. Record the printed machine label (chip / model / RAM / macOS) with every table.

Before starting: `git clone` (or `git pull`) the repo on the M5 and `cd` in. Grant the terminal app Screen Recording in System Settings → Privacy & Security → Screen Recording.

---

## A. Deterministic part (one command)

```bash
# optional: drop a test image for the image-encoder cosine check
curl -L -o /tmp/zrce_cats.jpg <any image url>

bash scripts/run_all_measurements.sh
```

This sets up the venv, downloads the S2 checkpoint, exports the **image + text** encoders, verifies both vs PyTorch, benchmarks the image encoder across ANE/GPU/CPU/ALL, builds the engine, and runs the numpy self-tests.

Numbers produced here:
- **Phase 0 table** (README) — model size + median/p95/throughput per compute unit, from `bench_coreml.py`.
- **Image export correctness** — `cosine_torch_vs_coreml` (expect ~0.9965, matching the M1/M5 history).
- **Phase 2 text-encoder correctness** — `verify_text_coreml.py` cosine per prompt. **If this step errors, the text export hit the argmax-pooling risk noted in PROGRESS — stop and fix the export before continuing.**

---

## B. Capture + zero-retention proof (Phase 1 / Phase 2 latency)

Pick known content to browse so you can label it later (e.g. a code editor, a banking page, a YouTube video, a terminal, an email inbox). Then:

```bash
.build/release/zre --duration 210 --fps 2 --scene-threshold 5
# in a second terminal, while it runs:
sudo bash scripts/proof_zero_retention.sh <pid> 210
```

Record from the engine's run summary: per-frame latency (median/p95/mean, the `downscale + hash + ocr + embed + store` path), **OCR latency**, scene-gate skip rate, vectors stored, chars recognized. Record from the proof: largest single write vs raw-frame size (must be far below a frame) and zero image paths.

→ Fill the **Phase 1** and **Phase 2** latency rows in README + RESUME_BULLETS + PROGRESS. (Phase 1's old 6.97 ms is from the 256×256-capture pipeline and is now superseded — the Phase 2 pipeline adds the resize + OCR.)

---

## C. Retrieval precision (Phase 2)

```bash
python scripts/dump_store.py                 # list every moment (idx, time, OCR snippet)
cp scripts/labels.template.json vectorstore/labels.json
# edit vectorstore/labels.json: for each query, list the record indices that truly show it
python scripts/query.py --query "a code editor with Swift source" --k 5
python scripts/eval_retrieval.py --labels vectorstore/labels.json --k 5
```

→ Fill **Phase 2 retrieval** row (top-1 / precision@5 / MRR) in README + RESUME_BULLETS + PROGRESS.

---

## D. Privacy red-team + defense (Phase 3)

```bash
# semantic leakage: what the attacker recovers from vectors alone
python scripts/attack_semantic_leakage.py --show 20

# before/after table: leakage fidelity vs retained retrieval, swept over defenses
python scripts/eval_defense.py --labels vectorstore/labels.json --k 5

# feature inversion: needs a folder of sample images the attacker trains on
mkdir -p attack_images   # put ~50+ varied images here (any public image set)
python scripts/attack_inversion.py --images attack_images --epochs 300
```

→ Fill the **Phase 3** before/after table (leakage retained / inversion SSIM / retrieval precision retained) in README + RESUME_BULLETS + PROGRESS. Report the real trade-off — do not claim a defense separates leakage from retrieval unless the numbers show it.

---

## E. Visualizer (Phase 4)

```bash
python scripts/export_viz.py                                  # writes viz/data.json
python scripts/attack_inversion.py --images attack_images --dump viz   # writes viz/recon_*.png
python3 -m http.server                                        # open http://localhost:8000/viz/
```

Screen-record the three panels for the demo.

---

## F. Cross-variant benchmark (Phase 4, optional but strong)

```bash
for v in mobileclip_s0 mobileclip_s1 mobileclip_b; do
  VARIANT=$v IMG_MODEL=MobileCLIP_${v}_image.mlpackage bash scripts/run_all_measurements.sh
done
python scripts/bench_all.py --machine "Apple M5 (Mac17,2, 16 GB, macOS 26.5.1)" \
  --models MobileCLIP_mobileclip_s0_image.mlpackage MobileCLIP_mobileclip_s1_image.mlpackage \
           MobileCLIPImage.mlpackage MobileCLIP_mobileclip_b_image.mlpackage
```

→ Fill the **Phase 4 cross-variant** table. If another Mac generation is ever available, run `bench_all.py` there too and add a machine column.

---

## After: write the numbers down and save

1. Edit README.md / RESUME_BULLETS.md / PROGRESS.md, replacing every `TBD` with the measured value (and the machine label). Check off the phases in PROGRESS.
2. Fill the real numbers into DEMO.md's bracketed placeholders.
3. `git add -A && git commit -m "Measured numbers from the M5 run" && git push`
4. `git log origin/main --oneline -1` to confirm the push landed.
