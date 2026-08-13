"""Barge-in self-check — the smallest thing that fails if the logic breaks.

Covers the CRITICAL bug this session found and fixed: interrupt() draining
queued-but-not-yet-played sentences without decrementing _pending would leave
Speaker.wait() hanging forever on every subsequent turn (a daemon-wide hang,
not just a cosmetic glitch) — found by reading the code, verified here so it
can never silently regress.

Run: ~/.hermes/hermes-agent/venv/bin/python test_bargein.py
"""
import sys, time

from jarvis_voice import jarvis_ear as je


def test_interrupt_decrements_pending_for_drained_items():
    """The bug: queue N sentences, interrupt after only 1 has started playing.
    _pending must return to (near) 0 promptly — NOT hang forever."""
    speaker = je.Speaker()
    for i in range(4):
        speaker.say(f"This is test sentence number {i} for the barge in check.")
    time.sleep(0.3)                      # let the player thread pick up #1
    assert speaker._pending > 0, "nothing queued — test setup broken"
    speaker.interrupt()
    t0 = time.time()
    while speaker._pending > 0 and time.time() - t0 < 5.0:
        time.sleep(0.05)
    ok = speaker._pending == 0
    print(f"interrupt() drains _pending to 0 within 5s: {'PASS' if ok else 'FAIL'} "
          f"(final _pending={speaker._pending})")
    return ok


def test_wait_has_a_ceiling():
    """Defense-in-depth: even if _pending accounting broke some other way,
    wait() must not hang the daemon forever."""
    speaker = je.Speaker()
    with speaker._lock:
        speaker._pending = 1              # simulate a stuck/impossible state
    t0 = time.time()
    speaker.wait(max_secs=1.0)
    elapsed = time.time() - t0
    ok = elapsed < 3.0 and speaker._pending == 0
    print(f"wait() ceiling forces return: {'PASS' if ok else 'FAIL'} "
          f"(elapsed={elapsed:.1f}s, pending={speaker._pending})")
    return ok


def test_player_skips_interrupted_queue_items():
    """Items already in the queue when interrupt() fires should not play."""
    speaker = je.Speaker()
    speaker.say("First sentence before interrupt for the barge in check.")
    time.sleep(0.05)                     # too fast for this one to start playing yet
    speaker.interrupt()
    t0 = time.time()
    while speaker._pending > 0 and time.time() - t0 < 5.0:
        time.sleep(0.05)
    ok = speaker._pending == 0
    print(f"queued-but-unplayed item cleared without hanging: {'PASS' if ok else 'FAIL'}")
    return ok


def test_degenerate_detector():
    cases = {
        "fish fish fish fish fish": True,
        "the quick brown fox": False,
        # live-caught 2026-07-19: hyphen-joined loop, one token under split()
        "the rocky rocky has an an e-re-re-re-re-re-re-re-re-re-re": True,
        # live-caught 2026-07-19: was reaching the LLM via the follow-up path
        "presently so that id id id id id id id id id id id id": True,
        # live-caught 2026-07-19 (audit item 3): 5-token phrase, past the old plen<=4 cap
        "i'm going to go to the beach. i'm going to the beach. i'm going to the "
        "beach. i'm going to the beach. i'm going to the beach.": True,
        "what time is it right now": False,
    }
    ok = True
    for t, want in cases.items():
        got = je.is_degenerate(t)
        if got != want:
            print(f"  MISMATCH: {t[:40]!r} expected {want} got {got}")
        ok &= got == want
    print(f"is_degenerate() classifies correctly: {'PASS' if ok else 'FAIL'}")
    return ok


if __name__ == "__main__":
    results = [
        test_interrupt_decrements_pending_for_drained_items(),
        test_wait_has_a_ceiling(),
        test_player_skips_interrupted_queue_items(),
        test_degenerate_detector(),
    ]
    print("BARGE-IN SELFTEST", "PASS" if all(results) else "FAIL")
    sys.exit(0 if all(results) else 1)
