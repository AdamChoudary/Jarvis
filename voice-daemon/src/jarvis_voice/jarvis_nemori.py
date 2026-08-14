#!/usr/bin/env python3
"""Nemori Active Distillation — real-time knowledge extraction from conversations.

Extracts structured knowledge from voice conversations and writes to:
  1. voice-memory.md (existing memory file)
  2. Obsidian vault notes (for important facts)
  3. Knowledge graph nodes (for LightRAG)

Usage:
    from jarvis_voice.jarvis_nemori import Nemori
    nemori = Nemori()
    new_facts = nemori.distill(recent_messages, existing_memory)
"""
import json, os, re, sqlite3, time
from pathlib import Path

HOME = os.path.expanduser("~")
MEMORY_FILE = os.path.join(HOME, ".hermes", "jarvis-voice", "voice-memory.md")
VAULT_DIR = os.path.join(HOME, "Documents", "Obsidian Vault", "Jarvis")
VAULT_MEMORY = os.path.join(VAULT_DIR, "Memory")
KB_PATH = os.path.join(HOME, ".hermes", "jarvis-voice", "knowledge-graph.db")

# LLM endpoints for distillation
SESSION = None
NIM_URL = "https://integrate.api.nvidia.com/v1/chat/completions"
NIM_KEY = os.environ.get("NVIDIA_API_KEY", "")
NIM_MODEL = "nvidia/llama-3.1-nemotron-70b-instruct"
# NOTE: this URL differs from jarvis_ear.py's ZEN_URL (opencode.ai/zen) — unverified
# whether that's intentional (a distillation-specific endpoint) or stale; left as-is.
ZEN_URL = "https://api.zen-llm.com/v1/chat/completions"
ZEN_KEY = os.environ.get("OPENCODE_ZEN_KEY", "")
FAST_MODEL = "meta-llama/llama-4-scout-17b-16e-instruct"

# ── Knowledge Graph Schema ───────────────────────────────────────────────────
_KG_SCHEMA = """
CREATE TABLE IF NOT EXISTS entities (
    name TEXT PRIMARY KEY,
    type TEXT,              -- person, project, tool, concept, location
    properties TEXT,        -- JSON properties
    last_seen INTEGER,
    mention_count INTEGER DEFAULT 1
);
CREATE TABLE IF NOT EXISTS relations (
    source TEXT,
    target TEXT,
    relation TEXT,          -- works_on, uses, mentioned_in, prefers
    context TEXT,
    weight REAL DEFAULT 1.0,
    last_seen INTEGER,
    PRIMARY KEY (source, target, relation)
);
CREATE TABLE IF NOT EXISTS facts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    text TEXT NOT NULL,
    entities TEXT,          -- JSON list of entity names
    source TEXT,            -- 'conversation', 'vault', 'context'
    confidence REAL DEFAULT 0.8,
    created_at INTEGER,
    UNIQUE(text)
);
"""

def _get_session():
    global SESSION
    if SESSION is None:
        import requests
        SESSION = requests.Session()
    return SESSION

