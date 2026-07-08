<div align="center">

# 🎙️ WisprOwn

**Hold a key. Speak. Release. Your words appear where your cursor is.**

Private, local, multilingual push-to-talk dictation for macOS —
no cloud, no subscription, no audio ever leaving your Mac.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%E2%80%93M4-blueviolet)
![Swift](https://img.shields.io/badge/Swift-5.10-F05138?logo=swift&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

*Work in progress — functional, rough edges, built in the open.*

</div>

---

## Why

Tools like Wispr Flow are excellent — but they send your voice to the cloud and
charge monthly for it. WisprOwn is the ~owned~ alternative: OpenAI's Whisper
running entirely on your Mac's Neural Engine, wrapped in a native Swift app.
Your audio is processed in memory and never written to disk or network.

## Features

|     | Feature | Detail |
|-----|---------|--------|
| 🎙️ | **Push-to-talk** | Hold **Left Option**, speak, release — text pastes at your cursor |
| 🔒 | **100% local** | whisper.cpp + CoreML on the Neural Engine; zero network calls after setup |
| 🌍 | **Multilingual** | English, German, Spanish — auto-detected per dictation |
| ⚡ | **Fast** | ~1 s from key-release to paste on Apple Silicon (M3 measured) |
| 🧾 | **Nothing gets lost** | Every transcript is saved to a local SQLite history *before* pasting |
| 🖥️ | **Hub window** | Click the Dock icon — stats (words, WPM, streak), searchable history, one-click copy |
| 📖 | **Dictionary** | Add your names & jargon — they bias the transcriber and come out spelled right |
| 🎛️ | **Configurable** | Push-to-talk key, microphone, and dictation languages — all in Settings |
| 📋 | **Clipboard-safe** | Whatever you had copied is restored ~1 s after each paste |

## Install

> **Requirements:** Apple Silicon Mac (M1+), macOS 14+, Xcode command line tools
> (`xcode-select --install`), ~3 GB free disk for the speech models.

```sh
git clone git@github.com:diebrudie/wispr-own.git   # or: gh repo clone diebrudie/wispr-own
cd wispr-own
./Scripts/make-signing-cert.sh   # one-time: stable signing identity (enter your login password)
make app
open dist/WisprOwn.app           # if Gatekeeper complains: right-click the app → Open
```

> **Don't skip the first command.** It creates a local self-signed certificate so
> every future rebuild keeps its Microphone and Accessibility permissions. Without
> it, macOS treats each rebuild as a brand-new app and you must re-grant access
> every single time. Later, use `make reload` to rebuild and relaunch in one step.

> **No accounts, no API keys.** Everything runs on-device. The only network
> activity is the one-time model download from Hugging Face (public files,
> no authentication) — after that the app works fully offline.

### First launch

1. **Allow Microphone** when macOS asks.
2. **Grant Accessibility**: System Settings → Privacy & Security → Accessibility →
   add `dist/WisprOwn.app` and toggle it on. *(This lets the app see the hotkey
   and paste for you.)*
3. Wait for the **models to download** (~2.9 GB, one time — Dock/menu bar icon
   shows progress) plus **~1 minute** of one-time CoreML compilation on the very
   first model load.
4. Icon shows a plain mic → click into any text field, **hold Left Option**,
   speak, release.

## Usage

- **Taps shorter than 300 ms are ignored** — no accidental recordings.
- **Option-key accents still work** (ñ, ü, €…): pressing any other key while
  holding Option cancels the dictation and types normally.
- **History**: click the Dock icon (or menu bar mic → History…). Click 📄 on any
  row to copy it — your safety net if a paste ever misfires.
- **Menu bar mic** shows live state: mic = ready, waveform = recording,
  ellipsis = transcribing, slashed = permissions needed.

## How it works

```
 Hold ⌥ ──▶ CGEventTap ──▶ AVAudioEngine ──▶ 16 kHz PCM buffer (in memory)
                                                    │ release ⌥
                                                    ▼
                              ggml-base (Neural lang detect, ~0.15 s)
                                                    ▼
                       whisper large-v3-turbo (CoreML encoder on ANE, ~0.7 s)
                                                    ▼
                    SQLite history (saved first — zero-loss) ──▶ ⌘V paste
                                                    ▼
                                    previous clipboard restored
```

All data lives in `~/Library/Application Support/WisprOwn/` — delete that
folder to reset the app completely.

## Troubleshooting

| Symptom | Explanation |
|---------|-------------|
| **App seems dead for ~1 minute after first launch** | macOS is compiling the CoreML model for the Neural Engine — one time per machine. The status icon shows "Loading model…"; just wait. |
| **No menu bar icon** | A crowded menu bar (especially next to a MacBook notch) hides new items. Remove some icons, or just use the Dock icon — WisprOwn also appears in ⌘Tab. |
| **"Nothing opened" after `open dist/WisprOwn.app`** | It did — there's no main window. Look for the mic in the menu bar and the violet icon in the Dock (click it for History). |
| **Hotkey stopped working after rebuilding** | You skipped `make-signing-cert.sh`, so the rebuild changed the app's identity and macOS dropped the Accessibility grant. Remove and re-add WisprOwn under System Settings → Privacy & Security → Accessibility, then create the cert so it never happens again. |
| **`codesign wants to access key "key"` prompt** | Enter your **Mac login password** and click **Always Allow** (not plain Allow) — it won't ask again. |
| **Gatekeeper refuses to open the app** | The build is self-signed, not notarized. Right-click the app in Finder → Open (needed once). |
| **Dictation pastes nothing** | Check the History window — if the text is there, the target field rejected synthetic ⌘V; copy it manually. If it's not there, the recording was empty/too short. |

## Development

```sh
make run                                       # run from source with live logs
swift build                                    # compile only
.build/debug/WisprOwn --transcribe test.wav    # headless pipeline check
```

The project is spec-driven: every component has a one-page spec in
[`specs/`](specs/), including the [decision record](specs/00-decisions.md) and
[measurable quality gates](specs/08-evaluation.md) the app is tested against.

| Spec | Component |
|------|-----------|
| [01](specs/01-hotkey-listener.md) | Hotkey state machine (hold / cancel / ignore) |
| [02](specs/02-audio-capture.md) | Microphone capture |
| [03](specs/03-transcription.md) | Whisper + CoreML two-model pipeline |
| [04](specs/04-paste.md) | Paste + clipboard restore |
| [05](specs/05-history-store.md) | Zero-loss SQLite history |
| [06](specs/06-menubar-and-history-ui.md) | Menu bar + history window |
| [07](specs/07-packaging.md) | Bundling & distribution |
| [09](specs/09-main-window.md) | Main hub window (Home, Settings overlay) |
| [10](specs/10-dictionary.md) | Dictionary / custom vocabulary |

## Roadmap

- [x] Configurable hotkey in the UI (Fn/Globe support) — v0.3
- [x] Search in history — v0.3
- [x] Custom vocabulary (Dictionary) — v0.3
- [ ] Streaming transcription (encode while speaking → near-instant paste)
- [ ] Insights page (usage charts, streak heatmap)
- [ ] UI localization (DE/ES)
- [ ] Dictionary auto-suggestions

## License

[MIT](LICENSE) — do whatever you like, no warranty.
