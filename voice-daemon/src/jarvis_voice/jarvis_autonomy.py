#!/usr/bin/env python3
"""Jarvis Autonomy — Proactive triggers, self-improvement, and health monitoring.

Components:
  1. TGL (Trigger Generation Layer) — decides when to speak unprompted
  2. SkillOpt — monitors skill performance and suggests improvements
  3. Health Monitor — predictive failure detection and tiered recovery

Usage:
    from jarvis_voice.jarvis_autonomy import AutonomyEngine
    aut = AutonomyEngine()
    triggers = aut.check_triggers()
    health = aut.health_check()
"""
import json, os, sqlite3, time
from pathlib import Path
from collections import defaultdict

HOME = os.path.expanduser("~")
AUTONOMY_DB = os.path.join(HOME, ".hermes", "jarvis-voice", "autonomy.db")
SKILLS_DIR = os.path.join(HOME, ".hermes", "skills")

# ── TGL: Trigger Generation Layer ───────────────────────────────────────────
class TriggerEngine:
    """Decides when Jarvis should speak unprompted."""

    TRIGGER_TYPES = {
        "daily_brief": {"time": "09:00", "cooldown_hours": 24},
        "market_update": {"time": "09:30", "cooldown_hours": 24},
        "evening_debrief": {"time": "20:00", "cooldown_hours": 24},
        "reminder": {"cooldown_hours": 1},
        "anomaly": {"cooldown_hours": 0.5},
        "idle_check": {"cooldown_hours": 4},
    }

    def __init__(self):
        os.makedirs(os.path.dirname(AUTONOMY_DB), exist_ok=True)
        self.conn = sqlite3.connect(AUTONOMY_DB)
        self.conn.executescript("""
            CREATE TABLE IF NOT EXISTS trigger_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                trigger_type TEXT,
                fired_at INTEGER,
                context TEXT,
                response TEXT
            );
            CREATE TABLE IF NOT EXISTS skill_perf (
                skill_name TEXT,
                call_count INTEGER DEFAULT 0,
                success_count INTEGER DEFAULT 0,
                avg_latency_ms REAL DEFAULT 0,
                last_called INTEGER,
                PRIMARY KEY (skill_name)
            );
        """)

    def should_fire(self, trigger_type: str) -> bool:
        """Check if a trigger should fire based on cooldown and time."""
        now = time.time()
        config = self.TRIGGER_TYPES.get(trigger_type, {})

        # Time-based triggers
        if "time" in config:
            target_h, target_m = map(int, config["time"].split(":"))
            current = time.localtime()
            if current.tm_hour != target_h or abs(current.tm_min - target_m) > 5:
                return False

        # Cooldown check
        cooldown = config.get("cooldown_hours", 1) * 3600
        last = self.conn.execute(
            "SELECT fired_at FROM trigger_log WHERE trigger_type = ? "
            "ORDER BY fired_at DESC LIMIT 1",
            (trigger_type,)
        ).fetchone()
        if last and now - last[0] < cooldown:
            return False

        return True

    def fire(self, trigger_type: str, context: str = ""):
        """Record a trigger fire."""
        self.conn.execute(
            "INSERT INTO trigger_log (trigger_type, fired_at, context) VALUES (?, ?, ?)",
            (trigger_type, int(time.time()), context)
        )
        self.conn.commit()

    def get_pending_triggers(self) -> list[dict]:
        """Check all trigger types and return pending ones."""
        pending = []
        for trigger_type in self.TRIGGER_TYPES:
            if self.should_fire(trigger_type):
                pending.append({
                    "type": trigger_type,
                    "config": self.TRIGGER_TYPES[trigger_type],
                })
        return pending


# ── SkillOpt: Self-improvement Lifecycle ─────────────────────────────────────
class SkillOptimizer:
    """Monitors skill performance and suggests improvements."""

    def __init__(self):
        os.makedirs(os.path.dirname(AUTONOMY_DB), exist_ok=True)
        self.conn = sqlite3.connect(AUTONOMY_DB)

    def record_call(self, skill_name: str, success: bool, latency_ms: float):
        """Record a skill call for performance tracking."""
        now = int(time.time())
        row = self.conn.execute(
            "SELECT call_count, success_count, avg_latency_ms FROM skill_perf WHERE skill_name = ?",
            (skill_name,)
        ).fetchone()

        if row:
            calls, successes, avg_lat = row
            new_calls = calls + 1
            new_successes = successes + (1 if success else 0)
            new_avg = (avg_lat * calls + latency_ms) / new_calls
            self.conn.execute(
                "UPDATE skill_perf SET call_count = ?, success_count = ?, "
                "avg_latency_ms = ?, last_called = ? WHERE skill_name = ?",
                (new_calls, new_successes, new_avg, now, skill_name)
            )
        else:
            self.conn.execute(
                "INSERT INTO skill_perf (skill_name, call_count, success_count, "
                "avg_latency_ms, last_called) VALUES (?, 1, ?, ?, ?)",
                (skill_name, 1 if success else 0, latency_ms, now)
            )
        self.conn.commit()

    def get_slow_skills(self, threshold_ms: float = 5000) -> list[dict]:
        """Find skills with high latency."""
        rows = self.conn.execute(
            "SELECT skill_name, avg_latency_ms, call_count FROM skill_perf "
            "WHERE avg_latency_ms > ? ORDER BY avg_latency_ms DESC",
            (threshold_ms,)
        ).fetchall()
        return [{"name": r[0], "avg_ms": r[1], "calls": r[2]} for r in rows]

    def get_failing_skills(self, min_calls: int = 5) -> list[dict]:
        """Find skills with low success rates."""
        rows = self.conn.execute(
            "SELECT skill_name, success_count, call_count FROM skill_perf "
            "WHERE call_count >= ? AND (success_count * 1.0 / call_count) < 0.8 "
            "ORDER BY (success_count * 1.0 / call_count) ASC",
            (min_calls,)
        ).fetchall()
        return [{"name": r[0], "success_rate": r[1]/r[2], "calls": r[2]} for r in rows]

    def suggest_improvements(self) -> list[str]:
        """Generate improvement suggestions based on performance data."""
        suggestions = []

        slow = self.get_slow_skills()
        for s in slow:
            suggestions.append(f"Optimize {s['name']}: avg {s['avg_ms']:.0f}ms over {s['calls']} calls")

        failing = self.get_failing_skills()
        for f in failing:
            suggestions.append(f"Fix {f['name']}: {f['success_rate']:.0%} success rate over {f['calls']} calls")

        return suggestions


