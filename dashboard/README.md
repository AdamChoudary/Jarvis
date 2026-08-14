# Jarvis Dashboard

A native macOS app (SwiftUI, built via Swift Package Manager — no Xcode
project needed) for seeing everything the Jarvis voice daemon is doing:
its memory as a live constellation graph, vitals, routines, projects and
ideas, its own source code, its architecture docs, and its actual running
configuration.

Built as a Swift Package rather than an .xcodeproj because this machine
only has the Command Line Tools installed, not full Xcode — `swift build`
works fine for a SwiftUI app; `xcodebuild` does not without Xcode itself.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+ / Xcode 15+ Command Line Tools (`xcode-select --install`) — a
  full Xcode install isn't required, just the toolchain
- A running [`voice-daemon`](../voice-daemon/) to have any real data to show —
  the app reads its state directly off disk (see [Data sources](#data-sources)
  below) and displays empty states otherwise

## Tabs

- **Space** — the memory graph: every indexed document (vault notes,
  opencode sessions, dev context files) as a node, self-drawn force-
  directed physics, clustered by source. Click a node to read the real
  file content. Overlaid with the Helm (vitals) and Log (today/projects/
  ideas) instruments, same as the HTML dashboard this evolved from.
- **Activity** — the full-detail version of Today/Projects/Ideas, plus a
  live feed of recent exchanges from ear.log.
- **Code** — browses jarvis-voice's own .py/.sh/.md source files.
- **Way of Working** — renders the project's existing architecture/
  features/master-context docs natively, so this view can't drift from
  what's actually written down elsewhere.
- **Settings** — read-only view of jarvis_ear.py's tunable constants and
  ~/.hermes/.env (secrets redacted), sourced live from those files, not a
  separate config schema.

## Build & run

```
./build-app.sh          # builds release + assembles ~/Applications/Jarvis.app
open ~/Applications/Jarvis.app
```

For iteration during development:

```
swift run                # debug build, runs in Terminal
```

## Data sources

Everything is read directly from disk — no server, no network:
`~/.hermes/jarvis-voice/{ear.log,ram-log.jsonl,jarvis-memory-v7.db,
knowledge-graph.db}`, `~/.hermes/cron/jobs.json`, `~/.hermes/.env`, and
the Obsidian vault's `Jarvis/Projects` and `Jarvis/Ideas` folders. All
reads are read-only; this app never writes to any of Jarvis's own state.
