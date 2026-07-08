# Spec 02 — Audio Capture

**Goal:** Record microphone audio between `recordingShouldStart` and `recordingShouldStop`, producing a buffer Whisper can consume.

**Behavior**
- Start: begin capturing from default input device.
- Stop: return audio as 16 kHz mono Float32 PCM (whisper.cpp's expected format). No file needs to be written in the success path; keep an in-memory buffer.
- Cancel: discard buffer.
- Cap recordings at 5 minutes (safety against a stuck key); auto-stop and proceed as a normal stop.

**Implementation notes**
- `AVAudioEngine` input node + `AVAudioConverter` down to 16 kHz mono.
- Requires Microphone permission (`NSMicrophoneUsageDescription`); handle denial with a menu bar error state.
- Play the system "begin/end recording" feedback: subtle sound or rely on menu bar icon change (Spec 06). Icon change is mandatory, sound optional-but-default-on.

**Done when:** holding the key and speaking yields a PCM buffer whose duration matches the hold time, verified by writing a debug WAV and listening to it.
