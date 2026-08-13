#!/usr/bin/env python3
"""Jarvis Conversation Mode — Pipecat streaming pipeline.

Open-channel dialogue: no wake word needed once running. Silero VAD detects
end-of-speech (~0.3s), tokens stream from the fast model, speech starts on the
first sentence, and you can barge in mid-reply.

  mic → SileroVAD → Whisper (local) → Zen north-mini (streaming) → Edge TTS → speakers

Run:   ~/.hermes/hermes-agent/venv/bin/python ~/.hermes/jarvis-voice/jarvis_pipecat.py
Stop:  Ctrl+C  (the wake-word daemon `jarvis_ear.py` keeps running independently)

Escalation: like the ear daemon, replies of exactly "AGENT" hand the request to
the full Hermes agent (API server) and speak its answer when done.
"""
import asyncio, os, subprocess, sys

import jarvis_ear  # shared TTS engine chain (edge -> kokoro -> say)

from pipecat.audio.vad.silero import SileroVADAnalyzer
from pipecat.audio.vad.vad_analyzer import VADParams
from pipecat.processors.audio.vad_processor import VADProcessor
from pipecat.frames.frames import (BotStartedSpeakingFrame, BotStoppedSpeakingFrame,
                                   Frame, InputAudioRawFrame, TTSAudioRawFrame,
                                   TTSStartedFrame, TTSStoppedFrame,
                                   UserSpeakingFrame, VADUserStartedSpeakingFrame,
                                   VADUserStoppedSpeakingFrame)
from pipecat.processors.frame_processor import FrameDirection, FrameProcessor
from pipecat.pipeline.pipeline import Pipeline
from pipecat.pipeline.runner import PipelineRunner
from pipecat.pipeline.task import PipelineParams, PipelineTask
from pipecat.processors.aggregators.llm_context import LLMContext
from pipecat.processors.aggregators.llm_response_universal import LLMContextAggregatorPair
from pipecat.services.openai.llm import OpenAILLMService
from pipecat.services.tts_service import TTSService
from pipecat.services.whisper.stt import WhisperSTTServiceMLX
from pipecat.transports.local.audio import LocalAudioTransport, LocalAudioTransportParams

ZEN_KEY = os.environ.get("OPENCODE_ZEN_KEY", "")
VOICE = "en-GB-RyanNeural"
TTS_RATE = 24000

SYSTEM = (
    "You are Jarvis, a British butler AI in a live spoken conversation with Sir. "
    "Replies are SPOKEN ALOUD: 1-3 short sentences, no markdown, no lists. Dry wit welcome. "
    "This channel is conversation only. If a request requires touching the computer — "
    "files, apps, projects, terminal, web — say: 'For that, summon me with Hey Jarvis, "
    "sir — this channel is conversation only.'"
)


class EchoGate(FrameProcessor):
    """Deafen the input path while Jarvis speaks so he doesn't answer himself
    (needed on open speakers; run with --barge-in on headphones to disable).

    Latched: BotStopped between TTS sentences doesn't unmute — only 1.2s of
    sustained bot silence does. While muted, VAD/user-speech frames are DROPPED
    so they can't trigger interruptions or STT segments."""

    def __init__(self):
        super().__init__()
        self._muted = False
        self._gen = 0

    async def _delayed_unmute(self, gen):
        await asyncio.sleep(2.5)              # pyaudio buffer keeps playing past BotStopped
        if gen == self._gen:                  # no new bot speech since
            self._muted = False
            print("[EchoGate] UNMUTE", flush=True)

    async def process_frame(self, frame: Frame, direction):
        await super().process_frame(frame, direction)
        if isinstance(frame, BotStartedSpeakingFrame):
            self._gen += 1
            if not self._muted:
                self._muted = True
                print("[EchoGate] MUTE", flush=True)
        elif isinstance(frame, BotStoppedSpeakingFrame):
            self._gen += 1
            asyncio.get_event_loop().create_task(self._delayed_unmute(self._gen))
        elif self._muted and direction == FrameDirection.DOWNSTREAM and isinstance(
                frame, (VADUserStartedSpeakingFrame, VADUserStoppedSpeakingFrame,
                        UserSpeakingFrame, InputAudioRawFrame)):
            return                            # drop: Jarvis hearing himself
        await self.push_frame(frame, direction)


class EdgeTTSService(TTSService):
    """Minimal Edge TTS for pipecat: sentence in → raw PCM frames out."""

    def __init__(self, voice=VOICE, **kwargs):
        super().__init__(sample_rate=TTS_RATE, **kwargs)
        self._voice = voice

    async def run_tts(self, text, context_id=None):
        yield TTSStartedFrame()
        path = await asyncio.to_thread(jarvis_ear._synth, text)   # engine chain w/ fallback
        pcm = await asyncio.to_thread(_file_to_pcm, path)
        os.unlink(path)
        for i in range(0, len(pcm), 9600):                      # 200ms chunks
            yield TTSAudioRawFrame(audio=pcm[i:i + 9600],
                                   sample_rate=TTS_RATE, num_channels=1)
        yield TTSStoppedFrame()


def _file_to_pcm(path):
    p = subprocess.run(["ffmpeg", "-i", path, "-f", "s16le", "-ar", str(TTS_RATE),
                        "-ac", "1", "pipe:1"], capture_output=True)
    return p.stdout


async def main():
    transport = LocalAudioTransport(LocalAudioTransportParams(
        audio_in_enabled=True, audio_in_sample_rate=16000,
        audio_out_enabled=True, audio_out_sample_rate=TTS_RATE,
    ))
    # pipecat 1.5: VAD is an explicit pipeline stage, not a transport param
    vad = VADProcessor(vad_analyzer=SileroVADAnalyzer(
        params=VADParams(confidence=0.5, min_volume=0.2, start_secs=0.15)))
    stt = WhisperSTTServiceMLX(settings=WhisperSTTServiceMLX.Settings(
        model="mlx-community/whisper-base-mlx"))   # base > tiny accuracy, M1 GPU
    llm = OpenAILLMService(api_key=ZEN_KEY, base_url="https://opencode.ai/zen/v1",
                           model="north-mini-code-free")
    tts = EdgeTTSService()
    context = LLMContext([{"role": "system", "content": SYSTEM}])
    agg = LLMContextAggregatorPair(context)

    stages = [transport.input(), vad]
    if "--barge-in" not in sys.argv:
        stages.append(EchoGate())
    stages += [stt, agg.user(), llm, tts, transport.output(), agg.assistant()]
    pipeline = Pipeline(stages)
    task = PipelineTask(pipeline, params=PipelineParams(allow_interruptions=True))
    print("Jarvis conversation mode — speak freely. Ctrl+C to end.")
    await PipelineRunner().run(task)


if __name__ == "__main__":
    asyncio.run(main())
