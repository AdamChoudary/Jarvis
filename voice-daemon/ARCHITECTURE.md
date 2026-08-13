# Jarvis Architecture (v7.2)

```
                                   ~/.hermes/jarvis-voice/  (THIS repo, git-versioned)
┌─────────────────────────────────────────────────────────────────────────┐
│  jarvis_ear.py  — THE DAEMON (launchd: com.jarvis.ear, KeepAlive)       │
│                                                                         │
│  mic 16kHz ──► ring buffer ──► openWakeWord ("Hey Jarvis")              │
│           └──► Silero VAD ──► segment ──► GTCRN denoise ──►             │
│                hear(): mlx-whisper + SenseVoice + TitaNet (HEAR_POOL)   │
│                  └► name_mentioned()? ──► conversation loop             │
│                                                                         │
│  dispatch ──► fast_lane: _llm_stream chain                              │
│    │            NIM ─6s deadline─► Zen ─► local Qwen (jarvis_brain.py)  │
│    │            + memory context (_memory_context ← jarvis_memory_v7)   │
│    ├──► agent_lane: gateway :8642 (full Hermes, 136 skills)             │
│    └──► guest_lane (unrecognized voices)                                │
│                                                                         │
│  Speaker ──► _synth chain: Edge ─► Kokoro ─► say  ──► afplay            │
│  idle branch ──► announcements · RAM guard (log/backstop/nightly) ·     │
│                  memory distillation                                    │
└─────────────────────────────────────────────────────────────────────────┘
   side modules: jarvis_memory_v7.py (FTS5+embeddings) · jarvis_nemori.py /
   jarvis_lightrag.py (knowledge graph) · jarvis_brain.py (local LLM) ·
   jarvis_autonomy.py (TGL/health) · jarvis_pipecat.py (conversation mode) ·
   jarvis_aw.py (ActivityWatch) · jarvis_voice_v7.py (component lib)

   separate processes: hermes gateway (launchd ai.hermes.gateway — cron ticker
   + API server) · ActivityWatch (com.jarvis.activitywatch)
```

## Data stores (all local)
| Store | What |
|---|---|
| jarvis-memory-v7.db | hybrid semantic index (319 docs) |
| knowledge-graph.db | entities/relations/facts |
| autonomy.db | trigger/health tracking |
| history.json / voice-memory.md / voices.json | conversation window / durable facts / speaker embeddings |
| ram-log.jsonl / mood-log.jsonl / ear.log / brain.log | observability |
| models/ | kokoro, sensevoice int8, titanet, silero-vad, gtcrn (~600MB) |

## Memory policy (council-governed)
- Tier-0 always resident: wake word, VAD, whisper(base-mlx + per-call cache clear), denoiser.
- Lazy: Kokoro (first Edge failure), local brain (cloud outage), sentence-transformers (first search).
- Guards: 2.5GB backstop restart (idle-gated, exit 75), 3am nightly restart, ram-log trend + sentry.
- HARD RULE: never idle-unload wake/VAD/whisper (mention trigger dies otherwise).
- Measure with `footprint <pid>` — ps rss is blind to Metal/unified memory.

## Where things run from
- launchd plists: `~/Library/LaunchAgents/com.jarvis.ear.plist`, `ai.hermes.gateway.plist`, `com.jarvis.activitywatch.plist`
- Hermes install: `~/.hermes/hermes-agent` (venv used by everything here)
- Skills: `~/.hermes/skills/` · Persona: `~/.hermes/SOUL.md` · Config: `~/.hermes/config.yaml` + `.env`
- Vault: `~/Documents/Obsidian Vault/Jarvis/` · Context: `~/Developer/Context/`
