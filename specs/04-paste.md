# Spec 04 — Paste into Focused App

**Goal:** Insert the transcript at the user's cursor in whatever app is focused, preserving their clipboard.

**Behavior**
1. Snapshot current clipboard contents (all types it holds, not just plain text).
2. Write transcript to clipboard as plain text.
3. Simulate ⌘V into the frontmost app.
4. After ~1 s, restore the snapshot.
- If paste fails (no editable focus, app blocks synthetic events), the transcript is still in history (Spec 05) — that is the designed safety net, no retry logic in v1.

**Implementation notes**
- `NSPasteboard` for clipboard; `CGEvent` keyDown/keyUp for ⌘V (covered by the same Accessibility permission as Spec 01).
- Restore delay is a constant (default 1000 ms). Known race: if the user copies something within that window it gets clobbered — accepted for v1.
- Edge case: transcript itself should remain retrievable after restore — that's what history is for; do not keep it on the clipboard.

**Done when:** dictating into TextEdit, Slack, and a browser text field inserts the text, and a pre-copied clipboard item is intact afterwards.
