# WisprOwn

Hold **Left Option**, speak, release — your words are transcribed locally and pasted
wherever your cursor is. Every transcript is also saved to a local history window,
so a failed paste never loses a dictation.

- **Private:** audio never leaves your Mac. Transcription runs locally via
  [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (`large-v3-turbo`).
- **Multilingual:** English, German, and Spanish, auto-detected per dictation.
- **Safety net:** menu bar → History shows your last 20 transcripts with one-click copy.

## Requirements

- Apple Silicon Mac (M1 or newer), macOS 14+
- Xcode 15+ command line tools (`xcode-select --install`)
- ~2 GB free disk (the Whisper model downloads on first launch)

## Install

```sh
git clone <this-repo>
cd wispr-own
make app
open dist/WisprOwn.app   # if blocked: right-click the app in Finder > Open
```

### First launch, step by step

1. **Microphone** — macOS asks automatically. Click **Allow**.
2. **Accessibility** — a prompt points you to
   *System Settings → Privacy & Security → Accessibility*. Enable **WisprOwn**,
   then quit and reopen the app (macOS only applies this grant on restart).
3. **Model download** — the menu bar icon shows progress (~1.75 GB total, one time:
   the main model plus a small language-detection model).
4. When the icon becomes a plain microphone, you're ready: focus any text field,
   **hold Left Option**, speak, release.

## Usage notes

- Taps shorter than 300 ms are ignored; pressing any other key while holding
  Option cancels the dictation — so Option-accents (ñ, ü, €) still work normally.
- Your previous clipboard is restored about a second after each paste.
- **History:** menu bar icon → *History…* — last 20 transcripts, click to copy.
- All data lives in `~/Library/Application Support/WisprOwn/`
  (model + `history.sqlite`). Delete that folder to reset everything.

## Development

```sh
make run                      # run from source (terminal shows debug logs)
swift build                   # compile only
.build/debug/WisprOwn --transcribe test.wav   # headless pipeline check
```

Project specs live in `specs/` — one file per component, plus the evaluation
gates in `specs/08-evaluation.md`.
