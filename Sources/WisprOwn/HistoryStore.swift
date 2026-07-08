import Foundation
import SQLite3

struct Transcript: Identifiable, Equatable {
    let id: Int64
    let createdAt: String
    let text: String
    let language: String?
    let audioDurationMs: Int?
    let transcribeMs: Int?
    let targetApp: String?
}

/// Spec 05 — SQLite-backed history. Zero-loss rule: `insert` is called
/// BEFORE any paste attempt. All access goes through one serial queue.
final class HistoryStore {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.diebrudie.wisprown.history")
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static var dbPath: URL { ModelManager.supportDir.appendingPathComponent("history.sqlite") }

    init() throws {
        try FileManager.default.createDirectory(at: ModelManager.supportDir, withIntermediateDirectories: true)
        guard sqlite3_open(Self.dbPath.path, &db) == SQLITE_OK else {
            throw NSError(domain: "WisprOwn", code: 20, userInfo: [
                NSLocalizedDescriptionKey: "Cannot open history database",
            ])
        }
        exec("PRAGMA journal_mode=WAL")
        exec("""
            CREATE TABLE IF NOT EXISTS transcripts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              created_at TEXT NOT NULL,
              text TEXT NOT NULL,
              language TEXT,
              audio_duration_ms INTEGER,
              transcribe_ms INTEGER,
              target_app TEXT
            )
            """)
        exec("""
            CREATE TABLE IF NOT EXISTS dictionary (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              phrase TEXT NOT NULL UNIQUE,
              created_at TEXT NOT NULL
            )
            """)
    }

    // MARK: - Dictionary (Spec 10)

    struct DictionaryEntry: Identifiable, Equatable {
        let id: Int64
        var phrase: String
    }

