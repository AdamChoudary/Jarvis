#!/usr/bin/env python3
"""ActivityWatch integration for Jarvis — query usage data from the AW server.

Usage:
    from jarvis_voice.jarvis_aw import ActivityWatch
    aw = ActivityWatch()
    print(aw.today_summary())
    print(aw.top_apps(hours=4))
    print(aw.focus_score())
"""
import json, os, time, urllib.request
from datetime import datetime, timedelta, timezone
from collections import Counter

AW_URL = "http://localhost:5600/api/0"

class ActivityWatch:
    def __init__(self, base_url=AW_URL):
        self.base_url = base_url

    def _get(self, path):
        try:
            req = urllib.request.Request(f"{self.base_url}{path}")
            with urllib.request.urlopen(req, timeout=5) as r:
                return json.loads(r.read())
        except Exception:
            return None

    def is_running(self):
        return self._get("/buckets/") is not None

    def buckets(self):
        return self._get("/buckets/") or {}

    def events(self, bucket_id, start=None, end=None, limit=10000):
        if start is None:
            start = (datetime.now(timezone.utc) - timedelta(hours=24)).strftime("%Y-%m-%dT%H:%M:%S.%f+00:00")
        if end is None:
            end = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f+00:00")
        params = f"?start={start}&end={end}&limit={limit}"
        return self._get(f"/buckets/{bucket_id}/events{params}") or []

    def _window_events(self, hours=24):
        buckets = self.buckets()
        for bid in buckets:
            if "window" in bid:
                start = (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat()
                return self.events(bid, start=start)
        return []

    def _afk_events(self, hours=24):
        buckets = self.buckets()
        for bid in buckets:
            if "afk" in bid:
                start = (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat()
                return self.events(bid, start=start)
        return []

    def top_apps(self, hours=4):
        """Get most-used applications in the last N hours."""
        events = self._window_events(hours)
        app_time = Counter()
        for e in events:
            data = e.get("data", {})
            app = data.get("app", "unknown")
            dur = e.get("duration", 0)
            app_time[app] += dur
        total = sum(app_time.values()) or 1
        return [(app, round(dur / 60, 1), round(dur / total * 100, 1))
                for app, dur in app_time.most_common(10)]

    def focus_score(self, hours=4):
        """0-100 score: % of time in the top app (proxy for focus)."""
        events = self._window_events(hours)
        app_time = Counter()
        for e in events:
            app = e.get("data", {}).get("app", "unknown")
            dur = e.get("duration", 0)
            app_time[app] += dur
        if not app_time:
            return 0
        top_dur = app_time.most_common(1)[0][1]
        total = sum(app_time.values())
        return round(top_dur / total * 100) if total else 0

    def active_hours(self, hours=24):
        """How many minutes were active (not AFK) in the last N hours."""
        events = self._afk_events(hours)
        active_secs = 0
        for e in events:
            data = e.get("data", {})
            if not data.get("status", "").startswith("afk"):
                active_secs += e.get("duration", 0)
        return round(active_secs / 60, 1)

    def today_summary(self):
        """Human-readable summary of today's usage."""
        top = self.top_apps(hours=8)
        focus = self.focus_score(hours=8)
        active = self.active_hours(hours=24)
        lines = [f"Focus score: {focus}/100", f"Active today: {active:.0f} min"]
        if top:
            lines.append("Top apps:")
            for app, mins, pct in top[:5]:
                lines.append(f"  {app}: {mins:.0f}m ({pct}%)")
        return "\n".join(lines)

    def context_for_memory(self, hours=4):
        """Generate a memory context string for injection into Jarvis prompts."""
        top = self.top_apps(hours)
        focus = self.focus_score(hours)
        if not top:
            return ""
        apps = ", ".join(f"{a} ({m:.0f}m)" for a, m, _ in top[:3])
        return f"Recent activity: focus={focus}/100, apps: {apps}"


if __name__ == "__main__":
    aw = ActivityWatch()
    if not aw.is_running():
        print("ActivityWatch is not running. Start with: ~/.hermes/activitywatch/aw-server/aw-server --port 5600")
        exit(1)
    print(aw.today_summary())
