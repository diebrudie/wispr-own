# Spec 05 — History Store

**Goal:** Persist every transcript so a failed paste is never a lost dictation, in a table structure that supports future analysis.

**Schema** (SQLite at `~/Library/Application Support/WisprOwn/history.sqlite`)
```sql
CREATE TABLE transcripts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at TEXT NOT NULL,        -- ISO 8601, local time with offset
  text TEXT NOT NULL,
  language TEXT,                   -- whisper-detected code: en/de/es/...
  audio_duration_ms INTEGER,
  transcribe_ms INTEGER,           -- latency, for future analysis
  target_app TEXT                  -- frontmost app bundle id at paste time
);
```

**Behavior**
- Insert happens BEFORE the paste attempt (Spec 04), so the safety net holds even if paste crashes.
- Empty transcripts are not stored.
- No retention limit in v1 (text is tiny); revisit if analysis wants it.

**Implementation notes**
- Raw SQLite3 C API or GRDB — whichever keeps dependencies minimal; no ORM ceremony needed for one table.
- All writes on a single serial queue.

**Done when:** every successful dictation appears as a row with correct fields, queryable via `sqlite3` CLI.
