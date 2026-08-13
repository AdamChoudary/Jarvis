# Jarvis — Complete Feature Inventory (v7.2, 2026-07-19)

Item 1 of Sir's mandate: every feature, functionality, and quality Jarvis currently has.
Sibling docs: AUDIT-TODO.md (item 2) · POLISH-TODO.md (item 3) · ARCHITECTURE.md · JARVIS-MASTER-CONTEXT.md

## A. Voice input (the ear)
1. **Wake word** — "Hey Jarvis" via openWakeWord (hey_jarvis onnx), 2-frame confirmation.
2. **Mention trigger** — say "Jarvis"/"Assistant" ANYWHERE in speech: Silero-VAD segments every utterance, whisper transcribes, fuzzy name match (accent variants + difflib) decides.
3. **STT** — mlx-whisper on M1 GPU (base model, `JARVIS_WHISPER_MODEL` dial), faster-whisper CPU fallback, English-pinned (accent-safety), MLX cache cleared per call.
4. **Noise suppression** — GTCRN denoiser (onnx) applied pre-transcription.
5. **Speaker recognition** — TitaNet embeddings: enrolled Sir vs guest vs open mode; guided voice enrollment ("learn my voice"); per-speaker access control.
6. **Emotional ear** — SenseVoice: emotion tags (happy/angry/tired…) + audio events (laughter, sigh) → `[voice analysis]` note biases replies; mood-log.jsonl trend.
7. **Conversation window** — 45s renewing follow-up window, no re-trigger needed; dismissal phrases ("thank you Jarvis", "go to sleep"); SILENCE sentinel keeps listening when speech isn't addressed to him.

## B. Brains (reply generation)
8. **Fast lane** — unified streaming chain: NIM nemotron (/no_think) → Zen north-mini → LOCAL Qwen2.5-3B (MLX, offline floor, proven organically). 6s first-token deadline per brain; empty-reply guard; persistent HTTP session (verified 38% faster consecutive calls).
9. **Agent lane** — full Hermes agent via gateway API server (terminal/files/web/browser, 136 skills); auto-escalation via AGENT sentinel; protocol keywords route directly.
10. **Guest lane** — restricted persona for unrecognized voices: chat only, no device access, no personal info.
11. **Persona** — J.A.R.V.I.S.-modeled butler (SOUL.md): dry wit, "Sir", READ-THE-HUMAN rules (venting→empathy, thinking-aloud→space, correction etiquette), tone-adaptive to voice analysis.

## C. Voice output (the mouth)
12. **TTS chain** — Edge (en-GB-Ryan, primary) → Kokoro local onnx (bm_george) → macOS say; per-sentence retry + timeout; in-process async edge.
13. **Sentence pipelining** — sentence N plays while N+1 synthesizes; LLM streams sentences to TTS mid-generation.
14. **Expressive delivery** — [tone:brisk|warm|amused|grave] directives → real rate/pitch/speed changes; ack + thinking + still-on phrase pools (pre-synthesized, randomized).
15. **Thinking narration** — 2.5s dead-air → "One moment, sir"; 12s intervals → "Still on it" (anti-ghosting).
16. **Echo protection** — playback-aware wait + queue drain (daemon never hears its own voice); pipecat mode has latched EchoGate + barge-in flag.

## D. Memory & knowledge
17. **Semantic memory index** — FTS5 + sentence-transformers embeddings + RRF hybrid over Claude transcripts, opencode sessions, Context files, vault (319 docs); auto-injected into every fast-lane prompt; background rebuild at boot.
18. **Voice memory** — voice-memory.md facts injected into persona; idle-time distillation (10min) extracts new facts via LLM.
19. **Knowledge graph** — Nemori distillation (entities/relations/facts → knowledge-graph.db) + LightRAG traversal/context injection.
20. **Conversation history** — rolling 24-message window, disk-persisted, bounded in-memory.
21. **`/where-was-i`** — engineer-grade 4-source project status (git + context files + Claude sessions + opencode DB).

## E. Autonomy & scheduling
22. **6 cron routines** — morning-briefing 08:30, market-watch 08:00, client-radar 09:15, sentry hourly, debrief 22:00, weekly-review Sun 18:00 (gateway-scheduled, drain-protected).
23. **Announce lane** — any process drops .txt → spoken when idle; quiet hours 23:00-08:00.
24. **Autonomy engine** — TGL triggers, SkillOpt monitoring, health checks (jarvis_autonomy.py).
25. **Self-maintenance** — RAM self-monitoring (capped ram-log.jsonl), 2.5GB emergency backstop restart, 3am nightly housekeeping restart (exit-75/launchd), announce-after-restart; sentry reads the trend.

## F. Skills & protocols (136 total via Hermes)
26. **8 hand-built protocols** — morning-briefing, ship-it, house-party (subagent fleet), debrief, sentry-mode, ghost-protocol, clean-slate (typed-confirm), red-alert.
27. **Chief-of-staff tier** — decision-brief, devils-advocate, premortem, first-principles, weekly-review, calendar-steward, meeting-prep/debrief, inbox-triage, commitment-tracker, project-manager, idea lifecycle, learning-coach, finance-pulse.
28. **Imported methodology** — superpowers (brainstorming, systematic-debugging, TDD, verification…), ponytail (×4 + SOUL default), Anthropic doc suite (pdf/docx/xlsx/pptx), full Claude Code design-skill collection, ui-ux-pro-max.

## G. Knowledge organization (Obsidian)
29. **Four-area vault** — Projects/ Ideas/ (lifecycle) Planning/<parent>/ Research/, wikilinked lineage, canvases, Dataview dashboards, Home command center.
30. **Context system** — ~/Developer/Context/ per-session files + CONTEXT-INDEX master map; written after every meaningful session.

## H. Infrastructure qualities
31. **Resilience** — crash-hardened hear() paths (proven: survived a real onnx bug), launchd KeepAlive, TTS/LLM fallback chains, cron drain timeout, gateway supervision.
32. **Free-tier stack** — $0 total: Zen/NIM free models, all-local voice models, Edge TTS free.
33. **Security posture** — keys in .env (600) not source, guest access control, voice≠auth rule (destructive = typed confirm), announce-lane quiet hours, skill audits.
34. **Multi-interface** — voice daemon, `jarvis-chat` (pipecat conversation mode), `hermes` CLI/TUI, gateway API :8642 (OpenAI-compatible), messaging-ready (Telegram token pending).
35. **Self-observability** — ear.log, ram-log.jsonl, mood-log.jsonl, brain.log, autonomy.db, cron output archives, git-versioned code (as of today).
