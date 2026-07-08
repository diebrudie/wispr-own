# Spec 07 — Packaging & Sharing

**Goal:** A GitHub repo your wife can clone and get running on her Mac without hand-holding.

**Deliverables**
- Repo: Xcode project (or SwiftPM executable + xcodegen), `specs/`, README.
- README covers: what it is, requirements (Apple Silicon, macOS version), build steps (`xcodebuild` or open-in-Xcode), first-run flow (model download, Microphone + Accessibility permission prompts and where to grant them), the Left Option hold gesture, where history lives.
- Model file and `history.sqlite` are never committed (`.gitignore`).
- Unsigned/ad-hoc-signed build is acceptable for v1 (Gatekeeper right-click-open dance documented). Notarization deferred.

**First-run experience (part of this spec)**
- On launch without permissions: menu bar error state with a menu item deep-linking to the right System Settings pane.
- On launch without model: prompt + download with progress, then ready state.

**Done when:** a fresh macOS user account (or wife's Mac) goes from `git clone` to a working dictation in under ~10 minutes following only the README.
