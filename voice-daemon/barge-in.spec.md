# Barge-in spec

Interrupt Jarvis mid-speech like a person, then continue on the new topic.
Implementation: `Speaker.interrupt()`, `barge_in_monitor()`,
`speak_and_listen()` in `jarvis_ear.py`. Tests: `test_bargein.py`,
`test_bargein_e2e.py`.

## Behaviour

While Jarvis is speaking, sustained real speech over the playback stops him,
captures the interruption, transcribes it, and feeds it back into the
conversation loop as the next turn (`first`). Not just "stop talking":
stop, listen, answer the new thing.

## Discrimination

RMS energy over the mic queue: Mac-speaker echo measured ~800-1200 on this
machine; real speech at 1-2m is 2000-6000+. Threshold `BARGE_IN_RMS=1800`,
sustained for `BARGE_IN_FRAMES=6` (~480ms) — a cough or a clink must not
trigger it.

## Invariants (each one was once a live bug)

1. `interrupt()` MUST decrement `_pending` for every queued item it drains.
   Missing this hung `wait()` — and the whole daemon — after any
   multi-sentence barge-in.
2. A fresh monitor thread per speaking phase, armed by waiting for
   `_pending > 0` (bounded by `BARGE_IN_ARM_TIMEOUT`). A single
   conversation-entry monitor saw `_pending == 0` and exited before anything
   was queued: barge-in only ever worked on the first reply.
3. `wait()` carries a hard ceiling as defence in depth: an accounting bug
   anywhere must degrade to a long pause, never a daemon hang.
4. An interrupted-but-garbled capture returns `()` — stop speaking, hand
   nothing off. Silence beats answering noise.
5. `_player()` must skip (and unlink) items already queued when the
   interrupt fired.

## Out of scope

Voice enrollment stays sequential — interrupting mid-enrollment would be
actively unhelpful.
