# Zero-Retention Context Engine

Flagship portfolio project for an Apple internship application (AIML and Software Engineering tracks). It must survive a senior Apple ML engineer's scrutiny in a technical interview.

## Cardinal rule
Every performance number must be genuinely measured on this machine. Never fabricate, estimate, extrapolate, or round up a metric. If a number cannot be measured yet, write "TBD" and state why. A wrong-but-impressive number is a failure; a modest-but-real number is a success.

## Where we are
- Current state, completed phases, and known issues: read `PROGRESS.md`.
- Full phase-by-phase build plan: read `BUILD_PROMPT.md`.
- At the start of a session, read both before doing anything else, then continue from the phase the user names.

## Workflow rules
- Build ONE phase at a time. Do not skip ahead.
- At the end of each phase: run the verification steps, update `README.md`, `RESUME_BULLETS.md`, and `PROGRESS.md` with real measured results, commit, then STOP and summarize for the user and wait for "go".
- Commit and push after every meaningful step, not only at end of phase. This is a wiped lab machine; uncommitted work is lost on logout, and your own auto memory does not persist here. `CLAUDE.md` plus `PROGRESS.md` in the repo are the only durable memory.
- Before ending a session, remind the user to commit and push.

## Tech stack and constraints
- Apple Silicon, macOS 14+.
- Core engine: Swift, Swift Package Manager executable target. Build with `swift build`, run with `swift run`.
- Capture: ScreenCaptureKit (needs Screen Recording permission).
- Image embedding: Apple MobileCLIP exported to Core ML (.mlpackage), running on the Neural Engine.
- OCR: Apple Vision framework, on-device.
- ML red-team and analysis: Python (torch, coremltools, numpy).
- Vector store: SQLite or append-only file with brute-force cosine similarity. No heavyweight vector database.

## Privacy invariant
Raw frames (CMSampleBuffer / pixel buffers) must never be written to disk and must be released or overwritten in memory immediately after embedding. Only vectors, OCR text, and timestamps persist. This must be provable.

## Coding standards
- Complete, runnable files. No inline code comments anywhere; use clear names and put explanation in commit messages and README prose.
- Clearly flag placeholder values for anything not provided.
- Communicate directly. If the user suggests something wrong, slow, or that won't survive interview scrutiny, push back and explain rather than agreeing.

## Never commit
The venv, model checkpoints, the .mlpackage, build artifacts, the vector store, and any captured data. The vector store contains embeddings of real screen content and is regenerable, so it stays local.
