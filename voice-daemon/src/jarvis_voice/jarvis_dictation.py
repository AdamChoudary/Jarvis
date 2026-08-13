"""Hold-to-dictate — isair/jarvis's WisprFlow-style engine, ported to a native
CGEventTap instead of pynput. isair's own spec flags pynput as broken on
macOS 26/Tahoe (TSM main-thread assertion crash); we're on Darwin 25 today,
but there's no reason to build on a dependency with a documented landmine
when the platform-native tap does the same job with nothing to pip-install
around it going forward.

Independent of the assistant pipeline by design: no wake word, no intent
judging, no TTS, no history. Hold the hotkey anywhere on the system, speak,
release, and the transcription is pasted into whatever app has focus.

Shares the ear daemon's already-loaded Whisper model (jarvis_ear.load_whisper()
is a cached singleton) rather than loading a second copy — a duplicate model
would cost another few hundred MB of unified memory for a feature used in
short bursts, which is exactly the tradeoff this project has repeatedly
measured and rejected elsewhere (see the whisper-base-mlx comment in
jarvis_ear.py).

Scope cut deliberately, both documented in dictation.spec.md: no hands-free
double-tap mode (adds a real tap-timing state machine for a secondary flow),
no LLM filler-word removal (isair's version calls a local Ollama instance we
don't run — our brain chain is NIM/Zen/local Qwen). CUSTOM_DICTIONARY below
covers the one piece of their post-processing pipeline cheap enough to keep.
"""
import re
import subprocess
import threading

import numpy as np
from Quartz import (
    CGEventTapCreate, kCGSessionEventTap, kCGHeadInsertEventTap,
    kCGEventTapOptionListenOnly, CGEventMaskBit, kCGEventFlagsChanged,
    CGEventGetFlags, kCGEventFlagMaskControl, kCGEventFlagMaskAlternate,
    kCGEventFlagMaskCommand, kCGEventFlagMaskShift,
    CFMachPortCreateRunLoopSource, CFRunLoopGetCurrent, CFRunLoopAddSource,
    kCFRunLoopCommonModes, CGEventTapEnable,
    CGEventCreateKeyboardEvent, CGEventPost, kCGHIDEventTap, CGEventSetFlags,
)
from CoreFoundation import CFRunLoopRun

from . import jarvis_ear as je

# Modifier-only combo, matching isair's macOS default (WisprFlow-aligned).
# ctrl+alt is the one preset in their list that never collides with a system
# or app shortcut. A held modifier set with anything else in _OTHER_MODIFIERS
# also down does NOT count as a match, so Cmd+Ctrl+Alt-anything (many window
# manager shortcuts) never mis-fires dictation.
_HOTKEY_MASK = kCGEventFlagMaskControl | kCGEventFlagMaskAlternate
_OTHER_MODIFIERS_MASK = kCGEventFlagMaskCommand | kCGEventFlagMaskShift

MIN_RECORD_SECS = 0.3     # shorter than this is almost certainly a mis-tap, not speech
CUSTOM_DICTIONARY = []    # [("wrong", "right"), ...] — case-insensitive whole-word

_state_lock = threading.Lock()
_recording = False
_frames = []
_stream = None


def _matches_hotkey(flags):
    return (flags & _HOTKEY_MASK) == _HOTKEY_MASK and not (flags & _OTHER_MODIFIERS_MASK)


def apply_dictionary(text):
    for wrong, right in CUSTOM_DICTIONARY:
        text = re.sub(rf"\b{re.escape(wrong)}\b", right, text, flags=re.IGNORECASE)
    return text


def _start_recording():
    global _recording, _frames, _stream
    import sounddevice as sd
    with _state_lock:
        if _recording:
            return
        _recording = True
        _frames = []
    je.chime(je.CHIME_WAKE)

    def cb(indata, frames, t, status):
        with _state_lock:
            if _recording:
                _frames.append(indata[:, 0].copy())

    try:
        stream = sd.InputStream(samplerate=je.RATE, channels=1, dtype="int16",
                                 blocksize=je.CHUNK, callback=cb,
                                 **je._resolve_audio_device())
        stream.start()
        with _state_lock:
            _stream = stream
    except Exception as e:
        je.log(f"dictation: failed to open input stream ({e})")
        with _state_lock:
            _recording = False


