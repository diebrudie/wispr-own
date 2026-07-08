# Spec 06 — Menu Bar + History Window

**Goal:** Visible app state and a Wispr-style history window with one-click re-copy.

**Menu bar**
- Icon states: idle / recording (distinct, e.g. filled red) / transcribing (spinner-ish) / error (permission missing, model downloading).
- Menu items: "History…", "Start at Login" toggle, "Quit". Settings beyond that deferred.

**History window** (modeled on the Wispr Flow screenshot)
- Chronological list, newest first, last 20 rows, grouped under a "Today"-style date header.
- Each row: time (e.g. "2:35 pm"), transcript text (wrap up to ~3 lines), copy button.
- Copy button puts full text on clipboard (no auto-restore here — copying is the point) and shows brief "Copied" feedback.
- Search icon/field: NOT in v1 (decision record #8) — layout should leave room for it.

**Implementation notes**
- SwiftUI: `MenuBarExtra` + a plain `Window` scene for history.
- Window reads from the SQLite store (Spec 05); refresh on open and on new insert.

**Done when:** you can dictate, open History, see the entry with timestamp, click copy, and paste it manually elsewhere.
