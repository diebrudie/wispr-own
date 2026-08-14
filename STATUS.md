# WisprOwn — status

Private, local, push-to-talk dictation for macOS (Swift/SwiftUI + whisper.cpp).
An owned alternative to Wispr Flow. Repo: `git@github.com:diebrudie/wispr-own.git` (**private**).

## Current status

v0.5.0 is built and running on Isabel's Mac. Since v0.4.0 it gained: a silence gate
(nothing said → nothing pasted), optional LLM cleanup with a bring-your-own API key
(Anthropic / OpenAI / Grok / custom, off by default), an Insights tab, dictionary
auto-learning from hand-corrected transcripts, a press-to-record hotkey picker, and a
warm-mic pre-roll so the first word isn't clipped.

The stretch from 2026-08-03 to 2026-08-14 was a run of audio-capture bugs, all caused by
that warm mic, and all now fixed. Two rules came out of it: **never hold a Bluetooth mic
open** (it pins the headset profile, and the profile flipping mid-take delivers silent
buffers), re-checked on every rebuild rather than only at startup; and **never trust
`AVAudioEngine.isRunning`** (it reports "running" while delivering nothing) — liveness is
now the timestamp of the last buffer that actually arrived, so a dead warm mic rebuilds
itself on the next key press instead of needing an app restart.

As of 2026-08-14 the app is running clean on AirPods with the Bluetooth guard active. The
self-healing path has not yet been seen firing on a genuinely dead engine in the wild —
that is what the next few days of real use will tell us.

## Open tasks / next steps

- [ ] **← NEXT: use it normally for a few days and confirm it no longer dies after a long idle.** The two lines that matter, either of which means the self-heal worked: `warm mic was not delivering audio, rebuilding it` and `is Bluetooth — releasing the warm mic`. Check with:
      `/usr/bin/log show --predicate 'subsystem == "com.diebrudie.wisprown"' --last 12h --style compact | grep -E 'rebuilding|WARNING|Bluetooth'`
      If a dictation still comes back empty, capture that window — the log now says which of the two failed.
- [ ] Isabel adds her friend as a GitHub collaborator (she wants to do this herself)
- [ ] `Scripts/make-signing-cert.sh` is still unverified on a Mac that has no certificate yet — the friend's install is the real test
- [ ] Backlog, unstarted (`specs/12-future-features.md`): §A interactive bar hover menu, §B streaming / paste latency, §D UI localization DE/ES, §H dictating over playing audio
- [ ] Offered, not built: a manual "restart audio" button (skipped on purpose — the self-heal makes it dead weight, but she floated it and can still have it); idle-release of the warm mic after N minutes; month labels on the activity calendar; date-range picker; CSV export

## Key locations

- **Canonical repo copy:** `/Users/isabelbruda/code/diebrudie/personal/wispr-own` (not the iCloud copy)
- **Built app:** `dist/WisprOwn.app` — rebuild + relaunch with the `/rebuild` skill or `make reload`
- **Specs / backlog:** `specs/12-future-features.md` (A–H), `13-llm-cleanup.md`, `14-insights.md`
- **Audio capture:** `Sources/WisprOwn/AudioRecorder.swift`, `AudioDevices.swift`
- **Whisper + guardrails:** `Sources/WisprOwn/Transcriber.swift` (silence gate, speaker-label strip, glossary prompt)
- **LLM cleanup:** `Sources/WisprOwn/LLMCleanup.swift`; API key lives in the **Keychain**, not UserDefaults
- **Diagnostics:** `TranscribeCLI.swift` — `--selftest`, `--audio-test`, `--llm-test`, `--snapshot`
- **Logs:** `/usr/bin/log show --process WisprOwn --last 5m --style compact` (use `/usr/bin/log`; zsh shadows `log`)
- **Signing identity:** "WisprOwn Dev", created 2026-07-08 — keeps Accessibility/Microphone grants across rebuilds

## Session log

### 2026-08-14 — the warm mic dies after a long idle

Isabel: "WisprOwn stops working suddenly after long periods of resting." Her log had
the failure captured live — three dictations at 12:59 with `hotkey: START`/`STOP` fine
but `captured 0% of the 2.9s you held`, on an app that had been up 22 hours.

Two causes, both fixed in `362de14`:

1. **The Bluetooth guard only ran at startup.** `startContinuous()` checked, but
   `recoverWarmCapture()` did not, so connecting AirPods to a running app (which arrives
   as a configuration change) put the warm mic straight back onto the profile-pinning
   device that `ef604aa` existed to avoid. Now re-checked on every rebuild.
2. **`engine.isRunning` lies.** It reported "running" through all three dead takes.
   Liveness is now the timestamp of the last buffer that actually arrived
   (`warmIsStale`, 1 s timeout, wall clock so it survives sleep); a stale warm mic is
   rebuilt on the next key press. This self-heals whatever the cause — sleep, App Nap,
   device flap, HAL wedge.

Deliberately did **not** add a "restart audio" button she floated: with automatic
recovery it would never be the thing that fixes it. Offered if she still wants one.

Not verified end-to-end: the stale-rebuild path firing on a real dead engine. The
decision function is unit-tested (and proven to fail when reverted), but the wiring
only gets its real test the next time a warm mic actually dies.

### 2026-07-29 → 2026-08-14

Logged four feature ideas as backlog §G/§H and folded the latency item into §B; moved the
recording bar to the physical screen edge.

Then built, in order:

- **Silence gate** — Whisper invents "you" / "thank you" from silence. `no_speech_prob`
  measured 0.000 and was useless, so the gate is an energy floor instead. Nothing said →
  nothing pasted.
- **LLM cleanup (§G)** — optional, off by default, key in Keychain, provider dropdown with
  a fetched model list, no endpoint field. Two bugs fixed along the way: ⌘V was dead
  app-wide because `NSApp.mainMenu` was never set, and a stored full endpoint from an older
  version produced `/v1/messages/messages` → a permanent "Not found".
- **Insights tab**, dictionary auto-learning, press-the-key hotkey recorder, 37 phantom
  transcripts purged, and a long UI pass (equal-height cards, page max-width, sidebar merged
  into the background, Dictionary table 1:1 with Flow).
- **Warm mic + 500 ms pre-roll** to catch the first word — then four follow-up fixes for the
  bugs it caused: recovery after sleep/device change, honouring the toggle immediately,
  a dropped `isRecording = true` that broke dictation with the toggle off (plus a fatal
  double `installTap` on re-enable), and finally the Bluetooth profile-pinning fix (`ef604aa`).

Decisions worth keeping: hallucination control is layered — energy gate, `suppress_nst`,
a bare comma-list glossary prompt (a `Glossary:` label taught Whisper the `Name:` format
and produced fake speaker names), a speaker-label strip, and a word-ratio plausibility
check on LLM output that falls back to the raw transcript.

Working discipline that repeatedly paid off: **measure before fixing**, render UI rather
than reason about it, and prove a test has teeth by reverting the fix. Several rounds were
lost to bad measurements — 90-second log windows catching stale processes, `ImageRenderer`
rendering a `ScrollView` blank, and an unbundled binary reading a different preferences
domain. Reading a bad measurement as a real result is the main failure mode here.

Blockers: none. Repo is private; sharing with the friend is pending Isabel's collaborator invite.
