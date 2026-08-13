# DESIGN.md — Jarvis Dashboard

Source of truth for the look. Downstream build agents obey the dials and the banned list.

**2026-07-28: fully rewritten.** The observatory theme this file used to describe (cool `#0A0C11` void, desaturated cluster hues, banned "arc-reactor gauges"/"literal orbit rings") was explicitly rejected and replaced with a ground-up redesign. Everything below reflects what's actually shipped, not what preceded it.

## Design read
An always-on desktop instrument for one user (Sir), running all day on a Mac. Read it as a real extension of Claude's own product — Claude Desktop's warm, editorial, serif-voiced chrome as the base material, with the pixel-sampled rainbow HUD dial as a deliberate, literal instrument at the centre: an island that doesn't match the calm around it on purpose. This is Jarvis's own control center, not a generic admin panel and not an Iron-Man HUD cosplay either — the drama is spent in exactly one place (the dial and the connections it powers), everything else stays quiet.

## Vibe (one line)
A warm study, not a cockpit. Claude's own paper-and-ink restraint holding one vivid, living instrument at its centre — calm chrome, serif prose, and real data that visibly connects to itself everywhere it appears.

## Palette (verified, not approximated)
Cross-referenced against Claude's real brand values, not "confident knowledge" — the first pass at this palette used `#D97757` for the accent; the real value is one hex digit different.
- **Void:** warm charcoal `#262624`, raised `#30302E`, sunken `#1F1E1D`. Never cool, never pure black.
- **Ink:** warm near-white `#F5F4ED`, stepping down through `#B3B0A8` (dim) and `#7A7870` (faint).
- **Accent — terracotta, reserved for Jarvis-state/selection only:** `#DA7756`, deep/pressed shade `#BD5D3A`. An 8-step tonal ramp exists (`Theme.accentRamp`) for real hierarchy, not a flat single color.
- **Domain identity — one color per real data source, used consistently everywhere that data appears** (sidebar badges, orrery bodies, Log rail icons, Activity panels — not just wherever it happened to be built first): opencode `#5FA3A0`, vault `#8E86C9`, context `#6E9E7C`, voice `#7C89A6`, knowledge-graph `#C9A15A`. A cool 8-step ramp (`Theme.coolRamp`) backs these for the same reason the accent has one.
- **Fail:** `#C9504A`.

