# Implementation plan — porting the best ideas into our Jarvis

Derived from `JARVIS-LANDSCAPE.md`. Ordered by value-per-effort against the complaints
already on record: responses take too long, triggering should feel instant, and the
dashboard should show everything end to end.

Reference implementations live in `reference/`. Paths below point at the exact files
worth reading before writing each piece.

---

## Wave 1 — latency (attacks the oldest open complaint)

### 1.1 Deterministic pre-brain
**Read:** `reference/sukeesh-jarvis/jarviscli/plugins/`

Before `fast_lane()` touches any LLM, run a small table of exact-answer handlers: time,
date, battery, RAM/footprint, uptime, daemon status, "what did you just say". Each is a
pure function returning a string.

- Where: new `jarvis_reflex.py`, called at the top of `dispatch()` in `jarvis_ear.py`.
- Win: 2-6s to about 50ms on the most common utterances.
- Guard: only fire on a confident full-phrase match; anything ambiguous falls through to
  the LLM. Never guess.
- Check: `test_reflex.py` asserting each pattern hits and that a near-miss falls through.

### 1.2 Recall gate
**Read:** `reference/isair-jarvis/src/jarvis/memory/recall_gate.spec.md` (the whole file
is 45 lines and is the design)

`_memory_context()` currently runs on every turn. Add a pre-flight that skips enrichment
when the recent history already grounds the query.

- Port their heuristic as-is: skip only if the hot window holds a prior tool/reply result
  **and** ≥50% of the query's content words already appear in it. Asymmetric coverage
  (`overlap / query_words`), not Jaccard. Fail open on any exception.
- Keep it language-agnostic: `re.findall(r"\w{3,}", text, flags=re.UNICODE)`.
- Where: `jarvis_ear.py`, guarding the `_memory_context(text)` call in `fast_lane()`.
- Check: unit test for both branches plus the fail-open path.

### 1.3 Latency instrumentation
Log per-turn timings (STT, memory, brain, TTS-first-sentence) into `ram-log.jsonl`
alongside what is already there. Needed to prove 1.1 and 1.2 actually worked, and it
feeds Wave 3's panel.

---

## Wave 2 — skills that scale

### 2.1 Tool search escape hatch
**Read:** `reference/isair-jarvis/src/jarvis/tools/builtin/tool_search.spec.md`

We have 136 skills and route by keyword. Adopt their two-stage model: narrow routing
once before the loop, plus a `skill_search` tool the model can call to widen its own
allow-list mid-conversation.

- Cap at 3 calls per reply, mirroring their `tool_search_max_calls`.
- Never remove `stop` or the search tool itself from the allow-list.
- Note their explicit non-goal: it re-runs the *same* router, it is not a "dump every
  tool" surface and not an authorisation bypass.

### 2.2 Prompt-injection fencing for fetched content
**Read:** `reference/isair-jarvis/src/jarvis/tools/builtin/web_search.spec.md`

Any web page or file content entering a prompt gets wrapped in an explicit
untrusted-data fence, and the system prompt states that fenced content is data, never
instructions. Our guest lane is already hardened; this closes the other door.

---

## Wave 3 — the dashboard, end to end

The four remaining tabs are built but visually unverified. Finish them, then extend.

### 3.1 Verify and polish Activity / Code / Way of Working / Settings
Same treatment the Space tab got: screenshot each, fix spacing, hierarchy and contrast
against `dashboard/DESIGN-PLAN.md`.

### 3.2 Vitals panel with real cost data
**Read:** OpenJarvis's framing — energy, latency and cost as first-class metrics.

We already log RSS, `footprint`, and brain latency. Add a proper panel: memory trend
(both measures, since they disagree by 3.5x), brain latency distribution, per-lane hit
counts (reflex / fast / agent / local), and restart events. This is the "see everything
end to end" ask, backed by data we genuinely have.

### 3.3 Metadata-driven, writable Settings
**Read:** `reference/isair-jarvis/src/desktop_app/settings_window.spec.md`

Today Settings reads constants out of `jarvis_ear.py` by regex and is read-only. Move to
a declared schema (name, type, range, default, help) that generates the UI *and* enables
writing. Write only non-default values; preserve unknown keys; the daemon reloads on
change.

### 3.4 Desktop companion overlay
**Read:** `reference/ethanplusai-jarvis/desktop-overlay/JarvisOverlay.swift` (299 lines,
read it fully — the window configuration is the whole trick)

Port the *window mode*, not the stack:

```
window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
window.isOpaque = false
window.backgroundColor = .clear
window.ignoresMouseEvents = true
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
```

Content is a SwiftUI `Canvas` reusing our existing star and core rendering — no
WKWebView, no Three.js, no CDN. A small always-present Jarvis presence sitting above the
wallpaper and below every window, brightening when he is listening or speaking.

---

## Wave 4 — quality signal

### 4.1 Evals
**Read:** `reference/isair-jarvis/EVALS.md`

A fixture set of utterances with expected routing (which lane, which skill, memory
needed or not) run against the real dispatcher. Publish a pass rate. Without this,
every prompt change is unmeasured.

### 4.2 Spec files beside implementations
Adopt their `*.spec.md` convention for the load-bearing modules: barge-in, the reflex
table, the recall gate, skill routing. A short contract next to the code, updated in the
same commit as the behaviour.

### 4.3 Hold-to-dictate
**Read:** `reference/isair-jarvis/src/jarvis/dictation/`

Hold a hotkey, speak, release, text lands in the focused app. We already have Whisper
resident; this is mostly hotkey capture plus paste. Their known caveat: `pynput` is
broken on macOS 26 (Tahoe) — we are on Darwin 25, and should prefer a native event tap
regardless.

---

## Sequencing

Wave 1 first and alone: it is small, it targets the complaint with the longest history,
and 1.3 gives the measurements that tell us whether the rest is worth doing. Wave 3.1 can
run in parallel since it is UI work with no daemon risk.

Do not start Wave 2 until Wave 1's numbers are in — if the reflex table and recall gate
take typical turns under a second, the case for restructuring skill routing changes.

## Standing constraints

Everything here is subject to the rules this project already runs on:

- The daemon is always-on and launchd-managed. Deliberate exits must be non-zero
  (`sys.exit(75)`); a clean exit kills it permanently.
- Measure memory with `footprint`, never `ps`/psutil RSS.
- Lightweight-first. Our 804KB / 1.8% CPU native app is the lightest thing in this
  survey and that is a property to defend, not spend.
- Real data only, honest empty states, no fabricated placeholder content.
