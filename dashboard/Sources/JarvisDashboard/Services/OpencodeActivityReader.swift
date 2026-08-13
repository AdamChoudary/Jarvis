import Foundation

/// The single most concrete "work in flight" signal available anywhere in
/// the system: opencode (and Claude Code, which shares this schema) writes
/// each tool call as a `part` row and marks it `state.status == "pending"`
/// until it resolves. Bounded to the most recent 200 rows and filtered in
/// Swift — a `WHERE json_extract(data,'$.state.status')='pending'` clause
/// forces a full scan of this table (measured ~2.7s against a live, 1.4GB
/// db); `ORDER BY rowid DESC LIMIT` is fast since rowid is the table's own
/// btree order, so this only ever costs reading the true tail.
enum OpencodeActivityReader {
    /// `ok == false` means the read itself failed (missing db, locked file,
    /// bad query) — distinct from a real empty result, which callers used to
    /// see as the exact same `[]` either way.
    static func pendingToolCalls() -> (calls: [PendingToolCall], ok: Bool) {
        guard let db = SQLiteReader(path: JarvisPaths.opencodeDB) else { return ([], false) }
        var out: [PendingToolCall] = []
        let ok = db.query("SELECT session_id, data FROM part ORDER BY rowid DESC LIMIT 200") { r in
            guard let sessionID = r["session_id"], let json = r["data"],
                  let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["type"] as? String == "tool",
                  let state = obj["state"] as? [String: Any],
                  state["status"] as? String == "pending" else { return }
            let tool = obj["tool"] as? String ?? "tool"
            let input = state["input"] as? [String: Any]
            let rawSummary = (input?["filePath"] as? String).map { ($0 as NSString).lastPathComponent }
                ?? (input?["command"] as? String)
                ?? (input?["pattern"] as? String)
                ?? ""
            // A shell command or grep pattern can run long; a comet label
            // sprawling across the orrery is its own kind of clutter.
            let summary = rawSummary.count > 48 ? String(rawSummary.prefix(48)) + "\u{2026}" : rawSummary
            out.append(PendingToolCall(sessionID: sessionID, tool: tool, summary: summary))
        }
        return (out, ok)
    }
}
