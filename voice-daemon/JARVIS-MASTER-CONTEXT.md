# JARVIS MASTER CONTEXT — the one file that ties everything (item 7)

Read this first in any future session about Jarvis. Everything below is load-bearing.

## Code & runtime
- Project repo: `~/.hermes/jarvis-voice/` (git). Daemon: jarvis_ear.py. Modules per ARCHITECTURE.md.
- launchd: com.jarvis.ear (daemon) · ai.hermes.gateway (cron+API) · com.jarvis.activitywatch.
- Hermes: `~/.hermes/hermes-agent` (framework+venv) · SOUL.md (persona) · config.yaml/.env · skills/ (136).

## Decision history (chronological, in ~/Developer/Context/)
2026-07-17: jarvis-setup → deep-dive research → maxout-roadmap → enhancement-build →
latency-optimization → human-processing (H1-H5) → chief-of-staff-skills → trigger-fix →
session-mining. 2026-07-18: lightweight-architecture (council r1, Wave 1) → cron-audit →
speed-async-refinement. 2026-07-19: v7-build (external session) → sustained-ram-verdict
(council r2 chaired) → streaming-deadline → THIS session (unified-memory fix + org).

## Council governance (the rules currently in force)
- Never idle-unload wake/VAD/whisper. Waterfall gate ships at 48h soak (~07-20). Idle-unload
  timer conditional on post-gate re-baseline. Restarts must exit non-zero (75). Measure memory
  with `footprint`, not ps. Full verdicts: council-synthesis.json, council-round2-reports.txt.

## Quality program
- JARVIS-FEATURES.md = the 35-feature inventory. AUDIT-TODO.md = feature-by-feature
  best-practice checks. POLISH-TODO.md = ranked fixes (P0: barge-in, instant-trigger feel,
  response time, hallucination classes).

## Knowledge & vault
- Vault `~/Documents/Obsidian Vault/Jarvis/`: Home.md (status+dashboards), Projects/, Ideas/
  (lifecycle), Planning/<parent>/, Research/. Dataview installed.
- Memory DBs (this folder): jarvis-memory-v7.db, knowledge-graph.db, autonomy.db.
- `~/Developer/Context/CONTEXT-INDEX.md` = all ~45 dev projects mapped.

## Known state (2026-07-19 evening)
- Unified memory footprint: 2389MB (was 5078 — turbo whisper was eating 3.5GB Metal).
- Free-tier turbulence: NIM degraded today (0.9s→23s); 6s first-token deadline protects.
- Local brain proven as offline floor. Sir's voice enrolled. Room often has TV noise
  (transcription hallucination source). Sir's pending items: Telegram token, automation
  permissions, client-radar domain confirmations.
