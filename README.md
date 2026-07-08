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
charge monthly for it. WisprOwn is the *owned* alternative: OpenAI's Whisper
running entirely on your Mac's Neural Engine, wrapped in a native Swift app.
Your audio is processed in memory and never written to disk or sent anywhere.

## Features

|     | Feature | Detail |
|-----|---------|--------|
| 🎙️ | **Push-to-talk** | Hold **Left Option**, speak, release — text pastes at your cursor |
| 🔒 | **100 % local** | whisper.cpp + CoreML on the Neural Engine; zero network calls after setup |
| 🌍 | **Multilingual** | English, German, Spanish and 13 more — auto-detected per dictation |
| ⚡ | **Fast** | ~1 s from key-release to paste on Apple Silicon (measured on an M3) |
| 🧾 | **Nothing gets lost** | Every transcript is saved to a local SQLite history *before* pasting |
| 🖥️ | **Hub window** | Stats (words, WPM, streak), searchable history, copy / edit / delete any transcript |
| 📖 | **Dictionary** | Add your names & jargon — they bias the transcriber and come out spelled right |
| 〰️ | **Live bar** | A floating pill at the bottom of the screen shows a real waveform while you speak |
| 🎛️ | **Configurable** | Hotkey, microphone, languages, light/dark theme — all in Settings |
| 📋 | **Clipboard-safe** | Whatever you had copied is restored ~1 s after each paste |

---

## Install

### Requirements

- **Apple Silicon Mac** (M1 or newer) — Intel is not supported
- **macOS 14** (Sonoma) or newer
- **Xcode command line tools** — install with `xcode-select --install`
- **~4 GB free disk** — the speech models are downloaded on first launch

### Steps

```sh
# 1. Get the code
git clone https://github.com/diebrudie/wispr-own.git
cd wispr-own

# 2. One-time: create a local signing certificate (see note below)
./Scripts/make-signing-cert.sh

# 3. Build the app (~1 min: downloads the whisper framework, compiles, signs)
make app

# 4. Launch it
open dist/WisprOwn.app
```

> #### ⚠️ Don't skip step 2
> It creates a self-signed certificate in *your* keychain so that every rebuild
> keeps its Microphone and Accessibility permissions. Skip it and macOS treats
> each rebuild as a brand-new app, forcing you to re-grant access every single
> time. The key never leaves your machine and only signs your own local builds.
>
> If macOS asks for a password, it's your **Mac login password**. If a
> `codesign wants to access key` dialog appears, click **Always Allow**.

> #### 🔑 No accounts, no API keys
> Everything runs on-device. The only network activity is the one-time model
> download from Hugging Face (public files, no authentication) — after that the
> app works fully offline, even in airplane mode.

### First launch — what to expect

