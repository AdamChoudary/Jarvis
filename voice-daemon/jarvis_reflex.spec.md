# Reflex table spec

Instant deterministic answers checked in `dispatch()` before any LLM call.
Implementation: `jarvis_reflex.py`. Evals: `evals.py` (routing section).

## Contract

- `reflex(text) -> str | None`. A string is spoken verbatim and recorded in
  history as a normal turn (lane `reflex` in ram-log). None falls through to
  the brain chain untouched.
- Fires only on a confident whole-utterance match. The failure mode to fear
  is a wrong instant answer, not a slow correct one — when in doubt, None.

## Guards, in order

1. Length: > 10 words is a real question even if it contains a trigger word.
2. Escape hatch regex: why/should/remind/schedule/tomorrow/... — anything
   that needs judgement, memory, or a side effect is never reflexive.
3. Patterns are anchored `^...$`; substring matches are forbidden
   ("what time should I leave" must not trip the time reflex).
4. Handlers are pure reads. No handler may change state, so the worst
   misfire is an irrelevant sentence.
5. Any handler exception returns None — a broken reflex must never eat the
   turn.

## Current families

Time / date / battery / memory (footprint, never ps) / uptime / day-left,
plus sukeesh-style deterministic tasks: coin, dice, random number in range,
spoken-friendly password, temperature and length/mass conversion. Mixed
dimensions, inverted ranges and degenerate dice deliberately return None.

## Non-goals

- Jokes, opinions, anything persona-flavoured: the butler voice lives in the
  LLM lanes.
- Anything requiring context from history or memory.
- Timers/reminders (side effects — agent lane's job).