def _stop_recording():
    """Runs off the tap callback thread by design: CGEventTap callbacks must
    return quickly or the OS can disable the tap, so teardown, transcription,
    and paste all happen on a background thread, matching isair's own
    threading-safety note for exactly this reason."""
    global _recording, _stream
    with _state_lock:
        if not _recording:
            return
        _recording = False
        frames = _frames.copy()
        stream = _stream
        _stream = None
    if stream is not None:
        try:
            stream.stop()
            stream.close()
        except Exception:
            pass
    je.chime(je.CHIME_FOLLOWUP)
    threading.Thread(target=_process, args=(frames,), daemon=True).start()


def _process(frames):
    if not frames:
        return
    audio = np.concatenate(frames).astype(np.float32) / 32768.0
    if len(audio) < je.RATE * MIN_RECORD_SECS:
        je.log("dictation: too short, discarding")
        return
    try:
        text = je.transcribe(je.load_whisper(), audio).strip()
    except Exception as e:
        je.log(f"dictation: transcription failed ({e})")
        return
    if not text:
        return
    text = apply_dictionary(text)
    je.log(f"dictation: {text!r}")
    _paste(text)


_KEYCODE_V = 9

def _paste(text):
    try:
        p = subprocess.Popen(["pbcopy"], stdin=subprocess.PIPE)
        p.communicate(text.encode("utf-8"), timeout=5)
    except Exception as e:
        je.log(f"dictation: clipboard write failed ({e})")
        return
    down = CGEventCreateKeyboardEvent(None, _KEYCODE_V, True)
    up = CGEventCreateKeyboardEvent(None, _KEYCODE_V, False)
    CGEventSetFlags(down, kCGEventFlagMaskCommand)
    CGEventSetFlags(up, kCGEventFlagMaskCommand)
    CGEventPost(kCGHIDEventTap, down)
    CGEventPost(kCGHIDEventTap, up)


def _tap_callback(proxy, event_type, event, refcon):
    if event_type == kCGEventFlagsChanged:
        flags = CGEventGetFlags(event)
        if _matches_hotkey(flags):
            _start_recording()
        else:
            with _state_lock:
                was_recording = _recording
            if was_recording:
                _stop_recording()
    return event


def start():
    """Call once at daemon boot. The event tap's CFRunLoop blocks forever, so
    it runs on its own daemon thread — never the main thread, or it would
    starve everything else in the process."""
    def _run():
        tap = CGEventTapCreate(
            kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
            CGEventMaskBit(kCGEventFlagsChanged), _tap_callback, None)
        if tap is None:
            je.log("dictation: could not create event tap — grant Accessibility "
                   "access to this Python (System Settings > Privacy & Security > "
                   "Accessibility), then restart the daemon. Dictation stays off "
                   "until then; the rest of Jarvis is unaffected.")
            return
        source = CFMachPortCreateRunLoopSource(None, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes)
        CGEventTapEnable(tap, True)
        je.log("dictation: hold Control+Option anywhere to dictate")
        CFRunLoopRun()
    threading.Thread(target=_run, daemon=True, name="dictation-tap").start()


if __name__ == "__main__":
    assert _matches_hotkey(kCGEventFlagMaskControl | kCGEventFlagMaskAlternate) is True
    assert _matches_hotkey(kCGEventFlagMaskControl) is False
    assert _matches_hotkey(kCGEventFlagMaskAlternate) is False
    assert _matches_hotkey(kCGEventFlagMaskControl | kCGEventFlagMaskAlternate
                            | kCGEventFlagMaskCommand) is False
    assert _matches_hotkey(kCGEventFlagMaskControl | kCGEventFlagMaskAlternate
                            | kCGEventFlagMaskShift) is False
    CUSTOM_DICTIONARY[:] = [("teh", "the"), ("jarvis", "Jarvis")]
    assert apply_dictionary("teh quick jarvis") == "the quick Jarvis"
    assert apply_dictionary("something else") == "something else"
    CUSTOM_DICTIONARY.clear()
    tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
                            kCGEventTapOptionListenOnly,
                            CGEventMaskBit(kCGEventFlagsChanged), lambda p, t, e, r: e, None)
    print("event tap creation (Accessibility granted):", "PASS" if tap else
          "FAIL — grant Accessibility to this Python in System Settings")
    print("DICTATION SELFTEST PASS")

