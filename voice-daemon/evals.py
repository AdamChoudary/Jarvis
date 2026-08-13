"""Routing evals — a fixed fixture set run against the real dispatch layers.

isair/jarvis's practice, ported: track what works with automated evals and a
published pass rate, so any change to routing, guards, or prompts gets judged
against a number instead of a feeling. This suite covers the DETERMINISTIC
layers (no LLM call, so it runs in milliseconds and can gate every commit):

  - reflex table         does the right lane fire, and never falsely
  - degenerate detector  hallucination classes from real incidents
  - recall gate          skip vs recall decisions
  - dismissal regex      conversation-ending phrases
  - name_mentioned       ambient trigger discrimination

Run: ~/.hermes/hermes-agent/venv/bin/python evals.py
Exit code is 0 only at 100%; the score line is the artefact to watch.
"""
import sys

sys.path.insert(0, "/Users/mac/.hermes/jarvis-voice")
import jarvis_ear as je
from jarvis_recall import should_recall
from jarvis_reflex import reflex

PASS = 0
FAIL = 0
FAILURES = []


def check(name, got, want):
    global PASS, FAIL
    if got == want:
        PASS += 1
    else:
        FAIL += 1
        FAILURES.append(f"{name}: expected {want!r}, got {got!r}")


# ── reflex routing ───────────────────────────────────────────────────────────
REFLEX_FIRES = [
    "what time is it", "battery", "uptime", "flip a coin", "roll a d20",
    "generate a password", "convert 5 miles to km", "what day is it",
]
REFLEX_FALLS_THROUGH = [
    "what time should I leave for the airport",
    "why is the battery draining so fast",
    "set a timer for ten minutes",
    "remind me to call the client tomorrow",
    "what do you think about the roadmap",
    "convert 5 miles to kilograms",          # dimensionally nonsense
    "tell me a joke",                         # deliberately NOT a reflex: persona work
]
for t in REFLEX_FIRES:
    check(f"reflex fires: {t}", reflex(t) is not None, True)
for t in REFLEX_FALLS_THROUGH:
    check(f"reflex falls through: {t}", reflex(t), None)

# ── degenerate (hallucination) detector ──────────────────────────────────────
DEGENERATE = [
    "fish fish fish fish fish",
    "the rocky rocky has an an e-re-re-re-re-re-re-re-re-re-re",
    "presently so that id id id id id id id id id id id id",
    "i'm going to go to the beach. i'm going to the beach. i'm going to the "
    "beach. i'm going to the beach. i'm going to the beach.",
]
CLEAN = [
    "what time is it right now",
    "I said no, no, no — not that one",       # natural emphasis, not a loop
    "can you check the build again and again until it passes",
]
for t in DEGENERATE:
    check(f"degenerate caught: {t[:40]}", je.is_degenerate(t), True)
for t in CLEAN:
    check(f"clean passes: {t[:40]}", je.is_degenerate(t), False)

# ── recall gate ──────────────────────────────────────────────────────────────
GROUNDED_HISTORY = [
    {"role": "user", "content": "how much unified memory is the daemon using"},
    {"role": "assistant", "content": "Around 2.3 gigabytes of unified memory, sir."},
]
check("gate skips covered follow-up",
      should_recall("what about the unified memory now", GROUNDED_HISTORY), False)
check("gate recalls unrelated query",
      should_recall("who is my dentist", GROUNDED_HISTORY), True)
check("gate recalls on empty history", should_recall("anything", []), True)
check("gate fails open on malformed history",
      should_recall("x", [{"bogus": object()}]), True)

# ── dismissal phrases ────────────────────────────────────────────────────────
DISMISSALS = ["that's all", "thank you Jarvis", "go to sleep", "stand down", "dismissed"]
NOT_DISMISSALS = ["thank goodness", "that's all wrong, try again", "stand by me"]
for t in DISMISSALS:
    check(f"dismissal: {t}", bool(je.DISMISS_RE.search(t)), True)
for t in NOT_DISMISSALS:
    check(f"not dismissal: {t}", bool(je.DISMISS_RE.search(t)), False)

# ── ambient name trigger ─────────────────────────────────────────────────────
MENTIONS = ["hey jarvis what time is it", "jarvis, thoughts?", "okay Jarvis"]
NOT_MENTIONS = ["the weather looks nice today", "let's grab lunch"]
for t in MENTIONS:
    check(f"mention: {t}", je.name_mentioned(t), True)
for t in NOT_MENTIONS:
    check(f"no mention: {t}", bool(je.name_mentioned(t)), False)

# ── score ────────────────────────────────────────────────────────────────────
total = PASS + FAIL
for f in FAILURES:
    print(f"  FAIL {f}")
print(f"EVALS: {PASS}/{total} ({100 * PASS / total:.0f}%)")
sys.exit(0 if FAIL == 0 else 1)
