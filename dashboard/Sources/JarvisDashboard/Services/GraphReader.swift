import Foundation

enum GraphReader {
    /// Distinguishes "read genuinely succeeded, no such row" from "the query
    /// itself failed" — a bare optional collapsed both into the same nil, so
    /// callers had no way to tell a transient IO hiccup from a real miss.
    enum DocLookup {
        case found(title: String, source: String, path: String, content: String)
        case notFound
        case readFailed
    }

    static func docs(limit: Int = 500) -> [DocNode] {
        guard let db = SQLiteReader(path: JarvisPaths.memoryDB) else { return [] }
        var out: [DocNode] = []
        db.query("SELECT id, source, title, path FROM docs ORDER BY updated_at DESC LIMIT \(limit)") { r in
            out.append(DocNode(id: r["id"] ?? "", source: r["source"] ?? "",
                                title: r["title"] ?? r["id"] ?? "", path: r["path"] ?? ""))
        }
        return out
    }

    /// When the FTS index was last actually rebuilt — distinct from any
    /// source doc's own mtime. Live-caught (2026-07-26): the rebuild silently
    /// stalled for 6 days with nothing in the UI to show it had gone stale.
    static func lastRebuilt() -> Date? {
        guard let db = SQLiteReader(path: JarvisPaths.memoryDB) else { return nil }
        var ts: Int?
        db.query("SELECT value FROM meta WHERE key = 'last_rebuild'") { r in
            guard let json = r["value"]?.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return }
            ts = obj["ts"] as? Int
        }
        return ts.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    static func docContent(id: String) -> DocLookup {
        guard let db = SQLiteReader(path: JarvisPaths.memoryDB) else { return .readFailed }
        var result: (String, String, String, String)?
        let ok = db.query("SELECT title, source, path, content FROM docs WHERE id = ?", bind: [id]) { r in
            result = (r["title"] ?? id, r["source"] ?? "", r["path"] ?? "", r["content"] ?? "")
        }
        guard ok else { return .readFailed }
        guard let result else { return .notFound }
        return .found(title: result.0, source: result.1, path: result.2, content: result.3)
    }

    /// `ok == false` means the read itself failed — distinct from a
    /// genuinely empty knowledge graph, which used to look identical (`[]`).
    /// Bounded the same way `docs(limit:)` already is — harmless at today's
    /// 0 rows, a real ceiling once distillation actually populates this db.
    static func entities(limit: Int = 300) -> (items: [KGEntity], ok: Bool) {
        guard let db = SQLiteReader(path: JarvisPaths.knowledgeGraphDB) else { return ([], false) }
        var out: [KGEntity] = []
        let ok = db.query("SELECT name, type, mention_count FROM entities ORDER BY mention_count DESC LIMIT \(limit)") { r in
            out.append(KGEntity(name: r["name"] ?? "", type: r["type"] ?? "",
                                 mentions: Int(r["mention_count"] ?? "1") ?? 1))
        }
        return (out, ok)
    }

    static func relations(limit: Int = 600) -> (items: [KGRelation], ok: Bool) {
        guard let db = SQLiteReader(path: JarvisPaths.knowledgeGraphDB) else { return ([], false) }
        var out: [KGRelation] = []
        let ok = db.query("SELECT source, target, relation FROM relations ORDER BY weight DESC LIMIT \(limit)") { r in
            out.append(KGRelation(source: r["source"] ?? "", target: r["target"] ?? "", relation: r["relation"] ?? ""))
        }
        return (out, ok)
    }
}