    func dictionaryEntries() -> [DictionaryEntry] {
        queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT id, phrase FROM dictionary ORDER BY phrase COLLATE NOCASE",
                                     -1, &stmt, nil) == SQLITE_OK else { return [] }
            var rows: [DictionaryEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(DictionaryEntry(
                    id: sqlite3_column_int64(stmt, 0),
                    phrase: String(cString: sqlite3_column_text(stmt, 1))
                ))
            }
            return rows
        }
    }

    /// Returns false when the phrase already exists (UNIQUE constraint).
    @discardableResult
    func dictionaryAdd(_ phrase: String) -> Bool {
        queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO dictionary (phrase, created_at) VALUES (?, ?)",
                                     -1, &stmt, nil) == SQLITE_OK else { return false }
            sqlite3_bind_text(stmt, 1, phrase, -1, Self.transient)
            sqlite3_bind_text(stmt, 2, Self.timestamp(), -1, Self.transient)
            return sqlite3_step(stmt) == SQLITE_DONE && sqlite3_changes(db) > 0
        }
    }

    func dictionaryUpdate(id: Int64, phrase: String) {
        queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "UPDATE OR IGNORE dictionary SET phrase = ? WHERE id = ?",
                                     -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, phrase, -1, Self.transient)
            sqlite3_bind_int64(stmt, 2, id)
            sqlite3_step(stmt)
        }
    }

    func dictionaryDelete(id: Int64) {
        queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "DELETE FROM dictionary WHERE id = ?",
                                     -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
        }
    }

    @discardableResult
    func insert(text: String, language: String?, audioDurationMs: Int?,
                transcribeMs: Int?, targetApp: String?) -> Int64 {
        queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, """
                INSERT INTO transcripts
                  (created_at, text, language, audio_duration_ms, transcribe_ms, target_app)
                VALUES (?, ?, ?, ?, ?, ?)
                """, -1, &stmt, nil) == SQLITE_OK else { return -1 }

            sqlite3_bind_text(stmt, 1, Self.timestamp(), -1, Self.transient)
            sqlite3_bind_text(stmt, 2, text, -1, Self.transient)
            bind(stmt, 3, language)
            bind(stmt, 4, audioDurationMs)
            bind(stmt, 5, transcribeMs)
            bind(stmt, 6, targetApp)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                dlog("history: INSERT failed: \(String(cString: sqlite3_errmsg(db)))")
                return -1
            }
            return sqlite3_last_insert_rowid(db)
        }
    }

    func recent(limit: Int = 20) -> [Transcript] {
        fetch(sql: """
            SELECT id, created_at, text, language, audio_duration_ms, transcribe_ms, target_app
            FROM transcripts ORDER BY id DESC LIMIT ?
            """) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(limit))
        }
    }

    /// Case-insensitive substring search across all history.
    func search(_ query: String, limit: Int = 50) -> [Transcript] {
        fetch(sql: """
            SELECT id, created_at, text, language, audio_duration_ms, transcribe_ms, target_app
            FROM transcripts WHERE text LIKE ? ORDER BY id DESC LIMIT ?
            """) { stmt in
            sqlite3_bind_text(stmt, 1, "%\(query)%", -1, Self.transient)
            sqlite3_bind_int(stmt, 2, Int32(limit))
        }
    }

    struct Stats {
        var totalWords = 0
        var wordsPerMinute = 0
        var dayStreak = 0
    }

    /// One pass over all rows: total words, average WPM (spoken time only),
    /// and consecutive-day streak ending today (or yesterday if today is empty).
    func stats() -> Stats {
        var totalWords = 0
        var totalSpokenMs = 0
        var days = Set<String>()

        let rows = fetch(sql: """
            SELECT id, created_at, text, language, audio_duration_ms, transcribe_ms, target_app
            FROM transcripts
            """) { _ in }
        for row in rows {
            totalWords += row.text.split(whereSeparator: \.isWhitespace).count
            totalSpokenMs += row.audioDurationMs ?? 0
            days.insert(String(row.createdAt.prefix(10))) // yyyy-MM-dd, local time
        }

        var stats = Stats(totalWords: totalWords)
        if totalSpokenMs > 0 {
            stats.wordsPerMinute = Int((Double(totalWords) / (Double(totalSpokenMs) / 60_000)).rounded())
        }

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        var cursor = Date()
        // A streak may still be alive if today has no dictation yet.
        if !days.contains(dayFormatter.string(from: cursor)) {
            cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor)!
        }
        while days.contains(dayFormatter.string(from: cursor)) {
            stats.dayStreak += 1
            cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor)!
        }
        return stats
    }

    func delete(id: Int64) {
        queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "DELETE FROM transcripts WHERE id = ?",
                                     -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
        }
    }

    private func fetch(sql: String, bind: (OpaquePointer?) -> Void) -> [Transcript] {
        queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            bind(stmt)

            var rows: [Transcript] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(Transcript(
                    id: sqlite3_column_int64(stmt, 0),
                    createdAt: String(cString: sqlite3_column_text(stmt, 1)),
                    text: String(cString: sqlite3_column_text(stmt, 2)),
                    language: column(stmt, 3),
                    audioDurationMs: columnInt(stmt, 4),
                    transcribeMs: columnInt(stmt, 5),
                    targetApp: column(stmt, 6)
                ))
            }
            return rows
        }
    }

    /// ISO 8601 with local offset, e.g. 2026-07-08T09:14:03+02:00
    static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return f.string(from: Date())
    }

    private func exec(_ sql: String) {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            dlog("history: exec failed (\(sql.prefix(30))…): \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, Self.transient)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let value {
            sqlite3_bind_int64(stmt, index, Int64(value))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func column(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL
            ? nil : String(cString: sqlite3_column_text(stmt, index))
    }

    private func columnInt(_ stmt: OpaquePointer?, _ index: Int32) -> Int? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL
            ? nil : Int(sqlite3_column_int64(stmt, index))
    }

    deinit {
        sqlite3_close(db)
    }
}
