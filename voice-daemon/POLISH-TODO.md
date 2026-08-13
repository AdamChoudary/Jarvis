# POLISH TODO — fixes, gaps, blocked functionality (item 3)

Ranked by Sir's explicitly stated pains first.

## P0 — Sir's direct complaints
- [x] **BARGE-IN (human-style interruption)** — "when I start to talk it should stop and listen".
      Implemented: Speaker.interrupt() terminates afplay subprocess, flushes queue.
      barge_in_monitor() daemon thread watches mic queue during TTS playback —
      sustained RMS > 1800 for 6 frames (~480ms) = real speech, not echo.
      9 interrupt checks after speaker.wait() in conversation loop exit immediately.
      Discrimination: Mac speaker echo ~800-1200 RMS; real speech at 1-2m ~2000-6000 RMS.
      Deployed 2026-07-19, PID 8942.
- [ ] **Instant trigger feel** — mention path = VAD segment close (~0.5-1s) + transcribe before
      anything audible happens. Add an immediate subtle chime the moment the name is matched
      (before the brain runs) so triggering FEELS instant; trial SILENCE_SECS 0.9→0.7.
- [ ] **Response time** — post-speech pipeline ≈ 0.9s silence + ~1.3s STT + 2-6s LLM
      (congestion-dependent) + ~1.7s first-sentence TTS. Levers: weekly brain-latency trend in
      ram-log → auto-flag congestion; consider promoting local brain when cloud is SLOW (not
      just down); STT small-mlx if base quality disappoints on Sir's voice.
- [x] **Hallucinations** — (a) whisper repetition loops: fixed in 3 stages — consecutive-word
      loops, phrase loops up to 4 tokens, hyphen-joined syllable loops (punctuation-stripped
      tokenization), and (2026-07-19 audit) extended phrase-loop detection from plen (2,3,4) to
      (2,3,4,5,6,7,8) after live-catching a 5-token loop ("I'm going to the beach." ×14) that
      slipped through. (b)/(c) mishears/invented-facts: not re-verified this pass, no live
      reproduction found — leave open, low urgency.

## P1 — architecture & organization (items 5-7)
- [x] git repo initialized (2026-07-19), .gitignore, first commit — code now versioned.
- [x] Project docs: README, ARCHITECTURE, FEATURES, MASTER-CONTEXT written 2026-07-19.
- [x] **Dashboard (item 6)** — built 2026-07-19/20: `dashboard.html` + `dashboard_server.py` +
      `open-dashboard.sh` in `~/.hermes/jarvis-voice/`. Observatory/celestial-atlas direction
      (`DESIGN.md`), real data only (326-doc graph, cron/project/idea rail, RAM+footprint
      vitals), design-qa-auditor pass applied (contrast, reduced-motion, amber discipline,
      focus/keyboard). Launch with `./open-dashboard.sh`.
- [ ] Wire brain.log + autonomy.db into sentry's weekly review.

## P2 — deferred by prior council rulings (scheduled, not forgotten)
- [ ] Waterfall gate (transcribe-first ambient path; emotion+speaker-ID only after name match)
      — ships at the 48h soak mark (~2026-07-20 morning). Cuts wasted 3-way inference on all
      room chatter: CPU + memory-churn win on top of the unified-memory fixes. **Audit (2026-07-19)
      found a second reason this matters**: ambient guest-lane chatter continuously refreshes
      `last_exchange`, which starves `distill_memory()`'s 600s idle trigger — Nemori distillation
      has never fired all session (zero log lines). This gate should fix that as a side effect.
- [ ] Idle-unload timer for SenseVoice+TitaNet — conditional: only if RSS doesn't settle well
      with the gate live (Architecture's re-baseline rule).
- [ ] Metal forensics: 1191MB IOAccelerator remains post-fix — identify what beyond whisper
      holds Metal memory (candidates: mlx residual pools; verify with per-engine footprint).
- [ ] **RAM_CEILING_MB recalibration off real `footprint`, not psutil RSS** (audit 2026-07-19) —
      `footprint <pid>` measured 5226MB phys_footprint while `_rss_mb()` (psutil) said 1634MB at
      nearly the same moment, a ~3.5x gap. The 2500MB emergency-restart ceiling is calibrated
      against psutil-RSS-scale numbers and will likely never fire even when true unified-memory
      use is 2x+ over budget. Shipped tonight: `_footprint_mb()` now logs `footprint_mb` alongside
      `rss_mb` in ram-log.jsonl every 10 min (~150ms/call, negligible). NOT yet done: swap the
      actual restart-decision source to footprint_mb and pick a real ceiling — needs a day or two
      of the new paired data first (one sample, taken right after heavy transient model loading,
      isn't a clean baseline). Revisit once ram-log.jsonl has a real footprint_mb trend.

## P3 — known gaps / blocked
- [ ] Telegram/pocket Jarvis — blocked on bot token from Sir (@BotFather, 2 min).
- [ ] Calendar/Mail skills — blocked on one-time macOS automation permission prompts (Sir must click OK on first use).
- [ ] ActivityWatch window watcher — blocked on Accessibility permission (System Settings).
- [ ] Client-radar's 4-sites-down finding — blocked on Sir confirming the real production domains.
- [ ] Voice cloning (NeuTTS) — deliberately shelved; models deleted; re-download on genuine need.
- [ ] Speaker-ID guest greeting only fires on main path, not follow-up (cosmetic).
- [ ] No "I'm back" announcement after an *external* kill/crash revival (audit 2026-07-19,
      confirmed via live `kill -9` test — launchd's KeepAlive revived it in ~2s, silently). Only
      `_self_restart()`'s deliberate paths announce. Rare in practice; low priority.
- [ ] Memory index retrieval: relevance scores uniformly low (0.02-0.03) across 4 spot-check
      queries (audit 2026-07-19) — not clearly broken, but never validated against true
      known-answer pairs. Worth a dedicated 10-query precision pass per the original audit method.