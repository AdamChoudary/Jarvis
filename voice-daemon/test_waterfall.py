"""Waterfall gate — proves the ambient path skips emotion/speaker-ID inference
on speech that never mentions Jarvis, and still runs the full pipeline once it
does. Council-approved 2026-07-18, soaked 48h, shipped 2026-07-20.

Run: ~/.hermes/hermes-agent/venv/bin/python test_waterfall.py
"""
import sys
sys.path.insert(0, "/Users/mac/.hermes/jarvis-voice")
import jarvis_ear as je


def test_ambient_path_transcribes_only():
    calls = []
    je.transcribe = lambda w, a: (calls.append("transcribe"), "the weather looks nice today")[1]
    je.analyze_voice = lambda a: calls.append("analyze_voice") or "happy"
    je.identify_speaker = lambda a: calls.append("identify_speaker") or ("guest", 0.1)

    text = je.hear_ambient(None, None)
    ok = calls == ["transcribe"] and text == "the weather looks nice today"
    print(f"ambient path (no mention): {'PASS' if ok else 'FAIL'} (calls={calls}, text={text!r})")
    return ok


def test_full_pipeline_still_runs_on_mention():
    """hear() itself — used once name_mentioned() confirms — must be untouched:
    still transcribe + emotion + speaker-ID, all three, concurrently."""
    calls = []
    je.transcribe = lambda w, a: calls.append("transcribe") or "hey jarvis what time is it"
    je.analyze_voice = lambda a: calls.append("analyze_voice") or None
    je.identify_speaker = lambda a: calls.append("identify_speaker") or ("sir", 0.9)

    text, note, who, score = je.hear(None, None)
    ok = set(calls) == {"transcribe", "analyze_voice", "identify_speaker"} and who == "sir"
    print(f"full pipeline on confirmed turn: {'PASS' if ok else 'FAIL'} (calls={sorted(calls)})")
    return ok


def test_name_mentioned_gates_correctly():
    """Sanity: the gate's whole premise rests on name_mentioned() discriminating."""
    cases = [
        ("the weather looks nice today", False),
        ("hey jarvis what time is it", True),
        ("jarvis, can you help me", True),
        ("I think jarvis is a good name for a cat", True),  # name_mentioned is substring-based by design
    ]
    ok = True
    for text, expected in cases:
        got = je.name_mentioned(text)
        if got != expected:
            print(f"  MISMATCH: {text!r} expected {expected}, got {got}")
            ok = False
    print(f"name_mentioned discriminates: {'PASS' if ok else 'FAIL'}")
    return ok


if __name__ == "__main__":
    results = [
        test_ambient_path_transcribes_only(),
        test_full_pipeline_still_runs_on_mention(),
        test_name_mentioned_gates_correctly(),
    ]
    print("WATERFALL GATE:", "PASS" if all(results) else "FAIL")
    sys.exit(0 if all(results) else 1)
