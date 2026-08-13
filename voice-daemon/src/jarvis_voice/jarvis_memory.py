#!/usr/bin/env python3
"""Jarvis Memory Index — SQLite hybrid FTS5 + vector search.

Indexes:
  1. OpenCode sessions (user + assistant text parts from opencode.db)
  2. Context files (~/Developer/Context/*.md)
  3. Obsidian vault notes (~/Documents/Obsidian Vault/Jarvis/**/*.md)
  4. Voice memory (voice-memory.md)

Search combines FTS5 full-text ranking with simple TF-IDF cosine similarity
for semantic-ish matching. No external deps beyond stdlib.

Usage:
    from jarvis_memory import MemoryIndex
    idx = MemoryIndex()
    idx.rebuild()                  # full re-index
    idx.search("market watch briefing", limit=5)

CLI:
    python jarvis_memory.py rebuild
    python jarvis_memory.py search "what did we do with jarvis"
    python jarvis_memory.py stats
"""
import glob, hashlib, json, math, os, re, sqlite3, sys, time
from collections import Counter
from pathlib import Path

HOME = os.path.expanduser("~")
DB_PATH = os.path.join(HOME, ".hermes", "jarvis-voice", "jarvis-memory.db")
OPENCODE_DB = os.path.join(HOME, ".local", "share", "opencode", "opencode.db")
CONTEXT_DIR = os.path.join(HOME, "Developer", "Context")
VAULT_DIR = os.path.join(HOME, "Documents", "Obsidian Vault", "Jarvis")
VOICE_MEMORY = os.path.join(HOME, ".hermes", "jarvis-voice", "voice-memory.md")

# ── tokenisation ──────────────────────────────────────────────────────────────
_STOP = frozenset(
    "a an the and or but is are was were be been being have has had do does did "
    "will would shall should may might can could of in to for on with at by from "
    "as into through during before after above below between out off over under "
    "again further then once here there when where why how all both each few more "
    "most other some such no nor not only own same so than too very just don now "
    "it its he she they them their his her we our you your i me my am".split()
)

def tokenize(text: str) -> list[str]:
    """Lowercase, strip non-alpha, remove stopwords, stem trivially."""
    words = re.findall(r"[a-z0-9]{2,}", text.lower())
    return [w for w in words if w not in _STOP]

def tf_vector(tokens: list[str]) -> dict[str, float]:
    """Term frequency vector (normalised by doc length)."""
    if not tokens:
        return {}
    counts = Counter(tokens)
    n = len(tokens)
    return {t: c / n for t, c in counts.items()}

def cosine_sim(a: dict[str, float], b: dict[str, float]) -> float:
    if not a or not b:
        return 0.0
    keys = set(a) & set(b)
    if not keys:
        return 0.0
    dot = sum(a[k] * b[k] for k in keys)
    na = math.sqrt(sum(v * v for v in a.values()))
    nb = math.sqrt(sum(v * v for v in b.values()))
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)

# ── database ──────────────────────────────────────────────────────────────────
_SCHEMA = """
CREATE TABLE IF NOT EXISTS docs (
    id TEXT PRIMARY KEY,
    source TEXT NOT NULL,          -- 'opencode' | 'context' | 'vault' | 'voice'
    title TEXT,
    path TEXT,
    content TEXT,
    updated_at INTEGER,
    tf_vector TEXT                 -- JSON dict
);
CREATE VIRTUAL TABLE IF NOT EXISTS docs_fts USING fts5(
    id, source, title, content,
    content='docs',
    content_rowid='rowid'
);
CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY,
    value TEXT
);
CREATE TRIGGER IF NOT EXISTS docs_ai AFTER INSERT ON docs BEGIN
    INSERT INTO docs_fts(rowid, id, source, title, content)
    VALUES (new.rowid, new.id, new.source, new.title, new.content);
END;
CREATE TRIGGER IF NOT EXISTS docs_ad AFTER DELETE ON docs BEGIN
    INSERT INTO docs_fts(docs_fts, rowid, id, source, title, content)
    VALUES ('delete', old.rowid, old.id, old.source, old.title, old.content);
END;
CREATE TRIGGER IF NOT EXISTS docs_au AFTER UPDATE ON docs BEGIN
    INSERT INTO docs_fts(docs_fts, rowid, id, source, title, content)
    VALUES ('delete', old.rowid, old.id, old.source, old.title, old.content);
    INSERT INTO docs_fts(rowid, id, source, title, content)
    VALUES (new.rowid, new.id, new.source, new.title, new.content);
END;
"""

