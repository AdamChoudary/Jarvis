import Foundation
import SQLite3

/// Minimal read-only SQLite wrapper — no ORM, no dependency, just the C API
/// that ships with macOS. Every query here is SELECT-only against Jarvis's
/// own databases; this process never writes to them.
final class SQLiteReader {
    private var db: OpaquePointer?

    init?(path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            db = nil
            return nil
        }
    }

    deinit { if db != nil { sqlite3_close(db) } }

    /// Runs `sql` and hands each result row to `row` as column index -> text.
    /// Returns whether the query actually ran — `false` means the prepare
    /// step itself failed (a real IO/schema problem), which callers need to
    /// tell apart from "ran fine, zero rows".
    @discardableResult
    func query(_ sql: String, bind: [String] = [], row: ([String: String]) -> Void) -> Bool {
        guard let db else { return false }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        for (i, value) in bind.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), value, -1, nil)
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            var dict: [String: String] = [:]
            let count = sqlite3_column_count(stmt)
            for col in 0..<count {
                let name = String(cString: sqlite3_column_name(stmt, col))
                if let text = sqlite3_column_text(stmt, col) {
                    dict[name] = String(cString: text)
                }
            }
            row(dict)
        }
        return true
    }
}
