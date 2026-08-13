# The Jarvis landscape — four open-source assistants, and where ours stands

In-depth analysis of four public Jarvis projects, cloned into `reference/`, against
our own build. Written to answer three questions: what do they have that we don't,
how are their interfaces actually built, and what makes them light or heavy.

All four are pinned at the shallow clone taken 2026-07-20.

---

## 1. The four at a glance

| | **sukeesh/jarvis** | **isair/jarvis** | **ethanplusai/jarvis** | **open-jarvis/OpenJarvis** | **ours** |
|---|---|---|---|---|---|
| Pitch | "Personal **non-AI** assistant" | 100% private local voice AI | Voice-first Mac assistant, MCU flavour | Stanford research framework for local-first AI | Always-on Mac voice butler |
| Size | 292 py | 204 py | 27 py + 7 ts + 2 swift | 1318 py + 127 rs + 51 tsx | ~1.5k-line daemon + Swift app |
| Interface | CLI only | PyQt6 tray app + Flask memory viewer | Browser (Vite/TS) + Swift overlay | Tauri + React 19 | Native SwiftUI |
| Brain | None (rule-based) | Local Ollama | Claude API | Local-first, cloud fallback | Free cloud tier, local fallback |
| Voice | Optional TTS | Whisper + wake word | Web Speech + Fish Audio | Optional | openWakeWord + mlx-whisper + Edge/Kokoro |
| Memory | None | Knowledge graph + diary + embeddings | SQLite + FTS5 | Trace store + learning loop | SQLite FTS5 + vectors + KG (empty) |
| Standout | Breadth of tasks | Architecture discipline | Aesthetic | Energy as a metric | Barge-in, unified-memory rigour |

---

## 2. Repo-by-repo

### 2.1 sukeesh/jarvis — the breadth benchmark

Deliberately **not** an AI assistant. A plugin CLI with ~18 categories of deterministic
tasks: unit conversions, sports scores, games, health calculators, network tools, PDF
and image conversion, QR codes, weather, translation, stocks.

**Architecture.** `jarviscli/plugins/` is a flat directory where each file registers
itself via a decorator. The plugin manager scans, builds a command table, and dispatches
on the first matching word. No LLM, no intent model, no embeddings.

**What it teaches us.** Two things. First, a decorator-registered flat plugin directory
is a genuinely low-friction extension model. Second, and more useful: *deterministic
commands should not go through an LLM at all*. Our daemon currently routes almost
everything through NIM/Zen and pays 2-6s. "What time is it", "battery", "how much RAM"
are pure function calls. A small deterministic pre-brain would cut the most common
queries to near-zero latency.

**What it lacks.** No GUI, no memory, no voice conversation. Not a UI reference.

---

### 2.2 isair/jarvis — the architecture benchmark

The most disciplined codebase of the four, and the closest to what we are building.
100% local, privacy as a hard constraint, automatic redaction of secrets before any
disk write.

**Feature set.** Wake-word-anywhere-in-sentence conversation, unlimited memory via a
self-organising knowledge graph, hold-to-dictate that types into any app, MCP tool
integration, screen reading, Chrome control, nutrition tracking, web search with an
SSRF guard and prompt-injection fencing, and automated evals with a published accuracy
table.

**Interface — two separate surfaces:**

1. **PyQt6 system tray app** (`src/desktop_app/`). A native widget toolkit, not a
   browser. `face_widget.py` (45KB) draws an animated face with pure `QPainter`
   primitives and a `math`/`random` driven animation loop — no game engine, no WebGL.
   `settings_window.py` (47KB) is **generated from config metadata**, so adding a
   setting to the config schema creates its UI automatically.
2. **Flask-served memory viewer** (`memory_viewer.py`, 152KB). Local HTTP + HTML for
   the data-dense views: diary, knowledge graph, meals. They deliberately chose the
   web stack for *browsing structured data* and the native toolkit for *the always-on
   chrome*.