# ── Health Monitor ───────────────────────────────────────────────────────────
class HealthMonitor:
    """Predictive failure detection and tiered recovery."""

    def __init__(self):
        self.checks = []

    def check_daemon(self, name: str, pid_file: str) -> dict:
        """Check if a daemon is running."""
        running = False
        pid = None
        try:
            if os.path.exists(pid_file):
                pid = int(open(pid_file).read().strip())
                os.kill(pid, 0)  # Check if process exists
                running = True
        except (ValueError, ProcessLookupError, PermissionError):
            pass
        return {"name": name, "running": running, "pid": pid}

    def check_disk(self) -> dict:
        """Check disk usage."""
        import shutil
        total, used, free = shutil.disk_usage(HOME)
        pct = used / total * 100
        return {
            "total_gb": round(total / (1024**3), 1),
            "used_gb": round(used / (1024**3), 1),
            "free_gb": round(free / (1024**3), 1),
            "pct_used": round(pct, 1),
            "warning": pct > 90,
        }

    def check_memory(self) -> dict:
        """Check memory usage."""
        import subprocess
        try:
            result = subprocess.run(
                ["vm_stat"], capture_output=True, text=True, timeout=5
            )
            lines = result.stdout.split("\n")
            stats = {}
            for line in lines:
                if "Pages active" in line:
                    pages = int(line.split(":")[1].strip().rstrip("."))
                    stats["active_mb"] = round(pages * 4096 / (1024**2))
                elif "Pages free" in line:
                    pages = int(line.split(":")[1].strip().rstrip("."))
                    stats["free_mb"] = round(pages * 4096 / (1024**2))
            return stats
        except:
            return {"error": "vm_stat failed"}

    def check_db_health(self, db_path: str) -> dict:
        """Check SQLite database health."""
        if not os.path.exists(db_path):
            return {"exists": False}
        try:
            conn = sqlite3.connect(db_path)
            result = conn.execute("PRAGMA integrity_check").fetchone()
            size = os.path.getsize(db_path)
            conn.close()
            return {
                "exists": True,
                "integrity": result[0] if result else "unknown",
                "size_mb": round(size / (1024**2), 2),
            }
        except Exception as e:
            return {"exists": True, "error": str(e)}

    def full_check(self) -> dict:
        """Run all health checks."""
        return {
            "daemon_jarvis": self.check_daemon(
                "jarvis", os.path.expanduser("~/.hermes/jarvis-voice/jarvis.pid")
            ),
            "daemon_activitywatch": self.check_daemon(
                "activitywatch", os.path.expanduser("~/.hermes/activitywatch/aw-server.pid")
            ),
            "disk": self.check_disk(),
            "memory": self.check_memory(),
            "memory_db": self.check_db_health(
                os.path.expanduser("~/.hermes/jarvis-voice/jarvis-memory-v7.db")
            ),
            "knowledge_graph": self.check_db_health(
                os.path.expanduser("~/.hermes/jarvis-voice/knowledge-graph.db")
            ),
        }


# ── Autonomy Engine (unified) ───────────────────────────────────────────────
class AutonomyEngine:
    """Unified autonomy layer for Jarvis."""

    def __init__(self):
        self.triggers = TriggerEngine()
        self.skill_opt = SkillOptimizer()
        self.health = HealthMonitor()

    def check_triggers(self) -> list[dict]:
        """Check and return pending triggers."""
        return self.triggers.get_pending_triggers()

    def health_check(self) -> dict:
        """Run full health check."""
        return self.health.full_check()

    def get_suggestions(self) -> list[str]:
        """Get improvement suggestions."""
        return self.skill_opt.suggest_improvements()

    def record_skill(self, name: str, success: bool, latency_ms: float):
        """Record a skill call."""
        self.skill_opt.record_call(name, success, latency_ms)


# ── CLI ───────────────────────────────────────────────────────────────────────
def main():
    import sys
    aut = AutonomyEngine()
    if len(sys.argv) < 2:
        print("Usage: python jarvis_autonomy.py [triggers|health|suggestions]")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "triggers":
        pending = aut.check_triggers()
        print(json.dumps(pending, indent=2))
    elif cmd == "health":
        health = aut.health_check()
        print(json.dumps(health, indent=2))
    elif cmd == "suggestions":
        suggestions = aut.get_suggestions()
        for s in suggestions:
            print(f"- {s}")
        if not suggestions:
            print("No suggestions - all systems optimal")
    else:
        print(f"Unknown command: {cmd}")

if __name__ == "__main__":
    main()
