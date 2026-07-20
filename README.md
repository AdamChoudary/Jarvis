# Jarvis

Project hub for the always-on Mac voice assistant and everything around it.

```
Jarvis/
├── voice-daemon -> ~/.hermes/jarvis-voice   the live daemon (symlink, see below)
├── dashboard/                               native SwiftUI Mac app
├── reference/                               four public Jarvis projects, for study
├── JARVIS-LANDSCAPE.md                      what they have, how their UIs are built
└── IMPLEMENTATION-PLAN.md                   what we port, in what order
```

## Why voice-daemon is a symlink

`~/.hermes/jarvis-voice` is running right now under launchd (`com.jarvis.ear`), and the
plist references that absolute path. Moving it would take the assistant offline until the
plist was rewritten and reloaded. It is linked instead, so the whole project is navigable
from one place without touching a live service. It is a full git repository in its own
right.

## The two components

**voice-daemon** — Python. openWakeWord + Silero VAD + mlx-whisper for hearing,
SenseVoice for emotion, TitaNet for speaker ID, a NIM/Zen/local-Qwen brain chain,
Edge-TTS/Kokoro/say for speech. Barge-in, self-restart on memory pressure, dead-audio-
stream recovery. Run `python jarvis_ear.py --selftest` to check it end to end.

**dashboard** — SwiftUI, built with Swift Package Manager (no Xcode project, since this
machine has only the Command Line Tools). `./build-app.sh` produces
`~/Applications/Jarvis.app`: 804KB binary, ~1.8% CPU idle. Five tabs: the orrery memory
view, activity, source browser, architecture docs, and settings. Reads Jarvis's real
state directly off disk, read-only, no server.

## reference/

Shallow clones taken 2026-07-20, kept for study only. Nothing here is a dependency.

- `sukeesh-jarvis` — CLI plugin assistant, deliberately non-AI, huge task breadth
- `isair-jarvis` — 100% local voice AI, PyQt6 + Flask, the best architecture of the four
- `ethanplusai-jarvis` — Mac butler with a Three.js orb and a click-through desktop overlay
- `openjarvis` — Stanford local-first framework, Tauri + React + Rust

See `JARVIS-LANDSCAPE.md` for the full analysis.
