#!/usr/bin/env python3
"""Jarvis Dashboard data endpoint — read-only, localhost-only.

Serves the single-file dashboard HTML plus two JSON endpoints that read
directly from what already exists on disk (ram-log, ear.log, jobs.json, the
vault, the memory + knowledge-graph databases). No writes, no new stores.

Run: python3 dashboard_server.py [port]   (default 8765)
"""
import json
import os
import re
import sqlite3
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

DIR = os.path.dirname(os.path.abspath(__file__))
HOME = os.path.expanduser("~")
EAR_LOG = f"{DIR}/ear.log"
RAM_LOG = f"{DIR}/ram-log.jsonl"
MEMORY_DB = f"{DIR}/jarvis-memory-v7.db"
KG_DB = f"{DIR}/knowledge-graph.db"
CRON_JOBS = f"{HOME}/.hermes/cron/jobs.json"
VAULT_JARVIS = f'{HOME}/Documents/Obsidian Vault/Jarvis'
HTML_FILE = f"{DIR}/dashboard.html"

TS_RE = re.compile(r"^\[(\d{2}):(\d{2}):(\d{2})\] (.*)$")
LATENCY_START_RE = re.compile(r"^(Heard|Follow-up) ")
LATENCY_END_RE = re.compile(r"^(Reply|Guest reply): ")


def _hms_to_secs(h, m, s):
    return int(h) * 3600 + int(m) * 60 + int(s)


def _tail_lines(path, n=4000):
    try:
        with open(path, "r", errors="replace") as f:
            return f.readlines()[-n:]
    except FileNotFoundError:
        return []


def _daemon_pid():
    try:
        import psutil
        for p in psutil.process_iter(["pid", "cmdline"]):
            cmd = p.info.get("cmdline") or []
            if any("jarvis_ear.py" in c for c in cmd):
                return p.info["pid"]
    except Exception:
        pass
    return None


def _uptime_hours():
    pid = _daemon_pid()
    if not pid:
        return None
    try:
        import psutil
        return round((time.time() - psutil.Process(pid).create_time()) / 3600, 1)
    except Exception:
        return None


def _ram_trend():
    out = []
    for line in _tail_lines(RAM_LOG, 200):
        try:
            d = json.loads(line)
        except Exception:
            continue
        if "rss_mb" in d:
            out.append(d)
    return out[-60:]


def _log_stats():
    """Exchange count and brain-latency samples since the daemon's last boot,
    derived purely from adjacent timestamped lines already in ear.log — no
    new instrumentation needed."""
    lines = _tail_lines(EAR_LOG, 6000)
    boot_idx = 0
    for i, line in enumerate(lines):
        if "Jarvis ear v7 online" in line:
            boot_idx = i
    since_boot = lines[boot_idx:]

    exchange_count = 0
    latencies = []
    pending_start = None
    for line in since_boot:
        m = TS_RE.match(line.rstrip("\n"))
        if not m:
            continue
        h, mi, s, rest = m.groups()
        secs = _hms_to_secs(h, mi, s)
        if LATENCY_START_RE.match(rest):
            exchange_count += 1
            pending_start = secs
        elif LATENCY_END_RE.match(rest) and pending_start is not None:
            delta = secs - pending_start
            if 0 <= delta <= 120:
                latencies.append(delta)
            pending_start = None
    return {
        "exchanges_since_boot": exchange_count,
        "latency_samples_secs": latencies[-20:],
        "latency_last_secs": latencies[-1] if latencies else None,
    }


def _cron_jobs():
    try:
        d = json.load(open(CRON_JOBS))
    except Exception:
        return []
    out = []
    for j in d.get("jobs", []):
        out.append({
            "name": j.get("name"),
            "schedule": j.get("schedule_display"),
            "enabled": j.get("enabled"),
            "last_run_at": j.get("last_run_at"),
            "last_status": j.get("last_status"),
            "completed": (j.get("repeat") or {}).get("completed"),
        })
    return out


