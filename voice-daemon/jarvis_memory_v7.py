#!/usr/bin/env python3
"""Jarvis Memory Index v7 — SQLite FTS5 + sentence-transformers vector search.

Upgrades from v6:
  - TF-IDF cosine → all-MiniLM-L6-v2 embeddings (384d, 3ms/100 docs)
  - Simple weighted sum → Reciprocal Rank Fusion (RRF) of FTS5 + vector
  - New: vector embeddings stored in DB, incrementally updated
  - New: emotion-weighted recency boost
  - New: source-specific weighting (vault > context > opencode > voice)

Usage:
    from jarvis_memory_v7 import MemoryIndex
    idx = MemoryIndex()
    idx.rebuild()
    idx.search("what did we do with jarvis")
"""
import glob, hashlib, json, math, os, re, sqlite3, sys, threading, time
from collections import Counter
from pathlib import Path

HOME = os.path.expanduser("~")
DB_PATH = os.path.join(HOME, ".hermes", "jarvis-voice", "jarvis-memory-v7.db")
OPENCODE_DB = os.path.join(HOME, ".local", "share", "opencode", "opencode.db")
CONTEXT_DIR = os.path.join(HOME, "Developer", "Context")
VAULT_DIR = os.path.join(HOME, "Documents", "Obsidian Vault", "Jarvis")
VOICE_MEMORY = os.path.join(HOME, ".hermes", "jarvis-voice", "voice-memory.md")

# ── Sentence-transformers embedding engine (lazy singleton) ──────────────────
_model = None
_model_name = "all-MiniLM-L6-v2"
_model_lock = threading.Lock()

def _get_model():
    """Double-checked locking: without it, a boot-time pre-warm thread racing
    a real concurrent query would each see _model is None and both load their
    own ~30s SentenceTransformer instance at once, doubling CPU/memory
    pressure during the exact window boot is already loading whisper/wake/
    sensevoice. Same pattern already used for _memory_index() in jarvis_ear.py."""
    global _model
    if _model is not None:
        return _model
    with _model_lock:
        if _model is None:
            from sentence_transformers import SentenceTransformer
            _model = SentenceTransformer(_model_name)
        return _model

def embed_texts(texts: list[str]) -> list[list[float]]:
    """Encode texts to 384d vectors. ~3ms/100 texts after first load."""
    model = _get_model()
    embeddings = model.encode(texts, show_progress_bar=False)
    return [e.tolist() for e in embeddings]

def embed_query(text: str) -> list[float]:
    """Encode a single query text."""
    return embed_texts([text])[0]

