# Spec 10 — Dictionary (custom vocabulary)

**Goal:** Personal terms (names, jargon, product words) transcribe correctly.

**Storage:** `dictionary(id, phrase UNIQUE, created_at)` in the existing SQLite db (`HistoryStore`).

**UI** (`DictionaryView.swift`): title + "Add new" (stays focused for batch adding), search, hover edit/delete rows, explainer text.

**Bias mechanism:** all phrases are joined into `whisper_full`'s `initial_prompt` ("Glossary: a, b, c.") on every dictation, capped ~700 chars (prompt window ≈224 tokens). Empty dictionary → nil prompt (no regression). Wired identically in the app (`AppState.refreshDictionary` → `Transcriber.glossary`) and the `--transcribe` CLI.

**Measured A/B** (2026-07-08, synthesized German audio):
- without: "die Gotar-Unterlagen für die Kian-W-Resentation"
- with: "die Gothaer-Unterlagen für die kyan-webpresenta-tion"

**Limits/known behavior:** biases the first 30 s window (fine for dictation); >~60 terms get truncated (oldest-alphabetical first) — revisit with per-language glossaries if it ever matters.

**Future (logged, not planned):** auto-learning from user corrections — would require observing edits in other apps; privacy-invasive, out of character for this tool.

**Done when:** adding a term makes a previously-garbled dictation of it come out right (A/B above), and entries survive restart.
