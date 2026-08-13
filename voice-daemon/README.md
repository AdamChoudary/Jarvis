# Jarvis — personal voice AI for this Mac

J.A.R.V.I.S.-style always-on assistant: wake word + "say Jarvis anywhere" trigger, voice-recognized
owner vs guests, emotion-aware replies, streaming free-tier LLM chain with a local offline brain,
semantic memory over every past session, 136 skills, self-maintaining RAM policy. 100% free stack.

- **Start/stop**: `launchctl load|unload ~/Library/LaunchAgents/com.jarvis.ear.plist` (Ghost Protocol = unload)
- **Talk**: say "Hey Jarvis" or just mention "Jarvis"/"Assistant"; dismiss with "thank you Jarvis"
- **Test**: `venv python jarvis_ear.py --selftest` (14 checks)
- **Conversation mode**: `jarvis-chat` (pipecat, barge-in capable with headphones)
- **Docs**: ARCHITECTURE.md (how it works) · JARVIS-FEATURES.md (what it does) ·
  AUDIT-TODO.md / POLISH-TODO.md (quality program) · JARVIS-MASTER-CONTEXT.md (everything linked)

Built 2026-07-17→19 with a documented decision trail in `~/Developer/Context/2026-07-1*-jarvis-*.md`.