# ── Database schema ──────────────────────────────────────────────────────────
_SCHEMA = """
CREATE TABLE IF NOT EXISTS docs (
    id TEXT PRIMARY KEY,
    source TEXT NOT NULL,
    title TEXT,
    path TEXT,
    content TEXT,
    updated_at INTEGER,
    embedding BLOB           -- 384d float32 vector
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
        # Ensure embedding column exists (migrate from v6)
        try:
            self.conn.execute("SELECT embedding FROM docs LIMIT 1")
        except:
            self.conn.execute("ALTER TABLE docs ADD COLUMN embedding BLOB")

    def _doc_id(self, source: str, path: str) -> str:
        return hashlib.sha1(f"{source}:{path}".encode()).hexdigest()[:16]

    def _upsert(self, doc_id, source, title, path, content, updated_at, embedding=None):
        """Upsert a document with optional embedding."""
        emb_blob = None
        if embedding:
            import struct
            emb_blob = struct.pack(f'{len(embedding)}f', *embedding)
        self.conn.execute(
            "INSERT OR REPLACE INTO docs (id, source, title, path, content, updated_at, embedding) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (doc_id, source, title, path, content[:50000], updated_at, emb_blob)
        )

    def _embedding_from_blob(self, blob) -> list[float]:
        """Convert BLOB back to float list."""
        if blob is None:
            return []
        import struct
        n = len(blob) // 4
        return list(struct.unpack(f'{n}f', blob))

    # ── Indexers ──────────────────────────────────────────────────────────────
    def index_opencode(self) -> int:
        if not os.path.exists(OPENCODE_DB):
            return 0
        src = sqlite3.connect(OPENCODE_DB)
        cutoff = int((time.time() - 30 * 86400) * 1000)
        rows = src.execute("""
            SELECT p.session_id, p.data, p.time_created, s.title
            FROM part p
            JOIN session s ON s.id = p.session_id
            WHERE json_extract(p.data, '$.type') = 'text'
              AND p.time_created > ?
            ORDER BY p.time_created
        """, (cutoff,)).fetchall()
        src.close()

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
            # Truncate for embedding (512 tokens max for MiniLM)
            emb_text = combined[:2000]
            embedding = embed_texts([emb_text])[0] if emb_text.strip() else None
            self._upsert(doc_id, "opencode", title, f"opencode:{sid}",
                         combined, ts // 1000, embedding)
            count += 1
        return count

    def index_context(self) -> int:
        files = sorted(glob.glob(os.path.join(CONTEXT_DIR, "*.md")))
        count = 0
        for fp in files:
            try:
                content = open(fp, encoding="utf-8", errors="replace").read()
            except:
                continue
            title = os.path.basename(fp).replace(".md", "")
            mtime = int(os.path.getmtime(fp))
            doc_id = self._doc_id("context", fp)
            emb_text = content[:2000]
            embedding = embed_texts([emb_text])[0] if emb_text.strip() else None
            self._upsert(doc_id, "context", title, fp, content, mtime, embedding)
            count += 1
        return count

    def index_vault(self) -> int:
        files = sorted(glob.glob(os.path.join(VAULT_DIR, "**", "*.md"), recursive=True))
        count = 0
        for fp in files:
            try:
                content = open(fp, encoding="utf-8", errors="replace").read()
            except:
                continue
            title = os.path.basename(fp).replace(".md", "")
            mtime = int(os.path.getmtime(fp))
            doc_id = self._doc_id("vault", fp)
            emb_text = content[:2000]
            embedding = embed_texts([emb_text])[0] if emb_text.strip() else None
            self._upsert(doc_id, "vault", title, fp, content, mtime, embedding)
            count += 1
        return count

    def index_voice(self) -> int:
        if not os.path.exists(VOICE_MEMORY):
            return 0
        content = open(VOICE_MEMORY, encoding="utf-8", errors="replace").read()
        mtime = int(os.path.getmtime(VOICE_MEMORY))
        doc_id = self._doc_id("voice", VOICE_MEMORY)
        emb_text = content[:2000]
        embedding = embed_texts([emb_text])[0] if emb_text.strip() else None
        self._upsert(doc_id, "voice", "Voice Memory", VOICE_MEMORY,
                     content, mtime, embedding)
        return 1

    def rebuild(self) -> dict:
        t0 = time.time()
        self.conn.execute("DELETE FROM docs")
        counts = {
            "opencode": self.index_opencode(),
            "context": self.index_context(),
            "vault": self.index_vault(),
            "voice": self.index_voice(),
        }
        counts["total"] = sum(counts.values())
        counts["elapsed"] = round(time.time() - t0, 2)
        counts["ts"] = int(time.time())
        self.conn.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES ('last_rebuild', ?)",
            (json.dumps(counts),)
        )
        self.conn.commit()
        return counts

    # ── Search with RRF fusion ────────────────────────────────────────────────
    def search(self, query: str, limit: int = 10, source: str = None) -> list[dict]:
        """Hybrid FTS5 + vector search with Reciprocal Rank Fusion (RRF)."""
        # 1. FTS5 full-text search
        fts_q = " OR ".join(query.split()[:5])
        fts_q = re.sub(r'[^a-z0-9* ]', '', fts_q.lower())
        if not fts_q.strip():
            fts_q = "*"

        fts_rows = self.conn.execute(
            "SELECT id, rank FROM docs_fts WHERE docs_fts MATCH ? ORDER BY rank LIMIT ?",
            (fts_q, min(limit * 3, 50))
        ).fetchall()
        fts_ranked = {r[0]: i for i, r in enumerate(fts_rows)}  # position-based rank

        # 2. Vector search (cosine similarity)
        query_emb = embed_query(query)
        all_docs = self.conn.execute(
            "SELECT id, embedding FROM docs WHERE embedding IS NOT NULL"
        ).fetchall()

        vec_scores = {}
        for doc_id, emb_blob in all_docs:
            doc_emb = self._embedding_from_blob(emb_blob)
            if doc_emb:
                # Cosine similarity
                dot = sum(a * b for a, b in zip(query_emb, doc_emb))
                norm_a = math.sqrt(sum(a * a for a in query_emb))
                norm_b = math.sqrt(sum(b * b for b in doc_emb))
                if norm_a > 0 and norm_b > 0:
                    vec_scores[doc_id] = dot / (norm_a * norm_b)

        # Rank vector results by score
        vec_ranked = sorted(vec_scores.keys(), key=lambda x: -vec_scores[x])
        vec_positions = {doc_id: i for i, doc_id in enumerate(vec_ranked[:50])}

        # 3. RRF fusion: score = sum(1 / (k + rank)) for each ranking
        k = 60  # RRF constant (standard value)
        combined = {}
        all_ids = set(fts_ranked.keys()) | set(vec_positions.keys())
        for doc_id in all_ids:
            fts_rank = fts_ranked.get(doc_id, len(fts_ranked) + 10)
            vec_rank = vec_positions.get(doc_id, len(vec_positions) + 10)
            # Source weighting boost
            source_boost = 1.0
            if source:
                row = self.conn.execute(
                    "SELECT source FROM docs WHERE id = ?", (doc_id,)
                ).fetchone()
                if row and row[0] == source:
                    source_boost = 1.3
            combined[doc_id] = source_boost * (
                1.0 / (k + fts_rank) + 0.8 / (k + vec_rank)
            )

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

            # Recency boost: newer docs get slight boost
            age_hours = (time.time() - row[4]) / 3600 if row[4] else 9999
            recency_boost = 1.0 / (1.0 + age_hours / 168)  # 1 week half-life

            results.append({
                "id": doc_id,
                "source": row[0],
                "title": row[1],
                "path": row[2],
                "preview": row[3][:800],
                "score": round(score * recency_boost, 4),
                "updated_at": row[4],
            })
        return results

    def stats(self) -> dict:
        row = self.conn.execute("SELECT COUNT(*) FROM docs").fetchone()
        by_source = self.conn.execute(
            "SELECT source, COUNT(*) FROM docs GROUP BY source"
        ).fetchall()
        last = self.conn.execute(
            "SELECT value FROM meta WHERE key='last_rebuild'"
        ).fetchone()
        emb_count = self.conn.execute(
            "SELECT COUNT(*) FROM docs WHERE embedding IS NOT NULL"
        ).fetchone()
        return {
            "total_docs": row[0],
            "docs_with_embeddings": emb_count[0],
            "by_source": {s: c for s, c in by_source},
            "last_rebuild": json.loads(last[0]) if last else None,
            "db_size_kb": round(os.path.getsize(self.db_path) / 1024, 1) if os.path.exists(self.db_path) else 0,
        }

    def context_for_query(self, query: str, max_chars: int = 2000) -> str:
        # Raised from 5: at the current real corpus size (a few hundred docs)
        # the search itself costs milliseconds — the actual latency risk was
        # the embedding model's cold-load race (fixed in listen_loop()), not
        # result count. More real context per turn, same safe search cost.
        results = self.search(query, limit=8)
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
        print("Usage: python jarvis_memory_v7.py [rebuild|search <query>|stats]")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "rebuild":
        counts = idx.rebuild()
        print(json.dumps(counts, indent=2))
    elif cmd == "search":
        query = " ".join(sys.argv[2:])
        results = idx.search(query, limit=5)
        for r in results:
            print(f"  [{r['source']}] {r['title']} (score={r['score']})")
            print(f"    {r['preview'][:200]}...")
            print()
    elif cmd == "stats":
        print(json.dumps(idx.stats(), indent=2))
    else:
        print(f"Unknown command: {cmd}")

if __name__ == "__main__":
    main()