**Why it is lightweight.** PyQt6 draws with the platform's own toolkit; the heavy
browser is only spawned for the viewer, on demand, and is a page not a bundled runtime.
Nothing is Electron.

**The four ideas most worth stealing** (all documented in `*.spec.md` files sitting
next to their implementations, a practice worth copying on its own):

- **Recall gate** (`memory/recall_gate.spec.md`). A ~1ms pure-Python heuristic that
  decides whether memory enrichment is needed *at all*, before paying for it. Skips
  when the conversation's hot window already contains a tool result and the query's
  content words overlap it by ≥50%. Fails open. Language-agnostic via
  `\w{3,}` + `re.UNICODE` rather than hardcoded English patterns.
- **Tool search escape hatch** (`tools/builtin/tool_search.spec.md`). Tools are routed
  narrowly once before the loop; if the model discovers mid-conversation that it needs
  something outside that set, it calls `toolSearchTool` to widen its own allow-list.
  Capped at 3 calls per reply. This is the answer to "how do you have hundreds of tools
  without context rot" — directly relevant to our 136 skills.
- **Echo detection + intent judge** (`listening/`). Separate modules for "is this my own
  speaker output" and "was this addressed to me". We solved echo with an RMS threshold;
  they solved it with a dedicated module, and their README lists the failure mode we
  should watch for: *"stop commands during speech sometimes get filtered as echo"*.
- **Metadata-driven settings UI.** Our Settings tab is hand-written and read-only.
  Theirs generates from the config schema and writes back only non-default values,
  preserving unknown keys.

---

### 2.3 ethanplusai/jarvis — the aesthetic benchmark

The closest to ours in *character*: British butler, dry wit, macOS-only, AppleScript
for Calendar/Mail/Notes, "Will do, sir." It can spawn Claude Code sessions to build
software by voice.

**Interface — a browser app plus a desktop overlay:**

- **Frontend** (`frontend/src/`, 7 TS files). Vite + TypeScript + Three.js. `orb.ts` is
  an audio-reactive particle orb; `voice.ts` uses the Web Speech API; `ws.ts` holds a
  WebSocket to a FastAPI backend carrying JSON plus binary audio.
- **Desktop overlay** (`desktop-overlay/JarvisOverlay.swift`, 299 lines). This is the
  clever part and worth reading in full. A borderless, transparent, **click-through**
  `NSWindow` pinned at `CGWindowLevelForKey(.desktopWindow) + 1` — above the wallpaper,
  below every real window — hosting a `WKWebView` with `drawsBackground = false`. The
  orb therefore floats on your desktop, visible between windows, and never intercepts a
  click. `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]` keeps it
  on every Space and out of Cmd-Tab.

**Is it lightweight?** The window trick is elegant and cheap. The content is not: 2000
particles plus up to 6000 line segments in WebGL, with `three.module.js` pulled from a
**CDN at runtime**, inside a WebKit process. That is a browser engine and a network
dependency for a decorative orb. Our whole native app is 804KB and idles at 1.8% CPU.

**What to steal.** Not the stack — the *window mode*. A click-through desktop-level
companion layer is a genuinely great idea for an always-on assistant, and in our case it
would be a `Canvas` in the app we already have, with no WebKit and no CDN.

---

### 2.4 open-jarvis/OpenJarvis — the systems benchmark

A Stanford research framework (arXiv 2605.17172) rather than a personal assistant.
Premise: local models already handle 88.7% of single-turn queries, so route to the cloud
only when genuinely necessary.

**Architecture.** 1318 Python files, 127 Rust files across a `rust/crates/` workspace,
and a Tauri desktop app. Presets (`morning-digest`, `deep-research`, `code-assistant`,
`scheduled-monitor`, `chat-simple`) configure whole agent behaviours in one command.
Skills install from a catalogue (`jarvis skill install hermes:arxiv`) — the same
agentskills-style ecosystem our Hermes layer already speaks.

