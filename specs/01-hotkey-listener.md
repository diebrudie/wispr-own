# Spec 01 — Hotkey Listener

**Goal:** Detect "Left Option held alone" as press-and-hold, without breaking normal Option usage.

**Behavior**
- On Left Option down: start a 300 ms arm timer.
- If timer fires and no other key was pressed: emit `recordingShouldStart`.
- If any other key is pressed while Left Option is held (accents like ñ/ü/´): cancel — emit `recordingShouldCancel` if already started; the keystroke passes through untouched (listener is passive, never swallows events).
- On Left Option up after recording started: emit `recordingShouldStop`.
- On Left Option up before 300 ms: do nothing.

**Implementation notes**
- `CGEventTap` (listen-only) on `flagsChanged` + `keyDown`; distinguish left vs right Option via keycode 58 (left) vs 61 (right).
- Requires Accessibility permission (System Settings → Privacy & Security → Accessibility). Detect missing permission and surface it in the menu bar UI.
- Key choice lives in one config constant/UserDefaults key so Fn can replace it later.

**Done when:** a debug build logs start/stop/cancel correctly while (a) dictating, (b) typing "Señora Müller" with Option-accents, (c) tapping Option briefly.
