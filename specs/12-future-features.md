# Spec 12 — Future Features (backlog)

Not built. Recorded so intent isn't lost. Each needs its own spec + sign-off before implementation.

## A. Interactive WisprOwn bar (hover menu) — requested 2026-07-08
Hovering the bottom bar reveals a small floating menu, Flow-style.

Scope for **our** app (deliberately smaller than Flow's):
- A **tooltip pill** above the bar reading `Dictate ⌥` — i.e. the word "Dictate" plus the *currently configured* push-to-talk key (`HotkeyOption.current.displayName`), so the user is always reminded which key works.
- A **microphone button** that starts/stops a dictation by click, for people who'd rather not hold a key (a toggle-mode entry point — note this is the toggle-recording idea deliberately deferred in decision #5).

Not wanted: Flow's scratchpad and AI-transform buttons.

**Implementation notes:** the bar is currently `ignoresMouseEvents = true` (click-through, `AppDelegate.setupFlowBar`). Hover requires enabling mouse events on the panel and adding an `NSTrackingArea`, which risks intercepting clicks meant for apps beneath it — the panel would need to stay click-through except within the bar's own bounds. Expanded state should animate like the existing recording transition (`FlowBarView`).

## B. Streaming transcription / paste latency
Encode audio while the user speaks so key-release → paste approaches Flow's ~0.3–0.5 s (currently ~1 s). Biggest engineering lift; whisper.cpp supports incremental encoding.

**Before optimizing, measure.** Log the budget per stage — recorder stop/flush (`AudioRecorder`), whisper.cpp encode + decode (`Transcriber`), paste (`Paster`) — and spend the effort where the time actually is. Streaming only helps the decode stage. Note §G puts a network call on this same path.

## C. Insights page
Usage charts, WPM over time, streak heatmap (Flow's "Insights" screenshot). Data already exists in `transcripts` (durations, timestamps, languages).

## D. UI localization (DE/ES)
App interface currently English-only (dictation languages are unaffected).

## E. Dictionary auto-suggestions
Surface words the transcriber seems unsure about, or that the user frequently edits, as dictionary candidates. Must not observe keystrokes in other apps — privacy line we don't cross.

## F. Public release hardening
Apple Developer ID + notarization (removes the Gatekeeper right-click-open step), then flip the repo public. See `specs/07-packaging.md`.

## G. Optional LLM cleanup — bring your own API key
**Built 2026-07-30 — see `specs/13-llm-cleanup.md`.** Off by default; opt in with an API key in Settings → Cleanup.

## H. Dictating over playing audio — requested 2026-07-29
With music or video playing, the mic picks up the speakers and Whisper transcribes them alongside the user. The app should recognise it's being spoken *to*.

Two routes, neither validated — needs a spike before a spec:
- **Voice Isolation on the input.** macOS 12+ offers a system mic mode that suppresses background audio; reachable per-app via `AVCaptureDevice` (`activeMicrophoneMode` / `preferredMicrophoneMode`). Doesn't touch playback.
- **Duck or pause playback while recording.** Heavier and more intrusive — no clean public macOS API (`AVAudioSession` ducking is iOS-only); would mean CoreAudio tricks or driving Now Playing controls.

Prefer isolation. Silencing someone's music to hear them is a worse trade than filtering it out.