**Interface.** Tauri v2 + React 19 + Tailwind 4 + shadcn + `motion` + `recharts`, with
`zustand` for state. Tauri means a Rust shell around the OS's *own* webview rather than
a bundled Chromium, so the binary is tens of MB instead of Electron's hundreds. Their
`tauri.conf.json` ships a strict CSP limiting `connect-src` to localhost only.

**The idea worth stealing.** They treat **energy, FLOPs, latency and dollar cost as
first-class metrics alongside accuracy**, and the desktop app exists largely to
visualise them: real-time energy monitoring, trace debugging, learning-curve charts.
We already measure unified memory with `footprint` and log brain latency — we are one
step from a genuine cost/latency panel, and we have the honest data to fill it.

---

## 3. Interface strategies compared

| Approach | Used by | Binary/runtime cost | Verdict for us |
|---|---|---|---|
| CLI only | sukeesh | ~0 | Insufficient |
| Native widgets (PyQt6) | isair (tray/face) | Python + Qt (~50MB dep) | Right instinct, wrong language for us |
| Local HTTP + HTML | isair (memory viewer) | A page, on demand | Good for data-dense browsing |
| Browser app + WS backend | ethanplusai | Full browser + Node dev server | Too heavy for always-on |
| WKWebView desktop overlay | ethanplusai | WebKit process + CDN fetch | Steal the *window mode*, not the stack |
| Tauri (Rust + system webview) | OpenJarvis | Tens of MB | Reasonable, still a webview |
| **Native SwiftUI** | **ours** | **804KB, 1.8% CPU** | **Lightest of everything surveyed** |

Our path is already the most efficient. Nothing here argues for changing stacks. What it
argues for is adopting their *ideas* — the overlay window mode, the metadata-driven
settings, the energy/latency panel, the on-demand data viewer — inside the native app.

---

## 4. What they have that we do not

Ranked by value to us.

| Gap | Who has it | Why it matters here |
|---|---|---|
| **Recall gate before memory search** | isair | We pay for memory enrichment on every turn. A measured 15s cold start and ~0.5s warm, every time, much of it unnecessary. |
| **Deterministic pre-brain for simple commands** | sukeesh | "What time is it" should never cost an LLM round trip. Directly attacks the response-time complaint. |
| **Tool/skill routing that scales** | isair | We have 136 skills and no routing story beyond the agent lane. |
| **Hold-to-dictate into any app** | isair | Genuinely useful daily, and we already have Whisper loaded. |
| **Metadata-driven settings UI** | isair | Our Settings tab is read-only and hand-maintained. |
| **Desktop-level click-through companion** | ethanplusai | An always-on assistant deserves an always-visible presence. |
| **Energy / cost / latency panel** | OpenJarvis | We have the data (`ram-log.jsonl`, brain latency) and no view of it. |
| **Automated evals with published accuracy** | isair | We verify by hand; no regression signal on reply quality. |
| **Spec files next to implementations** | isair | Their `*.spec.md` convention makes intent auditable. We have docs, but not per-module contracts. |
| **Prompt-injection fencing on web content** | isair | Our guest lane is hardened; fetched web content is not explicitly fenced. |

## 5. What we have that they do not

Worth stating plainly, because it is not a short list.

- **True barge-in with capture-and-continue.** isair explicitly lists interrupting-
  during-speech as a *known limitation*. Ours stops, captures the interruption,
  transcribes it, and answers the new topic.
- **Unified-memory honesty.** We measure with `footprint`, not `ps`, after finding a
  3.5x undercount. No other project here distinguishes the two.
- **Self-healing runtime.** RAM-ceiling restart, nightly housekeeping, and a dead-audio-
  stream detector that recovers from Bluetooth stealing the input device.
- **Hallucination guards.** A three-class repetition-loop detector built from real
  failures observed in our own logs.
- **The lightest interface of the five**, by an order of magnitude.
- **A real orrery** as the memory view, rather than a conventional force graph.
