# WisprOwn — status

Private, local, push-to-talk dictation for macOS (Swift/SwiftUI + whisper.cpp).
An owned alternative to Wispr Flow. Repo: `git@github.com:diebrudie/wispr-own.git` (**private**).

## Current status

v0.5.0 is built and running on Isabel's Mac. Since v0.4.0 it gained: a silence gate
(nothing said → nothing pasted), optional LLM cleanup with a bring-your-own API key
(Anthropic / OpenAI / Grok / custom, off by default), an Insights tab, dictionary
auto-learning from hand-corrected transcripts, a press-to-record hotkey picker, and a
warm-mic pre-roll so the first word isn't clipped.

The last stretch (2026-08-03 → 2026-08-11) was a run of audio-capture bugs caused by
that warm mic. All are fixed. The final one: holding a **Bluetooth** mic open pins the
headset profile, and profile flips mid-dictation deliver full-length *silent* buffers —
which looked like truncation. Bluetooth inputs now use the cold path; built-in and wired
mics keep warm-hold + pre-roll. Every take now logs its voiced share, so a silent take
and a good one are no longer indistinguishable in the log.

## Open tasks / next steps

- [ ] **← NEXT: live with v0.5.0 for a few days and confirm no more empty or clipped takes.** Watch the log for the `voiced share` warning: `/usr/bin/log show --process WisprOwn --last 10m --style compact | grep -E 'stopped|whisper:'`
- [ ] Isabel adds her friend as a GitHub collaborator (she wants to do this herself)
- [ ] `Scripts/make-signing-cert.sh` is still unverified on a Mac that has no certificate yet — the friend's install is the real test
- [ ] Backlog, unstarted (`specs/12-future-features.md`): §A interactive bar hover menu, §B streaming / paste latency, §D UI localization DE/ES, §H dictating over playing audio
- [ ] Offered, not built: idle-release of the warm mic after N minutes; month labels on the activity calendar; date-range picker; CSV export

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
