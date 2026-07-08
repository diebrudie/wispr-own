# Decision Record — v1 (confirmed 2026-07-07)

Interview-confirmed decisions. Change only with a new explicit sign-off; append changes, don't rewrite history.

| # | Decision | Value |
|---|----------|-------|
| 1 | Goal | Privacy + no subscription + learning; personal Wispr Flow replacement |
| 2 | Platform | macOS only, Apple Silicon, Swift native menu bar app |
| 3 | Engine | Local whisper.cpp, `large-v3-turbo` model, fully offline |
| 4 | Languages | English, German, Spanish — auto-detected per dictation |
| 5 | Trigger | Hold **Left Option** to record, release to transcribe + paste. Cancel if another key is pressed while held, or if held < 300 ms. Key is configurable (future switch to Fn planned once Wispr Flow is retired) |
| 6 | Paste | Put transcript on clipboard → simulate ⌘V → restore previous clipboard ~1 s later |
| 7 | History storage | SQLite, single file in `~/Library/Application Support/WisprOwn/` |
| 8 | History UI | Wispr-style window: last 20 transcripts, timestamp, per-row copy button. Search deferred to v2 |
| 9 | Distribution | GitHub repo; wife installs on her own Mac (build from source or shared .app) |

Out of scope for v1: Windows, iOS, search in history, toggle-mode recording, saving audio files, custom vocabulary, streaming transcription.
