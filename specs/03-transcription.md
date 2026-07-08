# Spec 03 — Transcription

**Goal:** Turn the PCM buffer into text, locally, in EN/DE/ES with auto-detection.

**Behavior**
- Input: 16 kHz mono Float32 buffer. Output: `(text, detectedLanguage, durationMs)`.
- Language: Whisper auto-detect (no manual switch in v1).
- Empty/silent recordings produce empty text → skip paste and history, show nothing.
- Target latency on Apple Silicon: ≤ 2–3 s for a 30 s dictation.

**Implementation notes**
- whisper.cpp prebuilt XCFramework (v1.9.1 release asset; upstream dropped SPM support), vendored by `Scripts/fetch-whisper.sh` with pinned SHA-256. Metal + flash attention enabled.
- **Two-model design** (added 2026-07-08): language auto-detection runs on `ggml-base` (~150 MB, ~0.2 s) and the detected language is passed to `large-v3-turbo` explicitly. Rationale: an encoder pass on the big model costs ~2.7 s on an M3; letting it self-detect doubles that. Measured: 5.2 s → 3.0 s warm for a 5 s clip.
- Models: `ggml-large-v3-turbo` (~1.6 GB) + `ggml-base` (~150 MB). Not committed to git — downloaded on first launch from Hugging Face to `~/Library/Application Support/WisprOwn/models/`, progress in the menu bar. Checksums are trust-on-first-use: pinned after first download, verified on later launches.
- Known gap vs gate G3: warm latency is ~3 s for short clips (encoder-bound), above the ≤1.5 s target. Options recorded: CoreML encoder build (~3-5× encoder speedup, requires custom framework build) or amending the gate.
- Load the model once at app start (or first use) and keep it resident; per-dictation model loading would dominate latency.
- Run transcription off the main thread; UI shows "transcribing" state meanwhile.

**Done when:** dictating the same sentence in English, German, and Spanish each yields correct text with correct detected language.
