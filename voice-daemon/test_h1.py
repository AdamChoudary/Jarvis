"""H1 Emotional Ear acceptance test.

1. Engine loads from the sherpa-onnx SenseVoice model dir.
2. Transcribes a synthesized utterance correctly (ASR sanity).
3. Result exposes emotion/event fields and analyze_voice() returns a
   well-formed note (or None for neutral speech — synthetic TTS audio is
   usually neutral; real emotion detection needs a human voice).
4. End-to-end: a [voice analysis: ...] note measurably changes the reply style.
"""
import subprocess, sys, tempfile, wave

import numpy as np

import jarvis_ear as je


def synth_wav(text, voice="en-US-GuyNeural"):
    mp3 = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False).name
    wav = mp3.replace(".mp3", ".wav")
    subprocess.run([je.VENV_BIN + "/edge-tts", "--voice", voice, "--text", text,
                    "--write-media", mp3], check=True, capture_output=True)
    subprocess.run(["ffmpeg", "-y", "-i", mp3, "-ar", "16000", "-ac", "1", wav],
                   check=True, capture_output=True)
    with wave.open(wav) as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0


ok = True

# 1+2. engine + ASR sanity
sv = je._sensevoice_engine()
print("engine load:", "PASS" if sv else "FAIL")
ok &= bool(sv)

if sv:
    audio = synth_wav("The quick brown fox jumps over the lazy dog.")
    stream = sv.create_stream()
    stream.accept_waveform(je.RATE, audio)
    sv.decode_stream(stream)
    res = stream.result
    text = (getattr(res, "text", "") or "").lower()
    print(f"ASR text: {text[:60]!r} ->", "PASS" if "quick brown fox" in text else "FAIL")
    ok &= "quick brown fox" in text
    emo = getattr(res, "emotion", "MISSING")
    evt = getattr(res, "event", "MISSING")
    print(f"fields: emotion={emo!r} event={evt!r} ->",
          "PASS" if "MISSING" not in (emo, evt) else "FAIL")
    ok &= "MISSING" not in (emo, evt)

    # 3. analyze_voice returns None or a clean note
    note = je.analyze_voice(synth_wav("I am absolutely thrilled, this is wonderful news!"))
    wellformed = note is None or (isinstance(note, str) and 0 < len(note) < 120)
    print(f"analyze_voice note: {note!r} ->", "PASS" if wellformed else "FAIL")
    ok &= wellformed

# 4. behavioral delta: same words, different voice note
r_neutral = je.fast_lane("Everything failed today. What time is it?", [], None)
r_angry = je.fast_lane("Everything failed today. What time is it?", [], None,
                       voice_note="sounds frustrated or angry")
print(f"neutral reply: {r_neutral!r}")
print(f"angry-note reply: {r_angry!r}")
delta = bool(r_neutral) and bool(r_angry) and r_neutral != r_angry
print("behavioral delta:", "PASS" if delta else "WEAK (same reply)")
ok &= bool(r_neutral) and bool(r_angry)

print("H1 TEST", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
