"""Recall gate — decide whether memory enrichment is worth paying for.

Ported from isair/jarvis (`src/jarvis/memory/recall_gate.spec.md`), whose design
this follows closely because it is well argued.

`_memory_context()` runs an FTS5 query, a vector search and a knowledge-graph
lookup on every single turn. On a warm index that is ~0.5s; on a cold one it was
measured at 15s. A large share of turns are follow-ups whose answer is already
sitting in the conversation history, and those pay the full cost for nothing.

The gate is a pre-flight check, not a routing decision. It answers one question:
"does the recent conversation already ground this query?" If yes, skip
enrichment. If unsure, recall. It is a pure-Python pass with no LLM call and no
I/O, so it is strictly additive and trivially removable.

Two rules carried over from the original, both worth keeping:

* **Fail open.** Any exception returns True (recall). The cost of recalling
  unnecessarily is some latency; the cost of wrongly skipping is an answer with
  no grounding.
* **Language-agnostic by construction.** Content words come from
  `\\w{3,}` with `re.UNICODE`, so Cyrillic, CJK, Arabic and Hebrew all tokenise.
  The stopword list is English-only and merely optional filtering: a non-English
  query simply skips it and lands on the conservative (recall) side.
"""
import re

# Deliberately small. This is not linguistics, it is noise removal so that
# "what is the ..." does not score as content overlap on its own.
_STOPWORDS = {
    "the", "and", "for", "are", "was", "were", "you", "your", "our", "his", "her",
    "its", "that", "this", "these", "those", "with", "from", "have", "has", "had",
    "what", "when", "where", "which", "who", "why", "how", "did", "does", "can",
    "could", "would", "should", "there", "then", "than", "them", "they", "about",
    "into", "just", "like", "some", "any", "not", "but", "all", "one", "get",
}

# Fraction of the query's content words that must already appear in the hot
# window before enrichment is considered redundant.
COVERAGE_THRESHOLD = 0.5


def _content_words(text):
    words = re.findall(r"\w{3,}", (text or "").lower(), flags=re.UNICODE)
    filtered = [w for w in words if w not in _STOPWORDS]
    # If stopword filtering removed everything (short or non-English query),
    # fall back to the unfiltered set rather than scoring an empty overlap.
    return set(filtered or words)


def _has_grounding_turn(history):
    """True if the hot window already contains an actual answer from us.

    The original keys off tool-result messages. Our equivalent is any prior
    assistant turn with real content: it means this exchange has already
    produced grounded material the follow-up can lean on.
    """
    for msg in history:
        if msg.get("role") == "assistant":
            body = (msg.get("content") or "").strip()
            if body and body != "SILENCE":
                return True
    return False


def should_recall(query, history, window=6):
    """Return True to run memory enrichment, False to skip it.

    `window` bounds how far back counts as the hot window; older turns are not
    fresh enough to justify skipping a lookup.
    """
    try:
        recent = list(history or [])[-window:]
        if not recent:
            return True                       # nothing to lean on
        if not _has_grounding_turn(recent):
            return True                       # no prior answer in the window

        q_words = _content_words(query)
        if not q_words:
            return True                       # nothing to score; be safe

        transcript = " ".join((m.get("content") or "") for m in recent)
        covered = q_words & _content_words(transcript)
        # Asymmetric on purpose: coverage of the QUERY, not Jaccard. A long
        # history must not dilute the score of a short follow-up.
        coverage = len(covered) / len(q_words)
        return coverage < COVERAGE_THRESHOLD
    except Exception:
        return True                           # fail open, always


if __name__ == "__main__":
    hist = [
        {"role": "user", "content": "how much unified memory is the daemon using"},
        {"role": "assistant", "content": "Around 3.4 gigabytes of unified memory, sir, "
                                          "with the whisper model resident."},
    ]
    cases = [
        # (query, history, expected should_recall, why)
        ("is that a lot", hist, True, "follow-up shares almost no content words"),
        ("what about the unified memory now", hist, False, "covered by the hot window"),
        ("who is my dentist", hist, True, "unrelated, needs the memory index"),
        ("anything", [], True, "empty history always recalls"),
        ("unified memory daemon", hist, False, "fully covered"),
        ("what did I say about the roadmap", hist, True, "not in the window"),
    ]
    ok = True
    for query, h, expected, why in cases:
        got = should_recall(query, h)
        if got != expected:
            print(f"  MISMATCH {query!r}: expected recall={expected}, got {got}  ({why})")
            ok = False
    # fail-open check: malformed history must not raise
    if should_recall("x", [{"bogus": object()}]) is not True:
        print("  fail-open broken")
        ok = False
    print("recall gate:", "PASS" if ok else "FAIL")
    raise SystemExit(0 if ok else 1)
