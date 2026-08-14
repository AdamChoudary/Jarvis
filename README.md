# Jarvis

An always-listening, J.A.R.V.I.S.-style voice assistant for the Mac, plus a
native SwiftUI dashboard for watching it think.

Say "Hey Jarvis" (or just mention its name in conversation) and it wakes up,
transcribes locally, answers over a streaming cloud LLM chain with an offline
fallback, speaks back, and remembers the conversation — semantically indexed,
distilled into a knowledge graph, recalled only when actually relevant to what
you're currently saying.

## Components

| | |
|---|---|
| **[`voice-daemon/`](voice-daemon/)** | The daemon itself. Python. Wake word, ambient transcription, memory, replies. |
| **[`dashboard/`](dashboard/)** | Native macOS app (SwiftUI). Reads the daemon's real state straight off disk — no server. |

## Features

- **Wake word + name-mention trigger** — "Hey Jarvis" or just saying "Jarvis"/"Assistant" mid-conversation
- **Local speech recognition** — mlx-whisper (Apple Silicon), with an emotion-aware pass (SenseVoice) and speaker ID (TitaNet) to tell the owner's voice from guests'
- **Three-tier reasoning chain** — a fast cloud lane (OpenCode Zen), a stronger cloud lane (NVIDIA NIM), and a fully offline local model (MLX) if both cloud lanes are down
- **Reflex table** — instant, LLM-free answers for common questions (time, battery, etc.) so they don't pay for a network round trip
- **Semantic memory** — a searchable index (FTS + embeddings) over every past conversation, plus a knowledge-graph distillation pass (Nemori) that extracts durable facts instead of replaying raw transcripts
- **Recall gate** — memory is only injected into a reply when the current turn actually needs it, not on every single turn
- **Barge-in** — you can interrupt it mid-reply
- **Hold-to-dictate** — a system-wide hotkey that transcribes speech directly into whatever app has focus
- **Self-healing** — restarts itself under memory pressure or a dead audio stream, without needing you to notice

## Requirements

- **macOS**, Apple Silicon recommended (the local-model fallback and accelerated
  transcription use Apple's MLX framework, which needs it — the rest of the
  daemon runs fine on Intel too)
- **Python 3.11+**
- **Xcode 15+ / Swift 5.9+** (only if you're building the dashboard — the
  Command Line Tools alone are enough, no full Xcode project needed)
- **[ffmpeg](https://ffmpeg.org/)** and **[PortAudio](http://www.portaudio.com/)**
  (e.g. `brew install ffmpeg portaudio`)
- API keys for the cloud reasoning lanes: an **NVIDIA NIM** key
  ([build.nvidia.com](https://build.nvidia.com/)) and an **OpenCode Zen** key
  ([opencode.ai/zen](https://opencode.ai/zen)) — both have free tiers
- Several **local model files** (~600MB total: Kokoro TTS, Silero VAD, GTCRN,
  TitaNet, sherpa-onnx SenseVoice) that aren't bundled in this repo — see
  [`voice-daemon/README.md`](voice-daemon/README.md#models) for what's needed
- macOS permissions: **Microphone**, and **Accessibility** if you want
  hold-to-dictate

Full setup steps are in [`voice-daemon/README.md`](voice-daemon/README.md) and
[`dashboard/README.md`](dashboard/README.md).

## Project layout

```
Jarvis/
├── voice-daemon/         the daemon — see voice-daemon/README.md
│   ├── src/jarvis_voice/ the actual package
│   ├── tests/
│   ├── scripts/
│   └── pyproject.toml
├── dashboard/             the SwiftUI app — see dashboard/README.md
│   └── Sources/JarvisDashboard/
├── docs/dev-notes/       internal design/planning notes, kept for transparency
├── LICENSE
└── README.md              you are here
```

## License

[MIT](LICENSE)
