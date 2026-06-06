# DEMO.md — storytelling

Every `[BRACKET]` is a placeholder for a real measured number from the M5 run (see MEASURE.md). Do not post until the brackets are filled with measured values — a wrong-but-impressive number is a failure.

---

## LinkedIn post

Microsoft Recall stored screenshots of everything you did. I wanted the opposite: an on-device engine that keeps the *meaning* of your screen without keeping the *pixels* — and then I tried to break my own privacy claim instead of just asserting it.

**Zero-Retention Context Engine** (Swift + Apple's on-device stack):
- ScreenCaptureKit → a perceptual-hash scene gate (skips ~[SKIP_RATE]% of near-identical frames) → MobileCLIP on the Neural Engine → a 512-d vector + on-device Vision OCR text + a timestamp. The raw frame is `memset` to zero in RAM and **never written to disk**.
- I proved that, didn't just claim it: an `fs_usage` syscall trace of the live process shows zero image-file writes; the largest single write is one [RECORD_BYTES]-byte vector record — [N]× smaller than a single raw frame.
- Embedding latency on the Apple Neural Engine: **[ANE_MEDIAN] ms median** ([ANE_THROUGHPUT] img/s), [SPEEDUP]× faster than CPU.
- Natural-language recall: "when was I looking at a code editor?" returns the right timestamped moments — [RETRIEVAL_TOP1] top-1 accuracy on a hand-labeled set.

Then the part I care about most — I red-teamed it:
- A semantic-leakage attack scores the stored vectors against sensitive labels ("bank login", "medical record") to recover what was on screen.
- A feature-inversion decoder tries to rebuild the image from the embedding.
- Then I defended with PCA / quantization / calibrated noise and measured the trade-off: reconstruction fidelity dropped from [SSIM_BEFORE] to [SSIM_AFTER] SSIM while retrieval stayed at [RETRIEVAL_AFTER].

Privacy you can measure beats privacy you promise. Code + numbers: [REPO_LINK]

#MachineLearning #AppleSilicon #CoreML #OnDevice #Privacy

---

## 30–60s video script

[0:00–0:06] On screen: a normal desktop, browsing. VO: "This watches your screen and remembers what you saw — without ever saving a screenshot."

[0:06–0:16] Cut to the visualizer panel 1 (memory wipe). VO: "Every frame is embedded on the Neural Engine in [ANE_MEDIAN] milliseconds, then the pixels are wiped from memory. Only a math vector and the OCR text survive."

[0:16–0:26] Panel 2, the concept map filling up. VO: "As I browse, each moment becomes a dot — 512 numbers, no image. I can ask, in plain English, 'when was I looking at a code editor?' and it finds it." Show `query.py` output.

[0:26–0:36] Terminal: the `fs_usage` proof. VO: "And I proved no frame is written — the biggest thing it ever saves to disk is [N] times smaller than one screenshot."

[0:36–0:50] Panel 3, the failed reconstruction. VO: "Then I attacked it. I trained a decoder to rebuild images from the vectors — here's what it gets. After the defense, SSIM collapses from [SSIM_BEFORE] to [SSIM_AFTER], but search still works at [RETRIEVAL_AFTER]."

[0:50–0:60] Title card: "Zero-Retention Context Engine — privacy you can measure." VO: "On-device. Apple Silicon. Adversarially verified."

---

## Talking points for the interview (defend the numbers)

- Why these are credible: every number is measured on labeled hardware (Phase 0 M1, capture/retrieval/red-team on the M5), `predict()` wall-clock is called out as an upper bound on compute, and the export is checked against PyTorch (cosine [IMAGE_COSINE]).
- The honest caveat on noise defenses: additive Gaussian noise on L2-normalized embeddings only injects σ-scale noise into the cosine score, so it tends to trade leakage and retrieval together; the eval reports which defense (if any) actually separates them.
- What I'd do next: on-device Swift query path (reuse the Core ML text encoder), and an (ε,δ)-DP accounting under a bounded-sensitivity release model rather than the indicative ε.