1. **Gatekeeper may block the app** (it's self-signed, not notarized).
   Right-click `dist/WisprOwn.app` in Finder → **Open** → **Open**. Once only.
2. **Allow Microphone** when macOS asks.
3. **Grant Accessibility** — the app shows an error state with a link, or go to
   *System Settings → Privacy & Security → Accessibility*, click **+**, add
   `dist/WisprOwn.app`, and switch it on. *(This is what lets the app see your
   hotkey and paste for you.)* The app picks up the grant within 2 seconds.
4. **Wait for the models** (~2.8 GB, one time). The menu bar icon shows download
   progress, then **about a minute** of one-time CoreML compilation for the
   Neural Engine. This only ever happens once — later launches take seconds.
5. When the icon becomes a plain microphone you're ready: click into any text
   field, **hold Left Option**, speak, release.

---

## Using it

- **Hold Left Option, speak, release.** Taps shorter than 300 ms are ignored, so
  you'll never record by accident.
- **Option-key accents still work** (ñ, ü, €…) — pressing any other key while
  holding Option cancels the dictation and types the character normally.
- **The bar at the bottom of your screen** rests as a slim pill, becomes a live
  waveform while you speak, and pulses while transcribing. Toggle it off in
  *Settings → System*.
- **The hub window** — click the Dock icon (or the menu bar mic → *Open
  WisprOwn…*). Hover any transcript for **copy** and a **⋯ menu** with *Edit
  Transcript* and *Delete Transcript*. Editing is your fix-and-copy safety net
  if a paste ever misfires.
- **Dictionary** — add names, companies, product terms. They're fed to the
  transcriber as context so `Gothaer` stops coming out as `Gotar`.
- **Settings** — the gear at the bottom of the hub window's sidebar (or ⌘,).
  Change the push-to-talk key, pick a microphone, enable more dictation
  languages, switch light/dark, or set the name used to greet you.
- **Menu bar mic** shows live state: mic = ready · waveform = recording ·
  ellipsis = transcribing · slashed mic = permissions needed.

All your data lives in `~/Library/Application Support/WisprOwn/` (models +
`history.sqlite`). Delete that folder to reset the app completely.

---

## How it works

```
 Hold ⌥ ──▶ CGEventTap ──▶ AVAudioEngine ──▶ 16 kHz PCM buffer (in memory)
                                                    │ release ⌥
                                                    ▼
                              ggml-base (fast language detect, ~0.15 s)
                                                    ▼
                       whisper large-v3-turbo (CoreML encoder on ANE, ~0.7 s)
                                                    ▼
                    SQLite history (saved first — zero-loss) ──▶ ⌘V paste
                                                    ▼
                                    previous clipboard restored
```

Two models are used on purpose: a tiny one detects the language in ~0.15 s, then
the big one transcribes with that language fixed. Letting the big model
auto-detect costs a second encoder pass and doubles the latency.

---

## Troubleshooting

| Symptom | What's happening |
|---------|------------------|
| **App seems dead for ~1 minute on first launch** | macOS is compiling the CoreML model for the Neural Engine — one time per machine. The menu bar icon shows "Loading model…". Just wait. |
| **"Nothing opened" after `open dist/WisprOwn.app`** | It did open — there's no main window by default. Look for the violet mic in the Dock (click it) and the mic in the menu bar. |
| **No menu bar icon** | A crowded menu bar (especially beside a MacBook notch) hides new items. Remove some icons — or just use the Dock icon; WisprOwn also appears in ⌘Tab. |
| **Hotkey does nothing** | Accessibility isn't granted. Check the menu bar icon: a slashed mic means permissions. Remove and re-add the app under *Privacy & Security → Accessibility*. |
| **Hotkey stopped working after a rebuild** | You skipped `make-signing-cert.sh`. Re-add the app under Accessibility, then run that script so it never happens again. |
| **`codesign wants to access key "key"`** | Enter your **Mac login password** and click **Always Allow** (not plain *Allow*), so it won't ask on later builds. |
| **Gatekeeper refuses to open the app** | Self-signed, not notarized. Right-click the app in Finder → **Open**. Needed once. |
| **Dictation pastes nothing** | Open the hub window. If the text is there, the target app rejected the synthetic ⌘V — copy it from the history. If it isn't, the recording was silent or under ~200 ms. |
| **A name is always misspelled** | Add it in **Dictionary**. It biases the transcriber from the next dictation on. |

---

## Development

```sh
make run        # run from source, live logs in the terminal
make build      # compile only
make reload     # rebuild the .app, kill the running instance, relaunch
make clean      # remove build artifacts

# headless checks (no UI)
.build/debug/WisprOwn --transcribe some-audio.wav   # transcribe a file, print text + timing
.build/debug/WisprOwn --devices                     # list microphones
.build/debug/WisprOwn --stats                       # print history stats
```

Reading the app's logs (note the full path — zsh shadows `log` with a builtin):

```sh
/usr/bin/log show --process WisprOwn --last 5m --style compact | grep -E 'app:|hotkey:|whisper:'
```

The project is spec-driven: every component has a one-page spec in
[`specs/`](specs/), including the [decision record](specs/00-decisions.md) and
the [measurable quality gates](specs/08-evaluation.md) the app is tested against.

| Spec | Component |
|------|-----------|
| [01](specs/01-hotkey-listener.md) | Hotkey state machine (hold / cancel / ignore) |
| [02](specs/02-audio-capture.md) | Microphone capture |
| [03](specs/03-transcription.md) | Whisper + CoreML two-model pipeline |
| [04](specs/04-paste.md) | Paste + clipboard restore |
| [05](specs/05-history-store.md) | Zero-loss SQLite history |
| [06](specs/06-menubar-and-history-ui.md) | Menu bar + status states |
| [07](specs/07-packaging.md) | Bundling, signing & distribution |
| [08](specs/08-evaluation.md) | Quality gates |
| [09](specs/09-main-window.md) | Hub window (Home, Settings) |
| [10](specs/10-dictionary.md) | Dictionary / custom vocabulary |
| [11](specs/11-flow-bar.md) | The floating WisprOwn bar |
| [12](specs/12-future-features.md) | Backlog & future ideas |

---

## Roadmap

- [x] Configurable hotkey, history search, custom dictionary — v0.3
- [x] Hub window, light/dark theme, live waveform bar — v0.4
- [ ] Interactive bar: hover to show `Dictate ⌥` and a click-to-record button
- [ ] Streaming transcription (encode while speaking → near-instant paste)
- [ ] Insights page (usage charts, streak heatmap)
- [ ] UI localization (DE/ES)
- [ ] Notarized release so no right-click-to-open is needed

See [`specs/12-future-features.md`](specs/12-future-features.md) for details.

## License

[MIT](LICENSE) — do whatever you like, no warranty.