def _frontmatter(path):
    fm = {}
    try:
        lines = open(path, "r", errors="replace").readlines()
    except OSError:
        return fm
    if not lines or lines[0].strip() != "---":
        return fm
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if ":" in line:
            k, _, v = line.partition(":")
            fm[k.strip()] = v.strip().strip('"')
    return fm


def _vault_notes(subdir, exclude=("README.md",)):
    d = f"{VAULT_JARVIS}/{subdir}"
    out = []
    try:
        names = os.listdir(d)
    except OSError:
        return out
    for name in sorted(names):
        if name in exclude or not name.endswith(".md"):
            continue
        fm = _frontmatter(f"{d}/{name}")
        out.append({"name": name[:-3], **fm})
    return out


def _graph_snapshot():
    nodes, edges = [], []
    try:
        con = sqlite3.connect(f"file:{MEMORY_DB}?mode=ro", uri=True)
        for id_, source, title in con.execute(
                "SELECT id, source, title FROM docs ORDER BY updated_at DESC LIMIT 500"):
            nodes.append({"id": id_, "source": source, "title": title or id_, "kind": "doc"})
        con.close()
    except Exception:
        pass

    kg_entities, kg_relations = [], []
    try:
        con = sqlite3.connect(f"file:{KG_DB}?mode=ro", uri=True)
        for name, type_, mentions in con.execute(
                "SELECT name, type, mention_count FROM entities"):
            kg_entities.append({"id": f"kg:{name}", "name": name, "type": type_,
                                 "mentions": mentions, "kind": "entity"})
        for src, tgt, rel, weight in con.execute(
                "SELECT source, target, relation, weight FROM relations"):
            kg_relations.append({"source": f"kg:{src}", "target": f"kg:{tgt}",
                                  "relation": rel, "weight": weight})
        con.close()
    except Exception:
        pass

    return {"nodes": nodes, "edges": edges,
            "kg_entities": kg_entities, "kg_relations": kg_relations}


def _mood_arc():
    path = f"{DIR}/mood-log.jsonl"
    out = []
    for line in _tail_lines(path, 100):
        try:
            out.append(json.loads(line))
        except Exception:
            continue
    return out


def build_snapshot():
    log_stats = _log_stats()
    return {
        "generated_at": time.time(),
        "daemon_alive": _daemon_pid() is not None,
        "vitals": {
            "uptime_hours": _uptime_hours(),
            "ram_trend": _ram_trend(),
            "latency_last_secs": log_stats["latency_last_secs"],
            "latency_samples_secs": log_stats["latency_samples_secs"],
        },
        "today": {
            "exchanges_since_boot": log_stats["exchanges_since_boot"],
            "crons": _cron_jobs(),
            "mood_arc": _mood_arc(),
        },
        "projects": _vault_notes("Projects"),
        "ideas": _vault_notes("Ideas"),
        "graph": _graph_snapshot(),
    }


def get_doc(doc_id):
    try:
        con = sqlite3.connect(f"file:{MEMORY_DB}?mode=ro", uri=True)
        row = con.execute("SELECT id, source, title, path, content FROM docs WHERE id = ?",
                           (doc_id,)).fetchone()
        con.close()
    except Exception:
        return None
    if not row:
        return None
    id_, source, title, path, content = row
    return {"id": id_, "source": source, "title": title, "path": path,
            "content": (content or "")[:20000]}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # ear.log stays the one log; keep this endpoint quiet

    def _json(self, obj, status=200):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/" or parsed.path == "/dashboard.html":
            try:
                body = open(HTML_FILE, "rb").read()
            except FileNotFoundError:
                self.send_response(404)
                self.end_headers()
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif parsed.path == "/api/snapshot":
            self._json(build_snapshot())
        elif parsed.path == "/api/doc":
            qs = parse_qs(parsed.query)
            doc_id = (qs.get("id") or [""])[0]
            doc = get_doc(doc_id) if doc_id else None
            if doc is None:
                self._json({"error": "not found"}, status=404)
            else:
                self._json(doc)
        else:
            self.send_response(404)
            self.end_headers()


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"Jarvis dashboard: http://127.0.0.1:{port}/  (localhost-only, read-only)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
