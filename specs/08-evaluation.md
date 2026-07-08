# Spec 08 — Evaluation Criteria (v1 quality gates)

v1 is "done" only when every gate below passes. Each gate states its measurement procedure — no gate is judged by impression.

## G1. Hotkey correctness (Spec 01)
- **False-positive rate:** 30 minutes of normal work (typing, shortcuts, app switching) that includes typing ≥20 Option-accent characters (ñ, ü, ö, ä, ´, €) → **0** unintended recordings started.
- **False-negative rate:** 20 deliberate hold-to-talk attempts → **20/20** start recording.
- **Guard behavior:** Option+letter accents produce the correct character every time; a <300 ms tap never records.
- **Responsiveness:** recording starts ≤50 ms after the 300 ms arm point; stop is registered ≤50 ms after release (verified via debug timestamps).

## G2. Audio integrity (Spec 02)
- Recorded buffer duration within ±100 ms of actual hold duration (measure 10 holds of 2 s / 10 s / 60 s).
- Debug-WAV listening check: no clipping, gaps, or wrong-device capture.
- 5-minute cap triggers cleanly: auto-stop, normal transcription, no crash.
- Mic is only open while the key is held: macOS orange mic indicator is **off** at idle (privacy gate).

## G3. Transcription quality (Spec 03)
- **Fixed test set:** 5 sentences × 3 languages (EN/DE/ES), each containing at least one proper noun and one number, read at normal pace in a quiet room. Stored in `specs/eval-sentences.md` so runs are comparable over time.
- **Accuracy:** ≥95% words correct per language (count errors by hand against the script).
- **Language detection:** 15/15 correct.
- **Code-switching sanity:** one German sentence with an English product name transcribes without garbling (qualitative pass/fail).
- **Latency:** on this M-series Mac, a 30 s dictation transcribes in ≤3 s; a 5 s dictation in ≤1.5 s (p50 of 5 runs, measured by the `transcribe_ms` column).

## G4. End-to-end latency (integration)
- Key-release → text visible in target app: **≤2 s p50, ≤4 s p95** for a 10 s dictation, measured over 20 real dictations using `transcribe_ms` + debug timestamps.

## G5. Paste correctness (Spec 04)
- Text lands at the cursor in **all** of: TextEdit, Apple Notes, Slack, Chrome (Gmail compose), Cursor/VS Code, Terminal. 3/3 attempts each.
- Clipboard restore: with (a) text, (b) an image, (c) a copied file on the clipboard → original content intact after paste, 10/10 runs.
- Paste into a non-editable context (Finder desktop): no crash, no stray keystrokes, transcript still lands in history.

## G6. Safety-net integrity (Spec 05) — the core promise
- **Zero-loss rule:** every non-empty dictation exists as a history row, even when paste fails — verified by dictating 5× onto a read-only target and checking `sqlite3` output.
- Row is committed before the paste attempt (code inspection + a forced-crash test between insert and paste).
- DB opens clean after `kill -9` during active use (WAL mode; check with `PRAGMA integrity_check`).
- All schema fields populated correctly on 10 sampled rows (timestamp offset, language, durations, target app bundle id).

## G7. UI truthfulness (Spec 06)
- Icon reflects actual state within 100 ms: idle/recording/transcribing/error each visually distinct and verified against real state transitions.
- History window: opens in <500 ms, shows exactly the 20 newest rows in order, timestamps match DB, copy button → paste elsewhere reproduces the full text (not the truncated preview), "Copied" feedback appears.

## G8. Resource & privacy footprint
- Idle CPU <1%; recording CPU spike acceptable, returns to idle after transcription.
- Memory: ~2 GB resident with model loaded — accepted and documented; no growth over 50 consecutive dictations (leak check via Activity Monitor before/after).
- **Zero network traffic** after the one-time model download, verified with `nettop -p WisprOwn` across 10 dictations (privacy is decision #1).

## G9. Permissions & first-run (Spec 07)
- Fresh macOS user account: every missing permission (Microphone, Accessibility) produces the error menu-bar state with a working deep link to the right System Settings pane — never a silent failure.
- Model download shows progress, survives an interrupted connection (resume or clean retry), and verifies checksum.

## G10. Distribution ("wife test")
- A second person on a different Mac goes from `git clone` to a successful dictation in ≤10 minutes using only the README. Every point where she has to ask a question is a README bug — fix and re-run.

## G11. Dogfood gate (final)
- Replace Wispr Flow for **3 consecutive working days**. Log every failure (missed trigger, wrong text, failed paste, crash) in a scratch note.
- Pass: ≥95% of dictations need no fallback to history, zero crashes, zero data loss. Otherwise fix and repeat the 3 days.

## Process rules
- Each spec's own "done when" must pass before its code merges; G1–G11 gate the v1 tag.
- Any gate change requires updating this file first (same explicit-sign-off rule as `00-decisions.md`).
