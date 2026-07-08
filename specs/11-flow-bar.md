# Spec 11 — WisprOwn Bar

**Goal:** Flow-style always-visible pill at the bottom-center of the screen that comes alive during dictation.

**States** (`FlowBarView.swift`)
- Idle: slim 64×10 dark pill with a resting dash.
- Recording: expands (spring) to 180×34 and renders a live waveform — 26 capsule bars driven by real mic RMS (`AudioRecorder.onLevel`, ~12 Hz, scaled ×9 into 0…1, ring-buffered in `AppState.levelHistory`).
- Transcribing: three pulsing dots (staggered ease-in-out).

**Panel** (`AppDelegate.setupFlowBar`)
- Borderless non-activating `NSPanel`, `.statusBar` level, transparent, click-through (`ignoresMouseEvents`), joins all Spaces + full-screen apps, repositioned on screen-parameter changes. Bottom-center, just above the Dock line.
- Toggle: Settings → System → "Show WisprOwn bar at all times" (`showFlowBar`, default on).

**Done when:** the pill sits at screen bottom, dances with speech volume while holding the hotkey, pulses during transcription, and returns to the slim resting state — without ever stealing focus or intercepting clicks.