class Nemori:
    def __init__(self):
        os.makedirs(os.path.dirname(KB_PATH), exist_ok=True)
        self.conn = sqlite3.connect(KB_PATH)
        self.conn.executescript(_KG_SCHEMA)
        self.conn.execute("PRAGMA journal_mode=WAL")
        os.makedirs(VAULT_MEMORY, exist_ok=True)

    def _call_llm(self, prompt: str, max_tokens: int = 1000) -> str:
        """Call LLM with fallback chain."""
        s = _get_session()
        for url, key, model in ((NIM_URL, NIM_KEY, NIM_MODEL),
                                 (ZEN_URL, ZEN_KEY, FAST_MODEL)):
            if not key:
                continue
            try:
                r = s.post(url, json={
                    "model": model,
                    "max_tokens": max_tokens,
                    "messages": [{"role": "user", "content": prompt}]
                }, headers={"Authorization": f"Bearer {key}"}, timeout=30)
                return (r.json()["choices"][0]["message"].get("content") or "").strip()
            except Exception as e:
                continue
        return ""

    def extract_entities(self, text: str) -> list[dict]:
        """Extract entities (people, projects, tools, concepts) from text."""
        prompt = (
            "Extract named entities from this text. Return JSON array with objects "
            "having 'name' (string), 'type' (person/project/tool/concept/location), "
            "and 'properties' (object with relevant details). "
            "Only include clearly named entities. Return empty array if none found.\n\n"
            f"TEXT: {text[:3000]}"
        )
        raw = self._call_llm(prompt, max_tokens=500)
        try:
            # Try to extract JSON from response
            match = re.search(r'\[.*\]', raw, re.DOTALL)
            if match:
                return json.loads(match.group())
        except:
            pass
        return []

    def extract_facts(self, text: str) -> list[str]:
        """Extract lasting facts from conversation."""
        prompt = (
            "From this conversation, extract NEW lasting facts worth remembering. "
            "Include: user preferences, project updates, corrections, important names, "
            "deadlines, tool configurations. Exclude small talk and one-off questions.\n"
            "Reply ONLY with '- ' bullet lines, or exactly NONE.\n\n"
            f"CONVERSATION:\n{text[:4000]}"
        )
        raw = self._call_llm(prompt, max_tokens=800)
        bullets = [l.strip() for l in raw.splitlines()
                   if l.strip().startswith("- ")]
        return bullets if not raw.upper().startswith("NONE") else []

    def extract_relations(self, text: str, entities: list[dict]) -> list[dict]:
        """Extract relationships between entities."""
        if len(entities) < 2:
            return []
        entity_names = [e["name"] for e in entities[:10]]
        prompt = (
            f"Given these entities: {', '.join(entity_names)}\n"
            "Extract relationships between them from the text. "
            "Return JSON array with objects: {'source': name, 'target': name, "
            "'relation': verb phrase, 'context': brief explanation}.\n"
            "Only include clear relationships. Return empty array if none.\n\n"
            f"TEXT: {text[:3000]}"
        )
        raw = self._call_llm(prompt, max_tokens=500)
        try:
            match = re.search(r'\[.*\]', raw, re.DOTALL)
            if match:
                return json.loads(match.group())
        except:
            pass
        return []

    def distill(self, messages: list[dict], existing_memory: str = "") -> dict:
        """Main distillation pipeline. Extracts facts, entities, relations."""
        if not messages:
            return {"facts": [], "entities": [], "relations": []}

        convo = "\n".join(f"{m['role']}: {m['content']}" for m in messages[-12:])
        now = int(time.time())

        # 1. Extract facts
        facts = self.extract_facts(convo)
        new_facts = [f for f in facts if f not in existing_memory]

        # 2. Extract entities and relations
        entities = self.extract_entities(convo)
        relations = self.extract_relations(convo, entities)

        # 3. Store in knowledge graph
        for ent in entities:
            self.conn.execute(
                "INSERT OR REPLACE INTO entities (name, type, properties, last_seen, mention_count) "
                "VALUES (?, ?, ?, ?, COALESCE((SELECT mention_count FROM entities WHERE name = ?) + 1, 1))",
                (ent["name"], ent.get("type", "concept"),
                 json.dumps(ent.get("properties", {})), now, ent["name"])
            )

        for rel in relations:
            self.conn.execute(
                "INSERT OR REPLACE INTO relations (source, target, relation, context, weight, last_seen) "
                "VALUES (?, ?, ?, ?, 1.0, ?)",
                (rel["source"], rel["target"], rel.get("relation", "related"),
                 rel.get("context", ""), now)
            )

        for fact in new_facts:
            ent_names = [e["name"] for e in entities]
            self.conn.execute(
                "INSERT OR IGNORE INTO facts (text, entities, source, confidence, created_at) "
                "VALUES (?, ?, 'conversation', 0.8, ?)",
                (fact, json.dumps(ent_names), now)
            )

        self.conn.commit()

        # 4. Write new facts to voice-memory.md
        if new_facts:
            with open(MEMORY_FILE, "a") as f:
                f.write("\n" + "\n".join(new_facts))

        return {
            "facts": new_facts,
            "entities": entities,
            "relations": relations,
        }

    def save_vault_note(self, title: str, content: str, tags: list[str] = None):
        """Save a structured note to Obsidian vault."""
        tag_str = "\n".join(f"  - {t}" for t in (tags or []))
        frontmatter = f"""---
created: {time.strftime('%Y-%m-%d')}
tags:
{tag_str}
---
"""
        path = os.path.join(VAULT_MEMORY, f"{title}.md")
        with open(path, "w") as f:
            f.write(frontmatter + content)

    def stats(self) -> dict:
        entities = self.conn.execute("SELECT COUNT(*) FROM entities").fetchone()[0]
        relations = self.conn.execute("SELECT COUNT(*) FROM relations").fetchone()[0]
        facts = self.conn.execute("SELECT COUNT(*) FROM facts").fetchone()[0]
        return {
            "entities": entities,
            "relations": relations,
            "facts": facts,
            "kb_size_kb": round(os.path.getsize(KB_PATH) / 1024, 1) if os.path.exists(KB_PATH) else 0,
        }

    def get_entity(self, name: str) -> dict:
        row = self.conn.execute(
            "SELECT name, type, properties, last_seen, mention_count FROM entities WHERE name = ?",
            (name,)
        ).fetchone()
        if not row:
            return None
        return {
            "name": row[0], "type": row[1], "properties": json.loads(row[2]),
            "last_seen": row[3], "mention_count": row[4],
        }

    def get_related(self, name: str) -> list[dict]:
        rows = self.conn.execute(
            "SELECT target, relation, context FROM relations WHERE source = ? "
            "UNION ALL "
            "SELECT source, relation, context FROM relations WHERE target = ?",
            (name, name)
        ).fetchall()
        return [{"name": r[0], "relation": r[1], "context": r[2]} for r in rows]

    def search_facts(self, query: str, limit: int = 5) -> list[dict]:
        rows = self.conn.execute(
            "SELECT text, entities, confidence FROM facts "
            "WHERE text LIKE ? ORDER BY confidence DESC LIMIT ?",
            (f"%{query}%", limit)
        ).fetchall()
        return [{"text": r[0], "entities": json.loads(r[1]), "confidence": r[2]} for r in rows]


# ── CLI ───────────────────────────────────────────────────────────────────────
def main():
    nemori = Nemori()
    if len(sys.argv) < 2:
        print("Usage: python jarvis_nemori.py [stats|test]")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "stats":
        print(json.dumps(nemori.stats(), indent=2))
    elif cmd == "test":
        # Test with sample conversation
        test_msgs = [
            {"role": "user", "content": "Jarvis, add market watch to my daily briefing at 9am"},
            {"role": "assistant", "content": "Done sir. Market Watch skill will run at 9am daily."},
        ]
        result = nemori.distill(test_msgs)
        print(json.dumps(result, indent=2))
    else:
        print(f"Unknown command: {cmd}")

if __name__ == "__main__":
    import sys
    main()
