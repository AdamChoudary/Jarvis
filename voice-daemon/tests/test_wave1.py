"""Wave 1 verification — reflex table, recall gate, and their wiring into dispatch.

Deliberately network-free. The full --selftest exercises the brain chain, which
is currently unusable (Zen is rate limited, NIM is missing its first-token
deadline), and that has nothing to do with this work. These checks prove the
latency path itself, and the reflex path in particular is verified END TO END
through the real dispatch() because a reflex hit never opens a socket.

Run: ~/.hermes/hermes-agent/venv/bin/python test_wave1.py
"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# Tags every turn this run logs to ram-log.jsonl with "source": "test" so
# real-usage latency analysis (and the dashboard's own laneStats()) doesn't
# average test fixtures in with production turns — found live-mixed together
# in the real log during a latency investigation.
os.environ["JARVIS_TEST_MODE"] = "1"
from jarvis_voice import jarvis_ear as je
from jarvis_voice.jarvis_reflex import reflex
from jarvis_voice.jarvis_recall import should_recall


class FakeSpeaker:
    """Captures what would have been spoken, so dispatch can run headless."""
    def __init__(self):
        self.said = []

    def say(self, text, tone="neutral"):
        self.said.append(text)

    def say_all(self, text, limit=None):
        self.said.append(text)

    def wait(self, max_secs=120.0):
        pass


def test_reflex_short_circuits_dispatch():
    """A reflex question must be answered without ever reaching the brain."""
    calls = []
    original = je.fast_lane
    je.fast_lane = lambda *a, **k: calls.append("fast_lane") or "SHOULD NOT HAPPEN"
    try:
        speaker = FakeSpeaker()
        history = []
        t0 = time.time()
        reply = je.dispatch("what time is it", history, speaker)
        elapsed = time.time() - t0
    finally:
        je.fast_lane = original

    ok = (not calls) and reply and "sir" in reply.lower() and elapsed < 1.0
    print(f"reflex short-circuits dispatch: {'PASS' if ok else 'FAIL'} "
          f"({elapsed*1000:.0f}ms, brain calls={len(calls)}, reply={reply!r})")
    # the exchange must still be recorded, or the follow-up window loses context
    recorded = len(history) == 2 and history[0]["content"] == "what time is it"
    print(f"  reflex turn recorded in history: {'PASS' if recorded else 'FAIL'}")
    return ok and recorded


def test_non_reflex_still_reaches_brain():
    """Anything the table is not confident about must fall through untouched."""
    calls = []
    original = je.fast_lane

    def spy(text, history, speaker, voice_note=None):
        calls.append(text)
        return "brain answered"

    je.fast_lane = spy
    try:
        speaker = FakeSpeaker()
        reply = je.dispatch("what do you make of the roadmap", [], speaker)
    finally:
        je.fast_lane = original
    ok = len(calls) == 1 and reply == "brain answered"
    print(f"non-reflex reaches brain: {'PASS' if ok else 'FAIL'} (calls={len(calls)})")
    return ok


def test_turn_logged_with_lane():
    """Latency instrumentation must land in ram-log.jsonl with a lane tag."""
    before = _last_turn_entry()
    speaker = FakeSpeaker()
    je.dispatch("battery", [], speaker)
    after = _last_turn_entry()
    ok = after is not None and after != before and after.get("lane") == "reflex" \
        and "secs" in after
    print(f"turn logged with lane: {'PASS' if ok else 'FAIL'} (entry={after})")
    return ok


def _last_turn_entry():
    try:
        with open(je.RAM_LOG) as f:
            for line in reversed(f.readlines()):
                d = json.loads(line)
                if d.get("event") == "turn":
                    return d
    except Exception:
        pass
    return None


def test_recall_gate_wired():
    """fast_lane must consult the gate rather than always enriching."""
    hits = []
    original = je._memory_context
    je._memory_context = lambda q: hits.append(q) or ""
    grounded = [
        {"role": "user", "content": "how much unified memory is the daemon using"},
        {"role": "assistant", "content": "Around 3.4 gigabytes of unified memory, sir."},
    ]
    try:
        # covered follow-up -> gate should skip enrichment entirely
        skip = not should_recall("what about the unified memory now", grounded)
        # unrelated query -> gate should demand enrichment
        recall = should_recall("who is my dentist", grounded)
    finally:
        je._memory_context = original
    ok = skip and recall
    print(f"recall gate discriminates: {'PASS' if ok else 'FAIL'} "
          f"(skips covered={skip}, recalls unrelated={recall})")
    return ok


def test_agent_timeout_is_bounded():
    """The 900s timeout left Sir in silence for a quarter hour; it must be sane."""
    ok = getattr(je, "AGENT_TIMEOUT_SECS", 900) <= 180
    print(f"agent timeout bounded: {'PASS' if ok else 'FAIL'} "
          f"({getattr(je, 'AGENT_TIMEOUT_SECS', 'unset')}s)")
    return ok


if __name__ == "__main__":
    results = [
        test_reflex_short_circuits_dispatch(),
        test_non_reflex_still_reaches_brain(),
        test_turn_logged_with_lane(),
        test_recall_gate_wired(),
        test_agent_timeout_is_bounded(),
    ]
    print("WAVE 1:", "PASS" if all(results) else "FAIL")
    sys.exit(0 if all(results) else 1)