class MemoryIndex:
    def __init__(self, db_path: str = DB_PATH):
        self.db_path = db_path
        os.makedirs(os.path.dirname(db_path), exist_ok=True)
        self.conn = sqlite3.connect(db_path)
        self.conn.executescript(_SCHEMA)
        self.conn.execute("PRAGMA journal_mode=WAL")

    def _doc_id(self, source: str, path: str) -> str:
        return hashlib.sha1(f"{source}:{path}".encode()).hexdigest()[:16]

    def _upsert(self, doc_id: str, source: str, title: str, path: str,
                content: str, updated_at: int, tf_vec: dict):
        tokens = tokenize(content)
        vec = tf_vector(tokens)
        self.conn.execute(
            "INSERT OR REPLACE INTO docs (id, source, title, path, content, updated_at, tf_vector) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (doc_id, source, title, path, content[:50000], updated_at, json.dumps(vec))
        )

    # ── indexers ──────────────────────────────────────────────────────────────
    def index_opencode(self) -> int:
        """Index recent opencode sessions (last 30 days of text parts)."""
        if not os.path.exists(OPENCODE_DB):
            return 0
        src = sqlite3.connect(OPENCODE_DB)
        cutoff = int((time.time() - 30 * 86400) * 1000)  # ms
        rows = src.execute("""
            SELECT p.session_id, p.data, p.time_created, s.title
            FROM part p
            JOIN session s ON s.id = p.session_id
            WHERE json_extract(p.data, '$.type') = 'text'
              AND p.time_created > ?
            ORDER BY p.time_created
        """, (cutoff,)).fetchall()
        src.close()

        # Group by session
        sessions: dict[str, list] = {}
        for sid, data_json, ts, title in rows:
            data = json.loads(data_json)
            text = data.get("text", "").strip()
            if not text:
                continue
            sessions.setdefault(sid, []).append((ts, text, title or "Untitled session"))

        count = 0
        for sid, parts in sessions.items():
            parts.sort(key=lambda x: x[0])
            combined = "\n\n".join(t for _, t, _ in parts)
            title = parts[0][2]
            ts = parts[-1][0]
            doc_id = self._doc_id("opencode", sid)
            self._upsert(doc_id, "opencode", title, f"opencode:{sid}", combined, ts, {})
            count += 1
        self.conn.commit()
        return count

    def index_context_files(self) -> int:
        """Index ~/Developer/Context/*.md files."""
        count = 0
        for path in glob.glob(os.path.join(CONTEXT_DIR, "*.md")):
            try:
                stat = os.stat(path)
                content = open(path, encoding="utf-8", errors="replace").read()
                title = os.path.basename(path).replace(".md", "")
                doc_id = self._doc_id("context", path)
                self._upsert(doc_id, "context", title, path, content, int(stat.st_mtime), {})
                count += 1
            except Exception:
                continue
        self.conn.commit()
        return count

    def index_vault(self) -> int:
        """Index ~/Documents/Obsidian Vault/Jarvis/**/*.md notes."""
        count = 0
        for path in glob.glob(os.path.join(VAULT_DIR, "**", "*.md"), recursive=True):
            try:
                stat = os.stat(path)
                content = open(path, encoding="utf-8", errors="replace").read()
                title = os.path.basename(path).replace(".md", "")
                doc_id = self._doc_id("vault", path)
                self._upsert(doc_id, "vault", title, path, content, int(stat.st_mtime), {})
                count += 1
            except Exception:
                continue
        self.conn.commit()
        return count

    def index_voice_memory(self) -> int:
        """Index voice-memory.md."""
        if not os.path.exists(VOICE_MEMORY):
            return 0
        content = open(VOICE_MEMORY, encoding="utf-8", errors="replace").read()
        doc_id = self._doc_id("voice", VOICE_MEMORY)
        stat = os.stat(VOICE_MEMORY)
        self._upsert(doc_id, "voice", "Voice Memory", VOICE_MEMORY, content, int(stat.st_mtime), {})
        self.conn.commit()
        return 1

    def rebuild(self) -> dict:
        """Full re-index of all sources. Returns counts."""
        t0 = time.time()
        self.conn.execute("DELETE FROM docs")
        counts = {
            "opencode": self.index_opencode(),
            "context": self.index_context_files(),
            "vault": self.index_vault(),
            "voice": self.index_voice_memory(),
        }
        elapsed = time.time() - t0
        self.conn.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)",
            ("last_rebuild", json.dumps({"counts": counts, "elapsed": round(elapsed, 2), "ts": int(time.time())}))
        )
        self.conn.commit()
        counts["elapsed"] = round(elapsed, 2)
        counts["total"] = sum(v for k, v in counts.items() if k != "elapsed")
        return counts

    # ── search ────────────────────────────────────────────────────────────────
    def search(self, query: str, limit: int = 5, source: str = None) -> list[dict]:
        """Hybrid search: FTS5 rank + TF-IDF cosine similarity."""
        tokens = tokenize(query)
        if not tokens:
            return []

        # FTS5 query: OR-join tokens
        fts_q = " OR ".join(tokens)
        fts_rows = self.conn.execute(
            "SELECT id, rank FROM docs_fts WHERE docs_fts MATCH ? ORDER BY rank LIMIT ?",
            (fts_q, min(limit * 3, 50))
        ).fetchall()
        fts_scores = {r[0]: -r[1] for r in fts_rows}  # FTS5 rank is negative (higher = better)

        # TF-IDF cosine for all candidate docs
        query_vec = tf_vector(tokens)
        candidates = set(fts_scores.keys())

        # Also check top docs by recency if FTS found little
        if len(candidates) < 5:
            recent = self.conn.execute(
                "SELECT id FROM docs ORDER BY updated_at DESC LIMIT 20"
            ).fetchall()
            candidates.update(r[0] for r in recent)

        vec_scores = {}
        for doc_id in candidates:
            row = self.conn.execute(
                "SELECT tf_vector FROM docs WHERE id = ?", (doc_id,)
            ).fetchone()
            if row and row[0]:
                doc_vec = json.loads(row[0])
                vec_scores[doc_id] = cosine_sim(query_vec, doc_vec)

        # Combine scores: normalise FTS rank to 0-1, combine with cosine
        fts_max = max(fts_scores.values()) if fts_scores else 1.0
        combined = {}
        for doc_id in candidates:
            fts_n = fts_scores.get(doc_id, 0) / fts_max if fts_max else 0
            vec_n = vec_scores.get(doc_id, 0)
            combined[doc_id] = 0.6 * fts_n + 0.4 * vec_n  # FTS gets more weight

        ranked = sorted(combined.items(), key=lambda x: -x[1])[:limit]

        results = []
        for doc_id, score in ranked:
            row = self.conn.execute(
                "SELECT source, title, path, content, updated_at FROM docs WHERE id = ?",
                (doc_id,)
            ).fetchone()
            if not row:
                continue
            if source and row[0] != source:
                continue
            content_preview = row[3][:800]
            results.append({
                "id": doc_id,
                "source": row[0],
                "title": row[1],
                "path": row[2],
                "preview": content_preview,
                "score": round(score, 4),
                "updated_at": row[4],
            })
        return results

    def stats(self) -> dict:
        """Index statistics."""
        row = self.conn.execute("SELECT COUNT(*) FROM docs").fetchone()
        by_source = self.conn.execute(
            "SELECT source, COUNT(*) FROM docs GROUP BY source"
        ).fetchall()
        last = self.conn.execute(
            "SELECT value FROM meta WHERE key='last_rebuild'"
        ).fetchone()
        return {
            "total_docs": row[0],
            "by_source": {s: c for s, c in by_source},
            "last_rebuild": json.loads(last[0]) if last else None,
            "db_size_kb": round(os.path.getsize(self.db_path) / 1024, 1) if os.path.exists(self.db_path) else 0,
        }

    def context_for_query(self, query: str, max_chars: int = 2000) -> str:
        """Return a formatted context string suitable for injection into an LLM prompt."""
        results = self.search(query, limit=5)
        if not results:
            return ""
        parts = []
        for r in results:
            header = f"[{r['source']}] {r['title']} (score={r['score']})"
            parts.append(f"{header}\n{r['preview']}")
        combined = "\n\n---\n\n".join(parts)
        return combined[:max_chars]


# ── CLI ───────────────────────────────────────────────────────────────────────
def main():
    idx = MemoryIndex()
    if len(sys.argv) < 2:
        print("Usage: python jarvis_memory.py [rebuild|search <query>|stats]")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "rebuild":
        counts = idx.rebuild()
        print(json.dumps(counts, indent=2))
    elif cmd == "search":
        query = " ".join(sys.argv[2:])
        results = idx.search(query, limit=5)
        for r in results:
            print(f"\n{'='*60}")
            print(f"[{r['source']}] {r['title']}  (score={r['score']})")
            print(f"path: {r['path']}")
            print(f"preview: {r['preview'][:300]}...")
    elif cmd == "stats":
        print(json.dumps(idx.stats(), indent=2))
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)

if __name__ == "__main__":
    main()
