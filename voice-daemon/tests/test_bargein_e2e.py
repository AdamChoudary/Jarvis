"""End-to-end barge-in test: injects synthesized 'interruption' audio directly
into a live Speaker + barge_in_monitor pair as raw int16 frames (matching
exactly what the real mic callback produces), bypassing the uncertain
speaker-to-mic acoustic path entirely. Proves the CAPTURE-AND-CONTINUE logic
(the actual feature Sir asked for) works, independent of the RMS threshold's
real-world acoustic calibration (which needs Sir's real voice to validate).

Run: ~/.hermes/hermes-agent/venv/bin/python test_bargein_e2e.py
"""
import queue, subprocess, sys, tempfile, threading, time, wave

import numpy as np

from jarvis_voice import jarvis_ear as je


def synth_frames(text, voice="en-US-GuyNeural"):
    """Real synthesized speech -> a list of int16 frames sized like real mic
    callbacks (je.CHUNK samples each) so it exercises the actual VAD/whisper
    path, not a fake signal."""
    mp3 = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False).name
    wav = mp3.replace(".mp3", ".wav")
    subprocess.run([je.VENV_BIN + "/edge-tts", "--voice", voice, "--text", text,
                    "--write-media", mp3], check=True, capture_output=True)
    subprocess.run(["ffmpeg", "-y", "-i", mp3, "-ar", str(je.RATE), "-ac", "1", wav],
                   check=True, capture_output=True)
    with wave.open(wav) as w:
        pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
    # amplify so it reliably crosses BARGE_IN_RMS regardless of the source
    # clip's own loudness — isolates the LOGIC under test from mixing levels
    pcm = np.clip(pcm.astype(np.int32) * 3, -32768, 32767).astype(np.int16)
    return [pcm[i:i + je.CHUNK] for i in range(0, len(pcm) - je.CHUNK, je.CHUNK)]


def main():
    whisper = je.load_whisper()
    speaker = je.Speaker()
    q = queue.Queue()

    # Jarvis "speaking" a long reply — enough sentences to give the
    # interruption time to land mid-playback, like a real long answer would.
    speaker.say_all(
        "This is the first sentence of a rather long reply, sir. "
        "Here is a second sentence to give us some time. "
        "And a third, in case the interruption is a touch late. "
        "Finally a fourth sentence that should never actually be heard."
    )
    time.sleep(0.6)                      # let real playback of sentence 1 begin
    assert speaker._pending > 0, "setup broken: nothing queued/playing"

    result = {}
    monitor = threading.Thread(target=je.barge_in_monitor,
                               args=(speaker, q, 100.0, result), daemon=True)
    monitor.start()

    # Feed the "interruption" utterance frame-by-frame, like a real mic would,
    # while Jarvis is mid-sentence.
    for frame in synth_frames("Actually, never mind that, what time is it?"):
        q.put(frame)
        time.sleep(je.CHUNK / je.RATE)    # real-time pacing

    monitor.join(timeout=15.0)

    print(f"interrupted: {speaker._interrupt.is_set()}")
    print(f"captured audio: {'yes' if result.get('audio') is not None else 'NO'}")
    ok = speaker._interrupt.is_set() and result.get("audio") is not None
    if not ok:
        print("BARGE-IN E2E: FAIL")
        sys.exit(1)

    text, note, who, score = je.hear(whisper, result["audio"])
    print(f"transcribed interruption: {text!r}")
    ok = ok and "time" in text.lower()
    print(f"pending drains to 0: ", end="")
    t0 = time.time()
    while speaker._pending > 0 and time.time() - t0 < 5.0:
        time.sleep(0.05)
    pending_ok = speaker._pending == 0
    print(pending_ok, f"(final={speaker._pending})")
    ok = ok and pending_ok

    print("BARGE-IN E2E:", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
