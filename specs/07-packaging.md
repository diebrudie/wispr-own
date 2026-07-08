# Spec 07 — Packaging & Sharing

**Goal:** A GitHub repo your wife can clone and get running on her Mac without hand-holding.

**Deliverables**
- Repo: Xcode project (or SwiftPM executable + xcodegen), `specs/`, README.
- README covers: what it is, requirements (Apple Silicon, macOS version), build steps (`xcodebuild` or open-in-Xcode), first-run flow (model download, Microphone + Accessibility permission prompts and where to grant them), the Left Option hold gesture, where history lives.
- Model file and `history.sqlite` are never committed (`.gitignore`).
- **Local signing identity** (added 2026-07-08): `Scripts/make-signing-cert.sh` creates a self-signed "WisprOwn Dev" cert in the login keychain (`security import -A` so codesign never prompts), trusted for code signing. `make-app.sh` auto-detects it. Rationale: ad-hoc signing (`-`) changes the app's identity every build, so macOS revokes its TCC grants (Accessibility/Microphone) each rebuild. Verified 2026-07-08: with the cert, a rebuild+relaunch reaches `app: ready` with no permission prompt.
  - Gotcha: `openssl pkcs12` bundles fail macOS `security import` ("MAC verification failed") — import key and cert as separate PEMs.
- Gatekeeper right-click-open dance still applies (self-signed ≠ notarized). Notarization + Developer ID deferred until the repo goes public.

**First-run experience (part of this spec)**
- On launch without permissions: menu bar error state with a menu item deep-linking to the right System Settings pane.
- On launch without model: prompt + download with progress, then ready state.

**Done when:** a fresh macOS user account (or wife's Mac) goes from `git clone` to a working dictation in under ~10 minutes following only the README.
