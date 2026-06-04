# RUNBOOK — Zero-Retention Context Engine

Everything you need to work on this project from a wiped lab Mac. Open this at the start of every session and follow Section B. Replace every `PLACEHOLDER_...` with your real value the first time.

## Contents
- A. First-time setup (do ONCE, ever)
- B. Every session (repeat EVERY time)
- C. If you run out of tokens mid-session
- D. Git command reference
- E. File map: what each file is and where it lives

---

## A. First-time setup (do this ONCE)

This creates the GitHub repo and uploads the project. After this the repo lives on GitHub permanently; you never do Section A again.

1. Put all project files into one folder named `zero-retention-context-engine` (full layout in Section E).
2. Open Terminal and `cd` into that folder.
3. Check the tools exist (lab Macs usually have them; install only what is missing):
   - `git --version`
   - `python3 --version`
   - `swift --version`   (if missing: `xcode-select --install`)
   - `gh --version`      (if missing and Homebrew is present: `brew install gh`)
4. Authenticate to GitHub:
   - `gh auth login`
   - choose: GitHub.com → HTTPS → "Login with a web browser"
   - copy the one-time code, press Enter, authorize in the browser
   - `gh auth setup-git`   (lets git push over HTTPS using gh)
5. Set your git identity for this repo:
   - `git config user.name "PLACEHOLDER_YOUR_NAME"`
   - `git config user.email "PLACEHOLDER_YOUR_EMAIL"`
6. Initialize and make the first commit:
   - `git init`
   - `git branch -M main`
   - `git add -A`
   - `git commit -m "Initial scaffold: Phase 0 + project docs"`
7. Create the GitHub repo (private) and push:
   - `gh repo create zero-retention-context-engine --private --source=. --push`
8. Confirm it worked:
   - `gh repo view --web`  (opens the repo in your browser; you should see your files)

Done. Never run Section A again.

---

## B. Every session (repeat this EVERY time)

1. Open Terminal.
2. Clone your repo (the machine was wiped, so it is not here):
   - `git clone https://github.com/PLACEHOLDER_YOUR_USERNAME/zero-retention-context-engine.git`
   - `cd zero-retention-context-engine`
3. Authenticate to GitHub again (credentials were wiped):
   - `gh auth login`   (same browser flow as Section A)
   - `gh auth setup-git`
4. Set git identity again (wiped):
   - `git config user.name "PLACEHOLDER_YOUR_NAME"`
   - `git config user.email "PLACEHOLDER_YOUR_EMAIL"`
5. Rebuild the local environment in one command:
   - `bash setup.sh`
   - For Phase 0 only: download the MobileCLIP-S2 checkpoint into `checkpoints/` (see github.com/apple/ml-mobileclip), then run the two commands setup.sh prints (export + benchmark). After Phase 0 the model load is wired into the engine.
6. If macOS prompts for Screen Recording permission, grant it in System Settings → Privacy & Security → Screen Recording, then re-run.
7. Launch Claude Code in the folder and paste the session prompt:
   - First session ever:
     `Read CLAUDE.md and BUILD_PROMPT.md, then begin Phase 0. Follow the iterative protocol: one phase, then stop and wait for my go.`
   - Every later session:
     `Read CLAUDE.md, BUILD_PROMPT.md, and PROGRESS.md, then continue from the next unfinished phase. Follow the iterative protocol: one phase, then stop and wait for my go.`
8. Work through the phase. After every meaningful step, save your progress:
   - `git add -A && git commit -m "describe what changed" && git push`
9. BEFORE YOU LOG OUT — always:
   - `git add -A && git commit -m "end of session checkpoint" && git push`
   - `git log origin/main --oneline -1`   (confirm your last commit is on GitHub; or check github.com)
   - only now log out.

---

## C. If you run out of tokens mid-session

Claude Code stops responding, but your work is still on the local disk, which the lab wipes on logout. Rescue it yourself — you do not need Claude:

1. In the Terminal (or a new one, `cd` into the folder):
   - `git add -A`
   - `git commit -m "wip: stopping mid-phase, out of tokens"`
   - `git push`
2. Confirm: `git log origin/main --oneline -1` shows your commit (or check github.com).
3. Log out safely.

Next time, do Section B. At step 7 Claude Code reads PROGRESS.md and resumes where you stopped. If a phase was only half done, tell it:
`We stopped partway through Phase N. Read PROGRESS.md and the latest commits, then continue.`

---

## D. Git command reference (the only commands you need)

- `git clone <url>` — download your repo to this machine.
- `git status` — see what changed.
- `git add -A` — stage all changes.
- `git commit -m "message"` — save a snapshot locally.
- `git push` — upload commits to GitHub. THIS is what survives the wipe.
- `git pull` — download commits made elsewhere (rarely needed if you only use the lab).
- `git log --oneline -5` — recent commits.
- `git log origin/main --oneline -1` — confirm what is actually on GitHub.

Rule of thumb: commit often, and push before you ever stand up from the machine.

---

## E. File map — what each file is and where it lives

Folder name: `zero-retention-context-engine/`

Repo root:
- `CLAUDE.md` — Claude Code reads this automatically every session. Project rules + pointer to PROGRESS.md.
- `BUILD_PROMPT.md` — the full phase-by-phase build plan. Claude Code reads it when you tell it to.
- `RUNBOOK.md` — this file. Your step-by-step playbook.
- `README.md` — public-facing overview, numbers-first results tables.
- `PROGRESS.md` — current state (done / next / issues). Claude Code keeps it updated; this is how you resume.
- `RESUME_BULLETS.md` — interview-defensible bullets with real numbers. Claude Code creates and updates it.
- `requirements.txt` — Python dependencies.
- `setup.sh` — one-command local environment rebuild.
- `.gitignore` — keeps regenerable artifacts and personal data OUT of the repo.

`scripts/` folder:
- `scripts/export_coreml.py` — converts MobileCLIP to Core ML.
- `scripts/bench_coreml.py` — benchmarks embedding latency and model size.

Created locally as you build, and NEVER committed (the .gitignore handles this):
- `.venv/` — Python virtual environment.
- `checkpoints/` — downloaded MobileCLIP weights.
- `MobileCLIPImage.mlpackage` — the exported Core ML model.
- `vectorstore/` and any `captures/` — embeddings of your real screen content. Stays local for privacy; regenerable.
- `.build/` — the Swift package build folder.

Files that do not exist yet and that Claude Code creates as phases progress: the Swift package (`Package.swift` + `Sources/`), `RESUME_BULLETS.md`, the `DEMO.md`, and the visualizer.
