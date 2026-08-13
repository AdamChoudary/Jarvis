#!/usr/bin/env python3
"""LightRAG — Lightweight knowledge graph for Jarvis memory.

Builds on Nemori's knowledge graph (entities + relations + facts) and adds:
  - Graph traversal queries (neighbors, paths, clusters)
  - Importance scoring (PageRank-like)
  - Context injection for LLM prompts
  - Auto-sync with Obsidian vault

Usage:
    from jarvis_lightrag import LightRAG
    rag = LightRAG()
    context = rag.context_for_query("what projects am I working on")
    neighbors = rag.get_neighbors("Jarvis")
"""
import json, os, sqlite3, time
from collections import defaultdict

HOME = os.path.expanduser("~")
KB_PATH = os.path.join(HOME, ".hermes", "jarvis-voice", "knowledge-graph.db")
VAULT_DIR = os.path.join(HOME, "Documents", "Obsidian Vault", "Jarvis")

class LightRAG:
    def __init__(self):
        self.conn = sqlite3.connect(KB_PATH)
        self.conn.execute("PRAGMA journal_mode=WAL")

    def get_entity(self, name: str) -> dict | None:
        """Get entity by name (case-insensitive)."""
        row = self.conn.execute(
            "SELECT name, type, properties, last_seen, mention_count "
            "FROM entities WHERE LOWER(name) = LOWER(?)",
            (name,)
        ).fetchone()
        if not row:
            return None
        return {
            "name": row[0], "type": row[1],
            "properties": json.loads(row[2]) if row[2] else {},
            "last_seen": row[3], "mention_count": row[4],
        }

    def get_neighbors(self, name: str, depth: int = 1) -> list[dict]:
        """Get all entities connected to the given entity."""
        visited = set()
        results = []

        def _traverse(n, d):
            if d > depth or n in visited:
                return
            visited.add(n)
            rows = self.conn.execute(
                "SELECT target, relation, context FROM relations WHERE source = ? "
                "UNION ALL "
                "SELECT source, relation, context FROM relations WHERE target = ?",
                (n, n)
            ).fetchall()
            for target, rel, ctx in rows:
                ent = self.get_entity(target)
                if ent:
                    results.append({
                        "entity": ent,
                        "relation": rel,
                        "context": ctx,
                        "depth": d,
                    })
                _traverse(target, d + 1)

        _traverse(name, 1)
        return results

    def get_clusters(self, min_members: int = 3) -> list[list[str]]:
        """Find connected components (clusters) in the knowledge graph."""
        adj = defaultdict(set)
        for src, tgt, *_ in self.conn.execute(
            "SELECT source, target FROM relations"
        ).fetchall():
            adj[src].add(tgt)
            adj[tgt].add(src)

        visited = set()
        clusters = []
        for node in adj:
            if node in visited:
                continue
            cluster = []
            stack = [node]
            while stack:
                n = stack.pop()
                if n in visited:
                    continue
                visited.add(n)
                cluster.append(n)
                stack.extend(adj[n] - visited)
            if len(cluster) >= min_members:
                clusters.append(sorted(cluster))
        return clusters

    def importance_scores(self) -> dict[str, float]:
        """PageRank-like importance scoring for entities."""
        # Simple version: mention_count * degree
        entities = self.conn.execute("SELECT name FROM entities").fetchall()
        scores = {}
        for (name,) in entities:
            mentions = self.conn.execute(
                "SELECT mention_count FROM entities WHERE name = ?", (name,)
            ).fetchone()
            degree = self.conn.execute(
                "SELECT COUNT(*) FROM relations WHERE source = ? OR target = ?",
                (name, name)
            ).fetchone()
            scores[name] = (mentions[0] if mentions else 1) * (degree[0] + 1)
        # Normalize to 0-1
        max_score = max(scores.values()) if scores else 1
        return {k: v / max_score for k, v in scores.items()}

    def search_entities(self, query: str, limit: int = 10) -> list[dict]:
        """Search entities by name or type."""
        rows = self.conn.execute(
            "SELECT name, type, properties, last_seen, mention_count "
            "FROM entities WHERE name LIKE ? OR type LIKE ? "
            "ORDER BY mention_count DESC LIMIT ?",
            (f"%{query}%", f"%{query}%", limit)
        ).fetchall()
        return [
            {"name": r[0], "type": r[1], "properties": json.loads(r[2]) if r[2] else {},
             "last_seen": r[3], "mention_count": r[4]}
            for r in rows
        ]

    def search_facts(self, query: str, limit: int = 5) -> list[dict]:
        """Search facts by keyword."""
        rows = self.conn.execute(
            "SELECT text, entities, confidence, created_at FROM facts "
            "WHERE text LIKE ? ORDER BY confidence DESC LIMIT ?",
            (f"%{query}%", limit)
        ).fetchall()
        return [
            {"text": r[0], "entities": json.loads(r[1]) if r[1] else [],
             "confidence": r[2], "created_at": r[3]}
            for r in rows
        ]

    def context_for_query(self, query: str, max_chars: int = 2000) -> str:
        """Build rich context from knowledge graph for LLM injection."""
        parts = []

        # 1. Relevant facts
        facts = self.search_facts(query, limit=5)
        if facts:
            fact_lines = [f"- {f['text']}" for f in facts]
            parts.append("Known facts:\n" + "\n".join(fact_lines))

        # 2. Relevant entities
        entities = self.search_entities(query, limit=5)
        for ent in entities:
            neighbors = self.get_neighbors(ent["name"], depth=1)
            if neighbors:
                rel_lines = [f"  - {n['relation']} → {n['entity']['name']}" for n in neighbors[:3]]
                parts.append(f"{ent['name']} ({ent['type']}):\n" + "\n".join(rel_lines))

        # 3. Important entities
        importance = self.importance_scores()
        top_entities = sorted(importance.items(), key=lambda x: -x[1])[:5]
        if top_entities:
            imp_lines = [f"- {name} (importance: {score:.2f})" for name, score in top_entities]
            parts.append("Key entities:\n" + "\n".join(imp_lines))

        combined = "\n\n".join(parts)
        return combined[:max_chars]

    def sync_to_vault(self):
        """Write knowledge graph summary to Obsidian vault."""
        importance = self.importance_scores()
        clusters = self.get_clusters(min_members=2)
        facts_count = self.conn.execute("SELECT COUNT(*) FROM facts").fetchone()[0]

        content = f"""---
created: {time.strftime('%Y-%m-%d')}
tags:
  - jarvis
  - knowledge-graph
---

# Jarvis Knowledge Graph

## Entities ({len(importance)})

| Entity | Type | Importance |
|--------|------|------------|
"""
        for name, score in sorted(importance.items(), key=lambda x: -x[1])[:20]:
            ent = self.get_entity(name)
            if ent:
                content += f"| {name} | {ent['type']} | {score:.2f} |\n"

        content += f"\n\n## Clusters ({len(clusters)})\n\n"
        for i, cluster in enumerate(clusters[:10]):
            content += f"### Cluster {i+1}\n"
            content += ", ".join(cluster) + "\n\n"

        content += f"\n## Facts ({facts_count})\n\n"
        recent_facts = self.conn.execute(
            "SELECT text, created_at FROM facts ORDER BY created_at DESC LIMIT 20"
        ).fetchall()
        for text, ts in recent_facts:
            date = time.strftime('%Y-%m-%d', time.localtime(ts)) if ts else "unknown"
            content += f"- [{date}] {text}\n"

        path = os.path.join(VAULT_DIR, "Knowledge Graph.md")
        with open(path, "w") as f:
            f.write(content)
        return path

    def stats(self) -> dict:
        entities = self.conn.execute("SELECT COUNT(*) FROM entities").fetchone()[0]
        relations = self.conn.execute("SELECT COUNT(*) FROM relations").fetchone()[0]
        facts = self.conn.execute("SELECT COUNT(*) FROM facts").fetchone()[0]
        clusters = len(self.get_clusters())
        return {
            "entities": entities,
            "relations": relations,
            "facts": facts,
            "clusters": clusters,
            "kb_size_kb": round(os.path.getsize(KB_PATH) / 1024, 1) if os.path.exists(KB_PATH) else 0,
        }


# ── CLI ───────────────────────────────────────────────────────────────────────
def main():
    import sys
    rag = LightRAG()
    if len(sys.argv) < 2:
        print("Usage: python jarvis_lightrag.py [stats|context <query>|neighbors <entity>|vault]")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "stats":
        print(json.dumps(rag.stats(), indent=2))
    elif cmd == "context":
        query = " ".join(sys.argv[2:])
        print(rag.context_for_query(query))
    elif cmd == "neighbors":
        name = " ".join(sys.argv[2:])
        results = rag.get_neighbors(name, depth=2)
        for r in results:
            print(f"  [{r['entity']['name']}] --{r['relation']}--> (depth={r['depth']})")
    elif cmd == "vault":
        path = rag.sync_to_vault()
        print(f"Synced to: {path}")
    else:
        print(f"Unknown command: {cmd}")

if __name__ == "__main__":
    main()
