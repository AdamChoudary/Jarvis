# Jarvis voice-daemon

The always-listening daemon: wake word, ambient transcription, a three-tier
reasoning chain, semantic memory, and spoken replies.

- **Talk**: say "Hey Jarvis" or just mention "Jarvis"/"Assistant" mid-sentence; dismiss with "thank you Jarvis"
- **Docs**: [`ARCHITECTURE.md`](ARCHITECTURE.md) (how it works) · [`JARVIS-FEATURES.md`](JARVIS-FEATURES.md) (what it does) · [`../docs/dev-notes/`](../docs/dev-notes/) (design/planning notes)

## Setup

1. **Create a venv and install the package** (from this directory):

   ```
   python3 -m venv .venv
   .venv/bin/pip install -e .
   # or, if you also want the optional open-channel conversation mode:
   .venv/bin/pip install -e ".[pipecat]"
   ```

2. **System dependencies** (Homebrew):

   ```
   brew install ffmpeg portaudio
   ```

3. **API keys**: copy [`.env.example`](.env.example) to `.env` and fill in an
   [NVIDIA NIM key](https://build.nvidia.com/) and an
   [OpenCode Zen key](https://opencode.ai/zen) (both free-tier). The daemon
   loads `.env` from its working directory — run it from this folder, or
   export the variables another way.

4. **Models** — see [Models](#models) below.

5. **macOS permissions** — System Settings → Privacy & Security:
   - **Microphone**, for obvious reasons
   - **Accessibility**, only if you want hold-to-dictate (`jarvis_dictation.py`'s
     system-wide hotkey) — you'll be prompted the first time it tries to
     install its event tap if this isn't granted

6. **Important: the daemon's working directory is hardcoded.** `jarvis_ear.py`
   resolves its data directory as `~/.hermes/jarvis-voice` (`DIR` near the top
   of the file) rather than relative to its own source location — a holdover
   from how this project runs on its original machine, not yet generalized.
   Either create that exact directory (with `models/` populated, per below)
   and run from there, or edit the `DIR` constant to point wherever you want
   the daemon's models/logs/databases to live.

## Models

Not bundled in this repo (~600MB, and they're binary model weights, not
source). Place them under `<DIR>/models/` (see the working-directory note
above):

| File | What it's for | Source project |
|---|---|---|
| `kokoro-v1.0.onnx` + `voices-v1.0.bin` | Kokoro TTS (spoken replies) | [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) |
| `silero_vad.onnx` | Voice activity detection | [Silero VAD](https://github.com/snakers4/silero-vad) |
| `gtcrn_simple.onnx` | Noise suppression | GTCRN |
| `titanet_small_en.onnx` | Speaker ID (owner vs. guest) | NVIDIA NeMo TitaNet |
| `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/` (directory, with `model.int8.onnx` inside) | Emotion-aware transcription | [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) SenseVoice |

mlx-whisper's own model (the default is
`mlx-community/whisper-base-mlx`) and the sentence-transformers embedding
model download automatically on first use via their own Hugging Face caches —
no manual step needed for those.

## Running

All commands run from this directory (`voice-daemon/`), with the venv from
setup step 1 active.

```
python -m jarvis_voice.jarvis_ear                  # start the daemon
python -m jarvis_voice.jarvis_ear --selftest        # 14-point self-check, no live mic loop
python -m jarvis_voice.jarvis_pipecat               # open-channel conversation mode (needs the [pipecat] extra)
python -m jarvis_voice.jarvis_v7_check              # diagnostics: models present, memory/knowledge-graph stats
./open-dashboard.sh                                 # local HTML dashboard (a lighter alternative to the SwiftUI app in ../dashboard/)
```

To run it persistently in the background on login, wrap the daemon command in
a `launchd` `.plist` (`~/Library/LaunchAgents/`) — see Apple's
[`launchd.plist` docs](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
for the format; this repo doesn't ship a specific plist since the paths in it
are inherently machine-specific.

## Testing

These are plain scripts (they `print` PASS/FAIL and call `sys.exit`), not a
pytest suite — the assertions inside don't `raise`, so running them under
real `pytest` would silently report a pass regardless of the actual result.
Run them directly:

```
python tests/test_wave1.py         # reflex table + recall gate, network-free
python tests/test_bargein.py       # barge-in interrupt logic
python tests/test_bargein_e2e.py   # barge-in, end-to-end with synthesized audio
python tests/test_waterfall.py     # ambient-path gating (skip inference until Jarvis is mentioned)
python tests/test_h1.py            # emotional-ear acceptance test (needs network, for TTS synthesis + STT)
```

`scripts/evals.py` is a separate eval harness, not a pass/fail test — run it
directly to see its own output format.
