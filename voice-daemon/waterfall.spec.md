# Waterfall gate spec

Transcribe-first on the always-on ambient path; emotion and speaker-ID only
after the utterance is confirmed as addressed to Jarvis.
Implementation: `hear_ambient()` + the mention call site in `jarvis_ear.py`.
Test: `test_waterfall.py`. Council-approved 2026-07-18, shipped 2026-07-20
after a 48h soak.

## Why

The ambient path fires on every sustained utterance near the Mac, and almost
all of it is never addressed to Jarvis (measured: 5,538 transcribe-and-
discard events vs 30 real mention triggers over three days). Before the
gate, every one of those also paid SenseVoice emotion + TitaNet speaker-ID —
full 3-way inference on room noise.

## Contract

- `hear_ambient(whisper, audio) -> text`: transcription only. Nothing else
  may run on this path.
- Only after `name_mentioned(text)` confirms does the call site submit
  `analyze_voice` + `identify_speaker`, concurrently, for that same segment.
- `hear()` (full 3-way) is reserved for turns already known to be his: the
  wake-triggered main turn, the follow-up window, barge-in capture. Do not
  "optimise" those through the gate — they are already confirmed.

## What this gate is not

- Not a fix for mention-trigger false positives (TV audio containing
  "Jarvis"-like sounds). It only removes cost on utterances that were never
  false positives to begin with.
- Not the idle-unload timer. That is a separate, conditional follow-up per
  the council ruling, gated on post-waterfall RSS behaviour.