## Typography (verified from Claude's real site, corrected from an earlier "confident knowledge" guess)
Claude's actual body/display font stack is **serif** (`ui-serif, Georgia, Cambria, "Times New Roman", Times, serif`) — a genuinely distinctive choice most AI products don't make, and the single biggest miss in the first redesign pass, which used plain system sans throughout.
- **Real content — titles, headings, document prose, panel headers:** serif (`Theme.serif(_:weight:)`, SwiftUI `design: .serif` — renders as "New York" on macOS, the native equivalent of the web's `ui-serif`).
- **Dense small UI chrome — nav labels, badges, section-group labels, stat-tile captions:** system sans, small and tracked. Claude's own smallest UI text stays sans too; serif is reserved for content, not chrome.
- **All data — numbers, timestamps, code, file paths, statuses:** monospace (`Theme.mono`), same as before. The mono/serif/sans three-way split (not a sans-only stack) is itself part of what reads as deliberate rather than generic.

## Structure: one honest shape per section, not a template
Each tab is shaped by what it actually contains, not decorated to match a shared template — a uniform "everything is a card in a grid" (or "everything overlaid on a starfield") look was tried and explicitly rejected as reading like the same UI underneath no matter how much was re-skinned on top.
- **Space:** a real spatial map — the HeroDial at the centre, concentric orbit bands for memory sources, a routines ring, and (new) a knowledge-graph ring with literal connection threads between entities — plus a fixed instrument column beside it (not floating overlay cards on top of it, which was the first pass's mistake).
- **Activity:** a genuine grid of independent measurements (memory, knowledge, routines, work) beside a conversation feed — a grid says "these don't have a reading order," which a hand-stacked column didn't.
- **Code / Way of Working:** a file-tree + content pane, grouped by real category (Python/Shell/Docs; here, by rendering the project's own docs) — the right shape for a reference browser, not forced into spatial or card-grid novelty for its own sake.
- **Settings:** utilitarian, restrained, closest to Claude's own settings surfaces — this is deliberately the calmest tab in the app.

## Connections: map what's real, nothing invented
The literal answer to "map the connections, every feature" — and the discipline that keeps it honest:
- Every real data domain gets **one** color/icon identity, reused everywhere it appears (sidebar, orrery, Log rail, Activity panels) — so the same cron job or vault note reads as visibly the same thing in every place it shows up, not a coincidence you have to click to discover.
- A domain with no live signal gets **no invented pulse or badge** — Code/Way of Working/Settings carry no fabricated "activity" indicator in the sidebar, because there's no real data behind one. Decoration standing in for data is exactly what this file bans below.
- Empty/dormant real data (the knowledge graph currently has 0 entities until distillation runs) gets an **honest, deliberate empty state** — never a fake/sample node just to look populated.
- A read failure and a genuinely-empty result must never look identical to the user — services distinguish `readOk` from empty, and the UI should surface that distinction where it matters (see `HelmView`'s confidence glyph).

## Motion
- Named, shared spring presets (`Animation.settle` = stiffness 210/damping 16, `Animation.snappy` = 320/20) — new interactions reuse these, not a fresh bespoke spring value each time.
- Ambient motion (the orrery's drift, the dial's independent-rate ring rotations) stays continuous but never demanding — it runs all day and must never fatigue or pull the eye.
- Discrete state changes use `.contentTransition`/`.animation(_:value:)`, not continuous loops layered on top of already-continuous `TimelineView(.animation)` canvases — stacking free-running animations on top of high-frequency data ticks is a real perf/stability risk, not just a style concern (a `@Published` property that re-fires on no actual change, multiplied across several observers, has caused a real reentrant-layout crash here before — dedupe at the source).
- `accessibilityReduceMotion` is threaded everywhere motion is added, including hover/magnetic modifiers — a gap in the first version of `MagneticModifier`, since closed.

## The hero dial — a deliberate exception to everything above
The rainbow HUD dial (`HeroDial.swift`) is pixel-sampled from a real reference and kept exactly as sampled — it does not follow the warm/restrained palette above, on purpose. It's a vivid, literal instrument sitting inside otherwise-calm chrome, not re-skinned to match it. Its own tick ring and highlight arcs each turn at independently, never-synchronized rates (an animejs-derived technique) — nothing here should ever move in lockstep.

## Do's (concrete)
1. Commit to Claude's actual warm chrome and verified serif typography — not an approximation of either.
2. One color per real data domain, reused everywhere that domain's data appears, not invented per-view.
3. Let each tab's structure follow its real content; a shared template across dissimilar content is decoration, not design.
4. Real data only, honest empty/dormant states, and a visible distinction between "empty" and "failed to read."
5. Named motion presets, reduce-motion guards everywhere, dedupe published values that don't need to re-fire on no change.

## Banned (anti-slop, this project)
- A uniform layout template forced across tabs with genuinely different content (the exact mistake corrected this round).
- Fabricated live badges/pulses for a destination or panel with no real backing data.
- Sample/fake nodes or entities to make an empty or dormant dataset look populated.
- Approximating a real, checkable brand fact (a color, a font) from "confident knowledge" when the real value can be found and verified instead.
- Continuous/free-running animation stacked on top of already-continuous canvases or high-frequency data ticks without a reduce-motion guard.
- Inter / Roboto / Space Grotesk / Open Sans / plain system sans for real content — Claude's own serif is the point.
- Emoji as iconography. Em-dash in visible body text where a hyphen reads more like Claude's own copy.
- Cyan/blue holographic glow, reticles, corner brackets, scanning/sweep lines, fake boot logs — none of that was ever part of this system and still isn't.

## Direction conflicts resolved
- "Look exactly like Claude Desktop" vs. "the HeroDial's own rainbow palette": resolved by treating the dial as a deliberate island (see above) rather than re-skinning it to match — the reconciliation this session settled on and re-validated across every redesign round since.
- Density vs. Claude's own restraint: dense tabular data (Activity's stat tiles, Code's line numbers) stays confined to those specific instruments; anywhere the content is prose or a title, serif and real breathing room win.
- "Diversified per section" vs. "still one coherent app": resolved by keeping the token layer (palette, type scale, motion presets) identical everywhere, while letting structure vary — the shared foundation is what keeps five differently-shaped tabs from reading as five different apps.
