# Spec 09 — Main Window (Home hub)

**Goal:** Wispr-Flow-style hub replacing the standalone History window. Violet theme derived from the app icon (`Theme.swift`).

**Layout** (`MainWindowView.swift`)
- `NavigationSplitView`: sidebar (wordmark, Home, Dictionary, Settings gear pinned bottom) → detail.
- Settings opens as a **sheet overlay** (Spec: `SettingsOverlayView.swift`), not a separate window.
- Opened via Dock icon click, ⌘Tab reopen, or menu bar → "Open WisprOwn…".

**Home** (`HomeView.swift`)
- "Welcome back, {first name}" (from `NSFullUserName()`).
- Stats card: total words, WPM (words ÷ spoken minutes), day streak (consecutive days with ≥1 dictation, today or yesterday anchored). Source: `HistoryStore.stats()`, verified against raw SQL.
- `TranscriptList` below: search across all history, day-grouped rows with copy/delete (reused from the old History window).

**Settings overlay**
- Shortcut picker (`HotkeyOption`), microphone picker (CoreAudio UIDs, `AudioDevices.swift`; applied per-recording in `AudioRecorder.applyPreferredDevice`), dictation-language chips (constrains detection; single selection skips the detect pass), sounds, launch at login, data folder, version.

**Explicitly deferred** (decision 2026-07-08): Insights page (charts/heatmap), app UI localization (EN-only for now).

**Done when:** window opens from Dock; stats match `sqlite3` arithmetic; search/copy/delete work; mic + language + hotkey changes take effect without restart.
