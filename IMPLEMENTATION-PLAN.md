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

### 2.1 Tool search escape hatch — DONE (already existed upstream)
**Read:** `reference/isair-jarvis/src/jarvis/tools/builtin/tool_search.spec.md`

Turns out this is moot for us: `jarvis_ear.py`'s `fast_lane()` is a single-shot completion
with no tool loop at all — every actual tool call already routes through `agent_lane()` to
the Hermes gateway, and `~/.hermes/hermes-agent/tools/tool_search.py` already implements a
strictly more capable version of this than isair's: progressive disclosure with three
bridge tools (`tool_search`/`tool_describe`/`tool_call`), a context-budget threshold gate,
and a hard rule that core tools never defer. Nothing to port here.

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

### 3.3 Metadata-driven, writable Settings — DONE
**Read:** `reference/isair-jarvis/src/desktop_app/settings_window.spec.md`

Adapted, not copied: isair's world has one config.json and six widget types; ours has
top-level tunable constants inside `jarvis_ear.py`, so the registry is `ConfigReader.
editableFields: [String: FieldMeta]` (min/max/step/isInt) and "write" means an anchored,
comment-preserving single-line regex replace (`ConfigWriter.write`), never touching any
other line. 11 numeric constants made writable (wake sensitivity, barge-in, RAM ceiling,
timing windows); voice-engine names, audio-format constants (`RATE`/`CHUNK`), and the one
computed-expression constant (`MIN_UPTIME_FOR_NIGHTLY = 20 * 3600`) stay read-only, same
spirit as isair's own "Fields NOT Exposed in UI" list. `.env` stays fully read-only (out
of scope, different risk class). Restart is a separate, explicit button — never automatic
on save, matching their confirm-before-restart flow.

Caught and fixed during build: the first version used a Stepper, and one still-unexplained
interaction wrote incorrect values (0.1/0.4) to the *live* daemon's actual source file
mid-session, caught via `git diff` and immediately reverted (the daemon was never
restarted while wrong, so its running behavior was never affected). Root cause wasn't
pinned down with certainty, but a Stepper's continuous-press chevrons are a known-flaky
control, so it was replaced with a plain type-and-commit TextField — a class of widget
that cannot fire without deliberate typed input. Re-verified clean over a subsequent idle
window with no interaction.

### 3.4 Desktop companion overlay — DONE
**Read:** `reference/ethanplusai-jarvis/desktop-overlay/JarvisOverlay.swift` (299 lines,
read it fully — the window configuration is the whole trick)

Ported the *window mode*, not the stack — same click-through, desktop-level, all-Spaces
`NSWindow` configuration, but content is a native SwiftUI `Canvas` reusing our existing
star/core rendering (no WKWebView, no Three.js, no CDN). `OverlayWindow.swift`.

Brightening on listening/speaking landed too: `jarvis_ear.py` now calls `write_state()` at
every wake/thinking/working/speaking/idle transition, atomically to `state.json`; the
overlay polls it once per animation frame (12fps) and falls back to idle on a stale
(>30s) or missing file.

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

### 4.3 Hold-to-dictate — DONE
**Read:** `reference/isair-jarvis/src/jarvis/dictation/`

Hold Control+Option anywhere, speak, release, text lands in the focused app via
clipboard + synthetic Cmd+V. `jarvis_dictation.py`, wired into `listen_loop()`'s boot
sequence. Built on a native `Quartz` `CGEventTap` rather than `pynput` per this plan's own
note (their spec documents a pynput crash on macOS 26/Tahoe; native avoids the landmine
entirely rather than deferring it). Shares the daemon's already-loaded Whisper model —
no second model instance.

Verified end to end with a synthetic modifier-hold (not just unit tests): the live daemon
recorded real ambient audio, transcribed it, and the result landed on the clipboard.

Scope cut, documented in `jarvis_dictation.py`'s module docstring: no hands-free
double-tap mode, no LLM filler-word removal (isair's calls a local Ollama instance we
don't run). Custom-dictionary replacement shipped since it was one function's worth of
work.

---

## Wave 5 — the last two ethanplusai/OpenJarvis gaps

### 5.1 macOS Calendar/Reminders/Notes access — DONE
**Read:** `reference/ethanplusai-jarvis/calendar_access.py`, `notes_access.py`

Audited hermes-agent first (the actual execution engine behind `agent_lane()`) and
confirmed this was genuinely missing — no Calendar/Mail/Notes/Reminders tool anywhere in
`tools/*.py`. Per hermes-agent's own `AGENTS.md` footprint guidance, a personal macOS-only
integration belongs in the **plugin** route, not core: shipped as
`~/.hermes/plugins/macos_productivity/` (7 tools — `calendar_list_events` read-only,
`reminders_list/create/complete`, `notes_search/read/create`). Notes never edits or
deletes an existing note, matching ethanplusai's own stated safety precedent for that
file. No Mail tool at all — out of scope, sensitive content class, wasn't worth the risk
for this pass.

Verified end to end through the *real* agent path, not just direct tool calls: restarted
the `ai.hermes.gateway` launchd service so it picked up the newly-enabled plugin, then
asked it (via `agent_lane()`, the same path voice queries take) to search Notes for a
just-created test note and report its exact body back — content it could only have known
by genuinely invoking `notes_search`/`notes_read`, not by guessing.

### 5.2 Persistent/spawnable coding sessions — moot, already covered upstream
**Read:** `reference/ethanplusai-jarvis/work_mode.py`

hermes-agent's `AGENTS.md` already documents this exact pattern: `delegate_task(background=
true)` for process-local durability, or `terminal(background=True, notify_on_complete=
True)` when the work must survive a process restart. Both are already-registered,
already-reachable tools — the same precedent as 2.1's tool_search finding. Nothing to
port; ethanplusai's dedicated "work mode" abstraction is a thinner, less configurable
version of what already exists here (no configurable concurrency caps, spawn-depth
limits, or timeout knobs).

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
